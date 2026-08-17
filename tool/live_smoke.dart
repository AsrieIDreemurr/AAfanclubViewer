import 'package:aafanclub_viewer/data/forum_repository.dart';
import 'package:aafanclub_viewer/domain/forum_document.dart';

Future<void> main() async {
  final repository = NetworkForumRepository();
  try {
    final home = await repository.load(Uri.parse('http://aafanclub.com/'));
    if (home.site != ForumSite.aaFanclub || home.threads.isEmpty) {
      throw StateError('Homepage did not produce AA Fanclub thread summaries.');
    }
    final firstThread = await repository.load(home.threads.first.uri);
    if (firstThread.kind != ForumPageKind.thread || firstThread.posts.isEmpty) {
      throw StateError('First thread did not produce forum posts.');
    }
    // ignore: avoid_print
    print(
      'Live smoke passed: ${home.threads.length} homepage threads; '
      '${firstThread.posts.length} posts on ${firstThread.uri.path}; '
      '${firstThread.pageCount ?? 1} pages.',
    );
  } finally {
    repository.source.close();
  }
}
