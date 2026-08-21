import 'package:aafanclub_viewer/ui/post_composer_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('composes layers by grid position with transparent Unicode spaces', () {
    expect(
      composeTextLayers(const [
        ComposerTextLayer(text: 'AB\nＣD', row: 0, column: 0),
        ComposerTextLayer(text: ' X ', row: 0, column: 0),
      ]),
      'AX\nＣD',
    );

    expect(
      composeTextLayers(const [
        ComposerTextLayer(text: 'ABC', row: 0, column: 0),
        ComposerTextLayer(text: '　Z', row: 0, column: 0),
      ]),
      'ABZ',
    );

    expect(
      composeTextLayers(const [
        ComposerTextLayer(text: 'ABC', row: 0, column: 0),
        ComposerTextLayer(text: '\u00a0Q', row: 0, column: 0),
      ]),
      'AQC',
    );
  });

  test('a gap inside a drawing hides the layer below it', () {
    // The lower layer is a solid run; the upper one has a shaped gap. The gap
    // blanks the run underneath — without this rule it would read 'AXXXBXXX'.
    expect(
      composeTextLayers(const [
        ComposerTextLayer(text: 'XXXXXXXX', row: 0, column: 0),
        ComposerTextLayer(text: 'A   B', row: 0, column: 0),
      ]),
      'A   BXXX',
    );

    // Leading and trailing whitespace still lets the lower layer through,
    // which is what lets a window be padded into position.
    expect(
      composeTextLayers(const [
        ComposerTextLayer(text: 'XXXXXXXX', row: 0, column: 0),
        ComposerTextLayer(text: '  A  ', row: 0, column: 0),
      ]),
      'XXAXXXXX',
    );

    // The rule is per line: the gap on the second line must not blank the
    // first line's characters.
    expect(
      composeTextLayers(const [
        ComposerTextLayer(text: 'XXXX\nXXXX', row: 0, column: 0),
        ComposerTextLayer(text: '  A\nB  C', row: 0, column: 0),
      ]),
      'XXAX\nB  C',
    );

    // A window with nothing but whitespace has no interior at all.
    expect(
      composeTextLayers(const [
        ComposerTextLayer(text: 'XXXX', row: 0, column: 0),
        ComposerTextLayer(text: '    ', row: 0, column: 0),
      ]),
      'XXXX',
    );
  });

  test('a marked run of spaces stays see-through', () {
    // Same shape as the gap test above, but with the gap marked.
    expect(
      composeTextLayers(const [
        ComposerTextLayer(text: 'XXXXXXXX', row: 0, column: 0),
        ComposerTextLayer(
          text: 'A   B',
          row: 0,
          column: 0,
          transparentSpans: [ComposerSpan(line: 0, start: 1, end: 4)],
        ),
      ]),
      'AXXXBXXX',
    );

    // Marking one line leaves the other line's gap opaque.
    expect(
      composeTextLayers(const [
        ComposerTextLayer(text: 'XXXXX\nXXXXX', row: 0, column: 0),
        ComposerTextLayer(
          text: 'A   B\nA   B',
          row: 0,
          column: 0,
          transparentSpans: [ComposerSpan(line: 1, start: 1, end: 4)],
        ),
      ]),
      'A   B\nAXXXB',
    );
  });

  test('a space run is found by pixel column, not character index', () {
    // A face where the two glyphs are different widths, so the same character
    // index sits at a different pixel on each line.
    double measure(String text) {
      var total = 0.0;
      for (final rune in text.runes) {
        total += String.fromCharCode(rune) == 'W' ? 20.0 : 10.0;
      }
      return total;
    }

    // 'W' is 20 wide, so the gap on line 0 spans pixels 20..50.
    expect(
      spaceRunAt('W   B', 0, 25, measure),
      const ComposerSpan(line: 0, start: 1, end: 4),
    );
    // Pixel 5 is inside the 'W' itself, not a space.
    expect(spaceRunAt('W   B', 0, 5, measure), isNull);
    // Past the end of the line there is nothing to select.
    expect(spaceRunAt('W   B', 0, 500, measure), isNull);
  });

  test('crossing lines follows the same pixel column and stops at ink', () {
    double measure(String text) {
      var total = 0.0;
      for (final rune in text.runes) {
        total += String.fromCharCode(rune) == 'W' ? 20.0 : 10.0;
      }
      return total;
    }

    final lines = [
      'AA    BB', // pixel 45 is blank
      'W     BB', // same pixel is blank, and the run starts at a different index
      'AA  ★ BB', // pixel 45 lands on the star: the walk stops before this line
      'AA    BB',
    ];

    final spans = connectedSpaceRuns(lines, 1, 45, measure, crossLines: true);
    expect(spans.map((span) => span.line), [0, 1]);
    // Line 1 starts its run one character earlier, which a character-index
    // anchor would have got wrong.
    expect(spans.firstWhere((span) => span.line == 0).start, 2);
    expect(spans.firstWhere((span) => span.line == 1).start, 1);

    // Without crossing, only the clicked line is taken.
    expect(
      connectedSpaceRuns(lines, 1, 45, measure, crossLines: false),
      hasLength(1),
    );
  });

  test('padding follows measured width so windows stay in column', () {
    // A proportional face where 'W' is twice a space and 'i' is half of one —
    // the shape that used to shear the right-hand window row by row.
    const spaceWidth = 10.0;
    double measure(String text) {
      var total = 0.0;
      for (final rune in text.runes) {
        total += switch (String.fromCharCode(rune)) {
          'W' => 20.0,
          'i' => 5.0,
          _ => 10.0,
        };
      }
      return total;
    }

    final output = composeTextLayers(
      const [
        // Left window: two lines whose glyphs measure differently.
        ComposerTextLayer(text: 'WW\nii', row: 0, column: 0),
        // Right window: must start at the same pixel column on both rows.
        ComposerTextLayer(text: 'X\nX', row: 0, column: 6),
      ],
      measureWidth: measure,
      spaceWidth: spaceWidth,
    );

    final lines = output.split('\n');
    expect(lines, hasLength(2));
    for (final line in lines) {
      final target = line.indexOf('X');
      expect(measure(line.substring(0, target)), closeTo(6 * spaceWidth, 5));
    }
    // 'WW' already measures 4 cells wide, 'ii' only one, so the two rows need
    // a different number of spaces to reach the same place.
    expect(lines[0], isNot(equals(lines[1].replaceAll('i', 'W'))));
  });

  test('a long run of ideographic spaces keeps a single drawing aligned', () {
    // Real Saitamaar metrics at 16px: the ideographic space is 2.2 space
    // widths, not 2, so a cell-counting engine drifts 10% per character.
    const space = 5.0;
    double measure(String text) {
      var total = 0.0;
      for (final rune in text.runes) {
        total += switch (rune) {
          0x3000 => 11.0,
          0x0020 => 5.0,
          _ => 15.0,
        };
      }
      return total;
    }

    final output = composeTextLayers(
      const [ComposerTextLayer(text: '　　　　　　　　　　あ', row: 0, column: 0)],
      measureWidth: measure,
      spaceWidth: space,
    );

    final glyph = output.indexOf('あ');
    expect(glyph, greaterThan(0));
    expect(
      measure(output.substring(0, glyph)),
      closeTo(10 * 11.0, space / 2),
    );
  });

  test('glyphs before the origin are dropped, not shifted', () {
    expect(
      composeTextLayers(const [
        ComposerTextLayer(text: 'ABCD', row: 0, column: -2),
      ]),
      'CD',
    );

    // A window pulled above the origin keeps the rows that remain in frame.
    expect(
      composeTextLayers(const [
        ComposerTextLayer(text: 'one\ntwo\nsix', row: -2, column: 0),
      ]),
      'six',
    );

    // Clipping one window must not move a window that is still inside.
    expect(
      composeTextLayers(const [
        ComposerTextLayer(text: 'XY', row: 0, column: -1),
        ComposerTextLayer(text: 'Z', row: 0, column: 4),
      ]),
      'Y   Z',
    );
  });

  testWidgets('text windows edit, expose layers, preview, and cancel locally', (
    tester,
  ) async {
    var submitCalls = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostComposerSheet(
            mode: ComposerMode.reply,
            loginName: 'Asriel',
            onSubmit: (title, content) async {
              submitCalls++;
              return true;
            },
          ),
        ),
      ),
    );

    expect(find.text('登录：Asriel'), findsOneWidget);
    expect(find.byKey(const Key('embed-aa')), findsOneWidget);
    await tester.tap(find.byKey(const Key('embed-text')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('composer-layer-input-0')),
      'ABC',
    );
    await tester.pump();

    final layerCenter = tester.getCenter(
      find.byKey(const ValueKey('composer-layer-0')),
    );
    await tester.tapAt(layerCenter);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(layerCenter);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const Key('composer-layer-panel')), findsOneWidget);

    await tester.tap(find.byKey(const Key('composer-primary-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('composer-preview')), findsOneWidget);
    final previewField = find.byKey(const Key('composer-preview-text'));
    expect(
      tester.widget<TextField>(previewField).controller?.text,
      contains('ABC'),
    );
    expect(find.text('发送'), findsOneWidget);

    // The confirmed text is editable, and 取消 throws those edits away
    // instead of turning them into another window.
    await tester.enterText(previewField, 'ABC 直接输入');
    await tester.pump();
    await tester.tap(find.byKey(const Key('composer-cancel-preview')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('composer-preview')), findsNothing);
    expect(find.text('ABC 直接输入'), findsNothing);

    await tester.tap(find.byKey(const Key('composer-primary-action')));
    await tester.pumpAndSettle();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('composer-preview-text')))
          .controller
          ?.text,
      contains('ABC'),
    );
    expect(submitCalls, 0);

    await tester.tap(find.byKey(const Key('composer-cancel-preview')));
    await tester.pump();
    expect(find.byKey(const Key('embed-text')), findsOneWidget);
    expect(
      find.byKey(const ValueKey('composer-layer-input-0')),
      findsOneWidget,
    );
    expect(submitCalls, 0);
  });

  testWidgets('an empty canvas confirms straight into a plain text box', (
    tester,
  ) async {
    String? sent;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostComposerSheet(
            mode: ComposerMode.reply,
            onSubmit: (title, content) async {
              sent = content;
              return true;
            },
          ),
        ),
      ),
    );

    // No windows at all — 确认 still opens the editor, which is all a
    // one-line reply needs.
    expect(find.byKey(const ValueKey('composer-layer-0')), findsNothing);
    await tester.tap(find.byKey(const Key('composer-primary-action')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('composer-preview')), findsOneWidget);

    final field = find.byKey(const Key('composer-preview-text'));
    expect(tester.widget<TextField>(field).controller?.text, isEmpty);

    // Sending nothing is still refused.
    await tester.tap(find.byKey(const Key('composer-primary-action')));
    await tester.pumpAndSettle();
    expect(sent, isNull);

    await tester.enterText(field, '单行回复');
    await tester.pump();
    await tester.tap(find.byKey(const Key('composer-primary-action')));
    await tester.pumpAndSettle();
    expect(sent, '单行回复');
  });

  testWidgets('windows are named, not labelled with their own contents', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostComposerSheet(
            mode: ComposerMode.reply,
            onSubmit: (title, content) async => true,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('embed-text')));
    await tester.pump();
    // A drawing's own characters would make an unreadable label.
    await tester.enterText(
      find.byKey(const ValueKey('composer-layer-input-0')),
      '　 ∧＿∧\n（ ´･ω･）',
    );
    await tester.pump();
    await tester.tap(find.byKey(const Key('embed-text')));
    await tester.pump();

    // The window's own title bar carries the name.
    expect(find.text('文字窗口 1'), findsOneWidget);
    expect(find.text('文字窗口 2'), findsOneWidget);

    final first = tester.getCenter(
      find.byKey(const ValueKey('composer-layer-0')),
    );
    await tester.tapAt(first);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(first);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const Key('composer-layer-panel')), findsOneWidget);

    // Both the panel row and the title bar show the name. The panel never
    // shows the drawing itself — only the window's own editor does.
    expect(find.text('文字窗口 1'), findsNWidgets(2));
    expect(
      find.descendant(
        of: find.byKey(const Key('composer-layer-panel')),
        matching: find.textContaining('∧＿∧'),
      ),
      findsNothing,
    );

    // Reordering must not renumber the windows.
    await tester.tap(find.byKey(const ValueKey('composer-layer-down-1')));
    await tester.pumpAndSettle();
    expect(find.text('文字窗口 1'), findsNWidgets(2));
    expect(find.text('文字窗口 2'), findsNWidgets(2));
  });

  testWidgets('space selection marks a run and survives until an edit', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostComposerSheet(
            mode: ComposerMode.reply,
            onSubmit: (title, content) async => true,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('embed-text')));
    await tester.pump();
    final input = find.byKey(const ValueKey('composer-layer-input-0'));
    await tester.enterText(input, 'A  B');
    await tester.pumpAndSettle();

    // Open the layer panel: the two buttons live at its bottom.
    final centre = tester.getCenter(
      find.byKey(const ValueKey('composer-layer-0')),
    );
    await tester.tapAt(centre);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(centre);
    await tester.pump(const Duration(milliseconds: 350));
    expect(find.byKey(const Key('composer-space-single')), findsOneWidget);
    expect(find.byKey(const Key('composer-space-cross')), findsOneWidget);

    // Off by default: the window takes taps as usual.
    expect(
      find.byKey(const ValueKey('composer-space-pick-0')),
      findsNothing,
    );

    await tester.tap(find.byKey(const Key('composer-space-single')));
    await tester.pumpAndSettle();
    final picker = find.byKey(const ValueKey('composer-space-pick-0'));
    expect(picker, findsOneWidget);

    // Tap the gap between the two letters.
    final textRect = tester.getRect(input);
    await tester.tapAt(Offset(textRect.left + 22, textRect.top + 6));
    await tester.pumpAndSettle();
    expect(find.byType(CustomPaint), findsWidgets);

    // Editing the text drops the marks, since a rune index no longer points
    // at the same character.
    await tester.enterText(input, 'A   B');
    await tester.pumpAndSettle();

    // Pressing the button again leaves selection mode.
    await tester.tap(find.byKey(const Key('composer-space-single')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('composer-space-pick-0')), findsNothing);
  });

  testWidgets('marks can be stepped back, forward and rubbed out', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostComposerSheet(
            mode: ComposerMode.reply,
            onSubmit: (title, content) async => true,
          ),
        ),
      ),
    );

    bool enabled(String key) =>
        tester
            .widget<OutlinedButton>(
              find.descendant(
                of: find.byKey(Key(key)),
                matching: find.byType(OutlinedButton),
              ),
            )
            .onPressed !=
        null;

    await tester.tap(find.byKey(const Key('embed-text')));
    await tester.pump();
    final window = find.byKey(const ValueKey('composer-layer-input-0'));
    await tester.enterText(window, 'A  B');
    await tester.pumpAndSettle();

    final centre = tester.getCenter(
      find.byKey(const ValueKey('composer-layer-0')),
    );
    await tester.tapAt(centre);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(centre);
    await tester.pump(const Duration(milliseconds: 350));

    // Nothing marked yet, so there is nowhere to step.
    expect(enabled('composer-marks-undo'), isFalse);
    expect(enabled('composer-marks-redo'), isFalse);

    await tester.tap(find.byKey(const Key('composer-space-single')));
    await tester.pumpAndSettle();
    final textRect = tester.getRect(window);
    await tester.tapAt(Offset(textRect.left + 22, textRect.top + 6));
    await tester.pumpAndSettle();
    expect(enabled('composer-marks-undo'), isTrue);
    expect(enabled('composer-marks-redo'), isFalse);

    await tester.tap(find.byKey(const Key('composer-marks-undo')));
    await tester.pumpAndSettle();
    expect(enabled('composer-marks-undo'), isFalse);
    expect(enabled('composer-marks-redo'), isTrue);

    await tester.tap(find.byKey(const Key('composer-marks-redo')));
    await tester.pumpAndSettle();
    expect(enabled('composer-marks-undo'), isTrue);
    expect(enabled('composer-marks-redo'), isFalse);

    // The erase button hands the picking back to the native selection, so the
    // tap interceptor comes off.
    await tester.tap(find.byKey(const Key('composer-space-erase')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('composer-space-pick-0')), findsNothing);
    expect(find.text('在窗口里选中文字，选区内的标记会被取消'), findsOneWidget);

    // Selecting across the marked run takes the mark off, which lands as a
    // further step in the history.
    tester.widget<TextField>(window).controller!.selection =
        const TextSelection(baseOffset: 1, extentOffset: 3);
    await tester.pumpAndSettle();
    expect(enabled('composer-marks-redo'), isFalse);
    await tester.tap(find.byKey(const Key('composer-marks-undo')));
    await tester.pumpAndSettle();
    expect(enabled('composer-marks-redo'), isTrue);
  });

  testWidgets('the confirmed editor never wraps a line', (tester) async {
    // The real font matters: fallback glyph widths are what a measured-width
    // layout gets wrong, and that is exactly what used to fold lines.
    final loader = FontLoader('Saitamaar')
      ..addFont(rootBundle.load('assets/fonts/Saitamaar.ttf'));
    await loader.load();

    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostComposerSheet(
            mode: ComposerMode.reply,
            onSubmit: (title, content) async => true,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Far wider than the phone-sized viewport, with mixed scripts so the font
    // has to fall back part way along.
    final text = [
      '这是一段包含汉字与假名的字符画测试行あいうえお＿＿＿' * 3,
      '( ﾟ∀ﾟ)＜ ${'─' * 120}',
      '短行',
    ].join('\n');

    await tester.tap(find.byKey(const Key('composer-primary-action')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('composer-preview-text')),
      text,
    );
    await tester.pumpAndSettle();

    final editable = find.byType(EditableText);
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: tester.widget<EditableText>(editable).style,
      ),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(tester.element(editable)),
    )..layout(maxWidth: tester.getSize(editable).width);

    // Laid out at the width the field actually got, the text must still occupy
    // exactly the lines it was written with.
    expect(painter.computeLineMetrics().length, text.split('\n').length);
  });

  testWidgets('new-thread composer owns a separate title field', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostComposerSheet(
            mode: ComposerMode.newThread,
            onSubmit: (title, content) async => true,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('composer-thread-title')), findsOneWidget);
    expect(find.text('登录：未登录'), findsOneWidget);
  });

  testWidgets('large windows keep their full width and the canvas pans in 2D', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: PostComposerSheet(
            mode: ComposerMode.reply,
            onSubmit: (title, content) async => true,
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('embed-text')));
    await tester.pump();
    await tester.enterText(
      find.byKey(const ValueKey('composer-layer-input-0')),
      List.filled(180, '1').join(),
    );
    await tester.pump();

    final layer = find.byKey(const ValueKey('composer-layer-0'));
    final canvas = find.byKey(const Key('composer-canvas'));
    expect(
      tester.getSize(layer).width,
      greaterThan(tester.getSize(canvas).width),
    );

    final before = tester.getTopLeft(layer);
    final canvasRect = tester.getRect(canvas);
    await tester.dragFrom(
      canvasRect.bottomRight - const Offset(16, 16),
      const Offset(-70, -55),
    );
    await tester.pump();
    final after = tester.getTopLeft(layer);
    expect(after.dx, lessThan(before.dx));
    expect(after.dy, lessThan(before.dy));
  });
}
