// Serveur de notifications push Snap'It — version Val Town (val.town).
// Sert au bouton admin « Envoyer maintenant » : envoie une alerte immédiate
// à tout le groupe, UN message PAR MEMBRE (sujet « u_<sha256(email)> ») avec
// SES prénoms dans le texte de la notification.
//
// Comment l'utiliser :
//  1. Va sur https://www.val.town → crée un compte (gratuit)
//  2. Bouton « New » → « HTTP val »
//  3. Efface le contenu par défaut et colle TOUT ce fichier
//  4. En bas à gauche → « Environment Variables » → ajoute :
//        FIREBASE_SA = tout le JSON de la clé de service Firebase
//        PUSH_SECRET = un mot de passe (le MÊME que dans lib/config.dart)
//  5. Le val a une URL du type https://<user>-<valname>.web.val.run
//     → c'est ta pushServerUrl.
//
// Requête : POST {secret, groupId} (les anciens champs seed/label/title/body
// sont ignorés). Réponse : {ok:true, sent, total} si au moins un message est
// parti ; sinon {ok:false, error, sent, total, errors} (HTTP 502) ; 409 si
// une alerte est encore en cours.
//
// NB : le code de répartition / sujet / message est DUPLIQUÉ depuis cron.ts
// (les deux vals sont déployés séparément) : toute modif doit être faite aux
// deux endroits ET rester identique au contrat de l'app.

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
          tag: alertId, // une notif distincte (avec son) par alerte
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

// Résultat d'un envoi : messages acceptés par FCM / membres visés / erreurs.
type SendReport = { sent: number; total: number; errors: string[] };

// Envoie l'alerte à chaque membre sur SON sujet, avec SES prénoms.
// Une erreur sur un membre est journalisée (et renvoyée dans le rapport)
// mais n'empêche pas l'envoi aux autres.
async function sendAlert(
  token: string,
  project: string,
  groupId: string,
  alertId: string,
  members: Array<Record<string, any>>,
  cfg: Record<string, any>,
): Promise<SendReport> {
  const parts = computePartition(members, cfg, alertId);
  const cd = countdownOf(cfg);
  const sentAtMs = Date.now(); // même horodatage pour tous les membres
  const errors: string[] = [];
  if (parts.length === 0) return { sent: 0, total: 0, errors };
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
        const txt = await r.text();
        console.error(`FCM ${r.status} pour ${email} (${alertId}) : ${txt}`);
        errors.push(`FCM ${r.status} : ${txt.slice(0, 200)}`);
      }
    } catch (e) {
      console.error(`FCM erreur pour ${email} (${alertId}) :`, e);
      errors.push(`FCM erreur : ${String(e).slice(0, 200)}`);
    }
  }
  return { sent: ok, total: parts.length, errors };
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

const SCOPES =
  "https://www.googleapis.com/auth/datastore https://www.googleapis.com/auth/firebase.messaging";

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

export default async function (req: Request): Promise<Response> {
  const SA = JSON.parse(Deno.env.get("FIREBASE_SA") || "{}");
  const SECRET = Deno.env.get("PUSH_SECRET") || "";

  if (req.method === "GET") return new Response("Snap'It push server OK");
  if (req.method !== "POST") {
    return json({ ok: false, error: "POST only" }, 405);
  }

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return json({ ok: false, error: "bad json" }, 400);
  }
  if (!SECRET || body.secret !== SECRET) {
    return json({ ok: false, error: "unauthorized" }, 401);
  }
  const groupId = String(body.groupId ?? "").trim();
  if (!groupId) return json({ ok: false, error: "groupId required" }, 400);

  try {
    const project = SA.project_id;
    const token = await getAccessToken(SA, SCOPES);

    // Document du groupe → notifConfig (prénoms min/max, extras, compte à rebours).
    const g = await fetch(
      `https://firestore.googleapis.com/v1/projects/${project}/databases/(default)/documents/groups/${
        encodeURIComponent(groupId)
      }`,
      { headers: { Authorization: `Bearer ${token}` } },
    );
    if (g.status === 404) {
      return json({ ok: false, error: "group not found" }, 404);
    }
    if (!g.ok) throw new Error(`group ${g.status}: ${await g.text()}`);
    const gf = parseFields((await g.json()).fields);
    const cfg = gf.notifConfig || {};

    // Une alerte est encore en cours (compte à rebours pas fini) : refus.
    const busy = busySeconds(gf.lastAlert, Date.now());
    if (busy > 0) {
      return json({ ok: false, error: "busy", remaining: busy }, 409);
    }

    const members = await fetchMembers(token, project, groupId);
    const alertId = `${groupId}_m_${Date.now()}`;
    const rep = await sendAlert(token, project, groupId, alertId, members, cfg);
    if (rep.total === 0) {
      return json({ ok: false, error: "no members", ...rep }, 422);
    }
    if (rep.sent === 0) {
      return json({ ok: false, error: "fcm", ...rep }, 502);
    }
    return json({ ok: true, ...rep });
  } catch (e) {
    return json({ ok: false, error: String(e) }, 500);
  }
}
