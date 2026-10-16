/// Candidate forms supplied by azooKey's special conversion providers.
class AzooKeySpecialCandidates {
  const AzooKeySpecialCandidates._();

  static const emailDomains = <String>[
    '@gmail.com',
    '@icloud.com',
    '@yahoo.co.jp',
    '@au.com',
    '@docomo.ne.jp',
    '@excite.co.jp',
    '@ezweb.ne.jp',
    '@googlemail.com',
    '@hotmail.co.jp',
    '@hotmail.com',
    '@i.softbank.jp',
    '@live.jp',
    '@me.com',
    '@mineo.jp',
    '@nifty.com',
    '@outlook.com',
    '@outlook.jp',
    '@softbank.ne.jp',
    '@yahoo.ne.jp',
    '@ybb.ne.jp',
    '@ymobile.ne.jp',
  ];

  static List<String> emailAddresses(String input) {
    final at = input.lastIndexOf('@');
    if (at < 0) return const [];
    final id = input.substring(0, at);
    if (!RegExp(r'^[A-Za-z0-9._+\-]*$').hasMatch(id)) return const [];
    final prefix = input.substring(at).toLowerCase();
    return emailDomains
        .where((domain) => domain.startsWith(prefix))
        .map((domain) => '$id$domain')
        .toList(growable: false);
  }

  static List<String> complete(String reading, {String? version}) {
    final values = <String>[];
    if (RegExp(r'^-?[0-9]+(\.[0-9]+)?$').hasMatch(reading)) {
      final negative = reading.startsWith('-');
      final unsigned = negative ? reading.substring(1) : reading;
      final parts = unsigned.split('.');
      if (parts.first.length > 3) {
        final digits = parts.first.split('').reversed.toList();
        final grouped = <String>[];
        for (var index = 0; index < digits.length; index++) {
          if (index > 0 && index % 3 == 0) grouped.add(',');
          grouped.add(digits[index]);
        }
        values.add(
          '${negative ? '-' : ''}${grouped.reversed.join()}'
          '${parts.length == 2 ? '.${parts.last}' : ''}',
        );
      }
      if (!negative && parts.length == 1) {
        final digits = parts.first;
        if (digits.length == 3 || digits.length == 4) {
          final hour = int.parse(digits.substring(0, digits.length - 2));
          final minute = int.parse(digits.substring(digits.length - 2));
          if (hour <= 24 && minute <= 59) {
            values.add(
              '${digits.length == 4 ? hour.toString().padLeft(2, '0') : hour}'
              ':${minute.toString().padLeft(2, '0')}',
            );
          }
        }
      }
    }
    final westernYear = RegExp(r'^([0-9]{4})ねん$').firstMatch(reading);
    if (westernYear != null) {
      final year = int.parse(westernYear[1]!);
      final eras = <(int, int, String)>[
        (2019, 2018, '令和'),
        (1989, 1988, '平成'),
        (1926, 1925, '昭和'),
        (1912, 1911, '大正'),
        (1868, 1867, '明治'),
      ];
      for (final (start, offset, name) in eras) {
        if (year >= start) {
          values.add('$name${year == start ? '元' : year - offset}年');
          break;
        }
      }
      if (year == 1989) values.add('昭和64年');
      if (year == 2019) values.add('平成31年');
      if (year == 1926) values.add('大正15年');
      if (year == 1912) values.add('明治45年');
      if (year == 1868) values.add('慶應4年');
    }
    final japaneseYear = RegExp(r'^(めいじ|たいしょう|しょうわ|へいせい|れいわ)(がん|[0-9]{1,2})ねん$')
        .firstMatch(reading);
    if (japaneseYear != null) {
      final era = japaneseYear[1]!;
      final year = japaneseYear[2] == 'がん' ? 1 : int.parse(japaneseYear[2]!);
      final offset = switch (era) {
        'めいじ' => 1867,
        'たいしょう' => 1911,
        'しょうわ' => 1925,
        'へいせい' => 1988,
        _ => 2018,
      };
      values.add('${year + offset}年');
    }
    if (reading == 'ばーじょん' && version != null && version.isNotEmpty) {
      values.add(version);
    }
    return values;
  }
}
