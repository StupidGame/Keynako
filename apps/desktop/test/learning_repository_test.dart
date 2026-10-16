import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keynako_desktop/input/desktop_input_controller.dart';
import 'package:keynako_desktop/input/desktop_learning.dart';

void main() {
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
      controller.commitSelected();
      await controller.flushLearning();
      expect(await file.readAsString(), '{broken');
      controller.dispose();
    } finally {
      await directory.delete(recursive: true);
    }
  });
}
