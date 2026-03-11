import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Provider
// ─────────────────────────────────────────────────────────────────────────────

final _postStreamProvider = StreamProvider.family<Map<String, dynamic>?, String>(
  (ref, postId) => FirebaseFirestore.instance
      .collection('posts')
      .doc(postId)
      .snapshots()
      .map((snap) => snap.data()),
);

final _commentsProvider = StreamProvider.family<List<Map<String, dynamic>>, String>(
  (ref, postId) => FirebaseFirestore.instance
      .collection('posts')
      .doc(postId)
      .collection('comments')
      .orderBy('createdAt', descending: false)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => {'id': d.id, ...d.data()}).toList()),
);

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

class IssueDetailPage extends ConsumerWidget {
  const IssueDetailPage({super.key, required this.postId});

  final String postId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final postAsync = ref.watch(_postStreamProvider(postId));

    return Scaffold(
      appBar: AppBar(
        title: const Text('Issue Detail'),
        centerTitle: true,
        actions: [
          // ── Upvote ─────────────────────────────────────────────────────
          postAsync.when(
            loading: () => const SizedBox.shrink(),
            error:   (_, __) => const SizedBox.shrink(),
            data: (post) => _UpvoteButton(
              postId:  postId,
              upvotes: (post?['upvotes'] as num?)?.toInt() ?? 0,
            ),
          ),
          // ── Share ──────────────────────────────────────────────────────
          postAsync.when(
            loading: () => const SizedBox.shrink(),
            error:   (_, __) => const SizedBox.shrink(),
            data: (post) => IconButton(
              icon:    const Icon(Icons.share_outlined),
              tooltip: 'Share',
              onPressed: post == null ? null : () => _share(context, post),
            ),
          ),
        ],
      ),
      body: postAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error:   (e, _) => _ErrorView(message: e.toString()),
        data: (post) {
          if (post == null) {
            return const _ErrorView(message: 'Issue not found.');
          }
          return _PostBody(post: post, postId: postId, ref: ref);
        },
      ),
    );
  }

  void _share(BuildContext context, Map<String, dynamic> post) {
    final title  = post['title'] as String? ?? 'Civic Issue';
    final city   = post['city']  as String? ?? '';
    final text   = 'CivicPulse — $title\nCity: $city\nPost ID: $postId';
    Clipboard.setData(ClipboardData(text: text));
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('Issue details copied to clipboard.')),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Upvote button (stateful so it shows a quick optimistic increment)
// ─────────────────────────────────────────────────────────────────────────────

class _UpvoteButton extends StatefulWidget {
  const _UpvoteButton({required this.postId, required this.upvotes});

  final String postId;
  final int    upvotes;

  @override
  State<_UpvoteButton> createState() => _UpvoteButtonState();
}

class _UpvoteButtonState extends State<_UpvoteButton> {
  static const _kBox = 'upvoted_posts';

  bool _voted = false;

