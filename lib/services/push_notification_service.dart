import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:flutter/services.dart';

import '../firebase_options.dart';

const MethodChannel _nativeSystemChannel = MethodChannel('bestie/system');

const String _bestieNotificationChannelId = 'bestie_notifications_v3';
const String _bestieCallChannelId = 'bestie_calls_v3';

AndroidNotificationChannel _bestieChannel(String language) {
  final name = switch (language) {
    'tr' => 'Turtle Dove Bildirimleri',
    'de' => 'Turtle Dove-Benachrichtigungen',
    'es' => 'Notificaciones de Turtle Dove',
    'fr' => 'Notifications Turtle Dove',
    _ => 'Turtle Dove Notifications',
  };
  return AndroidNotificationChannel(
    _bestieNotificationChannelId,
    name,
    description: name,
    importance: Importance.high,
    playSound: true,
    sound: null,
    audioAttributesUsage: AudioAttributesUsage.notificationEvent,
  );
}

AndroidNotificationChannel _bestieCallChannel(String language) {
  final name = switch (language) {
    'tr' => 'Turtle Dove Aramaları',
    'de' => 'Turtle Dove-Anrufe',
    'es' => 'Llamadas de Turtle Dove',
    'fr' => 'Appels Turtle Dove',
    _ => 'Turtle Dove Calls',
  };
  return AndroidNotificationChannel(
    _bestieCallChannelId,
    name,
    description: name,
    importance: Importance.max,
    playSound: true,
    sound: RawResourceAndroidNotificationSound('bestie_call_ringtone'),
    audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
  );
}

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

int _callNotificationId(Map<String, dynamic> data) {
  final callId =
      data['call_id']?.toString() ??
      data['notification_id']?.toString() ??
      'bestie-call';
  var hash = 0;
  for (final codeUnit in callId.codeUnits) {
    hash = (hash * 31 + codeUnit) & 0x7fffffff;
  }
  return hash == 0 ? 2147483646 : hash;
}

Future<void> _showBackgroundLocalNotification(RemoteMessage message) async {
  if (!Platform.isAndroid && !Platform.isIOS) return;

  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _localNotifications.initialize(
      const InitializationSettings(android: androidInit, iOS: iosInit),
    );

    if (Platform.isAndroid) {
      final android = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      await android?.createNotificationChannel(_bestieChannel('en'));
      await android?.createNotificationChannel(_bestieCallChannel('en'));
    }

    final data = Map<String, dynamic>.from(message.data);
    final type = data['type']?.toString() ?? '';
    final title =
        data['title']?.toString() ??
        message.notification?.title ??
        'Turtle Dove';
    final body = data['body']?.toString() ?? message.notification?.body ?? '';

    // Android calls are owned by BestieFirebaseMessagingService +
    // BestieCallRingingService. Do not also create a one-shot Flutter local
    // notification: that was the source of the single-ring behaviour.
    if (Platform.isAndroid &&
        (type == 'call' ||
            type == 'call_end' ||
            data['action']?.toString() == 'incoming_call' ||
            data['action']?.toString() == 'call_ended')) {
      return;
    }

    // Normal notifications are already displayed by FCM's notification payload.
    if (type != 'call' && data['action']?.toString() != 'incoming_call') return;

    final notificationId = _callNotificationId(data);
    await _localNotifications.show(
      notificationId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          'bestie_calls_v3',
          'Turtle Dove Calls',
          channelDescription: 'Incoming Turtle Dove calls',
          importance: Importance.max,
          priority: Priority.max,
          playSound: true,
          sound: RawResourceAndroidNotificationSound('bestie_call_ringtone'),
          audioAttributesUsage: AudioAttributesUsage.alarm,
          fullScreenIntent: true,
          category: AndroidNotificationCategory.call,
          visibility: NotificationVisibility.public,
          ongoing: true,
          autoCancel: false,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(data),
    );
  } catch (e, st) {
    debugPrint('[FCM] background local notification failed: $e\n$st');
  }
}

@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint(
    '[FCM] background message: ${message.messageId} data=${message.data}',
  );
  await _showBackgroundLocalNotification(message);
}

class PushNotificationService {
  final SupabaseClient client;

