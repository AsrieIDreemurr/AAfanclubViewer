import 'dart:convert';

import 'package:aafanclub_viewer/app.dart';
import 'package:aafanclub_viewer/data/forum_repository.dart';
import 'package:aafanclub_viewer/domain/forum_document.dart';
import 'package:flutter/material.dart';
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

  @override
  Future<ForumDocument> refresh(ForumDocument current) async {
    refreshCalls++;
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
    expect(
      find.byKey(const Key('bottom-pull-refresh-indicator')),
      findsNothing,
    );
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
}
