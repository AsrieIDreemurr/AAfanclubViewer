import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../domain/forum_document.dart';
import 'aligned_underline.dart';

class AaText extends StatefulWidget {
  const AaText(
    this.data, {
    this.runs = const [],
    this.wrap = false,
    this.lineHeight = 1,
    this.onLinkTap,
    super.key,
  });

  final String data;
  final List<ForumTextRun> runs;
  final bool wrap;
  final double lineHeight;
  final ValueChanged<Uri>? onLinkTap;

  static const baseStyle = TextStyle(
    fontFamily: 'Saitamaar',
    fontSize: 16,
    height: 1,
    letterSpacing: 0,
    color: Colors.black,
    decoration: TextDecoration.none,
  );

  @override
  State<AaText> createState() => _AaTextState();
}

class _AaTextState extends State<AaText> {
  final List<TapGestureRecognizer?> _linkRecognizers = [];

  @override
  void initState() {
    super.initState();
    _createRecognizers();
  }

  @override
  void didUpdateWidget(covariant AaText oldWidget) {
    super.didUpdateWidget(oldWidget);
    _disposeRecognizers();
    _createRecognizers();
  }

  @override
  void dispose() {
    _disposeRecognizers();
    super.dispose();
  }

  void _createRecognizers() {
    for (final run in widget.runs) {
      final uri = run.uri;
      final onLinkTap = widget.onLinkTap;
      _linkRecognizers.add(
        uri == null || onLinkTap == null
            ? null
            : (TapGestureRecognizer()..onTap = () => onLinkTap(uri)),
      );
    }
  }

  void _disposeRecognizers() {
    for (final recognizer in _linkRecognizers) {
      recognizer?.dispose();
    }
    _linkRecognizers.clear();
  }

  @override
  Widget build(BuildContext context) {
    var offset = 0;
    final underlineRanges = <AlignedUnderlineRange>[];
    final children =
        widget.runs.isEmpty
            ? <InlineSpan>[TextSpan(text: widget.data)]
            : widget.runs.indexed
                .map((entry) {
                  final run = entry.$2;
                  final start = offset;
                  offset += run.text.length;
                  if (run.tone == ForumTextTone.link) {
                    underlineRanges.add(
                      AlignedUnderlineRange(
                        start: start,
                        end: offset,
                        color: const Color(0xff0000ff),
                      ),
                    );
                  }
                  return TextSpan(
                    recognizer: _linkRecognizers[entry.$1],
                    text: run.text,
                    style: TextStyle(
                      color: _colorFor(run.tone),
                      fontWeight: run.bold ? FontWeight.bold : null,
                      decoration: TextDecoration.none,
                    ),
                  );
                })
                .toList(growable: false);
    final span = TextSpan(
      style: AaText.baseStyle.copyWith(height: widget.lineHeight),
      children: children,
    );
    final strutStyle = StrutStyle(
      fontFamily: 'Saitamaar',
      fontSize: 16,
      height: widget.lineHeight,
      // A forced one-em strut clips fallback CJK glyphs. Keep Saitamaar as
      // the minimum line height while allowing fallback fonts to expand it.
      forceStrutHeight: false,
    );
    final text = Text.rich(
      span,
      softWrap: widget.wrap,
      overflow: TextOverflow.visible,
      strutStyle: strutStyle,
    );
    final paintedText = CustomPaint(
      foregroundPainter: AlignedUnderlinePainter(
        text: span,
        ranges: underlineRanges,
        textDirection: Directionality.of(context),
        textScaler: MediaQuery.textScalerOf(context),
        strutStyle: strutStyle,
        locale: Localizations.maybeLocaleOf(context),
      ),
      child: text,
    );
    return SelectionArea(
      child:
          widget.wrap
              ? paintedText
              : SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(vertical: 1),
                child: paintedText,
              ),
    );
  }

  Color _colorFor(ForumTextTone tone) => switch (tone) {
    ForumTextTone.normal => Colors.black,
    ForumTextTone.link => const Color(0xff0000ff),
    ForumTextTone.red => const Color(0xffff0000),
    ForumTextTone.blue => const Color(0xff0000ff),
    ForumTextTone.green => const Color(0xff008000),
  };
}