  @override
  void initState() {
    super.initState();
    // Restore voted state from Hive — persists across app restarts.
    if (Hive.isBoxOpen(_kBox)) {
      final box = Hive.box<bool>(_kBox);
      _voted = box.get(widget.postId, defaultValue: false)!;
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return TextButton.icon(
      onPressed: _voted ? null : _upvote,
      icon: Icon(
        _voted ? Icons.thumb_up : Icons.thumb_up_outlined,
        size: 18,
        color: _voted ? cs.primary : null,
      ),
      label: Text(
        '${widget.upvotes + (_voted ? 1 : 0)}',
        style: TextStyle(color: _voted ? cs.primary : cs.onSurfaceVariant),
      ),
    );
  }

  Future<void> _upvote() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // Optimistic update + persist immediately.
    setState(() => _voted = true);
    if (Hive.isBoxOpen(_kBox)) {
      await Hive.box<bool>(_kBox).put(widget.postId, true);
    }

    try {
      await FirebaseFirestore.instance
          .collection('posts')
          .doc(widget.postId)
          .update({
        'upvotes':   FieldValue.increment(1),
        'updatedAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {
      // Revert both UI and Hive on failure.
      if (mounted) setState(() => _voted = false);
      if (Hive.isBoxOpen(_kBox)) {
        await Hive.box<bool>(_kBox).delete(widget.postId);
      }
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Post body
// ─────────────────────────────────────────────────────────────────────────────

class _PostBody extends StatelessWidget {
  const _PostBody({
    required this.post,
    required this.postId,
    required this.ref,
  });

  final Map<String, dynamic> post;
  final String postId;
  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final status     = post['status']      as String? ?? 'under_review';
    final title      = post['title']       as String? ?? '—';
    final description= post['description'] as String? ?? '—';
    final category   = post['category']    as String?;
    final city       = post['city']        as String? ?? '—';
    final mediaUrls  = (post['mediaUrls']  as List?)?.cast<String>() ?? [];
    final severity   = (post['severity']   as num?)?.toDouble();
    final authority  = post['authorityId'] as String?;

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        // ── Status banner ────────────────────────────────────────────────
        _StatusBanner(postStatus: status),
        const SizedBox(height: 20),

        // ── Photo ────────────────────────────────────────────────────────
        if (mediaUrls.isNotEmpty) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.network(
              mediaUrls.first,
              height:      220,
              width:       double.infinity,
              fit:         BoxFit.cover,
              loadingBuilder: (_, child, progress) => progress == null
                  ? child
                  : const SizedBox(
                      height: 220,
                      child: Center(child: CircularProgressIndicator()),
                    ),
              errorBuilder: (_, __, ___) => const SizedBox.shrink(),
            ),
          ),
          const SizedBox(height: 16),
        ],

        // ── Title ────────────────────────────────────────────────────────
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),

        // ── Meta row ─────────────────────────────────────────────────────
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: [
            if (category != null)
              _Chip(icon: Icons.category, label: _formatCategory(category)),
            _Chip(icon: Icons.location_city, label: city),
            if (severity != null)
              _Chip(
                icon:  Icons.warning_amber,
                label: 'Severity ${(severity * 10).toStringAsFixed(1)}/10',
              ),
          ],
        ),
        const SizedBox(height: 16),

        // ── Description ──────────────────────────────────────────────────
        Text(
          'Description',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
        const SizedBox(height: 4),
        Text(description, style: Theme.of(context).textTheme.bodyMedium),
        const SizedBox(height: 16),

        // ── Authority ────────────────────────────────────────────────────
        if (authority != null && authority != 'unmapped_city_authority') ...[
          Text(
            'Assigned to',
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                ),
          ),
          const SizedBox(height: 4),
          Text(
            authority.replaceAll('_', ' ').toUpperCase(),
            style: Theme.of(context).textTheme.bodyMedium,
          ),
          const SizedBox(height: 16),
        ],

        // ── Comments ─────────────────────────────────────────────────────
        const Divider(),
        const SizedBox(height: 8),
        Text(
          'Comments',
          style: Theme.of(context).textTheme.titleSmall?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
        const SizedBox(height: 8),
        _CommentsSection(postId: postId, ref: ref),
        const SizedBox(height: 24),

        // ── Post ID ──────────────────────────────────────────────────────
        Text(
          'Post ID: $postId',
          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
        ),
      ],
    );
  }

  String _formatCategory(String raw) => raw
      .replaceAll('_', ' ')
      .split(' ')
      .map((w) => '${w[0].toUpperCase()}${w.substring(1)}')
      .join(' ');
}

// ─────────────────────────────────────────────────────────────────────────────
// Comments section
// ─────────────────────────────────────────────────────────────────────────────

class _CommentsSection extends StatefulWidget {
  const _CommentsSection({required this.postId, required this.ref});

  final String  postId;
  final WidgetRef ref;

  @override
  State<_CommentsSection> createState() => _CommentsSectionState();
}

