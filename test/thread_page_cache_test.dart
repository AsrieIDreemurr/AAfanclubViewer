import 'dart:io';
import 'dart:typed_data';

import 'package:aafanclub_viewer/data/page_source.dart';
import 'package:aafanclub_viewer/data/thread_page_cache.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('persists thread pages, normalizes page one, and clears them', () async {
    final directory = await Directory.systemTemp.createTemp(
      'aafanclub-cache-test-',
    );
    addTearDown(() async {
      if (await directory.exists()) await directory.delete(recursive: true);
    });
    final base = Uri.parse('http://aafanclub.com/view/42');
    final page = SourcePage(
      uri: base,
      bytes: Uint8List.fromList('<html>cached</html>'.codeUnits),
      headers: const {'content-type': 'text/html; charset=utf-8'},
    );

    final first = ThreadPageCache(directoryProvider: () async => directory);
    await first.write(base, page);

    final restored = ThreadPageCache(directoryProvider: () async => directory);
    final cached = await restored.read(
      Uri.parse('http://aafanclub.com/view/42-1'),
    );
    expect(String.fromCharCodes(cached!.bytes), '<html>cached</html>');

    expect(await restored.clear(), greaterThan(0));
    expect(await restored.read(base), isNull);
  });
}
