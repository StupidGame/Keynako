import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keynako_conversion/keynako_conversion.dart';
import 'package:keynako_desktop/input/desktop_input_controller.dart';
import 'package:keynako_desktop/input/desktop_learning.dart';
import 'package:keynako_desktop/input/desktop_personal_dictionary.dart';
import 'package:keynako_desktop/input/portable_profile.dart';

void main() {
  test(
    'a failed setting write does not prevent the next setting save',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'keynako-settings-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final repository = _FailingSettingsRepository(
        File('${directory.path}/profile.json'),
      );
      final controller = DesktopInputController(profileRepository: repository);
      addTearDown(controller.dispose);
      controller.setLiveConversionEnabled(false);
      await expectLater(controller.exportPortableProfile(), throwsStateError);
      controller.setLiveConversionEnabled(true);
      await controller.exportPortableProfile();
      expect((await repository.loadImeSettings())['live_conversion'], isTrue);
      expect(repository.attempts, 2);
    },
  );

  test(
    'checks backup file size before decoding and accepts a small UTF-8 file',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'keynako-profile-size-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final file = File('${directory.path}/profile.json');
      await file.writeAsString('日本語');
      expect(await PortableProfile.readFile(file), '日本語');
      final handle = await file.open(mode: FileMode.append);
      try {
        await handle.truncate(PortableProfile.maxBytes + 1);
      } finally {
        await handle.close();
      }
      await expectLater(PortableProfile.readFile(file), throwsFormatException);
    },
  );

  test(
    'a late restore failure rolls back the desktop files already written',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'keynako-profile-undo-',
      );
      addTearDown(() => directory.delete(recursive: true));
      final dictionary = DesktopPersonalDictionaryRepository(
        file: File('${directory.path}/dictionary.tsv'),
      );
      final learning = DesktopLearningRepository(
        file: File('${directory.path}/learning.tsv'),
      );
      final profile = _FailingProfileRepository(
        File('${directory.path}/profile.json'),
      );
      await dictionary.save(const [
        ConversionDictionaryEntry(reading: 'ねこ', value: '猫'),
      ]);
      await learning.save({'ねこ\t猫': 4});
      await profile.saveImeSettings({
        'live_conversion': false,
        'automatic_completion_strength': 2,
      });
      final controller = DesktopInputController(
        personalDictionaryRepository: dictionary,
        learningRepository: learning,
        profileRepository: profile,
      );
      addTearDown(controller.dispose);

      await expectLater(
        controller.importPortableProfile(
          PortableProfile.empty().export(
            dictionary: const [],
            learning: const {},
            liveConversion: true,
            zenzaiEnabled: false,
          ),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect((await dictionary.load()).single.value, '猫');
      expect(await learning.load(), {'ねこ\t猫': 4});
      expect(await profile.loadImeSettings(), {
        'live_conversion': false,
        'automatic_completion_strength': 2,
      });
    },
  );

  test('desktop round trip keeps mobile-only dictionary metadata', () {
    final profile = PortableProfile.decode(
      jsonEncode({
        'schemaVersion': 7,
        'settings': {},
        'userDictionary': [
          {
            'id': 42,
            'ruby': 'ひづけ',
            'word': '日付',
            'importance': 3,
            'isTemplateMode': true,
            'formatLiteral': 'yyyy/MM/dd',
            'isPersonName': false,
          },
        ],
        'learning': {},
      }),
    );
    final exported = jsonDecode(
      profile.export(
        dictionary: [
          const ConversionDictionaryEntry(reading: 'ひづけ', value: '日付'),
        ],
        learning: {},
        liveConversion: true,
        zenzaiEnabled: true,
      ),
    ) as Map<String, dynamic>;
    final entry = (exported['userDictionary'] as List).single as Map;
    expect(entry['id'], 42);
    expect(entry['isTemplateMode'], true);
    expect(entry['formatLiteral'], 'yyyy/MM/dd');
  });

  test(
    'mobile backup works on desktop and round trips mobile fields',
    () async {
      final directory = await Directory.systemTemp.createTemp(
        'keynako-profile-',
      );
      try {
        final dictionary = DesktopPersonalDictionaryRepository(
          file: File('${directory.path}/user_dictionary.tsv'),
        );
        final learning = DesktopLearningRepository(
          file: File('${directory.path}/learning.tsv'),
        );
        final profile = DesktopPortableProfileRepository(
          file: File('${directory.path}/portable_profile.json'),
        );
        final controller = DesktopInputController(
          personalDictionaryRepository: dictionary,
          learningRepository: learning,
          profileRepository: profile,
        );
        await controller.initializePersonalDictionary();
        await controller.initializeLearning();
        final mobileJson = jsonEncode({
          'schemaVersion': 7,
          'settings': {
            'live_conversion': false,
            'automatic_completion_strength': 2,
            'enable_zenzai': false,
            'keyboard_type': 'flick',
          },
          'userDictionary': [
            {
              'id': 7,
              'ruby': 'ぼいすつき',
              'word': 'ボイス付き',
              'importance': 5,
              'isPersonName': false,
            },
          ],
          'learning': {'ぼいすつき\tボイス付き': 12, 'context:672c.65e5\tあめ\t飴': 4},
          'themes': [
            {'id': 'custom', 'name': 'mobile only'},
          ],
          'themeImages': {'custom': 'AQID'},
        });
        await controller.importPortableProfile(mobileJson);
        expect(controller.liveConversionEnabled, isFalse);
        expect(controller.personalDictionary.single.value, 'ボイス付き');
        expect((await learning.load())['ぼいすつき\tボイス付き'], 12);
        expect(await profile.loadImeSettings(), {
          'live_conversion': false,
          'automatic_completion_strength': 2,
        });
        controller.updateRawInput('boisutsuki');
        expect(
          controller.candidates.any((entry) => entry.text == 'ボイス付き'),
          isTrue,
        );

        final exported = jsonDecode(
          await controller.exportPortableProfile(),
        ) as Map<String, dynamic>;
        expect((exported['settings'] as Map)['keyboard_type'], 'flick');
        expect(
          (exported['userDictionary'] as List).single['isPersonName'],
          false,
        );
        expect((exported['learning'] as Map)['context:672c.65e5\tあめ\t飴'], 4);
        expect(exported['themes'], isNotEmpty);
        expect((exported['themeImages'] as Map)['custom'], 'AQID');
        expect(exported['schemaVersion'], 7);
        controller.dispose();
      } finally {
        await directory.delete(recursive: true);
      }
    },
  );

  test('invalid backup does not replace dictionary or learning', () async {
    final directory = await Directory.systemTemp.createTemp('keynako-profile-');
    try {
      final dictionary = DesktopPersonalDictionaryRepository(
        file: File('${directory.path}/user_dictionary.tsv'),
      );
      final learning = DesktopLearningRepository(
        file: File('${directory.path}/learning.tsv'),
      );
      final controller = DesktopInputController(
        personalDictionaryRepository: dictionary,
        learningRepository: learning,
        profileRepository: DesktopPortableProfileRepository(
          file: File('${directory.path}/portable_profile.json'),
        ),
      );
      await expectLater(
        controller.importPortableProfile('{"settings":{}}'),
        throwsFormatException,
      );
      expect(await dictionary.load(), isEmpty);
      expect(await learning.load(), isEmpty);
      controller.dispose();
    } finally {
      await directory.delete(recursive: true);
    }
  });
}

class _FailingSettingsRepository extends DesktopPortableProfileRepository {
  _FailingSettingsRepository(File file) : super(file: file);

  int attempts = 0;

  @override
  Future<void> saveImeSettings(Map<String, dynamic> settings) async {
    if (++attempts == 1) throw FileSystemException('write failed');
    await super.saveImeSettings(settings);
  }
}

class _FailingProfileRepository extends DesktopPortableProfileRepository {
  _FailingProfileRepository(File file) : super(file: file);

  @override
  Future<void> save(String source) async =>
      throw FileSystemException('write failed');
}