class _CommentsSectionState extends State<_CommentsSection> {
  final _ctrl       = TextEditingController();
  bool  _submitting = false;

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final commentsAsync = widget.ref.watch(_commentsProvider(widget.postId));
    final cs = Theme.of(context).colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── Comment list ─────────────────────────────────────────────────
        commentsAsync.when(
          loading: () => const Center(
            child: Padding(
              padding: EdgeInsets.all(16),
              child: CircularProgressIndicator(),
            ),
          ),
          error: (e, _) => Text('Error loading comments: $e'),
          data: (comments) => comments.isEmpty
              ? Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8),
                  child: Text(
                    'No comments yet. Be the first!',
                    style: TextStyle(color: cs.onSurfaceVariant, fontSize: 13),
                  ),
                )
              : Column(
                  children: comments.map((c) => _CommentTile(comment: c)).toList(),
                ),
        ),

        const SizedBox(height: 12),

        // ── Comment input ────────────────────────────────────────────────
        if (FirebaseAuth.instance.currentUser != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  controller: _ctrl,
                  minLines:   1,
                  maxLines:   3,
                  maxLength:  300,
                  decoration: InputDecoration(
                    hintText: 'Add a comment…',
                    border:   OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical:   10,
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _submitting ? null : _postComment,
                icon: _submitting
                    ? const SizedBox.square(
                        dimension: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.send),
              ),
            ],
          ),
      ],
    );
  }

  Future<void> _postComment() async {
    final text = _ctrl.text.trim();
    if (text.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _submitting = true);
    try {
      final postRef    = FirebaseFirestore.instance.collection('posts').doc(widget.postId);
      final commentRef = postRef.collection('comments').doc();
      final batch      = FirebaseFirestore.instance.batch();

      batch.set(commentRef, {
        'authorId':   user.uid,
        'authorName': user.displayName ?? 'Anonymous',
        'text':       text,
        'createdAt':  FieldValue.serverTimestamp(),
      });
      batch.update(postRef, {
        'commentsCount': FieldValue.increment(1),
        'updatedAt':     FieldValue.serverTimestamp(),
      });

      await batch.commit();
    } catch (e) {
      if (mounted) {
        setState(() => _submitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to post comment. Check your connection and try again.'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } finally {
      _ctrl.clear();
      if (mounted) {
        FocusScope.of(context).unfocus();
        setState(() => _submitting = false);
      }
    }
  }
}

class _CommentTile extends StatelessWidget {
  const _CommentTile({required this.comment});
  final Map<String, dynamic> comment;

  @override
  Widget build(BuildContext context) {
    final cs   = Theme.of(context).colorScheme;
    final name = comment['authorName'] as String? ?? 'Anonymous';
    final text = comment['text']       as String? ?? '';
    final ts   = comment['createdAt']  as Timestamp?;
    final time = ts != null ? _timeAgo(ts.toDate()) : '';

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          CircleAvatar(
            radius:          16,
            backgroundColor: cs.secondaryContainer,
            child: Text(
              name.isNotEmpty ? name[0].toUpperCase() : '?',
              style: TextStyle(
                fontSize: 12,
                color:    cs.onSecondaryContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(
                      name,
                      style: Theme.of(context)
                          .textTheme
                          .bodySmall
                          ?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const Spacer(),
                    Text(
                      time,
                      style: TextStyle(fontSize: 11, color: cs.outline),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                Text(text, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _timeAgo(DateTime dt) {
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1)  return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours   < 24) return '${diff.inHours}h ago';
    return '${diff.inDays}d ago';
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Status banner
// ─────────────────────────────────────────────────────────────────────────────

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({required this.postStatus});

  final String  postStatus;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final isPending  = postStatus == 'under_review';
    final isRejected = postStatus == 'rejected';
    final isResolved = postStatus == 'resolved';

    final Color bg;
    final Color fg;
    final IconData icon;
    final String title;
    final String subtitle;

    if (isPending) {
      bg       = cs.secondaryContainer;
      fg       = cs.onSecondaryContainer;
      icon     = Icons.hourglass_top;
      title    = 'Under Review';
      subtitle = 'Your report is live in the community feed and is under review by the team.';
    } else if (isRejected) {
      bg       = cs.errorContainer;
      fg       = cs.onErrorContainer;
      icon     = Icons.block;
      title    = 'Not Approved';
      subtitle = 'This report did not pass moderation. '
                 'Please ensure the content describes a genuine civic issue.';
    } else if (isResolved) {
      bg       = cs.primaryContainer;
      fg       = cs.onPrimaryContainer;
      icon     = Icons.check_circle;
      title    = 'Resolved';
      subtitle = 'This issue has been resolved. Thank you for reporting!';
    } else {
      bg       = cs.primaryContainer;
      fg       = cs.onPrimaryContainer;
      icon     = Icons.check_circle;
      title    = 'Live — ${_label(postStatus)}';
      subtitle = 'Your report is visible to the community.';
    }

    return Container(
      padding:    const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color:        bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, color: fg),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,    style: TextStyle(color: fg, fontWeight: FontWeight.bold)),
                const SizedBox(height: 4),
                Text(subtitle, style: TextStyle(color: fg, fontSize: 13)),
              ],
            ),
          ),
          if (isPending) ...[
            const SizedBox(width: 8),
            SizedBox.square(
              dimension: 20,
              child: CircularProgressIndicator(strokeWidth: 2, color: fg),
            ),
          ],
        ],
      ),
    );
  }

  String _label(String s) => s.replaceAll('_', ' ');
}

// ─────────────────────────────────────────────────────────────────────────────
// Small widgets
// ─────────────────────────────────────────────────────────────────────────────

class _Chip extends StatelessWidget {
  const _Chip({required this.icon, required this.label});

  final IconData icon;
  final String   label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color:        cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 14, color: cs.onSurfaceVariant),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant)),
        ],
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(message, textAlign: TextAlign.center),
      ),
    );
  }
}
