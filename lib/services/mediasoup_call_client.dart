import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:mediasfu_mediasoup_client/mediasfu_mediasoup_client.dart' as ms;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:web_socket_channel/io.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class MediasoupRemoteTrack {
  final ms.Consumer consumer;
  final String source;
  final String peerId;

  const MediasoupRemoteTrack({
    required this.consumer,
    required this.source,
    required this.peerId,
  });

  MediaStream get stream => consumer.stream;
  MediaStreamTrack get track => consumer.track;
}

/// Self-hosted mediasoup client. No hosted SFU/Cloud account is required.
///
/// Signaling is a plain WebSocket connection to the user's own mediasoup
/// server. Supabase remains the durable call/session layer.
class MediasoupCallClient {
  final SupabaseClient supabase;
  MediasoupCallClient(this.supabase);

  WebSocketChannel? _socket;
  StreamSubscription? _socketSubscription;

  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final Map<String, Completer<Map<String, dynamic>>> _pending = {};
  final Map<String, ms.Producer> producers = {};
  final Map<String, ms.Consumer> consumers = {};
  final Set<String> _pendingProducerIds = <String>{};

  ms.Device? _device;
  ms.Transport? _sendTransport;
  ms.Transport? _recvTransport;
  MediaStream? _micStream;
  MediaStream? _cameraStream;
  MediaStream? _screenStream;

  String? _callId;
  String? _userId;
  int _requestId = 0;
  bool _closed = false;

  static const MethodChannel _mediaProjectionChannel = MethodChannel('bestie/media_projection');

  Stream<Map<String, dynamic>> get events => _events.stream;
  MediaStream? get cameraStream => _cameraStream;
  MediaStream? get screenStream => _screenStream;

  bool get isReady =>
      !_closed &&
      _socket != null &&
      _device?.loaded == true &&
      _sendTransport != null &&
      _recvTransport != null;

  Future<void> connect({
    required String callId,
    required String userId,
  }) async {
    if (isReady && _callId == callId && _userId == userId) return;

    await close();

    final url = (dotenv.env['MEDIASOUP_SIGNALING_URL'] ?? '').trim();
    if (url.isEmpty) {
      throw StateError(
        'MEDIASOUP_SIGNALING_URL is missing. Add it to .env.',
      );
    }

    final session = supabase.auth.currentSession;
    final accessToken = session?.accessToken;
    if (accessToken == null || accessToken.isEmpty) {
      throw StateError('Supabase session is missing.');
    }

    _closed = false;
    _callId = callId;
    _userId = userId;

    final channel = IOWebSocketChannel.connect(
      Uri.parse(url),
      headers: {'Authorization': 'Bearer $accessToken'},
      pingInterval: const Duration(seconds: 15),
    );
    _socket = channel;

    final ready = Completer<void>();
    _socketSubscription = channel.stream.listen(
      (message) {
        _handleMessage(message);
        if (!ready.isCompleted) {
          final decoded = _decode(message);
          if (decoded?['event'] == 'joined') {
            ready.complete();
          } else if (decoded?['error'] != null) {
            ready.completeError(StateError(decoded!['error'].toString()));
          }
        }
      },
      onError: (Object error, StackTrace stack) {
        if (!ready.isCompleted) ready.completeError(error, stack);
        _events.add({
          'event': 'socketError',
          'error': error.toString(),
        });
      },
      onDone: () {
        if (!ready.isCompleted) {
          ready.completeError(StateError('mediasoup signaling closed'));
        }
        _events.add({'event': 'socketClosed'});
      },
      cancelOnError: false,
    );

    _send({
      'action': 'join',
      'callId': callId,
      'userId': userId,
    });

    await ready.future.timeout(
      const Duration(seconds: 12),
      onTimeout: () => throw TimeoutException('mediasoup join timeout'),
    );

    final routerCaps = await _request('routerRtpCapabilities');
    final device = ms.Device();
    await device.load(
      routerRtpCapabilities: ms.RtpCapabilities.fromMap(
        Map<String, dynamic>.from(routerCaps['rtpCapabilities'] as Map),
      ),
    );
    _device = device;

    await _createSendTransport();
    await _createRecvTransport();

    for (final producerId in _pendingProducerIds.toList()) {
      _pendingProducerIds.remove(producerId);
      unawaited(_consumeProducer(producerId));
    }

    // Existing producers are delivered by the server as producerAvailable
    // events immediately after the recv transport is ready.
    _send({'action': 'readyToConsume'});
  }

