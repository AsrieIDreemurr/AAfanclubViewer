import 'package:aafanclub_viewer/ui/aa_text.dart';
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
    expect(
      tester
          .widget<AaText>(find.byKey(const Key('composer-preview-text')))
          .data,
      contains('ABC'),
    );
    expect(find.text('发送'), findsOneWidget);
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
