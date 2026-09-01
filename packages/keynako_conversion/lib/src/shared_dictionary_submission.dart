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
        'app_version': '3.0.1',
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
      request.followRedirects = true;
      request.headers.contentType = ContentType.json;
      request.headers.set(HttpHeaders.acceptHeader, 'application/json');
      request.headers.set(HttpHeaders.userAgentHeader, 'Keynako 3.0.1');
      request.write(body);
      var response = await request.close().timeout(const Duration(seconds: 30));
      final redirect = response.headers.value(HttpHeaders.locationHeader);
      if (redirect != null &&
          const {
            HttpStatus.movedPermanently,
            HttpStatus.found,
            HttpStatus.seeOther,
          }.contains(response.statusCode)) {
        await response.drain<void>();
        final redirectRequest = await client.getUrl(uri.resolve(redirect));
        redirectRequest.followRedirects = true;
        redirectRequest.headers.set(
          HttpHeaders.acceptHeader,
          'application/json',
        );
        redirectRequest.headers.set(
          HttpHeaders.userAgentHeader,
          'Keynako 3.0.1',
        );
        response = await redirectRequest.close().timeout(
          const Duration(seconds: 30),
        );
      }
      const maximumBytes = 64 * 1024;
      final bytes = <int>[];
      await for (final chunk in response) {
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
