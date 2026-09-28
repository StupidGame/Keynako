import 'dart:io';

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
