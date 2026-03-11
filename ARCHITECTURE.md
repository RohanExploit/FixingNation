# FixingNation — Production Architecture

> Last updated to reflect the no-Blaze infrastructure redesign.
> Firebase Cloud Functions have been replaced by a Cloudflare Worker.

---

## 1) System Topology

```
┌──────────────────────────────────────────────────────────────────┐
│                           CLIENTS                                │
│                                                                  │
│  Flutter Android App          Flutter Web PWA (Firebase Hosting) │
│  ─ Firebase Auth (identity)                                      │
│  ─ Firestore (read feed, write raw post)                         │
│  ─ Firebase Storage (upload compressed images)                   │
│  ─ After post write → call Worker /classify                      │
└──────────────────────┬───────────────────────────────────────────┘
                       │ HTTPS
        ┌──────────────┼───────────────────┐
        │              │                   │
        ▼              ▼                   ▼
┌─────────────┐  ┌──────────────┐  ┌──────────────────────┐
│ Firebase    │  │  Firestore   │  │  Firebase Storage    │
│ Auth        │  │  (Spark)     │  │  (Spark, 1 GB)       │
│ (Spark)     │  │              │  │  max 2 MB/image      │
└─────────────┘  └──────┬───────┘  └──────────────────────┘
                        │ ▲
                        │ │ PATCH via REST API
                        │ │ (service account — bypasses rules)
                        ▼ │
              ┌───────────────────────────┐
              │   Cloudflare Worker       │
              │   (free, edge, ~0ms cold) │
              │                           │
              │  POST /classify           │
              │  ── validate shared secret│
              │  ── call Gemini Flash 2.0 │
              │  ── fallback: deterministic│
              │  ── compute severity      │
              │  ── compute rankingScore  │
              │  ── route authority       │
              │  ── PATCH Firestore doc   │
              │                           │
              │  Secrets (Worker env):    │
              │  API_SHARED_SECRET        │
              │  GEMINI_API_KEY           │
              │  FIREBASE_SERVICE_ACCOUNT │
              └───────────────────────────┘
                          │
                          ▼
              ┌───────────────────────────┐
              │  Google AI Studio         │
              │  Gemini 2.0 Flash         │
              │  temperature = 0.1        │
              │  1,500 req/day (free)     │
              └───────────────────────────┘
```

---

## 2) Why No Firebase Cloud Functions

Firebase Cloud Functions (any generation) require the **Blaze billing plan**,
which requires a credit or debit card.  As students without billing access, we
use a **Cloudflare Worker** instead.

| Capability        | Cloud Functions (Blaze) | Cloudflare Worker (free) |
|-------------------|-------------------------|--------------------------|
| Server-side logic | ✅                      | ✅                       |
| Firestore triggers| ✅ native               | ❌ (called by client instead) |
| AI API proxy      | ✅                      | ✅                       |
| Free tier         | ❌ requires Blaze       | ✅ 100,000 req/day       |
| Cold start        | 100–2000 ms             | ~0 ms (V8 isolate, edge) |
| Credit card       | required                | not required             |

The trade-off is that computed fields are no longer written by a Firestore
trigger; they are written by the Worker after the Flutter client explicitly
calls `/classify`.  The security rules enforce that clients cannot set these
fields directly on document creation.

---

## 3) Data Write Contract

### What Flutter writes (raw fields only)

```
posts/{postId}
  authorId      string   — Firebase Auth UID
  title         string   — 1–200 chars
  description   string   — 1–1000 chars
  lat           number
  lng           number
  geohash       string
  city          string
  mediaUrls     string[]
  status        string   — always 'PENDING_MODERATION' on create
  upvotes       int      — always 0 on create
  commentsCount int      — always 0 on create
  sharesCount   int      — always 0 on create
  createdAt     timestamp
  updatedAt     timestamp
```

### What the Worker writes (computed fields — client cannot set these)

```
  category      string   — normalised enum value
  severity      float    — 0.0–1.0
  rankingScore  float    — 0.0–1.0
  authorityId   string   — responsible government body
  moderation    map
    .status     string   — 'approved' | 'rejected'
    .reason     string
    .confidence float
    .source     string   — 'gemini_2_flash' | 'fallback_deterministic'
  updatedAt     timestamp (overwritten)
```

Firestore security rules include `hasNoComputedFields()` which rejects any
create document that already contains any of those computed field names.

---

## 4) Request Flow (Post Creation)

```
1. User fills in report form and taps Submit.
2. Flutter uploads compressed image to Firebase Storage.
3. Flutter writes raw post document to Firestore.
   → Returns postId immediately.
   → Post is invisible to other users (moderation.status not yet set).
   → Author can see their own post via myPostsQuery().
4. Flutter calls POST /classify with:
     { postId, title, description, city, category?, createdAtMs }
     Authorization: Bearer <API_SHARED_SECRET>
5. Worker validates the shared secret.
6. Worker calls Gemini 2.0 Flash with a structured JSON prompt.
7. Worker computes severity, rankingScore, authorityId from AI result.
8. Worker obtains a Firebase access token from the service account.
9. Worker PATCHes the Firestore document with computed fields.
10. Post is now visible in the feed (moderation.status = 'approved').
11. Worker returns classification result to Flutter for immediate UI update.
```

---

## 5) Firebase Resource Budget (Spark Plan)

