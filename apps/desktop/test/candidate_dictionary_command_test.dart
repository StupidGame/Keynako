import 'package:flutter_test/flutter_test.dart';
import 'package:keynako_conversion/keynako_conversion.dart';
import 'package:keynako_desktop/input/candidate_dictionary_command.dart';
import 'package:keynako_desktop/input/desktop_personal_dictionary.dart';

void main() {
  test(
    'right-click command waits for a destination and keeps the full reading',
    () async {
      final personal = _MemoryRepository();
      final shared = _CapturingSubmitter();
      expect(await runCandidateDictionaryCommand(const []), isNull);
      expect(personal.entries, isEmpty);

      const word = '仮面ライダー';
      const reading = 'かめんらいだー';
      expect(
        await runCandidateDictionaryCommand([
          candidatePersonalCommand,
          word,
          reading,
        ], personalRepository: personal),
        0,
      );
      expect(personal.entries.single.reading, reading);
      expect(
        await runCandidateDictionaryCommand([
          candidatePersonalCommand,
          word,
          reading,
        ], personalRepository: personal),
        0,
      );
      expect(personal.entries, hasLength(1));
      expect(shared.word, isNull);

      expect(
        await runCandidateDictionaryCommand([
          candidateSharedCommand,
          word,
          reading,
        ], sharedSubmitter: shared),
        0,
      );
      expect(shared.word, word);
      expect(shared.reading, reading);
      expect(
        await runCandidateDictionaryCommand([
          candidateSharedCommand,
          candidatePersonalCommand,
          word,
          reading,
        ]),
        2,
      );
    },
  );
}

class _MemoryRepository implements PersonalDictionaryRepository {
  List<ConversionDictionaryEntry> entries = [];

  @override
  Future<List<ConversionDictionaryEntry>> load() async => entries;

  @override
  Future<void> save(List<ConversionDictionaryEntry> values) async {
    entries = List.of(values);
  }
}

class _CapturingSubmitter implements KeynakoDictionarySubmitter {
  String? word;
  String? reading;

  @override
  Future<bool> submit({
    required String word,
    required String ruby,
    required int importance,
    required List<String> categories,
    String? note,
  }) async {
    this.word = word;
    reading = ruby;
    return true;
  }
}
