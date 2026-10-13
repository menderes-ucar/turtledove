import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../features/analytics/presentation/screens/analytics_screen.dart';
import '../../features/auth/presentation/providers/auth_provider.dart';
import '../../features/auth/presentation/screens/auth_screen.dart';
import '../../features/error_notebook/presentation/screens/error_notebook_screen.dart';
import '../../features/home/presentation/screens/home_screen.dart';
import '../../features/notes/presentation/screens/notes_screen.dart';
import '../../features/quiz/presentation/screens/quiz_screen.dart';
import '../../features/subjects/presentation/screens/subjects_screen.dart';
import 'route_names.dart';

class AppRouter {
  final AuthProvider authProvider;
  final GlobalKey<NavigatorState> navigatorKey =
      GlobalKey<NavigatorState>();

  AppRouter(this.authProvider);

  late final GoRouter router = GoRouter(
    navigatorKey: navigatorKey,
    initialLocation: RouteNames.home,
    refreshListenable: authProvider,
    redirect: (context, state) {
      final isLoggedIn = authProvider.isAuthenticated;
      final isLoginRoute = state.matchedLocation == RouteNames.login;

      if (!isLoggedIn && !isLoginRoute) {
        return RouteNames.login;
      }

      if (isLoggedIn && isLoginRoute) {
        return RouteNames.home;
      }

      return null;
    },
    routes: [
      GoRoute(
        path: RouteNames.login,
        builder: (_, __) => const AuthScreen(),
      ),
      GoRoute(
        path: RouteNames.home,
        builder: (_, __) => const HomeScreen(),
      ),
      GoRoute(
        path: RouteNames.subjects,
        builder: (_, __) => const SubjectsScreen(),
      ),
      GoRoute(
        path: RouteNames.notes,
        builder: (_, __) => const NotesScreen(),
      ),
      GoRoute(
        path: RouteNames.errors,
        builder: (_, __) => const ErrorNotebookScreen(),
      ),
      GoRoute(
        path: RouteNames.analytics,
        builder: (_, __) => const AnalyticsScreen(),
      ),
      GoRoute(
        path: RouteNames.quiz,
        builder: (_, __) => const QuizScreen(),
      ),
    ],
  );
}
