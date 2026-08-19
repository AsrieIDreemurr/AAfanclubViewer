import 'dart:async';
import 'dart:convert';

import 'package:aafanclub_viewer/app.dart';
import 'package:aafanclub_viewer/data/forum_repository.dart';
import 'package:aafanclub_viewer/domain/forum_document.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:scrollable_positioned_list/scrollable_positioned_list.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeRepository extends ForumRepository {
  final List<Uri> requestedUris = [];
  int refreshCalls = 0;
  int clearCacheCalls = 0;
  int loginCalls = 0;
  String? loginName;
  String? loginTrip;

  @override
  Future<ForumDocument> load(Uri uri) async {
    requestedUris.add(uri);
    if (uri.path.startsWith('/view/1')) {
      final page = uri.path.endsWith('-2') ? 2 : 1;
      final posts =
          page == 2
              ? List.generate(
                50,
                (index) => ForumPost(
                  number: '${index + 51}',
                  name: '作者',
                  body: '第 ${index + 51} 楼',
                ),
              )
              : [
                const ForumPost(
                  number: '1',
                  name: '作者',
                  body: '第一楼\n　 ∧＿∧\n第二行\n第三行\n第四行',
                ),
                ForumPost(
                  number: '2',
                  name: '读者',
                  body: '>> 75',
                  bodyRuns: [
                    ForumTextRun(
                      text: '>> 75',
                      tone: ForumTextTone.link,
                      uri: Uri.parse('http://aafanclub.com/view/1#f75'),
                    ),
                  ],
                ),
              ];
      return ForumDocument(
        uri: uri,
        title: '测试帖子',
        kind: ForumPageKind.thread,
        site: ForumSite.aaFanclub,
        encoding: 'UTF-8',
        threadId: '1',
        currentPage: page,
        pageCount: 2,
        posts: posts,
        pagination: [
          ForumLink(
            title: '1',
            uri: Uri.parse('http://aafanclub.com/view/1-1'),
            pageNumber: 1,
          ),
          ForumLink(
            title: '2',
            uri: Uri.parse('http://aafanclub.com/view/1-2'),
            pageNumber: 2,
          ),
        ],
      );
    }
    return ForumDocument(
      uri: uri,
      title: 'AA同好会揭示板',
      kind: ForumPageKind.board,
      site: ForumSite.aaFanclub,
      encoding: 'UTF-8',
      textBlocks: const ['最新更新\n\n欢迎来到揭示板', '当前昵称：互联网的无名者 ■修改■'],
      threads: [
        ForumThreadSummary(
          title: '测试帖子',
          uri: uri.resolve('/view/1'),
          replyCount: 3,
          previewPosts: const [
            ForumPost(number: '1', name: '作者', body: '　 ∧＿∧'),
          ],
        ),
      ],
    );
  }

  /// Lets a test hold a refresh open to observe the in-progress state.
  Future<void>? refreshGate;

  @override
  Future<ForumDocument> refresh(ForumDocument current) async {
    refreshCalls++;
    final gate = refreshGate;
    if (gate != null) await gate;
    return current;
  }

  @override
  Future<int> clearCache() async {
    clearCacheCalls++;
    return 1;
  }

  @override
  Future<ForumDocument> login(
    ForumDocument current, {
    required String name,
    required String trip,
  }) async {
    loginCalls++;
    loginName = name;
    loginTrip = trip;
    return current;
  }
}

/// Delivers the Android system back key the same way the engine does.
Future<void> pressSystemBack(WidgetTester tester) {
  return tester.binding.defaultBinaryMessenger.handlePlatformMessage(
    'flutter/navigation',
    const JSONMethodCodec().encodeMethodCall(const MethodCall('popRoute')),
    (_) {},
  );
}

