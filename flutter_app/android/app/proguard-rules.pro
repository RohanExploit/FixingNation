# Flutter Wrapper
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# Firebase (Core, Auth, Firestore, Storage)
-keep class com.google.firebase.** { *; }
-keep class io.flutter.plugins.firebase.** { *; }
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses

# Sentry
-keep class io.sentry.** { *; }
-keep class io.flutter.plugins.sentry.** { *; }

# Hive / Path Provider / Other core plugins
-keep class com.tekartik.sqflite.** { *; }
-keep class io.flutter.plugins.pathprovider.** { *; }

# Image compress
-keep class com.sython.flutter_image_compress.** { *; }

# Prevent R8 missing-class crashes for Play Core (used implicitly by Flutter engine)
# These are safe to ignore if not building a Play Feature Delivery bundle
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.**
-dontwarn com.google.android.play.core.tasks.**
