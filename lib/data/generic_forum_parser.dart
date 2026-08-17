import 'package:html/dom.dart';
import 'package:html/parser.dart' as html_parser;

import '../domain/forum_document.dart';
import 'site_adapter.dart';

class GenericForumParser implements SiteAdapter {
  const GenericForumParser();

  @override
  bool supports(Uri uri) => true;

  @override
  ForumDocument parse({
    required String source,
    required Uri uri,
    required String encoding,
  }) {
    final document = html_parser.parse(source);
    final title = _pageTitle(document, uri);
    final posts = _parsePosts(document);
    final links = _parseForumLinks(document, uri);
    final kind =
        posts.isNotEmpty
            ? ForumPageKind.thread
            : links.isNotEmpty
            ? ForumPageKind.board
            : ForumPageKind.generic;

    return ForumDocument(
      uri: uri,
      title: title,
      kind: kind,
      encoding: encoding,
      posts: posts,
      links: links,
      textBlocks:
          kind == ForumPageKind.generic ? _parseTextBlocks(document) : const [],
    );
  }

  String _pageTitle(Document document, Uri uri) {
    final heading = _cleanInline(document.querySelector('h1')?.text);
    final title = _cleanInline(document.querySelector('title')?.text);
    if (heading.isNotEmpty) return heading;
    if (title.isNotEmpty) return title;
    return uri.host;
  }

  List<ForumPost> _parsePosts(Document document) {
    final definitionPosts = _parseDefinitionListPosts(document);
    if (definitionPosts.isNotEmpty) return definitionPosts;

    const candidateSelectors = [
      '[data-post-id]',
      '.post',
      '.reply',
      '.res',
      'article',
    ];
    for (final selector in candidateSelectors) {
      final candidates = _topLevelMatches(document.querySelectorAll(selector));
      final posts = <ForumPost>[];
      for (var index = 0; index < candidates.length; index++) {
        final post = _elementToPost(candidates[index], index + 1);
        if (post.body.isNotEmpty) posts.add(post);
      }
      if (posts.isNotEmpty) return posts;
    }
    return const [];
  }

  List<ForumPost> _parseDefinitionListPosts(Document document) {
    final result = <ForumPost>[];
    for (final list in document.querySelectorAll('dl')) {
      Element? header;
      for (final child in list.children) {
        if (child.localName == 'dt') {
          header = child;
        } else if (child.localName == 'dd' && header != null) {
          final body = _blockText(child);
          if (body.isNotEmpty) {
            result.add(_makePost(header, child, result.length + 1));
          }
          header = null;
        }
      }
    }
    return result;
  }

  List<Element> _topLevelMatches(List<Element> elements) {
    final set = elements.toSet();
    return elements
        .where((element) {
          Element? ancestor = element.parent;
          while (ancestor != null) {
            if (set.contains(ancestor)) return false;
            ancestor = ancestor.parent;
          }
          return true;
        })
        .toList(growable: false);
  }

  ForumPost _elementToPost(Element element, int fallbackNumber) {
    final bodyElement =
        _firstMatch(element, const [
          '.post-body',
          '.message',
          '.body',
          '.content',
          'blockquote',
          'pre',
        ]) ??
        element;
    return _makePost(element, bodyElement, fallbackNumber);
  }

  ForumPost _makePost(Element header, Element body, int fallbackNumber) {
    final headerText = _cleanInline(header.text);
    final number =
        header.attributes['data-post-id'] ??
        _firstText(header, const ['.post-number', '.number', '.no']) ??
        RegExp(
          r'(?:^|\s)(\d{1,7})(?=\s|[：:]|$)',
        ).firstMatch(headerText)?.group(1) ??
        fallbackNumber.toString();
    final name =
        _firstText(header, const ['.poster-name', '.author', '.name']) ??
        RegExp(
          r'(?:名前|Name)\s*[：:]\s*([^\s]+)',
          caseSensitive: false,
        ).firstMatch(headerText)?.group(1);
    final date =
        _firstText(header, const [
          '.posted-at',
          '.datetime',
          '.date',
          '.time',
        ]) ??
        RegExp(
          r'\d{2,4}[/-]\d{1,2}[/-]\d{1,2}(?:\([^)]*\))?\s+\d{1,2}:\d{2}(?::\d{2})?',
        ).firstMatch(headerText)?.group(0);
    final id = RegExp(
      r'ID\s*[：:]\s*([A-Za-z0-9+/_-]+)',
      caseSensitive: false,
    ).firstMatch(headerText)?.group(1);

    return ForumPost(
      number: _cleanInline(number),
      name: _nullableClean(name),
      date: _nullableClean(date),
      id: _nullableClean(id),
      body: _blockText(body),
    );
  }