  Future<void> _createSendTransport() async {
    final device = _device!;
    final info = await _request(
      'createWebRtcTransport',
      data: {
        'direction': 'send',
        'sctpCapabilities': device.sctpCapabilities.toMap(),
      },
    );

    late ms.Transport transport;
    transport = device.createSendTransportFromMap(
      Map<String, dynamic>.from(info['transport'] as Map),
      producerCallback: (dynamic producer) {
        if (producer is ms.Producer) {
          producers[producer.id] = producer;
          producer.on('transportclose', () => producers.remove(producer.id));
          producer.on('close', () => producers.remove(producer.id));
        }
      },
    );

    transport.on('connect', (dynamic data) async {
      try {
        await _request(
          'connectWebRtcTransport',
          data: {
            'transportId': transport.id,
            'dtlsParameters': data['dtlsParameters'].toMap(),
          },
        );
        data['callback']();
      } catch (e) {
        data['errback'](e);
      }
    });

    transport.on('produce', (dynamic data) async {
      try {
        final response = await _request(
          'produce',
          data: {
            'transportId': transport.id,
            'kind': data['kind'],
            'rtpParameters': data['rtpParameters'].toMap(),
            'appData': data['appData'] ?? const <String, dynamic>{},
          },
        );
        data['callback'](response['producerId']);
      } catch (e) {
        data['errback'](e);
      }
    });

    transport.on('connectionstatechange', (dynamic state) {
      final value = state.toString();
      _events.add({
        'event': 'transportState',
        'direction': 'send',
        'state': value,
      });
      if (value.contains('failed')) {
        unawaited(_restartIce(transport, 'send'));
      }
    });

    _sendTransport = transport;
  }

  Future<void> _createRecvTransport() async {
    final device = _device!;
    final info = await _request(
      'createWebRtcTransport',
      data: {
        'direction': 'recv',
        'sctpCapabilities': device.sctpCapabilities.toMap(),
      },
    );

    final transport = device.createRecvTransportFromMap(
      Map<String, dynamic>.from(info['transport'] as Map),
      consumerCallback: (dynamic consumer, [dynamic accept]) {
        final c = consumer as ms.Consumer;
        consumers[c.id] = c;
        final appData = Map<String, dynamic>.from(c.appData);
        final source = appData['source']?.toString() ?? 'camera';
        final peerId = appData['userId']?.toString() ?? '';
        _events.add({
          'event': 'remoteTrack',
          'consumer': MediasoupRemoteTrack(
            consumer: c,
            source: source,
            peerId: peerId,
          ),
        });
        if (accept != null) accept({});
      },
    );

    transport.on('connect', (dynamic data) async {
      try {
        await _request(
          'connectWebRtcTransport',
          data: {
            'transportId': transport.id,
            'dtlsParameters': data['dtlsParameters'].toMap(),
          },
        );
        data['callback']();
      } catch (e) {
        data['errback'](e);
      }
    });

    transport.on('connectionstatechange', (dynamic state) {
      final value = state.toString();
      _events.add({
        'event': 'transportState',
        'direction': 'recv',
        'state': value,
      });
      if (value.contains('failed')) {
        unawaited(_restartIce(transport, 'recv'));
      }
    });

    _recvTransport = transport;
  }

