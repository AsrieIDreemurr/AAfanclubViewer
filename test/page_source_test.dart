import 'package:aafanclub_viewer/data/page_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('form submission keeps cookies and follows redirect as GET', () async {
    final requests = <http.Request>[];
    final client = MockClient((request) async {
      requests.add(request);
      if (request.url.path == '/login/') {
        return http.Response(
          '<html>login</html>',
          200,
          headers: const {
            'content-type': 'text/html; charset=utf-8',
            'set-cookie': 'SESSION=anonymous; Path=/',
          },
          request: request,
        );
      }
      if (request.url.path == '/login/setting/') {
        expect(request.method, 'POST');
        expect(request.headers['cookie'], contains('SESSION=anonymous'));
        expect(request.bodyFields, {'NAME': 'AA用户', 'TRIP': 'dummy-trip-key'});
        return http.Response(
          '',
          302,
          headers: const {
            'location': '/',
            'set-cookie': 'SESSION=logged-in; Path=/',
          },
          request: request,
        );
      }
      expect(request.url.path, '/');
      expect(request.method, 'GET');
      expect(request.headers['cookie'], contains('SESSION=logged-in'));
      return http.Response(
        '<html>ok</html>',
        200,
        headers: const {'content-type': 'text/html; charset=utf-8'},
        request: request,
      );
    });
    final source = NetworkPageSource(client: client);

    await source.load(Uri.parse('http://aafanclub.com/login/'));
    final result = await source.submitForm(
      Uri.parse('http://aafanclub.com/login/setting/'),
      {'NAME': 'AA用户', 'TRIP': 'dummy-trip-key'},
    );

    expect(result.uri, Uri.parse('http://aafanclub.com/'));
    expect(requests.map((request) => request.method), ['GET', 'POST', 'GET']);
  });

  test('form submission is restricted to the target site over HTTP', () {
    final source = NetworkPageSource(
      client: MockClient((_) async {
        fail('No request should be sent');
      }),
    );

    expect(
      () => source.submitForm(Uri.parse('https://example.com/post'), {
        'CONTENT': 'test',
      }),
      throwsA(isA<PageSourceException>()),
    );
  });
}
