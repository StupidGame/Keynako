import 'dart:io';

import 'package:keynako_conversion/keynako_conversion.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.length != 1) {
    stderr.writeln(
      'usage: dart run tool/update_bundled_shared_dictionary.dart <output.tsv>',
    );
    exitCode = 64;
    return;
  }

  final output = File(arguments.single);
  try {
    final snapshot = await KeynakoSharedDictionaryClient().fetch();
    await output.parent.create(recursive: true);
    await output.writeAsString(
      NativeSharedDictionaryCodec.encode(snapshot),
      flush: true,
    );
    stdout.writeln(
      'Bundled Dictionary/data_v1.json revision ${snapshot.revision}.',
    );
  } on Object catch (error) {
    if (await output.exists()) {
      stderr.writeln(
        'Could not refresh Dictionary/data_v1.json; using the checked-in '
        'snapshot: $error',
      );
      return;
    }
    rethrow;
  }
}
