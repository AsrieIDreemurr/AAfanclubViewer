import 'package:aafanclub_viewer/data/aa_library_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
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