  Future<void> cancelCallNotification(String callId) async {
    try {
      await _localNotifications.cancel(
        _callNotificationId({'call_id': callId}),
      );
      if (Platform.isAndroid) {
        try {
          await _nativeSystemChannel.invokeMethod('stopIncomingCallRinging');
        } catch (_) {}
      }
    } catch (e) {
      debugPrint('[FCM] call notification cancel failed: $e');
    }
  }

  PushNotificationService(this.client);

  FirebaseMessaging? _messaging;
  StreamSubscription<AuthState>? _authSubscription;
  StreamSubscription<String>? _tokenSubscription;
  StreamSubscription<RemoteMessage>? _messageSubscription;
  StreamSubscription<RemoteMessage>? _openedSubscription;
  bool _enabled = false;
  bool _localReady = false;
  String? _lastRegisteredToken;
  String? _lastRegisteredUserId;
  Timer? _iosTokenRetryTimer;
  bool _tokenSyncInProgress = false;

  void Function(Map<String, dynamic> data)? _navigationHandler;
  Map<String, dynamic>? _pendingNavigation;

  bool get isEnabled => _enabled;

  void setNavigationHandler(void Function(Map<String, dynamic> data) handler) {
    _navigationHandler = handler;
    final pending = _pendingNavigation;
    _pendingNavigation = null;
    if (pending != null) {
      WidgetsBindingCallback.schedule(() => handler(pending));
    }
  }

  void _handleNavigation(Map<String, dynamic> data) {
    final handler = _navigationHandler;
    if (handler == null) {
      _pendingNavigation = data;
      return;
    }
    handler(data);
  }

  Future<void> initialize() async {
    if (_enabled || kIsWeb || (!Platform.isAndroid && !Platform.isIOS)) return;

    try {
      if (Platform.isAndroid) {
        _nativeSystemChannel.setMethodCallHandler((call) async {
          if (call.method == 'incomingCallIntent' && call.arguments is Map) {
            final data = Map<String, dynamic>.from(call.arguments as Map);
            _handleNavigation(data);
          }
        });
      }

      _messaging = FirebaseMessaging.instance;
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

      await _messaging!.setAutoInitEnabled(true);
      await _initializeLocalNotifications();
      if (Platform.isAndroid) {
        try {
          final pending = await _nativeSystemChannel.invokeMethod<dynamic>(
            'getPendingIncomingCall',
          );
          if (pending is Map) {
            _handleNavigation(Map<String, dynamic>.from(pending));
          }
        } catch (e) {
          debugPrint('[FCM] pending native call read failed: $e');
        }
      }
      await _requestNotificationPermission();
      await _verifyAndroidNotificationState();

      if (Platform.isIOS) {
        await _messaging!.setForegroundNotificationPresentationOptions(
          alert: true,
          badge: true,
          sound: true,
        );
      }

      _enabled = true;

      _authSubscription = client.auth.onAuthStateChange.listen((event) {
        if (event.event == AuthChangeEvent.signedOut) {
          final token = _lastRegisteredToken;
          if (token != null) unawaited(_removeToken(token));
          _lastRegisteredToken = null;
          _lastRegisteredUserId = null;
          return;
        }
        unawaited(_syncToken());
      });
      if (Platform.isIOS) {
        // APNs registration can finish after app startup. Retry in the
        // background so a temporary null APNs token doesn't permanently
        // prevent this installation from being registered in Supabase.
        _iosTokenRetryTimer ??= Timer.periodic(const Duration(seconds: 10), (
          _,
        ) {
          if (client.auth.currentUser != null) unawaited(_syncToken());
        });
      }
      _tokenSubscription = _messaging!.onTokenRefresh.listen((token) {
        final previous = _lastRegisteredToken;
        if (previous != null && previous != token) {
          unawaited(_removeToken(previous));
        }
        unawaited(_saveToken(token));
      });
      _messageSubscription = FirebaseMessaging.onMessage.listen(
        (message) => unawaited(_showForegroundNotification(message)),
      );
      _openedSubscription = FirebaseMessaging.onMessageOpenedApp.listen(
        (message) => _handleNavigation(Map<String, dynamic>.from(message.data)),
      );

      final initial = await _messaging!.getInitialMessage();
      if (initial != null) {
        _handleNavigation(Map<String, dynamic>.from(initial.data));
      }

      await _syncToken();
      debugPrint('[FCM] initialization complete');
    } catch (e, st) {
      debugPrint('[FCM] initialization failed: $e\n$st');
    }
  }

