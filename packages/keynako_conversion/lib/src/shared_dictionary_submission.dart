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
  });

  final int statusCode;
  final String body;
}

typedef KeynakoDictionaryPost =
    Future<KeynakoDictionarySubmissionResponse> Function(Uri uri, String body);

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
  }) : _endpoint = endpoint.trim(),
       _post = post ?? _httpPost;

  final String _endpoint;
  final KeynakoDictionaryPost _post;

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

    final response = await _post(
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
      );
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
}
