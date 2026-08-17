import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../domain/forum_document.dart';
import 'site_adapter.dart';

class AaFanclubAdapter implements SiteAdapter {
  const AaFanclubAdapter();

  static final RegExp _threadPath = RegExp(
    r'^/view/(\d+)(?:-(\d+))?(?:-icchi)?/?$',
  );
  static final RegExp _boardPath = RegExp(r'^/form-(\d+)-(\d+)/?$');

  @override
  bool supports(Uri uri) {
    final host = uri.host.toLowerCase();
    return host == 'aafanclub.com' || host == 'www.aafanclub.com';
  }

  @override
  ForumDocument parse({
    required String source,
    required Uri uri,
    required String encoding,
  }) {
    final document = html_parser.parse(source);
    final threadMatch = _threadPath.firstMatch(uri.path);
    if (threadMatch != null) {
      return _parseThread(document, uri, encoding, threadMatch);
    }
    final boardMatch = _boardPath.firstMatch(uri.path);
    if (boardMatch != null) {
      return _parseBoard(document, uri, encoding, boardMatch);
    }
    if (uri.path.isEmpty || uri.path == '/') {
      return _parseHome(document, uri, encoding);
    }
    return _parseFallback(document, uri, encoding);
  }

  ForumDocument _parseHome(Document document, Uri uri, String encoding) {
    final noticeTable =
        document.querySelectorAll('table').where((table) {
          return table.attributes['bgcolor']?.toUpperCase() == '#CCFFCC';
        }).firstOrNull;
    final noticeCells =
        noticeTable?.querySelectorAll('td') ?? const <Element>[];
    final notices = <String>[];
    if (noticeCells.length > 1) {
      final notice = _blockText(noticeCells[1]);
      if (notice.isNotEmpty) notices.add(notice);
    }
    final navCells = noticeTable?.querySelectorAll('th') ?? const <Element>[];
    if (navCells.length > 1) {
      final sessionLabel = _cleanInline(navCells[1].text);
      if (sessionLabel.isNotEmpty) notices.add(sessionLabel);
    }

    final threads = <ForumThreadSummary>[];
    for (final table in document.querySelectorAll('table')) {
      if (table.attributes['bgcolor']?.toUpperCase() != '#EFEFEF' ||
          table.querySelector('dl') == null) {
        continue;
      }
      final anchor = table.querySelector('a[href^="/view/"]');
      if (anchor == null) continue;
      final title = _cleanInline(anchor.text);
      if (title.isEmpty) continue;
      final posts = _parsePosts(table, uri);
      final first = posts.firstOrNull;
      final last = posts.lastOrNull;
      threads.add(
        ForumThreadSummary(
          title: title,
          uri: uri.resolve(anchor.attributes['href']!),
          threadNumber: _threadIdFromHref(anchor.attributes['href']),
          replyCount: last?.numericNumber,
          author: first?.name,
          createdAt: first?.date,
          latestReplyAt: last?.date,
          id: first?.id,
          previewPosts: posts,
        ),
      );
    }

    return ForumDocument(
      uri: uri,
      title: 'AA同好会揭示板',
      kind: ForumPageKind.board,
      site: ForumSite.aaFanclub,
      encoding: encoding,
      textBlocks: notices,
      threads: threads,
    );
  }

  ForumDocument _parseBoard(
    Document document,
    Uri uri,
    String encoding,
    RegExpMatch pathMatch,
  ) {
    final summaries = <ForumThreadSummary>[];
    final list = document.querySelector('dl.thread');
    if (list != null) {
      final headings = list
          .querySelectorAll('div')
          .where(
            (element) =>
                element.querySelector('a[href^="/view/"]') != null &&
                element.text.contains('楼层数'),
          );
      final metadata = list.querySelectorAll('dt');
      var index = 0;
      for (final heading in headings) {
        final anchor = heading.querySelector('a[href^="/view/"]')!;
        final header =
            index < metadata.length ? _parseHeader(metadata[index]) : null;
        final detail = _cleanInline(heading.text);
        final count = RegExp(r'楼层数\s*：\s*(\d+)').firstMatch(detail);
        final latest = RegExp(r'最新回复\s*：\s*([^】]+)').firstMatch(detail);
        summaries.add(
          ForumThreadSummary(
            title: _cleanInline(anchor.text),
            uri: uri.resolve(anchor.attributes['href']!),
            threadNumber:
                header?.number ?? _threadIdFromHref(anchor.attributes['href']),
            replyCount: int.tryParse(count?.group(1) ?? ''),
            author: header?.name,
            createdAt: header?.date,
            latestReplyAt: _nullableClean(latest?.group(1)),
            id: header?.id,
          ),
        );
        index++;
      }
    }

    final currentPage = int.parse(pathMatch.group(2)!);
    final pagination = _boardPagination(document, uri, currentPage);
    final pageCount = pagination
        .map((link) => link.pageNumber ?? 1)
        .fold(currentPage, (highest, page) => page > highest ? page : highest);
    return ForumDocument(
      uri: uri,
      title: _cleanInline(document.querySelector('title')?.text),
      kind: ForumPageKind.board,
      site: ForumSite.aaFanclub,
      encoding: encoding,
      threads: summaries,
      pagination: pagination,
      currentPage: currentPage,
      pageCount: pageCount,
    );
  }

