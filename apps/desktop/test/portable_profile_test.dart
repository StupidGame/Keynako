import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:keynako_conversion/keynako_conversion.dart';
import 'package:keynako_desktop/input/desktop_input_controller.dart';
import 'package:keynako_desktop/input/desktop_learning.dart';
import 'package:keynako_desktop/input/desktop_personal_dictionary.dart';
import 'package:keynako_desktop/input/portable_profile.dart';

void main() {
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
