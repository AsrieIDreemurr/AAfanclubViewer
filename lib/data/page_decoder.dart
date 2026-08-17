import 'dart:convert';
import 'dart:typed_data';

import 'package:charset/charset.dart';

class DecodedPage {
  const DecodedPage({required this.text, required this.encoding});

  final String text;
  final String encoding;
}

class PageDecoder {
  const PageDecoder();

  DecodedPage decode(Uint8List bytes, Map<String, String> headers) {
    final declared = _charsetFromHeaders(headers) ?? _charsetFromMarkup(bytes);
    if (declared != null) {
      return DecodedPage(
        text: _decodeWithCharset(bytes, declared),
        encoding: _displayName(declared),
      );
    }

    if (_hasUtf8Bom(bytes)) {
      return DecodedPage(
        text: utf8.decode(bytes.sublist(3), allowMalformed: true),
        encoding: 'UTF-8',
      );
    }

    try {
      return DecodedPage(text: utf8.decode(bytes), encoding: 'UTF-8');
    } on FormatException {
      // Japanese legacy boards commonly omit the Shift_JIS declaration.
      return DecodedPage(text: shiftJis.decode(bytes), encoding: 'Shift_JIS');
    }
  }

  String? _charsetFromHeaders(Map<String, String> headers) {
    String? contentType;
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == 'content-type') {
        contentType = entry.value;
        break;
      }
    }
    if (contentType == null) return null;
    return RegExp(
      r'''charset\s*=\s*["']?([^\s;"']+)''',
      caseSensitive: false,
    ).firstMatch(contentType)?.group(1);
  }

  String? _charsetFromMarkup(Uint8List bytes) {
    final prefixLength = bytes.length < 8192 ? bytes.length : 8192;
    final prefix = latin1.decode(bytes.sublist(0, prefixLength));
    final direct = RegExp(
      r'''<meta[^>]+charset\s*=\s*["']?([^\s/>"']+)''',
      caseSensitive: false,
    ).firstMatch(prefix)?.group(1);
    if (direct != null) return direct;

    return RegExp(
      r'''<meta[^>]+content\s*=\s*["'][^"']*charset\s*=\s*([^\s;"']+)''',
      caseSensitive: false,
    ).firstMatch(prefix)?.group(1);
  }

  String _decodeWithCharset(Uint8List bytes, String charset) {
    switch (_normalized(charset)) {
      case 'utf8':
        final content = _hasUtf8Bom(bytes) ? bytes.sublist(3) : bytes;
        return utf8.decode(content, allowMalformed: true);
      case 'shiftjis':
      case 'sjis':
      case 'xsjis':
      case 'windows31j':
      case 'cp932':
        return shiftJis.decode(bytes);
      case 'eucjp':
        return eucJp.decode(bytes);
      case 'iso88591':
      case 'latin1':
        return latin1.decode(bytes);
      default:
        return utf8.decode(bytes, allowMalformed: true);
    }
  }

  String _displayName(String charset) {
    switch (_normalized(charset)) {
      case 'utf8':
        return 'UTF-8';
      case 'shiftjis':
      case 'sjis':
      case 'xsjis':
      case 'windows31j':
      case 'cp932':
        return 'Shift_JIS';
      case 'eucjp':
        return 'EUC-JP';
      default:
        return charset;
    }
  }

  String _normalized(String value) =>
      value.trim().toLowerCase().replaceAll(RegExp(r'[-_]'), '');

  bool _hasUtf8Bom(List<int> bytes) =>
      bytes.length >= 3 &&
      bytes[0] == 0xef &&
      bytes[1] == 0xbb &&
      bytes[2] == 0xbf;
}