  ForumDocument _parseThread(
    Document document,
    Uri uri,
    String encoding,
    RegExpMatch pathMatch,
  ) {
    final threadId = pathMatch.group(1)!;
    final currentPage = int.tryParse(pathMatch.group(2) ?? '') ?? 1;
    final pagination = _threadPagination(document, uri, threadId, currentPage);
    final pageCount = pagination
        .map((link) => link.pageNumber ?? 1)
        .fold(currentPage, (highest, page) => page > highest ? page : highest);
    final ownerAnchor = document.querySelector('a[href\$="-icchi"]');
    final heading = _cleanInline(document.querySelector('h1')?.text);
    final title =
        heading.isNotEmpty
            ? heading
            : _cleanInline(document.querySelector('title')?.text);

    return ForumDocument(
      uri: uri,
      title: title,
      kind: ForumPageKind.thread,
      site: ForumSite.aaFanclub,
      encoding: encoding,
      posts: _parsePosts(document, uri),
      pagination: pagination,
      currentPage: currentPage,
      pageCount: pageCount,
      threadId: threadId,
      ownerOnlyUri:
          ownerAnchor == null
              ? null
              : uri.resolve(ownerAnchor.attributes['href']!),
    );
  }

  ForumDocument _parseFallback(Document document, Uri uri, String encoding) {
    final title = _cleanInline(document.querySelector('title')?.text);
    final body = document.body == null ? '' : _blockText(document.body!);
    return ForumDocument(
      uri: uri,
      title: title.isEmpty ? 'AA同好会揭示板' : title,
      kind: ForumPageKind.generic,
      site: ForumSite.aaFanclub,
      encoding: encoding,
      textBlocks: body.isEmpty ? const [] : [body],
    );
  }

  List<ForumPost> _parsePosts(Node root, Uri baseUri) {
    final headers = _queryAll(root, 'dt[id^="f"]');
    final bodies = _queryAll(root, 'dd');
    final count =
        headers.length < bodies.length ? headers.length : bodies.length;
    return List.generate(count, (index) {
      final header = _parseHeader(headers[index]);
      final runs = _formattedText(bodies[index], baseUri);
      return ForumPost(
        number: header?.number ?? (index + 1).toString(),
        name: header?.name,
        date: header?.date,
        id: header?.id,
        authorIsTrip:
            headers[index].querySelector('font[color="green"] b') != null,
        body: runs.map((run) => run.text).join(),
        bodyRuns: runs,
      );
    });
  }

  List<Element> _queryAll(Node root, String selector) {
    if (root is Document) return root.querySelectorAll(selector);
    if (root is Element) return root.querySelectorAll(selector);
    return const [];
  }

  _PostHeader? _parseHeader(Element element) {
    final text = _cleanInline(element.text);
    final match = RegExp(
      r'^(\d+)\s*：\s*(.*?)\s*：\s*(\d{4}年\d{2}月\d{2}日\s+\d{2}:\d{2}:\d{2})\s+ID:([^\s]+)',
    ).firstMatch(text);
    if (match == null) return null;
    return _PostHeader(
      number: match.group(1)!,
      name: match.group(2)!.trim(),
      date: match.group(3)!,
      id: match.group(4)!,
    );
  }

  List<ForumLink> _threadPagination(
    Document document,
    Uri uri,
    String threadId,
    int currentPage,
  ) {
    final result = <ForumLink>[
      ForumLink(title: '$currentPage', uri: uri, pageNumber: currentPage),
    ];
    final seen = <int>{currentPage};
    final pattern = RegExp('^/view/$threadId-(\\d+)/?\$');
    for (final anchor in document.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href']!;
      final match = pattern.firstMatch(href);
      final page = int.tryParse(match?.group(1) ?? '');
      if (page == null || !seen.add(page)) continue;
      result.add(
        ForumLink(title: '$page', uri: uri.resolve(href), pageNumber: page),
      );
    }
    result.sort((a, b) => a.pageNumber!.compareTo(b.pageNumber!));
    return result;
  }

