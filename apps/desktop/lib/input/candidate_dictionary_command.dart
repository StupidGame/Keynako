import 'package:keynako_conversion/keynako_conversion.dart';

import 'desktop_personal_dictionary.dart';

const candidateSharedCommand = '--candidate-dictionary-shared';
const candidatePersonalCommand = '--candidate-dictionary-personal';

Future<int?> runCandidateDictionaryCommand(
  List<String> arguments, {
  PersonalDictionaryRepository? personalRepository,
  KeynakoDictionarySubmitter? sharedSubmitter,
}) async {
  final shared = arguments.contains(candidateSharedCommand);
  final personal = arguments.contains(candidatePersonalCommand);
  if (!shared && !personal) return null;
  if (shared && personal) return 2;
  final commandIndex = arguments.indexOf(
    shared ? candidateSharedCommand : candidatePersonalCommand,
  );
  if (arguments.length != commandIndex + 3) return 2;
  final word = arguments[commandIndex + 1].trim();
  final reading = arguments[commandIndex + 2].trim();
  if (word.isEmpty || reading.isEmpty) return 2;
  try {
    if (shared) {
      final submitter = sharedSubmitter ?? KeynakoDictionarySubmissionClient();
      return await submitter.submit(
            word: word,
            ruby: reading,
            importance: 3,
            categories: const [],
            note: 'Desktop system IME candidate right-click',
          )
          ? 0
          : 1;
    }
    final repository =
        personalRepository ?? DesktopPersonalDictionaryRepository();
    final entries = await repository.load();
    if (entries.any(
      (entry) => entry.value == word && entry.reading == reading,
    )) {
      return 0;
    }
    await repository.save([
      ...entries,
      ConversionDictionaryEntry(reading: reading, value: word, importance: 3),
    ]);
    return 0;
  } on Object {
    return 1;
  }
}
