import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

class MediaItem {
  final String url;
  final bool isVideo;

  const MediaItem({
    required this.url,
    required this.isVideo,
  });

  factory MediaItem.fromUrl(String url) {
    final lower = url.toLowerCase().split('?').first.split('#').first;
    final isVideo = RegExp(r'\.(mp4|mov|m4v|webm|avi)$').hasMatch(lower);
    return MediaItem(url: url, isVideo: isVideo);
  }
}

class MediaPreview {
  static Future<void> open(
    BuildContext context, {
    required String url,
    bool? isVideo,
  }) {
    final media = MediaItem(
      url: url,
      isVideo: isVideo ?? MediaItem.fromUrl(url).isVideo,
    );

    // Do NOT use showDialog here. Dialog routes can keep dialog/inset
    // constraints and are not a reliable full-screen media surface.
    // Push a real opaque route that occupies the entire screen instead.
    return Navigator.of(context, rootNavigator: true).push<void>(
      PageRouteBuilder<void>(
        opaque: true,
        fullscreenDialog: true,
        barrierColor: Colors.black,
        transitionDuration: const Duration(milliseconds: 180),
        reverseTransitionDuration: const Duration(milliseconds: 140),
        pageBuilder: (_, __, ___) => _FullscreenMediaViewer(media: media),
        transitionsBuilder: (_, animation, __, child) {
          return FadeTransition(opacity: animation, child: child);
        },
      ),
    );
  }
}

class MediaThumbnail extends StatefulWidget {
  final MediaItem media;
  final double? width;
  final double? height;
  final BoxFit fit;
  final BorderRadius borderRadius;

  const MediaThumbnail({
    super.key,
    required this.media,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.borderRadius = const BorderRadius.all(Radius.circular(14)),
  });

  @override
  State<MediaThumbnail> createState() => _MediaThumbnailState();
}

class _MediaThumbnailState extends State<MediaThumbnail> {
  VideoPlayerController? _controller;

  @override
  void initState() {
    super.initState();
    if (widget.media.isVideo) {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.media.url),
      );
      _controller = controller;
      controller.initialize().then((_) {
        if (mounted) setState(() {});
      }).catchError((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final radius = widget.borderRadius;
    return ClipRRect(
      borderRadius: radius,
      child: Container(
        width: widget.width,
        height: widget.height,
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (!widget.media.isVideo)
              Image.network(
                widget.media.url,
                fit: widget.fit,
                filterQuality: FilterQuality.medium,
                errorBuilder: (_, __, ___) => const Center(
                  child: Icon(Icons.broken_image_outlined,
                      color: Colors.white70, size: 32),
                ),
              )
            else
              _buildVideoThumbnail(),
            if (widget.media.isVideo)
              const Center(
                child: CircleAvatar(
                  radius: 25,
                  backgroundColor: Colors.black54,
                  child: Icon(
                    Icons.play_arrow_rounded,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoThumbnail() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const Center(
        child: SizedBox(
          width: 26,
          height: 26,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
      );
    }

    return FittedBox(
      fit: widget.fit,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: controller.value.size.width,
        height: controller.value.size.height,
        child: VideoPlayer(controller),
      ),
    );
  }
}

class _FullscreenMediaViewer extends StatefulWidget {
  final MediaItem media;

  const _FullscreenMediaViewer({required this.media});

  @override
  State<_FullscreenMediaViewer> createState() => _FullscreenMediaViewerState();
}

class _FullscreenMediaViewerState extends State<_FullscreenMediaViewer> {
  VideoPlayerController? _controller;
  bool _controlsVisible = true;

  @override
  void initState() {
    super.initState();

    // Hide Android/iOS system bars while the media is open so the image/video
    // genuinely uses the whole display. The app is restored on dispose.
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky));

    if (widget.media.isVideo) {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse(widget.media.url),
      );
      _controller = controller;
      controller.initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        controller.play();
      }).catchError((_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    // Return to the normal edge-to-edge app UI after closing the viewer.
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final initialized =
        controller != null && controller.value.isInitialized;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              if (widget.media.isVideo) {
                setState(() => _controlsVisible = !_controlsVisible);
              }
            },
            child: Center(
              child: widget.media.isVideo
                  ? initialized
                      ? InteractiveViewer(
                          minScale: 1,
                          maxScale: 3,
                          child: AspectRatio(
                            aspectRatio: controller.value.aspectRatio,
                            child: VideoPlayer(controller),
                          ),
                        )
                      : const CircularProgressIndicator(color: Colors.white)
                  : InteractiveViewer(
                      minScale: 1,
                      maxScale: 5,
                      child: Image.network(
                        widget.media.url,
                        width: double.infinity,
                        height: double.infinity,
                        fit: BoxFit.contain,
                        filterQuality: FilterQuality.high,
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.broken_image_outlined,
                          color: Colors.white70,
                          size: 64,
                        ),
                      ),
                    ),
            ),
          ),
          Positioned(
            top: MediaQuery.of(context).padding.top + 8,
            right: 12,
            child: IconButton.filled(
              style: IconButton.styleFrom(
                backgroundColor: Colors.black54,
                foregroundColor: Colors.white,
              ),
              icon: const Icon(Icons.close_rounded),
              onPressed: () => Navigator.of(context).pop(),
            ),
          ),
          if (widget.media.isVideo && initialized && _controlsVisible)
            Positioned(
              left: 16,
              right: 16,
              bottom: MediaQuery.of(context).padding.bottom + 18,
              child: _VideoControls(controller: controller),
            ),
        ],
      ),
    );
  }
}

class _VideoControls extends StatelessWidget {
  final VideoPlayerController controller;

  const _VideoControls({required this.controller});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (_, value, __) {
        final duration = value.duration.inMilliseconds.toDouble();
        final position = value.position.inMilliseconds
            .clamp(0, value.duration.inMilliseconds)
            .toDouble();

        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(.68),
            borderRadius: BorderRadius.circular(18),
          ),
          child: Row(
            children: [
              IconButton(
                color: Colors.white,
                icon: Icon(
                  value.isPlaying
                      ? Icons.pause_rounded
                      : Icons.play_arrow_rounded,
                ),
                onPressed: () {
                  if (value.isPlaying) {
                    controller.pause();
                  } else {
                    controller.play();
                  }
                },
              ),
              Expanded(
                child: Slider(
                  value: duration <= 0 ? 0 : position,
                  min: 0,
                  max: duration <= 0 ? 1 : duration,
                  onChanged: duration <= 0
                      ? null
                      : (v) => controller.seekTo(
                            Duration(milliseconds: v.round()),
                          ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
