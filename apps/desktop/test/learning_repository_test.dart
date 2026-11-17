import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keynako_desktop/input/desktop_input_controller.dart';
import 'package:keynako_desktop/input/desktop_learning.dart';

void main() {
  test(
    'resetting a prediction persists without removing unrelated learning',
    () async {
      final directory = await Directory.systemTemp.createTemp('keynako-reset-');
      final repository = DesktopLearningRepository(
        file: File('${directory.path}/learning.tsv'),
      );
      final controller = DesktopInputController(learningRepository: repository);
      try {
        await repository.save({
          'かめんらいだー\t仮面ライダー': 32,
          'context:4eca\tかめんらいだー\t仮面ライダー': 16,
          'ねこ\t猫': 8,
        });
        await controller.initializeLearning();
        controller.updateRawInput('kame');
        final candidate = controller.candidates.firstWhere(
          (value) => value.text == '仮面ライダー',
        );
        expect(candidate.reading, 'かめんらいだー');
        // A different IME process may save another matching context after load.
        await repository.save({
          ...await repository.load(),
          'context:65e5\tカメンライダー\t仮面ライダー': 12,
          'いぬ\t犬': 6,
        });
        expect(await controller.resetCandidateLearning(candidate), isTrue);
        expect(controller.rawInput, 'kame');
        expect(controller.committedText, isEmpty);
        expect(
          controller.candidates.map((value) => value.text),
          isNot(contains('仮面ライダー')),
        );
        expect(await repository.load(), {'ねこ\t猫': 8, 'いぬ\t犬': 6});
        final reloaded = DesktopInputController(learningRepository: repository);
        await reloaded.initializeLearning();
        reloaded.updateRawInput('kame');
        expect(
          reloaded.candidates.map((value) => value.text),
          isNot(contains('仮面ライダー')),
        );
        reloaded.dispose();
      } finally {
        controller.dispose();
        await directory.delete(recursive: true);
      }
    },
  );

  test('learned spelling and context survive a desktop restart', () async {
    final directory = await Directory.systemTemp.createTemp(
      'keynako-learning-',
    );
    try {
      final repository = DesktopLearningRepository(
        file: File('${directory.path}/learning.json'),
      );
      final original = DesktopInputController(learningRepository: repository);
      await original.initializeLearning();
      for (final (context, choice) in [('今日は', '飴'), ('明日は', '雨')]) {
        original.replaceCommittedText(context);
        original.updateRawInput('ame');
        original.selectCandidate(
          original.candidates.indexWhere(
            (candidate) => candidate.text == choice,
          ),
        );
        original.commitSelected();
      }
      await original.flushLearning();
      expect(original.learningSaveFailed, isFalse);
      original.dispose();

      final reloaded = DesktopInputController(learningRepository: repository);
      await reloaded.initializeLearning();
      expect(reloaded.learningLoadFailed, isFalse);
      reloaded.replaceCommittedText('今日は');
      reloaded.updateRawInput('ame');
      expect(reloaded.candidates.first.text, '飴');
      reloaded.replaceCommittedText('明日は');
      reloaded.updateRawInput('ame');
      expect(reloaded.candidates.first.text, '雨');
      reloaded.dispose();
    } finally {
      await directory.delete(recursive: true);
    }
  });

  test('a damaged learning file is kept for recovery', () async {
    final directory = await Directory.systemTemp.createTemp(
      'keynako-learning-',
    );
    try {
      final file = File('${directory.path}/learning.json');
      await file.writeAsString('{broken');
      final controller = DesktopInputController(
        learningRepository: DesktopLearningRepository(file: file),
      );
      await controller.initializeLearning();
      expect(controller.learningLoadFailed, isTrue);
      controller.updateRawInput('ame');
      expect(
        await controller.resetCandidateLearning(controller.candidates.first),
        isFalse,
      );
      controller.commitSelected();
      await controller.flushLearning();
      expect(await file.readAsString(), '{broken');
      controller.dispose();
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
