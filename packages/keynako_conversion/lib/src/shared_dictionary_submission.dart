import 'dart:async';
import 'dart:convert';
import 'dart:io';

const String keynakoDictionarySubmissionUrl = String.fromEnvironment(
  'KEYNAKO_DICTIONARY_SUBMISSION_URL',
);

class KeynakoDictionarySubmissionResponse {
  const KeynakoDictionarySubmissionResponse({
    required this.statusCode,
    required this.body,
    this.redirectLocation,
  });

  final int statusCode;
  final String body;
  final String? redirectLocation;
}

typedef KeynakoDictionaryPost =
    Future<KeynakoDictionarySubmissionResponse> Function(Uri uri, String body);
typedef KeynakoDictionaryGet =
    Future<KeynakoDictionarySubmissionResponse> Function(Uri uri);

abstract interface class KeynakoDictionarySubmitter {
  Future<bool> submit({
    required String word,
    required String ruby,
    required int importance,
    required List<String> categories,
    String? note,
  });
}

class KeynakoDictionarySubmissionClient implements KeynakoDictionarySubmitter {
  KeynakoDictionarySubmissionClient({
    String endpoint = keynakoDictionarySubmissionUrl,
    KeynakoDictionaryPost? post,
    KeynakoDictionaryGet? get,
  }) : _endpoint = endpoint.trim(),
       _post = post ?? _httpPost,
       _get = get ?? _httpGet;

  final String _endpoint;
  final KeynakoDictionaryPost _post;
  final KeynakoDictionaryGet _get;

  @override
  Future<bool> submit({
    required String word,
    required String ruby,
    required int importance,
    required List<String> categories,
    String? note,
  }) async {
    final uri = Uri.tryParse(_endpoint);
    if (uri == null || uri.scheme != 'https' || !uri.hasAuthority) return false;

    var response = await _post(
      uri,
      jsonEncode({
        'word': word.trim(),
        'ruby': ruby.trim(),
        'importance': importance.clamp(1, 5),
        'categories': categories,
        if (note?.trim().isNotEmpty ?? false) 'note': note!.trim(),
        'source': 'Keynako',
        'app_version': '3.1.0',
      }),
    );
    // Apps Script executes doPost, then redirects its ContentService response
    // to a one-time URL. Fetch only that response; never repeat the POST.
    if (uri.host == 'script.google.com' &&
        (response.statusCode == HttpStatus.found ||
            response.statusCode == HttpStatus.seeOther)) {
      final location = response.redirectLocation;
      final redirected = location == null ? null : uri.resolve(location);
      if (redirected == null ||
          redirected.scheme != 'https' ||
          redirected.host != 'script.googleusercontent.com') {
        return false;
      }
      response = await _get(redirected);
    }
    if (response.statusCode < 200 || response.statusCode >= 300) return false;
    if (response.body.trim().isEmpty) return true;
    try {
      final decoded = jsonDecode(response.body);
      return decoded is! Map || decoded['ok'] != false;
    } on FormatException {
      return false;
    }
  }

  static Future<KeynakoDictionarySubmissionResponse> _httpPost(
    Uri uri,
    String body,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.postUrl(uri);
      // Redirects can turn a POST into a GET and report a false success.
      // The configured gateway must be its final HTTPS endpoint.
      request.followRedirects = false;
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'Keynako 3.1.0');
      request.write(body);
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      return await _readResponse(response);
    } on TimeoutException {
      return const KeynakoDictionarySubmissionResponse(
        statusCode: HttpStatus.requestTimeout,
        body: '',
      );
    } on SocketException {
      return const KeynakoDictionarySubmissionResponse(
        statusCode: HttpStatus.serviceUnavailable,
        body: '',
      );
    } finally {
      client.close(force: true);
    }
  }

  static Future<KeynakoDictionarySubmissionResponse> _httpGet(Uri uri) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri);
      request.followRedirects = false;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      return await _readResponse(response);
    } on TimeoutException {
      return const KeynakoDictionarySubmissionResponse(
        statusCode: HttpStatus.requestTimeout,
        body: '',
      );
    } on SocketException {
      return const KeynakoDictionarySubmissionResponse(
        statusCode: HttpStatus.serviceUnavailable,
        body: '',
      );
    } finally {
      client.close(force: true);
    }
  }

  static Future<KeynakoDictionarySubmissionResponse> _readResponse(
    HttpClientResponse response,
  ) async {
    const maximumBytes = 64 * 1024;
    final bytes = <int>[];
    await for (final chunk in response.timeout(const Duration(seconds: 30))) {
      bytes.addAll(chunk);
      if (bytes.length > maximumBytes) {
        throw const FormatException('Submission response exceeds 64 KB.');
      }
    }
    return KeynakoDictionarySubmissionResponse(
      statusCode: response.statusCode,
      body: utf8.decode(bytes),
      redirectLocation: response.headers.value(HttpHeaders.locationHeader),
    );
  }
}
