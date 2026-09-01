import 'dart:convert';

import 'package:keynako_conversion/keynako_conversion.dart';
import 'package:test/test.dart';

void main() {
  test('submits a candidate to the configured HTTPS gateway', () async {
    Uri? requestedUri;
    Map<String, dynamic>? requestedBody;
    final client = KeynakoDictionarySubmissionClient(
      endpoint: 'https://example.com/dictionary',
      post: (uri, body) async {
        requestedUri = uri;
        requestedBody = jsonDecode(body) as Map<String, dynamic>;
        return const KeynakoDictionarySubmissionResponse(
          statusCode: 200,
          body: '{"ok":true}',
        );
      },
    );

    final sent = await client.submit(
      word: ' 日本語 ',
      ruby: ' にほんご ',
      importance: 3,
      categories: const [],
      note: 'Desktop candidate right-click',
    );

    expect(sent, isTrue);
    expect(requestedUri, Uri.parse('https://example.com/dictionary'));
    expect(requestedBody, {
      'word': '日本語',
      'ruby': 'にほんご',
      'importance': 3,
      'categories': <dynamic>[],
      'note': 'Desktop candidate right-click',
      'source': 'Keynako',
      'app_version': '3.0.1',
    });
  });

  test('rejects a non-HTTPS gateway without posting', () async {
    var posted = false;
    final client = KeynakoDictionarySubmissionClient(
      endpoint: 'http://example.com/dictionary',
      post: (uri, body) async {
        posted = true;
        return const KeynakoDictionarySubmissionResponse(
          statusCode: 200,
          body: '',
        );
      },
    );

    expect(
      await client.submit(
        word: '日本語',
        ruby: 'にほんご',
        importance: 3,
        categories: const [],
      ),
      isFalse,
    );
    expect(posted, isFalse);
  });
}
