import 'package:aafanclub_viewer/data/aafanclub_adapter.dart';
import 'package:aafanclub_viewer/domain/forum_document.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const adapter = AaFanclubAdapter();

  test('parses the real board-list structure and pagination', () {
    const source = '''
      <html><head><title>AA同好会揭示板测试服</title></head><body bgcolor="#EFEFEF">
      <table><tr><td><a href="/">■回到首页■</a></td>
        <td>1</td><td><a href="/form-1-2/">2</a></td>
        <td><a href="/form-1-14/">14</a></td></tr></table>
      <dl class="thread">
        <hr><div><font size="+2" color="#FF0000"><a href="/view/657">第一帖</a></font>
        【楼层数 ： 6766】【最新回复 ： 2026年08月17日 15:57:51】</div>
        <dt>657 ：<font color="green"><b>白毛爺爺</b></font>：2026年06月15日 14:50:32 ID:EEKxi50J</dt>
      </dl></body></html>
    ''';

    final result = adapter.parse(
      source: source,
      uri: Uri.parse('http://aafanclub.com/form-1-1/'),
      encoding: 'UTF-8',
    );

    expect(result.site, ForumSite.aaFanclub);
    expect(result.kind, ForumPageKind.board);
    expect(result.currentPage, 1);
    expect(result.pageCount, 14);
    expect(result.threads, hasLength(1));
    expect(result.threads.single.title, '第一帖');
    expect(result.threads.single.replyCount, 6766);
    expect(result.threads.single.author, '白毛爺爺');
    expect(result.threads.single.id, 'EEKxi50J');
  });

  test('parses thread posts, page links and original inline colors', () {
    const source = '''
      <html><head><title>测试帖子</title></head><body bgcolor="#EFEFEF">
      <table><tr><td><a href="/">■回到首页■</a></td>
        <td><a href="/view/657-1-icchi">■只看贴主■</a></td>
        <td>1</td><td><a href="/view/657-2">2</a></td>
        <td><a href="/view/657-136">136</a></td></tr></table>
      <h1>测试帖子</h1><div style="white-space: pre;">
        <dt id="f1">1 ： <font color="green"><b>◆作者</b></font> ： 2026年08月17日 12:00:00 ID:ABCDEFGH</dt><br>
        <dd>　 ∧＿∧<br><a href="#f2">&gt;&gt; 2</a> 【1d10 ： <font color="red"><b>5</b></font>】<br><br></dd>
        <dt id="f2">2 ： 读者 ： 2026年08月17日 12:01:00 ID:MOCKID99</dt><br>
        <dd>回复</dd>
      </div></body></html>
    ''';

    final result = adapter.parse(
      source: source,
      uri: Uri.parse('http://aafanclub.com/view/657'),
      encoding: 'UTF-8',
    );

    expect(result.kind, ForumPageKind.thread);
    expect(result.threadId, '657');
    expect(result.currentPage, 1);
    expect(result.pageCount, 136);
    expect(result.ownerFilter?.title, '■只看贴主■');
    expect(
      result.ownerFilter?.uri,
      Uri.parse('http://aafanclub.com/view/657-1-icchi'),
    );
    expect(
      result.pagination.map((link) => link.pageNumber),
      containsAll([1, 2, 136]),
    );
    expect(result.posts, hasLength(2));
    expect(result.posts.first.name, '◆作者');
    expect(result.posts.first.authorIsTrip, isTrue);
    expect(result.posts.first.body, contains('　 ∧＿∧'));
    expect(
      result.posts.first.bodyRuns.any(
        (run) => run.text.contains('>> 2') && run.tone == ForumTextTone.link,
      ),
      isTrue,
    );
    expect(
      result.posts.first.bodyRuns.any(
        (run) => run.text == '5' && run.tone == ForumTextTone.red && run.bold,
      ),
      isTrue,
    );
  });

  test('owner-only pages flip the filter link and keep their pagination', () {
    // Shape copied from a live http://aafanclub.com/view/388-1-icchi response.
    const source = '''
      <html><head><title>只看贴主</title></head><body bgcolor="#EFEFEF">
      <table><tr><td><a href="/">■回到首页■</a></td>
        <td><a href="/view/388-1">■查看全部■</a></td>
        <td>1</td><td><a href="/view/388-2-icchi">2</a></td>
        <td><a href="/view/388-63-icchi">63</a></td></tr></table>
      <h1>贴主专用</h1>
        <dt id="f1">1 ： 贴主 ： 2026年08月17日 12:00:00 ID:ABCDEFGH</dt>
        <dd>只有贴主的楼层</dd>
      </body></html>
    ''';

    final result = adapter.parse(
      source: source,
      uri: Uri.parse('http://aafanclub.com/view/388-1-icchi'),
      encoding: 'UTF-8',
    );

    expect(result.threadId, '388');
    expect(result.ownerFilter?.title, '■查看全部■');
    expect(
      result.ownerFilter?.uri,
      Uri.parse('http://aafanclub.com/view/388-1'),
    );
    // The ■查看全部■ target must not be mistaken for page one of this view.
    expect(result.pagination.map((link) => link.pageNumber), [1, 2, 63]);
    expect(
      result.pagination.firstWhere((link) => link.pageNumber == 2).uri,
      Uri.parse('http://aafanclub.com/view/388-2-icchi'),
    );
    expect(result.pageCount, 63);
  });

  test('parses homepage notices and preview posts', () {
    const source = '''
      <html><body><table bgcolor="#CCFFCC"><tr><td>AA同好会揭示板</td></tr>
      <tr><td>最新更新<br>欢迎来到揭示板</td></tr>
      <tr><th>帖子一览</th><th>当前昵称：互联网的无名者</th><th>点此发帖</th></tr></table>
      <table bgcolor="#EFEFEF"><tr><td><a href="/view/10"><font color="#0000FF">预览帖子</font></a>
      <dl><dt id="f1">1 ： 作者 ： 2026年08月17日 10:00:00 ID:ABCDEFGH</dt><br>
      <dd>第一楼</dd><dt id="f9">9 ： 读者 ： 2026年08月17日 11:00:00 ID:MOCKID99</dt><br>
      <dd>最新楼</dd></dl></td></tr></table></body></html>
    ''';

    final result = adapter.parse(
      source: source,
      uri: Uri.parse('http://aafanclub.com/'),
      encoding: 'UTF-8',
    );

    expect(result.textBlocks.first, contains('欢迎来到揭示板'));
    expect(result.textBlocks[1], contains('当前昵称'));
    expect(result.threads.single.replyCount, 9);
    expect(result.threads.single.previewPosts, hasLength(2));
  });
}
