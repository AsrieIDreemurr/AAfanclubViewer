import 'package:flutter/material.dart';

import 'aligned_underline.dart';

class ClassicLink extends StatefulWidget {
  const ClassicLink(
    this.label, {
    required this.onTap,
    this.fontSize = 16,
    this.bold = false,
    this.color = const Color(0xff0000ff),
    this.padding = EdgeInsets.zero,
    this.expand = false,
    super.key,
  });

  /// The site's own `alink` colour, shown while a link is held down.
  static const activeColor = Color(0xffff0000);

  final String label;
  final VoidCallback onTap;
  final double fontSize;
  final bool bold;
  final Color color;

  /// Tappable slack around the glyphs. A parent clips hit testing to its own
  /// box, so the target can only grow by taking real space — callers hand the
  /// link the padding their cell used to own instead of adding to it.
  final EdgeInsetsGeometry padding;

  /// Grows the target to the whole enclosing cell while the glyphs stay
  /// centred, so a tight classic cell can still be tapped anywhere.
  final bool expand;

  @override
  State<ClassicLink> createState() => _ClassicLinkState();
}

class _ClassicLinkState extends State<ClassicLink> {
  bool _pressed = false;

  void _setPressed(bool value) {
    if (_pressed != value) setState(() => _pressed = value);
  }

  @override
  Widget build(BuildContext context) {
    final color = _pressed ? ClassicLink.activeColor : widget.color;
    final style = TextStyle(
      fontFamily: 'Saitamaar',
      fontSize: widget.fontSize,
      height: 1,
      color: color,
      fontWeight: widget.bold ? FontWeight.bold : FontWeight.normal,
      decoration: TextDecoration.none,
    );
    final span = TextSpan(text: widget.label, style: style);
    final Widget content = Padding(
      padding: widget.padding,
      child: CustomPaint(
        foregroundPainter: AlignedUnderlinePainter(
          text: span,
          ranges: [
            AlignedUnderlineRange(
              start: 0,
              end: widget.label.length,
              color: color,
            ),
          ],
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
          locale: Localizations.maybeLocaleOf(context),
        ),
        child: Text(widget.label, style: style),
      ),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        onTapDown: (_) => _setPressed(true),
        onTapUp: (_) => _setPressed(false),
        onTapCancel: () => _setPressed(false),
        child: widget.expand ? Align(child: content) : content,
      ),
    );
  }
}
