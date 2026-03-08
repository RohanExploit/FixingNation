import 'dart:convert';
import 'package:http/http.dart' as http;

/// Calls the Cloudflare Worker /classify endpoint.
///
/// The Worker is the sole authority for:
///   - AI complaint classification (Gemini 2.0 Flash)
///   - severity scoring
///   - rankingScore calculation
///   - authority routing
///   - moderation verdict
///
/// Flutter sends only raw post content.  The Worker returns the computed
/// fields, which are also written directly to Firestore by the Worker using
/// its service account credentials.  The Flutter client uses the returned
/// values only for immediate UI feedback (e.g. showing the assigned category
/// before the next Firestore read).
///
/// SECURITY NOTE
/// -------------
/// The [apiSharedSecret] is a static value baked into the app.  This is
/// acceptable for an MVP because the secret only authorises calls to the
/// Worker, which itself validates and rate-limits all Firestore writes.
/// For production, replace this with Firebase ID-token verification in the
/// Worker and remove the shared secret entirely.
class ClassifyService {
  ClassifyService({
    required this.workerBaseUrl,
    required this.apiSharedSecret,
    http.Client? client,
  }) : _client = client ?? http.Client();

  final String workerBaseUrl;
  final String apiSharedSecret;
  final http.Client _client;

  /// Classify a post and return the computed server-side fields.
  ///
  /// [postId]      — the Firestore document ID returned after writing the post.
  /// [title]       — raw title from the user.
  /// [description] — raw description from the user.
  /// [city]        — city string derived from the user's GPS location.
  /// [categoryHint]— optional category selected by the user (treated as a hint
  ///                 only; the AI may override it).
  /// [createdAtMs] — Unix epoch milliseconds of the post creation time.
  ///
  /// Throws [ClassifyException] on HTTP errors or malformed responses.
  Future<ClassificationResult> classify({
    required String postId,
    required String title,
    required String description,
    required String city,
    String? categoryHint,
    required int createdAtMs,
  }) async {
    final uri = Uri.parse('$workerBaseUrl/classify');

    final http.Response response;
    try {
      response = await _client
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $apiSharedSecret',
            },
            body: jsonEncode({
              'postId':      postId,
              'title':       title,
              'description': description,
              'city':        city,
              if (categoryHint != null) 'category': categoryHint,
              'createdAtMs': createdAtMs,
            }),
          )
          .timeout(const Duration(seconds: 20));
    } on Exception catch (e) {
      throw ClassifyException('Network error calling Worker: $e');
    }

    if (response.statusCode == 200) {
      final Map<String, dynamic> json;
      try {
        json = jsonDecode(response.body) as Map<String, dynamic>;
      } catch (_) {
        throw ClassifyException(
          'Worker returned non-JSON body: ${response.body.substring(0, 200)}',
        );
      }
      return ClassificationResult.fromJson(json);
    }

    throw ClassifyException(
      'Worker returned HTTP ${response.statusCode}: ${response.body}',
    );
  }
}

// ---------------------------------------------------------------------------
// Result types
// ---------------------------------------------------------------------------

class ClassificationResult {
  const ClassificationResult({
    required this.category,
    required this.severity,
    required this.rankingScore,
    required this.authorityId,
    required this.moderation,
  });

  factory ClassificationResult.fromJson(Map<String, dynamic> json) {
    return ClassificationResult(
      category:    json['category']    as String? ?? 'other',
      severity:    (json['severity']   as num?)?.toDouble() ?? 0.5,
      rankingScore:(json['rankingScore'] as num?)?.toDouble() ?? 0.5,
      authorityId: json['authorityId'] as String? ?? 'unmapped_city_authority',
      moderation:  ModerationResult.fromJson(
        json['moderation'] as Map<String, dynamic>? ?? {},
      ),
    );
  }

  final String category;
  final double severity;
  final double rankingScore;
  final String authorityId;
  final ModerationResult moderation;

  /// Whether the post was approved by the moderation pipeline.
  bool get isApproved => moderation.status == 'approved';
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
      status:     json['status']     as String? ?? 'pending',
      reason:     json['reason']     as String? ?? '',
      confidence: (json['confidence'] as num?)?.toDouble() ?? 0.5,
      source:     json['source']     as String? ?? 'unknown',
    );
  }

  /// 'approved' | 'rejected' | 'pending'
  final String status;
  final String reason;
  final double confidence;
  final String source;
}

class ClassifyException implements Exception {
  const ClassifyException(this.message);
  final String message;

  @override
  String toString() => 'ClassifyException: $message';
}
