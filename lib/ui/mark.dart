import 'package:flutter/material.dart';

import '../theme.dart';

/// The Peghunt mark: a wall of cards on pegs, one of them ringed.
class PeghuntMark extends StatelessWidget {
  const PeghuntMark({super.key, this.size = 32, this.ring = Tone.gold});
  final double size;
  final Color ring;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _MarkPainter(ring));
}

class _MarkPainter extends CustomPainter {
  _MarkPainter(this.ring);
  final Color ring;

  @override
  void paint(Canvas canvas, Size size) {
    final s = size.width;
    final cell = s / 3;
    final cardW = cell * 0.52, cardH = cell * 0.70;
    final card = Paint()..color = Tone.faint;
    final hunted = Paint()..color = Tone.bone;
    for (var r = 0; r < 3; r++) {
      for (var c = 0; c < 3; c++) {
        final center = Offset(cell * (c + 0.5), cell * (r + 0.5));
        final rect = Rect.fromCenter(center: center, width: cardW, height: cardH);
        canvas.drawRRect(
          RRect.fromRectAndRadius(rect, Radius.circular(cell * 0.06)),
          r == 1 && c == 1 ? hunted : card,
        );
      }
    }
    canvas.drawCircle(
      Offset(s / 2, s / 2),
      cell * 0.54,
      Paint()
        ..color = ring
        ..style = PaintingStyle.stroke
        ..strokeWidth = s * 0.055,
    );
  }

  @override
  bool shouldRepaint(_MarkPainter old) => old.ring != ring;
}
