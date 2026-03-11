import 'package:cloud_firestore/cloud_firestore.dart';

/// Immutable representation of a civic issue post as used throughout the app.
///
/// The `status` lifecycle (set by Firestore / admin):
///   under_review → resolved | rejected
///
/// `modStatus` is removed — it was a duplicate of `status` mapped from the
/// same field, which caused confusing divergence.
class PostModel {
  const PostModel({
    required this.id,
    required this.title,
    required this.description,
    required this.city,
    required this.status,
    required this.upvotes,
    required this.commentsCount,
    required this.createdAt,
    this.category,
    this.authorId,
    this.authorName,
    this.lat,
    this.lng,
    this.severity,
    this.rankingScore,
    this.authorityId,
    this.mediaUrls = const [],
  });

  final String   id;
  final String   title;
  final String   description;
  final String   city;
  final String   status;
  final int      upvotes;
  final int      commentsCount;
  final DateTime createdAt;

  final String? category;
  final String? authorId;
  final String? authorName;
  final double? lat;
  final double? lng;
  final double? severity;
  final double? rankingScore;
  final String? authorityId;
  final List<String> mediaUrls;

  // ── Semantic status helpers ─────────────────────────────────────────────────

  bool get isUnderReview => status == 'under_review';
  bool get isResolved    => status == 'resolved';
  bool get isRejected    => status == 'rejected';

  // ── Firestore deserialisation ───────────────────────────────────────────────

  factory PostModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return PostModel(
      id:            doc.id,
      title:         d['title']          as String?  ?? '',
      description:   d['description']    as String?  ?? '',
      city:          d['city']           as String?  ?? '',
      status:        d['status']         as String?  ?? 'under_review',
      upvotes:       (d['upvotes']       as num?)?.toInt()    ?? 0,
      commentsCount: (d['commentsCount'] as num?)?.toInt()    ?? 0,
      createdAt:     (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      category:      d['category']       as String?,
      authorId:      d['authorId']       as String?,
      authorName:    d['authorName']     as String?,
      lat:           (d['lat']           as num?)?.toDouble(),
      lng:           (d['lng']           as num?)?.toDouble(),
      severity:      (d['severity']      as num?)?.toDouble(),
      rankingScore:  (d['rankingScore']  as num?)?.toDouble(),
      authorityId:   d['authorityId']    as String?,
      mediaUrls:     (d['mediaUrls']     as List?)?.cast<String>() ?? [],
    );
  }

  // ── Hive JSON cache ─────────────────────────────────────────────────────────

  /// Serialise to a plain Map for Hive JSON caching.
  /// Only non-null optional fields are included to minimse storage.
  Map<String, dynamic> toJson() => {
        'id':            id,
        'title':         title,
        'description':   description,
        'city':          city,
        'status':        status,
        'upvotes':       upvotes,
        'commentsCount': commentsCount,
        'createdAt':     createdAt.millisecondsSinceEpoch,
        'mediaUrls':     mediaUrls,
        if (category    != null) 'category':    category,
        if (authorId    != null) 'authorId':    authorId,
        if (authorName  != null) 'authorName':  authorName,
        if (lat         != null) 'lat':         lat,
        if (lng         != null) 'lng':         lng,
        if (severity    != null) 'severity':    severity,
        if (rankingScore!= null) 'rankingScore':rankingScore,
        if (authorityId != null) 'authorityId': authorityId,
      };

  factory PostModel.fromJson(Map<dynamic, dynamic> json) {
    final ms = json['createdAt'] as int? ?? 0;
    return PostModel(
      id:            json['id']            as String?  ?? '',
      title:         json['title']         as String?  ?? '',
      description:   json['description']   as String?  ?? '',
      city:          json['city']          as String?  ?? '',
      status:        json['status']        as String?  ?? 'under_review',
      upvotes:       (json['upvotes']      as num?)?.toInt()    ?? 0,
      commentsCount: (json['commentsCount']as num?)?.toInt()    ?? 0,
      createdAt:     DateTime.fromMillisecondsSinceEpoch(ms),
      category:      json['category']      as String?,
      authorId:      json['authorId']      as String?,
      authorName:    json['authorName']    as String?,
      lat:           (json['lat']          as num?)?.toDouble(),
      lng:           (json['lng']          as num?)?.toDouble(),
      severity:      (json['severity']     as num?)?.toDouble(),
      rankingScore:  (json['rankingScore'] as num?)?.toDouble(),
      authorityId:   json['authorityId']   as String?,
      mediaUrls:     (json['mediaUrls']    as List?)?.cast<String>() ?? [],
    );
  }

  // ── Derived helpers ─────────────────────────────────────────────────────────

  /// Human-readable category label, e.g. 'road_damage' → 'Road Damage'.
  /// O(n) single pass — avoids creating intermediate Lists.
  String get formattedCategory {
    if (category == null) return 'Other';
    return category!
        .split('_')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }
}
