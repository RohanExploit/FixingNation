import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';
import 'package:image_picker/image_picker.dart';

import '../../../core/utils/geohash.dart';
import '../data/post_repository.dart';

// ─────────────────────────────────────────────────────────────────────────────
// State
// ─────────────────────────────────────────────────────────────────────────────

enum ReportStatus { idle, locating, submitting, success }

@immutable
class ReportFormState {
  const ReportFormState({
    this.title = '',
    this.description = '',
    this.category,
    this.city,
    this.imageFile,
    this.lat,
    this.lng,
    this.status = ReportStatus.idle,
    this.submittedPostId,
    this.errorMessage,
  });

  final String title;
  final String description;

  /// Selected category hint — nullable because the user may leave it blank
  /// (the AI will classify automatically).
  final String? category;

  /// City selected by the user — required for authority routing.
  final String? city;

  /// Image picked from camera or gallery.
  final XFile? imageFile;

  /// GPS coordinates — null until the user taps "Detect Location".
  final double? lat;
  final double? lng;

  final ReportStatus status;

  /// Populated when [status] transitions to [ReportStatus.success].
  final String? submittedPostId;

  /// Non-null when a recoverable error occurred (location denied, network, etc.).
  final String? errorMessage;

  // ── Derived ────────────────────────────────────────────────────────────────

  bool get hasLocation => lat != null && lng != null;
  bool get isLocating   => status == ReportStatus.locating;
  bool get isSubmitting => status == ReportStatus.submitting;
  bool get isSuccess    => status == ReportStatus.success;

  /// True when the minimum required fields are filled.
  bool get canSubmit =>
      title.trim().isNotEmpty &&
      description.trim().isNotEmpty &&
      category != null &&
      hasLocation &&
      city != null &&
      status == ReportStatus.idle;

  // ── copyWith ───────────────────────────────────────────────────────────────

  ReportFormState copyWith({
    String? title,
    String? description,
    Object? category = _sentinel,
    Object? city = _sentinel,
    Object? imageFile = _sentinel,
    Object? lat = _sentinel,
    Object? lng = _sentinel,
    ReportStatus? status,
    Object? submittedPostId = _sentinel,
    Object? errorMessage = _sentinel,
  }) {
    return ReportFormState(
      title:           title           ?? this.title,
      description:     description     ?? this.description,
      category:        category        == _sentinel ? this.category        : category as String?,
      city:            city            == _sentinel ? this.city            : city as String?,
      imageFile:       imageFile       == _sentinel ? this.imageFile       : imageFile as XFile?,
      lat:             lat             == _sentinel ? this.lat             : lat as double?,
      lng:             lng             == _sentinel ? this.lng             : lng as double?,
      status:          status          ?? this.status,
      submittedPostId: submittedPostId == _sentinel ? this.submittedPostId : submittedPostId as String?,
      errorMessage:    errorMessage    == _sentinel ? this.errorMessage    : errorMessage as String?,
    );
  }
}

// Sentinel used by copyWith so that nullable fields can be explicitly cleared.
const _sentinel = Object();

// ─────────────────────────────────────────────────────────────────────────────
// Notifier
// ─────────────────────────────────────────────────────────────────────────────

class ReportNotifier extends Notifier<ReportFormState> {
  @override
  ReportFormState build() => const ReportFormState();

  // ── Field updates ──────────────────────────────────────────────────────────

  void updateTitle(String v) =>
      state = state.copyWith(title: v, errorMessage: null);

  void updateDescription(String v) =>
      state = state.copyWith(description: v, errorMessage: null);

  void updateCategory(String? v) =>
      state = state.copyWith(category: v, errorMessage: null);

  void updateCity(String? v) =>
      state = state.copyWith(city: v, errorMessage: null);

  void clearImage() =>
      state = state.copyWith(imageFile: null);

  // ── Image picking ──────────────────────────────────────────────────────────

  /// Pick an image from [source] (gallery or camera).
  ///
  /// image_picker handles basic size reduction via maxWidth/maxHeight and
  /// imageQuality, keeping uploads well under the 2 MB Storage rule.
  Future<void> pickImage(ImageSource source) async {
    final picker = ImagePicker();
    try {
      final file = await picker.pickImage(
        source:       source,
        maxWidth:     1024,
        maxHeight:    1024,
        imageQuality: 80,
      );
      state = state.copyWith(imageFile: file, errorMessage: null);
    } on Exception catch (e) {
      state = state.copyWith(errorMessage: 'Could not pick image: $e');
    }
  }

  // ── Location ───────────────────────────────────────────────────────────────

  /// Request GPS permission (if needed) and fetch the current position.
  Future<void> detectLocation() async {
    state = state.copyWith(status: ReportStatus.locating, errorMessage: null);

    try {
      // Check / request permission.
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
      }
      if (permission == LocationPermission.denied ||
          permission == LocationPermission.deniedForever) {
        state = state.copyWith(
          status:       ReportStatus.idle,
          errorMessage: 'Location permission denied. '
                        'Enable it in device settings to use GPS.',
        );
        return;
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
        ),
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () => throw Exception('GPS timed out. Try again.'),
      );

      state = state.copyWith(
        lat:    position.latitude,
        lng:    position.longitude,
        status: ReportStatus.idle,
        errorMessage: null,
      );
    } on Exception catch (e) {
      state = state.copyWith(
        status:       ReportStatus.idle,
        errorMessage: e.toString().replaceFirst('Exception: ', ''),
      );
    }
  }

  // ── Submission ─────────────────────────────────────────────────────────────

  /// Upload image (if any), write the post to Firestore, and trigger the
  /// Worker classification in the background.
  ///
  /// On success, [state.submittedPostId] is populated and the UI navigates
  /// to IssueDetailPage by watching [state.isSuccess].
  Future<void> submit() async {
    if (!state.canSubmit) return;

    state = state.copyWith(status: ReportStatus.submitting, errorMessage: null);

    try {
      final repo    = ref.read(postRepositoryProvider);
      final geohash = GeoHash.encode(state.lat!, state.lng!);

      // Upload image if provided (non-blocking failure — post still saves).
      final List<String> mediaUrls = [];
      if (state.imageFile != null) {
        final url = await repo.uploadImage(state.imageFile!);
        if (url != null) mediaUrls.add(url);
      }

      // Write post directly — no AI classification.
      final postId = await repo.createPost(
        title:       state.title.trim(),
        description: state.description.trim(),
        category:    state.category!,
        lat:         state.lat!,
        lng:         state.lng!,
        geohash:     geohash,
        city:        state.city!,
        mediaUrls:   mediaUrls,
      );

      state = state.copyWith(
        status:          ReportStatus.success,
        submittedPostId: postId,
        errorMessage:    null,
      );
    } on Exception catch (e) {
      state = state.copyWith(
        status:       ReportStatus.idle,
        errorMessage: 'Submission failed: ${e.toString().replaceFirst('Exception: ', '')}',
      );
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final reportNotifierProvider =
    NotifierProvider<ReportNotifier, ReportFormState>(ReportNotifier.new);
