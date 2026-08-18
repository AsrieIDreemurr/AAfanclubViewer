import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../data/aa_library_client.dart';

class AaSavedItem {
  const AaSavedItem({
    required this.id,
    required this.fileHash,
    required this.fileName,
    required this.directory,
    required this.index,
    required this.text,
    required this.savedAt,
  });

  final String id;
  final String fileHash;
  final String fileName;
  final String directory;
  final int index;
  final String text;
  final DateTime savedAt;

  factory AaSavedItem.fromSource({
    required AaSourceNode file,
    required int index,
    required String text,
  }) {
    return AaSavedItem(
      id: '${file.hash}:$index',
      fileHash: file.hash,
      fileName: file.filename,
      directory: file.directory,
      index: index,
      text: text,
      savedAt: DateTime.now(),
    );
  }

  Map<String, Object> toJson() => {
    'id': id,
    'fileHash': fileHash,
    'fileName': fileName,
    'directory': directory,
    'index': index,
    'text': text,
    'savedAt': savedAt.toIso8601String(),
  };

  static AaSavedItem? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final fileHash = value['fileHash'];
    final fileName = value['fileName'];
    final directory = value['directory'];
    final index = value['index'];
    final text = value['text'];
    final savedAt = value['savedAt'];
    if (id is! String ||
        fileHash is! String ||
        fileName is! String ||
        directory is! String ||
        index is! num ||
        text is! String ||
        savedAt is! String) {
      return null;
    }
    final time = DateTime.tryParse(savedAt);
    if (time == null) return null;
    return AaSavedItem(
      id: id,
      fileHash: fileHash,
      fileName: fileName,
      directory: directory,
      index: index.toInt(),
      text: text,
      savedAt: time,
    );
  }
}

class AaSavedPage {
  const AaSavedPage({
    required this.fileHash,
    required this.fileName,
    required this.directory,
    required this.savedAt,
  });

  final String fileHash;
  final String fileName;
  final String directory;
  final DateTime savedAt;

  String get id => fileHash;
  String get displayName => fileName.replaceFirst(RegExp(r'\.mlt$'), '');
  String get fullPath =>
      directory.isEmpty ? '/$fileName' : '$directory/$fileName';

  factory AaSavedPage.fromSource(AaSourceNode file) {
    return AaSavedPage(
      fileHash: file.hash,
      fileName: file.filename,
      directory: file.directory,
      savedAt: DateTime.now(),
    );
  }

  factory AaSavedPage.fromItem(AaSavedItem item) {
    return AaSavedPage(
      fileHash: item.fileHash,
      fileName: item.fileName,
      directory: item.directory,
      savedAt: item.savedAt,
    );
  }

  AaSourceNode toSourceNode() {
    return AaSourceNode(
      directory: directory,
      filename: fileName,
      hash: fileHash,
      filesize: 0,
      isFile: true,
    );
  }

  Map<String, Object> toJson() => {
    'fileHash': fileHash,
    'fileName': fileName,
    'directory': directory,
    'savedAt': savedAt.toIso8601String(),
  };

  static AaSavedPage? fromJson(Object? value) {
    if (value is! Map) return null;
    final fileHash = value['fileHash'];
    final fileName = value['fileName'];
    final directory = value['directory'];
    final savedAt = value['savedAt'];
    if (fileHash is! String ||
        fileName is! String ||
        directory is! String ||
        savedAt is! String) {
      return null;
    }
    final time = DateTime.tryParse(savedAt);
    if (time == null) return null;
    return AaSavedPage(
      fileHash: fileHash,
      fileName: fileName,
      directory: directory,
      savedAt: time,
    );
  }
}

/// A bookmarked directory in the AA source tree. Only the path is kept; the
/// folder's children are re-read from the live tree on the next visit.
class AaSavedFolder {
  const AaSavedFolder({
    required this.hash,
    required this.name,
    required this.directory,
    required this.savedAt,
  });

  final String hash;
  final String name;
  final String directory;
  final DateTime savedAt;

