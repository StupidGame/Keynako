import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/azookey_hotfix_dictionary.dart';

const Duration azooKeyHotfixCheckInterval = Duration(minutes: 5);
const String keynakoHotfixContentsUrl =
    'https://api.github.com/repos/StupidGame/'
    'keynako_hotfix_dictionary_storage/contents/Dictionary/data_v1.json?ref=main';

bool isAzooKeyHotfixCheckDue(DateTime? lastCheck, DateTime now) {
  return lastCheck == null ||
      !lastCheck.add(azooKeyHotfixCheckInterval).isAfter(now);
}

class AzooKeyHotfixHttpResponse {
  const AzooKeyHotfixHttpResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;
}

typedef AzooKeyHotfixGet = Future<AzooKeyHotfixHttpResponse> Function(
  Uri uri,
  Map<String, String> headers,
);

class AzooKeyHotfixSyncResult {
  const AzooKeyHotfixSyncResult({
    required this.latestTag,
    required this.dictionaryChanged,
    this.dictionary,
  });

  final String? latestTag;
  final bool dictionaryChanged;
  final AzooKeyHotfixDictionary? dictionary;
}

abstract interface class AzooKeyHotfixSynchronizer {
  Future<AzooKeyHotfixSyncResult> checkAndUpdate({String? cachedTag});
}

class AzooKeyHotfixSyncClient implements AzooKeyHotfixSynchronizer {
  AzooKeyHotfixSyncClient({AzooKeyHotfixGet? get}) : _get = get ?? _httpGet;

  final AzooKeyHotfixGet _get;

  @override
  Future<AzooKeyHotfixSyncResult> checkAndUpdate({String? cachedTag}) async {
    final response = await _get(
      Uri.parse(keynakoHotfixContentsUrl),
      const <String, String>{
        HttpHeaders.acceptHeader: 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Keynako hotfix download failed: HTTP ${response.statusCode}',
      );
    }
    final envelope = jsonDecode(response.body);
    if (envelope is! Map ||
        envelope['sha'] is! String ||
        envelope['content'] is! String ||
        envelope['encoding'] != 'base64') {
      throw const FormatException('Keynako hotfix response is malformed.');
    }
    final latestTag = envelope['sha'] as String;
    if (latestTag == cachedTag) {
      return AzooKeyHotfixSyncResult(
        latestTag: latestTag,
        dictionaryChanged: false,
      );
    }
    final content = (envelope['content'] as String).replaceAll('\n', '');
    final decoded = jsonDecode(utf8.decode(base64Decode(content)));
    if (decoded is! Map) {
      throw const FormatException('Keynako hotfix data is not an object.');
    }
    final dictionary = AzooKeyHotfixDictionary.fromJson(
      Map<String, dynamic>.from(decoded),
    );
    return AzooKeyHotfixSyncResult(
      latestTag: latestTag,
      dictionaryChanged: true,
      dictionary: dictionary.metadata.isActive ? dictionary : null,
    );
  }

  static Future<AzooKeyHotfixHttpResponse> _httpGet(
    Uri uri,
    Map<String, String> headers,
  ) async {
    final client = HttpClient()
      ..connectionTimeout = const Duration(seconds: 15);
    try {
      final request = await client.getUrl(uri);
      headers.forEach(request.headers.set);
      final response = await request.close().timeout(
        const Duration(seconds: 30),
      );
      const maximumBytes = 2 * 1024 * 1024;
      if (response.contentLength > maximumBytes) {
        throw const FormatException('Keynako hotfix response exceeds 2 MB.');
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > maximumBytes) {
          throw const FormatException('Keynako hotfix response exceeds 2 MB.');
        }
      }
      return AzooKeyHotfixHttpResponse(
        statusCode: response.statusCode,
        body: utf8.decode(bytes),
      );
    } on TimeoutException {
      throw const HttpException('Keynako hotfix request timed out.');
    } finally {
      client.close(force: true);
    }
  }
}
