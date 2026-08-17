import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:path_provider/path_provider.dart';

import 'page_source.dart';

typedef CacheDirectoryProvider = Future<Directory> Function();

class ThreadPageCache {
  ThreadPageCache({CacheDirectoryProvider? directoryProvider})
    : _directoryProvider = directoryProvider ?? _defaultDirectory;

  static final _threadPath = RegExp(r'^/view/(\d+)(?:-(\d+))?(-icchi)?/?$');

  final CacheDirectoryProvider _directoryProvider;
  final Map<String, SourcePage> _memory = {};
  Directory? _directory;
  bool _directoryUnavailable = false;

  int get memoryEntryCount => _memory.length;

  Future<SourcePage?> read(Uri uri) async {
    final key = _cacheKey(uri);
    if (key == null) return null;
    final memory = _memory[key];
    if (memory != null) return memory;

    final directory = await _getDirectory();
    if (directory == null) return null;
    final file = File(_filePath(directory, key));
    if (!await file.exists()) return null;
    try {
      final decoded = jsonDecode(await file.readAsString());
      if (decoded is! Map<String, dynamic>) return null;
      final finalUri = Uri.tryParse(decoded['uri'] as String? ?? '');
      final rawBytes = decoded['bytes'];
      final rawHeaders = decoded['headers'];
      if (finalUri == null ||
          rawBytes is! String ||
          rawHeaders is! Map<String, dynamic>) {
        return null;
      }
      final page = SourcePage(
        uri: finalUri,
        bytes: Uint8List.fromList(base64Decode(rawBytes)),
        headers: rawHeaders.map(
          (name, value) => MapEntry(name, value.toString()),
        ),
      );
      _memory[key] = page;
      unawaited(file.setLastModified(DateTime.now()));
      return page;
    } catch (_) {
      try {
        await file.delete();
      } catch (_) {}
      return null;
    }
  }

  Future<void> write(Uri requestedUri, SourcePage page) async {
    final key = _cacheKey(requestedUri);
    if (key == null) return;
    _memory[key] = page;
    final directory = await _getDirectory(create: true);
    if (directory == null) return;
    final file = File(_filePath(directory, key));
    final data = jsonEncode({
      'uri': page.uri.toString(),
      'headers': page.headers,
      'bytes': base64Encode(page.bytes),
    });
    try {
      await file.writeAsString(data, flush: false);
      await _prune(directory);
    } catch (_) {
      // Memory caching remains available when disk writes are unavailable.
    }
  }

  Future<int> clear() async {
    var removed = _memory.length;
    _memory.clear();
    final directory = await _getDirectory();
    if (directory == null || !await directory.exists()) return removed;
    try {
      final files =
          await directory.list().where((item) => item is File).toList();
      removed += files.length;
      for (final entity in files) {
        await entity.delete();
      }
    } catch (_) {}
    return removed;
  }

  Future<Directory?> _getDirectory({bool create = false}) async {
    if (_directoryUnavailable) return null;
    var directory = _directory;
    if (directory == null) {
      try {
        directory = await _directoryProvider();
        _directory = directory;
      } catch (_) {
        _directoryUnavailable = true;
        return null;
      }
    }
    if (create && !await directory.exists()) {
      try {
        await directory.create(recursive: true);
      } catch (_) {
        return null;
      }
    }
    return directory;
  }

  Future<void> _prune(Directory directory) async {
    const maximumBytes = 80 * 1024 * 1024;
    const targetBytes = 64 * 1024 * 1024;
    try {
      final files =
          await directory
              .list()
              .where((item) => item is File)
              .cast<File>()
              .toList();
      final entries = <({File file, int length, DateTime modified})>[];
      var total = 0;
      for (final file in files) {
        final stat = await file.stat();
        total += stat.size;
        entries.add((file: file, length: stat.size, modified: stat.modified));
      }
      if (total <= maximumBytes) return;
      entries.sort((a, b) => a.modified.compareTo(b.modified));
      for (final entry in entries) {
        await entry.file.delete();
        total -= entry.length;
        if (total <= targetBytes) break;
      }
    } catch (_) {}
  }

  String? _cacheKey(Uri uri) {
    final match = _threadPath.firstMatch(uri.path);
    if (match == null) return null;
    final page = match.group(2) ?? '1';
    final suffix = match.group(3) ?? '';
    return uri
        .replace(
          path: '/view/${match.group(1)}-$page$suffix',
          query: null,
          fragment: null,
        )
        .toString();
  }

  String _filePath(Directory directory, String key) {
    var hash = 0xcbf29ce484222325;
    for (final byte in utf8.encode(key)) {
      hash ^= byte;
      hash = (hash * 0x100000001b3) & 0xffffffffffffffff;
    }
    return '${directory.path}${Platform.pathSeparator}${hash.toRadixString(16)}.json';
  }

  static Future<Directory> _defaultDirectory() async {
    final root = await getApplicationCacheDirectory();
    return Directory(
      '${root.path}${Platform.pathSeparator}aafanclub_thread_pages',
    );
  }
}
