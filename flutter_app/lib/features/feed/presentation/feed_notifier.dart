import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import '../../../core/providers/city_provider.dart';
import '../domain/post_model.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Hive cache helpers
// ─────────────────────────────────────────────────────────────────────────────

const _kFeedBox = 'feed_cache';

List<PostModel>? _readCache(String city) {
  if (!Hive.isBoxOpen(_kFeedBox)) return null;
  final box = Hive.box<String>(_kFeedBox);
  final raw = box.get(city);
  if (raw == null) return null;
  try {
    final list = jsonDecode(raw) as List;
    return list.map((e) => PostModel.fromJson(e as Map)).toList();
  } catch (_) {
    return null;
  }
}

Future<void> _writeCache(String city, List<PostModel> posts) async {
  if (!Hive.isBoxOpen(_kFeedBox)) return;
  final box  = Hive.box<String>(_kFeedBox);
  final json = jsonEncode(posts.map((p) => p.toJson()).toList());
  await box.put(city, json);
}

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

class FeedState {
  const FeedState({
    this.posts        = const [],
    this.isLoading    = false,
    this.isRefreshing = false,
    this.errorMessage,
  });

  final List<PostModel> posts;
  final bool    isLoading;
  final bool    isRefreshing;
  final String? errorMessage;

  FeedState copyWith({
    List<PostModel>? posts,
    bool? isLoading,
    bool? isRefreshing,
    Object? errorMessage = _sentinel,
  }) {
    return FeedState(
      posts:        posts        ?? this.posts,
      isLoading:    isLoading    ?? this.isLoading,
      isRefreshing: isRefreshing ?? this.isRefreshing,
      errorMessage: errorMessage == _sentinel
          ? this.errorMessage
          : errorMessage as String?,
    );
  }
}

const _sentinel = Object();

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

/// Watches [selectedCityProvider] and automatically reloads the feed whenever
/// the city changes.  Serves cached data immediately on first build.
class FeedNotifier extends Notifier<FeedState> {
  @override
  FeedState build() {
    // Re-run build() whenever the selected city changes, which resets state
    // and triggers a fresh fetch for the new city.
    final city = ref.watch(selectedCityProvider);

    final cached = _readCache(city);
    if (cached != null && cached.isNotEmpty) {
      Future.microtask(() => _fetchFromFirestore(city, isRefresh: true));
      return FeedState(posts: cached);
    }

    Future.microtask(() => _fetchFromFirestore(city));
    return const FeedState(isLoading: true);
  }

  // ── Public actions ─────────────────────────────────────────────────────────

  Future<void> refresh() {
    final city = ref.read(selectedCityProvider);
    return _fetchFromFirestore(city, isRefresh: true);
  }

  // ── Private ────────────────────────────────────────────────────────────────

  Future<void> _fetchFromFirestore(String city, {bool isRefresh = false}) async {
    state = isRefresh
        ? state.copyWith(isRefreshing: true,  errorMessage: null)
        : state.copyWith(isLoading:    true,   errorMessage: null);

    try {
      final snap = await FirebaseFirestore.instance
          .collection('posts')
          .where('city', isEqualTo: city)
          .where('status', isEqualTo: 'under_review')
          .orderBy('createdAt', descending: true)
          .limit(30)
          .get();

      final posts = snap.docs.map(PostModel.fromFirestore).toList();
      await _writeCache(city, posts);

      state = state.copyWith(
        posts:        posts,
        isLoading:    false,
        isRefreshing: false,
        errorMessage: null,
      );
    } on Exception catch (e) {
      state = state.copyWith(
        isLoading:    false,
        isRefreshing: false,
        errorMessage: 'Could not load feed: $e',
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final feedNotifierProvider =
    NotifierProvider<FeedNotifier, FeedState>(FeedNotifier.new);
