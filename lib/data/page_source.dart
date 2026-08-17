import 'dart:async';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

class SourcePage {
  const SourcePage({
    required this.uri,
    required this.bytes,
    required this.headers,
  });

  final Uri uri;
  final Uint8List bytes;
  final Map<String, String> headers;
}

class PageSourceException implements Exception {
  const PageSourceException(this.message);

  final String message;

  @override
  String toString() => message;
}

class NetworkPageSource {
  NetworkPageSource({
    http.Client? client,
    this.timeout = const Duration(seconds: 20),
    this.maxBodyBytes = 8 * 1024 * 1024,
  }) : _client = client ?? http.Client();

  final http.Client _client;
  final Duration timeout;
  final int maxBodyBytes;
  final Map<String, String> _cookies = {};

  Future<SourcePage> load(Uri uri) => _request('GET', uri);

  Future<SourcePage> submitForm(
    Uri uri,
    Map<String, String> fields, {
    Uri? referer,
  }) {
    final host = uri.host.toLowerCase();
    if (uri.scheme != 'http' ||
        (host != 'aafanclub.com' && host != 'www.aafanclub.com')) {
      throw const PageSourceException('只允许向 AA同好会揭示板提交表单');
    }
    return _request('POST', uri, fields: fields, referer: referer);
  }

  Future<SourcePage> _request(
    String initialMethod,
    Uri initialUri, {
    Map<String, String>? fields,
    Uri? referer,
  }) async {
    var uri = initialUri;
    var method = initialMethod;
    var requestFields = fields;
    for (var redirect = 0; redirect <= 8; redirect++) {
      final result = await _sendOnce(
        method,
        uri,
        fields: requestFields,
        referer: referer,
      );
      _rememberCookies(result.headers['set-cookie']);

      if (result.statusCode >= 300 && result.statusCode < 400) {
        final location = result.headers['location'];
        if (location == null || location.isEmpty) {
          throw PageSourceException('网站返回 HTTP ${result.statusCode}，但没有跳转地址');
        }
        if (redirect == 8) {
          throw const PageSourceException('网站跳转次数过多');
        }
        referer = uri;
        uri = uri.resolve(location);
        if (result.statusCode != 307 && result.statusCode != 308) {
          method = 'GET';
          requestFields = null;
        }
        continue;
      }

      if (result.statusCode < 200 || result.statusCode >= 300) {
        throw PageSourceException('网站返回 HTTP ${result.statusCode}');
      }
      return SourcePage(
        uri: result.request?.url ?? uri,
        bytes: result.body,
        headers: result.headers,
      );
    }
    throw const PageSourceException('网站跳转次数过多');
  }

  Future<_RawResponse> _sendOnce(
    String method,
    Uri uri, {
    Map<String, String>? fields,
    Uri? referer,
  }) async {
    if (uri.scheme != 'http' && uri.scheme != 'https') {
      throw const PageSourceException('仅支持 HTTP 或 HTTPS 地址');
    }
    if (uri.host.isEmpty) {
      throw const PageSourceException('地址中缺少网站域名');
    }

    final request =
        http.Request(method, uri)
          ..followRedirects = false
          ..headers.addAll(const {
            'Accept': 'text/html,application/xhtml+xml;q=0.9,*/*;q=0.5',
            'Accept-Language': 'ja,en;q=0.8,zh-CN;q=0.6',
            'User-Agent': 'AAFanclubViewer/0.1 (Windows; Android)',
          });
    if (_cookies.isNotEmpty) {
      request.headers['Cookie'] = _cookies.entries
          .map((item) => '${item.key}=${item.value}')
          .join('; ');
    }
    if (referer != null) request.headers['Referer'] = referer.toString();
    if (fields != null) request.bodyFields = fields;

    late http.StreamedResponse response;
    try {
      response = await _client.send(request).timeout(timeout);
    } on TimeoutException {
      throw const PageSourceException('连接超时，请检查地址或网络');
    } on http.ClientException catch (error) {
      throw PageSourceException('无法连接网站：${error.message}');
    }

    final declaredLength = response.contentLength;
    if (declaredLength != null && declaredLength > maxBodyBytes) {
      throw PageSourceException('页面超过 ${maxBodyBytes ~/ (1024 * 1024)} MB 限制');
    }

    final builder = BytesBuilder(copy: false);
    try {
      await for (final chunk in response.stream.timeout(timeout)) {
        if (builder.length + chunk.length > maxBodyBytes) {
          throw PageSourceException(
            '页面超过 ${maxBodyBytes ~/ (1024 * 1024)} MB 限制',
          );
        }
        builder.add(chunk);
      }
    } on TimeoutException {
      throw const PageSourceException('读取页面超时');
    }

    return _RawResponse(
      request: response.request,
      statusCode: response.statusCode,
      body: builder.takeBytes(),
      headers: response.headers,
    );
  }

  void _rememberCookies(String? header) {
    if (header == null || header.isEmpty) return;
    final starts = RegExp(r'(?:^|,\s*)([A-Za-z0-9_.-]+)=');
    final matches = starts.allMatches(header).toList();
    for (var index = 0; index < matches.length; index++) {
      final match = matches[index];
      final name = match.group(1)!;
      final valueStart = match.end;
      final nextStart =
          index + 1 < matches.length ? matches[index + 1].start : header.length;
      final attributes = header.substring(valueStart, nextStart);
      final value = attributes
          .split(';')
          .first
          .trim()
          .replaceFirst(RegExp(r',$'), '');
      final lower = attributes.toLowerCase();
      if (value.isEmpty || lower.contains('max-age=0')) {
        _cookies.remove(name);
      } else {
        _cookies[name] = value;
      }
    }
  }

  void close() => _client.close();
}

class _RawResponse {
  const _RawResponse({
    required this.request,
    required this.statusCode,
    required this.body,
    required this.headers,
  });

  final http.BaseRequest? request;
  final int statusCode;
  final Uint8List body;
  final Map<String, String> headers;
}
