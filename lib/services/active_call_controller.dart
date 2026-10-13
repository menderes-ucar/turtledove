import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'call_service.dart';
import 'mediasoup_call_client.dart';
import '../models/call_signal_model.dart';

/// Owns an active mediasoup call while the call route is minimized.
///
/// The important rule is that minimizing a call must NOT dispose the media
/// client. The WebRTC transports and camera/microphone continue running while
/// the user navigates through BESTIE. The call route can later claim the same
/// media client again.
class ActiveCallController extends ChangeNotifier {
  MediasoupCallClient? _media;
  CallService? _callService;
  StreamSubscription<Map<String, dynamic>>? _mediaEvents;
  StreamSubscription<CallSignal>? _signals;
  StreamSubscription<Map<String, dynamic>?>? _session;

  String? callId;
  String? userId;
  String? partnerId;
  String? callerName;
  bool isCaller = false;
  bool minimized = false;

  MediaStream? remoteCameraStream;
  MediaStream? remoteScreenStream;

  bool get hasActiveCall => _media != null && callId != null;
  MediasoupCallClient? get media => _media;

  Future<void> minimize({
    required MediasoupCallClient media,
    required CallService callService,
    required String activeCallId,
    required String activeUserId,
    required String activePartnerId,
    required bool activeIsCaller,
    String? activeCallerName,
    MediaStream? currentRemoteCamera,
    MediaStream? currentRemoteScreen,
  }) async {
    await _detachSubscriptions();

    _media = media;
    _callService = callService;
    callId = activeCallId;
    userId = activeUserId;
    partnerId = activePartnerId;
    isCaller = activeIsCaller;
    callerName = activeCallerName;
    remoteCameraStream = currentRemoteCamera;
    remoteScreenStream = currentRemoteScreen;
    minimized = true;

    _listenWhileMinimized();
    notifyListeners();
  }

  MediasoupCallClient? claim(String activeCallId) {
    if (!hasActiveCall || callId != activeCallId) return null;
    final result = _media;
    _detachSubscriptions();
    minimized = false;
    notifyListeners();
    return result;
  }

  Future<void> endActiveCall() async {
    final media = _media;
    _media = null;
    await _detachSubscriptions();
    if (media != null) {
      try {
        await media.dispose();
      } catch (_) {}
    }
    callId = null;
    userId = null;
    partnerId = null;
    callerName = null;
    remoteCameraStream = null;
    remoteScreenStream = null;
    minimized = false;
    notifyListeners();
  }

  void _listenWhileMinimized() {
    final media = _media;
    final calls = _callService;
    final id = callId;
    if (media == null || calls == null || id == null) return;

    _mediaEvents = media.events.listen((event) {
      if (event['event']?.toString() == 'remoteTrack') {
        final remote = event['consumer'];
        if (remote is MediasoupRemoteTrack) {
          if (remote.source == 'camera') {
            remoteCameraStream = remote.stream;
          } else if (remote.source == 'screen') {
            remoteScreenStream = remote.stream;
          }
          notifyListeners();
        }
      }
    });

    _signals = calls.signals.listen((signal) {
      if (signal.callId != id) return;
      if (signal.type == 'hangup' || signal.type == 'reject') {
        unawaited(endActiveCall());
      }
    });

    _session = calls.callSessionStream(id).listen((row) {
      final status = row?['status']?.toString();
      if (status == 'ended' || status == 'rejected') {
        unawaited(endActiveCall());
      }
    });
  }

  Future<void> _detachSubscriptions() async {
    await _mediaEvents?.cancel();
    await _signals?.cancel();
    await _session?.cancel();
    _mediaEvents = null;
    _signals = null;
    _session = null;
  }

  @override
  void dispose() {
    unawaited(_detachSubscriptions());
    super.dispose();
  }
}
