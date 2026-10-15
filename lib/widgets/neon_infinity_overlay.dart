import 'dart:ui' as ui;
import 'package:flutter/material.dart';

/// Decorative neon infinity symbols only; the screen's original UI stays intact.
class NeonInfinityOverlay extends StatelessWidget {
  const NeonInfinityOverlay({super.key});

  @override
  Widget build(BuildContext context) => const IgnorePointer(
        child: CustomPaint(
          painter: _NeonInfinityPainter(),
          size: Size.infinite,
        ),
      );
}

class _NeonInfinityPainter extends CustomPainter {
  const _NeonInfinityPainter();

  Path _infinity(Rect rect) {
    final path = Path();
    path.moveTo(rect.left, rect.center.dy);
    path.cubicTo(rect.left, rect.top, rect.center.dx, rect.top,
        rect.center.dx, rect.center.dy);
    path.cubicTo(rect.center.dx, rect.bottom, rect.right, rect.bottom,
        rect.right, rect.center.dy);
    path.cubicTo(rect.right, rect.top, rect.center.dx, rect.top,
        rect.center.dx, rect.center.dy);
    path.cubicTo(rect.center.dx, rect.bottom, rect.left, rect.bottom,
        rect.left, rect.center.dy);
    return path;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final symbols = <({Rect rect, Color color, double width})>[
      (rect: Rect.fromLTWH(size.width * .06, size.height * .12, 112, 56), color: const Color(0xFF00E5FF), width: 2.2),
      (rect: Rect.fromLTWH(size.width - 142, size.height * .70, 116, 58), color: const Color(0xFFFF35D3), width: 2.2),
      (rect: Rect.fromLTWH(size.width * .72, size.height * .18, 48, 24), color: const Color(0xFF9D66FF), width: 1.5),
    ];
    for (final symbol in symbols) {
      final path = _infinity(symbol.rect);
      final glow = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = symbol.width * 3.5
        ..color = symbol.color.withValues(alpha: .42)
        ..maskFilter = const ui.MaskFilter.blur(ui.BlurStyle.normal, 12);
      final line = Paint()
        ..style = PaintingStyle.stroke
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..strokeWidth = symbol.width
        ..color = symbol.color.withValues(alpha: .92);
      canvas.drawPath(path, glow);
      canvas.drawPath(path, line);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
