import '../domain/forum_document.dart';

abstract interface class SiteAdapter {
  bool supports(Uri uri);

  ForumDocument parse({
    required String source,
    required Uri uri,
    required String encoding,
  });
}
