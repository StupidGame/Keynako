import 'dart:convert';

import 'package:azookey_flutter/input/azookey_hotfix_sync.dart';
import 'package:flutter_test/flutter_test.dart';

const _activeDictionary = <String, dynamic>{
  'metadata': {
    'status': 'active',
    'name': 'data_v1.json',
    'description': 'test',
    'version': '1.0',
    'last_update': '2025-05-04T16:30:00.00',
  },
  'data': [
    {
      'word': 'azooKey',
      'ruby': 'あずーきー',
      'word_weight': -15.0,
      'lcid': 1288,
      'rcid': 1288,
      'mid': 501,
      'date': '2025-05-04',
      'author': '@ensan-hcl',
    },
  ],
};

void main() {
  test(
    'uses the same latest-release and data_v1 protocol as azooKey',
    () async {
      final requests = <(Uri, Map<String, String>)>[];
      final client = AzooKeyHotfixSyncClient(
        get: (uri, headers) async {
          requests.add((uri, headers));
          if (uri.toString() == azooKeyHotfixLatestReleaseUrl) {
            return const AzooKeyHotfixHttpResponse(
              statusCode: 200,
              body: '{"tag_name":"v20260221044324"}',
            );
          }
          return AzooKeyHotfixHttpResponse(
            statusCode: 200,
            body: jsonEncode(_activeDictionary),
          );
        },
      );

      final result = await client.checkAndUpdate(cachedTag: 'older');

      expect(result.latestTag, 'v20260221044324');
      expect(result.dictionaryChanged, isTrue);
      expect(result.dictionary?.entries.single.word, 'azooKey');
      expect(requests, hasLength(2));
      expect(requests.first.$2['accept'], 'application/vnd.github+json');
      expect(
        requests.last.$1.toString(),
        '$azooKeyHotfixReleaseBaseUrl/v20260221044324/data_v1.json',
      );
    },
  );

  test('does not download data_v1 when the cached tag is current', () async {
    var requestCount = 0;
    final client = AzooKeyHotfixSyncClient(
      get: (uri, headers) async {
        requestCount += 1;
        return const AzooKeyHotfixHttpResponse(
          statusCode: 200,
          body: '{"tag_name":"v1"}',
        );
      },
    );

    final result = await client.checkAndUpdate(cachedTag: 'v1');

    expect(result.dictionaryChanged, isFalse);
    expect(requestCount, 1);
  });

  test(
    'removes the cached dictionary when azooKey marks it disabled',
    () async {
      final disabled = Map<String, dynamic>.from(_activeDictionary)
        ..['metadata'] = {
          ...Map<String, dynamic>.from(_activeDictionary['metadata']! as Map),
          'status': 'disabled',
        };
      final client = AzooKeyHotfixSyncClient(
        get: (uri, headers) async =>
            uri.toString() == azooKeyHotfixLatestReleaseUrl
            ? const AzooKeyHotfixHttpResponse(
                statusCode: 200,
                body: '{"tag_name":"v2"}',
              )
            : AzooKeyHotfixHttpResponse(
                statusCode: 200,
                body: jsonEncode(disabled),
              ),
      );

      final result = await client.checkAndUpdate(cachedTag: 'v1');

      expect(result.dictionaryChanged, isTrue);
      expect(result.dictionary, isNull);
      expect(result.latestTag, 'v2');
    },
  );

  test('checks at the same 24-hour interval as azooKey', () {
    final checked = DateTime.utc(2026, 8, 1, 12);

    expect(isAzooKeyHotfixCheckDue(null, checked), isTrue);
    expect(
      isAzooKeyHotfixCheckDue(
        checked,
        checked.add(const Duration(hours: 23, minutes: 59)),
      ),
      isFalse,
    );
    expect(
      isAzooKeyHotfixCheckDue(checked, checked.add(const Duration(hours: 24))),
      isTrue,
    );
  });
}
