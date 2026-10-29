import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import '../screens/auth/login_screen.dart';
import '../screens/auth/signup_screen.dart';
import '../screens/auth/splash_screen.dart';
import '../screens/home/pairing_screen.dart';
import '../screens/home/home_screen.dart';
import '../screens/home/shared_map_screen.dart';
import '../screens/profile/profile_screen.dart';
import '../screens/profile/partner_profile_screen.dart';
import '../screens/profile/voice_message_archive_screen.dart';
import '../screens/games/most_likely_to_screen.dart';
import '../screens/games/trivia_screen.dart';
import '../screens/games/game_lobby_screen.dart';
import '../screens/games/dove_deck_lobby_screen.dart';
import '../screens/games/game_round_screen.dart';
import '../screens/games/word_game_lobby_screen.dart';
import '../screens/games/word_game_round_screen.dart';
import '../screens/games/name_city_animal_screen.dart';
import '../screens/premium/countdown_screen.dart';
import '../screens/premium/mood_screen.dart';
import '../screens/premium/love_letter_screen.dart';
import '../providers/auth_provider.dart';
import '../screens/call/call_screen.dart';
import '../screens/home/notifications_screen.dart';
import '../screens/home/conversation_topics_screen.dart';
import '../screens/home/partner_hall_of_fame_screen.dart';

GoRouter buildRouter(AuthProvider auth) {
  return GoRouter(
    initialLocation: '/splash',
    refreshListenable: auth,
    redirect: (context, state) {
      final location = state.matchedLocation;
      final isAuthRoute = location == '/login' || location == '/signup';
      final isSplashRoute = location == '/splash';

      // Keep the splash visible while Supabase restores the persisted session.
      if (auth.isLoading) return isSplashRoute ? null : '/splash';
      // A profile request can fail even while the Supabase session exists.
      // Do not trap the user on the splash forever once loading has finished.
      if (auth.hasSession && auth.profile == null) return isAuthRoute ? null : '/login';
      final isPairingRoute = location == '/pairing';
      final hasProfile = auth.profile != null;

      if (isSplashRoute) {
        if (hasProfile) return auth.isPaired ? '/home' : '/pairing';
        return auth.hasSession ? null : '/login';
      }

      if (!hasProfile) {
        // Protected routes must not be reachable without a valid profile.
        if (!isAuthRoute) return '/login';
        return null;
      }

      // A restored session should skip the login/signup screens.
      if (isAuthRoute) {
        return auth.isPaired ? '/home' : '/pairing';
      }

      // Keep an unpaired user on the pairing flow unless they are already there.
      if (!auth.isPaired && !isPairingRoute) return '/pairing';

      return null;
    },
    routes: [
      GoRoute(path: '/splash', builder: (_, __) => const SplashScreen()),
      GoRoute(path: '/login', builder: (_, __) => const LoginScreen()),
      GoRoute(path: '/signup', builder: (_, __) => const SignupScreen()),
      GoRoute(path: '/pairing', builder: (_, __) => const PairingScreen()),
      GoRoute(path: '/profile', builder: (_, __) => const ProfileScreen()),
      GoRoute(
        path: '/home/profile/:profileId',
        builder: (_, state) {
          final profileId = state.pathParameters['profileId'];
          if (profileId == null || profileId.isEmpty) return const SizedBox.shrink();
          return PartnerProfileScreen(
            profileId: profileId,
            userId: auth.profile?.id ?? '',
          );
        },
      ),
      GoRoute(
        path: '/home/profile/:profileId/voice-messages',
        builder: (_, state) {
          final profileId = state.pathParameters['profileId'];
          if (profileId == null || profileId.isEmpty) return const SizedBox.shrink();
          return VoiceMessageArchiveScreen(partnerId: profileId);
        },
      ),
      GoRoute(
        path: '/home',
        builder: (_, __) => const HomeScreen(),
        routes: [
          GoRoute(path: 'most-likely-to', builder: (_, __) => const MostLikelyToScreen()),
          GoRoute(path: 'trivia', builder: (_, __) => const TriviaScreen()),
          GoRoute(path: 'dove-deck', builder: (_, __) => const DoveDeckLobbyScreen()),
          GoRoute(path: 'word-game', builder: (_, __) => const WordGameLobbyScreen()),
          GoRoute(
            path: 'word-game-round/:sessionId',
            builder: (_, state) {
              final sessionId = state.pathParameters['sessionId'];
              if (sessionId == null || sessionId.isEmpty) return const SizedBox.shrink();
              return WordGameRoundScreen(sessionId: sessionId);
            },
          ),
          GoRoute(
            path: 'game-round/:sessionId/:roundNumber',
            builder: (_, state) {
              final sessionId = state.pathParameters['sessionId'];
              final roundNumber = int.tryParse(state.pathParameters['roundNumber'] ?? '');
              if (sessionId == null || sessionId.isEmpty || roundNumber == null || roundNumber < 1) {
                return const SizedBox.shrink();
              }
              return GameRoundScreen(sessionId: sessionId, roundNumber: roundNumber);
            },
          ),
          GoRoute(
            path: 'game-lobby/:gameType',
            builder: (_, state) {
              final gameType = state.pathParameters['gameType'];
              if (gameType == null ||
                  !{'most_likely_to', 'trivia', 'word_game', 'name_city_animal'}.contains(gameType)) {
                return const SizedBox.shrink();
              }
              if (gameType == 'word_game') {
                return const WordGameLobbyScreen();
              }
              if (gameType == 'name_city_animal') {
                return const NameCityAnimalLobbyScreen();
              }
              return GameLobbyScreen(gameType: gameType);
            },
          ),
          GoRoute(path: 'countdown', builder: (_, __) => const CountdownScreen()),
          GoRoute(path: 'mood', builder: (_, __) => const MoodScreen()),
          GoRoute(path: 'love-letters', builder: (_, __) => const LoveLetterScreen()),
          GoRoute(path: 'map', builder: (_, __) => const SharedMapScreen()),
          GoRoute(path: 'conversation-topics', builder: (_, __) => const ConversationTopicsScreen()),
          GoRoute(path: 'hall-of-fame', builder: (_, __) => const PartnerHallOfFameScreen()),
          GoRoute(path: 'notifications', builder: (_, __) => const NotificationsScreen()),
          GoRoute(
            path: 'call/:callId/:mode',
            builder: (_, state) {
              final callId = state.pathParameters['callId'];
              final mode = state.pathParameters['mode'];
              final user = auth.profile;
              if (callId == null || callId.isEmpty || user == null) return const SizedBox.shrink();
              final partnerId = state.uri.queryParameters['partnerId'] ?? user.pairedWith ?? '';
              if (partnerId.isEmpty) return const SizedBox.shrink();
              final autoAccept = state.uri.queryParameters['autoAccept'] == '1';
              final callerName = state.uri.queryParameters['callerName'];
              return CallScreen(
                userId: user.id,
                partnerId: partnerId,
                callId: callId,
                isCaller: mode == 'caller',
                autoAccept: autoAccept,
                callerName: callerName,
              );
            },
          ),

        ],
      ),
    ],
  );
}
