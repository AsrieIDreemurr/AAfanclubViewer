import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../application/aa_library_store.dart';
import '../data/aa_library_client.dart';
import 'aa_text.dart';

enum _AaPickerView { browse, favorites, history }

class AaPickerPage extends StatefulWidget {
  const AaPickerPage({this.client, this.store, super.key});

  final AaLibraryClient? client;
  final AaLibraryStore? store;

  @override
  State<AaPickerPage> createState() => _AaPickerPageState();
}

class _AaPickerPageState extends State<AaPickerPage> {
  late final AaLibraryClient _client;
  late final AaLibraryStore _store;
  late final bool _ownsClient;
  late final bool _ownsStore;
  final _search = TextEditingController();

  List<AaSourceNode> _tree = const [];
  List<AaSourceNode> _allFiles = const [];
  final List<AaSourceNode> _folderStack = [];
  AaSourceNode? _selectedFile;
  List<_AaEntry> _fileEntries = const [];
  _AaPickerView _view = _AaPickerView.browse;
  bool _loadingTree = true;
  bool _loadingFile = false;
  String? _treeError;
  String? _fileError;

  @override
  void initState() {
    super.initState();
    _ownsClient = widget.client == null;
    _ownsStore = widget.store == null;
    _client = widget.client ?? AaLibraryClient();
    _store = widget.store ?? AaLibraryStore();
    _store.addListener(_onStoreChanged);
    _search.addListener(_onSearchChanged);
    unawaited(_loadInitialData());
  }

  @override
  void dispose() {
    _search
      ..removeListener(_onSearchChanged)
      ..dispose();
    _store.removeListener(_onStoreChanged);
    if (_ownsStore) _store.dispose();
    if (_ownsClient) _client.close();
    super.dispose();
  }

