import 'package:sentry_flutter/sentry_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// firebaseGuard — reusable safe wrapper for all Firebase operations
// ─────────────────────────────────────────────────────────────────────────────

/// Executes [action] and captures any exception to Sentry automatically.
///
/// Use this for every Firebase call site (Firestore, Storage, Auth) where
/// you want the error reported but not necessarily surfaced to the user.
///
/// Optional [tags] let you add structured context visible in Sentry:
///   - `operation`: e.g. 'firestore_write_post', 'storage_upload_image'
///   - `city`: city name — safe to log (not PII)
///   - `user_id`: Firebase UID — safe to log (opaque identifier)
///   - `screen`: screen name, e.g. 'ReportIssuePage'
///
/// ⚠️  Never pass email, phone, GPS coordinates, or any raw PII as tags.
///
/// Returns the result of [action] on success, or `null` on failure.
///
/// Example:
/// ```dart
/// final id = await firebaseGuard(
///   () => repo.createPost(...),
///   tags: {'operation': 'firestore_write_post', 'city': city},
/// );
/// ```
Future<T?> firebaseGuard<T>(
  Future<T> Function() action, {
  Map<String, String> tags = const {},
}) async {
  try {
    return await action();
  } catch (e, stackTrace) {
    await Sentry.captureException(
      e,
      stackTrace: stackTrace,
      withScope: (scope) {
        for (final entry in tags.entries) {
          scope.setTag(entry.key, entry.value);
        }
      },
    );
    return null;
  }
}

/// Variant that re-throws after reporting, for callers that must handle errors
/// themselves (e.g. UI state machines that show error messages to the user).
///
/// Example:
/// ```dart
/// try {
///   await firebaseGuardRethrow(
///     () => FirebaseAuth.instance.signInWithEmailAndPassword(...),
///     tags: {'operation': 'auth_sign_in'},
///   );
/// } on FirebaseAuthException catch (e) {
///   // show user-facing message
/// }
/// ```
Future<T> firebaseGuardRethrow<T>(
  Future<T> Function() action, {
  Map<String, String> tags = const {},
}) async {
  try {
    return await action();
  } catch (e, stackTrace) {
    await Sentry.captureException(
      e,
      stackTrace: stackTrace,
      withScope: (scope) {
        for (final entry in tags.entries) {
          scope.setTag(entry.key, entry.value);
        }
      },
    );
    rethrow;
  }
}
