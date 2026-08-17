import 'package:aafanclub_viewer/data/generic_forum_parser.dart';
import 'package:aafanclub_viewer/domain/forum_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const parser = GenericForumParser();

  test('parses classic dt/dd posts while preserving AA whitespace', () {
    const source = '''
      <html><head><title>fallback</title></head><body>
        <h1>AA 総合スレ</h1>
        <dl>
          <dt>1 名前：名無しさん 2026/08/17 12:34:56 ID:AbC123</dt>
          <dd>first line<br>　 ∧＿∧<br>　( ´･ω･)</dd>
          <dt>2 名前：AA好き 2026/08/17 12:36:00</dt>
          <dd>second post</dd>
        </dl>
      </body></html>
    ''';

    final result = parser.parse(
      source: source,
      uri: Uri.parse('https://example.jp/test/read.cgi/aa/1'),
      encoding: 'Shift_JIS',
    );

    expect(result.kind, ForumPageKind.thread);
    expect(result.title, 'AA 総合スレ');
    expect(result.posts, hasLength(2));
    expect(result.posts.first.number, '1');
    expect(result.posts.first.name, '名無しさん');
    expect(result.posts.first.id, 'AbC123');
    expect(result.posts.first.body, 'first line\n　 ∧＿∧\n　( ´･ω･)');
  });

  test('parses same-origin thread links as a board', () {
    const source = '''
      <html><head><title>AA Board</title></head><body>
        <a href="/test/read.cgi/aa/100">雑談スレ (42)</a>
        <a href="https://outside.example/thread/2">outside (9)</a>
        <a href="/about">about</a>
      </body></html>
    ''';

    final result = parser.parse(
      source: source,
      uri: Uri.parse('https://example.jp/aa/'),
      encoding: 'UTF-8',
    );

    expect(result.kind, ForumPageKind.board);
    expect(result.links, hasLength(1));
    expect(result.links.single.replyCount, 42);
    expect(
      result.links.single.uri,
      Uri.parse('https://example.jp/test/read.cgi/aa/100'),
    );
  });
}
