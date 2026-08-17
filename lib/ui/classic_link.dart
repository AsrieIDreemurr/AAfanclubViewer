import 'package:flutter/material.dart';

import 'aligned_underline.dart';

class ClassicLink extends StatelessWidget {
  const ClassicLink(
    this.label, {
    required this.onTap,
    this.fontSize = 16,
    this.bold = false,
    this.color = const Color(0xff0000ff),
    super.key,
  });

  final String label;
  final VoidCallback onTap;
  final double fontSize;
  final bool bold;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final style = TextStyle(
      fontFamily: 'Saitamaar',
      fontSize: fontSize,
      height: 1,
      color: color,
      fontWeight: bold ? FontWeight.bold : FontWeight.normal,
      decoration: TextDecoration.none,
    );
    final span = TextSpan(text: label, style: style);
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: CustomPaint(
          foregroundPainter: AlignedUnderlinePainter(
            text: span,
            ranges: [
              AlignedUnderlineRange(start: 0, end: label.length, color: color),
            ],
            textDirection: Directionality.of(context),
            textScaler: MediaQuery.textScalerOf(context),
            locale: Localizations.maybeLocaleOf(context),
          ),
          child: Text(label, style: style),
        ),
      ),
    );
  }
}
