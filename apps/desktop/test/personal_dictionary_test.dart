import 'dart:io';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:keynako_conversion/keynako_conversion.dart';
import 'package:keynako_desktop/app.dart';
import 'package:keynako_desktop/input/desktop_input_controller.dart';
import 'package:keynako_desktop/input/desktop_personal_dictionary.dart';

void main() {
  test('personal entries survive reload and affect conversion', () async {
    final directory = await Directory.systemTemp.createTemp(
      'keynako-personal-',
    );
    try {
      final repository = DesktopPersonalDictionaryRepository(
        file: File('${directory.path}/user_dictionary.tsv'),
      );
      final controller = DesktopInputController(
        personalDictionaryRepository: repository,
      );
      await controller.initializePersonalDictionary();
      expect(controller.personalDictionary, isEmpty);
      await controller.savePersonalDictionary(const [
        ConversionDictionaryEntry(
          reading: 'きゃわわ',
          value: '独自の単語',
          importance: 5,
        ),
      ]);
      controller.updateRawInput('kyawawa');
      expect(
        controller.candidates.any((candidate) => candidate.text == '独自の単語'),
        isTrue,
      );

      final reloaded = DesktopInputController(
        personalDictionaryRepository: repository,
      );
      await reloaded.initializePersonalDictionary();
      expect(reloaded.personalDictionary.single.value, '独自の単語');
      await reloaded.savePersonalDictionary(const []);
      expect(await repository.load(), isEmpty);
      controller.dispose();
      reloaded.dispose();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test(
    'right-click candidate saves locally without duplicate entries',
    () async {
      final repository = _MemoryPersonalDictionaryRepository();
      final controller = DesktopInputController(
        personalDictionaryRepository: repository,
      );
      controller.updateRawInput('nihongo');
      final index = controller.candidates.indexWhere(
        (candidate) => candidate.text == '日本語',
      );

      expect(await controller.saveCandidateToPersonalDictionary(index), isTrue);
      expect(repository.entries.single.reading, 'にほんご');
      expect(repository.entries.single.value, '日本語');
      expect(controller.candidateShareStatus, '個人辞書に登録しました');
      expect(await controller.saveCandidateToPersonalDictionary(index), isTrue);
      expect(repository.entries, hasLength(1));
      expect(controller.candidateShareStatus, '個人辞書に登録済みです');
      controller.dispose();
    },
  );

  testWidgets('right-click menu waits for a dictionary choice', (tester) async {
    final repository = _MemoryPersonalDictionaryRepository();
    final controller = DesktopInputController(
      personalDictionaryRepository: repository,
    );
    controller.updateRawInput('nihongo');
    final index = controller.candidates.indexWhere(
      (candidate) => candidate.text == '日本語',
    );
    await tester.pumpWidget(KeynakoDesktopApp(controller: controller));
    final candidate = find.byKey(Key('candidate-$index'));
    final mouse = await tester.createGesture(
      kind: PointerDeviceKind.mouse,
      buttons: kSecondaryMouseButton,
    );
    await mouse.down(tester.getCenter(candidate));
    await mouse.up();
    await tester.pumpAndSettle();

    expect(find.text('共通辞書に送る'), findsOneWidget);
    expect(find.text('個人辞書に登録'), findsOneWidget);
    expect(repository.entries, isEmpty);
    await tester.tap(find.text('個人辞書に登録'));
    await tester.pumpAndSettle();
    expect(repository.entries.single.value, '日本語');
    await mouse.removePointer();
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('system IME choice saves the passed word and full reading', (
    tester,
  ) async {
    final repository = _MemoryPersonalDictionaryRepository();
    final submitter = _CapturingSubmitter();
    final controller = DesktopInputController(
      personalDictionaryRepository: repository,
      sharedDictionarySubmitter: submitter,
    );
    await tester.pumpWidget(
      KeynakoDesktopApp(
        controller: controller,
        candidateWord: '仮面ライダー',
        candidateReading: 'かめんらいだー',
      ),
    );
    expect(repository.entries, isEmpty);
    await tester.tap(find.byKey(const Key('candidate-register-personal')));
    await tester.pumpAndSettle();
    expect(repository.entries.single.reading, 'かめんらいだー');
    expect(repository.entries.single.value, '仮面ライダー');
    expect(submitter.word, isNull);
    await tester.tap(find.byKey(const Key('candidate-register-shared')));
    await tester.pumpAndSettle();
    expect(submitter.word, '仮面ライダー');
    expect(submitter.reading, 'かめんらいだー');
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });

  testWidgets('dictionary opens from IME and adds, edits, deletes a word', (
    tester,
  ) async {
    final controller = DesktopInputController(
      personalDictionaryRepository: _MemoryPersonalDictionaryRepository(),
    );
    await tester.pumpWidget(KeynakoDesktopApp(controller: controller));
    await tester.tap(find.byKey(const Key('personal-dictionary-open')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('dictionary-add')));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const Key('dictionary-reading')),
      'kyawawa',
    );
    await tester.enterText(find.byKey(const Key('dictionary-word')), '独自の単語');
    await tester.tap(find.byKey(const Key('dictionary-save')));
    await tester.pumpAndSettle();
    expect(controller.personalDictionary.single.reading, 'きゃわわ');
    expect(find.text('独自の単語'), findsOneWidget);

    await tester.tap(find.byKey(const Key('dictionary-entry-0')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('dictionary-word')), '編集後の単語');
    await tester.tap(find.byKey(const Key('dictionary-save')));
    await tester.pumpAndSettle();
    expect(controller.personalDictionary.single.value, '編集後の単語');

    await tester.tap(find.byTooltip('削除'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('削除').last);
    await tester.pumpAndSettle();
    expect(controller.personalDictionary, isEmpty);
    await tester.pumpWidget(const SizedBox.shrink());
    controller.dispose();
  });
}

class _MemoryPersonalDictionaryRepository
    implements PersonalDictionaryRepository {
  List<ConversionDictionaryEntry> entries = const [];

  @override
  Future<List<ConversionDictionaryEntry>> load() async => entries;

  @override
  Future<void> save(List<ConversionDictionaryEntry> value) async {
    entries = List.of(value);
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
