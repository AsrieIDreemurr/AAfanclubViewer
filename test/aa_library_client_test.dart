import 'dart:convert';

import 'package:aafanclub_viewer/data/aa_library_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('character references in AA sources become real characters', () {
    // Shapes taken from live aa.yaruyomi.com files.
    expect(decodeCharacterReferences('&#9829;'), '♥');
    expect(decodeCharacterReferences('&#10084;'), '❤');
    expect(decodeCharacterReferences('&#65293;'), '－');
    expect(decodeCharacterReferences('&#xA0;'), ' ');
    expect(decodeCharacterReferences('&#Xa0;'), ' ');
    expect(decodeCharacterReferences('&amp;&lt;&gt;'), '&<>');

    // A single pass, so a decoded ampersand is never decoded twice.
    expect(decodeCharacterReferences('&amp;#9829;'), '&#9829;');

    // AA draws with these characters; only complete references may change.
    expect(decodeCharacterReferences('( ﾟ∀ﾟ)＜ & > #9829;'), '( ﾟ∀ﾟ)＜ & > #9829;');
    expect(decodeCharacterReferences('&#;'), '&#;');
    expect(decodeCharacterReferences('&notareference;'), '&notareference;');
    // Surrogate halves are not characters on their own.
    expect(decodeCharacterReferences('&#xD800;'), '&#xD800;');
  });

  test('decoded contents come back through the client', () async {
    final client = AaLibraryClient(
      client: MockClient((request) async {
        return http.Response(
          jsonEncode({
            'dir': '/x',
            'filename': 'y.mlt',
            'filesize': 1,
            'contents': ['&#9829;&#xA0;（'],
          }),
          200,
          headers: const {'content-type': 'application/json'},
        );
      }),
    );

    final file = await client.loadFile(
      const AaSourceNode(
        directory: '/x',
        filename: 'y.mlt',
        hash: 'h',
        filesize: 1,
        isFile: true,
      ),
    );

    expect(file.contents.single, '♥ （');
  });

  test('loads the public yaruyomi directory and mlt contents JSON', () async {
    final client = AaLibraryClient(
      client: MockClient((request) async {
        if (request.url.path.endsWith('/list')) {
          return http.Response(
            '''[
              {
                "dir":"",
                "filename":"あ行",
                "hash":"folder",
                "filesize":0,
                "isF":false,
                "child":[{
                  "dir":"/あ行",
                  "filename":"作品.mlt",
                  "hash":"file-1",
                  "filesize":123,
                  "isF":true
                }]
              }
            ]''',
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        expect(request.url.queryParameters['hash'], 'file-1');
        return http.Response(
          '''{
            "dir":"/あ行",
            "filename":"作品.mlt",
            "filesize":123,
            "contents":["标题"," /\\n/  \\\\ "]
          }''',
          200,
          headers: {'content-type': 'application/json; charset=utf-8'},
        );
      }),
    );

    final tree = await client.loadTree();
    expect(tree.single.filename, 'あ行');
    expect(tree.single.children.single.hash, 'file-1');

    final file = await client.loadFile(tree.single.children.single);
    expect(file.filename, '作品.mlt');
    expect(file.contents, hasLength(2));
    expect(file.contents.last, contains('\n'));
    client.close();
  });
}
