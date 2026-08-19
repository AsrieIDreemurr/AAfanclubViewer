import 'package:aafanclub_viewer/ui/post_composer_sheet.dart';
import 'package:flutter/material.dart';
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
