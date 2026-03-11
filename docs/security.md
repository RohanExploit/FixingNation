# Security Scanning — FixingNation

FixingNation uses a two-layer security scanning system on every push to `main`
and on every pull request.

---

## Automated Scanning (GitHub Actions — `.github/workflows/security.yml`)

### 1. `dart pub audit`

Scans all Dart/Flutter dependencies for known CVEs from the official Dart
advisory database.

```bash
# Run locally
cd flutter_app
dart pub audit
```

Exits with a non-zero code if any audited packages have vulnerabilities,
blocking the CI run.

### 2. Trivy Filesystem Scan

[Trivy](https://aquasecurity.github.io/trivy) scans the entire repository for:

- Leaked secrets / API keys in source files
- Vulnerable npm/yarn dependencies (Cloudflare Worker)
- Misconfigured IaC files

```bash
# Run locally (requires Docker or Trivy binary)
trivy fs --scanners secret,vuln .
```

### 3. `flutter analyze`

Runs on every CI job to enforce zero Dart warnings/errors.

```bash
cd flutter_app
flutter analyze
```

---

## What Is **Not** Scanned by CodeQL

GitHub CodeQL does not yet officially support Dart/Flutter. We use the tools
above instead — they cover the same categories for our stack:

| Category | Tool used |
|---|---|
| Dependency CVEs | `dart pub audit` + Trivy |
| Secret leaks | Trivy secret scanner |
| Code quality | `flutter analyze` |
| npm vulnerabilities | Trivy |

---

## Manual Security Checklist (Pre-Release)

Before every APK release, verify:

- [ ] `dart pub audit` passes with no vulnerabilities
- [ ] `firebase.json` / `.env` files are in `.gitignore`
- [ ] Firebase rules (Firestore + Storage) are reviewed
- [ ] `google-services.json` is in `.gitignore`
- [ ] Sentry DSN is not in any log output
- [ ] GPS coordinates are not sent to Sentry (enforced in `errorLogger.dart`)

---

## Firebase Security Rules

- **Firestore** rules: `firebase/firestore.rules`
- **Storage** rules: `firebase/storage.rules`

Storage is restricted to authenticated users, image MIME types only, ≤ 5 MB.
