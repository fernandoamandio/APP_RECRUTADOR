import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import 'features/applications/applications_screen.dart';
import 'auth/auth_service.dart';
import 'features/auth/change_password_screen.dart';
import 'features/auth/forgot_password_screen.dart';
import 'features/auth/sign_in_screen.dart';
import 'features/auth/sign_up_screen.dart';
import 'features/feed/feed_screen.dart';
import 'features/job/job_detail_screen.dart';
import 'features/onboarding/documents_screen.dart';
import 'features/onboarding/household_screen.dart';
import 'features/profile/ai_settings_screen.dart';
import 'features/profile/career_profile_screen.dart';
import 'theme.dart';
import 'widgets/brand.dart';

final _router = GoRouter(
  initialLocation: '/feed',
  redirect: (context, state) {
    final loggedIn = Supabase.instance.client.auth.currentSession != null;
    final loc = state.matchedLocation;
    // Telas acessíveis sem login; cadastro e recuperação continuam válidos logo após o código criar a sessão
    const publicRoutes = {'/login', '/signup', '/forgot-password'};
    if (!loggedIn) return publicRoutes.contains(loc) ? null : '/login';
    if (passwordGate.expired && !{'/change-password', '/signup', '/forgot-password'}.contains(loc)) {
      return '/change-password'; // senha com mais de 90 dias: troca obrigatória
    }
    if (loc == '/login') return '/feed';
    return null;
  },
  refreshListenable: Listenable.merge([_AuthRefresh(), passwordGate]),
  routes: [
    GoRoute(path: '/login', builder: (_, __) => const SignInScreen()),
    GoRoute(path: '/signup', builder: (_, s) {
      final extra = s.extra is Map ? s.extra as Map : const {};
      return SignUpScreen(
        initialEmail: extra['email'] as String?,
        initialPassword: extra['password'] as String?,
        verifyOnly: extra['verifyOnly'] == true,
      );
    }),
    GoRoute(path: '/forgot-password', builder: (_, s) => ForgotPasswordScreen(initialEmail: s.extra as String?)),
    GoRoute(path: '/change-password', builder: (_, __) => const ChangePasswordScreen()),
    GoRoute(path: '/onboarding/documents', builder: (_, __) => const DocumentsScreen(onboarding: true)),
    GoRoute(path: '/documents', builder: (_, __) => const DocumentsScreen()),
    GoRoute(path: '/onboarding/household', builder: (_, __) => const HouseholdScreen()),
    GoRoute(path: '/profile', builder: (_, __) => const CareerProfileScreen()),
    GoRoute(path: '/ai-settings', builder: (_, __) => const AiSettingsScreen()),
    GoRoute(path: '/feed', builder: (_, __) => const FeedScreen()),
    GoRoute(path: '/applications', builder: (_, __) => const ApplicationsScreen()),
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
      title: productName,
      theme: buildTheme(),
      routerConfig: _router,
      debugShowCheckedModeBanner: false,
    );
  }
}
