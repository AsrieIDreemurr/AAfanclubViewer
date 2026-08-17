import '../domain/forum_document.dart';
import 'aafanclub_adapter.dart';
import 'generic_forum_parser.dart';
import 'page_decoder.dart';
import 'page_source.dart';
import 'site_adapter.dart';
import 'thread_page_cache.dart';

abstract class ForumRepository {
  Future<ForumDocument> load(Uri uri);

  Future<ForumDocument> refresh(ForumDocument current) => load(current.uri);

  Future<ForumDocument> login(
    ForumDocument current, {
    required String name,
    required String trip,
  }) => throw UnsupportedError('此数据源不支持登录');

  Future<ForumDocument> reply(
    ForumDocument current, {
    required String content,
  }) => throw UnsupportedError('此数据源不支持回复');

  Future<ForumDocument> createThread(
    ForumDocument current, {
    required String title,
    required String content,
  }) => throw UnsupportedError('此数据源不支持新建帖子');

  Future<int> clearCache() async => 0;
}

class NetworkForumRepository implements ForumRepository {
  NetworkForumRepository({
    NetworkPageSource? source,
    ThreadPageCache? cache,
    this.decoder = const PageDecoder(),
    List<SiteAdapter>? adapters,
  }) : source = source ?? NetworkPageSource(),
       cache = cache ?? ThreadPageCache(),
       adapters = adapters ?? const [AaFanclubAdapter(), GenericForumParser()];

  final NetworkPageSource source;
  final ThreadPageCache cache;
  final PageDecoder decoder;
  final List<SiteAdapter> adapters;

  @override
  Future<ForumDocument> load(Uri uri) async {
    return _loadOnce(uri);
  }

  @override
  Future<ForumDocument> refresh(ForumDocument current) async {
    if (current.kind != ForumPageKind.thread ||
        current.site != ForumSite.aaFanclub) {
      return _loadOnce(current.uri);
    }

    final refreshedPage = await _loadOnce(current.uri, useCache: false);
    final collected = <ForumPost>[...current.posts];
    final knownNumbers = current.posts.map((post) => post.number).toSet();
    _appendUnknownPosts(collected, knownNumbers, refreshedPage.posts);

    final oldLastPage = current.pageCount ?? current.currentPage ?? 1;
    final newLastPage = refreshedPage.pageCount ?? oldLastPage;
    final wasViewingLastPage = current.currentPage == oldLastPage;
    if (wasViewingLastPage &&
        newLastPage > oldLastPage &&
        current.threadId != null) {
      for (var page = oldLastPage + 1; page <= newLastPage; page++) {
        final pageUri = current.uri.replace(
          path: '/view/${current.threadId}-$page',
          query: null,
          fragment: null,
        );
        final nextPage = await _loadOnce(pageUri, useCache: false);
        _appendUnknownPosts(collected, knownNumbers, nextPage.posts);
      }
    }

    return refreshedPage.copyWith(
      uri: current.uri,
      posts: collected,
      currentPage: current.currentPage,
    );
  }

  @override
  Future<ForumDocument> login(
    ForumDocument current, {
    required String name,
    required String trip,
  }) async {
    final root = current.uri.replace(path: '/', query: null, fragment: null);
    await source.submitForm(root.resolve('/login/setting/'), {
      'NAME': name,
      'TRIP': trip,
    }, referer: root.resolve('/login/'));
    return _loadOnce(current.uri, useCache: false);
  }

  @override
  Future<ForumDocument> reply(
    ForumDocument current, {
    required String content,
  }) async {
    final threadId = current.threadId;
    if (current.kind != ForumPageKind.thread || threadId == null) {
      throw const PageSourceException('当前页面不是帖子，无法回复');
    }
    await source.submitForm(current.uri.resolve('/post/$threadId'), {
      'CONTENT': content,
    }, referer: current.uri);
    return refresh(current);
  }

  @override
  Future<ForumDocument> createThread(
    ForumDocument current, {
    required String title,
    required String content,
  }) async {
    final result = await source.submitForm(current.uri.resolve('/new/'), {
      'TITLE': title,
      'CONTENT': content,
    }, referer: current.uri.resolve('/newthread/'));
    final decoded = decoder.decode(result.bytes, result.headers);
    final adapter = adapters.firstWhere((item) => item.supports(result.uri));
    final parsed = adapter.parse(
      source: decoded.text,
      uri: result.uri,
      encoding: decoded.encoding,
    );
    if (parsed.kind == ForumPageKind.thread) {
      await cache.write(result.uri, result);
      return parsed;
    }
    return _loadOnce(current.uri.resolve('/'));
  }

  @override
  Future<int> clearCache() => cache.clear();

  Future<ForumDocument> _loadOnce(Uri uri, {bool useCache = true}) async {
    final cached = useCache ? await cache.read(uri) : null;
    final page = cached ?? await source.load(uri);
    if (cached == null) await cache.write(uri, page);
    final decoded = decoder.decode(page.bytes, page.headers);
    final adapter = adapters.firstWhere((item) => item.supports(page.uri));
    return adapter.parse(
      source: decoded.text,
      uri: page.uri,
      encoding: decoded.encoding,
    );
  }

  void _appendUnknownPosts(
    List<ForumPost> target,
    Set<String> knownNumbers,
    Iterable<ForumPost> candidates,
  ) {
    for (final post in candidates) {
      if (knownNumbers.add(post.number)) target.add(post);
    }
    target.sort((a, b) {
      final left = a.numericNumber;
      final right = b.numericNumber;
      if (left == null || right == null) return 0;
      return left.compareTo(right);
    });
  }
}
