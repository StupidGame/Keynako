import 'dart:convert';

import 'package:keynako_conversion/keynako_conversion.dart';
import 'package:test/test.dart';

void main() {
  test('downloads and converts the shared dictionary', () async {
    final dictionary = jsonEncode({
      'metadata': {
        'status': 'active',
        'version': '1.1',
        'last_update': '2026-08-29',
      },
      'data': [
        {
          'word': 'Keynako共有',
          'ruby': 'きーなこ',
          'word_weight': -10.0,
          'lcid': 1285,
          'rcid': 1285,
          'importance': 5,
        },
      ],
    });
    final client = KeynakoSharedDictionaryClient(
      get: (_, _) async => SharedDictionaryHttpResponse(
        statusCode: 200,
        body: jsonEncode({
          'sha': 'abc123',
          'encoding': 'base64',
          'content': base64Encode(utf8.encode(dictionary)),
        }),
      ),
    );

    final snapshot = await client.fetch();

    expect(snapshot.revision, 'abc123');
    expect(snapshot.entries.single.value, 'Keynako共有');
    expect(snapshot.entries.single.importance, 5);
    expect(snapshot.entries.single.wordWeight, -10.0);
    expect(snapshot.entries.single.leftContextId, 1285);
    expect(snapshot.entries.single.rightContextId, 1285);
  });

  test('round trips the native dictionary cache', () {
    const snapshot = SharedDictionarySnapshot(
      revision: 'revision',
      version: '1.1',
      lastUpdate: 'today',
      entries: [
        ConversionDictionaryEntry(
          reading: 'きーなこ',
          value: 'Keynako',
          importance: 4,
          wordWeight: -10,
          leftContextId: 1285,
          rightContextId: 1285,
        ),
      ],
    );

    final decoded = NativeSharedDictionaryCodec.decode(
      NativeSharedDictionaryCodec.encode(snapshot),
    );

    expect(decoded.revision, 'revision');
    expect(decoded.entries.single.reading, 'きーなこ');
    expect(decoded.entries.single.value, 'Keynako');
    expect(decoded.entries.single.importance, 4);
    expect(decoded.entries.single.wordWeight, -10);
    expect(decoded.entries.single.leftContextId, 1285);
    expect(decoded.entries.single.rightContextId, 1285);
  });
}
