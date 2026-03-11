# FixingNation Pre-Release Audit Report

## Executive Summary
This document summarizes the findings from the pre-release stability and constraint audit. The application was audited specifically against **Firebase Spark plan limits**, **low-bandwidth/offline scenarios**, and **overall runtime stability** suitable for a production un-paid Android-first release.

**Conclusion:** The application is architecturally sound and respects Firebase Spark plan limits. All core flows (Auth, Feed, Report Issue, Profile) have been engineered with defensive guarding, aggressive compression, cache-first strategies, and proper Sentry error reporting.

---

## 1. Firebase Spark Plan Compliance

### Firestore Reads & Writes (Limits: 50k reads/day, 20k writes/day)
- **Feed Pagination:** The feed correctly utilizes `.limit(30)` in `_fetchFromFirestore` to avoid full-collection reads.
- **Profile Pagination:** The user's profile also paginates their own reports with `.limit(20)`.
- **Offline Caching:** The feed aggressively caches to `Hive`, meaning duplicate app opens on the same day won't necessarily incur network costs if the device goes offline.

### Firebase Storage (Limit: 1 GB)
- **Image Compression:** `uploadImage()` in `post_repository.dart` aggressively steps down JPEG quality (80 -> 60 -> 40) ensuring images are consistently under 200 KB before uploading.
- **Capacity:** At ~200 KB per issue, the free tier allows ~5,000 image reports before hitting the 1 GB Storage limit.
- **Rules:** `storage.rules` caps files at 5MB and enforces content-type restrictions (image only), stopping malicious over-allocation.

---

## 2. Stability & Error Handling

### Offline Resiliency
- **Auth:** `auth_notifier.dart` provides graceful, context-aware messages for network failures (e.g., `network-request-failed`).
- **Feed:** `feed_notifier.dart` gracefully falls back to Hive-cached data if `Connectivity().checkConnectivity()` detects no internet or if the Firestore request fails.
- **Submissions:** `report_notifier.dart` checks connectivity *before* attempting upload/write to prevent silent failures mid-transaction.

### Crash Prevention
- **Safe Deserialization:** `PostModel.fromFirestore` provides safe defaults (`status = 'under_review'`, empty strings for missing fields) preventing null-check operator crashes.
- **Global Error Boundary:** Sentry is correctly integrated in `main.dart` with `SentryFlutter.init` mapping unhandled async errors.
- **Repository Safety:** All Firebase transactions are wrapped in `firebaseGuard` and `firebaseGuardRethrow`, guaranteeing UI state stability instead of abrupt layout crashes.

---

## 3. Data Integrity & Moderation

### Hive Initialization
- All required Hive boxes (`feed_cache`, `upvoted_posts`) are synchronously opened in `main.dart` *before* provider initialization, completely preventing `HiveError: Box not found`.

### Idempotency
- The `report_notifier.dart` generates a UUID v4 `_idempotencyKey` per form session. This prevents accidental duplicate post creation if a user double-taps or if network latency triggers retries.

### Moderation Logic
- Posts are initiated with `status: 'under_review'`.
- The feed effectively queries `where('status', isEqualTo: 'under_review')` which reflects community moderation logic.

### Upvote Duplicate Prevention
- Upvote limits are enforced locally using Hive `upvoted_posts` to block multiple API calls.
- Transactional increments are used in Firestore to prevent race conditions from concurrent users upvoting.

---

## 4. Security Rules Check

### Firestore (`firestore.rules`)
- Read access is strictly authenticated.
- Writes require the user to hold the `authorId`.
- Updates limit mutating the base post, only allowing the `upvotes` field to increment.

### Storage (`storage.rules`)
- Restricted to authenticated users.
- Users can only write to their specific `issues/{userId}/{uuid}` path.
- Payload strictness: `< 5MB`, `image/jpeg`, `image/png`, `image/webp`.

---

## Remaining Actions (User side)
- Deploy Android APK to real device.
- Add `CODECOV_TOKEN` to GitHub secrets.
- Verify Codecov reports on next pull request.
