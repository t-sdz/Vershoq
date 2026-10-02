// Cron Snap'It — envoie les ALERTES AUTOMATIQUES du groupe via FCM (Firebase
// Cloud Messaging), UN message PAR MEMBRE avec SES prénoms dans le texte.
//
// ┌─ Installation sur Val Town ───────────────────────────────────────────────┐
// │ 1. Val Town → « New » → crée un Cron val, colle TOUT ce fichier.           │
// │ 2. Règle le calendrier sur toutes les 15 min (minimum du plan gratuit).    │
// │ 3. Dans « Env vars » du val, ajoute FIREBASE_SA = ta clé de service        │
// │    Firebase (le JSON complet). C'est la seule variable nécessaire.         │
// └────────────────────────────────────────────────────────────────────────────┘
//
// Comment ça marche :
//  - à chaque passage (~15 min), le cron lit tes groupes dans Firestore ;
//  - pour chaque groupe, il calcule les horaires d'alerte du jour (aléatoires
//    mais DÉTERMINISTES : mêmes horaires à chaque exécution) ;
//  - pour toute alerte devenue due depuis le dernier passage, il lit les
//    membres du groupe, calcule LUI-MÊME la répartition (qui pose avec qui,
//    réciproque) et envoie à chaque membre un push sur son sujet personnel
//    « u_<sha256(email)> » contenant ses prénoms → visibles dès la toute
//    première notification, même app fermée ;
//  - le compte à rebours est celui défini par l'admin (strict, non borné) ;
//  - le marqueur « sent » (Blob) évite tout doublon.
//
// NB : le code de répartition / sujet / message est DUPLIQUÉ dans valtown.ts
// (les deux vals sont déployés séparément) : toute modif doit être faite aux
// deux endroits ET rester identique au contrat de l'app.

import { blob } from "https://esm.town/v/std/blob";

const TIMEZONE = "Europe/Paris"; // fuseau horaire des membres

// ── Crypto : signe un JWT et échange contre un jeton d'accès ──────────────────
function pemToArrayBuffer(pem: string): ArrayBuffer {
  const b64 = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, "")
    .replace(/-----END PRIVATE KEY-----/, "")
    .replace(/\s+/g, "");
  const bin = atob(b64);
  const buf = new Uint8Array(bin.length);
  for (let i = 0; i < bin.length; i++) buf[i] = bin.charCodeAt(i);
  return buf.buffer;
}

