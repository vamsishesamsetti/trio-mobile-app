import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/supabase.dart';
import '../features/auth/login_page.dart';
import '../features/dashboard/dashboard_page.dart';
import '../features/hours/presentation/hours_page.dart';
import '../features/money/presentation/money_page.dart';
import '../features/profile/profile_page.dart';
import '../features/shell/home_shell.dart';
import '../features/split/presentation/split_page.dart';

final _rootKey = GlobalKey<NavigatorState>();

/// App router with an auth guard. Redirects to /login when signed out and to
/// /dashboard when a signed-out screen is shown while authed. Rebuilds routes
/// whenever Supabase auth state changes.
final routerProvider = Provider<GoRouter>((ref) {
  final client = ref.watch(supabaseProvider);
  final refresh = _GoRouterRefreshStream(client.auth.onAuthStateChange);
  ref.onDispose(refresh.dispose);

  return GoRouter(
    navigatorKey: _rootKey,
    initialLocation: '/dashboard',
    refreshListenable: refresh,
    redirect: (context, state) {
      final loggedIn = client.auth.currentSession != null;
      final loggingIn = state.matchedLocation == '/login';
      if (!loggedIn) return loggingIn ? null : '/login';
      if (loggingIn) return '/dashboard';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (context, state) => const LoginPage(),
      ),
      StatefulShellRoute.indexedStack(
        builder: (context, state, navigationShell) =>
            HomeShell(navigationShell: navigationShell),
        branches: [
          StatefulShellBranch(routes: [
            GoRoute(
                path: '/dashboard',
                builder: (c, s) => const DashboardPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/money', builder: (c, s) => const MoneyPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/split', builder: (c, s) => const SplitPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/hours', builder: (c, s) => const HoursPage()),
          ]),
          StatefulShellBranch(routes: [
            GoRoute(path: '/profile', builder: (c, s) => const ProfilePage()),
          ]),
        ],
      ),
    ],
  );
});

/// Bridges a Stream into a [Listenable] for go_router's refreshListenable.
class _GoRouterRefreshStream extends ChangeNotifier {
  _GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _sub = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _sub;

  @override
  void dispose() {
    _sub.cancel();
    super.dispose();
  }
}
