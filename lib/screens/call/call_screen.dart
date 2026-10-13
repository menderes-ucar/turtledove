import 'dart:async';

import 'package:flutter/material.dart';
import '../../localization/app_strings.dart';
import 'package:flutter/foundation.dart';
import 'package:android_pip/android_pip.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';

import 'package:provider/provider.dart';

import '../../models/call_signal_model.dart';
import '../../services/call_service.dart';
import '../../services/mediasoup_call_client.dart';
import '../../services/push_notification_service.dart';

class CallScreen extends StatefulWidget {
  final String userId;
  final String partnerId;
  final String callId;
  final bool isCaller;
  final bool autoAccept;
  final String? callerName;

  const CallScreen({
    super.key,
    required this.userId,
    required this.partnerId,
    required this.callId,
    required this.isCaller,
    this.autoAccept = false,
    this.callerName,
  });

  @override
  State<CallScreen> createState() => _CallScreenState();
}

class _CallScreenState extends State<CallScreen> with WidgetsBindingObserver {
  final RTCVideoRenderer _local = RTCVideoRenderer();
  final RTCVideoRenderer _remoteCamera = RTCVideoRenderer();
  final RTCVideoRenderer _remoteScreen = RTCVideoRenderer();

  MediasoupCallClient? _media;
  StreamSubscription<Map<String, dynamic>>? _mediaEvents;
  StreamSubscription<CallSignal>? _signals;
  StreamSubscription<Map<String, dynamic>?>? _session;

