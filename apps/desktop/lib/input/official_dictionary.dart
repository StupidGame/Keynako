import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';

/// Direct official downloads, shared by the app and system IME helper commands.
class OfficialDictionary {
  OfficialDictionary({Directory? cache, this._client})
    : cache = cache ?? defaultCache();

  final Directory cache;
  final HttpClient? _client;
  static final _shaPattern = RegExp(r'^[0-9a-f]{40}$');

  static Directory defaultCache() {
    final env = Platform.environment;
    final String base;
    if (Platform.isWindows) {
      base = '${env['LOCALAPPDATA'] ?? Directory.systemTemp.path}/Keynako';
    } else if (Platform.isMacOS) {
      base = '${env['HOME']}/Library/Application Support/Keynako';
    } else {
      base = '${env['XDG_DATA_HOME'] ?? '${env['HOME']}/.local/share'}/keynako';
    }
    return Directory('$base/official_dictionary');
  }

  Future<void> refreshIfDue() async {
    await cache.create(recursive: true);
    final lock = await File('${cache.path}/update.lock')
        .open(mode: FileMode.append);
    final client = _client ?? HttpClient();
    client.connectionTimeout = const Duration(seconds: 15);
    try {
      await lock.lock();
      Future<bool> recent(String name, Duration interval) async {
        final file = File('${cache.path}/$name');
        return await file.exists() &&
            DateTime.now().difference(await file.lastModified()) < interval;
      }

      if (await recent('checked', const Duration(days: 1)) ||
          await recent('attempt', const Duration(hours: 1))) {
        return;
      }
      await File('${cache.path}/attempt').writeAsString('');
      Future<List<int>> fetch(String url, int limit) async {
        final request = await client.getUrl(Uri.parse(url));
        request.headers.set(HttpHeaders.userAgentHeader, 'Keynako-dictionary');
        final response = await request.close();
        if (response.statusCode != 200) {
          throw const HttpException('Dictionary download failed');
        }
        final bytes = <int>[];
        await for (final chunk in response.timeout(
          const Duration(seconds: 60),
        )) {
          if (bytes.length + chunk.length > limit) {
            throw const FormatException('Dictionary too large');
          }
          bytes.addAll(chunk);
        }
        return bytes;
      }

      final metadata = jsonDecode(
        utf8.decode(
          await fetch(
            'https://api.github.com/repos/azooKey/azooKey_dictionary_storage/commits/main',
            1024 * 1024,
          ),
        ),
      ) as Map<String, dynamic>;
      final sha = metadata['sha'] as String;
      if (!_shaPattern.hasMatch(sha)) {
        throw const FormatException('Invalid dictionary revision');
      }
      final current = File('${cache.path}/current');
      if (!await current.exists() ||
          (await current.readAsString()).trim() != sha) {
        final bytes = await fetch(
          'https://codeload.github.com/azooKey/azooKey_dictionary_storage/zip/$sha',
          128 * 1024 * 1024,
        );
        final staging = await cache.createTemp('staging-');
        try {
          await extract(bytes, sha, staging);
          final destination = Directory('${cache.path}/$sha');
          if (!await destination.exists()) {
            await staging.rename(destination.path);
          }
          final pending = File('${cache.path}/current.$pid.tmp');
          await pending.writeAsString(sha, flush: true);
          if (Platform.isWindows && await current.exists()) {
            final previous = File('${cache.path}/previous');
            if (await previous.exists()) await previous.delete();
            await current.rename(previous.path);
            try {
              await pending.rename(current.path);
            } on Object {
              await previous.rename(current.path);
              rethrow;
            }
          } else {
            await pending.rename(current.path);
          }
        } finally {
          if (await staging.exists()) await staging.delete(recursive: true);
        }
      }
      await File('${cache.path}/checked').writeAsString(sha, flush: true);
    } finally {
      await lock.close();
      if (_client == null) client.close(force: true);
    }
  }

  static Future<void> extract(
    List<int> bytes,
    String sha,
    Directory staging,
  ) async {
    if (!_shaPattern.hasMatch(sha)) {
      throw const FormatException('Invalid revision');
    }
    final archive = ZipDecoder().decodeBytes(bytes, verify: true);
    final prefix = 'azooKey_dictionary_storage-$sha/';
    var total = 0;
    if (archive.length > 5000) {
      throw const FormatException('Too many dictionary files');
    }
    for (final entry in archive) {
      total += entry.size;
      if (!entry.name.startsWith(prefix) ||
          entry.isSymbolicLink ||
          total > 256 * 1024 * 1024) {
        throw const FormatException('Invalid dictionary archive');
      }
      final relative = entry.name.substring(prefix.length);
      if (relative.contains('\\') ||
          relative.split('/').any((part) => part == '..' || part == '.')) {
        throw const FormatException('Invalid dictionary path');
      }
      if (!entry.isFile ||
          !(relative.startsWith('Dictionary/') || relative == 'LICENSE')) {
        continue;
      }
      final file = File('${staging.path}/$relative');
      await file.parent.create(recursive: true);
      final content = entry.content;
      if (content.length != entry.size || getCrc32(content) != entry.crc32) {
        throw const FormatException('Dictionary checksum mismatch');
      }
      await file.writeAsBytes(content);
    }
    await validate(staging);
  }

  static Future<void> validate(Directory repo) async {
    if (!(await File(
      '${repo.path}/LICENSE',
    ).readAsString()).contains('Apache License')) {
      throw const FormatException('Dictionary license changed');
    }
    final root = '${repo.path}/Dictionary';
    Future<void> binary(String path, int alignment, [int minimum = 1]) async {
      final size = await File('$root/$path').length();
      if (size < minimum || size % alignment != 0) {
        throw FormatException('Invalid dictionary: $path');
      }
    }

    await binary('louds/charID.chid', 1);
    final characters = (await File('$root/louds/charID.chid').readAsString()).runes;
    if (characters.length > 256 || characters.toSet().length != characters.length) {
      throw const FormatException('Invalid dictionary character IDs');
    }
    await binary('mm.binary', 4, 1008020);
    for (var cid = 0; cid < 1319; cid++) {
      await binary('cb/$cid.binary', 8);
    }
    var shards = 0;
    await for (final file in Directory('$root/louds').list()) {
      if (!file.path.endsWith('.louds')) continue;
      shards++;
      final stem = file.path
          .split(Platform.pathSeparator)
          .last
          .replaceFirst(RegExp(r'\.louds$'), '');
      await binary('louds/$stem.louds', 8);
      await binary('louds/$stem.loudschars2', 1);
      await binary('louds/${stem}0.loudstxt3', 1);
    }
    if (shards == 0) throw const FormatException('No dictionary shards');
  }
}