  Future<void> _initializeLocalNotifications() async {
    const android = AndroidInitializationSettings('@mipmap/ic_launcher');
    const ios = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    await _localNotifications.initialize(
      const InitializationSettings(android: android, iOS: ios),
      onDidReceiveNotificationResponse: (response) {
        final raw = response.payload;
        if (raw == null || raw.isEmpty) return;
        try {
          final decoded = jsonDecode(raw);
          if (decoded is Map) {
            _handleNavigation(Map<String, dynamic>.from(decoded));
          }
        } catch (e) {
          debugPrint('[FCM] notification payload parse failed: $e');
        }
      },
    );

    if (Platform.isAndroid) {
      final androidPlugin = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final channelLanguage = await _currentLanguageCode();
      await androidPlugin?.createNotificationChannel(
        _bestieChannel(channelLanguage),
      );
      await androidPlugin?.createNotificationChannel(
        _bestieCallChannel(channelLanguage),
      );
      await androidPlugin?.requestNotificationsPermission();
      try {
        await androidPlugin?.requestFullScreenIntentPermission();
      } catch (e) {
        debugPrint('[FCM] full-screen intent permission request skipped: $e');
      }
    }

    // Recover a notification that launched the process/full-screen Activity.
    // This is required for call actions when the app was not already running.
    final launchDetails = await _localNotifications
        .getNotificationAppLaunchDetails();
    final launchPayload = launchDetails?.notificationResponse?.payload;
    if (launchDetails?.didNotificationLaunchApp == true &&
        launchPayload != null &&
        launchPayload.isNotEmpty) {
      try {
        final decoded = jsonDecode(launchPayload);
        if (decoded is Map) {
          _pendingNavigation = Map<String, dynamic>.from(decoded);
        }
      } catch (e) {
        debugPrint('[FCM] launch payload parse failed: $e');
      }
    }

    _localReady = true;
  }

  Future<void> _requestNotificationPermission() async {
    final settings = await _messaging!.requestPermission(
      alert: true,
      badge: true,
      sound: true,
      announcement: false,
      carPlay: false,
      criticalAlert: false,
      provisional: false,
    );
    final status = settings.authorizationStatus;
    final allowed =
        status == AuthorizationStatus.authorized ||
        status == AuthorizationStatus.provisional;
    debugPrint(
      '[FCM] permission status: ${status.name}; notificationsAllowed=$allowed',
    );
    if (!allowed) {
      debugPrint(
        '[FCM] notifications are not authorized. The user may need to enable '
        'Turtle Dove notifications in system settings.',
      );
    }
  }

  Future<String> _currentLanguageCode() async {
    try {
      final user = client.auth.currentUser;
      if (user != null) {
        final row = await client
            .from('profiles')
            .select('language_code')
            .eq('id', user.id)
            .maybeSingle();
        final code = row?['language_code']?.toString().toLowerCase();
        if (const {'tr', 'en', 'de', 'es', 'fr'}.contains(code)) {
          return code!;
        }
      }
    } catch (e) {
      debugPrint('[FCM] language lookup for notification channel failed: $e');
    }
    return 'en';
  }

  Future<void> _verifyAndroidNotificationState() async {
    if (!Platform.isAndroid) return;
    try {
      final android = _localNotifications
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      final enabled = await android?.areNotificationsEnabled() ?? true;
      debugPrint('[FCM] Android notifications enabled=$enabled');
    } catch (e) {
      debugPrint('[FCM] Android notification state check failed: $e');
    }
  }

