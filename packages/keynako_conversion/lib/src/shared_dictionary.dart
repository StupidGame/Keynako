import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'conversion_options.dart';

const String keynakoSharedDictionaryContentsUrl =
    'https://api.github.com/repos/StupidGame/'
    'keynako_hotfix_dictionary_storage/contents/Dictionary/data_v1.json?ref=main';

class SharedDictionarySnapshot {
  const SharedDictionarySnapshot({
    required this.revision,
    required this.version,
    required this.lastUpdate,
    required this.entries,
  });

  final String revision;
  final String version;
  final String lastUpdate;
  final List<ConversionDictionaryEntry> entries;
}

class SharedDictionaryHttpResponse {
  const SharedDictionaryHttpResponse({
    required this.statusCode,
    required this.body,
  });

  final int statusCode;
  final String body;
}

typedef SharedDictionaryGet = Future<SharedDictionaryHttpResponse> Function(
  Uri uri,
  Map<String, String> headers,
);

class KeynakoSharedDictionaryClient {
  KeynakoSharedDictionaryClient({SharedDictionaryGet? get})
    : _get = get ?? _httpGet;

  final SharedDictionaryGet _get;

  Future<SharedDictionarySnapshot> fetch() async {
    final response = await _get(
      Uri.parse(keynakoSharedDictionaryContentsUrl),
      const {
        HttpHeaders.acceptHeader: 'application/vnd.github+json',
        'X-GitHub-Api-Version': '2022-11-28',
      },
    );
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw HttpException(
        'Keynako shared dictionary download failed: '
        'HTTP ${response.statusCode}',
      );
    }
    final envelope = jsonDecode(response.body);
    if (envelope is! Map ||
        envelope['sha'] is! String ||
        envelope['content'] is! String ||
        envelope['encoding'] != 'base64') {
      throw const FormatException(
        'Keynako shared dictionary response is malformed.',
      );
    }
    final encoded = (envelope['content'] as String).replaceAll('\n', '');
    final decoded = jsonDecode(utf8.decode(base64Decode(encoded)));
    if (decoded is! Map || decoded['metadata'] is! Map) {
      throw const FormatException('Keynako shared dictionary is malformed.');
    }
    final metadata = Map<String, dynamic>.from(decoded['metadata'] as Map);
    if (metadata['status'] != 'active' || decoded['data'] is! List) {
      throw const FormatException('Keynako shared dictionary is not active.');
    }
    final entries = <ConversionDictionaryEntry>[];
    for (final item in decoded['data'] as List) {
      if (item is! Map) {
        throw const FormatException(
          'Keynako shared dictionary entry is malformed.',
        );
      }
      final entry = Map<String, dynamic>.from(item);
      final reading = entry['ruby'];
      final value = entry['word'];
      final weight = entry['word_weight'];
      if (reading is! String || value is! String || weight is! num) {
        throw const FormatException(
          'Keynako shared dictionary entry is malformed.',
        );
      }
      final explicitImportance = entry['importance'];
      final importance = explicitImportance is num
          ? explicitImportance.toInt().clamp(1, 5)
          : ((weight.toDouble() + 17.5) / 2.5).round().clamp(1, 5);
      entries.add(
        ConversionDictionaryEntry(
          reading: reading,
          value: value,
          importance: importance,
        ),
      );
    }
    entries.sort((left, right) {
      final reading = left.reading.compareTo(right.reading);
      return reading != 0
          ? reading
          : right.importance.compareTo(left.importance);
    });
    return SharedDictionarySnapshot(
      revision: envelope['sha'] as String,
      version: metadata['version']?.toString() ?? 'unknown',
      lastUpdate: metadata['last_update']?.toString() ?? 'unknown',
      entries: List.unmodifiable(entries),
    );
  }

  static Future<SharedDictionaryHttpResponse> _httpGet(
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
        throw const FormatException('Keynako shared dictionary exceeds 2 MB.');
      }
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
        if (bytes.length > maximumBytes) {
          throw const FormatException(
            'Keynako shared dictionary exceeds 2 MB.',
          );
        }
      }
      return SharedDictionaryHttpResponse(
        statusCode: response.statusCode,
        body: utf8.decode(bytes),
      );
    } on TimeoutException {
      throw const HttpException('Keynako shared dictionary request timed out.');
    } finally {
      client.close(force: true);
    }
  }
}

class NativeSharedDictionaryCodec {
  const NativeSharedDictionaryCodec._();

  static String encode(SharedDictionarySnapshot snapshot) {
    String clean(String value) =>
        value.replaceAll('\t', ' ').replaceAll('\r', ' ').replaceAll('\n', ' ');
    final output = StringBuffer(
      '# keynako-shared-dictionary-v1\t${clean(snapshot.revision)}\t'
      '${clean(snapshot.version)}\t${clean(snapshot.lastUpdate)}\n',
    );
    for (final entry in snapshot.entries) {
      output.writeln(
        '${entry.importance.clamp(1, 5)}\t'
        '${clean(entry.reading)}\t${clean(entry.value)}',
      );
    }
    return output.toString();
  }

  static SharedDictionarySnapshot decode(String value) {
    final lines = const LineSplitter().convert(value);
    if (lines.isEmpty) {
      throw const FormatException('Shared dictionary cache is empty.');
    }
    final header = lines.first.split('\t');
    if (header.isEmpty || header.first != '# keynako-shared-dictionary-v1') {
      throw const FormatException('Shared dictionary cache is malformed.');
    }
    final entries = <ConversionDictionaryEntry>[];
    for (final line in lines.skip(1)) {
      if (line.trim().isEmpty || line.startsWith('#')) continue;
      final fields = line.split('\t');
      if (fields.length != 3) continue;
      final importance = int.tryParse(fields[0]);
      if (importance == null || fields[1].isEmpty || fields[2].isEmpty) {
        continue;
      }
      entries.add(
        ConversionDictionaryEntry(
          reading: fields[1],
          value: fields[2],
          importance: importance.clamp(1, 5),
        ),
      );
    }
    return SharedDictionarySnapshot(
      revision: header.length > 1 ? header[1] : 'unknown',
      version: header.length > 2 ? header[2] : 'unknown',
      lastUpdate: header.length > 3 ? header[3] : 'unknown',
      entries: List.unmodifiable(entries),
    );
  }
}
