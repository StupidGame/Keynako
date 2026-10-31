import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:keynako_desktop/input/official_dictionary.dart';

void main() {
  const sha = '0123456789012345678901234567890123456789';
  late Directory cache;
  setUp(
    () async => cache = await Directory.systemTemp.createTemp(
      'official-dictionary-test',
    ),
  );
  tearDown(() async => cache.delete(recursive: true));

  List<int> archiveWith(String name, List<int> bytes) {
    final archive = Archive()..addFile(ArchiveFile(name, bytes.length, bytes));
    return ZipEncoder().encode(archive);
  }

  test('rejects traversal without writing outside staging', () async {
    final staging = await cache.createTemp('staging');
    final bytes = archiveWith('azooKey_dictionary_storage-$sha/../escaped', [
      1,
    ]);
    await expectLater(
      OfficialDictionary.extract(bytes, sha, staging),
      throwsFormatException,
    );
    expect(await File('${cache.path}/escaped').exists(), isFalse);
  });

  test('rejects an archive from a different revision', () async {
    final bytes = archiveWith(
      'azooKey_dictionary_storage-wrong/Dictionary/mm.binary',
      [1],
    );
    await expectLater(
      OfficialDictionary.extract(bytes, sha, cache),
      throwsFormatException,
    );
  });

  test('invalid archive does not replace current snapshot', () async {
    final current = File('${cache.path}/current');
    await current.writeAsString(sha);
    final staging = await cache.createTemp('staging');
    await expectLater(
      OfficialDictionary.extract([1, 2, 3], sha, staging),
      throwsA(anything),
    );
    expect(await current.readAsString(), sha);
  });

  test('a recent successful check performs no network requests', () async {
    await File('${cache.path}/checked').writeAsString(sha);
    final client = HttpClient()..findProxy = (_) => 'PROXY 127.0.0.1:1';
    addTearDown(client.close);
    await OfficialDictionary(cache: cache, client: client).refreshIfDue();
    expect(await File('${cache.path}/attempt').exists(), isFalse);
  });

  test('a failed update is throttled for one hour', () async {
    await File('${cache.path}/attempt').writeAsString('');
    final client = HttpClient()..findProxy = (_) => 'PROXY 127.0.0.1:1';
    addTearDown(client.close);
    await OfficialDictionary(cache: cache, client: client).refreshIfDue();
    expect(await File('${cache.path}/checked').exists(), isFalse);
  });

  test('validates the real bundled official dictionary', () async {
    await OfficialDictionary.validate(
      Directory('../../third_party/azookey_dictionary_storage'),
    );
  });
}
