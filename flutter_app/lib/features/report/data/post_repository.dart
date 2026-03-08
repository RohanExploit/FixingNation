import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../../services/telegram_service.dart';

// AI classification is disabled — category comes from user input.
// The worker and AiService are intentionally not called here.

/// Handles all Firestore read/write operations for civic issue posts.
///
/// Submission flow (no AI):
///   1. User fills form with category, title, description, location, optional image
///   2. Image uploaded to Firebase Storage (if provided)
///   3. Post written to Firestore with status = 'under_review'
///   4. Post immediately appears in the feed
class PostRepository {
  PostRepository({
    FirebaseFirestore? db,
    FirebaseAuth? auth,
  })  : _db   = db   ?? FirebaseFirestore.instance,
        _auth = auth ?? FirebaseAuth.instance;

  final FirebaseFirestore _db;
  final FirebaseAuth _auth;

  // ── Post creation ──────────────────────────────────────────────────────────

  /// Write a new civic issue post directly to Firestore.
  ///
  /// Returns the Firestore document ID on success.
  Future<String> createPost({
    required String title,
    required String description,
    required String category,
    required double lat,
    required double lng,
    required String geohash,
    required String city,
    List<String> mediaUrls = const [],
  }) async {
    final user = _auth.currentUser;
    if (user == null) throw Exception('Must be signed in to create a post.');

    if (category.isEmpty) throw Exception('Category is required.');
    if (description.trim().isEmpty) throw Exception('Description is required.');

    final docRef = await _db.collection('posts').add({
      'authorId':      user.uid,
      'title':         title.trim(),
      'description':   description.trim(),
      'category':      category,
      'lat':           lat,
      'lng':           lng,
      'geohash':       geohash,
      'city':          city,
      'mediaUrls':     mediaUrls,
      'status':        'under_review',
      'upvotes':       0,
      'commentsCount': 0,
      'sharesCount':   0,
      'createdAt':     FieldValue.serverTimestamp(),
      'updatedAt':     FieldValue.serverTimestamp(),
    }).timeout(
      const Duration(seconds: 15),
      onTimeout: () => throw Exception('Connection timed out. Check your internet.'),
    );

    // Notify Telegram — fire-and-forget, never blocks the return.
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
        .limit(20);
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
      'authorId':  user.uid,
      'text':      text.trim(),
      'createdAt': FieldValue.serverTimestamp(),
    });
    batch.update(postRef, {
      'commentsCount': FieldValue.increment(1),
      'updatedAt':     FieldValue.serverTimestamp(),
    });

    await batch.commit();
  }

  // ── Image upload ───────────────────────────────────────────────────────────

  /// Upload [file] to Firebase Storage and return its download URL.
  /// Returns null on failure — post is still created without media.
  Future<String?> uploadImage(XFile file) async {
    try {
      final uid       = _auth.currentUser?.uid ?? 'anonymous';
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final ref       = FirebaseStorage.instance.ref('posts/$uid/$timestamp.jpg');

      final bytes = await File(file.path).readAsBytes();
      await ref.putData(bytes, SettableMetadata(contentType: 'image/jpeg'));
      return await ref.getDownloadURL();
    } on Exception catch (e) {
      debugPrint('[PostRepository] Image upload failed: $e');
      return null;
    }
  }
}

// ── Riverpod provider ─────────────────────────────────────────────────────────

final postRepositoryProvider = Provider<PostRepository>(
  (_) => PostRepository(),
);
