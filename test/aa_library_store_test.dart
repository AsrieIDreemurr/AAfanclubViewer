import 'package:aafanclub_viewer/application/aa_library_store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('persists page-grouped favorites and page browsing history', () async {
    final item = AaSavedItem(
      id: 'file:3',
      fileHash: 'file',
      fileName: '作品.mlt',
      directory: '/あ行',
      index: 3,
      text: ' /\\n/  \\\\ ',
      savedAt: DateTime(2026, 8, 18),
    );
    final first = AaLibraryStore();
    await first.load();
    final page = AaSavedPage.fromItem(item);
    first.toggleAaFavorite(item);
    first.togglePageFavorite(page);
    first.addPageHistory(page);
    await Future<void>.delayed(Duration.zero);

    final restored = AaLibraryStore();
    await restored.load();
    expect(restored.favoriteAas.single.text, item.text);
    expect(restored.favoritePages.single.fileHash, item.fileHash);
    expect(restored.favoritePageGroups.single.fileHash, item.fileHash);
    expect(restored.pageHistory.single.fileHash, item.fileHash);

    restored.clearFavorites();
    restored.clearHistory();
    expect(restored.favoriteAas, isEmpty);
    expect(restored.favoritePages, isEmpty);
    expect(restored.favoritePageGroups, isEmpty);
    expect(restored.pageHistory, isEmpty);
  });

  test('migrates the old single-AA history into page history', () async {
    SharedPreferences.setMockInitialValues({
      'aa.library.history.v1':
          '[{"id":"file:3","fileHash":"file","fileName":"作品.mlt",'
          '"directory":"/あ行","index":3,"text":"AA",'
          '"savedAt":"2026-08-18T00:00:00.000"}]',
    });

    final store = AaLibraryStore();
    await store.load();

    expect(store.pageHistory.single.fileHash, 'file');
    expect(store.pageHistory.single.fileName, '作品.mlt');
  });
}
