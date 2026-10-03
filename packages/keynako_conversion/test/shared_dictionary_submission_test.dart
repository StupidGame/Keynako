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
      'app_version': '3.1.0',
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

  test('reads an Apps Script response after its one-time redirect', () async {
    var posts = 0;
    Uri? responseUri;
    final client = KeynakoDictionarySubmissionClient(
      endpoint: 'https://script.google.com/macros/s/deployment/exec',
      post: (uri, body) async {
        posts += 1;
        return const KeynakoDictionarySubmissionResponse(
          statusCode: 302,
          body: '',
          redirectLocation:
              'https://script.googleusercontent.com/macros/echo?token=1',
        );
      },
      get: (uri) async {
        responseUri = uri;
        return const KeynakoDictionarySubmissionResponse(
          statusCode: 200,
          body: '{"ok":true}',
        );
      },
    );

    expect(
      await client.submit(
        word: '仮面ライダー',
        ruby: 'かめんらいだー',
        importance: 3,
        categories: const [],
      ),
      isTrue,
    );
    expect(posts, 1);
    expect(
      responseUri,
      Uri.parse('https://script.googleusercontent.com/macros/echo?token=1'),
    );
  });

  test('rejects an Apps Script redirect to another host', () async {
    var fetched = false;
    final client = KeynakoDictionarySubmissionClient(
      endpoint: 'https://script.google.com/macros/s/deployment/exec',
      post: (uri, body) async => const KeynakoDictionarySubmissionResponse(
        statusCode: 302,
        body: '',
        redirectLocation: 'https://example.com/collect',
      ),
      get: (uri) async {
        fetched = true;
        return const KeynakoDictionarySubmissionResponse(
          statusCode: 200,
          body: '{"ok":true}',
        );
      },
    );

    expect(
      await client.submit(
        word: '仮面ライダー',
        ruby: 'かめんらいだー',
        importance: 3,
        categories: const [],
      ),
      isFalse,
    );
    expect(fetched, isFalse);
  });
}
