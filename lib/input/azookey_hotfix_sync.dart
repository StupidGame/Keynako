import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../models/azookey_hotfix_dictionary.dart';

const Duration azooKeyHotfixCheckInterval = Duration(hours: 24);
const String azooKeyHotfixLatestReleaseUrl =
    'https://api.github.com/repos/azooKey/'
    'azooKey_hotfix_dictionary_storage/releases/latest';
const String azooKeyHotfixReleaseBaseUrl =
    'https://github.com/azooKey/azooKey_hotfix_dictionary_storage/'
    'releases/download';

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
    final latestTag = await getLatestTag();
    if (latestTag == null || latestTag == cachedTag) {
      return AzooKeyHotfixSyncResult(
        latestTag: latestTag,
        dictionaryChanged: false,
      );
    }

    final response = await _get(
      Uri.parse(
        '$azooKeyHotfixReleaseBaseUrl/'
        '${Uri.encodeComponent(latestTag)}/data_v1.json',
      ),
      const <String, String>{},
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'azooKey hotfix download failed: HTTP ${response.statusCode}',
      );
    }
    final decoded = jsonDecode(response.body);
    if (decoded is! Map) {
      throw const FormatException('azooKey hotfix response is not an object.');
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

  Future<String?> getLatestTag() async {
    final response = await _get(Uri.parse(azooKeyHotfixLatestReleaseUrl), {
      HttpHeaders.acceptHeader: 'application/vnd.github+json',
    });
    // azooKey treats non-200 responses as "no latest tag" and records that a
    // check took place. Keep that behavior for protocol compatibility.
    if (response.statusCode != HttpStatus.ok) return null;
    final decoded = jsonDecode(response.body);
    if (decoded is! Map || decoded['tag_name'] is! String) {
      throw const FormatException('azooKey latest release tag is missing.');
    }
    return decoded['tag_name'] as String;
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
        throw const FormatException('azooKey hotfix response exceeds 2 MB.');
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > maximumBytes) {
          throw const FormatException('azooKey hotfix response exceeds 2 MB.');
        }
      }
      return AzooKeyHotfixHttpResponse(
        statusCode: response.statusCode,
        body: utf8.decode(bytes),
      );
    } on TimeoutException {
      throw const HttpException('azooKey hotfix request timed out.');
    } finally {
      client.close(force: true);
    }
  }
}