  String get id => hash;
  String get fullPath => directory.isEmpty ? '/$name' : '$directory/$name';

  factory AaSavedFolder.fromSource(AaSourceNode folder) {
    return AaSavedFolder(
      hash: folder.hash,
      name: folder.filename,
      directory: folder.directory,
      savedAt: DateTime.now(),
    );
  }

  Map<String, Object> toJson() => {
    'hash': hash,
    'name': name,
    'directory': directory,
    'savedAt': savedAt.toIso8601String(),
  };

  static AaSavedFolder? fromJson(Object? value) {
    if (value is! Map) return null;
    final hash = value['hash'];
    final name = value['name'];
    final directory = value['directory'];
    final savedAt = value['savedAt'];
    if (hash is! String ||
        name is! String ||
        directory is! String ||
        savedAt is! String) {
      return null;
    }
    final time = DateTime.tryParse(savedAt);
    if (time == null) return null;
    return AaSavedFolder(
      hash: hash,
      name: name,
      directory: directory,
      savedAt: time,
    );
  }
}

class AaLibraryStore extends ChangeNotifier {
  static const _favoritesKey = 'aa.library.favorites.v1';
  static const _legacyAaHistoryKey = 'aa.library.history.v1';
  static const _favoritePagesKey = 'aa.library.favorite-pages.v1';
  static const _pageHistoryKey = 'aa.library.page-history.v1';
  static const _favoriteFoldersKey = 'aa.library.favorite-folders.v1';

  SharedPreferences? _preferences;
  final List<AaSavedItem> _favoriteAas = [];
  final List<AaSavedPage> _favoritePages = [];
  final List<AaSavedPage> _pageHistory = [];
  final List<AaSavedFolder> _favoriteFolders = [];
  bool _loaded = false;

  bool get loaded => _loaded;
  List<AaSavedItem> get favoriteAas => List.unmodifiable(_favoriteAas);
  List<AaSavedPage> get favoritePages => List.unmodifiable(_favoritePages);
  List<AaSavedPage> get pageHistory => List.unmodifiable(_pageHistory);
  List<AaSavedFolder> get favoriteFolders =>
      List.unmodifiable(_favoriteFolders);

  List<AaSavedPage> get favoritePageGroups {
    final pages = <String, AaSavedPage>{};
    for (final page in _favoritePages) {
      pages[page.fileHash] = page;
    }
    for (final item in _favoriteAas) {
      pages.putIfAbsent(item.fileHash, () => AaSavedPage.fromItem(item));
    }
    final result =
        pages.values.toList()..sort((a, b) => b.savedAt.compareTo(a.savedAt));
    return List.unmodifiable(result);
  }

  Future<void> load() async {
    if (_loaded) return;
    try {
      final preferences = await SharedPreferences.getInstance();
      _preferences = preferences;
      _decodeAaList(preferences.getString(_favoritesKey), _favoriteAas);
      _decodePageList(preferences.getString(_favoritePagesKey), _favoritePages);
      _decodePageList(preferences.getString(_pageHistoryKey), _pageHistory);
      _decodeFolderList(
        preferences.getString(_favoriteFoldersKey),
        _favoriteFolders,
      );
      if (_pageHistory.isEmpty) {
        final legacyHistory = <AaSavedItem>[];
        _decodeAaList(
          preferences.getString(_legacyAaHistoryKey),
          legacyHistory,
        );
        for (final item in legacyHistory) {
          if (_pageHistory.any((page) => page.fileHash == item.fileHash)) {
            continue;
          }
          _pageHistory.add(AaSavedPage.fromItem(item));
        }
        if (_pageHistory.isNotEmpty) {
          _savePages(_pageHistoryKey, _pageHistory);
        }
      }
    } catch (_) {
      // The picker remains usable with in-memory storage.
    }
    _loaded = true;
    notifyListeners();
  }

  bool isAaFavorite(String id) => _favoriteAas.any((item) => item.id == id);

  bool isPageFavorite(String fileHash) {
    return _favoritePages.any((page) => page.fileHash == fileHash);
  }

