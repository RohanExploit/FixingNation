import 'dart:async';
import 'dart:convert';

import 'package:http/http.dart' as http;

import 'worker_config.dart';

// ─────────────────────────────────────────────────────────────────────────────
// AiService
// ─────────────────────────────────────────────────────────────────────────────

/// Sends civic complaint data to the Cloudflare Worker /classify endpoint.
///
/// The Worker is responsible for:
///   • AI classification via Gemini 2.0 Flash
///   • Computing severity, rankingScore, and authorityId
///   • Writing all computed fields back to the Firestore post document
///
/// Flutter only sends raw post content — it never computes or writes
/// server-authoritative scoring fields.
///
/// Usage — fire-and-forget (recommended for post submission):
/// ```dart
/// aiService.classifyInBackground(
///   postId:      docRef.id,
///   title:       title,
///   description: description,
///   city:        city,
///   createdAtMs: DateTime.now().millisecondsSinceEpoch,
///   onError: (e) => debugPrint('Classification failed: $e'),
/// );
/// ```
///
/// Usage — await result (for testing or admin tools):
/// ```dart
/// final result = await aiService.classify(...);
/// ```
class AiService {
  AiService({http.Client? httpClient})
      : _client = httpClient ?? http.Client();

  final http.Client _client;

  // Retry configuration
  static const int _maxRetries = 3;
  static const Duration _requestTimeout = Duration(seconds: 20);

  // Auth header — must match the `x-api-secret` Worker secret.
  static const Map<String, String> _headers = {
    'Content-Type': 'application/json',
    'x-api-secret': kWorkerSharedSecret,
  };

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Classify a post and return the computed fields.
  ///
  /// Retries up to [_maxRetries] times on server errors (5xx) and network
  /// failures, with exponential backoff (2 s, 4 s).  Client errors (4xx) are
  /// not retried because they indicate a request problem that won't change.
  ///
  /// The Worker writes the result directly to Firestore using its service
  /// account.  The returned [ClassificationResult] is provided for immediate
  /// optimistic UI feedback only — the authoritative values are in Firestore.
  ///
  /// Throws [AiServiceException] if all retries are exhausted.
  Future<ClassificationResult> classify({
    required String postId,
    required String title,
    required String description,
    required String city,
    String? categoryHint,
    required int createdAtMs,
  }) async {
    AiServiceException? lastError;

    for (int attempt = 1; attempt <= _maxRetries; attempt++) {
      try {
        return await _sendRequest(
          postId:       postId,
          title:        title,
          description:  description,
          city:         city,
          categoryHint: categoryHint,
          createdAtMs:  createdAtMs,
        );
      } on AiServiceException catch (e) {
        lastError = e;

        // Client errors (4xx) will not improve on retry.
        if (e.isClientError) rethrow;

        // Last attempt — surface the error to the caller.
        if (attempt == _maxRetries) rethrow;

        // Exponential backoff: 2 s after attempt 1, 4 s after attempt 2.
        await Future<void>.delayed(Duration(seconds: attempt * 2));
      }
    }

    // Unreachable — the loop always rethrows or returns before here.
    throw lastError!;
  }

  /// Fire-and-forget variant.
  ///
  /// Returns immediately.  Classification runs in the background and the
  /// Worker writes the result to Firestore when complete.  No [Future] is
  /// returned so the calling UI is never blocked.
  ///
  /// [onError] is invoked on the calling zone if all retries are exhausted.
  /// If [onError] is null, errors are silently discarded after logging.
  void classifyInBackground({
    required String postId,
    required String title,
    required String description,
    required String city,
    String? categoryHint,
    required int createdAtMs,
    void Function(Object error)? onError,
  }) {
    // unawaited is intentional — fire and forget.
    // ignore: discarded_futures
    classify(
      postId:       postId,
      title:        title,
      description:  description,
      city:         city,
      categoryHint: categoryHint,
      createdAtMs:  createdAtMs,
    ).catchError((Object error) {
      // Always log so the error is visible during development.
      // ignore: avoid_print
      print('[AiService] Background classification failed for $postId: $error');
      onError?.call(error);
      return ClassificationResult(
        postId:      postId,
        status:      'error',
        category:    'other',
        severity:    0.5,
        rankingScore: 0.5,
        authorityId: 'unmapped_city_authority',
        moderation:  ModerationResult(
          status:     'pending',
          reason:     error.toString(),
          confidence: 0,
          source:     'error',
        ),
      );
    });
  }

  // ── Internal ───────────────────────────────────────────────────────────────

