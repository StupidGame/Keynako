import 'dart:convert';

import 'package:azookey_flutter/input/azookey_hotfix_sync.dart';
import 'package:flutter_test/flutter_test.dart';

const _activeDictionary = <String, dynamic>{
  'metadata': {
    'status': 'active',
    'name': 'data_v1.json',
    'description': 'test',
    'version': '1.1',
    'last_update': '2026-08-28T12:00:00Z',
  },
  'data': [
    {
      'word': 'Keynako',
      'ruby': 'きーなこ',
      'word_weight': -5.0,
      'importance': 5,
      'lcid': 1288,
      'rcid': 1288,
      'mid': 501,
      'date': '2026-08-28',
      'author': 'Keynako',
    },
  ],
};

String _contentsResponse(
  Map<String, dynamic> dictionary, {
  String sha = 'abc',
}) {
  return jsonEncode({
    'sha': sha,
    'encoding': 'base64',
    'content': base64Encode(utf8.encode(jsonEncode(dictionary))),
  });
}

void main() {
  test('downloads data_v1 from the Keynako repository contents API', () async {
    final requests = <(Uri, Map<String, String>)>[];
    final client = AzooKeyHotfixSyncClient(
      get: (uri, headers) async {
        requests.add((uri, headers));
        return AzooKeyHotfixHttpResponse(
          statusCode: 200,
          body: _contentsResponse(_activeDictionary),
        );
      },
    );

    final result = await client.checkAndUpdate(cachedTag: 'older');

    expect(result.latestTag, 'abc');
    expect(result.dictionaryChanged, isTrue);
    expect(result.dictionary?.entries.single.word, 'Keynako');
    expect(requests.single.$1.toString(), keynakoHotfixContentsUrl);
    expect(requests.single.$2['accept'], 'application/vnd.github+json');
  });

  test(
    'does not decode data again when the repository blob is current',
    () async {
      var requestCount = 0;
      final client = AzooKeyHotfixSyncClient(
        get: (_, _) async {
          requestCount += 1;
          return AzooKeyHotfixHttpResponse(
            statusCode: 200,
            body: _contentsResponse(_activeDictionary, sha: 'current'),
          );
        },
      );

      final result = await client.checkAndUpdate(cachedTag: 'current');

      expect(result.dictionaryChanged, isFalse);
      expect(requestCount, 1);
    },
  );

  test(
    'removes the cached dictionary when Keynako marks it disabled',
    () async {
      final disabled = Map<String, dynamic>.from(_activeDictionary)
        ..['metadata'] = {
          ...Map<String, dynamic>.from(_activeDictionary['metadata']! as Map),
          'status': 'disabled',
        };
      final client = AzooKeyHotfixSyncClient(
        get: (_, _) async => AzooKeyHotfixHttpResponse(
          statusCode: 200,
          body: _contentsResponse(disabled, sha: 'disabled'),
        ),
      );

      final result = await client.checkAndUpdate(cachedTag: 'older');

      expect(result.dictionaryChanged, isTrue);
      expect(result.dictionary, isNull);
      expect(result.latestTag, 'disabled');
    },
  );

  test('checks the live dictionary at a five-minute interval', () {
    final checked = DateTime.utc(2026, 8, 28, 12);

    expect(isAzooKeyHotfixCheckDue(null, checked), isTrue);
    expect(
      isAzooKeyHotfixCheckDue(
        checked,
        checked.add(const Duration(minutes: 4, seconds: 59)),
      ),
      isFalse,
    );
    expect(
      isAzooKeyHotfixCheckDue(checked, checked.add(const Duration(minutes: 5))),
      isTrue,
    );
  });
}