### Daily estimate for 500 DAU

| Operation               | Count/day | Spark limit |
|-------------------------|-----------|-------------|
| Feed reads (10 docs)    | 15,000    | 50,000 ✅   |
| Post detail + comments  | 10,000    | —           |
| Profile reads           | 5,000     | —           |
| **Total reads**         | **30,000**| **50,000**  |
| Writes (posts/comments) | 5,000     | 20,000 ✅   |
| Storage uploads         | 500       | 1 GB total  |

### Bandwidth control
- Compress images client-side before upload (target < 1 MB each).
- Limit 2 images per post.
- No unbounded real-time listeners for the global feed.
- Feed page size: 10 posts.  Comments: 20 per page.

---

## 6) Data Models

### Collections
- `users/{uid}`
- `posts/{postId}`
- `posts/{postId}/comments/{commentId}`
- `reports/{reportId}`
- `authorities/{authorityId}`
- `cities/{cityId}/routes/{routeId}` — future: dynamic authority routing
- `rate_limits/{uid}` — future: abuse prevention

### `posts` field reference
See Section 3 above for the full write contract.

---

## 7) Feed Ranking Formula

```
rankingScore = 0.35·proximity + 0.30·engagement + 0.20·recency + 0.15·severity
```

- **proximity** (0.35) — default 0.5 at creation; updated when user views feed.
- **engagement** (0.30) — (upvotes + commentsCount) / 100, clamped to [0, 1].
- **recency** (0.20) — linear decay from 1.0 at creation to 0.0 at 72 hours.
- **severity** (0.15) — from AI classification or category-severity map.

---

## 8) AI Classification Pipeline

```
Gemini 2.0 Flash (primary)
  temperature = 0.1
  responseMimeType = "application/json"
  Input:  city, title (≤200 chars), description (≤400 chars)
  Output: { category, severity, isSpam, isToxic, confidence, reason,
            suggestedDepartment }

  ↓ if Gemini unavailable or API key not configured

Deterministic fallback
  category from hint or normalised to 'other'
  severity from SEVERITY_BY_CATEGORY map
  isSpam = false, isToxic = false, confidence = 0.5
  source = 'fallback_deterministic'
```

---

## 9) Flutter App Architecture

- **Pattern**: Clean Architecture + Riverpod
- **Layers**: presentation → domain → data → services
- **Feature modules**: auth, feed, report, map_view, notifications, profile, admin_tools

### Offline-first (Phase 2)
- Local cache via Hive.
- Outbox queue for posts created offline.
- Background sync on reconnect.

---

## 10) Security Design

| Control                          | Implementation                               |
|----------------------------------|----------------------------------------------|
| Auth                             | Firebase Auth (email / OTP)                  |
| Post read access                 | Firestore rules — approved only (others)     |
| Computed field protection        | `hasNoComputedFields()` rule on post create  |
| AI API key protection            | Stored as Cloudflare Worker secret           |
| Worker authentication            | Shared secret in Authorization header        |
| Service account scope            | Datastore scope only (not full admin)        |
| Image upload ownership           | Storage rules — uid must match path segment  |
| Image size limit                 | Storage rules — 2 MB maximum                 |
| Rate limiting (future)           | `rate_limits/{uid}` collection + Worker check|
| Admin overrides                  | Firebase custom claim `admin: true`          |
| App Check (future)               | Play Integrity / DeviceCheck                 |

---

## 11) Worker File Structure

```
worker/
├── wrangler.toml          — Cloudflare Worker config
├── package.json           — Wrangler + Vitest devDependencies
└── src/
    ├── index.js           — Entry point, router, /classify handler
    ├── classifier.js      — Gemini call + deterministic fallback
    ├── scoring.js         — Pure scoring functions (ported from Cloud Functions)
    ├── auth.js            — Service account → OAuth access token (Web Crypto)
    └── firestore.js       — Firestore REST API PATCH wrapper
```

---

## 12) Deployment

### Cloudflare Worker
```bash
cd worker
npm install
wrangler secret put API_SHARED_SECRET
wrangler secret put GEMINI_API_KEY
wrangler secret put FIREBASE_SERVICE_ACCOUNT   # paste full JSON on one line
wrangler deploy
```

### Firebase (Spark plan — no functions)
```bash
firebase deploy --only hosting,firestore,storage
```

### Flutter
```bash
flutter build apk --release \
  --dart-define=WORKER_URL=https://fixingnation-ai.YOUR_SUBDOMAIN.workers.dev \
  --dart-define=WORKER_SECRET=<same value as API_SHARED_SECRET>
```

---

## 13) Scaling Plan

### MVP (< 500 users)
- Firebase Spark + Cloudflare Worker free tier — $0/month.
- Worker handles up to 100,000 classifications/day for free.
- Gemini free tier: 1,500 classifications/day (sufficient for MVP).

### Growth (500–5,000 users)
- Upgrade Gemini to a paid tier if daily posts exceed 1,500.
- Evaluate Firebase Blaze for Cloud Functions if Spark read/write limits hit.
- Add Cloudflare KV to cache Worker access tokens (eliminate one network round-trip per request).

### Expansion
- Add city routing from Firestore `cities/{city}/routes` (replace hardcoded map).
- Tune ranking weights from engagement metrics.
- Introduce city-level trending snapshots to reduce query cost.
