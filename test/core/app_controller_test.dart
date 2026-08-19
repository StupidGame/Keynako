import 'package:azookey_flutter/core/app_controller.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('resolves azooKey share URLs to the Custard API', () {
    expect(
      resolveCustardUrl(Uri.parse('https://custard.azookey.com/tab/example-id'))
          .toString(),
      'https://custard.azookey.com/api/tab/example-id',
    );
  });

  test('resolves GitHub and Gist page URLs to raw content', () {
    expect(
      resolveCustardUrl(
        Uri.parse('https://github.com/owner/repo/blob/main/layout.custard'),
      ).toString(),
      'https://raw.githubusercontent.com/owner/repo/main/layout.custard',
    );
    expect(
      resolveCustardUrl(
        Uri.parse('https://gist.github.com/owner/0123456789abcdef'),
      ).toString(),
      'https://gist.github.com/owner/0123456789abcdef/raw',
    );
  });
}