Future<void> openReaderPanel(WidgetTester tester) async {
  final edgeRect = tester.getRect(find.byKey(const Key('edge-tap-surface')));
  await tester.tapAt(Offset(edgeRect.right - 20, edgeRect.center.dy));
  await tester.pumpAndSettle();
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('opens the AA Fanclub homepage on launch with classic styling', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await tester.pumpWidget(AaFanclubApp(repository: repository));
    await tester.pumpAndSettle();

    expect(repository.requestedUris.single, Uri.parse('http://aafanclub.com/'));
    expect(find.text('AA同好会揭示板'), findsOneWidget);
    expect(find.text('■帖子一览■'), findsOneWidget);
    expect(find.text('■点此发帖■'), findsNothing);
    expect(find.textContaining('修改'), findsNothing);
    expect(find.text('测试帖子'), findsOneWidget);
    expect(find.textContaining('∧＿∧'), findsOneWidget);
  });

  testWidgets('restores cached login and opens the bottom composer', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({
      'reader.login.v1': jsonEncode({'name': 'Asriel', 'trip': 'dummy-trip-key'}),
    });
    final repository = _FakeRepository();
    await tester.pumpWidget(AaFanclubApp(repository: repository));
    await tester.pumpAndSettle();

    expect(repository.loginCalls, 1);
    expect(repository.loginName, 'Asriel');
    expect(repository.loginTrip, 'dummy-trip-key');

    final edgeRect = tester.getRect(find.byKey(const Key('edge-tap-surface')));
    await tester.tapAt(Offset(edgeRect.right - 20, edgeRect.center.dy));
    await tester.pumpAndSettle();
    await tester.tap(find.text('新建帖子'));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('post-composer-sheet')), findsOneWidget);
    expect(find.text('登录：Asriel'), findsOneWidget);
    expect(find.byKey(const Key('composer-thread-title')), findsOneWidget);
    expect(find.byKey(const Key('new-thread-content')), findsNothing);

    await tester.tapAt(const Offset(400, 20));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('post-composer-sheet')), findsNothing);
  });

  testWidgets('uses invisible edge tap zones and ignores drags', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await tester.pumpWidget(AaFanclubApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('address-field')), findsNothing);
    expect(find.text('HTTP'), findsNothing);

    final edgeSurface = find.byKey(const Key('edge-tap-surface'));
    final edgeRect = tester.getRect(edgeSurface);
    final leftPoint = Offset(edgeRect.left + 20, edgeRect.center.dy);
    final rightPoint = Offset(edgeRect.right - 20, edgeRect.center.dy);
    expect(find.text('↻'), findsNothing);
    expect(find.text('‹'), findsNothing);

    await tester.dragFrom(leftPoint, const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(repository.refreshCalls, 0);

    await tester.tapAt(leftPoint);
    await tester.pump();
    expect(repository.refreshCalls, 1);
    expect(find.text('帖子列表已刷新'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('帖子列表已刷新'), findsNothing);

    await tester.dragFrom(rightPoint, const Offset(0, -80));
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const Key('reader-side-panel'))).dx,
      greaterThanOrEqualTo(800),
    );

    await tester.tapAt(rightPoint);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('reader-side-panel')), findsOneWidget);
    expect(find.byKey(const Key('display-scale-slider')), findsOneWidget);
    expect(find.text('登录'), findsOneWidget);
    expect(find.text('新建帖子'), findsOneWidget);
    expect(find.byKey(const Key('clear-thread-cache')), findsOneWidget);

    await tester.tap(find.byKey(const Key('clear-thread-cache')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('清除').last);
    await tester.pumpAndSettle();
    expect(repository.clearCacheCalls, 1);
  });

  testWidgets('thread drawer can bookmark the visible floor', (tester) async {
    final repository = _FakeRepository();
    await tester.pumpWidget(AaFanclubApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('测试帖子').first);
    await tester.pumpAndSettle();
    final edgeRect = tester.getRect(find.byKey(const Key('edge-tap-surface')));
    await tester.tapAt(Offset(edgeRect.right - 20, edgeRect.center.dy));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('bookmark-current')));
    await tester.pumpAndSettle();

    expect(find.textContaining('帖子标签（1）'), findsOneWidget);
    expect(find.byKey(const ValueKey('thread-tab-1')), findsOneWidget);
    expect(find.textContaining('楼层书签（1）'), findsOneWidget);
    expect(find.textContaining('#1'), findsWidgets);
  });

  testWidgets('saved thread tabs reopen their recorded floor', (tester) async {
    final now = DateTime(2026, 8, 17).toIso8601String();
    SharedPreferences.setMockInitialValues({
      'reader.progress.v1': jsonEncode([
        {
          'threadId': '1',
          'threadTitle': '测试帖子',
          'uri': 'http://aafanclub.com/view/1-2',
          'floor': 75,
          'updatedAt': now,
        },
      ]),
    });
    final repository = _FakeRepository();
    await tester.pumpWidget(AaFanclubApp(repository: repository));
    await tester.pumpAndSettle();

    final edgeRect = tester.getRect(find.byKey(const Key('edge-tap-surface')));
    await tester.tapAt(Offset(edgeRect.right - 20, edgeRect.center.dy));
    await tester.pumpAndSettle();

    expect(find.textContaining('帖子标签（1）'), findsOneWidget);
    expect(find.text('#75'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('thread-tab-1')));
    await tester.pumpAndSettle();

    expect(
      repository.requestedUris.last,
      Uri.parse('http://aafanclub.com/view/1-2'),
    );
    expect(find.text('第 75 楼'), findsOneWidget);
  });

  testWidgets('pagination cells shrink with the page number text', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({'reader.displayScale.v1': 0.3});
    final repository = _FakeRepository();
    await tester.pumpWidget(AaFanclubApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('测试帖子').first);
    await tester.pumpAndSettle();

    final cell = find.byKey(const ValueKey('nav-page-1')).first;
    final number = find.descendant(of: cell, matching: find.text('1'));
    final cellHeight = tester.getSize(cell).height;
    final numberHeight = tester.getSize(number).height;

    expect(cellHeight, lessThanOrEqualTo(numberHeight + 6.1));
  });

  testWidgets('floor links beat edge taps and jump across pages', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await tester.pumpWidget(AaFanclubApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('测试帖子').first);
    await tester.pumpAndSettle();
    expect(repository.refreshCalls, 1);
    repository.refreshCalls = 0;

    final body = find.byKey(const Key('post-body-2'));
    final linkPoint = tester.getTopLeft(body) + const Offset(8, 5);
    expect(linkPoint.dx, lessThan(56));
    await tester.tapAt(linkPoint);
    await tester.pumpAndSettle();

    expect(repository.refreshCalls, 1);
    expect(
      repository.requestedUris.last,
      Uri.parse('http://aafanclub.com/view/1-2'),
    );
    expect(find.text('第 75 楼'), findsOneWidget);
  });

  testWidgets('pulling past the bottom refreshes and rebounds', (tester) async {
    final repository = _FakeRepository();
    await tester.pumpWidget(AaFanclubApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('测试帖子').first);
    await tester.pumpAndSettle();
    final pageTwoCell = find.byKey(const ValueKey('nav-page-2')).first;
    await tester.tap(
      find.descendant(of: pageTwoCell, matching: find.text('2')),
    );
    await tester.pumpAndSettle();

    final thread = find.byType(ScrollablePositionedList);
    await tester.drag(thread, const Offset(0, -10000));
    await tester.pumpAndSettle();
    repository.refreshCalls = 0;

    await tester.drag(thread, const Offset(0, -180));
    await tester.pumpAndSettle();

    expect(repository.refreshCalls, 1);
    expect(find.byKey(const Key('pull-refresh-indicator')), findsNothing);

    // Pulling down at the top refreshes just as pulling up at the bottom does.
    await tester.drag(thread, const Offset(0, 10000));
    await tester.pumpAndSettle();
    repository.refreshCalls = 0;

    await tester.drag(thread, const Offset(0, 180));
    await tester.pumpAndSettle();

    expect(repository.refreshCalls, 1);
    expect(find.byKey(const Key('pull-refresh-indicator')), findsNothing);
  });

  testWidgets('the bottom nav row carries a reply button', (tester) async {
    final repository = _FakeRepository();
    await tester.pumpWidget(AaFanclubApp(repository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试帖子').first);
    await tester.pumpAndSettle();

    // Only the row under the last post has it, not the one above the thread.
    expect(find.byKey(const Key('nav-reply')), findsOneWidget);
    await tester.tap(find.byKey(const Key('nav-reply')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('post-composer-sheet')), findsOneWidget);
    expect(find.byKey(const Key('composer-thread-title')), findsNothing);
  });

  testWidgets('the pull indicator says it is refreshing while it runs', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await tester.pumpWidget(AaFanclubApp(repository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试帖子').first);
    await tester.pumpAndSettle();

    final thread = find.byType(ScrollablePositionedList);
    await tester.drag(thread, const Offset(0, 10000));
    await tester.pumpAndSettle();

    // Hold the next refresh open only now, so opening the thread could settle.
    final gate = Completer<void>();
    repository.refreshGate = gate.future;

    // Hold the drag past the trigger so the "release" wording shows first.
    final start = tester.getCenter(thread);
    final gesture = await tester.startGesture(start);
    await gesture.moveBy(const Offset(0, 180));
    await tester.pump();
    expect(find.text('松开刷新'), findsOneWidget);

    // The bounce has to spring back before the scroll reports it ended, and
    // pumpAndSettle cannot be used here: the loading bar animates forever
    // while the gated refresh is in flight.
    await gesture.up();
    for (var frame = 0; frame < 40 && repository.refreshCalls < 3; frame++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(find.text('正在刷新'), findsOneWidget);
    expect(find.text('松开刷新'), findsNothing);

    gate.complete();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('pull-refresh-indicator')), findsNothing);
  });

  testWidgets('restores a cached page and jumps to an off-screen floor', (
    tester,
  ) async {
    final now = DateTime(2026, 8, 17).toIso8601String();
    SharedPreferences.setMockInitialValues({
      'reader.progress.v1': jsonEncode([
        {
          'threadId': '1',
          'threadTitle': '测试帖子',
          'uri': 'http://aafanclub.com/view/1-2',
          'floor': 75,
          'updatedAt': now,
        },
      ]),
    });
    final repository = _FakeRepository();
    await tester.pumpWidget(AaFanclubApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('测试帖子').first);
    await tester.pumpAndSettle();

    expect(
      repository.requestedUris.last,
      Uri.parse('http://aafanclub.com/view/1-2'),
    );
    expect(find.text('第 75 楼'), findsOneWidget);
  });

  testWidgets('the system back key closes the panel, then walks history', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await tester.pumpWidget(AaFanclubApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('测试帖子').first);
    await tester.pumpAndSettle();
    expect(find.textContaining('第一楼'), findsOneWidget);

    await openReaderPanel(tester);
    await pressSystemBack(tester);
    await tester.pumpAndSettle();
    expect(
      tester.getTopLeft(find.byKey(const Key('reader-side-panel'))).dx,
      greaterThanOrEqualTo(800),
    );
    expect(find.textContaining('第一楼'), findsOneWidget);

    await pressSystemBack(tester);
    await tester.pumpAndSettle();
    expect(repository.requestedUris.last, Uri.parse('http://aafanclub.com/'));
    expect(find.text('■帖子一览■'), findsOneWidget);

    await pressSystemBack(tester);
    await tester.pump();
    expect(find.text('再按一次返回键退出'), findsOneWidget);
  });

  testWidgets('the side panel pages through a thread', (tester) async {
    final repository = _FakeRepository();
    await tester.pumpWidget(AaFanclubApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('测试帖子').first);
    await tester.pumpAndSettle();
    await openReaderPanel(tester);

    expect(find.text('第 1 / 2 页'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.descendant(
              of: find.byKey(const Key('panel-previous-page')),
              matching: find.byType(OutlinedButton),
            ),
          )
          .onPressed,
      isNull,
    );

    await tester.tap(find.byKey(const Key('panel-next-page')));
    await tester.pumpAndSettle();

    expect(
      repository.requestedUris.last,
      Uri.parse('http://aafanclub.com/view/1-2'),
    );
    expect(find.text('第 51 楼'), findsOneWidget);
  });

  testWidgets('jumping to a floor opens the page holding it', (tester) async {
    final repository = _FakeRepository();
    await tester.pumpWidget(AaFanclubApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('测试帖子').first);
    await tester.pumpAndSettle();
    await openReaderPanel(tester);
    await tester.tap(find.byKey(const Key('panel-jump-floor')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('jump-to-floor-dialog')), findsOneWidget);
    await tester.enterText(find.byKey(const Key('jump-to-floor-input')), '75');
    await tester.tap(find.byKey(const Key('jump-to-floor-confirm')));
    await tester.pumpAndSettle();

    expect(
      repository.requestedUris.last,
      Uri.parse('http://aafanclub.com/view/1-2'),
    );
    expect(find.text('第 75 楼'), findsOneWidget);
  });

  testWidgets('desktop shows a toolbar and drops the invisible edges', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    final repository = _FakeRepository();
    await tester.pumpWidget(AaFanclubApp(repository: repository));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('desktop-toolbar')), findsOneWidget);
    expect(find.byKey(const Key('toolbar-page-indicator')), findsOneWidget);

    // The left edge no longer reloads now that the toolbar owns that job.
    final edgeRect = tester.getRect(find.byKey(const Key('edge-tap-surface')));
    await tester.tapAt(Offset(edgeRect.left + 20, edgeRect.center.dy));
    await tester.pump();
    expect(repository.refreshCalls, 0);

    await tester.tap(find.byKey(const Key('toolbar-reload')));
    await tester.pump();
    expect(repository.refreshCalls, 1);

    await tester.tap(find.byKey(const Key('toolbar-panel')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('display-scale-slider')), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a thread tab can be closed from the panel', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await tester.pumpWidget(AaFanclubApp(repository: repository));
    await tester.pumpAndSettle();

    await tester.tap(find.text('测试帖子').first);
    await tester.pumpAndSettle();
    await openReaderPanel(tester);
    expect(find.byKey(const ValueKey('thread-tab-1')), findsOneWidget);
    expect(find.text('#1'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('thread-tab-close-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('thread-tab-1')), findsNothing);
    expect(find.text('还没有打开过帖子'), findsOneWidget);
  });

  testWidgets('double tapping reveals the edge zones until the next action', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await tester.pumpWidget(AaFanclubApp(repository: repository));
    await tester.pumpAndSettle();

    final edge = find.byKey(const Key('edge-tap-surface'));
    final middle = tester.getRect(edge).center;
    expect(find.byKey(const Key('edge-hint-left')), findsNothing);

    await tester.tapAt(middle);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(middle);
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('edge-hint-left')), findsOneWidget);
    expect(find.byKey(const Key('edge-hint-right')), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const Key('edge-hint-left')),
        matching: find.text('刷新'),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('edge-hint-right')),
        matching: find.text('阅读工具'),
      ),
      findsOneWidget,
    );

    // The hint never swallows a tap: the zone underneath still refreshes.
    final edgeRect = tester.getRect(edge);
    await tester.tapAt(Offset(edgeRect.left + 20, edgeRect.center.dy));
    await tester.pumpAndSettle();
    expect(repository.refreshCalls, 1);
    expect(find.byKey(const Key('edge-hint-left')), findsNothing);

    // A double tap on post text beats the SelectionArea's word selection.
    await tester.tap(find.text('测试帖子').first);
    await tester.pumpAndSettle();
    final body = tester.getCenter(find.byKey(const Key('post-body-1')));
    await tester.tapAt(body);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(body);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edge-hint-left')), findsOneWidget);

    // Long press still belongs to the text, so copying keeps working.
    await tester.longPressAt(body);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edge-hint-left')), findsNothing);

    await tester.tap(find.text('■回到首页■').first);
    await tester.pumpAndSettle();

    // Two slow taps are not a double tap.
    await tester.tapAt(middle);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.tapAt(middle);
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('edge-hint-left')), findsNothing);
  });

  testWidgets('an edge tap works even when it lands on selectable text', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await tester.pumpWidget(AaFanclubApp(repository: repository));
    await tester.pumpAndSettle();
    await tester.tap(find.text('测试帖子').first);
    await tester.pumpAndSettle();
    repository.refreshCalls = 0;

    // Find a spot inside the left zone that is covered by a post's
    // SelectionArea — that combination used to swallow the tap outright,
    // because SelectionArea wins the gesture arena against an ancestor.
    final surface = tester.getRect(find.byKey(const Key('edge-tap-surface')));
    final zone = Rect.fromLTWH(0, (surface.height - 156) / 2, 96, 156);
    Offset? onText;
    for (final element in find.byType(SelectionArea).evaluate()) {
      final box = element.renderObject as RenderBox?;
      if (box == null || !box.hasSize) continue;
      final overlap = (box.localToGlobal(Offset.zero) & box.size).intersect(
        zone,
      );
      if (overlap.width > 4 && overlap.height > 4) {
        onText = overlap.center;
        break;
      }
    }
    expect(onText, isNotNull, reason: '需要一个既在点击区内、又在文字上的点');

    await tester.tapAt(onText!);
    await tester.pumpAndSettle();
    expect(repository.refreshCalls, 1);
  });

  testWidgets('a shown edge zone can be moved, resized and reset', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await tester.pumpWidget(AaFanclubApp(repository: repository));
    await tester.pumpAndSettle();

    final middle = tester.getRect(find.byKey(const Key('edge-tap-surface')));
    await tester.tapAt(middle.center);
    await tester.pump(const Duration(milliseconds: 60));
    await tester.tapAt(middle.center);
    await tester.pumpAndSettle();

    final zone = find.byKey(const Key('edge-hint-left'));
    expect(zone, findsOneWidget);
    final before = tester.getRect(zone);
    // Nothing has been adjusted yet, so there is nothing to reset.
    expect(find.byKey(const Key('edge-reset-left')), findsNothing);

    await tester.drag(zone, const Offset(0, 90));
    await tester.pumpAndSettle();
    final moved = tester.getRect(zone);
    expect(moved.top, greaterThan(before.top));
    expect(moved.size, before.size);
    expect(find.byKey(const Key('edge-reset-left')), findsOneWidget);

    await tester.drag(
      find.byKey(const Key('edge-resize-left')),
      const Offset(30, 40),
    );
    await tester.pumpAndSettle();
    final resized = tester.getRect(zone);
    expect(resized.width, greaterThan(moved.width));
    expect(resized.height, greaterThan(moved.height));

    await tester.tap(find.byKey(const Key('edge-reset-left')));
    await tester.pumpAndSettle();
    expect(tester.getRect(zone), before);
    expect(find.byKey(const Key('edge-reset-left')), findsNothing);
    // The right zone was never touched, so it keeps its own default.
    expect(find.byKey(const Key('edge-reset-right')), findsNothing);
  });

  testWidgets('links turn red while held and take taps beyond the glyphs', (
    tester,
  ) async {
    final repository = _FakeRepository();
    await tester.pumpWidget(AaFanclubApp(repository: repository));
    await tester.pumpAndSettle();

    final title = find.text('测试帖子').first;
    Color? titleColor() => tester.widget<Text>(title).style?.color;
    expect(titleColor(), const Color(0xff0000ff));

    // Press in the slack just below the glyphs, past the tap deadline.
    final glyphs = tester.getRect(title);
    final gesture = await tester.startGesture(
      Offset(glyphs.left + 4, glyphs.bottom + 4),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(titleColor(), const Color(0xffff0000));

    // Releasing there still opens the thread, so the slack really is tappable.
    await gesture.up();
    await tester.pumpAndSettle();
    expect(repository.requestedUris.last.path, startsWith('/view/1'));
  });
}
