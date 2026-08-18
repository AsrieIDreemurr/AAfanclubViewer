import 'package:aafanclub_viewer/application/aa_library_store.dart';
import 'package:aafanclub_viewer/data/aa_library_client.dart';
import 'package:aafanclub_viewer/ui/aa_picker_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _FakeAaLibraryClient extends AaLibraryClient {
  final file = const AaSourceNode(
    directory: '/あ行',
    filename: '作品.mlt',
    hash: 'file-1',
    filesize: 100,
    isFile: true,
  );

  @override
  Future<List<AaSourceNode>> loadTree() async {
    return [
      AaSourceNode(
        directory: '',
        filename: 'あ行',
        hash: 'folder-1',
        filesize: 0,
        isFile: false,
        children: [file],
      ),
    ];
  }

  @override
  Future<AaSourceFile> loadFile(AaSourceNode node) async {
    return const AaSourceFile(
      directory: '/あ行',
      filename: '作品.mlt',
      filesize: 100,
      contents: ['【基本】', '  /\\\n ( ･ω･)'],
    );
  }

  @override
  void close() {}
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('the path above a file walks back to its folders', (
    tester,
  ) async {
    final store = AaLibraryStore();
    await tester.pumpWidget(
      MaterialApp(
        home: AaPickerPage(client: _FakeAaLibraryClient(), store: store),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('aa-node-folder-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('aa-node-file-1')));
    await tester.pumpAndSettle();

    // Viewing a file: the trail is AA目录 / あ行 / 作品.
    expect(find.byKey(const Key('aa-crumb-current-file')), findsOneWidget);
    final folderCrumb = find.byKey(const ValueKey('aa-crumb-folder-1'));
    expect(folderCrumb, findsOneWidget);

    await tester.tap(folderCrumb);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('aa-node-file-1')), findsOneWidget);
    expect(find.byKey(const Key('aa-crumb-current-file')), findsNothing);

    await tester.tap(find.byKey(const Key('aa-crumb-root')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('aa-node-folder-1')), findsOneWidget);
  });

  testWidgets('the path works for a file opened without walking the tree', (
    tester,
  ) async {
    final store = AaLibraryStore();
    await tester.pumpWidget(
      MaterialApp(
        home: AaPickerPage(client: _FakeAaLibraryClient(), store: store),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('aa-search-field')));
    await tester.enterText(find.byKey(const Key('aa-search-field')), '作品');
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: find.byKey(const Key('aa-search-results')),
        matching: find.text('作品'),
      ),
    );
    await tester.pumpAndSettle();

    // Reached by search, so the folder stack was never built — the crumb has
    // to come from the file's own directory string.
    await tester.tap(find.byKey(const ValueKey('aa-crumb-folder-1')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('aa-node-file-1')), findsOneWidget);
  });

  testWidgets('folders can be favorited and reopened from the favorites view', (
    tester,
  ) async {
    final store = AaLibraryStore();
    await tester.pumpWidget(
      MaterialApp(
        home: AaPickerPage(client: _FakeAaLibraryClient(), store: store),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('aa-folder-star-folder-1')));
    await tester.pumpAndSettle();
    expect(store.isFolderFavorite('folder-1'), isTrue);

    tester
        .state<ScaffoldState>(find.byKey(const Key('aa-picker-page')))
        .openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('aa-menu-favorites')));
    await tester.pumpAndSettle();
    final favorite = find.byKey(const ValueKey('aa-favorite-folder-folder-1'));
    expect(favorite, findsOneWidget);

    // Opening it walks back into the live tree, showing the folder's files.
    await tester.tap(favorite);
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('aa-node-file-1')), findsOneWidget);
  });

  testWidgets('reopening the picker jumps straight to the last file', (
    tester,
  ) async {
    final store = AaLibraryStore();
    await tester.pumpWidget(
      MaterialApp(
        home: AaPickerPage(client: _FakeAaLibraryClient(), store: store),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('aa-node-folder-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('aa-node-file-1')));
    await tester.pumpAndSettle();
    expect(store.pageHistory.first.fileHash, 'file-1');

    // A fresh picker over the same store lands on that file, not the root.
    await tester.pumpWidget(
      MaterialApp(
        home: AaPickerPage(client: _FakeAaLibraryClient(), store: store),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.textContaining('作品'), findsWidgets);
    expect(find.byKey(const ValueKey('aa-node-folder-1')), findsNothing);
  });

  testWidgets('groups AA favorites by page and records page history', (
    tester,
  ) async {
    final store = AaLibraryStore();
    await tester.pumpWidget(
      MaterialApp(
        home: AaPickerPage(client: _FakeAaLibraryClient(), store: store),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('aa-node-folder-1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('aa-node-file-1')));
    await tester.pumpAndSettle();

    expect(find.byKey(const Key('aa-grid')), findsOneWidget);
    expect(store.pageHistory.single.fileHash, 'file-1');
    await tester.tap(find.byKey(const ValueKey('aa-page-favorite-file-1')));
    await tester.pump();
    expect(store.favoritePages.single.fileHash, 'file-1');
    const id = 'file-1:1';
    await tester.tap(find.byKey(const ValueKey('aa-favorite-$id')));
    await tester.pump();
    expect(store.favoriteAas.single.id, id);

    final scaffold = tester.state<ScaffoldState>(
      find.byKey(const Key('aa-picker-page')),
    );
    scaffold.openDrawer();
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('aa-menu-favorites')), findsOneWidget);
    expect(find.byKey(const Key('aa-menu-history')), findsOneWidget);

    await tester.tap(find.byKey(const Key('aa-menu-favorites')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey('aa-favorite-page-file-1')),
      findsOneWidget,
    );
    expect(find.byKey(const ValueKey('aa-card-$id')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('aa-select-$id')));
    await tester.pump();
    expect(store.pageHistory.single.fileHash, 'file-1');
  });

  testWidgets('allows favoriting a page without favoriting an AA', (
    tester,
  ) async {
    final store = AaLibraryStore();
    await tester.pumpWidget(
      MaterialApp(
        home: AaPickerPage(client: _FakeAaLibraryClient(), store: store),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('aa-node-folder-1')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('aa-node-file-1')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('aa-page-favorite-file-1')));
    await tester.pump();

    final scaffold = tester.state<ScaffoldState>(
      find.byKey(const Key('aa-picker-page')),
    );
    scaffold.openDrawer();
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('aa-menu-favorites')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('aa-favorite-page-file-1')),
      findsOneWidget,
    );
    expect(find.text('已收藏页面；本页面尚未收藏具体 AA'), findsOneWidget);
  });
}
