import 'dart:io';

import 'package:keynako_conversion/keynako_conversion.dart';

import 'desktop_input_controller.dart';

class DesktopZenzaiLocator {
  const DesktopZenzaiLocator._();

  static Future<ZenzaiEngine?> create(ZenzaiModel model) async {
    if (model == ZenzaiModel.off) return null;
    final executableOverride = Platform.environment['KEYNAKO_ZENZAI_BIN'];
    final modelOverride = Platform.environment['KEYNAKO_ZENZAI_MODEL'];
    if (executableOverride != null && modelOverride != null) {
      return ZenzaiProcessEngine(
        executablePath: executableOverride,
        modelPath: modelOverride,
      );
    }

    final size = model == ZenzaiModel.small ? 'small' : 'xsmall';
    final executableName = Platform.isWindows
        ? 'keynako_zenzai.exe'
        : 'keynako_zenzai';
    final executableDirectory = File(Platform.resolvedExecutable)
        .absolute
        .parent;
    final bundledModel = Platform.isMacOS
        ? File(
            '${executableDirectory.parent.path}${Platform.pathSeparator}'
            'Resources${Platform.pathSeparator}zenzai${Platform.pathSeparator}'
            'zenz-v3.2-$size-gguf${Platform.pathSeparator}'
            'ggml-model-Q5_K_M.gguf',
          )
        : File(
            '${executableDirectory.path}${Platform.pathSeparator}zenzai'
            '${Platform.pathSeparator}zenz-v3.2-$size-gguf'
            '${Platform.pathSeparator}ggml-model-Q5_K_M.gguf',
          );
    final bundledExecutable = File(
      '${executableDirectory.path}${Platform.pathSeparator}$executableName',
    );
    if (bundledExecutable.existsSync() && bundledModel.existsSync()) {
      return ZenzaiProcessEngine(
        executablePath: bundledExecutable.path,
        modelPath: bundledModel.path,
      );
    }

    final repositoryRoot = _findRepositoryRoot(Directory.current.absolute);
    if (repositoryRoot == null) return null;
    final developmentModel = File(
      '${repositoryRoot.path}${Platform.pathSeparator}assets'
      '${Platform.pathSeparator}zenz-v3.2-$size-gguf'
      '${Platform.pathSeparator}ggml-model-Q5_K_M.gguf',
    );
    final developmentExecutables = [
      File(
        '${repositoryRoot.path}${Platform.pathSeparator}build'
        '${Platform.pathSeparator}zenzai${Platform.pathSeparator}'
        '$executableName',
      ),
      File(
        '${repositoryRoot.path}${Platform.pathSeparator}build'
        '${Platform.pathSeparator}zenzai${Platform.pathSeparator}Release'
        '${Platform.pathSeparator}$executableName',
      ),
    ];
    final developmentExecutable = developmentExecutables
        .where((file) => file.existsSync())
        .firstOrNull;
    if (developmentExecutable == null || !developmentModel.existsSync()) {
      return null;
    }
    return ZenzaiProcessEngine(
      executablePath: developmentExecutable.path,
      modelPath: developmentModel.path,
    );
  }

  static Directory? _findRepositoryRoot(Directory start) {
    var directory = start;
    for (var depth = 0; depth < 8; depth++) {
      if (File('${directory.path}${Platform.pathSeparator}.gitmodules')
          .existsSync()) {
        return directory;
      }
      final parent = directory.parent;
      if (parent.path == directory.path) return null;
      directory = parent;
    }
    return null;
  }
}
