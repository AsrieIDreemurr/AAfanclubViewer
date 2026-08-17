import 'package:aafanclub_viewer/application/reader_store.dart';
import 'package:aafanclub_viewer/domain/forum_document.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test(
    'records the highest floor and creates floor-specific bookmarks',
    () async {
      final store = ReaderStore();
      await store.load();
      final document = ForumDocument(
        uri: Uri.parse('http://aafanclub.com/view/20-2'),
        title: '阅读进度测试',
        kind: ForumPageKind.thread,
        encoding: 'UTF-8',
        site: ForumSite.aaFanclub,
        threadId: '20',
        currentPage: 2,
      );

      store.recordProgress(document, 78);
      store.recordProgress(document, 60);
      expect(store.progressFor('20')?.floor, 78);
      expect(store.openedThreads.single.threadId, '20');
      expect(
        store.progressFor('20')?.uri,
        Uri.parse('http://aafanclub.com/view/20-2'),
      );

      final secondDocument = ForumDocument(
        uri: Uri.parse('http://aafanclub.com/view/21'),
        title: '第二个帖子',
        kind: ForumPageKind.thread,
        encoding: 'UTF-8',
        site: ForumSite.aaFanclub,
        threadId: '21',
        currentPage: 1,
      );
      store.markThreadOpened(secondDocument, 3);
      expect(
        store.openedThreads.map((item) => item.threadId),
        containsAll(['20', '21']),
      );
      expect(store.progressFor('21')?.floor, 3);

      store.markThreadOpened(document, 60);
      expect(store.progressFor('20')?.floor, 78);

      expect(store.addBookmark(document, 101), isTrue);
      expect(store.addBookmark(document, 101), isFalse);
      expect(store.bookmarks.single.floor, 101);
      expect(
        store.bookmarks.single.uri,
        Uri.parse('http://aafanclub.com/view/20-3'),
      );

      store.setDisplayScale(0.1);
      expect(store.displayScale, 0.3);
    },
  );

  test('persists cached login information for the next app launch', () async {
    final first = ReaderStore();
    await first.load();
    first.saveLogin(' Asriel ', 'dummy-trip-key');
    await Future<void>.delayed(Duration.zero);

    final second = ReaderStore();
    await second.load();
    expect(second.login?.name, 'Asriel');
    expect(second.login?.trip, 'dummy-trip-key');
  });
}
