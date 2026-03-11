import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sentry_flutter/sentry_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// ErrorLogger — centralised error capture for the entire app
// ─────────────────────────────────────────────────────────────────────────────

/// Call [ErrorLogger.init] once in [main] before [SentryFlutter.init].
///
/// Sets up three global net-catches:
///   1. [FlutterError.onError]   — catches widget/framework errors
///   2. [PlatformDispatcher.onError] — catches platform errors (Flutter 3.3+)
///   3. [runZonedGuarded]        — catches all uncaught async exceptions
///
/// Usage in main():
/// ```dart
/// await SentryFlutter.init(
///   (options) { ... },
///   appRunner: () => runZonedGuarded(
///     () => runApp(const ProviderScope(child: CivicPulseApp())),
///     ErrorLogger.onZoneError,
///   ),
/// );
/// ```
class ErrorLogger {
  ErrorLogger._();

  /// Wire up Flutter framework and platform error handlers.
  /// Call this inside [SentryFlutter.init] → [appRunner] before [runApp].
  static void init() {
    // 1. Flutter framework / widget errors
    FlutterError.onError = (FlutterErrorDetails details) {
      // Still print in debug mode for local feedback.
      if (kDebugMode) {
        FlutterError.presentError(details);
      }
      Sentry.captureException(
        details.exception,
        stackTrace: details.stack,
      );
    };

    // 2. Platform dispatcher (uncaught from platform channel, etc.)
    PlatformDispatcher.instance.onError = (error, stack) {
      Sentry.captureException(error, stackTrace: stack);
      return true; // true = handled, don't crash
    };
  }

  /// Pass to [runZonedGuarded] as the error callback.
  /// Catches uncaught async exceptions that escape all other handlers.
  static void onZoneError(Object error, StackTrace stack) {
    if (kDebugMode) {
      debugPrint('[ErrorLogger] Uncaught async error: $error\n$stack');
    }
    Sentry.captureException(error, stackTrace: stack);
  }

  // ── Manual breadcrumb helpers ───────────────────────────────────────────────

  /// Add a navigation breadcrumb manually (for non-named-route navigation).
  static void logNavigation(String screen) {
    Sentry.addBreadcrumb(Breadcrumb(
      type:     'navigation',
      category: 'navigation',
      data:     {'to': screen},
    ));
  }

  /// Log a structured Firebase operation breadcrumb.
  /// [operation]: e.g. 'firestore_read_feed', 'storage_upload_image'
  /// [city]: city filter in use, if applicable — safe to log (not PII)
  static void logFirebaseOp(String operation, {String? city}) {
    Sentry.addBreadcrumb(Breadcrumb(
      category: 'firebase',
      message:  operation,
      data:     {
        if (city != null) 'city': city,
      },
      level: SentryLevel.info,
    ));
  }
}
