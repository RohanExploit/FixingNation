# FixingNation — Developer Context

> This file is the single source of truth for any AI assistant, new contributor,
> or future self picking up this project. Read this before touching any code.

---

## What This App Does

FixingNation is a **civic issue reporting platform** for Indian cities (Pune, Mumbai, Bangalore).
Citizens report local problems (potholes, garbage, broken streetlights, corruption) via a Flutter
Android app. Reports appear in a city-scoped public feed. A Telegram bot notifies the owner and
supports a parallel submission + approval channel.

**Demo context:** Built for a hackathon / college presentation. No production billing.

---

## Constraints (Do Not Violate)

| Constraint | Reason |
|---|---|
| **Firebase Spark plan only** | No credit/debit card. No Cloud Functions, no extensions, no paid tiers. |
| **Cloudflare Worker replaces Cloud Functions** | Free, 100k req/day, ~0ms cold start. |
| **No Gemini/AI in the critical path** | AI was removed from post submission. Category is user-selected. |
| **Do not revoke the Telegram bot token** | Owner decision. Token is `8493507107:AAF6EtBErAgA1J9_WOumQT5qOdIQxlvE2wI` for `@vishwaguru_bot`. |
| **Spark Storage limit: 1 GB / 2 MB per image** | Enforce in Storage rules and client-side compression. |
| **Spark Firestore: 50k reads / 20k writes per day** | Design queries to be cheap. No real-time listeners on global feed. |

---

## Current Architecture

```
Flutter App (Android)
  ├── Firebase Auth       — email/password login
  ├── Firestore           — read feed, write posts & comments
  ├── Firebase Storage    — image uploads (max 2 MB)
  └── Telegram Bot        — fire-and-forget owner notification on submit

Cloudflare Worker (fixingnation-ai-worker)
  ├── POST /classify      — AI classification (currently unused by app, kept for future)
  ├── POST /telegram      — Telegram bot webhook (new, needs deploy)
  └── GET  /health        — liveness probe

Firebase Backend (Spark)
  ├── Firestore           — posts, users, comments, reports, authorities
  ├── Storage             — posts/{uid}/{timestamp}.jpg
  └── Hosting             — (web frontend, not primary focus)
```

---

## Post Submission Flow (Current — No AI)

1. User fills form: title, description, category (user-selected), city, location, optional photo
2. Photo uploaded to Firebase Storage → download URL stored
3. Post written to Firestore with `status: 'under_review'` directly
4. Post immediately visible in city feed
5. `TelegramService.notifyNewIssue()` fires-and-forgets a notification to owner's Telegram

**Status values in use:** `under_review` | `resolved` | `rejected`

---

## Telegram Integration (Two Channels)

