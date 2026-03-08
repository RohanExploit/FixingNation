/**
 * auth.js
 *
 * Obtains a short-lived Google OAuth 2.0 access token from a Firebase
 * service account private key using only the Web Crypto API (SubtleCrypto).
 *
 * This is necessary because Cloudflare Workers run in a V8 isolate — the
 * Node.js `crypto` module and the `firebase-admin` SDK are NOT available.
 * All cryptographic work uses the standard Web Crypto API instead.
 *
 * Flow:
 *   1. Parse the service account JSON stored as an env secret.
 *   2. Build a signed RS256 JWT (the "assertion").
 *   3. POST the assertion to Google's token endpoint.
 *   4. Return the short-lived access_token (valid for 1 hour).
 *
 * The access token is used to authenticate Firestore REST API calls.
 * Workers are stateless per-request so a fresh token is fetched each time.
 * For a production optimisation, cache the token in Cloudflare KV with a TTL.
 */

const TOKEN_ENDPOINT = "https://oauth2.googleapis.com/token";
const DATASTORE_SCOPE = "https://www.googleapis.com/auth/datastore";

// ---------------------------------------------------------------------------
// Internal helpers
// ---------------------------------------------------------------------------

/** Encode an ArrayBuffer or Uint8Array as URL-safe Base64 (no padding). */
function base64url(buffer) {
  const bytes = buffer instanceof Uint8Array ? buffer : new Uint8Array(buffer);
  let binary = "";
  for (const b of bytes) binary += String.fromCharCode(b);
  return btoa(binary).replace(/\+/g, "-").replace(/\//g, "_").replace(/=/g, "");
}

/** Encode a plain object as URL-safe Base64 JSON. */
function encodeJsonPart(obj) {
  return base64url(new TextEncoder().encode(JSON.stringify(obj)));
}

/**
 * Import an RSA private key from a PKCS#8 PEM string.
 * The key material is decoded from Base64 and imported as a CryptoKey.
 */
async function importPrivateKey(pemString) {
  const body = pemString
    .replace(/-----BEGIN PRIVATE KEY-----/g, "")
    .replace(/-----END PRIVATE KEY-----/g, "")
    .replace(/\s+/g, "");

  const der = Uint8Array.from(atob(body), (c) => c.charCodeAt(0));

  return crypto.subtle.importKey(
    "pkcs8",
    der,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["sign"]
  );
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * Build and sign a JWT assertion then exchange it for an access token.
 *
 * @param {string | object} serviceAccount
 *   The Firebase service account JSON — either already parsed or as a string.
 * @returns {Promise<string>} A Google OAuth 2.0 access token.
 */
export async function getFirebaseAccessToken(serviceAccount) {
  const sa =
    typeof serviceAccount === "string"
      ? JSON.parse(serviceAccount)
      : serviceAccount;

  const now = Math.floor(Date.now() / 1000);

  const header  = encodeJsonPart({ alg: "RS256", typ: "JWT" });
  const payload = encodeJsonPart({
    iss:   sa.client_email,
    sub:   sa.client_email,
    aud:   TOKEN_ENDPOINT,
    scope: DATASTORE_SCOPE,
    iat:   now,
    exp:   now + 3600,
  });

  const signingInput = `${header}.${payload}`;
  const key = await importPrivateKey(sa.private_key);

  const signature = await crypto.subtle.sign(
    "RSASSA-PKCS1-v1_5",
    key,
    new TextEncoder().encode(signingInput)
  );

  const jwt = `${signingInput}.${base64url(signature)}`;

  const response = await fetch(TOKEN_ENDPOINT, {
    method:  "POST",
    headers: { "Content-Type": "application/x-www-form-urlencoded" },
    body:    new URLSearchParams({
      grant_type: "urn:ietf:params:oauth:grant-type:jwt-bearer",
      assertion:  jwt,
    }),
  });

  if (!response.ok) {
    const detail = await response.text();
    throw new Error(`Token exchange failed (${response.status}): ${detail}`);
  }

  const { access_token } = await response.json();
  return access_token;
}