  List<AaSavedItem> favoriteAasForPage(String fileHash) {
    return List.unmodifiable(
      _favoriteAas.where((item) => item.fileHash == fileHash),
    );
  }

  void toggleAaFavorite(AaSavedItem item) {
    final index = _favoriteAas.indexWhere((saved) => saved.id == item.id);
    if (index >= 0) {
      _favoriteAas.removeAt(index);
    } else {
      _favoriteAas.insert(0, item);
    }
    notifyListeners();
    _saveAas(_favoritesKey, _favoriteAas);
  }

  void togglePageFavorite(AaSavedPage page) {
    final index = _favoritePages.indexWhere(
      (saved) => saved.fileHash == page.fileHash,
    );
    if (index >= 0) {
      _favoritePages.removeAt(index);
    } else {
      _favoritePages.insert(0, page);
    }
    notifyListeners();
    _savePages(_favoritePagesKey, _favoritePages);
  }

  bool isFolderFavorite(String hash) {
    return _favoriteFolders.any((folder) => folder.hash == hash);
  }

  void toggleFolderFavorite(AaSavedFolder folder) {
    final index = _favoriteFolders.indexWhere(
      (saved) => saved.hash == folder.hash,
    );
    if (index >= 0) {
      _favoriteFolders.removeAt(index);
    } else {
      _favoriteFolders.insert(0, folder);
    }
    notifyListeners();
    _saveFolders();
  }

  void addPageHistory(AaSavedPage page) {
    _pageHistory.removeWhere((saved) => saved.fileHash == page.fileHash);
    _pageHistory.insert(0, page);
    notifyListeners();
    _savePages(_pageHistoryKey, _pageHistory);
  }

  void clearFavorites() {
    if (_favoriteAas.isEmpty &&
        _favoritePages.isEmpty &&
        _favoriteFolders.isEmpty) {
      return;
    }
    _favoriteAas.clear();
    _favoritePages.clear();
    _favoriteFolders.clear();
    notifyListeners();
    _saveAas(_favoritesKey, _favoriteAas);
    _savePages(_favoritePagesKey, _favoritePages);
    _saveFolders();
  }

  void clearHistory() {
    if (_pageHistory.isEmpty) return;
    _pageHistory.clear();
    notifyListeners();
    _savePages(_pageHistoryKey, _pageHistory);
  }

  void _decodeAaList(String? source, List<AaSavedItem> target) {
    if (source == null) return;
    final decoded = jsonDecode(source);
    if (decoded is! List) return;
    for (final value in decoded) {
      final item = AaSavedItem.fromJson(value);
      if (item != null) target.add(item);
    }
  }

  void _decodeFolderList(String? source, List<AaSavedFolder> target) {
    if (source == null) return;
    final decoded = jsonDecode(source);
    if (decoded is! List) return;
    for (final value in decoded) {
      final folder = AaSavedFolder.fromJson(value);
      if (folder != null) target.add(folder);
    }
  }

  void _saveFolders() {
    final preferences = _preferences;
    if (preferences == null) return;
    unawaited(
      preferences.setString(
        _favoriteFoldersKey,
        jsonEncode(_favoriteFolders.map((item) => item.toJson()).toList()),
      ),
    );
  }

  void _decodePageList(String? source, List<AaSavedPage> target) {
    if (source == null) return;
    final decoded = jsonDecode(source);
    if (decoded is! List) return;
    for (final value in decoded) {
      final page = AaSavedPage.fromJson(value);
      if (page != null) target.add(page);
    }
  }

  void _saveAas(String key, List<AaSavedItem> values) {
    final preferences = _preferences;
    if (preferences == null) return;
    unawaited(
      preferences.setString(
        key,
        jsonEncode(values.map((item) => item.toJson()).toList()),
      ),
    );
  }

  void _savePages(String key, List<AaSavedPage> values) {
    final preferences = _preferences;
    if (preferences == null) return;
    unawaited(
      preferences.setString(
        key,
        jsonEncode(values.map((page) => page.toJson()).toList()),
      ),
    );
  }
}
