import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../features/auth/login_screen.dart';
import '../features/billing/paywall_screen.dart';
import '../features/library/library_screen.dart';
import '../features/curated/curated_screen.dart';
import '../features/practice/practice_screens.dart';
import '../features/progress/progress_screen.dart';
import '../features/studio/blueprint_screen.dart';
import '../features/studio/simulator_screen.dart';
import '../features/studio/voice_screen.dart';
import '../features/library/line_detail_screen.dart';
import '../core/access.dart';
import '../features/auth/splash_screen.dart';
import '../features/coach/coach_screen.dart';
import '../features/home/home_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/sections/sections_screens.dart';
import '../features/shell/home_shell.dart';
import '../features/social/social_screen.dart';

class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh(Stream<dynamic> stream) {
    _sub = stream.listen((_) => notifyListeners());
  }
  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}

final routerProvider = Provider<GoRouter>((ref) {
  final auth = Supabase.instance.client.auth;
  final refresh = _AuthRefresh(auth.onAuthStateChange);
  ref.onDispose(refresh.dispose);
  final access = ref.read(accessProvider);

  return GoRouter(
    initialLocation: '/home',
    refreshListenable: Listenable.merge([refresh, access]),
    // Pay first: signed out -> login, signed in without membership -> paywall, members and admins -> app.
    redirect: (context, state) => accessRedirect(
      location: state.matchedLocation,
      signedIn: auth.currentSession != null,
      premium: access.premium,
    ),
    routes: [
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/coach', builder: (_, __) => const CoachScreen()),
      GoRoute(path: '/paywall', builder: (_, __) => const PaywallScreen()),
      GoRoute(path: '/library', builder: (_, __) => const LibraryScreen()),
      GoRoute(
        path: '/practice',
        builder: (_, state) {
          final e = state.extra! as Map<String, String>;
          return PracticeListScreen(track: e['track']!, category: e['category']!);
        },
      ),
      GoRoute(
        path: '/practice/exercise',
        builder: (_, state) => ExerciseScreen(exercise: state.extra! as Map<String, dynamic>),
      ),
      GoRoute(path: '/progress', builder: (_, __) => const ProgressScreen()),
      GoRoute(path: '/studio/voice', builder: (_, __) => const VoiceScreen()),
      GoRoute(path: '/studio/simulator', builder: (_, __) => const SimulatorScreen()),
      GoRoute(path: '/studio/blueprint', builder: (_, __) => const BlueprintScreen()),
      GoRoute(
        path: '/openers',
        builder: (_, __) => const CuratedScreen(
          collection: 'opener',
          title: 'Best Openers',
          intro: '50 openers built on curiosity, warmth and respect. A no is a complete answer: thank her and move on.',
        ),
      ),
      GoRoute(
        path: '/flirts',
        builder: (_, __) => const CuratedScreen(
          collection: 'flirt',
          title: 'Flirt Database',
          intro: '50 authentic, respectful flirting techniques. No manipulation, no negs, no push-pull games.',
        ),
      ),
      GoRoute(
        path: '/library/line',
        builder: (_, state) => LineDetailScreen(line: state.extra! as Map<String, dynamic>),
      ),
      StatefulShellRoute.indexedStack(
        builder: (_, __, shell) => HomeShell(shell: shell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(path: '/home', builder: (_, __) => const HomeScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/social', builder: (_, __) => const SocialScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/deep-talk', builder: (_, __) => const DeepTalkScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/business', builder: (_, __) => const BusinessScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/speak', builder: (_, __) => const SpeakBetterScreen()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
          ]),
        ],
      ),
    ],
  );
});
