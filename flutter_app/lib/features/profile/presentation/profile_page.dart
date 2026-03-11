import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../auth/presentation/auth_notifier.dart';
import '../../issue_detail/presentation/issue_detail_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Provider: stream the current user's own posts (including pending)
// ─────────────────────────────────────────────────────────────────────────────

final _myPostsProvider = StreamProvider<List<Map<String, dynamic>>>((ref) {
  final uid = FirebaseAuth.instance.currentUser?.uid;
  if (uid == null) return Stream.value([]);

  return FirebaseFirestore.instance
      .collection('posts')
      .where('authorId', isEqualTo: uid)
      .orderBy('createdAt', descending: true)
      .limit(20)
      .snapshots()
      .map((snap) =>
          snap.docs.map((d) => {'id': d.id, ...d.data()}).toList());
});

// ─────────────────────────────────────────────────────────────────────────────
// Page
// ─────────────────────────────────────────────────────────────────────────────

class ProfilePage extends ConsumerWidget {
  const ProfilePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user      = FirebaseAuth.instance.currentUser;
    final postsAsync = ref.watch(_myPostsProvider);
    final notifier   = ref.read(authNotifierProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title:       const Text('My Profile'),
        centerTitle: true,
        actions: [
          IconButton(
            icon:     const Icon(Icons.logout_outlined),
            tooltip:  'Sign Out',
            onPressed: () async {
              final ok = await _confirmSignOut(context);
              if (ok) notifier.signOut();
            },
          ),
        ],
      ),
      body: ListView(
        children: [
          // ── Avatar + name ─────────────────────────────────────────────
          _ProfileHeader(user: user),
          const Divider(height: 1),

          // ── Stats row ─────────────────────────────────────────────────
          postsAsync.when(
            loading: () => const SizedBox(height: 56, child: Center(child: CircularProgressIndicator())),
            error:   (_, __) => const SizedBox.shrink(),
            data:    (posts) => _StatsRow(posts: posts),
          ),
          const Divider(height: 1),

          // ── My reports header ─────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
            child: Text(
              'My Reports',
              style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ),

          // ── Posts list ────────────────────────────────────────────────
          postsAsync.when(
            loading: () => const Padding(
              padding: EdgeInsets.all(32),
              child:   Center(child: CircularProgressIndicator()),
            ),
            error: (e, _) => Padding(
              padding: const EdgeInsets.all(32),
              child:   Center(child: Text('Error loading posts: $e')),
            ),
            data: (posts) => posts.isEmpty
                ? const _EmptyPosts()
                : Column(
                    children: posts
                        .map((p) => _MyPostTile(post: p))
                        .toList(),
                  ),
          ),

          const SizedBox(height: 32),
        ],
      ),
    );
  }

  Future<bool> _confirmSignOut(BuildContext context) async {
    final result = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title:   const Text('Sign Out'),
        content: const Text('Are you sure you want to sign out?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Sign Out'),
          ),
        ],
      ),
    );
    return result ?? false;
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Profile header
// ─────────────────────────────────────────────────────────────────────────────

class _ProfileHeader extends StatelessWidget {
  const _ProfileHeader({required this.user});

  final User? user;

  @override
  Widget build(BuildContext context) {
    final cs           = Theme.of(context).colorScheme;
    final displayName  = user?.displayName ?? 'Anonymous';
    final email        = user?.email ?? '';
    final initials     = displayName.isNotEmpty
        ? displayName.split(' ').map((w) => w.isEmpty ? '' : w[0]).take(2).join().toUpperCase()
        : '?';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 20),
      child: Row(
        children: [
          CircleAvatar(
            radius:          32,
            backgroundColor: cs.primaryContainer,
            child: Text(
              initials,
              style: TextStyle(
                fontSize:   20,
                fontWeight: FontWeight.bold,
                color:      cs.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: Theme.of(context).textTheme.titleLarge
                      ?.copyWith(fontWeight: FontWeight.bold),
                ),
                if (email.isNotEmpty)
                  Text(
                    email,
                    style: Theme.of(context).textTheme.bodyMedium
                        ?.copyWith(color: cs.onSurfaceVariant),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Stats row
// ─────────────────────────────────────────────────────────────────────────────

class _StatsRow extends StatelessWidget {
  const _StatsRow({required this.posts});

  final List<Map<String, dynamic>> posts;

  @override
  Widget build(BuildContext context) {
    // Single O(n) pass instead of three separate where/fold calls.
    int approved = 0, pending = 0, totalUpvotes = 0;
    for (final p in posts) {
      final st = p['status'] as String? ?? '';
      if (st == 'resolved')     approved++;
      if (st == 'under_review') pending++;
      totalUpvotes += (p['upvotes'] as num?)?.toInt() ?? 0;
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          _StatTile(value: '${posts.length}', label: 'Total'),
          _StatTile(value: '$approved',        label: 'Approved'),
          _StatTile(value: '$pending',         label: 'Pending'),
          _StatTile(value: '$totalUpvotes',    label: 'Upvotes'),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  const _StatTile({required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      children: [
        Text(
          value,
          style: Theme.of(context).textTheme.headlineSmall
              ?.copyWith(fontWeight: FontWeight.bold, color: cs.primary),
        ),
        Text(
          label,
          style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
        ),
      ],
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// My post tile
// ─────────────────────────────────────────────────────────────────────────────

class _MyPostTile extends StatelessWidget {
  const _MyPostTile({required this.post});

  final Map<String, dynamic> post;

  @override
  Widget build(BuildContext context) {
    final cs     = Theme.of(context).colorScheme;
    final status = post['status'] as String? ?? 'under_review';

    final Color statusColor;
    final String statusLabel;
    if (status == 'under_review') {
      statusColor = cs.secondaryContainer;
      statusLabel = 'Under Review';
    } else if (status == 'rejected') {
      statusColor = cs.errorContainer;
      statusLabel = 'Rejected';
    } else if (status == 'resolved') {
      statusColor = cs.primaryContainer;
      statusLabel = 'Resolved';
    } else {
      statusColor = cs.primaryContainer;
      statusLabel = 'Live';
    }

    return ListTile(
      leading: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color:        statusColor,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          statusLabel,
          style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600),
        ),
      ),
      title: Text(
        post['title'] as String? ?? '',
        maxLines:  1,
        overflow:  TextOverflow.ellipsis,
        style: Theme.of(context).textTheme.bodyMedium
            ?.copyWith(fontWeight: FontWeight.w500),
      ),
      subtitle: Text(
        post['city'] as String? ?? '',
        style: TextStyle(fontSize: 12, color: cs.onSurfaceVariant),
      ),
      trailing: const Icon(Icons.chevron_right),
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => IssueDetailPage(postId: post['id'] as String),
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Empty state
// ─────────────────────────────────────────────────────────────────────────────

class _EmptyPosts extends StatelessWidget {
  const _EmptyPosts();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(Icons.assignment_outlined,
              size: 56,
              color: Theme.of(context).colorScheme.outline),
          const SizedBox(height: 12),
          const Text(
            "You haven't filed any reports yet.\nTap + to report an issue in your city.",
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
