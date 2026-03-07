# CivicPulse (FixingNation) — Production Architecture

## 1) System Architecture

### Topology
- **Clients**: Flutter Android app + Flutter Web PWA.
- **Identity**: Firebase Authentication (email/OTP/social providers where free).
- **Core data**: Firestore.
- **Media evidence**: Firebase Storage.
- **Backend logic**: Firebase Cloud Functions (HTTP + Firestore triggers + scheduled jobs).
- **Push notifications**: Firebase Cloud Messaging.
- **Hosting**: Firebase Hosting (web app + admin dashboard).
- **Analytics/monitoring**: Firebase Analytics + Crashlytics.

### Request flow
1. User creates post in client.
2. Client writes minimal post document (`PENDING_MODERATION`) and uploads media.
3. Firestore trigger calls moderation + classification pipeline.
4. Function writes moderation result, severity, authority routing, and feed score.
5. Optional social amplification function publishes to external channels.
6. Feed query reads pre-ranked documents using indexed pagination.

---

## 2) Firebase Resource Budget (Spark-aware)

### Read/write strategy
- Feed page size: 10 posts.
- Max auto-refresh: manual pull-to-refresh + timed refresh (>=60s).
- No unbounded real-time listeners for global feed.
- Comments paginated (20 max per page).
- Store denormalized counters (`upvotes`, `commentsCount`) to avoid aggregations.

### Daily budget estimate for 10k registered users (500 DAU target on Spark)
- Feed reads: 500 DAU × 3 sessions × 10 docs = 15,000 reads/day.
- Post detail/comments: ~10,000 reads/day.
- Profile/metadata: ~5,000 reads/day.
- **Total reads**: ~30,000/day (< 50,000).
- Writes (posts/comments/votes/events): target < 15,000/day (< 20,000).

### Bandwidth control
- Compress images client-side before upload.
- Limit media per post (max 2 images, 1.2MB each compressed).
- Lazy load media thumbnails.

---

## 3) Data Models

## Collections
- `users/{uid}`
- `posts/{postId}`
- `posts/{postId}/comments/{commentId}`
- `reports/{reportId}` (abuse reports)
- `authorities/{authorityId}`
- `cities/{cityId}/routes/{routeId}` (category-to-authority mapping)
- `rate_limits/{uid}` (rolling counters)

### `users`
- `username` (public)
- `avatarUrl` (public)
- `reputation` (public)
- `city` (public)
- `email` (admin-only)
- `deviceHash` (admin-only)
- `ipLogRefs` (admin-only)
- `roles` (`user`/`admin`)
- `createdAt`

### `posts`
- `authorId`
- `title`
- `description`
- `category` (`road_damage|garbage|electricity|water|safety|corruption|other`)
- `lat`, `lng`, `geohash`
- `city`
- `mediaUrls[]`
- `status` (`OPEN|ACKNOWLEDGED|IN_PROGRESS|RESOLVED|REJECTED`)
- `severity` (0-1)
- `engagementScore`
- `rankingScore`
- `authorityId`
- `moderation` (`pending|approved|rejected` + reason)
- `upvotes`, `commentsCount`, `sharesCount`
- `createdAt`, `updatedAt`

### `authorities`
- `name`
- `departmentType`
- `city`
- `zones[]`
- `contactInfo`
- `active`

---

## 4) Backend Services

### Cloud Functions modules
1. `onPostCreated`: moderation, category validation, severity scoring, routing.
2. `onVoteChanged`: updates denormalized engagement counters.
3. `onCommentCreated`: updates `commentsCount` and ranking score.
4. `scheduledReRank`: recalculates recency decay periodically.
5. `shareToSocial`: optional publish to Telegram/Reddit bridges.
6. `adminActions`: user ban/shadow-ban/status override.

### Routing engine
- Input: `city`, `category`, `lat/lng`.
- Source of truth: Firestore `cities/{city}/routes` rules.
- Output: `authorityId`, fallback reason if unresolved.

### Feed ranking
`score = 0.35*proximity + 0.30*engagement + 0.20*recency + 0.15*severity`

---

## 5) Flutter App Architecture

- **Pattern**: Clean Architecture + Riverpod.
- **Layers**:
  - `presentation`: widgets, pages, providers
  - `domain`: entities/use-cases
  - `data`: repositories + DTO mappers
  - `services`: Firebase + local cache + network + location

### Feature modules
- `auth`
- `feed`
- `post_issue`
- `map_view`
- `notifications`
- `profile`
- `admin_tools` (web/admin role gated)

### Offline-first
- Local cache via Hive/Isar.
- Outbox queue for posts/comments.
- Background sync when network returns.

---

## 6) AI Moderation System

- Provider: Gemini Pro via function proxy.
- Deterministic settings: `temperature <= 0.2`.
- JSON schema output:
  - `isSpam`
  - `isToxic`
  - `category`
  - `severity`
  - `confidence`
  - `reason`
- Rule: if `confidence < threshold`, return `Insufficient information` and route to manual review.

---

## 7) Deployment Pipeline

### GitHub Actions
- Lint/test Flutter and functions.
- Build APK + AAB artifacts.
- Build web PWA.
- Deploy hosting/functions/rules for main branch.

### Outputs
- `android/app-release.apk`
- `android/app-release.aab`
- `build/web`

---

## 8) Security Design

- Firestore rules: owner write, public read for approved posts, admin overrides.
- Storage rules: authenticated upload, strict path ownership.
- Rate-limits enforced in functions.
- Shadow ban flag at user level (`visibility = limited`) without user-facing notice.
- Admin audit log for moderation actions.

---

## 9) Scaling Plan

### MVP month-1
- Week 1: scaffolding + auth + post schema.
- Week 2: feed + comments + routing.
- Week 3: moderation + admin dashboard basics.
- Week 4: optimization + release artifacts + rollout in Pune.

### Expansion
- Add Mumbai then Bangalore authority mappings.
- Tune ranking weights from engagement metrics.
- Introduce city-level trending snapshots to reduce query cost.