  Future<void> startLocalMedia() async {
    final send = _sendTransport;
    if (send == null) throw StateError('Send transport is not ready.');

    _micStream ??= await navigator.mediaDevices.getUserMedia({
      'audio': {
        'echoCancellation': true,
        'noiseSuppression': true,
        'autoGainControl': true,
        'channelCount': 2,
      },
      'video': false,
    });

    final mic = _micStream!.getAudioTracks().firstOrNull;
    if (mic != null && !producers.values.any((p) => p.source == 'mic')) {
      send.produce(
        track: mic,
        stream: _micStream!,
        source: 'mic',
        appData: {'source': 'mic', 'userId': _userId},
        stopTracks: false,
      );
    }

    _cameraStream ??= await navigator.mediaDevices.getUserMedia({
      'audio': false,
      'video': {
        'facingMode': 'user',
        'width': {'ideal': 1920, 'max': 1920},
        'height': {'ideal': 1080, 'max': 1080},
        'frameRate': {'ideal': 60, 'max': 60},
      },
    });

    final camera = _cameraStream!.getVideoTracks().firstOrNull;
    if (camera != null) {
      debugPrint('BESTIE MEDIASOUP CAMERA TRACK id=${camera.id} settings=${camera.getSettings()}');
    }
    if (camera != null && !producers.values.any((p) => p.source == 'camera')) {
      try {
        await camera.adaptRes(1920, 1080);
      } catch (_) {}
      send.produce(
        track: camera,
        stream: _cameraStream!,
        source: 'camera',
        encodings: _cameraEncodings(),
        appData: {'source': 'camera', 'userId': _userId},
        stopTracks: false,
      );
    }
  }

  // One full-quality layer is intentional here. Three simultaneous 1080p
  // simulcast encoders were causing Android main-thread/encoder pressure on
  // the devices seen in testing. The SFU still forwards the same producer;
  // this avoids quality thrashing while preserving the requested 1080p60
  // target whenever the camera capturer supports it.
  List<ms.RtpEncodingParameters> _cameraEncodings() => [
        ms.RtpEncodingParameters(
          rid: 'f',
          scaleResolutionDownBy: 1.0,
          maxBitrate: 6500000,
          minBitrate: 700000,
          maxFramerate: 60,
          scalabilityMode: 'L1T3',
        ),
      ];

  Future<void> startScreenShare() async {
    final send = _sendTransport;
    if (send == null) throw StateError('Send transport is not ready.');

    await stopScreenShare();

    if (defaultTargetPlatform == TargetPlatform.android) {
      final granted = await Helper.requestCapturePermission(fullScreenOnly: true);
      if (!granted) {
        throw StateError('Screen sharing permission was denied.');
      }
      try {
        await _mediaProjectionChannel.invokeMethod('start');
      } catch (e) {
        debugPrint('BESTIE SCREEN foreground service start skipped: $e');
      }
    }

    // Android may return the physical display's native dimensions. We request
    // a 1080p60 target, then let the capturer/encoder negotiate the highest
    // supported representation without adding a second lower-quality layer.
    final stream = await navigator.mediaDevices.getDisplayMedia({
      'video': {
        'width': {'ideal': 1920, 'max': 1920},
        'height': {'ideal': 1080, 'max': 1080},
        'frameRate': {'ideal': 60, 'max': 60},
      },
      'audio': true,
    });

    final track = stream.getVideoTracks().firstOrNull;
    if (track != null) {
      debugPrint('BESTIE MEDIASOUP SCREEN TRACK id=${track.id} settings=${track.getSettings()}');
    }
    if (track == null) {
      await stream.dispose();
      throw StateError('No screen video track returned.');
    }

    // Do not force adaptRes here. On Android, flutter_webrtc can return
    // UnimplementedError for display tracks; the encoder can still consume
    // the native display track. The requested producer cap remains 1080p60.
    _screenStream = stream;

    send.produce(
      track: track,
      stream: stream,
      source: 'screen',
      encodings: [
        ms.RtpEncodingParameters(
          rid: 'f',
          scaleResolutionDownBy: 1.0,
          maxBitrate: 6500000,
          minBitrate: 700000,
          maxFramerate: 60,
          scalabilityMode: 'L1T3',
        ),
      ],
      appData: {
        'source': 'screen',
        'userId': _userId,
        'screenAudioRequested': true,
      },
      stopTracks: false,
    );

    final screenAudio = stream.getAudioTracks().firstOrNull;
    if (screenAudio != null) {
      send.produce(
        track: screenAudio,
        stream: stream,
        source: 'screen-audio',
        appData: {
          'source': 'screen-audio',
          'userId': _userId,
        },
        stopTracks: false,
      );
    }

    // Never change the camera producer's spatial layer when screen sharing
    // starts/stops. Camera and screen are independent mediasoup producers.
    track.onEnded = () {
      unawaited(stopScreenShare());
    };
  }

