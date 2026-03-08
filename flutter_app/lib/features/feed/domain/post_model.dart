import 'package:cloud_firestore/cloud_firestore.dart';

/// Immutable representation of a civic issue post as returned by Firestore.
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
    this.lat,
    this.lng,
    this.severity,
    this.rankingScore,
    this.authorityId,
    this.mediaUrls = const [],
    this.modStatus,
  });

  final String  id;
  final String  title;
  final String  description;
  final String  city;
  final String  status;
  final int     upvotes;
  final int     commentsCount;
  final DateTime createdAt;

  final String? category;
  final String? authorId;
  final double? lat;
  final double? lng;
  final double? severity;
  final double? rankingScore;
  final String? authorityId;
  final List<String> mediaUrls;
  final String? modStatus;

  factory PostModel.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final d = doc.data() ?? {};
    return PostModel(
      id:            doc.id,
      title:         d['title']         as String? ?? '',
      description:   d['description']   as String? ?? '',
      city:          d['city']          as String? ?? '',
      status:        d['status']        as String? ?? 'under_review',
      upvotes:       (d['upvotes']      as num?)?.toInt()    ?? 0,
      commentsCount: (d['commentsCount'] as num?)?.toInt()   ?? 0,
      createdAt:     (d['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      category:      d['category']      as String?,
      authorId:      d['authorId']      as String?,
      lat:           (d['lat']          as num?)?.toDouble(),
      lng:           (d['lng']          as num?)?.toDouble(),
      severity:      (d['severity']     as num?)?.toDouble(),
      rankingScore:  (d['rankingScore'] as num?)?.toDouble(),
      authorityId:   d['authorityId']   as String?,
      mediaUrls:     (d['mediaUrls']    as List?)?.cast<String>() ?? [],
      modStatus:     d['status']        as String?,
    );
  }

  /// Serialize to a plain Map for Hive JSON caching.
  Map<String, dynamic> toJson() => {
        'id':            id,
        'title':         title,
        'description':   description,
        'city':          city,
        'status':        status,
        'upvotes':       upvotes,
        'commentsCount': commentsCount,
        'createdAt':     createdAt.millisecondsSinceEpoch,
        if (category     != null) 'category':     category,
        if (authorId     != null) 'authorId':     authorId,
        if (lat          != null) 'lat':           lat,
        if (lng          != null) 'lng':           lng,
        if (severity     != null) 'severity':     severity,
        if (rankingScore != null) 'rankingScore': rankingScore,
        if (authorityId  != null) 'authorityId':  authorityId,
        'mediaUrls':     mediaUrls,
        if (modStatus    != null) 'modStatus':    modStatus,
      };

  factory PostModel.fromJson(Map<dynamic, dynamic> json) {
    final ms = json['createdAt'] as int? ?? 0;
    return PostModel(
      id:            json['id']            as String? ?? '',
      title:         json['title']         as String? ?? '',
      description:   json['description']   as String? ?? '',
      city:          json['city']          as String? ?? '',
      status:        json['status']        as String? ?? 'PENDING_MODERATION',
      upvotes:       (json['upvotes']      as num?)?.toInt()    ?? 0,
      commentsCount: (json['commentsCount'] as num?)?.toInt()   ?? 0,
      createdAt:     DateTime.fromMillisecondsSinceEpoch(ms),
      category:      json['category']      as String?,
      authorId:      json['authorId']      as String?,
      lat:           (json['lat']          as num?)?.toDouble(),
      lng:           (json['lng']          as num?)?.toDouble(),
      severity:      (json['severity']     as num?)?.toDouble(),
      rankingScore:  (json['rankingScore'] as num?)?.toDouble(),
      authorityId:   json['authorityId']   as String?,
      mediaUrls:     (json['mediaUrls']    as List?)?.cast<String>() ?? [],
      modStatus:     json['modStatus']     as String?,
    );
  }

  String get formattedCategory {
    if (category == null) return 'Other';
    return category!
        .replaceAll('_', ' ')
        .split(' ')
        .map((w) => w.isEmpty ? w : '${w[0].toUpperCase()}${w.substring(1)}')
        .join(' ');
  }

  bool get isApproved => status == 'under_review';
  bool get isRejected => status == 'rejected';
  bool get isPending  => !isApproved && !isRejected;
}
