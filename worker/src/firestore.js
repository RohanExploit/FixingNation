/**
 * firestore.js
 *
 * Minimal Firestore REST API client for Cloudflare Workers.
 *
 * The firebase-admin SDK requires Node.js APIs that are unavailable in the
 * Workers V8 isolate runtime. Instead we use the documented Firestore REST
 * API authenticated with the service account access token from auth.js.
 *
 * Only the operations needed by this Worker are implemented:
 *   - patchDocument — PATCH (merge-update) specific fields of one document.
 *
 * Firestore REST API reference:
 *   https://firebase.google.com/docs/firestore/reference/rest
 */

const FIRESTORE_BASE =
  "https://firestore.googleapis.com/v1/projects/{projectId}/databases/(default)/documents";

// ---------------------------------------------------------------------------
// Value serialiser
// ---------------------------------------------------------------------------

/**
 * Convert a plain JavaScript value into a Firestore REST "Value" object.
 *
 * Supported types: null, boolean, integer, double, string, Date/ISO-string
 * (stored as timestamp), plain arrays, plain objects (stored as map).
 */
function toValue(value) {
  if (value === null || value === undefined) {
    return { nullValue: null };
  }
  if (typeof value === "boolean") {
    return { booleanValue: value };
  }
  if (typeof value === "number") {
    return Number.isInteger(value)
      ? { integerValue: String(value) }
      : { doubleValue: value };
  }
  if (typeof value === "string") {
    // Detect ISO-8601 date strings and store as Firestore timestamps.
    if (/^\d{4}-\d{2}-\d{2}T/.test(value)) {
      return { timestampValue: value };
    }
    return { stringValue: value };
  }
  if (value instanceof Date) {
    return { timestampValue: value.toISOString() };
  }
  if (Array.isArray(value)) {
    return { arrayValue: { values: value.map(toValue) } };
  }
  if (typeof value === "object") {
    const fields = {};
    for (const [k, v] of Object.entries(value)) {
      fields[k] = toValue(v);
    }
    return { mapValue: { fields } };
  }
  return { stringValue: String(value) };
}

/** Wrap a flat JS object as a Firestore document `{ fields: { ... } }`. */
function toDocument(obj) {
  const fields = {};
  for (const [k, v] of Object.entries(obj)) {
    fields[k] = toValue(v);
  }
  return { fields };
}

// ---------------------------------------------------------------------------
// Public API
// ---------------------------------------------------------------------------

/**
 * POST a new document to a Firestore collection (auto-generated ID).
 *
 * @param {string} projectId
 * @param {string} accessToken
 * @param {string} collection   e.g. "posts"
 * @param {object} data         Plain JS object — all fields written.
 * @returns {Promise<string>}   The new document ID.
 */
export async function createDocument(projectId, accessToken, collection, data) {
  const base = FIRESTORE_BASE.replace("{projectId}", projectId);
  const url  = `${base}/${collection}`;

  const response = await fetch(url, {
    method:  "POST",
    headers: {
      Authorization:  `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(toDocument(data)),
  });

  if (!response.ok) {
    const detail = await response.text();
    throw new Error(
      `Firestore POST ${collection} failed (${response.status}): ${detail}`
    );
  }

  const result = await response.json();
  // name format: projects/{proj}/databases/(default)/documents/{collection}/{id}
  return (result.name || "").split("/").pop();
}

/**
 * PATCH (merge-update) specific fields of a Firestore document.
 *
 * Only the keys present in `data` are updated; all other fields on the
 * document are left untouched. This mirrors Firestore's `set(..., {merge:true})`.
 *
 * For nested objects (e.g. `moderation`), the entire sub-object is replaced
 * as one atomic field — individual sub-keys are not individually masked.
 *
 * @param {string} projectId      Firebase project ID.
 * @param {string} accessToken    Google OAuth 2.0 access token.
 * @param {string} collection     Firestore collection path, e.g. "posts".
 * @param {string} documentId     Document ID within the collection.
 * @param {object} data           Plain JS object of fields to update.
 * @returns {Promise<object>}     The updated Firestore document representation.
 */
export async function patchDocument(projectId, accessToken, collection, documentId, data) {
  // The Firestore REST PATCH endpoint accepts repeated `updateMask.fieldPaths`
  // query parameters — one per top-level field being updated.
  const maskParams = Object.keys(data)
    .map((k) => `updateMask.fieldPaths=${encodeURIComponent(k)}`)
    .join("&");

  const base = FIRESTORE_BASE.replace("{projectId}", projectId);
  const url  = `${base}/${collection}/${documentId}?${maskParams}`;

  const response = await fetch(url, {
    method:  "PATCH",
    headers: {
      Authorization:  `Bearer ${accessToken}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify(toDocument(data)),
  });

  if (!response.ok) {
    const detail = await response.text();
    throw new Error(
      `Firestore PATCH ${collection}/${documentId} failed (${response.status}): ${detail}`
    );
  }

  return response.json();
}
