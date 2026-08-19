import 'dart:convert';

import 'package:azookey_flutter/models/app_data.dart';
import 'package:azookey_flutter/models/custard.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final definition = <String, dynamic>{
    'identifier': 'official-sample',
    'language': 'ja_JP',
    'input_style': 'direct',
    'metadata': {'custard_version': '1.2', 'display_name': '公式サンプル'},
    'interface': {
      'key_style': 'tenkey_style',
      'key_layout': {'type': 'grid_fit', 'row_count': 5, 'column_count': 4},
      'keys': [
        {
          'specifier_type': 'grid_fit',
          'specifier': {'x': 0, 'y': 0, 'width': 1, 'height': 1},
          'key_type': 'system',
          'key': {'type': 'change_keyboard'},
        },
        {
          'specifier_type': 'grid_fit',
          'specifier': {'x': 1, 'y': 0, 'width': 2, 'height': 1},
          'key_type': 'custom',
          'key': {
            'design': {
              'label': {'text': 'あいう'},
              'color': 'normal',
            },
            'press_actions': [
              {'type': 'input', 'text': 'あ'},
              {'type': 'move_cursor', 'count': 1},
            ],
            'longpress_actions': {
              'duration': 'light',
              'start': [
                {'type': 'toggle_cursor_bar'},
              ],
              'repeat': [
                {'type': 'delete', 'count': 1},
              ],
            },
            'variations': [
              {
                'type': 'flick_variation',
                'direction': 'left',
                'key': {
                  'design': {
                    'label': {'text': 'い'},
                  },
                  'press_actions': [
                    {'type': 'input', 'text': 'い'},
                  ],
                  'longpress_actions': {'start': [], 'repeat': []},
                },
              },
            ],
          },
        },
      ],
    },
  };

  test('decodes the official Custard 1.2 structure without flattening it', () {
    final custard = AzooKeyCustard.decodeMany(jsonEncode(definition)).single;

    expect(custard.identifier, 'official-sample');
    expect(custard.displayName, '公式サンプル');
    expect(custard.layoutType, 'grid_fit');
    expect(custard.keyCount, 2);
    expect(custard.toJson(), definition);
  });

  test('accepts a list and preserves Custards in portable app state', () {
    final custards = AzooKeyCustard.decodeMany(
      jsonEncode([
        definition,
        {...definition, 'identifier': 'second'},
      ]),
    );
    final data = AppData.defaults()..custards.addAll(custards);

    final decoded = AppData.decode(data.encode());

    expect(decoded.custards.map((value) => value.identifier), [
      'official-sample',
      'second',
    ]);
    expect(decoded.custards.first.toJson(), definition);
  });

  test('accepts fractional QWERTY geometry and system keys', () {
    final qwerty = Map<String, dynamic>.from(
      jsonDecode(jsonEncode(definition)) as Map,
    );
    qwerty['interface'] = {
      'key_style': 'pc_style',
      'key_layout': {'type': 'grid_fit', 'row_count': 10, 'column_count': 4},
      'keys': [
        {
          'specifier_type': 'grid_fit',
          'specifier': {'x': 1.4, 'y': 3, 'width': 4.4, 'height': 1},
          'key_type': 'system',
          'key': {'type': 'qwerty_space'},
        },
      ],
    };

    expect(AzooKeyCustard.fromJson(qwerty).toJson(), qwerty);
  });

  test('rejects malformed or unsupported definitions', () {
    expect(
      () => AzooKeyCustard.decodeMany(
        jsonEncode({...definition, 'input_style': 'unsupported'}),
      ),
      throwsFormatException,
    );
    expect(
      () => AzooKeyCustard.decodeMany(
        jsonEncode({
          ...definition,
          'metadata': {'custard_version': '2.0', 'display_name': 'future'},
        }),
      ),
      throwsFormatException,
    );
  });
}