  List<ForumLink> _boardPagination(
    Document document,
    Uri uri,
    int currentPage,
  ) {
    final result = <ForumLink>[
      ForumLink(title: '$currentPage', uri: uri, pageNumber: currentPage),
    ];
    final seen = <int>{currentPage};
    for (final anchor in document.querySelectorAll('a[href^="/form-"]')) {
      final href = anchor.attributes['href']!;
      final match = _boardPath.firstMatch(Uri.parse(href).path);
      final page = int.tryParse(match?.group(2) ?? '');
      if (page == null || !seen.add(page)) continue;
      result.add(
        ForumLink(title: '$page', uri: uri.resolve(href), pageNumber: page),
      );
    }
    result.sort((a, b) => a.pageNumber!.compareTo(b.pageNumber!));
    return result;
  }

  List<ForumTextRun> _formattedText(Element element, Uri baseUri) {
    final runs = <ForumTextRun>[];
    for (final node in element.nodes) {
      _writeFormattedNode(node, baseUri, runs, ForumTextTone.normal, false);
    }
    return _mergeRuns(runs);
  }

  void _writeFormattedNode(
    Node node,
    Uri baseUri,
    List<ForumTextRun> output,
    ForumTextTone tone,
    bool bold,
  ) {
    if (node is Text) {
      if (node.data.isNotEmpty) {
        output.add(ForumTextRun(text: node.data, tone: tone, bold: bold));
      }
      return;
    }
    if (node is! Element) return;
    if (node.localName == 'br') {
      output.add(const ForumTextRun(text: '\n'));
      return;
    }
    if (const {'script', 'style', 'noscript', 'svg'}.contains(node.localName)) {
      return;
    }

    var childTone = tone;
    Uri? target;
    if (node.localName == 'a') {
      childTone = ForumTextTone.link;
      final href = node.attributes['href'];
      if (href != null) target = baseUri.resolve(href);
    } else if (node.localName == 'font') {
      final color = node.attributes['color']?.toLowerCase() ?? '';
      if (color.contains('ff0000') || color == 'red') {
        childTone = ForumTextTone.red;
      } else if (color.contains('0000ff') || color == 'blue') {
        childTone = ForumTextTone.blue;
      } else if (color == 'green') {
        childTone = ForumTextTone.green;
      }
    }
    final childBold =
        bold || node.localName == 'b' || node.localName == 'strong';
    final start = output.length;
    for (final child in node.nodes) {
      _writeFormattedNode(child, baseUri, output, childTone, childBold);
    }
    if (target != null) {
      for (var index = start; index < output.length; index++) {
        final run = output[index];
        output[index] = ForumTextRun(
          text: run.text,
          tone: run.tone,
          bold: run.bold,
          uri: target,
        );
      }
    }
  }

  List<ForumTextRun> _mergeRuns(List<ForumTextRun> input) {
    final result = <ForumTextRun>[];
    for (final run in input) {
      if (run.text.isEmpty) continue;
      if (result.isNotEmpty) {
        final previous = result.last;
        if (previous.tone == run.tone &&
            previous.bold == run.bold &&
            previous.uri == run.uri) {
          result[result.length - 1] = ForumTextRun(
            text: previous.text + run.text,
            tone: run.tone,
            bold: run.bold,
            uri: run.uri,
          );
          continue;
        }
      }
      result.add(run);
    }
    return result;
  }

  String _blockText(Element element) {
    final buffer = StringBuffer();
    void visit(Node node) {
      if (node is Text) {
        buffer.write(node.data);
      } else if (node is Element) {
        if (node.localName == 'br') {
          buffer.write('\n');
        } else if (!const {
          'script',
          'style',
          'noscript',
        }.contains(node.localName)) {
          for (final child in node.nodes) {
            visit(child);
          }
          if (const {'div', 'p', 'tr', 'li'}.contains(node.localName)) {
            buffer.write('\n');
          }
        }
      }
    }

    visit(element);
    return buffer
        .toString()
        .replaceAll('\r', '')
        .replaceAll(RegExp(r'\n{3,}'), '\n\n')
        .trim();
  }

  String? _threadIdFromHref(String? href) {
    if (href == null) return null;
    return _threadPath.firstMatch(Uri.parse(href).path)?.group(1);
  }

  String _cleanInline(String? value) =>
      (value ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

  String? _nullableClean(String? value) {
    final cleaned = _cleanInline(value);
    return cleaned.isEmpty ? null : cleaned;
  }
}

class _PostHeader {
  const _PostHeader({
    required this.number,
    required this.name,
    required this.date,
    required this.id,
  });

  final String number;
  final String name;
  final String date;
  final String id;
}
