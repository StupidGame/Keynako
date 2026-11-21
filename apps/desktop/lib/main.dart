import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'input/candidate_dictionary_command.dart';
import 'input/desktop_input_controller.dart';
import 'input/desktop_learning.dart';
import 'input/desktop_personal_dictionary.dart';
import 'input/desktop_shared_dictionary.dart';
import 'input/official_dictionary.dart';
import 'input/desktop_zenzai_locator.dart';
import 'input/portable_profile.dart';

Future<void> main(List<String> arguments) async {
  if (arguments.contains(refreshSharedDictionaryCommand) ||
      arguments.contains(refreshSharedDictionaryIfDueCommand)) {
    try {
      await OfficialDictionary().refreshIfDue();
    } on Object {
      // Offline and rejected updates retain the active immutable snapshot.
    }
  }
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
  void refreshOfficialDictionary() {
    unawaited(OfficialDictionary().refreshIfDue().catchError((Object _) {}));
  }

  refreshOfficialDictionary();
  Timer.periodic(const Duration(hours: 1), (_) => refreshOfficialDictionary());
  final profileRepository = DesktopPortableProfileRepository();
  final controller = DesktopInputController(
    zenzaiEngineFactory: DesktopZenzaiLocator.create,
    sharedDictionaryRepository: DesktopSharedDictionaryRepository(),
    personalDictionaryRepository: DesktopPersonalDictionaryRepository(),
    learningRepository: DesktopLearningRepository(),
    profileRepository: profileRepository,
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
  var zenzaiEnabled = true;
  try {
    final profile = await profileRepository.load();
    final imeSettings = await profileRepository.loadImeSettings();
    controller.setLiveConversionEnabled(
      imeSettings['live_conversion'] as bool? ??
          profile.settings['live_conversion'] != false,
      persist: false,
    );
    zenzaiEnabled = profile.settings['enable_zenzai'] != false;
  } on FormatException {
    // Preserve the damaged backup for manual recovery; use normal defaults.
  }
  if (!openDictionary && (candidateWord == null || candidateReading == null)) {
    await controller.initializeSharedDictionary();
    await controller.setZenzaiModel(
      zenzaiEnabled ? ZenzaiModel.xsmall : ZenzaiModel.off,
    );
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
