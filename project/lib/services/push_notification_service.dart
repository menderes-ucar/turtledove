import 'dart:async';
import 'dart:convert';
import 'dart:io' show Platform;

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';

import '../firebase_options.dart';

const MethodChannel _nativeSystemChannel = MethodChannel('bestie/system');

const AndroidNotificationChannel _bestieChannel = AndroidNotificationChannel(
  'bestie_notifications_v3',
  'Bestie Notifications',
  description: 'Bestie notifications',
  importance: Importance.high,
  playSound: true,
  sound: null,
  audioAttributesUsage: AudioAttributesUsage.notificationEvent,
);

final AndroidNotificationChannel _bestieCallChannel = AndroidNotificationChannel(
  'bestie_calls_v3',
  'Bestie Calls',
  description: 'Incoming Bestie calls',
  importance: Importance.max,
  playSound: true,
  sound: RawResourceAndroidNotificationSound('bestie_call_ringtone'),
  audioAttributesUsage: AudioAttributesUsage.notificationRingtone,
);

final FlutterLocalNotificationsPlugin _localNotifications =
    FlutterLocalNotificationsPlugin();

int _callNotificationId(Map<String, dynamic> data) {
  final callId = data['call_id']?.toString() ?? data['notification_id']?.toString() ?? 'bestie-call';
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
      final android = _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await android?.createNotificationChannel(_bestieChannel);
      await android?.createNotificationChannel(_bestieCallChannel);
    }

    final data = Map<String, dynamic>.from(message.data);
    final type = data['type']?.toString() ?? '';
    final title = data['title']?.toString() ?? message.notification?.title ?? 'Bestie';
    final body = data['body']?.toString() ?? message.notification?.body ?? '';

    // Android calls are owned by BestieFirebaseMessagingService +
    // BestieCallRingingService. Do not also create a one-shot Flutter local
    // notification: that was the source of the single-ring behaviour.
    if (Platform.isAndroid && (type == 'call' || type == 'call_end' || data['action']?.toString() == 'incoming_call' || data['action']?.toString() == 'call_ended')) {
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
          'Bestie Calls',
          channelDescription: 'Incoming Bestie calls',
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
  debugPrint('[FCM] background message: ${message.messageId} data=${message.data}');
  await _showBackgroundLocalNotification(message);
}

class PushNotificationService {
  final SupabaseClient client;