  Future<ClassificationResult> _sendRequest({
    required String postId,
    required String title,
    required String description,
    required String city,
    String? categoryHint,
    required int createdAtMs,
  }) async {
    final uri = Uri.parse('$kWorkerBaseUrl/classify');

    final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: _headers,
            body: jsonEncode({
              'postId':      postId,
              'title':       title.trim(),
              'description': description.trim(),
              'city':        city,
              if (categoryHint != null) 'category': categoryHint,
              'createdAtMs': createdAtMs,
            }),
          )
          .timeout(_requestTimeout);
    } on TimeoutException {
      throw AiServiceException(
        'Request timed out after ${_requestTimeout.inSeconds}s',
        isClientError: false,
      );
    } on Exception catch (e) {
      throw AiServiceException('Network error: $e', isClientError: false);
    }

    // 2xx → parse and return result.
    if (response.statusCode >= 200 && response.statusCode < 300) {
      return _parseBody(response.body);
    }

    // 4xx → client error, do not retry.
    if (response.statusCode >= 400 && response.statusCode < 500) {
      throw AiServiceException(
        'Worker rejected request (${response.statusCode}): ${response.body}',
        isClientError: true,
      );
    }

    // 5xx or unexpected → server error, will be retried.
    throw AiServiceException(
      'Worker server error (${response.statusCode}): ${response.body}',
      isClientError: false,
    );
  }

  ClassificationResult _parseBody(String body) {
    try {
      final json = jsonDecode(body) as Map<String, dynamic>;
      return ClassificationResult.fromJson(json);
    } on FormatException catch (e) {
      throw AiServiceException(
        'Worker returned malformed JSON: $e',
        isClientError: false,
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Result types
// ─────────────────────────────────────────────────────────────────────────────

/// The computed fields returned by the Worker after classification.
///
/// These values are also written to Firestore by the Worker, so this object
/// is used only for immediate UI feedback (e.g. showing the assigned category
/// badge before the next Firestore read completes).
class ClassificationResult {
  const ClassificationResult({
    required this.postId,
    required this.status,
    required this.category,
    required this.severity,
    required this.rankingScore,
    required this.authorityId,
    required this.moderation,
  });

  factory ClassificationResult.fromJson(Map<String, dynamic> json) {
    return ClassificationResult(
      postId:      json['postId']      as String? ?? '',
      status:      json['status']      as String? ?? 'OPEN',
      category:    json['category']    as String? ?? 'other',
      severity:    (json['severity']   as num?)?.toDouble() ?? 0.5,
      rankingScore:(json['rankingScore'] as num?)?.toDouble() ?? 0.5,
      authorityId: json['authorityId'] as String? ?? 'unmapped_city_authority',
      moderation:  ModerationResult.fromJson(
        json['moderation'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  final String postId;

  /// Top-level post status: 'OPEN' | 'REJECTED'
  final String status;

  /// Normalised category: 'road_damage' | 'garbage' | 'electricity' |
  ///                      'water' | 'safety' | 'corruption' | 'other'
  final String category;

  /// Severity score [0.0, 1.0] — higher means more critical.
  final double severity;

  /// Feed ranking score [0.0, 1.0].
  final double rankingScore;

  /// ID of the responsible government authority.
  final String authorityId;

  final ModerationResult moderation;

  /// Convenience getter — true when moderation passed.
  bool get isApproved => moderation.status == 'approved';

  @override
  String toString() =>
      'ClassificationResult(postId: $postId, category: $category, '
      'severity: $severity, status: $status, '
      'moderation: ${moderation.status} [${moderation.source}])';
}

class ModerationResult {
  const ModerationResult({
    required this.status,
    required this.reason,
    required this.confidence,
    required this.source,
  });

  factory ModerationResult.fromJson(Map<String, dynamic> json) {
    return ModerationResult(
      status:     json['status']      as String? ?? 'pending',
      reason:     json['reason']      as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
      source:     json['source']      as String? ?? 'unknown',
    );
  }

  /// 'approved' | 'rejected' | 'pending'
  final String status;
  final String reason;
  final double confidence;

  /// 'gemini_2_flash' | 'fallback_deterministic' | 'fallback_error'
  final String source;
}

// ─────────────────────────────────────────────────────────────────────────────
// Exception
// ─────────────────────────────────────────────────────────────────────────────

class AiServiceException implements Exception {
  const AiServiceException(this.message, {required this.isClientError});

  final String message;

  /// True for 4xx responses — these are not retried.
  /// False for network errors and 5xx responses — these are retried.
  final bool isClientError;

  @override
  String toString() =>
      'AiServiceException(clientError: $isClientError): $message';
}