  Future<void> _loadInitialData() async {
    await _store.load();
    try {
      final tree = await _client.loadTree();
      if (!mounted) return;
      setState(() {
        _tree = tree;
        _allFiles = List.unmodifiable(_flattenFiles(tree));
        _loadingTree = false;
        _treeError = null;
      });
      // Pick up where the last visit left off instead of at the tree root.
      final last = _store.pageHistory.firstOrNull;
      if (last != null) unawaited(_openFile(last.toSourceNode()));
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _loadingTree = false;
        _treeError = error.toString();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canLeavePicker =
        _search.text.isEmpty &&
        _view == _AaPickerView.browse &&
        _selectedFile == null &&
        _folderStack.isEmpty;
    return PopScope(
      canPop: canLeavePicker,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop) _goBackInsidePicker();
      },
      child: Scaffold(
        key: const Key('aa-picker-page'),
        backgroundColor: const Color(0xfff5f5f5),
        appBar: AppBar(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          surfaceTintColor: Colors.white,
          titleSpacing: 0,
          title: Container(
            height: 42,
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: const Color(0xffeeeeee),
              borderRadius: BorderRadius.circular(12),
            ),
            child: TextField(
              key: const Key('aa-search-field'),
              controller: _search,
              textInputAction: TextInputAction.search,
              decoration: const InputDecoration(
                hintText: '搜索作品名或角色名',
                prefixIcon: Icon(Icons.search),
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.symmetric(vertical: 11),
              ),
            ),
          ),
          actions: [
            if (_view == _AaPickerView.favorites ||
                _view == _AaPickerView.history)
              TextButton(
                key: const Key('clear-aa-list'),
                onPressed: _confirmClearCurrentList,
                child: const Text('清除'),
              ),
          ],
        ),
        drawer: _buildDrawer(),
        body: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _buildLocationBar(),
            const Divider(height: 1, color: Color(0xffcccccc)),
            Expanded(child: _buildBody()),
          ],
        ),
      ),
    );
  }

  Widget _buildDrawer() {
    return Drawer(
      width: MediaQuery.sizeOf(context).width * 0.76,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(),
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 64,
              child: Row(
                children: [
                  const Expanded(
                    child: Padding(
                      padding: EdgeInsets.only(left: 18),
                      child: Text('AA菜单', style: TextStyle(fontSize: 22)),
                    ),
                  ),
                  IconButton(
                    key: const Key('close-aa-menu'),
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, size: 28),
                  ),
                  const SizedBox(width: 8),
                ],
              ),
            ),
            const Divider(height: 1),
            if (_loadingTree)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else
              Expanded(
                child: ListView(
                  padding: EdgeInsets.zero,
                  children: [
                    for (final node in _tree)
                      ListTile(
                        key: ValueKey('aa-menu-${node.hash}'),
                        leading: Icon(
                          node.isFile
                              ? Icons.description_outlined
                              : Icons.folder,
                          color: Colors.black,
                        ),
                        title: Text(
                          node.displayName,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing:
                            node.isFile
                                ? null
                                : const Icon(Icons.chevron_right),
                        onTap: () => _selectDrawerNode(node),
                      ),
                    const Divider(height: 1),
                    ListTile(
                      key: const Key('aa-menu-favorites'),
                      leading: const Icon(Icons.star_border),
                      title: Text('收藏（${_store.favoritePageGroups.length}）'),
                      onTap: () => _openSavedView(_AaPickerView.favorites),
                    ),
                    ListTile(
                      key: const Key('aa-menu-history'),
                      leading: const Icon(Icons.history),
                      title: Text('历史（${_store.pageHistory.length}）'),
                      onTap: () => _openSavedView(_AaPickerView.history),
                    ),
                  ],
                ),
              ),
            const Padding(
              padding: EdgeInsets.all(12),
              child: Text(
                'AA来源：aa.yaruyomi.com',
                style: TextStyle(color: Color(0xff777777), fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLocationBar() {
    final showBack =
        _search.text.isNotEmpty ||
        _view != _AaPickerView.browse ||
        _selectedFile != null ||
        _folderStack.isNotEmpty;
    return SizedBox(
      height: 48,
      child: Row(
        children: [
          if (showBack)
            IconButton(
              key: const Key('aa-picker-back'),
              onPressed: _goBackInsidePicker,
              icon: const Icon(Icons.arrow_back),
            )
          else
            const SizedBox(width: 12),
          Expanded(child: _buildBreadcrumbs()),
          if (_view == _AaPickerView.browse && _selectedFile != null)
            IconButton(
              key: ValueKey('aa-page-favorite-${_selectedFile!.hash}'),
              tooltip:
                  _store.isPageFavorite(_selectedFile!.hash)
                      ? '取消收藏页面'
                      : '收藏页面',
              onPressed: () {
                _store.togglePageFavorite(
                  AaSavedPage.fromSource(_selectedFile!),
                );
              },
              icon: Icon(
                _store.isPageFavorite(_selectedFile!.hash)
                    ? Icons.star
                    : Icons.star_border,
                color:
                    _store.isPageFavorite(_selectedFile!.hash)
                        ? const Color(0xffffa000)
                        : Colors.black,
              ),
            )
          else
            const SizedBox(width: 10),
        ],
      ),
    );
  }

  /// The location turned into a `/`-separated trail. Every folder in it jumps
  /// to that level, including when the file was reached from history, a
  /// favorite or a search result and the browser never walked the tree.
  Widget _buildBreadcrumbs() {
    if (_view != _AaPickerView.browse) {
      return Text(
        _view == _AaPickerView.favorites ? '收藏' : '历史',
        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
      );
    }

    const style = TextStyle(fontSize: 16, fontWeight: FontWeight.bold);
    const linkStyle = TextStyle(
      fontSize: 16,
      fontWeight: FontWeight.bold,
      color: Color(0xff0b57d0),
    );
    final crumbs = <Widget>[
      InkWell(
        key: const Key('aa-crumb-root'),
        onTap: () => _openFolderPath(const []),
        child: const Padding(
          padding: EdgeInsets.symmetric(horizontal: 4, vertical: 8),
          child: Text('AA目录', style: linkStyle),
        ),
      ),
    ];

    void addFolder(AaSourceNode folder) {
      crumbs
        ..add(const Text('/', style: style))
        ..add(
          InkWell(
            key: ValueKey('aa-crumb-${folder.hash}'),
            onTap: () => _openFolderNode(folder),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Text(folder.filename, style: linkStyle),
            ),
          ),
        );
    }

    final file = _selectedFile;
    if (file == null) {
      for (final folder in _folderStack) {
        addFolder(folder);
      }
    } else {
      var path = '';
      for (final part in file.directory.split('/')) {
        if (part.isEmpty) continue;
        path = '$path/$part';
        final folder = _folderForPath(path);
        if (folder == null) {
          crumbs
            ..add(const Text('/', style: style))
            ..add(
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4),
                child: Text(part, style: style),
              ),
            );
        } else {
          addFolder(folder);
        }
      }
      crumbs
        ..add(const Text('/', style: style))
        ..add(
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Text(
              file.displayName,
              key: const Key('aa-crumb-current-file'),
              style: style,
            ),
          ),
        );
    }

    return SingleChildScrollView(
      key: const Key('aa-breadcrumbs'),
      scrollDirection: Axis.horizontal,
      reverse: true,
      child: Row(children: crumbs),
    );
  }

  Widget _buildBody() {
    if (_search.text.trim().isNotEmpty) return _buildSearchResults();
    if (_view == _AaPickerView.favorites) {
      return _buildFavoritePages();
    }
    if (_view == _AaPickerView.history) {
      return _buildPageHistory();
    }
    if (_selectedFile != null) return _buildFileContents();
    if (_loadingTree) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_treeError != null) {
      return _ErrorView(message: _treeError!, onRetry: _retryTree);
    }
    final nodes = _folderStack.isEmpty ? _tree : _folderStack.last.children;
    return ListView.separated(
      key: const Key('aa-source-node-list'),
      itemCount: nodes.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final node = nodes[index];
        return ListTile(
          key: ValueKey('aa-node-${node.hash}'),
          leading: Icon(
            node.isFile ? Icons.description_outlined : Icons.folder,
            color: Colors.black,
          ),
          title: Text(node.displayName),
          subtitle:
              node.isFile
                  ? Text('${(node.filesize / 1024).toStringAsFixed(1)} KiB')
                  : null,
          trailing:
              node.isFile
                  ? const Icon(Icons.chevron_right)
                  : _FolderStar(
                    node: node,
                    isFavorite: _store.isFolderFavorite(node.hash),
                    onToggle: _store.toggleFolderFavorite,
                  ),
          onTap: () => _openNode(node),
        );
      },
    );
  }

  Widget _buildSearchResults() {
    if (_loadingTree) {
      return const Center(child: CircularProgressIndicator());
    }
    final query = _search.text.trim().toLowerCase();
    final results =
        _allFiles.where((file) {
          return file.filename.toLowerCase().contains(query) ||
              file.directory.toLowerCase().contains(query);
        }).toList();
    if (results.isEmpty) return const Center(child: Text('没有匹配的 AA 文件'));
    return ListView.builder(
      key: const Key('aa-search-results'),
      itemCount: results.length,
      itemBuilder: (context, index) {
        final file = results[index];
        return ListTile(
          leading: const Icon(Icons.description_outlined),
          title: Text(file.displayName),
          subtitle: Text(file.directory),
          onTap: () {
            _search.clear();
            _openFile(file);
          },
        );
      },
    );
  }

  Widget _buildFileContents() {
    if (_loadingFile) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_fileError != null) {
      return _ErrorView(
        message: _fileError!,
        onRetry: () => _openFile(_selectedFile!),
      );
    }
    if (_fileEntries.isEmpty) {
      return const Center(child: Text('这个文件里没有可选择的 AA'));
    }
    return _AaGrid(
      entries: _fileEntries,
      isFavorite: (entry) => _store.isAaFavorite(entry.id),
      onFavorite: _toggleFavorite,
      onSelect: _selectEntry,
    );
  }

  Widget _buildFavoritePages() {
    final folders = _store.favoriteFolders;
    final pages = _store.favoritePageGroups;
    if (folders.isEmpty && pages.isEmpty) {
      return const Center(child: Text('还没有收藏的文件夹、页面或 AA'));
    }
    return ListView.builder(
      key: const Key('aa-favorite-pages'),
      padding: const EdgeInsets.only(bottom: 12),
      itemCount: folders.length + pages.length,
      itemBuilder: (context, index) {
        if (index < folders.length) {
          final folder = folders[index];
          return Material(
            color: Colors.white,
            child: ListTile(
              key: ValueKey('aa-favorite-folder-${folder.hash}'),
              leading: const Icon(Icons.folder, color: Colors.black),
              title: Text(folder.name),
              subtitle: Text(folder.directory),
              trailing: IconButton(
                tooltip: '取消收藏文件夹',
                onPressed: () => _store.toggleFolderFavorite(folder),
                icon: const Icon(Icons.star, color: Color(0xffffa000)),
              ),
              onTap: () => _openSavedFolder(folder),
            ),
          );
        }
        final page = pages[index - folders.length];
        final items = _store.favoriteAasForPage(page.fileHash);
        final entries = items.map(_AaEntry.fromSaved).toList(growable: false);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Material(
              color: Colors.white,
              child: ListTile(
                key: ValueKey('aa-favorite-page-${page.fileHash}'),
                leading: const Icon(Icons.description_outlined),
                title: Text(page.displayName),
                subtitle: Text(page.directory),
                onTap: () => _openSavedPage(page),
                trailing: IconButton(
                  key: ValueKey('aa-saved-page-star-${page.fileHash}'),
                  tooltip:
                      _store.isPageFavorite(page.fileHash) ? '取消收藏页面' : '收藏页面',
                  onPressed: () => _store.togglePageFavorite(page),
                  icon: Icon(
                    _store.isPageFavorite(page.fileHash)
                        ? Icons.star
                        : Icons.star_border,
                    color:
                        _store.isPageFavorite(page.fileHash)
                            ? const Color(0xffffa000)
                            : Colors.black,
                  ),
                ),
              ),
            ),
            if (entries.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(72, 6, 12, 12),
                child: Text(
                  '已收藏页面；本页面尚未收藏具体 AA',
                  style: TextStyle(color: Color(0xff777777), fontSize: 12),
                ),
              )
            else
              _AaGrid(
                entries: entries,
                isFavorite: (entry) => _store.isAaFavorite(entry.id),
                onFavorite: _toggleFavorite,
                onSelect: _selectEntry,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
              ),
            const Divider(height: 1, color: Color(0xffbbbbbb)),
          ],
        );
      },
    );
  }

  Widget _buildPageHistory() {
    final pages = _store.pageHistory;
    if (pages.isEmpty) return const Center(child: Text('还没有浏览页面的历史'));
    return ListView.separated(
      key: const Key('aa-page-history'),
      itemCount: pages.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final page = pages[index];
        return ListTile(
          key: ValueKey('aa-history-page-${page.fileHash}'),
          leading: const Icon(Icons.description_outlined),
          title: Text(page.displayName),
          subtitle: Text(page.directory),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _openSavedPage(page),
        );
      },
    );
  }

  void _openNode(AaSourceNode node) {
    if (node.isFile) {
      _openFile(node);
      return;
    }
    setState(() {
      _folderStack.add(node);
      _selectedFile = null;
    });
  }

  Future<void> _openFile(AaSourceNode file) async {
    setState(() {
      _view = _AaPickerView.browse;
      _selectedFile = file;
      _fileEntries = const [];
      _fileError = null;
      _loadingFile = true;
    });
    _store.addPageHistory(AaSavedPage.fromSource(file));
    try {
      final contents = await _client.loadFile(file);
      final candidates = <_AaEntry>[];
      for (final (index, text) in contents.contents.indexed) {
        if (_looksLikeAa(text)) {
          candidates.add(_AaEntry.fromSource(file, index, text));
        }
      }
      if (candidates.isEmpty) {
        for (final (index, text) in contents.contents.indexed) {
          if (text.trim().isNotEmpty) {
            candidates.add(_AaEntry.fromSource(file, index, text));
          }
        }
      }
      if (!mounted || _selectedFile?.hash != file.hash) return;
      setState(() {
        _fileEntries = List.unmodifiable(candidates);
        _loadingFile = false;
      });
    } catch (error) {
      if (!mounted || _selectedFile?.hash != file.hash) return;
      setState(() {
        _loadingFile = false;
        _fileError = error.toString();
      });
    }
  }

  void _selectDrawerNode(AaSourceNode node) {
    Navigator.pop(context);
    _search.clear();
    setState(() {
      _view = _AaPickerView.browse;
      _folderStack.clear();
      _selectedFile = null;
    });
    if (node.isFile) {
      unawaited(_openFile(node));
    } else {
      setState(() => _folderStack.add(node));
    }
  }

  void _openSavedView(_AaPickerView view) {
    Navigator.pop(context);
    _search.clear();
    setState(() {
      _view = view;
      _selectedFile = null;
    });
  }

  void _openSavedPage(AaSavedPage page) {
    _folderStack.clear();
    unawaited(_openFile(page.toSourceNode()));
  }

  /// Re-walks the live tree to the saved path, so a bookmarked folder still
  /// opens after the source adds or renames entries around it.
  void _openSavedFolder(AaSavedFolder folder) {
    final path = _pathToFolder(_tree, folder.hash);
    if (path == null) {
      _showMessage('这个文件夹在 AA来源里已经找不到了');
      return;
    }
    _openFolderPath(path);
  }

  void _openFolderNode(AaSourceNode folder) {
    _openFolderPath(_pathToFolder(_tree, folder.hash) ?? [folder]);
  }

  void _openFolderPath(List<AaSourceNode> path) {
    _search.clear();
    setState(() {
      _view = _AaPickerView.browse;
      _selectedFile = null;
      _fileEntries = const [];
      _fileError = null;
      _loadingFile = false;
      _folderStack
        ..clear()
        ..addAll(path);
    });
  }

  /// Finds the folder whose own full path is [path]; a file's `directory`
  /// string is exactly the full path of the folder holding it.
  AaSourceNode? _folderForPath(String path) {
    AaSourceNode? search(Iterable<AaSourceNode> nodes) {
      for (final node in nodes) {
        if (node.isFile) continue;
        if (node.fullPath == path) return node;
        final deeper = search(node.children);
        if (deeper != null) return deeper;
      }
      return null;
    }

    return search(_tree);
  }

  static List<AaSourceNode>? _pathToFolder(
    Iterable<AaSourceNode> nodes,
    String hash,
  ) {
    for (final node in nodes) {
      if (node.isFile) continue;
      if (node.hash == hash) return [node];
      final deeper = _pathToFolder(node.children, hash);
      if (deeper != null) return [node, ...deeper];
    }
    return null;
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }

  void _toggleFavorite(_AaEntry entry) {
    _store.toggleAaFavorite(entry.toSavedItem());
  }

  void _selectEntry(_AaEntry entry) {
    Navigator.of(context).pop(entry.text);
  }

  void _goBackInsidePicker() {
    if (_search.text.isNotEmpty) {
      _search.clear();
      return;
    }
    if (_view != _AaPickerView.browse) {
      setState(() => _view = _AaPickerView.browse);
      return;
    }
    if (_selectedFile != null) {
      setState(() {
        _selectedFile = null;
        _fileEntries = const [];
        _fileError = null;
      });
      return;
    }
    if (_folderStack.isNotEmpty) {
      setState(() => _folderStack.removeLast());
      return;
    }
    Navigator.of(context).pop();
  }

  Future<void> _confirmClearCurrentList() async {
    final favorites = _view == _AaPickerView.favorites;
    final confirmed = await showDialog<bool>(
      context: context,
      builder:
          (context) => AlertDialog(
            title: Text(favorites ? '清除全部收藏' : '清除全部历史'),
            content: Text(
              favorites ? '删除本机保存的所有页面和 AA 收藏？' : '删除本机保存的所有页面浏览历史？',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text('取消'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text('清除'),
              ),
            ],
          ),
    );
    if (confirmed != true) return;
    if (favorites) {
      _store.clearFavorites();
    } else {
      _store.clearHistory();
    }
  }

  Future<void> _retryTree() async {
    setState(() {
      _loadingTree = true;
      _treeError = null;
    });
    await _loadInitialData();
  }

  void _onStoreChanged() {
    if (mounted) setState(() {});
  }

  void _onSearchChanged() {
    if (mounted) setState(() {});
  }

  static Iterable<AaSourceNode> _flattenFiles(
    Iterable<AaSourceNode> nodes,
  ) sync* {
    for (final node in nodes) {
      if (node.isFile) {
        yield node;
      } else {
        yield* _flattenFiles(node.children);
      }
    }
  }

  static bool _looksLikeAa(String text) {
    final normalized = text.trim();
    return normalized.contains('\n') || normalized.length >= 24;
  }
}