  Element? _firstMatch(Element root, List<String> selectors) {
    for (final selector in selectors) {
      final match = root.querySelector(selector);
      if (match != null) return match;
    }
    return null;
  }

  String? _firstText(Element root, List<String> selectors) {
    final match = _firstMatch(root, selectors);
    if (match == null) return null;
    final value = _cleanInline(match.text);
    return value.isEmpty ? null : value;
  }

  List<ForumLink> _parseForumLinks(Document document, Uri baseUri) {
    final result = <ForumLink>[];
    final seen = <String>{};
    for (final anchor in document.querySelectorAll('a[href]')) {
      final href = anchor.attributes['href']?.trim();
      if (href == null || href.isEmpty || href.startsWith('#')) continue;

      late Uri target;
      try {
        target = baseUri.resolve(href);
      } on FormatException {
        continue;
      }
      if ((target.scheme != 'http' && target.scheme != 'https') ||
          target.host != baseUri.host) {
        continue;
      }

      final label = _cleanInline(anchor.text);
      if (label.isEmpty || !_looksLikeForumLink(target, label)) continue;
      final normalized = target.removeFragment().toString();
      if (!seen.add(normalized)) continue;
      final countMatch = RegExp(
        r'[\(（\[]\s*(\d{1,6})\s*[\)）\]]',
      ).firstMatch(label);
      result.add(
        ForumLink(
          title: label,
          uri: Uri.parse(normalized),
          replyCount: int.tryParse(countMatch?.group(1) ?? ''),
        ),
      );
      if (result.length == 300) break;
    }
    return result;
  }

  bool _looksLikeForumLink(Uri uri, String label) {
    final address = uri.toString().toLowerCase();
    return RegExp(
          r'(?:/test)?/read\.cgi|/thread(?:s)?/|/topic(?:s)?/|/bbs/',
        ).hasMatch(address) ||
        uri.queryParameters.keys.any(
          (key) => const {
            'thread',
            'thread_id',
            'tid',
            'key',
            'res',
          }.contains(key.toLowerCase()),
        ) ||
        RegExp(r'[\(（\[]\s*\d{1,6}\s*[\)）\]]\s*$').hasMatch(label);
  }

  List<String> _parseTextBlocks(Document document) {
    final root = document.querySelector('main') ?? document.body;
    if (root == null) return const [];
    final blocks = <String>[];
    final seen = <String>{};
    for (final element in root.querySelectorAll(
      'h1,h2,h3,p,pre,blockquote,li',
    )) {
      final value = _blockText(element);
      if (value.isNotEmpty && seen.add(value)) blocks.add(value);
      if (blocks.length == 200) break;
    }
    if (blocks.isEmpty) {
      final value = _blockText(root);
      if (value.isNotEmpty) blocks.add(value);
    }
    return blocks;
  }

  String _blockText(Element element) {
    final buffer = StringBuffer();
    _writeNode(element, buffer);
    final lines =
        buffer
            .toString()
            .replaceAll('\r', '')
            .replaceAll('\u00a0', ' ')
            .split('\n')
            .map((line) => line.replaceFirst(RegExp(r'[ \t]+$'), ''))
            .toList();
    while (lines.isNotEmpty && lines.first.trim().isEmpty) {
      lines.removeAt(0);
    }
    while (lines.isNotEmpty && lines.last.trim().isEmpty) {
      lines.removeLast();
    }
    return lines.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n');
  }

  void _writeNode(Node node, StringBuffer buffer) {
    if (node is Text) {
      buffer.write(node.data);
      return;
    }
    if (node is! Element) return;
    const ignored = {'script', 'style', 'noscript', 'template', 'svg'};
    if (ignored.contains(node.localName)) return;
    if (node.localName == 'br') {
      buffer.write('\n');
      return;
    }
    if (node.localName == 'img') {
      buffer.write(node.attributes['alt'] ?? '');
      return;
    }
    for (final child in node.nodes) {
      _writeNode(child, buffer);
    }
    const blockElements = {
      'address',
      'article',
      'aside',
      'blockquote',
      'dd',
      'div',
      'dt',
      'figcaption',
      'footer',
      'h1',
      'h2',
      'h3',
      'h4',
      'h5',
      'h6',
      'header',
      'li',
      'main',
      'p',
      'pre',
      'section',
      'tr',
    };
    if (blockElements.contains(node.localName) &&
        buffer.isNotEmpty &&
        !buffer.toString().endsWith('\n')) {
      buffer.write('\n');
    }
  }

  String _cleanInline(String? value) =>
      (value ?? '').replaceAll(RegExp(r'\s+'), ' ').trim();

  String? _nullableClean(String? value) {
    final cleaned = _cleanInline(value);
    return cleaned.isEmpty ? null : cleaned;
  }
}