  Future<void> cancelCallNotification(String callId) async {
    try {
      await _localNotifications.cancel(_callNotificationId({'call_id': callId}));
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
          final pending = await _nativeSystemChannel.invokeMethod<dynamic>('getPendingIncomingCall');
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
        if (event.event != AuthChangeEvent.signedOut) unawaited(_syncToken());
      });
      _tokenSubscription = _messaging!.onTokenRefresh.listen(
        (token) => unawaited(_saveToken(token)),
      );
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
      final androidPlugin = _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.createNotificationChannel(_bestieChannel);
      await androidPlugin?.createNotificationChannel(_bestieCallChannel);
      await androidPlugin?.requestNotificationsPermission();
      try {
        await androidPlugin?.requestFullScreenIntentPermission();
      } catch (e) {
        debugPrint('[FCM] full-screen intent permission request skipped: $e');
      }
    }

    // Recover a notification that launched the process/full-screen Activity.
    // This is required for call actions when the app was not already running.
    final launchDetails = await _localNotifications.getNotificationAppLaunchDetails();
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
    debugPrint('[FCM] permission status: ${settings.authorizationStatus.name}');
  }

  Future<void> _verifyAndroidNotificationState() async {
    if (!Platform.isAndroid) return;
    try {
      final android = _localNotifications.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();
      final enabled = await android?.areNotificationsEnabled() ?? true;
      debugPrint('[FCM] Android notifications enabled=$enabled');
    } catch (e) {
      debugPrint('[FCM] Android notification state check failed: $e');
    }
  }

  Future<void> _syncToken() async {
    if (!_enabled || _messaging == null) return;
    final user = client.auth.currentUser;
    if (user == null) return;

    if (Platform.isIOS) {
      String? apns;
      for (var i = 0; i < 20; i++) {
        apns = await _messaging!.getAPNSToken();
        if (apns != null && apns.isNotEmpty) break;
        await Future<void>.delayed(const Duration(milliseconds: 500));
      }
      if (apns == null || apns.isEmpty) {
        debugPrint('[FCM] APNs token not available yet');
        return;
      }
    }

    try {
      final token = await _messaging!.getToken();
      if (token == null || token.isEmpty) return;
      await _saveToken(token);
    } catch (e, st) {
      debugPrint('[FCM] getToken failed: $e\n$st');
    }
  }

  Future<void> _saveToken(String token) async {
    final user = client.auth.currentUser;
    if (user == null || token.isEmpty) return;
    final platform = Platform.isIOS ? 'ios' : 'android';

    // The RPC is an optional server-side helper. Older/already-provisioned
    // Supabase projects may not have it in PostgREST's schema cache yet.
    // Token registration must never make app startup fail in that case, so
    // fall back to the RLS-protected table directly.
    try {
      await client.rpc('register_device_token', params: {
        'p_token': token,
        'p_platform': platform,
      });
      debugPrint('[FCM] token synced successfully via RPC');
      return;
    } catch (e) {
      debugPrint('[FCM] register_device_token RPC unavailable; using table fallback: $e');
    }

    try {
      await client.from('device_tokens').upsert(
        {
          'user_id': user.id,
          'token': token,
          'platform': platform,
          'updated_at': DateTime.now().toUtc().toIso8601String(),
        },
        onConflict: 'token',
      );
      debugPrint('[FCM] token synced successfully via table fallback');
    } catch (e, st) {
      debugPrint('[FCM] device_tokens fallback failed: $e\n$st');
    }
  }

  Future<String> _localizedIncomingCallLabel() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final code = prefs.getString('app_locale') ?? 'tr';
      switch (code) {
        case 'de': return 'Eingehender Anruf';
        case 'es': return 'Llamada entrante';
        case 'fr': return 'Appel entrant';
        case 'en': return 'Incoming call';
        default: return 'Gelen arama';
      }
    } catch (_) {
      return 'Gelen arama';
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    debugPrint('[FCM] foreground message: ${message.messageId} ${message.data}');
    if (!_localReady) return;

    final data = Map<String, dynamic>.from(message.data);
    final type = data['type']?.toString() ?? '';
    final title = message.notification?.title ?? data['title']?.toString() ?? 'Bestie';
    final body = message.notification?.body ?? data['body']?.toString() ?? '';

    if (type == 'call_end' || data['action']?.toString() == 'call_ended') {
      final callId = data['call_id']?.toString();
      if (callId != null && callId.isNotEmpty) {
        await cancelCallNotification(callId);
      }
      return;
    }

    final isCall = type == 'call' || data['action']?.toString() == 'incoming_call';
    if (Platform.isAndroid && isCall) {
      // Native BestieCallRingingService owns Android ringing + CallStyle.
      // Flutter only routes the already-running app into the call screen.
      _handleNavigation(data);
      return;
    }
    final notificationId = isCall ? _callNotificationId(data) :
        DateTime.now().millisecondsSinceEpoch.remainder(2147483647);
    await _localNotifications.show(
      notificationId,
      title,
      body,
      NotificationDetails(
        android: AndroidNotificationDetails(
          isCall ? 'bestie_calls_v3' : 'bestie_notifications_v3',
          isCall ? 'Bestie Calls' : 'Bestie Notifications',
          channelDescription: isCall ? 'Incoming Bestie calls' : 'Bestie notifications',
          importance: isCall ? Importance.max : Importance.high,
          priority: isCall ? Priority.max : Priority.high,
          playSound: true,
          sound: isCall ? RawResourceAndroidNotificationSound('bestie_call_ringtone') : null,
          audioAttributesUsage: isCall ? AudioAttributesUsage.alarm : AudioAttributesUsage.notificationEvent,
          fullScreenIntent: isCall,
          category: isCall ? AndroidNotificationCategory.call : AndroidNotificationCategory.message,
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