### Channel 1 — App Submission Notification (existing)
- File: `flutter_app/lib/services/telegram_service.dart`
- Bot: `@vishwaguru_bot`
- Token: hardcoded in client (known risk, owner decision to keep)
- Chat ID: `1990648223` (owner's personal chat, @its_oppa)
- Sends a formatted card to owner whenever a post is submitted via the app

### Channel 2 — Bot Submission + Approval Flow (new, pending deploy)
- File: `worker/src/telegram.js`
- Any Telegram user can send `/report` to `@vishwaguru_bot`
- Multi-step conversation: title → description → category → city → location → photo
- Bot sends submission card to owner with ✅ Approve / ❌ Deny inline buttons
- On Approve: Worker creates Firestore post (`status: under_review`) → appears in feed
- On Deny: submitter notified
- **State stored in Cloudflare KV** (namespace: `PENDING_SUBMISSIONS`, TTL 1h for state, 24h for submissions)

**Pending steps to activate Channel 2:**
```bash
# 1. Create KV namespace, get the ID
npx wrangler kv namespace create PENDING_SUBMISSIONS

# 2. Paste the returned ID into worker/wrangler.toml under [[kv_namespaces]]

# 3. Set bot token as secret
npx wrangler secret put TELEGRAM_BOT_TOKEN
# value: 8493507107:AAF6EtBErAgA1J9_WOumQT5qOdIQxlvE2wI

# 4. Deploy worker
npx wrangler deploy

# 5. Register webhook (replace <WORKER_URL> with actual deployed URL)
curl "https://api.telegram.org/bot8493507107:AAF6EtBErAgA1J9_WOumQT5qOdIQxlvE2wI/setWebhook?url=<WORKER_URL>/telegram"
```

---

## Firestore Schema

### `posts/{postId}`
```
authorId      string   — Firebase Auth UID (or "tg:{chatId}" for Telegram submissions)
title         string   — max 200 chars
description   string   — max 1000 chars
category      string   — road_damage | garbage | electricity | water | safety | corruption | other
city          string   — pune | mumbai | bangalore (lowercase)
lat           number
lng           number
geohash       string   — precision 6 (~1.2 km)
mediaUrls     string[] — Firebase Storage download URLs
status        string   — under_review | resolved | rejected
source        string   — "app" | "telegram" (telegram submissions only)
upvotes       int
commentsCount int
sharesCount   int
createdAt     timestamp
updatedAt     timestamp
```

### `posts/{postId}/comments/{commentId}`
```
authorId   string
text       string   — max 500 chars
createdAt  timestamp
```

### `users/{uid}`
```
displayName  string
email        string
city         string
createdAt    timestamp
```

### `reports/{reportId}`
```
postId      string
reason      string   — spam | fake | offensive | duplicate
reporterId  string   — Firebase Auth UID
createdAt   timestamp
```

---

## Composite Indexes

Defined in `firebase/firestore.indexes.json` (now committed, deploy with firebase CLI):

| Collection | Fields | Used by |
|---|---|---|
| `posts` | city ASC + status ASC + createdAt DESC | Feed query |
| `posts` | authorId ASC + createdAt DESC | Profile / my posts query |

**Deploy:** `firebase deploy --only firestore:indexes`

---

## Known Bugs / Debt (From Production Audit)

### Critical — Fix Before Any Public Demo

| # | Issue | File | Fix |
|---|---|---|---|
| C-1 | Firestore rules check `status == 'PENDING_MODERATION'` but app writes `'under_review'`. Rules also check `moderation.status` (nested) which no longer exists. Database may be in test mode (open). | `firebase/firestore.rules` | Update `validPostCreate()` to check `'under_review'`; update read rule to use flat `status` field |
| C-3 | Indexes were created manually via Firebase Console links but weren't in `firestore.indexes.json` — would be wiped on `firebase deploy --only firestore:indexes` | `firebase/firestore.indexes.json` | ✅ Fixed this session |

### High Priority — Fix Before Launch

| # | Issue | File | Fix |
|---|---|---|---|
| H-1 | Storage rules allow uploading any file type — no content-type check | `firebase/storage.rules` | Add `request.resource.contentType.matches('image/(jpeg|png|webp)')` |
| H-4 | No rate limiting on Worker — Gemini quota and Firestore writable without limit | `worker/src/index.js` | Add per-UID rate limit using Cloudflare KV |
| H-5 | `failed_classifications` collection allows any signed-in user to write arbitrary data | `firebase/firestore.rules` | Add strict field validation |
| H-6 | User profiles world-readable (unauthenticated access) | `firebase/firestore.rules` | Change `allow read: if true` to `if isSignedIn()` |

### Medium — Fix Early Post-Launch

| # | Issue | Fix |
|---|---|---|
| M-1 | No cursor-based pagination — feed truncates at 30 posts | Add `startAfterDocument` cursor in feed query |
| M-2 | No idempotency on post creation — retries create duplicates | Use `doc(uuid).set()` instead of `collection.add()` |
| M-3 | No offline queue — submissions lost without internet | Enable Firestore persistence in `main.dart` |
| M-4 | Images uploaded raw (up to 15 MB) — add `flutter_image_compress` | Compress to ~300 KB before upload |

---

## Session Log

### Session (2026-03-09)

**Android Build Fixes**
- Pinned NDK to `27.0.12077973` in `android/app/build.gradle.kts` to avoid NDK 28 auto-download
- Added all required `AndroidManifest.xml` permissions: INTERNET, ACCESS_FINE_LOCATION, ACCESS_COARSE_LOCATION, FOREGROUND_SERVICE, CAMERA, READ_MEDIA_IMAGES
- Fixed `output-metadata.json` error with `flutter clean`

**Firebase Setup**
- User enabled Email/Password auth in Firebase Console
- User added SHA-1 fingerprint to Firebase project, replaced `google-services.json`
- User created Firestore database (test mode, asia-south1)
- User clicked index creation URLs for both composite indexes

**Report Flow Fixes**
- Removed AI classification pipeline entirely — category is now user-selected
- `PostRepository.createPost()` rewritten: writes `status: 'under_review'` directly, no Worker call
- Fixed right overflow (56px) in report form: removed bad `prefixIcon` padding, replaced `TextButton` trailing with `IconButton`
- Fixed location detection: `ACCESS_FINE_LOCATION` was missing from manifest

**Telegram Integration**
- Created `flutter_app/lib/services/telegram_service.dart` — fire-and-forget owner notification on app submission
- Wired into `PostRepository.createPost()` after successful Firestore write
- Confirmed working: bot token valid, chat ID `1990648223` obtained via `getUpdates`

**Telegram Bot Approval Flow (new)**
- Created `worker/src/telegram.js` — full multi-step conversation + owner approval workflow
- Added `createDocument()` to `worker/src/firestore.js`
- Wired `/telegram` route into `worker/src/index.js`
- Updated `worker/wrangler.toml` — added KV namespace binding + `TELEGRAM_OWNER_CHAT_ID` var
- **Pending:** KV namespace creation, `wrangler deploy`, webhook registration (see above)

**Indexes**
- Populated `firebase/firestore.indexes.json` with both required composite indexes ✅

**Code Quality**
- Replaced broken default `test/widget_test.dart` with empty placeholder
- `flutter analyze` → 0 errors, 0 warnings (only info-level style hints)

---

## File Map (Key Files Only)

```
FixingNation/
├── CONTEXT.md                          ← this file
├── ARCHITECTURE.md                     ← system design detail
├── firebase/
│   ├── firestore.rules                 ← NEEDS C-1 FIX before deploy
│   ├── storage.rules                   ← needs content-type check
│   ├── firestore.indexes.json          ← ✅ composite indexes committed
│   └── functions/index.js              ← scoring functions (reference only, not deployed)
├── worker/
│   ├── wrangler.toml                   ← KV namespace ID still needs to be filled in
│   └── src/
│       ├── index.js                    ← /classify + /telegram routes
│       ├── telegram.js                 ← bot webhook handler (new)
│       ├── firestore.js                ← patchDocument + createDocument
│       ├── auth.js                     ← service account → OAuth token
│       ├── classifier.js               ← Gemini + deterministic fallback
│       └── scoring.js                  ← ranking formula, severity map
└── flutter_app/lib/
    ├── main.dart                       ← app entry, Firebase init, auth gate
    ├── services/
    │   └── telegram_service.dart       ← owner notification on app submit
    └── features/
        ├── auth/                       ← login + register
        ├── report/                     ← submission form + notifier + repository
        ├── feed/                       ← city feed + Hive cache
        └── issue_detail/               ← post detail + comments
```

---

## Running the App

```bash
# Prerequisites: Flutter 3.41.4, Android device connected
cd flutter_app
flutter run                             # debug on connected device

# Build release APK
flutter build apk --release
```

## Deploying the Worker

```bash
cd worker
npx wrangler deploy
```

## Deploying Firebase Rules + Indexes

```bash
# From project root
firebase deploy --only firestore:rules,firestore:indexes,storage
```
