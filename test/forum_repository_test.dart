import 'dart:io';

import 'package:aafanclub_viewer/data/forum_repository.dart';
import 'package:aafanclub_viewer/data/page_source.dart';
import 'package:aafanclub_viewer/data/thread_page_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test(
    'thread refresh keeps old floors and appends floors from a new page',
    () async {
      var secondPageLoads = 0;
      final client = MockClient((request) async {
        if (request.url.path == '/view/10-3') {
          return http.Response(
            _threadHtml(
              title: '刷新测试',
              navLastPage: 3,
              posts: const [(101, 'new page floor')],
            ),
            200,
            headers: const {'content-type': 'text/html; charset=utf-8'},
            request: request,
          );
        }
        secondPageLoads++;
        return http.Response(
          _threadHtml(
            title: '刷新测试',
            navLastPage: secondPageLoads == 1 ? 2 : 3,
            posts:
                secondPageLoads == 1
                    ? const [(51, 'immutable original')]
                    : const [
                      (51, 'changed on server'),
                      (52, 'new same-page floor'),
                    ],
          ),
          200,
          headers: const {'content-type': 'text/html; charset=utf-8'},
          request: request,
        );
      });
      final repository = NetworkForumRepository(
        source: NetworkPageSource(client: client),
      );

      final initial = await repository.load(
        Uri.parse('http://aafanclub.com/view/10-2'),
      );
      final refreshed = await repository.refresh(initial);

      expect(refreshed.posts.map((post) => post.number), ['51', '52', '101']);
      expect(refreshed.posts.first.body, 'immutable original');
      expect(refreshed.posts[1].body, 'new same-page floor');
      expect(refreshed.posts.last.body, 'new page floor');
      expect(refreshed.currentPage, 2);
      expect(refreshed.pageCount, 3);
    },
  );

  test(
    'reopens a visited thread page from cache until cache is cleared',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'aafanclub-repository-cache-',
      );
      addTearDown(() async {
        if (await directory.exists()) await directory.delete(recursive: true);
      });
      var networkLoads = 0;
      final client = MockClient((request) async {
        networkLoads++;
        return http.Response(
          _threadHtml(
            title: '缓存测试',
            navLastPage: 1,
            posts: const [(1, 'cached floor')],
          ),
          200,
          headers: const {'content-type': 'text/html; charset=utf-8'},
          request: request,
        );
      });
      final repository = NetworkForumRepository(
        source: NetworkPageSource(client: client),
        cache: ThreadPageCache(directoryProvider: () async => directory),
      );

      await repository.load(Uri.parse('http://aafanclub.com/view/10'));
      await repository.load(Uri.parse('http://aafanclub.com/view/10-1'));
      expect(networkLoads, 1);

      await repository.clearCache();
      await repository.load(Uri.parse('http://aafanclub.com/view/10'));
      expect(networkLoads, 2);
    },
  );
}

String _threadHtml({
  required String title,
  required int navLastPage,
  required List<(int, String)> posts,
}) {
  final content =
      posts
          .map(
            (post) =>
                '<dt id="f${post.$1}">${post.$1} ： 作者 ： '
                '2026年08月17日 12:00:00 ID:ABCDEFGH</dt><br>'
                '<dd>${post.$2}</dd>',
          )
          .join();
  return '''
    <html><head><title>$title</title></head><body>
    <table><tr><td><a href="/view/10-1">1</a></td>
    <td><a href="/view/10-$navLastPage">$navLastPage</a></td></tr></table>
    <h1>$title</h1><div style="white-space: pre;">$content</div>
    </body></html>
  ''';
}