function b64url(data: ArrayBuffer | string): string {
  let bin: string;
  if (typeof data === "string") {
    bin = data;
  } else {
    const b = new Uint8Array(data);
    bin = "";
    for (let i = 0; i < b.length; i++) bin += String.fromCharCode(b[i]);
  }
  return btoa(bin).replace(/\+/g, "-").replace(/\//g, "_").replace(/=+$/, "");
}

async function getAccessToken(sa: any, scope: string): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claim = {
    iss: sa.client_email,
    scope,
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${b64url(JSON.stringify(header))}.${
    b64url(JSON.stringify(claim))
  }`;
  const key = await crypto.subtle.importKey(
    "pkcs8",
    pemToArrayBuffer(sa.private_key),
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"],
  );
  const sig = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(unsigned),
  );
  const jwt = `${unsigned}.${b64url(sig)}`;
  const res = await fetch("https://oauth2.googleapis.com/token", {
    method: "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body:
      `grant_type=urn:ietf:params:oauth:grant-type:jwt-bearer&assertion=${jwt}`,
  });
  const j = await res.json();
  if (!j.access_token) throw new Error("token error: " + JSON.stringify(j));
  return j.access_token;
}

// ── Heure locale (Paris) ──────────────────────────────────────────────────────
function nowLocal(): { dateStr: string; minutes: number } {
  const fmt = new Intl.DateTimeFormat("en-CA", {
    timeZone: TIMEZONE,
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
  });
  const parts = fmt.formatToParts(new Date());
  const get = (t: string) => parts.find((p) => p.type === t)!.value;
  const hour = parseInt(get("hour"));
  const minute = parseInt(get("minute"));
  return {
    dateStr: `${get("year")}-${get("month")}-${get("day")}`,
    minutes: hour * 60 + minute,
  };
}

// ── Firestore REST : parse les valeurs typées ────────────────────────────────
function parseValue(v: any): any {
  if (v == null) return null;
  if ("stringValue" in v) return v.stringValue;
  if ("integerValue" in v) return parseInt(v.integerValue);
  if ("doubleValue" in v) return v.doubleValue;
  if ("booleanValue" in v) return v.booleanValue;
  if ("mapValue" in v) return parseFields(v.mapValue.fields);
  if ("arrayValue" in v) return (v.arrayValue.values || []).map(parseValue);
  return null;
}
function parseFields(fields: any): Record<string, any> {
  const out: Record<string, any> = {};
  for (const [k, v] of Object.entries(fields || {})) out[k] = parseValue(v);
  return out;
}

// ── PRNG déterministe + hash stable ───────────────────────────────────────────
function mulberry32(seed: number) {
  let a = seed >>> 0;
  return function () {
    a |= 0;
    a = (a + 0x6D2B79F5) | 0;
    let t = Math.imul(a ^ (a >>> 15), 1 | a);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}

function stableHash(s: string): number {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) & 0x7fffffff;
  return h;
}

// ── Sujet FCM personnel d'un membre ───────────────────────────────────────────
// « u_ » + 40 premiers caractères hexa du SHA-256 de l'email normalisé.
// DOIT être identique au calcul fait dans l'app (abonnement au sujet).
async function memberTopic(email: string): Promise<string> {
  const data = new TextEncoder().encode(email.trim().toLowerCase());
  const digest = await crypto.subtle.digest("SHA-256", data);
  const hex = Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
  return "u_" + hex.slice(0, 40);
}

// ── Répartition des membres pour une alerte (source de vérité unique) ────────
type PoolEntry = { email: string; username: string };

// Entier depuis la config (comme _cfgInt côté app : nombre sinon défaut).
function cfgInt(v: unknown, fallback: number): number {
  return typeof v === "number" && Number.isFinite(v) ? Math.trunc(v) : fallback;
}

function clamp(v: number, lo: number, hi: number): number {
  return Math.min(Math.max(v, lo), hi);
}

// « A », « A et B », « A, B et C ».
function joinNames(names: string[]): string {
  if (names.length === 0) return "";
  if (names.length === 1) return names[0];
  return `${names.slice(0, -1).join(", ")} et ${names[names.length - 1]}`;
}

// Liste des participants : membres (email normalisé) + prénoms en plus de
// l'admin, dédoublonnés contre les pseudos des membres.
function buildPool(
  members: Array<Record<string, any>>,
  cfg: Record<string, any>,
): PoolEntry[] {
  const pool: PoolEntry[] = [];
  for (const m of members) {
    const email = String(m.email ?? "").trim().toLowerCase();
    if (!email) continue;
    pool.push({ email, username: String(m.username ?? "") });
  }
  const seen = new Set(pool.map((p) => p.username.trim().toLowerCase()));
  const extras = Array.isArray(cfg.extraNames) ? cfg.extraNames : [];
  for (const n of extras) {
    const name = String(n ?? "").trim();
    const key = name.toLowerCase();
    if (!key || seen.has(key)) continue;
    pool.push({ username: name, email: "extra:" + key });
    seen.add(key);
  }
  return pool;
}

// Calcule, pour chaque VRAI membre, les prénoms avec qui il doit poser.
// Déterministe (graine = alertId) et réciproque : si A voit B, B voit A.
// Renvoie une liste {email, names} (les « extra: » n'ont pas de téléphone).
function computePartition(
  members: Array<Record<string, any>>,
  cfg: Record<string, any>,
  alertId: string,
): Array<{ email: string; names: string }> {
  const pool = buildPool(members, cfg);
  if (pool.length < 2) return [];
  pool.sort((a, b) => (a.email < b.email ? -1 : a.email > b.email ? 1 : 0));

  const rng = mulberry32(stableHash(alertId));
  const total = pool.length;
  const minN = cfgInt(cfg.minNames, 1);
  const maxN = cfgInt(cfg.maxNames, 3);
  const loS = clamp(minN + 1, 2, total);
  const hiS = clamp(maxN + 1, loS, total);
  const cap = loS + Math.floor(rng() * (hiS - loS + 1));

  // Mélange de Fisher–Yates avec le même générateur.
  for (let i = pool.length - 1; i >= 1; i--) {
    const j = Math.floor(rng() * (i + 1));
    [pool[i], pool[j]] = [pool[j], pool[i]];
  }

  // Groupes d'au plus `cap`, aussi égaux que possible, jamais de personne seule.
  let numGroups = Math.ceil(total / cap);
  const maxGroups = Math.floor(total / 2);
  if (maxGroups >= 1 && numGroups > maxGroups) numGroups = maxGroups;
  if (numGroups < 1) numGroups = 1;
  const base = Math.floor(total / numGroups);
  const extra = total % numGroups; // les `extra` premiers groupes ont +1

  const out: Array<{ email: string; names: string }> = [];
  let acc = 0;
  for (let g = 0; g < numGroups; g++) {
    const size = base + (g < extra ? 1 : 0);
    const slice = pool.slice(acc, acc + size);
    acc += size;
    for (const p of slice) {
      if (p.email.startsWith("extra:")) continue;
      const names = joinNames(
        slice.filter((o) => o !== p).map((o) => o.username),
      );
      if (names) out.push({ email: p.email, names });
    }
  }
  return out;
}

// ── Message FCM personnel ─────────────────────────────────────────────────────
// Compte à rebours strict défini par l'admin (0 = pas de compte à rebours).
function countdownOf(cfg: Record<string, any>): number {
  if (cfg.countdownEnabled !== true) return 0;
  // Pas de durée enregistrée : 2 min par défaut (comme l'app).
  const raw = cfg.countdownSeconds;
  const s = raw === undefined || raw === null ? 120 : Number(raw);
  return s > 0 ? Math.floor(s) : 0;
}

function fmtDuration(s: number): string {
  if (s < 60) return `${s} s`;
  const m = Math.floor(s / 60);
  const r = s % 60;
  return r === 0 ? `${m} min` : `${m} min ${r} s`;
}

function buildMemberMessage(
  topic: string,
  alertId: string,
  groupId: string,
  names: string,
  sentAtMs: number,
  cd: number,
) {
  const body = cd > 0
    ? `C'est parti ! Tu as ${fmtDuration(cd)} pour prendre ta photo avec ${names}.`
    : `C'est le moment ! Prends ta photo avec ${names}.`;
  return {
    message: {
      topic,
      notification: { title: "📸 Snap'It", body },
      data: {
        type: "alert",
        alertId,
        groupId,
        names,
        sentAt: String(sentAtMs),
        cd: String(cd),
      },
      android: {
        priority: "HIGH",
        ttl: cd > 0 ? `${cd + 120}s` : "21600s",
        notification: {
          channel_id: "vershoq_shots",
          sound: "default",
          tag: `snap_${groupId}`, // remplace la notif précédente du groupe
        },
      },
      apns: { payload: { aps: { sound: "default" } } },
    },
  };
}

// Mémorise l'alerte dans le document du groupe (champ « lastAlert ») :
// l'app la relit à l'ouverture, même si la notif n'a pas pu être traitée en
// arrière-plan (Xiaomi…). Clé des prénoms = sujet personnel du membre.
async function recordLastAlert(
  token: string,
  project: string,
  groupId: string,
  alertId: string,
  sentAtMs: number,
  cd: number,
  parts: Array<{ email: string; names: string }>,
): Promise<void> {
  const names: Record<string, unknown> = {};
  for (const { email, names: n } of parts) {
    names[await memberTopic(email)] = { stringValue: n };
  }
  const r = await fetch(
    `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/groups/${
      encodeURIComponent(groupId)
    }?updateMask.fieldPaths=lastAlert&currentDocument.exists=true`,
    {
      method: "PATCH",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify({
        fields: {
          lastAlert: {
            mapValue: {
              fields: {
                id: { stringValue: alertId },
                sentAt: { integerValue: String(sentAtMs) },
                cd: { integerValue: String(cd) },
                names: { mapValue: { fields: names } },
              },
            },
          },
        },
      }),
    },
  );
  if (!r.ok) throw new Error(`lastAlert ${r.status}: ${await r.text()}`);
}

// Alerte encore « en cours » : son compte à rebours n'est pas fini.
// Renvoie les secondes restantes (0 = on peut envoyer). Sans compte à
// rebours, rien ne bloque : la nouvelle alerte remplace l'ancienne.
function busySeconds(lastAlert: any, nowMs: number): number {
  if (!lastAlert || typeof lastAlert !== "object") return 0;
  const sentAt = Number(lastAlert.sentAt);
  const cd = Number(lastAlert.cd);
  if (!Number.isFinite(sentAt) || !Number.isFinite(cd) || cd <= 0) return 0;
  const left = sentAt + cd * 1000 - nowMs;
  return left > 0 ? Math.ceil(left / 1000) : 0;
}

// Envoie l'alerte à chaque membre sur SON sujet, avec SES prénoms.
// Renvoie le nombre de messages acceptés par FCM. Une erreur sur un membre
// est journalisée mais n'empêche pas l'envoi aux autres.
async function sendAlert(
  token: string,
  project: string,
  groupId: string,
  alertId: string,
  members: Array<Record<string, any>>,
  cfg: Record<string, any>,
): Promise<number> {
  const parts = computePartition(members, cfg, alertId);
  const cd = countdownOf(cfg);
  const sentAtMs = Date.now(); // même horodatage pour tous les membres
  if (parts.length === 0) return 0;
  try {
    await recordLastAlert(token, project, groupId, alertId, sentAtMs, cd, parts);
  } catch (e) {
    console.error(`lastAlert en échec (${alertId}) :`, e);
  }
  let ok = 0;
  for (const { email, names } of parts) {
    try {
      const msg = buildMemberMessage(
        await memberTopic(email),
        alertId,
        groupId,
        names,
        sentAtMs,
        cd,
      );
      const r = await fetch(
        `https://fcm.googleapis.com/v1/projects/${project}/messages:send`,
        {
          method: "POST",
          headers: {
            Authorization: `Bearer ${token}`,
            "Content-Type": "application/json",
          },
          body: JSON.stringify(msg),
        },
      );
      if (r.ok) {
        ok++;
      } else {
        console.error(
          `FCM ${r.status} pour ${email} (${alertId}) : ${await r.text()}`,
        );
      }
    } catch (e) {
      console.error(`FCM erreur pour ${email} (${alertId}) :`, e);
    }
  }
  return ok;
}

// ── Firestore REST : membres d'un groupe ──────────────────────────────────────
async function fetchMembers(
  token: string,
  project: string,
  groupId: string,
): Promise<Array<Record<string, any>>> {
  const r = await fetch(
    `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/groups/${
      encodeURIComponent(groupId)
    }/members?pageSize=300`,
    { headers: { Authorization: `Bearer ${token}` } },
  );
  if (!r.ok) throw new Error(`members ${r.status}: ${await r.text()}`);
  const j = await r.json();
  return (j.documents || []).map((d: any) => parseFields(d.fields));
}

export default async function () {
  const SA = JSON.parse(Deno.env.get("FIREBASE_SA") || "{}");
  const project = SA.project_id;
  const token = await getAccessToken(
    SA,
    "https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/firebase.messaging",
  );

  // 1. Tous les groupes
  const res = await fetch(
    `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/groups?pageSize=300`,
    { headers: { Authorization: `Bearer ${token}` } },
  );
  const j = await res.json();
  const docs = j.documents || [];

  const { dateStr, minutes: nowMin } = nowLocal();

  // Anti-doublon : on retient les alertes déjà envoyées aujourd'hui.
  const sent: Record<string, boolean> =
    (await blob.getJSON("snapit_sent")) || {};
  for (const k of Object.keys(sent)) {
    if (!k.startsWith(dateStr)) delete sent[k]; // purge des jours passés
  }

  for (const doc of docs) {
    const id = String(doc.name).split("/").pop();
    const f = parseFields(doc.fields);
    const cfg = f.notifConfig || {};
    let lastAlert = f.lastAlert;
    if (cfg.enabled === false) continue;

    const timeLimit = cfg.timeLimit !== false;
    const startHour = timeLimit ? (cfg.startHour ?? 9) : 0;
    const endHour = timeLimit ? (cfg.endHour ?? 21) : 23;
    const minCount = cfg.minCount ?? 2;
    const maxCount = cfg.maxCount ?? 5;

    const total = (endHour - startHour) * 60 + 59;
    if (total <= 0) continue;

    // Horaires du jour (déterministes par groupe + date).
    const rng = mulberry32(stableHash(`${id}|${dateStr}`));
    const range = Math.abs(maxCount - minCount);
    const count = minCount + (range === 0 ? 0 : Math.floor(rng() * (range + 1)));
    const times: number[] = [];
    for (let i = 0; i < count; i++) {
      times.push(startHour * 60 + Math.floor(rng() * total));
    }
    times.sort((a, b) => a - b);

    for (let i = 0; i < times.length; i++) {
      // Le cron tourne toutes les ~15 min (plan gratuit Val Town). On déclenche
      // toute alerte devenue due depuis le dernier passage (fenêtre glissante de
      // 20 min) ; le marqueur `sent` évite les doublons. L'alerte part donc au
      // plus tard ~15 min après son horaire aléatoire — mais à tout le monde en
      // même temps, et sans accumulation.
      if (!(times[i] <= nowMin && times[i] > nowMin - 20)) continue;
      const key = `${dateStr}|${id}|${i}`;
      if (sent[key]) continue;
      // Une alerte est encore en cours (compte à rebours pas fini) : on
      // n'envoie pas ; on réessaiera au prochain passage si l'horaire est
      // encore dans la fenêtre.
      const busy = busySeconds(lastAlert, Date.now());
      if (busy > 0) {
        console.log(`Alerte ${key} reportée : une alerte est en cours (${busy} s)`);
        continue;
      }
      sent[key] = true; // marqué d'office : jamais de double envoi
      const alertId = `${id}_${dateStr}_${i}`;
      try {
        const members = await fetchMembers(token, project, id!);
        const n = await sendAlert(token, project, id!, alertId, members, cfg);
        if (n > 0) lastAlert = { sentAt: Date.now(), cd: countdownOf(cfg) };
        console.log(`Alerte ${alertId} : ${n} message(s) envoyé(s)`);
      } catch (e) {
        console.error(`Alerte ${alertId} en échec :`, e);
      }
    }
  }

  await blob.setJSON("snapit_sent", sent);
}
