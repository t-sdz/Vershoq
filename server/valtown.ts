// Serveur de notifications push Snap'It — version Val Town (val.town).
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

async function getAccessToken(sa: any): Promise<string> {
  const now = Math.floor(Date.now() / 1000);
  const header = { alg: "RS256", typ: "JWT" };
  const claim = {
    iss: sa.client_email,
    scope: "https://www.googleapis.com/auth/firebase.messaging",
    aud: "https://oauth2.googleapis.com/token",
    iat: now,
    exp: now + 3600,
  };
  const unsigned = `${b64url(JSON.stringify(header))}.${b64url(JSON.stringify(claim))}`;
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

export default async function (req: Request): Promise<Response> {
  const SA = JSON.parse(Deno.env.get("FIREBASE_SA") || "{}");
  const SECRET = Deno.env.get("PUSH_SECRET") || "";

  if (req.method === "GET") return new Response("Snap'It push server OK");
  if (req.method !== "POST") return new Response("POST only", { status: 405 });

  let body: Record<string, unknown>;
  try {
    body = await req.json();
  } catch {
    return new Response("bad json", { status: 400 });
  }
  if (!SECRET || body.secret !== SECRET) {
    return new Response("unauthorized", { status: 401 });
  }
  if (!body.groupId) return new Response("groupId required", { status: 400 });

  try {
    const token = await getAccessToken(SA);
    const message = {
      message: {
        topic: `group_${body.groupId}`,
        notification: {
          title: (body.title as string) || "📸 Snap'It",
          body: (body.body as string) ||
            "C'est le moment ! Prends ta photo avec le groupe.",
        },
        data: {
          label: String(body.label || ""),
          groupId: String(body.groupId),
        },
        android: {
          priority: "HIGH",
          notification: { channel_id: "vershoq_shots", sound: "default" },
        },
        apns: { payload: { aps: { sound: "default" } } },
      },
    };
    const r = await fetch(
      `https://fcm.googleapis.com/v1/projects/${SA.project_id}/messages:send`,
      {
        method: "POST",
        headers: {
          Authorization: `Bearer ${token}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify(message),
      },
    );
    return new Response(await r.text(), { status: r.status });
  } catch (e) {
    return new Response("error: " + e, { status: 500 });
  }
}
