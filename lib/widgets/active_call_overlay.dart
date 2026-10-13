import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_webrtc/flutter_webrtc.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';

import '../services/active_call_controller.dart';
import '../services/call_service.dart';

class ActiveCallOverlay extends StatefulWidget {
  const ActiveCallOverlay({super.key});

  @override
  State<ActiveCallOverlay> createState() => _ActiveCallOverlayState();
}

class _ActiveCallOverlayState extends State<ActiveCallOverlay> {
  final RTCVideoRenderer _remote = RTCVideoRenderer();
  final RTCVideoRenderer _local = RTCVideoRenderer();
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    await _remote.initialize();
    await _local.initialize();
    if (mounted) setState(() => _ready = true);
  }

  void _syncStreams(ActiveCallController active) {
    if (!_ready) return;
    final remote = active.remoteScreenStream ?? active.remoteCameraStream;
    final local = active.media?.cameraStream;
    if (_remote.srcObject != remote) _remote.srcObject = remote;
    if (_local.srcObject != local) _local.srcObject = local;
  }

  Future<void> _openCall(ActiveCallController active) async {
    final id = active.callId;
    if (id == null || active.partnerId == null) return;
    final query = <String, String>{
      'partnerId': active.partnerId!,
      if (active.callerName?.isNotEmpty == true) 'callerName': active.callerName!,
      if (active.isCaller) 'mode': 'caller',
    };
    // The route's mode is part of the path, not the query string.
    final mode = active.isCaller ? 'caller' : 'receiver';
    final queryString = '?${query.entries.where((e) => e.key != 'mode').map((e) => '${Uri.encodeQueryComponent(e.key)}=${Uri.encodeQueryComponent(e.value)}').join('&')}';
    context.go('/home/call/$id/$mode${queryString == '?' ? '' : queryString}');
  }

  Future<void> _hangup(ActiveCallController active) async {
    final id = active.callId;
    if (id != null) {
      try {
        await context.read<CallService>().terminateCall(id);
      } catch (_) {}
    }
    await active.endActiveCall();
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<ActiveCallController>(
      builder: (context, active, _) {
        if (!active.hasActiveCall || !active.minimized || !_ready) {
          return const SizedBox.shrink();
        }

        _syncStreams(active);
        final hasRemote = _remote.srcObject != null;
        final hasLocal = _local.srcObject != null;

        return Positioned(
          left: 12,
          right: 12,
          bottom: 92,
          child: SafeArea(
            top: false,
            child: Align(
              alignment: Alignment.centerRight,
              child: GestureDetector(
                onTap: () => _openCall(active),
                child: Container(
                  width: 188,
                  height: 118,
                  decoration: BoxDecoration(
                    color: Colors.black,
                    borderRadius: BorderRadius.circular(18),
                    border: Border.all(color: Colors.white24),
                    boxShadow: const [BoxShadow(color: Colors.black54, blurRadius: 16)],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      if (hasRemote)
                        RTCVideoView(
                          _remote,
                          objectFit: active.remoteScreenStream != null
                              ? RTCVideoViewObjectFit.RTCVideoViewObjectFitContain
                              : RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                        )
                      else
                        const Center(child: Icon(Icons.videocam, color: Colors.white54, size: 34)),
                      if (hasLocal)
                        Positioned(
                          right: 6,
                          top: 6,
                          width: 62,
                          height: 78,
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(10),
                            child: RTCVideoView(
                              _local,
                              mirror: true,
                              objectFit: RTCVideoViewObjectFit.RTCVideoViewObjectFitCover,
                            ),
                          ),
                        ),
                      Positioned(
                        left: 7,
                        bottom: 7,
                        child: DecoratedBox(
                          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(8)),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 7, vertical: 4),
                            child: Text('BESTIE • Arama', style: TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w600)),
                          ),
                        ),
                      ),
                      Positioned(
                        right: 7,
                        bottom: 7,
                        child: Material(
                          color: Colors.red,
                          shape: const CircleBorder(),
                          child: InkWell(
                            customBorder: const CircleBorder(),
                            onTap: () => unawaited(_hangup(active)),
                            child: const Padding(
                              padding: EdgeInsets.all(7),
                              child: Icon(Icons.call_end, color: Colors.white, size: 16),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    unawaited(_remote.dispose());
    unawaited(_local.dispose());
    super.dispose();
  }
}
