import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:android_pip/android_pip.dart';
import 'package:provider/provider.dart';
import 'package:audioplayers/audioplayers.dart';

import '../../localization/app_strings.dart';
import '../../models/call_signal_model.dart';
import '../../services/call_service.dart';
import '../../services/push_notification_service.dart';

/// Production call surface for BESTIE.
///
/// Media model:
/// - One RTCPeerConnection for the entire call.
/// - Three negotiated media sections: microphone, camera and screen video.
/// - Both cameras are opened before the first offer/answer, so a video call
///   starts like WhatsApp: both participants immediately see themselves and
///   each other.
/// - Camera toggles use track.enabled. Screen start/stop uses replaceTrack on a
///   pre-negotiated sendrecv video section; no setDirection() or renegotiation is needed.
/// - Transceivers are mapped by media kind/order, never by hard-coded mids.
///   Android/WebRTC may assign mids differently when an optional section is
///   rejected.
/// - Screen video is handled as a separate RTP video sender.
/// - System/playback audio is intentionally NOT mixed into the microphone.
///   Android requires an AudioPlaybackCapture/WebRTC audio-device integration,
///   while iOS full-device capture requires a ReplayKit Broadcast Extension.
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
  RTCPeerConnection? _peer;

  // Local sources. They intentionally stay alive while a call is active so a
  // camera can be turned off/on without creating another RTP receiver track.
  MediaStream? _microphoneStream;
  MediaStream? _cameraStream;
  MediaStream? _screenStream;

  // RTP senders. Camera is added before the first offer so the initial SDP
  // contains a real camera track. Screen is added only when sharing starts,
  // then negotiated once; this avoids phantom/empty video m-lines on Android.
  RTCRtpSender? _micSender;
  RTCRtpSender? _cameraSender;
  RTCRtpSender? _screenSender;
  String? _cameraMid;
  String? _screenMid;

  final RTCVideoRenderer _localCameraRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _localScreenRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteCameraRenderer = RTCVideoRenderer();
  final RTCVideoRenderer _remoteScreenRenderer = RTCVideoRenderer();

  final AudioPlayer _ringtone = AudioPlayer();
  StreamSubscription<CallSignal>? _signals;
  Future<void> _signalQueue = Future<void>.value();

  static const MethodChannel _mediaProjectionChannel =
      MethodChannel('bestie/media_projection');

  bool _micOn = true;
  bool _cameraOn = false;
  bool _screenOn = false;
  bool _connected = false;
  bool _starting = true;
  bool _ending = false;
  bool _incomingPending = false;
  bool _pipConfigured = false;
  bool _cameraBusy = false;
  bool _screenBusy = false;
  bool _remoteCamera = false;
  bool _remoteScreen = false;
  bool _localCameraExpanded = false;
  bool _remoteDescriptionSet = false;
  bool _initialOfferSent = false;
  bool _autoAcceptStarted = false;
  bool _makingOffer = false;
  String? _incomingCallerName;

  String _status = 'Connecting…';
  String? _lastOfferSdp;
  String? _lastAnswerSdp;

  String? _remoteCameraTrackId;
  String? _remoteScreenTrackId;
  String? _remoteCameraStreamId;
  String? _remoteScreenStreamId;

  final List<RTCIceCandidate> _pendingRemoteCandidates = [];
  final Map<String, MediaStream> _remoteStreamsByTrackId = {};
  final Map<String, MediaStream> _remoteStreamsByMid = {};
  final Map<String, MediaStreamTrack> _remoteVideoTracks = {};
  int _remoteVideoArrivalOrder = 0;
  Future<void>? _incomingConnectFuture;
  StreamSubscription<Map<String, dynamic>?>? _callSessionSubscription;
  int _ringtoneGeneration = 0;
  bool _ringing = false;
  bool _ringtoneStopped = true;
  Offset _localTileOffset = const Offset(12, 88);

  @override
  void initState() {
    super.initState();
    _incomingCallerName = widget.callerName;
    WidgetsBinding.instance.addObserver(this);
    unawaited(_start());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused &&
        defaultTargetPlatform == TargetPlatform.android &&
        _connected &&
        !_ending &&
        !_screenBusy) {
      unawaited(_enterPip());
    }
  }

  Future<void> _watchCallSession() async {
    try {
      final service = context.read<CallService>();
      await service.getCallSession(widget.callId).then(_handleCallSessionState);
      _callSessionSubscription?.cancel();
      _callSessionSubscription = service.callSessionStream(widget.callId).listen(
        _handleCallSessionState,
        onError: (Object error, StackTrace stack) {
          debugPrint('BESTIE CALL session stream error: $error');
        },
      );
    } catch (e) {
      debugPrint('BESTIE CALL session watcher failed: $e');
    }
  }

  void _handleCallSessionState(Map<String, dynamic>? row) {
    if (!mounted || _ending || row == null) return;
    final status = row['status']?.toString() ?? '';
    if (status != 'ended' && status != 'rejected') return;

    // The durable call row is authoritative. This closes a stale incoming
    // screen even when the realtime hangup signal was missed, and it also
    // closes the native/background flow after the caller has cancelled.
    _ending = true;
    _incomingPending = false;
    unawaited(_stopRingtone());
    debugPrint('BESTIE CALL SESSION CLOSED call=${widget.callId} status=$status');
    Navigator.of(context).pop();
  }

  Future<void> _start() async {
    try {
      await _localCameraRenderer.initialize();
      await _localScreenRenderer.initialize();
      await _remoteCameraRenderer.initialize();
      await _remoteScreenRenderer.initialize();

      final calls = context.read<CallService>();
      if (!widget.isCaller && (_incomingCallerName == null || _incomingCallerName!.trim().isEmpty)) {
        try {
          final row = await calls.client
              .from('profiles')
              .select('username')
              .eq('id', widget.partnerId)
              .maybeSingle();
          _incomingCallerName = row?['username']?.toString();
        } catch (e) {
          debugPrint('BESTIE CALL caller name lookup failed: $e');
        }
      }
      unawaited(_watchCallSession());
      _signals = calls.signals.listen((signal) {
        _signalQueue = _signalQueue.then((_) => _handleSignal(signal));
      });

      if (!widget.isCaller) {
        if (!mounted) return;
        setState(() {
          _starting = false;
          _incomingPending = true;
          _status = AppStrings.of(context).incomingCall;
        });
        unawaited(_startRingtone());

        _incomingConnectFuture = calls.connect(
          userId: widget.userId,
          partnerId: widget.partnerId,
          callId: widget.callId,
        );
        unawaited(_incomingConnectFuture!);
        unawaited(
          context
              .read<PushNotificationService>()
              .cancelCallNotification(widget.callId),
        );
        unawaited(_configurePip());

        if (widget.autoAccept && !_autoAcceptStarted) {
          _autoAcceptStarted = true;
          unawaited(_autoAcceptIncoming());
        }
        return;
      }

      await calls.connect(
        userId: widget.userId,
        partnerId: widget.partnerId,
        callId: widget.callId,
      );
      await _configurePip();
      await _createPeer();

      if (!mounted) return;
      setState(() {
        _starting = false;
        _status = AppStrings.of(context).startCall;
      });
    } catch (e) {
      debugPrint('BESTIE CALL start error: $e');
      _showMediaError('${AppStrings.of(context).callFailed}: $e');
      if (mounted) {
        setState(() {
          _starting = false;
          _status = AppStrings.of(context).callFailed;
        });
      }
    }
  }

  Future<void> _autoAcceptIncoming() async {
    try {
      await _incomingConnectFuture;
      if (mounted && _incomingPending && !_ending) {
        await _acceptIncomingCall();
      }
    } catch (e) {
      debugPrint('BESTIE CALL auto-accept error: $e');
    }
  }

  Future<void> _startRingtone() async {
    if (defaultTargetPlatform == TargetPlatform.android ||
        widget.isCaller ||
        !_incomingPending ||
        _ending ||
        _ringing) {
      return;
    }

    final generation = ++_ringtoneGeneration;
    _ringing = true;
    _ringtoneStopped = false;
    try {
      await _ringtone.setReleaseMode(ReleaseMode.loop);
      await _ringtone.setVolume(1);
      if (_ringtoneStopped ||
          !_ringing ||
          generation != _ringtoneGeneration ||
          _ending ||
          !_incomingPending) {
        return;
      }
      unawaited(_ringtone.play(AssetSource('sounds/call_ringtone.wav')));
    } catch (e) {
      debugPrint('BESTIE CALL ringtone error: $e');
    }
  }

  Future<void> _stopRingtone() async {
    ++_ringtoneGeneration;
    _ringing = false;
    _ringtoneStopped = true;
    unawaited(_ringtone.stop().catchError((_) {}));
    unawaited(_ringtone.release().catchError((_) {}));
  }

  Future<void> _createPeer() async {
    if (_peer != null) return;

    final turnUrl = dotenv.env['TURN_URL']?.trim() ?? '';
    final turnUser = dotenv.env['TURN_USERNAME']?.trim() ?? '';
    final turnCredential = dotenv.env['TURN_CREDENTIAL']?.trim() ?? '';

    final config = <String, dynamic>{
      'sdpSemantics': 'unified-plan',
      'bundlePolicy': 'max-bundle',
      'rtcpMuxPolicy': 'require',
      'iceServers': [
        {'urls': 'stun:stun.l.google.com:19302'},
        if (turnUrl.isNotEmpty)
          {
            'urls': turnUrl,
            'username': turnUser,
            'credential': turnCredential,
          },
      ],
    };

    final peer = await createPeerConnection(config);
    _peer = peer;

    try {
      await Helper.setSpeakerphoneOn(true);
    } catch (_) {}

    // Do not pre-create an empty screen transceiver. On Android that can
    // produce an unsignaled/empty receiver which is later mistaken for the
    // partner camera and can also make the first camera frame black. The
    // microphone and camera are real tracks before the initial offer; screen
    // gets a real sender only when sharing starts.
    debugPrint('BESTIE CALL MEDIA PLAN: mic + camera are real senders before offer; screen is on-demand');

    peer.onIceCandidate = (candidate) async {
      if (candidate.candidate == null || _ending) return;
      try {
        await context.read<CallService>().send(
          type: 'ice',
          callId: widget.callId,
          data: {
            'candidate': candidate.candidate,
            'sdpMid': candidate.sdpMid,
            'sdpMLineIndex': candidate.sdpMLineIndex,
          },
        );
      } catch (e) {
        debugPrint('BESTIE CALL ICE send error: $e');
      }
    };

    peer.onTrack = (event) {
      unawaited(_attachRemoteTrack(event));
    };

    peer.onAddTrack = (stream, track) {
      if (track.kind == 'video') {
        unawaited(_attachRemoteVideo(track, stream));
      }
    };

    peer.onAddStream = (stream) {
      for (final track in stream.getVideoTracks()) {
        unawaited(_attachRemoteVideo(track, stream));
      }
    };

    peer.onConnectionState = (state) {
      if (!mounted) return;
      final connected =
          state == RTCPeerConnectionState.RTCPeerConnectionStateConnected;
      setState(() {
        _connected = connected;
        _status = connected
            ? AppStrings.of(context).connectedCall
            : _stateText(state);
      });
    };

    peer.onIceConnectionState = (state) {
      debugPrint('BESTIE CALL ICE state=$state');
    };

    // Establish audio + camera before the first offer/answer. This makes the
    // initial call a real two-way video call instead of requiring a later media
    // negotiation just to reveal the local camera. Camera failure must not kill
    // the audio call (permission/device failure is handled independently).
    await _ensureMicrophone();
    await _ensureInitialCamera();
  }

  Future<void> _ensureInitialCamera() async {
    if (_cameraStream != null || _peer == null) return;

    try {
      final stream = await _openCamera();
      final track = stream.getVideoTracks().firstOrNull;
      if (track == null) {
        await stream.dispose();
        throw StateError('Android returned no camera video track.');
      }

      track.enabled = true;
      _cameraStream = stream;
      _cameraOn = true;
      _localCameraRenderer.srcObject = stream;
      _cameraSender = await _peer!.addTrack(track, stream);
      await _setSenderStreams(_cameraSender, stream);
      await _setVideoParameters(_cameraSender, screen: false);
      await _preferStableVideoCodecs();
      debugPrint('BESTIE CALL INITIAL CAMERA track=${track.id} sender=${_cameraSender?.senderId}');
    } catch (e) {
      _cameraOn = false;
      debugPrint('BESTIE CALL initial camera unavailable: $e');
    }
  }

  Future<void> _ensureMicrophone() async {
    if (_microphoneStream != null || _peer == null) return;

    final stream = await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
      },
      'video': false,
    });

    final track = stream.getAudioTracks().firstOrNull;
    if (track == null) {
      await stream.dispose();
      throw StateError('No microphone track was returned.');
    }

    track.enabled = _micOn;
    _microphoneStream = stream;
    _micSender = await _peer!.addTrack(track, stream);
    await _setSenderStreams(_micSender, stream);
  }

  Future<void> _refreshTransceivers() async {
    final peer = _peer;
    if (peer == null) return;

    try {
      final list = await peer.getTransceivers();
      final cameraId = _cameraStream?.getVideoTracks().firstOrNull?.id;
      final screenId = _screenStream?.getVideoTracks().firstOrNull?.id;

      for (final t in list) {
        final id = t.sender.track?.id;
        if (id != null && id == cameraId) {
          _cameraMid = t.mid;
        }
        if (id != null && id == screenId) {
          _screenMid = t.mid;
        }
      }

      final mids = list
          .where((t) => t.sender.track?.kind == 'video' || t.receiver.track?.kind == 'video')
          .map((t) => t.mid)
          .whereType<String>()
          .toList();
      if (_cameraMid == null && mids.isNotEmpty) _cameraMid = mids.first;
      if (_screenMid == null && mids.length > 1) _screenMid = mids[1];

      debugPrint(
        'BESTIE CALL MEDIA mids camera=$_cameraMid screen=$_screenMid '
        'senders camera=${_cameraSender?.senderId} screen=${_screenSender?.senderId}',
      );
    } catch (e) {
      debugPrint('BESTIE CALL refresh transceivers failed: $e');
    }
  }

  Future<void> _replaceTrack(RTCRtpSender? sender, MediaStreamTrack? track) async {
    if (sender == null) {
      throw StateError('Required RTP sender is unavailable.');
    }
    await sender.replaceTrack(track);
  }

  Future<void> _setSenderStreams(RTCRtpSender? sender, MediaStream stream) async {
    if (sender == null) return;
    try {
      await sender.setStreams([stream]);
    } catch (e) {
      debugPrint('BESTIE CALL setStreams skipped: $e');
    }
  }

  Future<void> _setVideoParameters(
    RTCRtpSender? sender, {
    required bool screen,
  }) async {
    if (sender == null) return;
    try {
      final params = sender.parameters;
      final encodings = params.encodings;
      // Target quality modes:
      //   normal call       = 1080p / 60fps
      //   screen share      = 720p / 30fps
      //   screen + camera   = 720p / 30fps for both video tracks
      // The network/encoder may negotiate lower values, but BESTIE never
      // intentionally asks for 480p/15fps.
      final maxBitrate = screen ? 5_500_000 : (_screenOn ? 4_000_000 : 8_000_000);
      final minBitrate = screen ? 1_000_000 : 500_000;
      final maxFramerate = screen ? 30 : (_screenOn ? 30 : 60);

      if (encodings == null || encodings.isEmpty) {
        params.encodings = [
          RTCRtpEncoding(
            active: true,
            maxBitrate: maxBitrate,
            minBitrate: minBitrate,
            maxFramerate: maxFramerate,
            scaleResolutionDownBy: screen ? 1.0 : 1.0,
          ),
        ];
      } else {
        for (final encoding in encodings) {
          encoding.active = true;
          encoding.maxBitrate = maxBitrate;
          encoding.minBitrate = minBitrate;
          encoding.maxFramerate = maxFramerate;
          encoding.scaleResolutionDownBy = 1.0;
        }
      }
      params.degradationPreference = screen
          ? RTCDegradationPreference.MAINTAIN_FRAMERATE
          : RTCDegradationPreference.MAINTAIN_RESOLUTION;
      await sender.setParameters(params);
    } catch (e) {
      debugPrint('BESTIE CALL video parameter tuning skipped: $e');
    }
  }

  Future<void> _createOfferAndSend({required bool initial}) async {
    final peer = _peer;
    if (peer == null || _ending) return;

    try {
      final session = await context.read<CallService>().getCallSession(widget.callId);
      if (session?['status']?.toString() != 'accepted') {
        debugPrint('BESTIE CALL offer blocked; session=${session?['status']}');
        return;
      }

      final state = await peer.getSignalingState();
      if (state != RTCSignalingState.RTCSignalingStateStable) {
        debugPrint('BESTIE CALL offer deferred; signalingState=$state');
        return;
      }

      // Read the actual tracks immediately before SDP generation. Do not trust
      // a stale boolean: SDP must describe the media that is really attached.
      final cameraTrack = _cameraStream?.getVideoTracks().firstOrNull;
      final screenTrack = _screenStream?.getVideoTracks().firstOrNull;
      _cameraOn = cameraTrack?.enabled == true;
      _screenOn = screenTrack != null;

      final offer = await peer.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      });
      await peer.setLocalDescription(offer);
      await _refreshTransceivers();

      _initialOfferSent = true;
      debugPrint(
        'BESTIE CALL OFFER initial=$initial '
        'camera=$_cameraOn screen=$_screenOn '
        'cameraTrack=${cameraTrack?.id} screenTrack=${screenTrack?.id}',
      );

      await context.read<CallService>().send(
        type: 'offer',
        callId: widget.callId,
        data: {
          'sdp': offer.sdp,
          'type': offer.type,
          'camera': _cameraOn,
          'screen': _screenOn,
          'cameraTrackId': cameraTrack?.id,
          'screenTrackId': screenTrack?.id,
        },
      );
    } catch (e) {
      debugPrint('BESTIE CALL create/send offer failed: $e');
      if (initial) _initialOfferSent = false;
      rethrow;
    }
  }

  Future<void> _acceptIncomingCall() async {
    if (widget.isCaller || !_incomingPending || _ending) return;

    _incomingPending = false;
    await _stopRingtone();
    if (mounted) {
      setState(() {
        _starting = true;
        _status = AppStrings.of(context).connectingCall;
      });
    }

    final calls = context.read<CallService>();
    try {
      await _incomingConnectFuture;
      await _createPeer();

      // Build the receiver before telling the caller that it can offer. The
      // durable DB update is useful for call history, but the realtime accept
      // signal is the event that actually starts SDP. Treat them independently
      // so a transient DB/update failure cannot leave the UI stuck on
      // "Incoming call". Retry the low-latency accept signal briefly.
      bool acceptedInSession;
      try {
        acceptedInSession = await calls.acceptCall(widget.callId);
      } catch (e) {
        debugPrint('BESTIE CALL accept session update failed: $e');
        acceptedInSession = false;
      }

      if (!acceptedInSession) {
        final session = await calls.getCallSession(widget.callId);
        final status = session?['status']?.toString();
        if (status != 'ringing') {
          _ending = true;
          if (mounted) Navigator.of(context).pop();
          return;
        }
        throw StateError('Call session could not be accepted while it was still ringing.');
      }

      Object? lastAcceptError;
      var acceptedSignalSent = false;
      for (var attempt = 1; attempt <= 3 && !acceptedSignalSent; attempt++) {
        try {
          await calls.send(type: 'accept', callId: widget.callId);
          acceptedSignalSent = true;
        } catch (e) {
          lastAcceptError = e;
          debugPrint('BESTIE CALL accept signal attempt=$attempt failed: $e');
          if (attempt < 3) {
            await Future<void>.delayed(const Duration(milliseconds: 250));
          }
        }
      }

      if (!acceptedSignalSent) {
        throw StateError('Accept signal could not be delivered: $lastAcceptError');
      }

      // Tell the caller immediately that the receiver's initial camera is on.
      // The answer SDP carries the RTP section; this metadata lets the UI bind
      // the incoming track before/while onTrack is delivered.
      await _sendMediaState();

      unawaited(
        context
            .read<PushNotificationService>()
            .cancelCallNotification(widget.callId),
      );

      if (mounted) {
        setState(() {
          _starting = false;
          _status = AppStrings.of(context).connectingCall;
        });
      }
    } catch (e) {
      debugPrint('BESTIE CALL accept failed: $e');
      if (mounted) {
        setState(() {
          _incomingPending = false;
          _starting = false;
          _status = AppStrings.of(context).callFailed;
        });
      }
      _showMediaError('${AppStrings.of(context).callFailed}: $e');
    }
  }

  Future<void> _rejectIncomingCall() async {
    if (widget.isCaller || _ending) return;
    _ending = true;
    _incomingPending = false;
    await _stopRingtone();

    final calls = context.read<CallService>();
    try {
      await _incomingConnectFuture;
      final rejected = await calls.rejectCallSession(widget.callId);
      if (rejected) {
        try {
          await calls.send(type: 'reject', callId: widget.callId);
        } catch (_) {}
      }
      await context
          .read<PushNotificationService>()
          .cancelCallNotification(widget.callId);
    } catch (_) {}
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _handleSignal(CallSignal signal) async {
    if (_ending || signal.callId != widget.callId) return;

    try {
      switch (signal.type) {
        case 'accept':
          if (widget.isCaller) {
            // The accept signal is only a transport hint. The call-session row
            // is authoritative. A receiver can tap Accept at the same moment
            // the caller taps Hang Up; never start WebRTC for a call that has
            // already transitioned to ended/rejected.
            final session = await context
                .read<CallService>()
                .getCallSession(widget.callId);
            if (session?['status']?.toString() != 'accepted') {
              debugPrint(
                'BESTIE CALL accept ignored; session is ${session?['status']}',
              );
              return;
            }
            await _createOfferAndSend(initial: true);
          }
          return;

        case 'offer':
          await _handleOffer(signal);
          return;

        case 'answer':
          await _handleAnswer(signal);
          return;

        case 'ice':
          await _handleIce(signal);
          return;

        case 'media_state':
          _handleRemoteMediaState(signal.data);
          return;

        case 'hangup':
        case 'reject':
          _ending = true;
          _incomingPending = false;
          unawaited(_stopRingtone());
          if (mounted) Navigator.of(context).pop();
          return;
      }
    } catch (e) {
      debugPrint('BESTIE CALL signal ${signal.type} error: $e');
    }
  }

  Future<void> _handleOffer(CallSignal signal) async {
    final peer = _peer;
    if (peer == null) return;

    final sdp = signal.data['sdp']?.toString();
    final type = signal.data['type']?.toString();
    if (sdp == null || type == null || sdp.isEmpty) return;
    if (_lastOfferSdp == sdp) return;

    var state = await peer.getSignalingState();
    if (state != RTCSignalingState.RTCSignalingStateStable) {
      if (widget.isCaller) {
        debugPrint('BESTIE CALL glare: caller ignored incoming offer state=$state');
        return;
      }
      try {
        await peer.setLocalDescription(RTCSessionDescription('', 'rollback'));
        state = await peer.getSignalingState();
      } catch (e) {
        debugPrint('BESTIE CALL polite rollback failed: $e');
      }
      if (state != RTCSignalingState.RTCSignalingStateStable) return;
    }

    _lastOfferSdp = sdp;
    _remoteCamera = signal.data['camera'] == true;
    _remoteScreen = signal.data['screen'] == true;
    _remoteCameraTrackId = signal.data['cameraTrackId']?.toString();
    _remoteScreenTrackId = signal.data['screenTrackId']?.toString();

    if (!_remoteCamera) _remoteCameraRenderer.srcObject = null;
    if (!_remoteScreen) _remoteScreenRenderer.srcObject = null;

    await peer.setRemoteDescription(RTCSessionDescription(sdp, type));
    _remoteDescriptionSet = true;
    await _refreshTransceivers();
    await _flushPendingCandidates();

    final answer = await peer.createAnswer({
      'offerToReceiveAudio': true,
      'offerToReceiveVideo': true,
    });
    await peer.setLocalDescription(answer);
    await _refreshTransceivers();

    await context.read<CallService>().send(
      type: 'answer',
      callId: widget.callId,
      data: {'sdp': answer.sdp, 'type': answer.type},
    );

    if (mounted) setState(() {});
  }

  Future<void> _handleAnswer(CallSignal signal) async {
    final peer = _peer;
    if (peer == null) return;

    final sdp = signal.data['sdp']?.toString();
    final type = signal.data['type']?.toString();
    if (sdp == null || type == null || sdp.isEmpty) return;
    if (_lastAnswerSdp == sdp) return;

    final state = await peer.getSignalingState();
    if (state != RTCSignalingState.RTCSignalingStateHaveLocalOffer) {
      debugPrint('BESTIE CALL stale answer ignored state=$state');
      return;
    }

    _lastAnswerSdp = sdp;
    await peer.setRemoteDescription(RTCSessionDescription(sdp, type));
    _remoteDescriptionSet = true;
    await _refreshTransceivers();
    await _flushPendingCandidates();
  }

  Future<void> _handleIce(CallSignal signal) async {
    final peer = _peer;
    if (peer == null) return;

    final candidateText = signal.data['candidate']?.toString();
    if (candidateText == null || candidateText.isEmpty) return;

    final rawIndex = signal.data['sdpMLineIndex'];
    final index = rawIndex is num ? rawIndex.toInt() : null;
    final candidate = RTCIceCandidate(
      candidateText,
      signal.data['sdpMid']?.toString(),
      index,
    );

    if (!_remoteDescriptionSet) {
      _pendingRemoteCandidates.add(candidate);
      return;
    }

    try {
      await peer.addCandidate(candidate);
    } catch (e) {
      debugPrint('BESTIE CALL add ICE error: $e');
    }
  }

  Future<void> _flushPendingCandidates() async {
    final peer = _peer;
    if (peer == null || !_remoteDescriptionSet) return;
    if (_pendingRemoteCandidates.isEmpty) return;

    final pending = List<RTCIceCandidate>.from(_pendingRemoteCandidates);
    _pendingRemoteCandidates.clear();
    for (final candidate in pending) {
      try {
        await peer.addCandidate(candidate);
      } catch (e) {
        debugPrint('BESTIE CALL pending ICE error: $e');
      }
    }
  }

  Future<void> _attachRemoteTrack(RTCTrackEvent event) async {
    if (event.track.kind != 'video') return;
    final stream = event.streams.isNotEmpty
        ? event.streams.first
        : await _createRemoteStream(event.track);
    await _attachRemoteVideo(event.track, stream, mid: event.transceiver?.mid);
  }

  Future<MediaStream> _createRemoteStream(MediaStreamTrack track) async {
    final stream = await createLocalMediaStream('bestie-remote-${track.id}');
    await stream.addTrack(track);
    return stream;
  }

  Future<void> _attachRemoteVideo(
    MediaStreamTrack track,
    MediaStream stream, {
    String? mid,
  }) async {
    if (track.kind != 'video') return;

    final trackId = track.id;
    if (trackId == null || trackId.isEmpty) return;

    _remoteStreamsByTrackId[trackId] = stream;
    _remoteVideoTracks[trackId] = track;
    if (mid != null && mid.isNotEmpty) {
      _remoteStreamsByMid[mid] = stream;
    }

    // Android flutter_webrtc can deliver onAddTrack without a Dart
    // transceiver/mid. Never classify a second video track as "screen" merely
    // because it arrived second: the screen media section exists permanently,
    // so an empty screen section may still produce a receiver track on some
    // Android/WebRTC versions. That was the source of the duplicate-partner
    // tile and black remote video after stopping screen share.
    final cameraMid = _cameraMid;
    final screenMid = _screenMid;
    bool camera = trackId == _remoteCameraTrackId ||
        (mid != null && cameraMid != null && mid == cameraMid);
    bool screen = trackId == _remoteScreenTrackId ||
        (mid != null && screenMid != null && mid == screenMid);

    // A mid is stronger than arrival order. On Android the Dart track id can
    // differ across the native bridge, while the negotiated transceiver mid
    // remains stable for the lifetime of this PeerConnection.
    if (mid != null && mid.isNotEmpty) {
      if (cameraMid != null && mid == cameraMid) {
        camera = true;
        screen = false;
      } else if (screenMid != null && mid == screenMid) {
        screen = true;
        camera = false;
      }
    }

    if (!camera && !screen) {
      if (_remoteScreen && !_remoteCamera) {
        // Only screen is active: the first useful video receiver is the screen.
        screen = true;
      } else if (_remoteCamera && !_remoteScreen) {
        // Camera-only call: additional empty video receivers are ignored.
        camera = _remoteCameraTrackId == null &&
            _remoteCameraRenderer.srcObject == null;
      } else if (_remoteCamera && _remoteScreen) {
        // Both active. The fixed negotiated order is audio, camera, screen.
        // Use the first unbound track as camera and the next as screen.
        final cameraAlreadyBound = _remoteCameraTrackId != null &&
            _remoteStreamsByTrackId.containsKey(_remoteCameraTrackId);
        final screenAlreadyBound = _remoteScreenTrackId != null &&
            _remoteStreamsByTrackId.containsKey(_remoteScreenTrackId);
        if (!cameraAlreadyBound) {
          camera = true;
        } else if (!screenAlreadyBound && trackId != _remoteCameraTrackId) {
          screen = true;
        }
      }
    }

    // When neither media flag says the remote is publishing video, do not put
    // a stale/empty receiver into either renderer. The receiver can remain
    // negotiated; the UI must follow the sender's media state.
    if (!_remoteCamera && !_remoteScreen) {
      debugPrint(
        'BESTIE CALL IGNORE REMOTE VIDEO track=$trackId mid=$mid '
        'because remote camera/screen are both OFF',
      );
      return;
    }

    debugPrint(
      'BESTIE CALL REMOTE VIDEO track=$trackId mid=$mid '
      'camera=$camera screen=$screen '
      'remoteState(camera=$_remoteCamera,screen=$_remoteScreen)',
    );

    if (camera && !screen && _remoteCamera) {
      if (_remoteCameraRenderer.srcObject != stream) {
        _remoteCameraRenderer.srcObject = stream;
      }
      _remoteCameraTrackId = trackId;
      _remoteCameraStreamId = stream.id;
    } else if (screen && _remoteScreen) {
      if (_remoteScreenRenderer.srcObject != stream) {
        _remoteScreenRenderer.srcObject = stream;
      }
      _remoteScreenTrackId = trackId;
      _remoteScreenStreamId = stream.id;
    }

    if (mounted) setState(() {});
  }

  void _handleRemoteMediaState(Map<String, dynamic> data) {
    _remoteCamera = data['camera'] == true;
    _remoteScreen = data['screen'] == true;
    _remoteCameraTrackId = data['cameraTrackId']?.toString();
    _remoteScreenTrackId = data['screenTrackId']?.toString();

    // A track id is authoritative when supplied. If the sender turns a source
    // off, clear only that renderer; never leave the old frame visible.
    if (!_remoteCamera) {
      _remoteCameraRenderer.srcObject = null;
      _remoteCameraStreamId = null;
      _remoteCameraTrackId = null;
    }
    if (!_remoteScreen) {
      _remoteScreenRenderer.srcObject = null;
      _remoteScreenStreamId = null;
      _remoteScreenTrackId = null;
    }

    final cameraId = _remoteCameraTrackId;
    final screenId = _remoteScreenTrackId;
    if (_remoteCamera && cameraId != null && cameraId.isNotEmpty) {
      final stream = _remoteStreamsByTrackId[cameraId];
      if (stream != null) {
        _remoteCameraRenderer.srcObject = stream;
        _remoteCameraStreamId = stream.id;
      }
    }
    if (_remoteScreen && screenId != null && screenId.isNotEmpty) {
      final stream = _remoteStreamsByTrackId[screenId];
      if (stream != null) {
        _remoteScreenRenderer.srcObject = stream;
        _remoteScreenStreamId = stream.id;
      }
    }

    // Android may deliver onAddTrack before media_state. Reconcile using the
    // already received tracks, but ONLY according to the currently active
    // sources. Never invent a screen renderer when screen=false.
    final ids = _remoteVideoTracks.keys.toList();
    if (_remoteCamera && _remoteCameraRenderer.srcObject == null) {
      final candidate = cameraId != null && ids.contains(cameraId)
          ? cameraId
          : ids.isNotEmpty ? ids.first : null;
      if (candidate != null) {
        _remoteCameraTrackId = candidate;
        _remoteCameraRenderer.srcObject = _remoteStreamsByTrackId[candidate];
      }
    }
    if (_remoteScreen && _remoteScreenRenderer.srcObject == null) {
      final candidate = screenId != null && ids.contains(screenId)
          ? screenId
          : ids.where((id) => id != _remoteCameraTrackId).firstOrNull;
      if (candidate != null) {
        _remoteScreenTrackId = candidate;
        _remoteScreenRenderer.srcObject = _remoteStreamsByTrackId[candidate];
      }
    }

    if (mounted) setState(() {});
  }

  Future<void> _sendMediaState() async {
    try {
      await context.read<CallService>().send(
        type: 'media_state',
        callId: widget.callId,
        data: {
          'camera': _cameraOn,
          'screen': _screenOn,
          'cameraTrackId': _cameraStream?.getVideoTracks().firstOrNull?.id,
          'screenTrackId': _screenStream?.getVideoTracks().firstOrNull?.id,
        },
      );
    } catch (e) {
      debugPrint('BESTIE CALL media state error: $e');
    }
  }

  Future<MediaStream> _openCamera() async {
    try {
      return await Helper.openCamera({
        'audio': false,
        'video': {
          'facingMode': 'user',
          // Normal call target: 1920x1080 @ 60fps.
          // When screen sharing starts we adapt the existing track to 1280x720
          // @ 30fps instead of reopening the camera and renegotiating it.
          'width': {'ideal': 1920, 'max': 1920},
          'height': {'ideal': 1080, 'max': 1080},
          'frameRate': {'ideal': 60, 'max': 60},
        },
      });
    } catch (e) {
      debugPrint('BESTIE CALL Helper.openCamera fallback: $e');
      return navigator.mediaDevices.getUserMedia({
        'audio': false,
        'video': {
          'facingMode': 'user',
          // Normal call target: 1920x1080 @ 60fps.
          // When screen sharing starts we adapt the existing track to 1280x720
          // @ 30fps instead of reopening the camera and renegotiating it.
          'width': {'ideal': 1920, 'max': 1920},
          'height': {'ideal': 1080, 'max': 1080},
          'frameRate': {'ideal': 60, 'max': 60},
        },
      });
    }
  }

  Future<void> _toggleMic() async {
    _micOn = !_micOn;
    for (final track in _microphoneStream?.getAudioTracks() ?? <MediaStreamTrack>[]) {
      track.enabled = _micOn;
    }
    if (mounted) setState(() {});
  }

  Future<void> _toggleCamera() async {
    if (_cameraBusy || _ending || _peer == null) return;
    _cameraBusy = true;
    try {
      await _refreshTransceivers();
      if (_cameraStream == null) {
        final stream = await _openCamera();
        final track = stream.getVideoTracks().firstOrNull;
        if (track == null) {
          await stream.dispose();
          throw StateError('Android returned no camera video track.');
        }
        _cameraStream = stream;
        _localCameraRenderer.srcObject = stream;
        _cameraSender = await _peer!.addTrack(track, stream);
        await _setSenderStreams(_cameraSender, stream);
        await _setVideoParameters(_cameraSender, screen: false);
        _cameraOn = true;
      } else {
        final track = _cameraStream!.getVideoTracks().firstOrNull;
        if (track == null) throw StateError('Camera track disappeared.');
        // Keep the exact same RTP track. This is the critical part that makes
        // off -> on instantaneous for the remote receiver as well.
        track.enabled = !track.enabled;
        _cameraOn = track.enabled;
        if (!_cameraOn) {
          _localCameraRenderer.srcObject = _cameraStream;
        }
      }

      await _sendMediaState();
      debugPrint(
        'BESTIE CALL CAMERA state=$_cameraOn '
        'track=${_cameraStream?.getVideoTracks().firstOrNull?.id} '
        'sender=${_cameraSender?.senderId} mid=$_cameraMid',
      );
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('BESTIE CALL camera error: $e');
      _showMediaError('${AppStrings.of(context).cameraOpenFailed}: $e');
    } finally {
      _cameraBusy = false;
    }
  }

  Future<void> _switchCamera() async {
    if (!_cameraOn) return;
    final track = _cameraStream?.getVideoTracks().firstOrNull;
    if (track == null) return;
    try {
      await Helper.switchCamera(track, null, _cameraStream);
    } catch (e) {
      _showMediaError('${AppStrings.of(context).cameraSwitchFailed}: $e');
    }
  }

  Future<void> _renegotiate() async {
    final peer = _peer;
    if (peer == null || _ending || _makingOffer) return;

    final state = await peer.getSignalingState();
    if (state != RTCSignalingState.RTCSignalingStateStable) {
      debugPrint('BESTIE CALL renegotiation deferred state=$state');
      return;
    }

    _makingOffer = true;
    try {
      final offer = await peer.createOffer({
        'offerToReceiveAudio': true,
        'offerToReceiveVideo': true,
      });
      await peer.setLocalDescription(offer);
      await _refreshTransceivers();
      final cameraTrack = _cameraStream?.getVideoTracks().firstOrNull;
      final screenTrack = _screenStream?.getVideoTracks().firstOrNull;
      await context.read<CallService>().send(
        type: 'offer',
        callId: widget.callId,
        data: {
          'sdp': offer.sdp,
          'type': offer.type,
          'camera': _cameraOn,
          'screen': _screenOn,
          'cameraTrackId': cameraTrack?.id,
          'screenTrackId': screenTrack?.id,
        },
      );
      debugPrint('BESTIE CALL RENEGOTIATION sent camera=$_cameraOn screen=$_screenOn');
    } finally {
      _makingOffer = false;
    }
  }

  Future<void> _adaptCameraForCallMode({required bool screenSharing}) async {
    final track = _cameraStream?.getVideoTracks().firstOrNull;
    if (track == null) return;

    try {
      if (screenSharing) {
        await track.adaptRes(1280, 720);
      } else {
        await track.adaptRes(1920, 1080);
      }
    } catch (e) {
      debugPrint('BESTIE CALL camera adaptRes skipped: $e');
    }

    await _setVideoParameters(_cameraSender, screen: false);
  }

  Future<void> _preferStableVideoCodecs() async {
    final peer = _peer;
    if (peer == null) return;

    try {
      final capabilities = await getRtpSenderCapabilities('video');
      final codecs = List<RTCRtpCodecCapability>.from(
        capabilities.codecs ?? const <RTCRtpCodecCapability>[],
      );
      if (codecs.isEmpty) return;

      int rank(RTCRtpCodecCapability codec) {
        final mime = codec.mimeType.toUpperCase();
        if (mime == 'VIDEO/H264') return 0;
        if (mime == 'VIDEO/VP8') return 1;
        if (mime == 'VIDEO/VP9') return 2;
        return 3;
      }

      codecs.sort((a, b) => rank(a).compareTo(rank(b)));
      final transceivers = await peer.getTransceivers();
      for (final transceiver in transceivers) {
        if (transceiver.sender.track?.kind == 'video') {
          try {
            await transceiver.setCodecPreferences(codecs);
          } catch (e) {
            debugPrint('BESTIE CALL codec preference skipped mid=${transceiver.mid}: $e');
          }
        }
      }
    } catch (e) {
      debugPrint('BESTIE CALL codec capability lookup skipped: $e');
    }
  }

  Future<void> _toggleScreen() async {
    if (_screenBusy || _ending || _peer == null) return;
    _screenBusy = true;
    try {
      if (_screenOn) {
        await _stopScreenShareInternal();
        return;
      }

      if (defaultTargetPlatform == TargetPlatform.android) {
        final granted = await Helper.requestCapturePermission(fullScreenOnly: true);
        if (!granted) {
          _showMediaError('Screen sharing permission was denied.');
          return;
        }
        await _mediaProjectionChannel.invokeMethod('start');
      }

      final stream = await navigator.mediaDevices.getDisplayMedia({
        // Android's current flutter_webrtc implementation captures the
        // physical display at its native size/30fps; these constraints are not
        // used by the native capturer. We adapt the track immediately below.
        'video': true,
        'audio': false,
      });

      final videoTrack = stream.getVideoTracks().firstOrNull;
      if (videoTrack == null) {
        await stream.dispose();
        throw StateError('Android returned no screen video track.');
      }

      // Reduce the screen source before it enters the encoder. This is the
      // critical performance path for high-resolution Android/Huawei displays.
      try {
        await videoTrack.adaptRes(1280, 720);
      } catch (e) {
        debugPrint('BESTIE CALL screen adaptRes skipped: $e');
      }

      // Android can end MediaProjection from the system shade. Treat that as
      // a normal screen-share stop so the remote side immediately returns to
      // the camera view instead of freezing the last screen frame.
      videoTrack.onEnded = () {
        if (!_ending && _screenOn) {
          unawaited(_stopScreenShareInternal());
        }
      };

      // Two-video mode is explicitly 720p/30 for both tracks. Keep the same
      // camera track/sender; only adapt its capture size and RTP envelope.
      await _adaptCameraForCallMode(screenSharing: true);

      _screenStream = stream;
      _localScreenRenderer.srcObject = stream;
      if (_screenSender == null) {
        _screenSender = await _peer!.addTrack(videoTrack, stream);
      } else {
        await _replaceTrack(_screenSender, videoTrack);
      }
      await _setSenderStreams(_screenSender, stream);
      await _setVideoParameters(_screenSender, screen: true);
      await _refreshTransceivers();

      debugPrint('BESTIE CALL SCREEN AUDIO unavailable in flutter_webrtc Android capture path');

      _screenOn = true;
      await _sendMediaState();
      await _renegotiate();
      debugPrint(
        'BESTIE CALL SCREEN state=true track=${videoTrack.id} '
        'sender=${_screenSender?.senderId} mid=$_screenMid',
      );
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('BESTIE CALL screen error: $e');
      await _mediaProjectionChannel.invokeMethod('stop').catchError((_) {});
      _showMediaError('${AppStrings.of(context).screenShareStartFailed}: $e');
    } finally {
      _screenBusy = false;
    }
  }

  Future<void> _stopScreenShareInternal() async {
    try {
      final track = _screenStream?.getVideoTracks().firstOrNull;
      _screenOn = false;

      // Detach from RTP first, then stop MediaProjection. This avoids a short
      // frozen-frame interval on the remote receiver.
      await _replaceTrack(_screenSender, null);

      if (track != null) {
        try {
          await track.stop();
        } catch (_) {}
      }

      await _screenStream?.dispose();
      _screenStream = null;
      await _adaptCameraForCallMode(screenSharing: false);
      _localScreenRenderer.srcObject = null;
      _screenOn = false;
      await _mediaProjectionChannel.invokeMethod('stop').catchError((_) {});
      await _sendMediaState();
      await _renegotiate();
      if (mounted) setState(() {});
    } catch (e) {
      debugPrint('BESTIE CALL stop screen error: $e');
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

  Future<void> _hangup() async {
    if (_ending) return;
    _ending = true;
    await _stopRingtone();

    // Shut down the local capture and WebRTC audio path BEFORE leaving the
    // route. Relying on widget disposal alone can leave Android's audio device
    // alive for a short time, which is why audio could continue after hangup.
    try {
      await _mediaProjectionChannel.invokeMethod('stop');
    } catch (_) {}
    await _stopAllCallMedia();

    final calls = context.read<CallService>();
    try {
      await calls.terminateCall(widget.callId);
    } catch (e) {
      debugPrint('BESTIE CALL hangup signaling failed: $e');
    }

    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _stopAllCallMedia() async {
    final peer = _peer;
    if (peer != null) {
      try {
        final senders = await peer.getSenders();
        for (final sender in senders) {
          try {
            await sender.replaceTrack(null);
          } catch (_) {}
        }
      } catch (_) {}
      try {
        final receivers = await peer.getReceivers();
        for (final receiver in receivers) {
          try {
            await receiver.track?.stop();
          } catch (_) {}
        }
      } catch (_) {}
      try {
        await peer.close();
      } catch (_) {}
      _peer = null;
    }

    for (final stream in <MediaStream?>[
      _microphoneStream,
      _cameraStream,
      _screenStream,
    ]) {
      for (final track in stream?.getTracks() ?? <MediaStreamTrack>[]) {
        try {
          await track.stop();
        } catch (_) {}
      }
      try {
        await stream?.dispose();
      } catch (_) {}
    }

    _microphoneStream = null;
    _cameraStream = null;
    _screenStream = null;
    _localCameraRenderer.srcObject = null;
    _localScreenRenderer.srcObject = null;
    _remoteCameraRenderer.srcObject = null;
    _remoteScreenRenderer.srcObject = null;

    try {
      await Helper.setSpeakerphoneOn(false);
    } catch (_) {}
  }

  void _showMediaError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  String _stateText(RTCPeerConnectionState state) {
    switch (state) {
      case RTCPeerConnectionState.RTCPeerConnectionStateNew:
        return AppStrings.of(context).preparingCall;
      case RTCPeerConnectionState.RTCPeerConnectionStateConnecting:
        return AppStrings.of(context).connectingCall;
      case RTCPeerConnectionState.RTCPeerConnectionStateConnected:
        return AppStrings.of(context).connectedCall;
      case RTCPeerConnectionState.RTCPeerConnectionStateDisconnected:
        return AppStrings.of(context).connectionLost;
      case RTCPeerConnectionState.RTCPeerConnectionStateFailed:
        return AppStrings.of(context).connectionFailed;
      case RTCPeerConnectionState.RTCPeerConnectionStateClosed:
        return AppStrings.of(context).callClosed;
    }
  }

  void _dragLocalTile(DragUpdateDetails details, Size size) {
    const tileWidth = 118.0;
    const tileHeight = 166.0;
    final maxX = (size.width - tileWidth - 12).clamp(12.0, double.infinity);
    final maxY = (size.height - tileHeight - 116).clamp(80.0, double.infinity);
    final next = _localTileOffset + details.delta;
    setState(() {
      _localTileOffset = Offset(
        next.dx.clamp(12.0, maxX),
        next.dy.clamp(80.0, maxY),
      );
    });
  }

  Widget _localCameraTile(Size size, {required bool screenShareMode}) {
    if (!_cameraOn || _localCameraRenderer.srcObject == null) {
      return const SizedBox.shrink();
    }

    final width = _localCameraExpanded ? 180.0 : 118.0;
    final height = _localCameraExpanded ? 255.0 : 166.0;
    final maxX = (size.width - width - 12).clamp(12.0, double.infinity);
    final maxY = (size.height - height - 116).clamp(80.0, double.infinity);
    final left = screenShareMode
        ? (size.width / 2 - width - 6).clamp(12.0, maxX)
        : _localTileOffset.dx.clamp(12.0, maxX);
    final top = screenShareMode
        ? 18.0
        : _localTileOffset.dy.clamp(80.0, maxY);

    return Positioned(
      left: left,
      top: top,
      child: GestureDetector(
        onTap: () => setState(() => _localCameraExpanded = !_localCameraExpanded),
        onPanUpdate: screenShareMode ? null : (d) => _dragLocalTile(d, size),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          width: width,
          height: height,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white30),
            boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 18)],
          ),
          clipBehavior: Clip.antiAlias,
          child: Stack(
            fit: StackFit.expand,
            children: [
              RTCVideoView(
                _localCameraRenderer,
                mirror: true,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
              ),
              Positioned(
                right: 7,
                bottom: 7,
                child: Material(
                  color: Colors.black87,
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: _switchCamera,
                    customBorder: const CircleBorder(),
                    child: const Padding(
                      padding: EdgeInsets.all(8),
                      child: Icon(Icons.flip_camera_ios_rounded, color: Colors.white, size: 18),
                    ),
                  ),
                ),
              ),
              Positioned(
                left: 7,
                bottom: 7,
                child: _label(AppStrings.of(context).you),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _cameraMiniTile({
    required RTCVideoRenderer renderer,
    required String label,
  }) {
    return SizedBox(
      width: 118,
      height: 166,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(18),
        child: Stack(
          fit: StackFit.expand,
          children: [
            RTCVideoView(
              renderer,
              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
            ),
            Positioned(left: 7, bottom: 7, child: _label(label)),
          ],
        ),
      ),
    );
  }

  Widget _screenShareCameraStrip() {
    final hasLocal = _cameraOn && _localCameraRenderer.srcObject != null;
    final hasRemote = _remoteCamera && _remoteCameraRenderer.srcObject != null;
    if (!hasLocal && !hasRemote) return const SizedBox.shrink();

    return Positioned(
      top: 14,
      left: 0,
      right: 0,
      child: SafeArea(
        bottom: false,
        child: Center(
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (hasLocal) ...[
                _cameraMiniTile(
                  renderer: _localCameraRenderer,
                  label: AppStrings.of(context).you,
                ),
                if (hasRemote) const SizedBox(width: 8),
              ],
              if (hasRemote)
                _cameraMiniTile(
                  renderer: _remoteCameraRenderer,
                  label: AppStrings.of(context).partner,
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black54,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }

  Widget _screenLocalOverlay() {
    if (!_screenOn || _localScreenRenderer.srcObject == null) {
      return const SizedBox.shrink();
    }
    return Positioned(
      top: 18,
      left: 14,
      child: SizedBox(
        width: 118,
        height: 166,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: Stack(
            fit: StackFit.expand,
            children: [
              RTCVideoView(
                _localScreenRenderer,
                objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
              ),
              Positioned(left: 7, bottom: 7, child: _label(AppStrings.of(context).you)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _controls() {
    return Positioned(
      left: 14,
      right: 14,
      bottom: 14,
      child: SafeArea(
        top: false,
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: Colors.black.withValues(alpha: .76),
            borderRadius: BorderRadius.circular(30),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _CallButton(
                  icon: _micOn ? Icons.mic : Icons.mic_off,
                  active: _micOn,
                  onTap: _toggleMic,
                ),
                const SizedBox(width: 10),
                _CallButton(
                  icon: _cameraOn ? Icons.videocam : Icons.videocam_off,
                  active: _cameraOn,
                  onTap: _toggleCamera,
                ),
                const SizedBox(width: 10),
                _CallButton(
                  icon: _screenOn ? Icons.stop_screen_share : Icons.screen_share,
                  active: _screenOn,
                  onTap: _toggleScreen,
                ),
                const SizedBox(width: 10),
                _CallButton(
                  icon: Icons.call_end,
                  active: false,
                  danger: true,
                  onTap: _hangup,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _incomingOverlay() {
    if (!_incomingPending || widget.autoAccept) return const SizedBox.shrink();

    return Positioned.fill(
      child: ColoredBox(
        color: Colors.black.withValues(alpha: .92),
        child: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.all(28),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircleAvatar(
                    radius: 56,
                    child: Icon(Icons.person, size: 56),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    _incomingCallerName?.trim().isNotEmpty == true
                        ? _incomingCallerName!.trim()
                        : AppStrings.of(context).incomingCall,
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 25, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    AppStrings.of(context).incomingCall,
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    AppStrings.of(context).acceptToStartCall,
                    style: const TextStyle(color: Colors.white70, fontSize: 15),
                  ),
                  const SizedBox(height: 34),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      _IncomingCallAction(
                        icon: Icons.call_end,
                        label: AppStrings.of(context).decline,
                        color: Colors.red,
                        onTap: _rejectIncomingCall,
                      ),
                      const SizedBox(width: 44),
                      _IncomingCallAction(
                        icon: Icons.call,
                        label: AppStrings.of(context).accept,
                        color: Colors.green,
                        onTap: _acceptIncomingCall,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final showRemoteScreen = _remoteScreen && _remoteScreenRenderer.srcObject != null;
    final showLocalScreen = !showRemoteScreen && _screenOn && _localScreenRenderer.srcObject != null;
    final showScreen = showRemoteScreen || showLocalScreen;

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && !_ending) unawaited(_enterPip());
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        body: SafeArea(
          child: Stack(
            fit: StackFit.expand,
            children: [
              // Main media surface: remote screen > local screen preview >
              // remote camera > voice placeholder.
              if (showRemoteScreen)
                RTCVideoView(
                  _remoteScreenRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                )
              else if (showLocalScreen)
                RTCVideoView(
                  _localScreenRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitContain,
                )
              else if (_remoteCamera && _remoteCameraRenderer.srcObject != null)
                RTCVideoView(
                  _remoteCameraRenderer,
                  objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                )
              else
                Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const CircleAvatar(
                        radius: 42,
                        child: Icon(Icons.favorite, size: 42),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        _connected ? AppStrings.of(context).voiceCall : _status,
                        style: const TextStyle(color: Colors.white, fontSize: 18),
                      ),
                    ],
                  ),
                ),

              // During screen share the shared screen is the main surface and
              // both participant cameras appear exactly once in a fixed top strip.
              if (showScreen)
                _screenShareCameraStrip()
              else
                _localCameraTile(size, screenShareMode: false),

              if (!showScreen) const SizedBox.shrink(),

              Positioned(
                top: 10,
                left: 0,
                right: 0,
                child: IgnorePointer(
                  child: Center(
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: Colors.black45,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        child: Text(
                          showRemoteScreen
                              ? AppStrings.of(context).screenShareActiveRemote
                              : showLocalScreen
                                  ? AppStrings.of(context).screenShareActiveLocal
                                  : _status,
                          style: const TextStyle(color: Colors.white70, fontSize: 12),
                        ),
                      ),
                    ),
                  ),
                ),
              ),

              Positioned(
                top: 10,
                right: 10,
                child: Material(
                  color: Colors.black54,
                  shape: const CircleBorder(),
                  child: InkWell(
                    onTap: _enterPip,
                    customBorder: const CircleBorder(),
                    child: const Padding(
                      padding: EdgeInsets.all(10),
                      child: Icon(Icons.picture_in_picture_alt, color: Colors.white, size: 20),
                    ),
                  ),
                ),
              ),

              if (!_incomingPending) _controls(),
              _incomingOverlay(),
              if (_starting)
                const Center(child: CircularProgressIndicator(color: Colors.white)),
            ],
          ),
        ),
      ),
    );
  }

  @override
  void dispose() {
    _ending = true;
    WidgetsBinding.instance.removeObserver(this);
    _signals?.cancel();
    _callSessionSubscription?.cancel();
    context.read<CallService>().releaseIncomingCallUi(widget.callId);
    _ringtone.dispose();
    _mediaProjectionChannel.invokeMethod('stop').catchError((_) {});
    unawaited(_stopAllCallMedia());
    _localCameraRenderer.dispose();
    _localScreenRenderer.dispose();
    _remoteCameraRenderer.dispose();
    _remoteScreenRenderer.dispose();
    _remoteStreamsByTrackId.clear();
    _remoteStreamsByMid.clear();
    super.dispose();
  }
}

class _IncomingCallAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _IncomingCallAction({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Material(
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Icon(icon, color: Colors.white, size: 30),
            ),
          ),
        ),
        const SizedBox(height: 9),
        Text(
          label,
          style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
        ),
      ],
    );
  }
}

class _CallButton extends StatelessWidget {
  final IconData icon;
  final bool active;
  final bool danger;
  final VoidCallback onTap;

  const _CallButton({
    required this.icon,
    required this.active,
    required this.onTap,
    this.danger = false,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: danger ? Colors.red : (active ? Colors.white24 : Colors.white12),
      shape: const CircleBorder(),
      child: InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Icon(icon, color: Colors.white),
        ),
      ),
    );
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
