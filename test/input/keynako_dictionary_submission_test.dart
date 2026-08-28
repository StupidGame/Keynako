import 'dart:convert';

import 'package:azookey_flutter/input/keynako_dictionary_submission.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'posts the shared conversion and importance to the Keynako gateway',
    () async {
      Uri? receivedUri;
      String? receivedBody;
      final client = KeynakoDictionarySubmissionClient(
        endpoint: 'https://example.com/submissions',
        post: (uri, body) async {
          receivedUri = uri;
          receivedBody = body;
          return const KeynakoDictionarySubmissionResponse(
            statusCode: 200,
            body: '{"ok":true}',
          );
        },
      );

      final result = await client.submit(
        word: '小倉',
        ruby: 'おぐら',
        importance: 5,
        categories: const ['場所・建物などの名前'],
      );

      expect(result, isTrue);
      expect(receivedUri, Uri.parse('https://example.com/submissions'));
      expect(jsonDecode(receivedBody!), {
        'word': '小倉',
        'ruby': 'おぐら',
        'importance': 5,
        'categories': ['場所・建物などの名前'],
        'source': 'Keynako',
        'app_version': '3.0.1',
      });
    },
  );

  test('does not submit without a configured HTTPS gateway', () async {
    var called = false;
    final client = KeynakoDictionarySubmissionClient(
      endpoint: '',
      post: (_, _) async {
        called = true;
        return const KeynakoDictionarySubmissionResponse(
          statusCode: 200,
          body: '',
        );
      },
    );

    expect(
      await client.submit(
        word: '単語',
        ruby: 'たんご',
        importance: 3,
        categories: const [],
      ),
      isFalse,
    );
    expect(called, isFalse);
  });
}
