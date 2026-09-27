import 'dart:async';
import 'dart:io';

import 'package:keynako_conversion/keynako_conversion.dart';
import 'package:test/test.dart';

void main() {
  test('restarts the helper after a timed out response', () async {
    final directory = await Directory.systemTemp.createTemp('keynako_zenzai_');
    addTearDown(() => directory.delete(recursive: true));
    final script = File('${directory.path}/helper.sh');
    await script.writeAsString('''
marker="\$0.marker"
if [ ! -f "\$marker" ]; then
  : > "\$marker"
  printf 'READY\\n'
  read line
  sleep 3
else
  printf 'READY\\n'
  while read line; do
    if [ "\$line" = 'QUIT' ]; then exit 0; fi
    printf '41\\n'
  done
fi
''');
    final engine = ZenzaiProcessEngine(
      executablePath: '/bin/sh',
      modelPath: script.path,
      requestTimeout: const Duration(milliseconds: 250),
    );
    addTearDown(engine.close);

    await expectLater(
      engine.generate(const ZenzaiRequest(reading: 'あ')),
      throwsA(isA<TimeoutException>()),
    );
    expect(await engine.generate(const ZenzaiRequest(reading: 'あ')), 'A');
    await engine.close();
    expect(await engine.generate(const ZenzaiRequest(reading: 'あ')), isNull);
  }, skip: Platform.isWindows ? 'Requires /bin/sh' : null);
}
