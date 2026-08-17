enum ForumPageKind { board, thread, generic }

enum ForumSite { generic, aaFanclub }

enum ForumTextTone { normal, link, red, blue, green }

class ForumDocument {
  const ForumDocument({
    required this.uri,
    required this.title,
    required this.kind,
    required this.encoding,
    this.site = ForumSite.generic,
    this.posts = const [],
    this.links = const [],
    this.textBlocks = const [],
    this.threads = const [],
    this.pagination = const [],
    this.currentPage,
    this.pageCount,
    this.threadId,
    this.ownerOnlyUri,
  });

  final Uri uri;
  final String title;
  final ForumPageKind kind;
  final String encoding;
  final ForumSite site;
  final List<ForumPost> posts;
  final List<ForumLink> links;
  final List<String> textBlocks;
  final List<ForumThreadSummary> threads;
  final List<ForumLink> pagination;
  final int? currentPage;
  final int? pageCount;
  final String? threadId;
  final Uri? ownerOnlyUri;

  ForumDocument copyWith({
    Uri? uri,
    String? title,
    ForumPageKind? kind,
    String? encoding,
    ForumSite? site,
    List<ForumPost>? posts,
    List<ForumLink>? links,
    List<String>? textBlocks,
    List<ForumThreadSummary>? threads,
    List<ForumLink>? pagination,
    int? currentPage,
    int? pageCount,
    String? threadId,
    Uri? ownerOnlyUri,
  }) => ForumDocument(
    uri: uri ?? this.uri,
    title: title ?? this.title,
    kind: kind ?? this.kind,
    encoding: encoding ?? this.encoding,
    site: site ?? this.site,
    posts: posts ?? this.posts,
    links: links ?? this.links,
    textBlocks: textBlocks ?? this.textBlocks,
    threads: threads ?? this.threads,
    pagination: pagination ?? this.pagination,
    currentPage: currentPage ?? this.currentPage,
    pageCount: pageCount ?? this.pageCount,
    threadId: threadId ?? this.threadId,
    ownerOnlyUri: ownerOnlyUri ?? this.ownerOnlyUri,
  );
}

class ForumPost {
  const ForumPost({
    required this.number,
    required this.body,
    this.name,
    this.date,
    this.id,
    this.authorIsTrip = false,
    this.bodyRuns = const [],
  });

  final String number;
  final String body;
  final String? name;
  final String? date;
  final String? id;
  final bool authorIsTrip;
  final List<ForumTextRun> bodyRuns;

  int? get numericNumber => int.tryParse(number);
}

class ForumTextRun {
  const ForumTextRun({
    required this.text,
    this.tone = ForumTextTone.normal,
    this.bold = false,
    this.uri,
  });

  final String text;
  final ForumTextTone tone;
  final bool bold;
  final Uri? uri;
}

class ForumThreadSummary {
  const ForumThreadSummary({
    required this.title,
    required this.uri,
    this.threadNumber,
    this.replyCount,
    this.author,
    this.createdAt,
    this.latestReplyAt,
    this.id,
    this.previewPosts = const [],
  });

  final String title;
  final Uri uri;
  final String? threadNumber;
  final int? replyCount;
  final String? author;
  final String? createdAt;
  final String? latestReplyAt;
  final String? id;
  final List<ForumPost> previewPosts;
}

class ForumLink {
  const ForumLink({
    required this.title,
    required this.uri,
    this.replyCount,
    this.pageNumber,
  });

  final String title;
  final Uri uri;
  final int? replyCount;
  final int? pageNumber;
}
