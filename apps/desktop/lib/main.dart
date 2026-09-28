import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'input/desktop_input_controller.dart';
import 'input/desktop_personal_dictionary.dart';
import 'input/desktop_shared_dictionary.dart';
import 'input/desktop_zenzai_locator.dart';

Future<void> main(List<String> arguments) async {
  WidgetsFlutterBinding.ensureInitialized();
  final dictionaryCommand = await runSharedDictionaryCommand(arguments);
  if (dictionaryCommand != null) {
    exitCode = dictionaryCommand;
    return;
  }
  final controller = DesktopInputController(
    zenzaiEngineFactory: DesktopZenzaiLocator.create,
    sharedDictionaryRepository: DesktopSharedDictionaryRepository(),
    personalDictionaryRepository: DesktopPersonalDictionaryRepository(),
  );
  final openDictionary = arguments.contains('--dictionary');
  await controller.initializePersonalDictionary();
  if (!openDictionary) {
    await controller.initializeSharedDictionary();
    await controller.setZenzaiModel(ZenzaiModel.xsmall);
  }
  runApp(
    KeynakoDesktopApp(controller: controller, openDictionary: openDictionary),
  );
}
