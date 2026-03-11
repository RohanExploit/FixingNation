import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../services/telegram_service.dart';

// AI classification is disabled — category comes from user input.

/// Handles all Firestore read/write operations for civic issue posts.
///
/// Submission flow (no AI):
///   1. User fills form with category, title, description, location, optional image
///   2. Image compressed to ≤ 200 KB, then uploaded to Firebase Storage
///   3. Post written to Firestore with status = 'under_review'
///   4. Idempotency key stored on the doc — duplicate calls are safe
class PostRepository {
  PostRepository({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
  })  : _db   = db   ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  // ── Target compression thresholds ─────────────────────────────────────────
  static const _maxImageBytes = 200 * 1024; // 200 KB hard cap
  static const _targetWidth   = 1080;        // px — enough for phone screens
  static const _targetQuality = 80;          // JPEG quality 0-100

  // ── Post creation ──────────────────────────────────────────────────────────

  /// Write a new civic issue post directly to Firestore.
  ///
  /// [idempotencyKey] is a UUID generated client-side at form-open time.
  /// Re-submitting with the same key is safe — Firestore's set-with-merge
  /// is idempotent because the data is identical each time.
  /// Returns the Firestore document ID on success.
  Future<String> createPost({
    required String title,
    required String description,
    required String category,
    required double lat,
    required double lng,
    required String geohash,
    required String city,
    required String idempotencyKey,
    List<String> mediaUrls = const [],
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Must be signed in to create a post.');
    if (category.isEmpty)              throw Exception('Category is required.');
    if (description.trim().isEmpty)    throw Exception('Description is required.');

    // Use idempotencyKey as the doc ID → re-submission = overwrite, not duplicate.
    final docRef = _db.collection('posts').doc(idempotencyKey);

    await docRef.set({
      'authorId':       user.uid,
      'authorName':     user.displayName ?? 'Anonymous',
      'title':          title.trim(),
      'description':    description.trim(),
      'category':       category,
      'lat':            lat,
      'lng':            lng,
      'geohash':        geohash,
      'city':           city,
      'mediaUrls':      mediaUrls,
      'status':         'under_review',
      'upvotes':        0,
      'commentsCount':  0,
      'sharesCount':    0,
      'createdAt':      FieldValue.serverTimestamp(),
      'updatedAt':      FieldValue.serverTimestamp(),
    }, SetOptions(merge: false)).timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw Exception('Connection timed out. Check your internet.'),
    );

    // Notify Telegram — fire-and-forget, never blocks return.
    TelegramService.notifyNewIssue(
      title:       title,
      category:    category,
      city:        city,
      description: description,
      lat:         lat,
      lng:         lng,
      postId:      docRef.id,
    );

    return docRef.id;
  }

  // ── Feed queries ───────────────────────────────────────────────────────────

  /// Posts with status 'under_review' for a given city, newest first.
  Query<Map<String, dynamic>> feedQuery(String city) {
    return _db
        .collection('posts')
        .where('city', isEqualTo: city)
        .where('status', isEqualTo: 'under_review')
        .orderBy('createdAt', descending: true)
        .limit(30);
  }

  /// All posts by the current user, newest first.
  Query<Map<String, dynamic>>? myPostsQuery() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return null;
    return _db
        .collection('posts')
        .where('authorId', isEqualTo: uid)
        .orderBy('createdAt', descending: true)
        .limit(50);
  }

  // ── Comment creation ───────────────────────────────────────────────────────

  Future<void> addComment({
    required String postId,
    required String text,
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Must be signed in to comment.');

    final postRef    = _db.collection('posts').doc(postId);
    final commentRef = postRef.collection('comments').doc();

    final batch = _db.batch();
    batch.set(commentRef, {
      'authorId':   user.uid,
      'authorName': user.displayName ?? 'Anonymous',
      'text':       text.trim(),
      'createdAt':  FieldValue.serverTimestamp(),
    });
    batch.update(postRef, {
      'commentsCount': FieldValue.increment(1),
      'updatedAt':     FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  // ── Image upload with aggressive compression ───────────────────────────────

  /// Compress [file] to ≤ [_maxImageBytes] then upload to Firebase Storage.
  ///
  /// Compression pipeline:
  ///   1. flutter_image_compress: resize to [_targetWidth]px wide, JPEG quality [_targetQuality]
  ///   2. If still > 200 KB, retry at quality 60
  ///   3. If still > 200 KB, retry at quality 40 (minimum acceptable)
  ///
  /// Returns the download URL on success, null on failure.
  /// The post is still created even if image upload fails.
  Future<String?> uploadImage(XFile file) async {
    try {
      final uid       = _auth.currentUser?.uid ?? 'anonymous';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final storageRef = FirebaseStorage.instance
          .ref('posts/$uid/$timestamp.jpg');

      // ── Compress ──────────────────────────────────────────────────────────
      Uint8List? compressed = await _compressImage(file.path, _targetQuality);
      if (compressed == null) return null;

      // Retry at lower quality if still too large.
      if (compressed.length > _maxImageBytes) {
        compressed = await _compressImage(file.path, 60) ?? compressed;
      }
      if (compressed.length > _maxImageBytes) {
        compressed = await _compressImage(file.path, 40) ?? compressed;
      }

      debugPrint(
        '[PostRepository] Uploading image: '
        '${(compressed.length / 1024).toStringAsFixed(1)} KB',
      );

      await storageRef.putData(
        compressed,
        SettableMetadata(contentType: 'image/jpeg'),
      );
      return await storageRef.getDownloadURL();
    } on Exception catch (e) {
      debugPrint('[PostRepository] Image upload failed: $e');
      return null;
    }
  }

  Future<Uint8List?> _compressImage(String path, int quality) async {
    try {
      return await FlutterImageCompress.compressWithFile(
        path,
        minWidth:  _targetWidth,
        minHeight: 1,           // unconstrained height — respects aspect ratio
        quality:   quality,
        format:    CompressFormat.jpeg,
      );
    } on Exception catch (e) {
      debugPrint('[PostRepository] Compression error: $e');
      return null;
    }
  }
}

// ── Riverpod provider ──────────────────────────────────────────────────────────

final postRepositoryProvider = Provider<PostRepository>(
  (_) => PostRepository(),
);
