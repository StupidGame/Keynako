import 'dart:io';

import 'package:flutter/material.dart';

import 'app.dart';
import 'input/desktop_input_controller.dart';
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
  );
  await controller.initializeSharedDictionary();
  await controller.setZenzaiModel(ZenzaiModel.xsmall);
  runApp(KeynakoDesktopApp(controller: controller));
}