  bool _micOn = true;
  bool _cameraOn = true;
  bool _screenOn = false;
  bool _connected = false;
  bool _busy = true;
  bool _ending = false;
  bool _pipConfigured = false;
  String _status = 'Connecting…';
  Timer? _durationTimer;
  Timer? _heartbeatTimer;
  Duration _duration = Duration.zero;
  DateTime? _connectedAt;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  Future<void> _start() async {
    final callService = context.read<CallService>();
    try {
      await _local.initialize();
      await _remoteCamera.initialize();
      await _remoteScreen.initialize();

      await _configurePip();

      await callService.connect(
        userId: widget.userId,
        partnerId: widget.partnerId,
        callId: widget.callId,
      );

      _signals = callService.signals.listen(_onSignal);
      _session = callService.callSessionStream(widget.callId).listen(
        _onSession,
        onError: (e) => debugPrint('BESTIE mediasoup session stream: $e'),
      );

      final session = await callService.getCallSession(widget.callId);
      final status = session?['status']?.toString();

      if (!widget.isCaller && !widget.autoAccept && status == 'ringing') {
        if (mounted) {
          setState(() {
            _busy = false;
            _status = 'Incoming call';
          });
        }
        return;
      }

      if (!widget.isCaller && widget.autoAccept && status == 'ringing') {
        final accepted = await callService.acceptCall(widget.callId);
        if (!accepted) {
          throw StateError('Call is no longer ringing.');
        }
        await _connectMedia();
      } else if (status == 'accepted') {
        // The receiver has already accepted. Only now is it legal to start
        // mediasoup/WebRTC.
        await _connectMedia();
      } else if (status == 'ringing') {
        if (mounted) setState(() {
          _busy = false;
          _status = widget.isCaller ? 'Calling…' : 'Incoming call';
        });
      } else {
        throw StateError('Call is no longer active.');
      }
    } catch (e) {
      // If the session was accepted but mediasoup failed to connect, do not
      // leave an accepted call behind. That stale row blocks the next call.
      try {
        final failedSession = await callService.getCallSession(widget.callId);
        final failedStatus = failedSession?['status']?.toString();
        if (failedStatus == 'accepted' || failedStatus == 'ringing') {
          await callService.terminateCall(widget.callId);
        }
      } catch (cleanupError) {
        debugPrint('BESTIE CALL failed-start cleanup failed: $cleanupError');
      }
      debugPrint('BESTIE MEDIASOUP CALL START ERROR: $e');
      if (mounted) {
        setState(() {
          _busy = false;
          _status = 'Call connection failed';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _connectMedia() async {
    final media = _media ?? MediasoupCallClient(context.read<CallService>().client);
    _media = media;
    _mediaEvents ??= media.events.listen(_onMediaEvent);

    await media.connect(
      callId: widget.callId,
      userId: widget.userId,
    );
    await media.startLocalMedia();

    _local.srcObject = media.cameraStream;

    if (mounted) {
      setState(() {
        _busy = false;
        _cameraOn = true;
        _status = 'Connected';
      });
      _markConnected();
      _startHeartbeat();
    }
  }

  void _startHeartbeat() {
    _heartbeatTimer?.cancel();
    final calls = context.read<CallService>();
    _heartbeatTimer = Timer.periodic(const Duration(seconds: 25), (_) {
      if (!_ending && _connected) {
        unawaited(calls.heartbeatCall(widget.callId));
      }
    });
    unawaited(calls.heartbeatCall(widget.callId));
  }

  Future<void> _acceptIncoming() async {
    if (_ending || _connected || _busy) return;
    if (mounted) {
      setState(() {
        _busy = true;
        _status = 'Connecting…';
      });
    }
    try {
      final changed = await context.read<CallService>().acceptCall(widget.callId);
      if (!changed) {
        throw StateError('Call is no longer ringing.');
      }
      await context.read<PushNotificationService>().cancelCallNotification(widget.callId);
      await _connectMedia();
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _status = 'Incoming call';
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString())),
        );
      }
    }
  }

  Future<void> _rejectIncoming() async {
    if (_ending || widget.isCaller || _connected) return;
    _ending = true;
    try {
      final calls = context.read<CallService>();
      await calls.rejectCall(widget.callId);
      await context.read<PushNotificationService>().cancelCallNotification(widget.callId);
    } catch (e) {
      debugPrint('BESTIE incoming reject failed: $e');
    }
    if (mounted) Navigator.of(context).pop();
  }

  void _onSession(Map<String, dynamic>? session) {
    final status = session?['status']?.toString();
    if (status == 'accepted' && _media == null && !_ending) {
      // Caller stays on the ringing screen until the receiver accepts.
      // The session transition to accepted is the single gate for media.
      unawaited(_connectMedia());
    }
    if (status == 'ended' || status == 'rejected') {
      unawaited(_finishRemote());
    }
  }

  void _onSignal(CallSignal signal) {
    if (signal.callId != widget.callId) return;
    if (signal.type == 'hangup' || signal.type == 'reject') {
      unawaited(_finishRemote());
    }
  }

  void _onMediaEvent(Map<String, dynamic> event) {
    if (!mounted) return;

    final type = event['event']?.toString();
    if (type == 'remoteTrack') {
      final remote = event['consumer'];
      if (remote is MediasoupRemoteTrack) {
        final source = remote.source;
        if (source == 'screen') {
          _remoteScreen.srcObject = remote.stream;
        } else if (source == 'camera') {
          _remoteCamera.srcObject = remote.stream;
        }
        setState(() {});
      }
    } else if (type == 'transportState') {
      final state = event['state']?.toString() ?? '';
      if (state.contains('connected')) {
        _markConnected();
      }
    } else if (type == 'socketClosed' && !_ending) {
      setState(() => _status = 'Reconnecting…');
    }
  }

  void _markConnected() {
    if (_connected || !mounted) return;
    _connected = true;
    _connectedAt = DateTime.now();
    _durationTimer?.cancel();
    _durationTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      final start = _connectedAt;
      if (start != null && mounted) {
        setState(() => _duration = DateTime.now().difference(start));
      }
    });
    setState(() => _status = 'Connected');
  }

  Future<void> _toggleMic() async {
    final media = _media;
    if (media == null) return;
    final next = !_micOn;
    await media.setMicEnabled(next);
    if (mounted) setState(() => _micOn = next);
  }

  Future<void> _toggleCamera() async {
    final media = _media;
    if (media == null) return;
    final next = !_cameraOn;
    await media.setCameraEnabled(next);
    if (mounted) setState(() => _cameraOn = next);
  }

  Future<void> _switchCamera() async {
    if (!_cameraOn) return;
    final track = _media?.cameraStream?.getVideoTracks().firstOrNull;
    if (track == null) return;
    try {
      await Helper.switchCamera(track, null, _media?.cameraStream);
      if (mounted) setState(() {});
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.of(context).t('camera_switch_failed')}: $e')),
        );
      }
    }
  }

  Future<void> _configurePip() async {
    if (defaultTargetPlatform != TargetPlatform.android || _pipConfigured) return;
    try {
      if (await AndroidPIP.isPipAvailable) {
        await AndroidPIP().setAutoPipMode(
          aspectRatio: const [16, 9],
          seamlessResize: true,
        );
        _pipConfigured = true;
      }
    } catch (e) {
      debugPrint('BESTIE CALL PiP setup skipped: $e');
    }
  }

  Future<void> _enterPip() async {
    if (defaultTargetPlatform != TargetPlatform.android || _ending) return;
    try {
      if (await AndroidPIP.isPipAvailable) {
        await AndroidPIP().enterPipMode(
          aspectRatio: const [16, 9],
          seamlessResize: true,
        );
      }
    } catch (e) {
      debugPrint('BESTIE CALL PiP error: $e');
    }
  }

  Future<void> _toggleScreen() async {
    final media = _media;
    if (media == null) return;

    try {
      if (_screenOn) {
        await media.stopScreenShare();
        if (mounted) setState(() => _screenOn = false);
        return;
      }

      await media.startScreenShare();
      if (mounted) setState(() => _screenOn = true);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${AppStrings.of(context).t('screen_sharing_failed')}: $e')),
        );
      }
    }
  }

  Future<void> _finishRemote() async {
    if (_ending) return;
    _ending = true;
    _durationTimer?.cancel();
    _heartbeatTimer?.cancel();
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _hangUp() async {
    if (_ending) return;
    _ending = true;
    _durationTimer?.cancel();
    _heartbeatTimer?.cancel();

    try {
      await context.read<CallService>().terminateCall(widget.callId);
    } catch (e) {
      debugPrint('BESTIE MEDIASOUP hangup: $e');
    }

    if (mounted) Navigator.of(context).pop();
  }

  String get _durationText {
    final h = _duration.inHours;
    final m = _duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = _duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The media stack remains alive while the OS allows the call to run.
    // We deliberately do not tear down the mediasoup transports on pause.
    if (state == AppLifecycleState.resumed && mounted) {
      setState(() {});
    } else if (state == AppLifecycleState.paused && _connected && !_ending) {
      unawaited(_enterPip());
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _durationTimer?.cancel();
    _heartbeatTimer?.cancel();
    _mediaEvents?.cancel();
    _signals?.cancel();
    _session?.cancel();

    final media = _media;
    _media = null;
    if (media != null) {
      unawaited(media.dispose());
    }

    unawaited(_local.dispose());
    unawaited(_remoteCamera.dispose());
    unawaited(_remoteScreen.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (_remoteScreen.srcObject != null)
              RTCVideoView(
                _remoteScreen,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
              )
            else if (_remoteCamera.srcObject != null)
              RTCVideoView(
                _remoteCamera,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              )
            else
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.videocam, color: Colors.white54, size: 56),
                    const SizedBox(height: 12),
                    Text(
                      widget.callerName ?? 'BESTIE',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 22,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _status,
                      style: const TextStyle(color: Colors.white60),
                    ),
                  ],
                ),
              ),

            Positioned(
              top: 16,
              left: 16,
              right: 16,
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.callerName ?? 'BESTIE',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                  if (_connected)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: Text(
                        _durationText,
                        style: const TextStyle(color: Colors.white),
                      ),
                    ),
                ],
              ),
            ),

            if (_local.srcObject != null && _cameraOn)
              Positioned(
                right: 16,
                top: 70,
                width: 118,
                height: 170,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(16),
                  child: RTCVideoView(
                    _local,
                    mirror: true,
                    objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                  ),
                ),
              ),

            if (!_busy && !_connected && !widget.isCaller && _status == 'Incoming call')
              Positioned(
                left: 24,
                right: 24,
                bottom: 110,
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _control(
                      icon: Icons.call,
                      background: Colors.green,
                      onTap: _acceptIncoming,
                    ),
                    const SizedBox(width: 28),
                    _control(
                      icon: Icons.call_end,
                      background: Colors.red,
                      onTap: _rejectIncoming,
                    ),
                  ],
                ),
              ),

            if (_connected)
              Positioned(
                left: 20,
                right: 20,
                bottom: 20,
                child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  _control(
                    icon: _micOn ? Icons.mic : Icons.mic_off,
                    onTap: _toggleMic,
                  ),
                  _control(
                    icon: _cameraOn ? Icons.videocam : Icons.videocam_off,
                    onTap: _toggleCamera,
                  ),
                  _control(
                    icon: Icons.cameraswitch,
                    onTap: _switchCamera,
                  ),
                  _control(
                    icon: _screenOn
                        ? Icons.stop_screen_share
                        : Icons.screen_share,
                    onTap: _toggleScreen,
                  ),
                  _control(
                    icon: Icons.picture_in_picture_alt,
                    onTap: _enterPip,
                  ),
                  _control(
                    icon: Icons.call_end,
                    background: Colors.red,
                    onTap: _hangUp,
                  ),
                ],
              ),
            ),

            if (_busy)
              const Center(
                child: CircularProgressIndicator(color: Colors.white),
              ),
          ],
        ),
      ),
    );
  }

  Widget _control({
    required IconData icon,
    required VoidCallback onTap,
    Color background = const Color(0xAA222222),
  }) {
    return Material(
      color: background,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(
          width: 58,
          height: 58,
          child: Icon(icon, color: Colors.white, size: 27),
        ),
      ),
    );
  }
}
