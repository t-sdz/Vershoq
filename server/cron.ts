// Cron Snap'It — envoie les ALERTES AUTOMATIQUES du groupe de façon
// SIMULTANÉE à tout le monde, via FCM (Firebase Cloud Messaging).
//
// ┌─ Installation sur Val Town ───────────────────────────────────────────────┐
// │ 1. Val Town → bouton « New » → choisis « Cron »                            │
// │ 2. Efface le contenu par défaut et colle TOUT ce fichier                   │
// │ 3. Règle la fréquence sur « chaque minute »  (cron : * * * * *)            │
// │ 4. La variable d'environnement FIREBASE_SA (déjà réglée au niveau du       │
// │    compte pour le serveur push) est réutilisée ici — rien à ajouter.       │
// └────────────────────────────────────────────────────────────────────────────┘
//
// Comment ça marche :
//  - chaque minute, le cron lit tes groupes dans Firestore ;
//  - pour chaque groupe, il calcule les horaires d'alerte du jour (aléatoires
//    mais DÉTERMINISTES : mêmes horaires à chaque exécution) ;
//  - si l'heure locale (Europe/Paris) correspond à un horaire, il envoie UN
//    push au sujet « group_<id> » → tous les téléphones abonnés le reçoivent
//    en même temps. Chaque téléphone calcule ensuite SES propres prénoms à
//    partir de la graine envoyée (appariement réciproque).

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

async function sendPush(
  token: string,
  project: string,
  groupId: string,
  seed: number,
) {
  const message = {
    message: {
      topic: `group_${groupId}`,
      notification: {
        title: "📸 Snap'It",
        body: "C'est le moment ! Prends ta photo avec le groupe.",
      },
      data: { seed: String(seed), groupId: String(groupId) },
      android: {
        priority: "HIGH",
        notification: { channel_id: "vershoq_shots", sound: "default" },
      },
      apns: { payload: { aps: { sound: "default" } } },
    },
  };
  await fetch(
    `https://fcm.googleapis.com/v1/projects/${project}/messages:send`,
    {
      method: "POST",
      headers: {
        Authorization: `Bearer ${token}`,
        "Content-Type": "application/json",
      },
      body: JSON.stringify(message),
    },
  );
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
      if (times[i] !== nowMin) continue;
      const key = `${dateStr}|${id}|${i}`;
      if (sent[key]) continue;
      sent[key] = true;
      const seed = stableHash(`${id}|${dateStr}|${i}`);
      try {
        await sendPush(token, project, id!, seed);
      } catch (_) { /* on réessaiera à la prochaine minute si non marqué */ }
    }
  }

  await blob.setJSON("snapit_sent", sent);
}
