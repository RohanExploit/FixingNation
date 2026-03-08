import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';

import '../../../core/providers/city_provider.dart';
import '../../issue_detail/presentation/issue_detail_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// City centres (lat/lng)
// ─────────────────────────────────────────────────────────────────────────────

const _kCityCentres = {
  'pune':      LatLng(18.5204, 73.8567),
  'mumbai':    LatLng(19.0760, 72.8777),
  'bangalore': LatLng(12.9716, 77.5946),
};

// ─────────────────────────────────────────────────────────────────────────────
// Provider: stream approved posts for the selected city
// ─────────────────────────────────────────────────────────────────────────────

final _mapPostsProvider =
    StreamProvider.family<List<_MapPost>, String>((ref, city) {
  return FirebaseFirestore.instance
      .collection('posts')
      .where('city', isEqualTo: city)
      .where('moderation.status', isEqualTo: 'approved')
      .limit(100)
      .snapshots()
      .map((snap) => snap.docs
          .map((doc) {
            final d   = doc.data();
            final lat = (d['lat'] as num?)?.toDouble();
            final lng = (d['lng'] as num?)?.toDouble();
            if (lat == null || lng == null) return null;
            return _MapPost(
              id:       doc.id,
              title:    d['title']    as String? ?? '',
              category: d['category'] as String?,
              severity: (d['severity'] as num?)?.toDouble() ?? 0.5,
              lat:      lat,
              lng:      lng,
            );
          })
          .whereType<_MapPost>()
          .toList());
});

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

class MapPage extends ConsumerStatefulWidget {
  const MapPage({super.key});

  @override
  ConsumerState<MapPage> createState() => _MapPageState();
}

class _MapPageState extends ConsumerState<MapPage> {
  late final MapController _mapController;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final city      = ref.watch(selectedCityProvider);
    final postsAsync = ref.watch(_mapPostsProvider(city));
    final centre     = _kCityCentres[city] ?? const LatLng(18.5204, 73.8567);

    // Move map when city changes.
    ref.listen(selectedCityProvider, (_, next) {
      final c = _kCityCentres[next];
      if (c != null) _mapController.move(c, 12);
    });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Map'),
        centerTitle: false,
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: DropdownButton<String>(
              value:        city,
              underline:    const SizedBox.shrink(),
              borderRadius: BorderRadius.circular(12),
              items: _kCityCentres.keys
                  .map((c) => DropdownMenuItem(
                        value: c,
                        child: Text(
                          '${c[0].toUpperCase()}${c.substring(1)}',
                          style: const TextStyle(fontSize: 14),
                        ),
                      ))
                  .toList(),
              onChanged: (v) {
                if (v != null) ref.read(selectedCityProvider.notifier).state = v;
              },
            ),
          ),
        ],
      ),
      body: Stack(
        children: [
          FlutterMap(
            mapController: _mapController,
            options: MapOptions(
              initialCenter: centre,
              initialZoom:   12,
              maxZoom:       18,
              minZoom:       5,
            ),
            children: [
              // ── OSM tile layer ──────────────────────────────────────────
              TileLayer(
                urlTemplate:        'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'com.fixingnation.civicpulse',
                maxZoom:            19,
              ),

              // ── Issue markers ────────────────────────────────────────────
              postsAsync.when(
                loading: () => const MarkerLayer(markers: []),
                error:   (_, __) => const MarkerLayer(markers: []),
                data:    (posts) => MarkerLayer(
                  markers: posts.map((p) => _buildMarker(context, p)).toList(),
                ),
              ),
            ],
          ),

          // ── Loading overlay ───────────────────────────────────────────────
          if (postsAsync.isLoading)
            const Positioned(
              top: 0, left: 0, right: 0,
              child: LinearProgressIndicator(),
            ),

          // ── Post count badge ──────────────────────────────────────────────
          postsAsync.when(
            loading: () => const SizedBox.shrink(),
            error:   (_, __) => const SizedBox.shrink(),
            data: (posts) => Positioned(
              bottom: 16,
              left:   16,
              child: _CountBadge(count: posts.length),
            ),
          ),
        ],
      ),
    );
  }

  Marker _buildMarker(BuildContext context, _MapPost post) {
    final cs    = Theme.of(context).colorScheme;
    final Color color;
    if (post.severity >= 0.7)      color = cs.error;
    else if (post.severity >= 0.4) color = Colors.orange;
    else                           color = cs.primary;

    return Marker(
      point:  LatLng(post.lat, post.lng),
      width:  36,
      height: 36,
      child: GestureDetector(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => IssueDetailPage(postId: post.id),
          ),
        ),
        child: Tooltip(
          message: post.title,
          child: Container(
            decoration: BoxDecoration(
              color:  color,
              shape:  BoxShape.circle,
              border: Border.all(color: Colors.white, width: 2),
              boxShadow: [
                BoxShadow(
                  color:      Colors.black.withValues(alpha: 0.3),
                  blurRadius: 4,
                  offset:     const Offset(0, 2),
                ),
              ],
            ),
            child: const Icon(Icons.warning_rounded, color: Colors.white, size: 18),
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _CountBadge extends StatelessWidget {
  const _CountBadge({required this.count});
  final int count;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
      decoration: BoxDecoration(
        color:        cs.surfaceContainerHigh.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color:      Colors.black.withValues(alpha: 0.15),
            blurRadius: 6,
            offset:     const Offset(0, 2),
          ),
        ],
      ),
      child: Text(
        '$count issue${count == 1 ? '' : 's'} in view',
        style: TextStyle(
          fontSize:   13,
          fontWeight: FontWeight.w500,
          color:      cs.onSurface,
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Internal data class
// ─────────────────────────────────────────────────────────────────────────────

class _MapPost {
  const _MapPost({
    required this.id,
    required this.title,
    required this.lat,
    required this.lng,
    required this.severity,
    this.category,
  });

  final String  id;
  final String  title;
  final double  lat;
  final double  lng;
  final double  severity;
  final String? category;
}
