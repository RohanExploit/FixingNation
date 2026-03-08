import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/providers/city_provider.dart';
import '../../issue_detail/presentation/issue_detail_page.dart';
import '../domain/post_model.dart';
import 'feed_notifier.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

class FeedPage extends ConsumerWidget {
  const FeedPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final city     = ref.watch(selectedCityProvider);
    final feedState = ref.watch(feedNotifierProvider);
    final notifier  = ref.read(feedNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('CivicPulse'),
        centerTitle: false,
        actions: [
          // ── City picker ─────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: DropdownButton<String>(
              value:         city,
              underline:     const SizedBox.shrink(),
              borderRadius:  BorderRadius.circular(12),
              items: kSupportedCities
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
      body: _FeedBody(
        state:    feedState,
        onRefresh: notifier.refresh,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Feed body
// ─────────────────────────────────────────────────────────────────────────────

class _FeedBody extends StatelessWidget {
  const _FeedBody({required this.state, required this.onRefresh});

  final FeedState       state;
  final Future<void> Function() onRefresh;

  @override
  Widget build(BuildContext context) {
    if (state.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (state.posts.isEmpty) {
      return _EmptyView(
        message: state.errorMessage ?? 'No approved issues yet in this city.',
        onRetry: onRefresh,
      );
    }

    return RefreshIndicator(
      onRefresh: onRefresh,
      child: Stack(
        children: [
          ListView.separated(
            padding:           const EdgeInsets.symmetric(vertical: 8),
            itemCount:         state.posts.length,
            separatorBuilder:  (_, __) => const SizedBox(height: 0),
            itemBuilder:       (ctx, i) => _IssueCard(post: state.posts[i]),
          ),
          if (state.isRefreshing)
            const Positioned(
              top:   0,
              left:  0,
              right: 0,
              child: LinearProgressIndicator(),
            ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Issue card
// ─────────────────────────────────────────────────────────────────────────────

class _IssueCard extends StatelessWidget {
  const _IssueCard({required this.post});

  final PostModel post;

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final tt   = Theme.of(context).textTheme;
    final hasImg = post.mediaUrls.isNotEmpty;

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: () => Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => IssueDetailPage(postId: post.id),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Thumbnail ────────────────────────────────────────────────
            if (hasImg)
              CachedNetworkImage(
                imageUrl:    post.mediaUrls.first,
                height:      180,
                width:       double.infinity,
                fit:         BoxFit.cover,
                placeholder: (_, __) => Container(
                  height: 180,
                  color:  cs.surfaceContainerHighest,
                  child:  const Center(child: CircularProgressIndicator()),
                ),
                errorWidget: (_, __, ___) => const SizedBox.shrink(),
              ),

            Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Category chip ───────────────────────────────────────
                  if (post.category != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 6),
                      child: _CategoryChip(label: post.formattedCategory),
                    ),

                  // ── Title ────────────────────────────────────────────────
                  Text(
                    post.title,
                    style: tt.titleMedium?.copyWith(fontWeight: FontWeight.w600),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),

                  // ── Description ──────────────────────────────────────────
                  Text(
                    post.description,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 12),

                  // ── Bottom row ───────────────────────────────────────────
                  Row(
                    children: [
                      Icon(Icons.thumb_up_outlined,
                          size: 15, color: cs.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text('${post.upvotes}',
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      const SizedBox(width: 16),
                      Icon(Icons.comment_outlined,
                          size: 15, color: cs.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text('${post.commentsCount}',
                          style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      const Spacer(),
                      if (post.severity != null)
                        _SeverityDot(severity: post.severity!),
                      const SizedBox(width: 8),
                      Text(
                        _timeAgo(post.createdAt),
                        style: tt.bodySmall?.copyWith(color: cs.outline),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 60)  return '${diff.inMinutes}m ago';
    if (diff.inHours   < 24)  return '${diff.inHours}h ago';
    if (diff.inDays    < 30)  return '${diff.inDays}d ago';
    return '${(diff.inDays / 30).floor()}mo ago';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _CategoryChip extends StatelessWidget {
  const _CategoryChip({required this.label});
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color:        cs.primaryContainer,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontSize: 11,
          color:    cs.onPrimaryContainer,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

class _SeverityDot extends StatelessWidget {
  const _SeverityDot({required this.severity});
  final double severity;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final Color color;
    if (severity >= 0.7)      color = cs.error;
    else if (severity >= 0.4) color = Colors.orange;
    else                      color = Colors.green;

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 4),
        Text(
          'S${(severity * 10).toStringAsFixed(1)}',
          style: TextStyle(fontSize: 11, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

class _EmptyView extends StatelessWidget {
  const _EmptyView({required this.message, required this.onRetry});

  final String               message;
  final Future<void> Function() onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inbox_outlined,
                size: 64,
                color: Theme.of(context).colorScheme.outline),
            const SizedBox(height: 16),
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 24),
            OutlinedButton.icon(
              onPressed: onRetry,
              icon:  const Icon(Icons.refresh),
              label: const Text('Retry'),
            ),
          ],
        ),
      ),
    );
  }
}