  Future<void> _syncToken() async {
    if (!_enabled || _messaging == null || _tokenSyncInProgress) return;
    final user = client.auth.currentUser;
    if (user == null) {
      debugPrint('[FCM] token sync skipped: no authenticated user');
      return;
    }
    debugPrint(
      '[FCM] token sync started: platform=${Platform.isIOS ? 'ios' : 'android'}, user=${user.id}',
    );
    await _reportPushDiagnostic(
      'token_sync_started',
      'platform=${Platform.isIOS ? 'ios' : 'android'}',
    );

    _tokenSyncInProgress = true;
    try {
      if (Platform.isIOS) {
        String? apns;
        // Short bounded wait per attempt; the periodic retry above handles
        // APNs tokens that become available later without blocking for a minute.
        for (var i = 0; i < 10; i++) {
          try {
            apns = await _messaging!.getAPNSToken();
          } catch (e) {
            debugPrint('[FCM] APNs token check ${i + 1}/10 failed: $e');
          }
          if (apns != null && apns.isNotEmpty) break;
          await Future<void>.delayed(const Duration(milliseconds: 500));
        }
        if (apns == null || apns.isEmpty) {
          debugPrint(
            '[FCM][IOS_APNS_TOKEN_MISSING] APNs token is null after 5 seconds; background retry in 10 seconds.',
          );
          await _reportPushDiagnostic(
            'ios_apns_token_missing',
            'getAPNSToken returned null after 10 attempts',
          );
          return;
        }
        debugPrint(
          '[FCM][IOS_APNS_TOKEN_OK] APNs token received; requesting FCM token',
        );
        await _reportPushDiagnostic(
          'ios_apns_token_ok',
          'APNs token received; token value intentionally not logged',
        );
      }

      try {
        final token = await _messaging!.getToken();
        if (token == null || token.isEmpty) {
          debugPrint(
            '[FCM][FCM_TOKEN_EMPTY] getToken returned an empty FCM token',
          );
          await _reportPushDiagnostic(
            'fcm_token_empty',
            'FirebaseMessaging.getToken returned null/empty',
          );
          return;
        }
        debugPrint(
          '[FCM][FCM_TOKEN_OK] FCM token obtained; value intentionally not logged',
        );
        await _reportPushDiagnostic(
          'fcm_token_ok',
          'FCM token obtained; token value intentionally not logged',
        );
        // Avoid attaching a token to a different account if auth changed while
        // getToken was awaiting the native Firebase SDK.
        if (client.auth.currentUser?.id != user.id) {
          debugPrint(
            '[FCM] token sync discarded: account changed during token request',
          );
          return;
        }
        await _saveToken(token);
      } catch (e, st) {
        debugPrint(
          '[FCM][FCM_TOKEN_OR_SAVE_ERROR] getToken/save token sync failed: $e\n$st',
        );
        await _reportPushDiagnostic('fcm_token_or_save_error', e.toString());
      }
    } finally {
      _tokenSyncInProgress = false;
    }
  }

  Future<void> _saveToken(String token) async {
    final user = client.auth.currentUser;
    if (user == null || token.isEmpty) return;
    final platform = Platform.isIOS ? 'ios' : 'android';

    // Don't mark the token as registered until the server confirms the write.
    // The auth/session may be missing or the request may fail on iOS.

    // The RPC is an optional server-side helper. Older/already-provisioned
    // Supabase projects may not have it in PostgREST's schema cache yet.
    // Token registration must never make app startup fail in that case, so
    // fall back to the RLS-protected table directly.
    try {
      await client.rpc(
        'register_device_token',
        params: {'p_token': token, 'p_platform': platform},
      );
      _lastRegisteredToken = token;
      _lastRegisteredUserId = user.id;
      debugPrint(
        '[FCM][TOKEN_REGISTERED] device token synced via RPC; platform=$platform user=${user.id}',
      );
      await _reportPushDiagnostic('token_registered_rpc', 'platform=$platform');
      return;
    } catch (e) {
      debugPrint(
        '[FCM][TOKEN_RPC_FAILED] register_device_token failed; trying table fallback: $e',
      );
      await _reportPushDiagnostic('token_rpc_failed', e.toString());
    }

    try {
      await client.from('device_tokens').upsert({
        'user_id': user.id,
        'token': token,
        'platform': platform,
        'updated_at': DateTime.now().toUtc().toIso8601String(),
      }, onConflict: 'token');
      _lastRegisteredToken = token;
      _lastRegisteredUserId = user.id;
      debugPrint(
        '[FCM][TOKEN_REGISTERED] device token synced via table fallback; platform=$platform user=${user.id}',
      );
      await _reportPushDiagnostic(
        'token_registered_table',
        'platform=$platform',
      );
    } catch (e, st) {
      debugPrint(
        '[FCM][TOKEN_TABLE_FAILED] device_tokens fallback failed: $e\n$st',
      );
      await _reportPushDiagnostic('token_table_failed', e.toString());
    }
  }