  Future<void> stopScreenShare() async {
    _screenStream?.getVideoTracks().forEach((track) {
      try {
        track.stop();
      } catch (_) {}
    });
    _screenStream?.getAudioTracks().forEach((track) {
      try {
        track.stop();
      } catch (_) {}
    });
    try {
      await _screenStream?.dispose();
    } catch (_) {}
    _screenStream = null;

    if (defaultTargetPlatform == TargetPlatform.android) {
      try {
        await _mediaProjectionChannel.invokeMethod('stop');
      } catch (_) {}
    }

    final screenProducer = producers.values
        .where((p) => p.source == 'screen' || p.source == 'screen-audio')
        .toList();
    for (final producer in screenProducer) {
      producer.close();
      producers.remove(producer.id);
    }

  }

  Future<void> setCameraEnabled(bool enabled) async {
    final stream = _cameraStream;
    if (stream == null) return;
    for (final track in stream.getVideoTracks()) {
      track.enabled = enabled;
    }
    for (final producer in producers.values.where((p) => p.source == 'camera')) {
      if (enabled) {
        producer.resume();
      } else {
        producer.pause();
      }
    }
  }

  Future<void> setMicEnabled(bool enabled) async {
    final stream = _micStream;
    if (stream == null) return;
    for (final track in stream.getAudioTracks()) {
      track.enabled = enabled;
    }
    for (final producer in producers.values.where((p) => p.source == 'mic')) {
      if (enabled) {
        producer.resume();
      } else {
        producer.pause();
      }
    }
  }

  bool _restartingSendIce = false;
  bool _restartingRecvIce = false;

  Future<void> _restartIce(ms.Transport transport, String direction) async {
    final locked = direction == 'send' ? _restartingSendIce : _restartingRecvIce;
    if (locked || _closed) return;

    if (direction == 'send') {
      _restartingSendIce = true;
    } else {
      _restartingRecvIce = true;
    }

    try {
      final response = await _request(
        'restartIce',
        data: {'transportId': transport.id},
      );
      final params = ms.IceParameters.fromMap(
        Map<String, dynamic>.from(response['iceParameters'] as Map),
      );
      transport.restartIce(params);
      _events.add({
        'event': 'iceRestart',
        'direction': direction,
        'ok': true,
      });
    } catch (e) {
      _events.add({
        'event': 'iceRestart',
        'direction': direction,
        'ok': false,
        'error': e.toString(),
      });
    } finally {
      if (direction == 'send') {
        _restartingSendIce = false;
      } else {
        _restartingRecvIce = false;
      }
    }
  }

