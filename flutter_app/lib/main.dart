import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';

import 'features/auth/presentation/auth_notifier.dart';
import 'features/auth/presentation/login_page.dart';
import 'features/feed/presentation/feed_page.dart';
import 'features/map/presentation/map_page.dart';
import 'features/profile/presentation/profile_page.dart';
import 'features/report/presentation/report_issue_page.dart';

// ─────────────────────────────────────────────────────────────────────────────
// Entry point
// ─────────────────────────────────────────────────────────────────────────────

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Firebase — google-services.json / GoogleService-Info.plist must be present.
  // Run `flutterfire configure` to regenerate firebase_options.dart if needed.
  await Firebase.initializeApp();

  // Hive offline cache
  await Hive.initFlutter();
  await Hive.openBox<String>('feed_cache');
  await Hive.openBox<bool>('upvoted_posts'); // upvote dedup across sessions

  runApp(const ProviderScope(child: CivicPulseApp()));
}

// ─────────────────────────────────────────────────────────────────────────────
// Root app
// ─────────────────────────────────────────────────────────────────────────────

class CivicPulseApp extends StatelessWidget {
  const CivicPulseApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title:                    'CivicPulse',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor:  const Color(0xFF6C3BFF),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      home: const _AuthGate(),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Auth gate — shows LoginPage until a user is signed in
// ─────────────────────────────────────────────────────────────────────────────

class _AuthGate extends ConsumerWidget {
  const _AuthGate();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authAsync = ref.watch(authStateProvider);

    return authAsync.when(
      // While resolving, show a neutral splash
      loading: () => const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      ),
      error: (_, __) => const LoginPage(),
      data: (User? user) {
        if (user == null) return const LoginPage();
        return const _MainShell();
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Current tab provider
// ─────────────────────────────────────────────────────────────────────────────

final _tabProvider = StateProvider<int>((_) => 0);

// ─────────────────────────────────────────────────────────────────────────────
// Main shell with bottom navigation
// ─────────────────────────────────────────────────────────────────────────────

class _MainShell extends ConsumerWidget {
  const _MainShell();

  static const _pages = <Widget>[
    FeedPage(),
    MapPage(),
    ReportIssuePage(),
    ProfilePage(),
  ];

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTab = ref.watch(_tabProvider);

    return Scaffold(
      // IndexedStack keeps all page states alive across tab switches.
      body: IndexedStack(
        index:    currentTab,
        children: _pages,
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: currentTab,
        onDestinationSelected: (i) =>
            ref.read(_tabProvider.notifier).state = i,
        destinations: const [
          NavigationDestination(
            icon:          Icon(Icons.home_outlined),
            selectedIcon:  Icon(Icons.home),
            label:         'Feed',
          ),
          NavigationDestination(
            icon:          Icon(Icons.map_outlined),
            selectedIcon:  Icon(Icons.map),
            label:         'Map',
          ),
          NavigationDestination(
            icon:          Icon(Icons.add_circle_outline),
            selectedIcon:  Icon(Icons.add_circle),
            label:         'Report',
          ),
          NavigationDestination(
            icon:          Icon(Icons.person_outline),
            selectedIcon:  Icon(Icons.person),
            label:         'Profile',
          ),
        ],
      ),
    );
  }
}