  Future<void> _reportPushDiagnostic(String stage, String details) async {
    // Diagnostics are best-effort and never block token registration. No device
    // token or credential is written to the diagnostics table.
    try {
      if (client.auth.currentUser == null) return;
      await client.rpc(
        'log_push_device_diagnostic',
        params: {
          'p_stage': stage,
          'p_details': details.length > 1000
              ? details.substring(0, 1000)
              : details,
          'p_platform': Platform.isIOS ? 'ios' : 'android',
        },
      );
    } catch (e) {
      debugPrint('[FCM][DIAGNOSTICS_WRITE_FAILED] $e');
    }
  }

  Future<void> _removeToken(String token) async {
    if (token.isEmpty) return;
    try {
      await client.from('device_tokens').delete().eq('token', token);
      debugPrint('[FCM] old device token removed');
    } catch (e) {
      debugPrint('[FCM] old device token cleanup failed: $e');
    }
  }

  Future<String> _localizedIncomingCallLabel() async {
    try {
      final user = client.auth.currentUser;
      if (user != null) {
        final row = await client
            .from('profiles')
            .select('language_code')
            .eq('id', user.id)
            .maybeSingle();
        switch (row?['language_code']?.toString()) {
          case 'de':
            return 'Eingehender Anruf';
          case 'es':
            return 'Llamada entrante';
          case 'fr':
            return 'Appel entrant';
          case 'en':
            return 'Incoming call';
          default:
            return 'Gelen arama';
        }
      }
      return 'Gelen arama';
    } catch (_) {
      return 'Gelen arama';
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    debugPrint(
      '[FCM] foreground message: ${message.messageId} ${message.data}',
    );
    if (!_localReady) return;

    final data = Map<String, dynamic>.from(message.data);
    final type = data['type']?.toString() ?? '';
    final title =
        message.notification?.title ??
        data['title']?.toString() ??
        'Turtle Dove';
    final body = message.notification?.body ?? data['body']?.toString() ?? '';

    if (type == 'call_end' || data['action']?.toString() == 'call_ended') {
      final callId = data['call_id']?.toString();
      if (callId != null && callId.isNotEmpty) {
        await cancelCallNotification(callId);
      }
      return;
    }

    final isCall =
        type == 'call' || data['action']?.toString() == 'incoming_call';
    // Do not skip the local call notification while the app is in the
    // foreground. The native ringing service is primarily the background /
    // terminated-app transport; when Flutter is already active we still need
    // the call channel to play its ringtone. The Flutter route below remains
    // the single incoming-call UI.
    final notificationId = isCall
        ? _callNotificationId(data)
        : DateTime.now().millisecondsSinceEpoch.remainder(2147483647);
    await _localNotifications.show(
      notificationId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          isCall ? _bestieCallChannelId : _bestieNotificationChannelId,
          isCall ? 'Turtle Dove Calls' : 'Turtle Dove Notifications',
          channelDescription: isCall
              ? 'Incoming Turtle Dove calls'
              : 'Turtle Dove notifications',
          importance: isCall ? Importance.max : Importance.high,
          priority: isCall ? Priority.max : Priority.high,
          playSound: true,
          sound: isCall
              ? RawResourceAndroidNotificationSound('bestie_call_ringtone')
              : null,
          audioAttributesUsage: isCall
              ? AudioAttributesUsage.alarm
              : AudioAttributesUsage.notificationEvent,
          fullScreenIntent: isCall,
          category: isCall
              ? AndroidNotificationCategory.call
              : AndroidNotificationCategory.message,
          visibility: NotificationVisibility.public,
          ongoing: isCall,
          autoCancel: !isCall,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(
          presentAlert: true,
          presentBadge: true,
          presentSound: true,
        ),
      ),
      payload: jsonEncode(data),
    );

    if (isCall) {
      // Foreground: still make the call immediately visible after playing
      // the notification-channel ringtone.
      _handleNavigation(data);
    }
  }

  Future<void> dispose() async {
    _iosTokenRetryTimer?.cancel();
    await _authSubscription?.cancel();
    await _tokenSubscription?.cancel();
    await _messageSubscription?.cancel();
    await _openedSubscription?.cancel();
  }
}

// Avoid importing a UI framework into the notification background path just
// to schedule a callback. This is a tiny main-isolate microtask bridge.
class WidgetsBindingCallback {
  static void schedule(void Function() callback) {
    Future<void>.microtask(callback);
  }
}
