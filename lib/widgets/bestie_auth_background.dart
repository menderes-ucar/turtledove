import 'dart:math' as math;
import 'package:flutter/material.dart';

/// Lightweight, responsive auth background drawn in Flutter (no network/image asset).
class BestieAuthBackground extends StatelessWidget {
  const BestieAuthBackground({super.key});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF100D2B), Color(0xFF21164B), Color(0xFF35164C)],
        ),
      ),
      child: CustomPaint(
        painter: _InfinityBackgroundPainter(),
        child: const SizedBox.expand(),
      ),
    );
  }
}

class _InfinityBackgroundPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final blobs = <(Offset, double, Color)>[
      (Offset(size.width * .04, size.height * .16), size.width * .42, const Color(0xFF7447D8)),
      (Offset(size.width * .98, size.height * .42), size.width * .48, const Color(0xFFE94DA8)),
      (Offset(size.width * .12, size.height * .92), size.width * .46, const Color(0xFF4B62C9)),
    ];
    for (final (center, radius, color) in blobs) {
      canvas.drawCircle(center, radius, Paint()..color = color.withValues(alpha: .12)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 55));
    }

    final infinity = Path();
    final rect = Rect.fromCenter(center: Offset(size.width * .5, size.height * .25), width: size.width * .68, height: size.width * .29);
    final left = Offset(rect.left + rect.width * .25, rect.center.dy);
    final right = Offset(rect.left + rect.width * .75, rect.center.dy);
    infinity.moveTo(left.dx, left.dy);
    infinity.cubicTo(rect.left - rect.width * .04, rect.top - rect.height * .08, rect.left - rect.width * .04, rect.bottom + rect.height * .08, right.dx, right.dy);
    infinity.cubicTo(rect.right + rect.width * .04, rect.top - rect.height * .08, rect.right + rect.width * .04, rect.bottom + rect.height * .08, left.dx, left.dy);

    canvas.drawPath(infinity, Paint()..style = PaintingStyle.stroke..strokeWidth = 15..strokeCap = StrokeCap.round..color = const Color(0xFFE96BC8).withValues(alpha: .12)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 18));
    final gradientPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.8
      ..strokeCap = StrokeCap.round
      ..shader = const LinearGradient(colors: [Color(0xFFFF8FD5), Color(0xFFFFD39D), Color(0xFF9E9BFF)]).createShader(rect);
    canvas.drawPath(infinity, gradientPaint);

    final stars = <Offset>[
      Offset(size.width * .12, size.height * .12), Offset(size.width * .82, size.height * .10),
      Offset(size.width * .88, size.height * .31), Offset(size.width * .08, size.height * .52),
      Offset(size.width * .76, size.height * .64), Offset(size.width * .19, size.height * .81),
      Offset(size.width * .91, size.height * .88), Offset(size.width * .48, size.height * .46),
    ];
    for (var i = 0; i < stars.length; i++) {
      final point = stars[i];
      final radius = i.isEven ? 1.8 : 1.1;
      canvas.drawCircle(point, radius, Paint()..color = const Color(0xFFFFD6F3).withValues(alpha: .75));
      if (i.isEven) {
        final starPaint = Paint()..color = const Color(0xFFFFD6F3).withValues(alpha: .45);
        canvas.drawLine(point.translate(-5, 0), point.translate(5, 0), starPaint..strokeWidth = .7);
        canvas.drawLine(point.translate(0, -5), point.translate(0, 5), starPaint..strokeWidth = .7);
      }
    }

    // Subtle bottom haze.
    final haze = Paint()
      ..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Colors.transparent, const Color(0xFF09091D).withValues(alpha: .42)]).createShader(Offset.zero & size);
    canvas.drawRect(Offset.zero & size, haze);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