  Future<void> _consumeProducer(String producerId) async {
    final recv = _recvTransport;
    final device = _device;
    if (recv == null || device == null) {
      _pendingProducerIds.add(producerId);
      return;
    }

    final data = await _request(
      'consume',
      data: {
        'transportId': recv.id,
        'producerId': producerId,
        'rtpCapabilities': device.rtpCapabilities.toMap(),
      },
    );

    final kind = ms.RTCRtpMediaTypeExtension.fromString(
      data['kind'].toString(),
    );

    recv.consume(
      id: data['id'].toString(),
      producerId: producerId,
      peerId: data['peerId']?.toString() ?? '',
      kind: kind,
      rtpParameters: ms.RtpParameters.fromMap(
        Map<String, dynamic>.from(data['rtpParameters'] as Map),
      ),
      appData: Map<String, dynamic>.from(
        (data['appData'] as Map?) ?? const {},
      ),
      accept: (_) {
        _send({
          'action': 'resumeConsumer',
          'consumerId': data['id'],
        });
      },
    );
  }

  void _handleMessage(dynamic raw) {
    final message = _decode(raw);
    if (message == null) return;

    final id = message['requestId']?.toString();
    if (id != null && id.isNotEmpty) {
      final pending = _pending.remove(id);
      if (pending != null) {
        if (message['error'] != null) {
          pending.completeError(StateError(message['error'].toString()));
        } else {
          pending.complete(message);
        }
        return;
      }
    }

    final event = message['event']?.toString();
    if (event == 'producerAvailable') {
      final producerId = message['producerId']?.toString();
      if (producerId != null && !consumers.values.any((c) => c.producerId == producerId)) {
        unawaited(_consumeProducer(producerId));
      }
    } else if (event == 'producerClosed') {
      final producerId = message['producerId']?.toString();
      if (producerId != null) {
        final ids = consumers.values
            .where((c) => c.producerId == producerId)
            .map((c) => c.id)
            .toList();
        for (final id in ids) {
          consumers.remove(id)?.close();
        }
      }
    }

    if (!_events.isClosed) _events.add(message);
  }

  Future<Map<String, dynamic>> _request(
    String action, {
    Map<String, dynamic> data = const {},
  }) {
    final requestId = (++_requestId).toString();
    final completer = Completer<Map<String, dynamic>>();
    _pending[requestId] = completer;
    _send({
      'action': action,
      'requestId': requestId,
      ...data,
    });
    return completer.future.timeout(
      const Duration(seconds: 15),
      onTimeout: () {
        _pending.remove(requestId);
        throw TimeoutException('mediasoup request timeout: $action');
      },
    );
  }

  void _send(Map<String, dynamic> message) {
    _socket?.sink.add(jsonEncode(message));
  }

  Map<String, dynamic>? _decode(dynamic raw) {
    try {
      if (raw is String) {
        final decoded = jsonDecode(raw);
        return decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : null;
      }
      if (raw is List<int>) {
        final decoded = jsonDecode(utf8.decode(raw));
        return decoded is Map
            ? Map<String, dynamic>.from(decoded)
            : null;
      }
    } catch (_) {}
    return null;
  }

  Future<void> close() async {
    _closed = true;

    for (final producer in producers.values.toList()) {
      try {
        producer.close();
      } catch (_) {}
    }
    producers.clear();
    _pendingProducerIds.clear();

    for (final consumer in consumers.values.toList()) {
      try {
        consumer.close();
      } catch (_) {}
    }
    consumers.clear();

    try {
      await _sendTransport?.close();
    } catch (_) {}
    try {
      await _recvTransport?.close();
    } catch (_) {}

    for (final stream in [_micStream, _cameraStream, _screenStream]) {
      try {
        for (final t in [...?stream?.getTracks()]) {
          t.stop();
        }
        await stream?.dispose();
      } catch (_) {}
    }

    _micStream = null;
    _cameraStream = null;
    _screenStream = null;
    _sendTransport = null;
    _recvTransport = null;
    _device = null;

    await _socketSubscription?.cancel();
    _socketSubscription = null;
    try {
      await _socket?.sink.close();
    } catch (_) {}
    _socket = null;

    for (final c in _pending.values) {
      if (!c.isCompleted) {
        c.completeError(StateError('mediasoup client closed'));
      }
    }
    _pending.clear();
  }

  Future<void> dispose() async {
    await close();
    await _events.close();
  }
}
