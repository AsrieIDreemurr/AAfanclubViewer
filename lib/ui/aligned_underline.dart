import 'dart:math' as math;

import 'package:flutter/material.dart';

class AlignedUnderlineRange {
  const AlignedUnderlineRange({
    required this.start,
    required this.end,
    required this.color,
  });

  final int start;
  final int end;
  final Color color;
}

/// Draws link underlines from paragraph line metrics instead of font glyph
/// metrics. This keeps one straight underline when Saitamaar falls back to a
/// different font for unsupported CJK characters.
class AlignedUnderlinePainter extends CustomPainter {
  const AlignedUnderlinePainter({
    required this.text,
    required this.ranges,
    required this.textDirection,
    required this.textScaler,
    this.strutStyle,
    this.locale,
  });

  final InlineSpan text;
  final List<AlignedUnderlineRange> ranges;
  final TextDirection textDirection;
  final TextScaler textScaler;
  final StrutStyle? strutStyle;
  final Locale? locale;

  @override
  void paint(Canvas canvas, Size size) {
    if (ranges.isEmpty || size.isEmpty) return;
    final painter = TextPainter(
      text: text,
      textDirection: textDirection,
      textScaler: textScaler,
      strutStyle: strutStyle,
      locale: locale,
    )..layout(maxWidth: size.width);
    final lines = painter.computeLineMetrics();
    if (lines.isEmpty) return;

    for (final range in ranges) {
      if (range.end <= range.start) continue;
      final boxes = painter.getBoxesForSelection(
        TextSelection(baseOffset: range.start, extentOffset: range.end),
      );
      final paint =
          Paint()
            ..color = range.color
            ..strokeWidth = 1
            ..style = PaintingStyle.stroke;
      for (final box in boxes) {
        final centerY = (box.top + box.bottom) / 2;
        final line = lines.reduce((best, candidate) {
          final bestDistance = (centerY - best.baseline).abs();
          final candidateDistance = (centerY - candidate.baseline).abs();
          return candidateDistance < bestDistance ? candidate : best;
        });
        final y = math.min(size.height - 0.5, line.baseline + 1.25);
        canvas.drawLine(Offset(box.left, y), Offset(box.right, y), paint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant AlignedUnderlinePainter oldDelegate) {
    return oldDelegate.text != text ||
        oldDelegate.ranges != ranges ||
        oldDelegate.textDirection != textDirection ||
        oldDelegate.textScaler != textScaler ||
        oldDelegate.strutStyle != strutStyle ||
        oldDelegate.locale != locale;
  }
}
