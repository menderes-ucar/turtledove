import 'package:flutter/material.dart';
import 'package:flutter_3d_controller/flutter_3d_controller.dart';
import 'pet_localization.dart';

/// Real 3D pet renderer.
///
/// IMPORTANT:
/// - This widget never draws an animal with CustomPainter.
/// - This widget never falls back to a 2D animal image.
/// - Every supported breed is a real GLB asset.
class PetAvatar3D extends StatefulWidget {
  final String species;
  final String breed;
  final PetAnimation animation;
  final double size;
  final bool sleeping;

  const PetAvatar3D({
    super.key,
    required this.species,
    required this.breed,
    required this.animation,
    this.size = 235,
    this.sleeping = false,
  });

  @override
  State<PetAvatar3D> createState() => _PetAvatar3DState();
}

class _PetAvatar3DState extends State<PetAvatar3D> {
  late final Flutter3DController _controller;
  bool _loaded = false;
  double _progress = 0;
  String? _error;
  List<String> _animations = const [];

  String get _src => Pet3DAssetCatalog.modelPath(
        species: widget.species,
        breed: widget.breed,
      );

  @override
  void initState() {
    super.initState();
    _controller = Flutter3DController();
  }

  @override
  void didUpdateWidget(covariant PetAvatar3D oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.animation != widget.animation && _loaded) {
      _playAnimationForState();
    }
  }

  Future<void> _onLoaded(String modelAddress) async {
    if (!mounted) return;

    try {
      final names = await _controller.getAvailableAnimations();
      if (!mounted) return;

      debugPrint('BESTIE 3D LOADED: $modelAddress');
      debugPrint('BESTIE 3D ANIMATIONS: $names');
      setState(() {
        _loaded = true;
        _error = null;
        _animations = names;
      });

      // Let model-viewer auto-frame the imported model first. The real Kitty
      // asset has its own scale/orientation and this avoids forcing a camera
      // target that can miss the animal when an asset uses a different size.

      _playAnimationForState();
    } catch (e) {
      debugPrint('BESTIE 3D ANIMATION READ FAILED: $e');
      // A model without animation clips is still a valid 3D pet.
      if (!mounted) return;
      debugPrint('BESTIE 3D LOADED WITHOUT ANIMATION LIST: $modelAddress');
      setState(() {
        _loaded = true;
        _error = null;
        _animations = const [];
      });
    }
  }

  void _playAnimationForState() {
    if (!_loaded) return;

    final preferred = Pet3DAssetCatalog.animationCandidates(widget.animation);
    final selected = preferred.cast<String?>().firstWhere(
          (name) => name != null && _animations.contains(name),
          orElse: () => null,
        );

    if (selected != null) {
      _controller.playAnimation(animationName: selected);
      return;
    }

    // If the authored model contains only one generic idle animation,
    // keep the character alive instead of inventing 2D motion.
    if (_animations.isNotEmpty) {
      _controller.playAnimation(animationName: _animations.first);
    }
  }

  @override
  Widget build(BuildContext context) {
    final modelKey = '${widget.species}:${widget.breed}';

    return SizedBox(
      width: widget.size,
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          AnimatedSwitcher(
            duration: const Duration(milliseconds: 280),
            child: Flutter3DViewer(
              key: ValueKey(modelKey),
              src: _src,
              controller: _controller,
              enableTouch: true,
              activeGestureInterceptor: true,
              progressBarColor: Theme.of(context).colorScheme.primary,
              onProgress: (progress) {
                if (!mounted) return;
                setState(() => _progress = progress);
              },
              onLoad: _onLoaded,
              onError: (error) {
                debugPrint('BESTIE 3D ERROR: $error | SRC: $_src');
                if (!mounted) return;
                setState(() {
                  _loaded = false;
                  _error = error;
                });
              },
            ),
          ),
          if (_error == null && !_loaded)
            Positioned(
              left: 8,
              right: 8,
              bottom: 8,
              child: IgnorePointer(
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(.55),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    '${PetStrings.of(context).loading3d} ${(_progress * 100).round()}%\n$_src',
                    textAlign: TextAlign.center,
                    style: const TextStyle(color: Colors.white, fontSize: 9, fontWeight: FontWeight.w700),
                  ),
                ),
              ),
            ),
          if (_error != null)
            _Pet3DError(
              message: _error!,
              assetPath: _src,
            ),
        ],
      ),
    );
  }
}

/// Keeps the existing PetAnimation API used by PetScreen.
enum PetAnimation {
  idle,
  talk,
  feed,
  bath,
  clean,
  nails,
  toilet,
  play,
  sleep,
  love,
}

/// Centralized mapping between BESTIE pet breeds and the actual 3D assets.
class Pet3DAssetCatalog {
  const Pet3DAssetCatalog._();

  static String modelPath({
    required String species,
    required String breed,
  }) {
    final normalizedSpecies = species.trim().toLowerCase();
    final normalizedBreedRaw = breed.trim().toLowerCase();
    final normalizedBreed = normalizedBreedRaw.isEmpty && normalizedSpecies == 'cat'
        ? 'ragdoll'
        : normalizedBreedRaw;
    // Each returned file is a real 3D GLB asset. There is deliberately no
    // 2D animal-image fallback and no CustomPainter animal.
    return 'assets/pet_3d/$normalizedSpecies/$normalizedBreed/none.glb';
  }

  static List<String?> animationCandidates(PetAnimation animation) {
    return switch (animation) {
      PetAnimation.idle => const ['Kitty_001_idle', 'Idle', 'idle', 'Idle_01'],
      PetAnimation.talk => const ['Kitty_001_idle', 'Talk', 'talk', 'Happy', 'Idle'],
      PetAnimation.feed => const ['Kitty_001_idle', 'Eat', 'Feed', 'eat', 'Idle'],
      PetAnimation.bath => const ['Kitty_001_idle', 'Bath', 'Bathing', 'bath', 'Idle'],
      PetAnimation.clean => const ['Kitty_001_idle', 'Clean', 'Groom', 'clean', 'Idle'],
      PetAnimation.nails => const ['Kitty_001_idle', 'Nails', 'Groom', 'clean', 'Idle'],
      PetAnimation.toilet => const ['Kitty_001_idle', 'Toilet', 'Idle'],
      PetAnimation.play => const ['Kitty_001_walk', 'Kitty_001_idle', 'Play', 'play', 'Happy', 'Idle'],
      PetAnimation.sleep => const ['Kitty_001_idle', 'Sleep', 'sleep', 'Idle'],
      PetAnimation.love => const ['Kitty_001_idle', 'Love', 'Happy', 'love', 'Idle'],
    };
  }
}

class _Pet3DError extends StatelessWidget {
  final String message;
  final String assetPath;

  const _Pet3DError({required this.message, required this.assetPath});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        margin: const EdgeInsets.all(12),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(.72),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.white.withOpacity(.16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.view_in_ar_rounded, color: Colors.white, size: 28),
            const SizedBox(height: 8),
            Text(
              PetStrings.of(context).petAssetMissing,
              style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 5),
            Text(
              assetPath,
              style: TextStyle(color: Colors.white.withOpacity(.72), fontSize: 9),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 4),
            Text(
              message,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: Colors.white.withOpacity(.60), fontSize: 9),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
