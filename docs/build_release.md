# FixingNation First Android Release Guide

## 1. What's Already Configured
The Android release build is completely pre-configured and optimized:
- **`proguard-rules.pro`**: Contains explicit rules so that **Firebase, Sentry, and Hive** are not stripped out by R8 minification.
- **`build.gradle.kts`**: `isMinifyEnabled` and `isShrinkResources` are both set to `true`, dramatically shrinking the Android app size.
- **Default signing**: The release currently uses the `debug` signing key. This allows anyone to install the APK directly to their hardware for side-loading without Google Play restrictions during beta testing.

## 2. Generating the Android APK & AAB
Because your PC does not have the **Android SDK** installed (as confirmed by `flutter doctor`), and disk space is low, it is recommended to build the APK via a remote CI/CD tool, or to install Android Studio on a machine with sufficient disk space.

### Option A: Local Build (When Android SDK is installed)
If you configure an Android SDK locally, just run:
```bash
cd flutter_app
flutter build apk --release
flutter build appbundle --release
```
- The APK will be saved at: `build/app/outputs/flutter-apk/app-release.apk`
- The App Bundle (AAB) will be saved at: `build/app/outputs/bundle/release/app-release.aab`

### Option B: Cloud Build (Recommended for low-spec PCs)
You can use **GitHub Actions** to automatically build your APK and AAB without using your computer's RAM or disk space. I can set this up for you in the next step by generating an `android_release.yml` workflow file!

## 3. What Happens After the APK
Next testing stage should be:
1. **Install APK on real Android device** using a USB cable or sending the file to your phone.
2. Test flows on a real 4G/5G connection:
   - Registration and Login
   - Create an issue (test camera permission and GPS)
   - Upload photo
   - Feed pagination (`limit(30)`)
   - Offline mode (turn off Wi-Fi/Data and open app)
   - Upvote persistence (ensure it sticks across restarts)
