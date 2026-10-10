import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'input/candidate_dictionary_command.dart';
import 'input/desktop_input_controller.dart';
import 'input/desktop_learning.dart';
import 'input/desktop_personal_dictionary.dart';
import 'input/desktop_shared_dictionary.dart';
import 'input/desktop_zenzai_locator.dart';

Future<void> main(List<String> arguments) async {
  final dictionaryCommand = await runSharedDictionaryCommand(arguments);
  if (dictionaryCommand != null) {
    exitCode = dictionaryCommand;
    return;
  }
  final candidateCommand = await runCandidateDictionaryCommand(arguments);
  if (candidateCommand != null) {
    exitCode = candidateCommand;
    return;
  }
  WidgetsFlutterBinding.ensureInitialized();
  final controller = DesktopInputController(
    zenzaiEngineFactory: DesktopZenzaiLocator.create,
    sharedDictionaryRepository: DesktopSharedDictionaryRepository(),
    personalDictionaryRepository: DesktopPersonalDictionaryRepository(),
    learningRepository: DesktopLearningRepository(),
  );
  final openDictionary = arguments.contains('--dictionary');
  final candidateIndex = arguments.indexOf('--candidate-word');
  final readingIndex = arguments.indexOf('--candidate-reading');
  final candidateWord =
      candidateIndex >= 0 && candidateIndex + 1 < arguments.length
      ? arguments[candidateIndex + 1]
      : null;
  final candidateReading =
      readingIndex >= 0 && readingIndex + 1 < arguments.length
      ? arguments[readingIndex + 1]
      : null;
  await controller.initializePersonalDictionary();
  await controller.initializeLearning();
  if (!openDictionary && (candidateWord == null || candidateReading == null)) {
    await controller.initializeSharedDictionary();
    await controller.setZenzaiModel(ZenzaiModel.xsmall);
  }
  runApp(
    KeynakoDesktopApp(
      controller: controller,
      openDictionary: openDictionary,
      candidateWord: candidateWord,
      candidateReading: candidateReading,
    ),
  );
}
