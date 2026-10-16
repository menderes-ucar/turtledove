
import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'firebase_options.dart';
import 'services/auth_service.dart';
import 'services/chat_service.dart';
import 'services/todo_service.dart';
import 'services/shared_place_service.dart';
import 'services/map_selection_service.dart';
import 'services/interaction_service.dart';
import 'services/call_service.dart';
import 'services/notification_service.dart';
import 'services/push_notification_service.dart';
import 'services/relationship_service.dart';
import 'providers/auth_provider.dart';
import 'providers/theme_provider.dart';
import 'providers/locale_provider.dart';
import 'router/app_router.dart';
import 'config/theme_config.dart';
import 'utils/constants.dart';

// Supabase PKCE verifier storage.
// Avoid Android SharedPreferences during Supabase startup.
class _MemoryPkceStorage extends GotrueAsyncStorage {
  final Map<String, String> _values = <String, String>{};

  @override
  Future<String?> getItem({required String key}) async => _values[key];

  @override
  Future<void> setItem({
    required String key,
    required String value,
  }) async {
    _values[key] = value;
  }

  @override
  Future<void> removeItem({required String key}) async {
    _values.remove(key);
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

// ------------------------------------------------------------
// ENV
// ------------------------------------------------------------
  var envLoaded = false;
  try {
    await dotenv.load(fileName: '.env');
    envLoaded = true;
  } catch (e) {
    debugPrint('⚠️ .env yüklenemedi: $e');
  }

  if (!envLoaded) {
    runApp(const ConfigErrorApp(error: 'Proje kök dizinindeki .env dosyası yüklenemedi.'));
    return;
  }

  final url = dotenv.env['SUPABASE_URL']?.trim();
  final key = dotenv.env['SUPABASE_ANON_KEY']?.trim();

  if (url == null || url.isEmpty || key == null || key.isEmpty) {
    print(
      '❌ ERROR: SUPABASE_URL or SUPABASE_ANON_KEY not set in .env',
    );

    runApp(const ConfigErrorApp());
    return;
  }

// ------------------------------------------------------------
// SUPABASE
// ------------------------------------------------------------
  try {
    await Supabase.initialize(
      url: url,
      anonKey: key,
      authOptions: FlutterAuthClientOptions(
// Let supabase_flutter use its persistent platform storage for the auth
// session. EmptyLocalStorage is intentionally a no-op and caused sessions
// to disappear after app restarts.
        pkceAsyncStorage: _MemoryPkceStorage(),
      ),
    );
  } catch (e) {
    print('❌ Supabase init error: $e');

    runApp(
      ConfigErrorApp(
        error: e.toString(),
      ),
    );

    return;
  }

// ------------------------------------------------------------
// FIREBASE
// ------------------------------------------------------------
  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    print('✅ Firebase initialized successfully');
  } catch (e) {
    print('❌ Firebase init error: $e');

    runApp(
      ConfigErrorApp(
        error: e.toString(),
      ),
    );

    return;
  }

// ------------------------------------------------------------
// APP
// ------------------------------------------------------------
  runApp(const BestieApp());
}

// ============================================================================
// CONFIG ERROR APP
// ============================================================================

class ConfigErrorApp extends StatelessWidget {
  final String? error;