class _AaEntry {
  const _AaEntry({
    required this.id,
    required this.fileHash,
    required this.fileName,
    required this.directory,
    required this.index,
    required this.text,
  });

  factory _AaEntry.fromSource(AaSourceNode file, int index, String text) {
    return _AaEntry(
      id: '${file.hash}:$index',
      fileHash: file.hash,
      fileName: file.filename,
      directory: file.directory,
      index: index,
      text: text,
    );
  }

  factory _AaEntry.fromSaved(AaSavedItem item) {
    return _AaEntry(
      id: item.id,
      fileHash: item.fileHash,
      fileName: item.fileName,
      directory: item.directory,
      index: item.index,
      text: item.text,
    );
  }

  final String id;
  final String fileHash;
  final String fileName;
  final String directory;
  final int index;
  final String text;

  AaSavedItem toSavedItem() {
    return AaSavedItem(
      id: id,
      fileHash: fileHash,
      fileName: fileName,
      directory: directory,
      index: index,
      text: text,
      savedAt: DateTime.now(),
    );
  }
}

class _AaGrid extends StatelessWidget {
  const _AaGrid({
    required this.entries,
    required this.isFavorite,
    required this.onFavorite,
    required this.onSelect,
    this.shrinkWrap = false,
    this.physics,
  });

