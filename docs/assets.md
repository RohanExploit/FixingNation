# Asset Optimization — FixingNation

---

## Imgbot (Automatic Image Compression)

[Imgbot](https://imgbot.net) is a GitHub App that automatically compresses
images in the repository and opens a pull request with the optimized versions.

### Setup (one-time manual step)

1. Go to [github.com/marketplace/imgbot](https://github.com/marketplace/imgbot)
2. Click **Set up a plan** (free for open-source)
3. Grant access to the **FixingNation** repository
4. Imgbot will open a PR whenever it finds compressible images

Imgbot configuration is in `.imgbotconfig` at the repo root.

---

## Flutter App Image Guidelines

Images used by the app (in `flutter_app/assets/`) should follow these rules:

| Type | Format | Max size |
|---|---|---|
| App icons | PNG | 50 KB |
| Placeholder images | WebP | 30 KB |
| Splash/onboarding | WebP | 100 KB |

### Generating WebP from PNG locally

```bash
# Requires cwebp (libwebp)
cwebp -q 80 input.png -o output.webp
```

### Adding assets to pubspec.yaml

```yaml
flutter:
  assets:
    - assets/images/
    - assets/icons/
```

---

## User-Uploaded Images (Firebase Storage)

User-uploaded civic report images are compressed **in-app** by
`flutter_image_compress` before upload:

- Target: ≤ 200 KB
- Format: JPEG
- Quality fallback: 80 → 60 → 40
- Width cap: 1080 px (height proportional)

This is handled in `post_repository.dart → uploadImage()`.
Firebase Storage rules enforce a 5 MB hard cap server-side as a backstop.

---

## APK Size Monitoring

Run before every release to check the APK size impact of assets:

```bash
cd flutter_app
flutter build apk --analyze-size
```

This shows a breakdown of what's contributing to APK size.
