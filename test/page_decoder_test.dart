import 'dart:typed_data';

import 'package:aafanclub_viewer/data/page_decoder.dart';
import 'package:charset/charset.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  const decoder = PageDecoder();

  test('uses charset from the HTTP content-type header', () {
    final bytes = Uint8List.fromList(shiftJis.encode('こんにちは AA'));
    final result = decoder.decode(bytes, const {
      'content-type': 'text/html; charset=Shift_JIS',
    });

    expect(result.encoding, 'Shift_JIS');
    expect(result.text, 'こんにちは AA');
  });

  test('uses charset from an HTML meta element', () {
    const markup = '<meta charset="shift_jis"><p>モナー</p>';
    final bytes = Uint8List.fromList(shiftJis.encode(markup));
    final result = decoder.decode(bytes, const {});

    expect(result.encoding, 'Shift_JIS');
    expect(result.text, contains('モナー'));
  });
}