  final List<_AaEntry> entries;
  final bool Function(_AaEntry entry) isFavorite;
  final ValueChanged<_AaEntry> onFavorite;
  final ValueChanged<_AaEntry> onSelect;
  final bool shrinkWrap;
  final ScrollPhysics? physics;

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    final columnCount =
        width >= 1200
            ? 5
            : width >= 850
            ? 4
            : width >= 600
            ? 3
            : 2;
    return GridView.builder(
      key: const Key('aa-grid'),
      shrinkWrap: shrinkWrap,
      physics: physics,
      padding: const EdgeInsets.all(7),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: columnCount,
        mainAxisSpacing: 7,
        crossAxisSpacing: 7,
        childAspectRatio: 0.82,
      ),
      itemCount: entries.length,
      itemBuilder: (context, index) {
        final entry = entries[index];
        final favorite = isFavorite(entry);
        return Material(
          key: ValueKey('aa-card-${entry.id}'),
          color: Colors.white,
          shape: const RoundedRectangleBorder(
            side: BorderSide(color: Color(0xffcccccc), width: 0.7),
            borderRadius: BorderRadius.all(Radius.circular(8)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              SizedBox(
                height: 36,
                child: Row(
                  children: [
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Text(
                          '#${entry.index + 1}',
                          style: const TextStyle(fontSize: 12),
                        ),
                      ),
                    ),
                    IconButton(
                      key: ValueKey('aa-favorite-${entry.id}'),
                      tooltip: favorite ? '取消收藏' : '收藏',
                      padding: EdgeInsets.zero,
                      visualDensity: VisualDensity.compact,
                      onPressed: () => onFavorite(entry),
                      icon: Icon(
                        favorite ? Icons.star : Icons.star_border,
                        color:
                            favorite ? const Color(0xffffa000) : Colors.black,
                        size: 21,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: InkWell(
                  key: ValueKey('aa-select-${entry.id}'),
                  onTap: () => onSelect(entry),
                  child: Padding(
                    padding: const EdgeInsets.all(5),
                    child: CustomPaint(
                      painter: _AaThumbnailPainter(entry.text),
                      child: const SizedBox.expand(),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class _AaThumbnailPainter extends CustomPainter {
  _AaThumbnailPainter(this.text);

  final String text;

  @override
  void paint(Canvas canvas, Size size) {
    final painter = TextPainter(
      text: TextSpan(text: text, style: AaText.baseStyle),
      textDirection: TextDirection.ltr,
      textScaler: TextScaler.noScaling,
    )..layout();
    if (painter.width <= 0 || painter.height <= 0) return;
    final scale = math.min(
      1.0,
      math.min(size.width / painter.width, size.height / painter.height),
    );
    canvas.save();
    canvas.scale(scale, scale);
    painter.paint(canvas, Offset.zero);
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _AaThumbnailPainter oldDelegate) {
    return oldDelegate.text != text;
  }
}

class _FolderStar extends StatelessWidget {
  const _FolderStar({
    required this.node,
    required this.isFavorite,
    required this.onToggle,
  });

  final AaSourceNode node;
  final bool isFavorite;
  final ValueChanged<AaSavedFolder> onToggle;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      key: ValueKey('aa-folder-star-${node.hash}'),
      tooltip: isFavorite ? '取消收藏文件夹' : '收藏文件夹',
      onPressed: () => onToggle(AaSavedFolder.fromSource(node)),
      icon: Icon(
        isFavorite ? Icons.star : Icons.star_border,
        color: isFavorite ? const Color(0xffffa000) : Colors.black,
      ),
    );
  }
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(message, textAlign: TextAlign.center),
            const SizedBox(height: 12),
            OutlinedButton(onPressed: onRetry, child: const Text('重试')),
          ],
        ),
      ),
    );
  }
}
