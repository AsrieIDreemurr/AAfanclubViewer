import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class AaSourceNode {
  const AaSourceNode({
    required this.directory,
    required this.filename,
    required this.hash,
    required this.filesize,
    required this.isFile,
    this.children = const [],
  });

  final String directory;
  final String filename;
  final String hash;
  final int filesize;
  final bool isFile;
  final List<AaSourceNode> children;

  String get displayName => filename.replaceFirst(RegExp(r'\.mlt$'), '');
  String get fullPath =>
      directory.isEmpty ? '/$filename' : '$directory/$filename';

  static AaSourceNode? fromJson(Object? value) {
    if (value is! Map) return null;
    final directory = value['dir'];
    final filename = value['filename'];
    final hash = value['hash'];
    if (directory is! String || filename is! String || hash is! String) {
      return null;
    }
    final children = <AaSourceNode>[];
    final rawChildren = value['child'];
    if (rawChildren is List) {
      for (final item in rawChildren) {
        final child = AaSourceNode.fromJson(item);
        if (child != null) children.add(child);
      }
    }
    return AaSourceNode(
      directory: directory,
      filename: filename,
      hash: hash,
      filesize: (value['filesize'] as num?)?.toInt() ?? 0,
      isFile: value['isF'] == true,
      children: List.unmodifiable(children),
    );
  }
}

class AaSourceFile {
  const AaSourceFile({
    required this.directory,
    required this.filename,
    required this.filesize,
    required this.contents,
  });

  final String directory;
  final String filename;
  final int filesize;
  final List<String> contents;

  static AaSourceFile? fromJson(Object? value) {
    if (value is! Map) return null;
    final directory = value['dir'];
    final filename = value['filename'];
    final rawContents = value['contents'];
    if (directory is! String || filename is! String || rawContents is! List) {
      return null;
    }
    return AaSourceFile(
      directory: directory,
      filename: filename,
      filesize: (value['filesize'] as num?)?.toInt() ?? 0,
      contents: List.unmodifiable(
        rawContents.whereType<String>().map(decodeCharacterReferences),
      ),
    );
  }
}

final _characterReference = RegExp(
  r'&(?:#(\d{1,7})|#[xX]([0-9a-fA-F]{1,6})|(amp|lt|gt|quot|apos|nbsp));',
);

const _namedCharacterReferences = {
  'amp': '&',
  'lt': '<',
  'gt': '>',
  'quot': '"',
  'apos': "'",
  'nbsp': ' ',
};

/// Turns the HTML character references the AA source ships into the characters
/// they stand for. The drawings are stored as HTML fragments, so a heart or a
/// no-break space arrives as `&#9829;` or `&#xA0;`.
///
/// Leaving them encoded is not only ugly on screen: the composer measures text
/// to place it, and an eight-character escape is nothing like the one glyph it
/// represents, so every drawing containing one would be laid out wrong.
///
/// Only well-formed references are touched, in a single pass, so the `&`, `<`
/// and `>` that AA uses as ordinary strokes are left exactly as they are.
String decodeCharacterReferences(String source) {
  if (!source.contains('&')) return source;
  return source.replaceAllMapped(_characterReference, (match) {
    final named = match.group(3);
    if (named != null) return _namedCharacterReferences[named]!;
    final digits = match.group(1);
    final code =
        digits != null
            ? int.tryParse(digits)
            : int.tryParse(match.group(2)!, radix: 16);
    if (code == null || code < 0 || code > 0x10ffff) return match.group(0)!;
    // Surrogate halves are not characters on their own.
    if (code >= 0xd800 && code <= 0xdfff) return match.group(0)!;
    return String.fromCharCode(code);
  });
}

class AaLibraryException implements Exception {
  const AaLibraryException(this.message);

  final String message;

  @override
  String toString() => message;
}

class AaLibraryClient {
  AaLibraryClient({http.Client? client}) : _client = client ?? http.Client();

  static final Uri _listUri = Uri.https(
    'aa.yaruyomi.com',
    '/matome-zip/file/list',
  );
  static final Uri _contentsUri = Uri.https(
    'aa.yaruyomi.com',
    '/matome-zip/file/contents',
  );

  final http.Client _client;

  Future<List<AaSourceNode>> loadTree() async {
    final decoded = await _getJson(_listUri);
    if (decoded is! List) throw const AaLibraryException('AA目录格式不正确');
    final nodes = <AaSourceNode>[];
    for (final item in decoded) {
      final node = AaSourceNode.fromJson(item);
      if (node != null) nodes.add(node);
    }
    return List.unmodifiable(nodes);
  }

  Future<AaSourceFile> loadFile(AaSourceNode node) async {
    final decoded = await _getJson(
      _contentsUri.replace(queryParameters: {'hash': node.hash}),
    );
    final file = AaSourceFile.fromJson(decoded);
    if (file == null) throw const AaLibraryException('AA文件格式不正确');
    return file;
  }

  void close() => _client.close();

  Future<Object?> _getJson(Uri uri) async {
    try {
      final response = await _client
          .get(uri, headers: const {'Accept': 'application/json'})
          .timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw AaLibraryException('AA来源读取失败（${response.statusCode}）');
      }
      final source = utf8.decode(response.bodyBytes);
      return compute(_decodeJson, source);
    } on AaLibraryException {
      rethrow;
    } catch (error) {
      throw AaLibraryException('AA来源读取失败：$error');
    }
  }
}

Object? _decodeJson(String source) => jsonDecode(source);
