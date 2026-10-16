import 'package:keynako_conversion/keynako_conversion.dart';
import 'package:test/test.dart';

void main() {
  test('matches azooKey number and time candidates', () {
    expect(AzooKeySpecialCandidates.complete('49000'), contains('49,000'));
    expect(AzooKeySpecialCandidates.complete('2129.49'), contains('2,129.49'));
    expect(AzooKeySpecialCandidates.complete('-13932'), contains('-13,932'));
    expect(AzooKeySpecialCandidates.complete('123'), contains('1:23'));
    expect(AzooKeySpecialCandidates.complete('1234'), contains('12:34'));
    expect(AzooKeySpecialCandidates.complete('1260'), isNot(contains('12:60')));
    expect(AzooKeySpecialCandidates.complete('１２３４'), isEmpty);
  });

  test('converts western and Japanese era years', () {
    expect(
      AzooKeySpecialCandidates.complete('2019ねん'),
      containsAll(['令和元年', '平成31年']),
    );
    expect(AzooKeySpecialCandidates.complete('れいわがんねん'), contains('2019年'));
    expect(AzooKeySpecialCandidates.complete('しょうわ64ねん'), contains('1989年'));
  });

  test('completes an email domain while preserving the local part', () {
    expect(
      AzooKeySpecialCandidates.emailAddresses('azooKey@g'),
      containsAll(['azooKey@gmail.com', 'azooKey@googlemail.com']),
    );
    expect(
      AzooKeySpecialCandidates.emailAddresses('azooKey@g'),
      isNot(contains('azooKey@yahoo.co.jp')),
    );
    expect(AzooKeySpecialCandidates.emailAddresses('あずき@'), isEmpty);
  });

  test('shows special forms in both Japanese and English candidate lists', () {
    const japanese = JapaneseConverter();
    const english = EnglishConverter();
    expect(
      japanese.candidates(input: '1234').map((value) => value.text),
      containsAll(['1,234', '12:34']),
    );
    expect(
      english.candidates(input: 'azooKey@g').map((value) => value.text),
      contains('azooKey@gmail.com'),
    );
  });
}
