import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/auth/sign_in_screen.dart';
import 'features/feed/feed_screen.dart';
import 'features/job/job_detail_screen.dart';
import 'features/onboarding/documents_screen.dart';
import 'features/onboarding/household_screen.dart';
import 'features/profile/career_profile_screen.dart';
import 'theme.dart';

final _router = GoRouter(
  initialLocation: '/feed',
  redirect: (context, state) {
    final loggedIn = Supabase.instance.client.auth.currentSession != null;
    final goingToLogin = state.matchedLocation == '/login';
    if (!loggedIn && !goingToLogin) return '/login';
    if (loggedIn && goingToLogin) return '/feed';
    return null;
  },
  refreshListenable: _AuthRefresh(),
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const SignInScreen()),
    GoRoute(path: '/onboarding/documents', builder: (_, __) => const DocumentsScreen()),
    GoRoute(path: '/onboarding/household', builder: (_, __) => const HouseholdScreen()),
    GoRoute(path: '/profile', builder: (_, __) => const CareerProfileScreen()),
    GoRoute(path: '/feed', builder: (_, __) => const FeedScreen()),
    GoRoute(path: '/job/:id', builder: (_, s) => JobDetailScreen(jobId: s.pathParameters['id']!)),
  ],
);

/// Faz o roteador reavaliar o redirect quando a sessão muda.
class _AuthRefresh extends ChangeNotifier {
  _AuthRefresh() {
    Supabase.instance.client.auth.onAuthStateChange.listen((_) => notifyListeners());
  }
}

class RecrutadorApp extends ConsumerWidget {
  const RecrutadorApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp.router(
      title: 'Vagas Globais',
      theme: buildTheme(),
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