  const ConfigErrorApp({
    this.error,
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      home: Scaffold(
        appBar: AppBar(
          title: const Text('Configuration Error'),
        ),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            children: [
              const SizedBox(height: 40),

              const Icon(
                Icons.error,
                size: 80,
                color: Colors.red,
              ),

              const SizedBox(height: 20),

              const Text(
                'Setup Required',
                style: TextStyle(
                  fontSize: 24,
                  fontWeight: FontWeight.bold,
                ),
              ),

              const SizedBox(height: 20),

              if (error != null)
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.red.shade100,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Text(
                    'Error: $error',
                    style: TextStyle(
                      color: Colors.red.shade900,
                    ),
                  ),
                ),

              const SizedBox(height: 20),

              const Text(
                'Supabase .env configuration was loaded. '
                    'The error above occurred while initializing Supabase.',
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 20),

              const Text(
                'Expected project-root .env keys:',
                textAlign: TextAlign.center,
              ),

              const SizedBox(height: 10),

              const SelectableText(
                'SUPABASE_URL=...\\n'
                    'SUPABASE_ANON_KEY=...\\n'
                    'SUPABASE_SERVICE_ROLE_KEY=...\\n'
                    'MEDIASOUP_ANNOUNCED_IP=...\\n'
                    'MEDIASOUP_SIGNALING_URL=...',
                style: TextStyle(
                  fontFamily: 'monospace',
                  fontSize: 12,
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                'Do not put the real service-role key in Flutter source code. '
                    'The mobile app uses only SUPABASE_ANON_KEY.',
                textAlign: TextAlign.center,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================================
// BESTIE APP
// ============================================================================

class BestieApp extends StatelessWidget {
  const BestieApp({
    Key? key,
  }) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
// ----------------------------------------------------------
// SERVICES
// ----------------------------------------------------------

        Provider(
          create: (_) => AuthService(
            Supabase.instance.client,
          ),
        ),

        Provider(
          create: (_) => ChatService(
            Supabase.instance.client,
          ),
        ),

        Provider(
          create: (_) => TodoService(
            Supabase.instance.client,
          ),
        ),

        Provider(
          create: (_) => SharedPlaceService(
            Supabase.instance.client,
          ),
        ),

        Provider(
          create: (_) => MapSelectionService(
            Supabase.instance.client,
          ),
        ),

        Provider(
          create: (_) => InteractionService(
            Supabase.instance.client,
          ),
        ),

        Provider(
          create: (_) => CallService(
            Supabase.instance.client,
          ),
        ),

        Provider(
          create: (_) => NotificationService(
            Supabase.instance.client,
          ),
        ),

        Provider(
          create: (_) => RelationshipService(
            Supabase.instance.client,
          ),
        ),

        Provider(
          create: (_) => PushNotificationService(
            Supabase.instance.client,
          ),
        ),

// ----------------------------------------------------------
// PROVIDERS
// ----------------------------------------------------------

        ChangeNotifierProvider(
          create: (ctx) => AuthProvider(
            ctx.read<AuthService>(),
          ),
        ),

        ChangeNotifierProvider(
          create: (_) => ThemeProvider(),
        ),

        ChangeNotifierProvider(
          create: (_) => LocaleProvider(Supabase.instance.client),
        ),
      ],

      child: const _BestieRouterApp(),
    );
  }
}

// ============================================================================
// ROUTER APP
// ============================================================================

class _BestieRouterApp extends StatefulWidget {
  const _BestieRouterApp();

  @override
  State<_BestieRouterApp> createState() => _BestieRouterAppState();
}

class _BestieRouterAppState extends State<_BestieRouterApp> {
  late final GoRouter _router;
  late final AuthProvider _auth;
  Map<String, dynamic>? _pendingNotificationNavigation;
  bool _openingIncomingCall = false;

  @override
  void initState() {
    super.initState();

    _auth = context.read<AuthProvider>();
    _router = buildRouter(_auth);

    _auth.addListener(_flushPendingNotificationNavigation);

    context.read<PushNotificationService>().setNavigationHandler((data) {
      _pendingNotificationNavigation = Map<String, dynamic>.from(data);
      _flushPendingNotificationNavigation();
    });

    unawaited(
      context.read<PushNotificationService>().initialize(),
    );
  }

  void _flushPendingNotificationNavigation() {
    final data = _pendingNotificationNavigation;
    if (data == null || _openingIncomingCall) return;

// Cold-start: wait until the persisted Supabase session/profile is ready.
// Otherwise GoRouter's auth redirect can discard the incoming-call route.
    if (_auth.isLoading || _auth.profile == null) return;

    final type = data['type']?.toString() ?? '';
    final action = data['action']?.toString() ?? '';

    if (action == 'call_ended' || type == 'call_end') {
      _pendingNotificationNavigation = null;
      final callId = data['call_id']?.toString();
      if (callId != null && callId.isNotEmpty) {
        unawaited(
          context.read<PushNotificationService>().cancelCallNotification(callId),
        );
      }
// call_end is the remote-device recovery transport. If Supabase
// Realtime is delayed/unavailable, this push still tears down an active
// Flutter call screen instead of leaving the user on a stale call UI.
      final currentPath = _router.routerDelegate.currentConfiguration.uri.path;
      if (currentPath.contains('/call/')) {
        _router.go('/home');
      }
      return;
    }

    if (type == 'call' || action == 'incoming_call') {
      final callId = data['call_id']?.toString();
      if (callId == null || callId.isEmpty) {
        _pendingNotificationNavigation = null;
        return;
      }
      unawaited(_openIncomingCallFromNotification(data));
      return;
    }

    _pendingNotificationNavigation = null;
    if (type == 'love_letter') {
      _router.go('/home/love-letters');
    } else if (type == 'map' || type == 'place') {
      _router.go('/home/map');
    } else if (type == 'relationship_streak' || type == 'today_us' || type == 'us') {
      _router.go('/home?tab=1');
    } else if (type == 'mood') {
      _router.go('/home/mood');
    } else if (type == 'countdown') {
      _router.go('/home/countdown');
    } else if (type == 'game') {
      _router.go('/home/notifications');
    } else {
      _router.go('/home/notifications');
    }
  }

  Future<void> _openIncomingCallFromNotification(Map<String, dynamic> data) async {
    if (_openingIncomingCall) return;
    _openingIncomingCall = true;
    try {
      final callId = data['call_id']?.toString() ?? '';
      if (callId.isEmpty || _auth.profile == null) return;

      final currentPath = _router.routerDelegate.currentConfiguration.uri.path;
      if (currentPath.contains('/call/')) {
        _pendingNotificationNavigation = null;
        return;
      }

      final calls = context.read<CallService>();
      final session = await calls.getCallSession(callId);
      final status = session?['status']?.toString();
      final receiverId = session?['receiver_id']?.toString();
      final callerId = session?['caller_id']?.toString();
      if (status != 'ringing' || receiverId != _auth.profile!.id) {
        _pendingNotificationNavigation = null;
        return;
      }

      final nativeAction = data['native_action']?.toString();
      if (nativeAction == 'reject') {
        _pendingNotificationNavigation = null;
        try {
          await calls.connect(
            userId: _auth.profile!.id,
            partnerId: callerId ?? _auth.profile!.pairedWith ?? '',
            callId: callId,
          );
          await calls.rejectCall(callId);
        } catch (e) {
          debugPrint('BESTIE native reject failed: $e');
        }
        return;
      }

      if (!calls.claimIncomingCallUi(callId)) {
        _pendingNotificationNavigation = null;
        debugPrint('BESTIE CALL duplicate incoming route suppressed call=$callId');
        return;
      }

      _pendingNotificationNavigation = null;
      final query = <String, String>{};
      if (callerId != null && callerId.isNotEmpty) query['partnerId'] = callerId;
      final callerName = data['caller_name']?.toString().trim();
      if (callerName != null && callerName.isNotEmpty) query['callerName'] = callerName;
      if (nativeAction == 'accept') query['autoAccept'] = '1';
      final queryString = query.isEmpty
          ? ''
          : '?${query.entries.map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
      _router.go('/home/call/$callId/receiver$queryString');
    } finally {
      _openingIncomingCall = false;
      if (_pendingNotificationNavigation != null && mounted) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _flushPendingNotificationNavigation();
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Consumer3<AuthProvider, ThemeProvider, LocaleProvider>(
      builder: (ctx, auth, theme, locale, _) {
        return MaterialApp.router(
          routerConfig: _router,

// ------------------------------------------------------
// THEME
// ------------------------------------------------------

          theme: AppTheme.lightTheme(
            theme.primaryColor,
          ),

          darkTheme: AppTheme.darkTheme(
            theme.primaryColor,
          ),

          themeMode: theme.isDark
              ? ThemeMode.dark
              : ThemeMode.light,

// ------------------------------------------------------
// APP
// ------------------------------------------------------

          debugShowCheckedModeBanner: false,

          title: AppConstants.appName,

          locale: locale.locale,

// ------------------------------------------------------
// LOCALIZATION
// ------------------------------------------------------

          supportedLocales: const [
            Locale('tr'),
            Locale('en'),
            Locale('de'),
            Locale('es'),
            Locale('fr'),
          ],

          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
          ],
        );
      },
    );
  }
}
