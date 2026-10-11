import 'package:flutter_test/flutter_test.dart';

import 'package:owntone_sync/presentation/widgets/app_drawer.dart';

/// Phase U4 build item 2 (ux-refactor.md §6): the drawer's server line
/// demotes the full URL to an address — host, plus the port only when one
/// was typed. The fallback rule is invariant 39's unknown rule applied to
/// display: a value that cannot be proved to be an address is shown as-is,
/// never blanked or "cleaned up".
void main() {
  group('AppDrawer.serverAddress', () {
    test('shows host and port when the URL has one', () {
      expect(
        AppDrawer.serverAddress('http://192.168.1.13:3689'),
        '192.168.1.13:3689',
      );
    });

    test('shows the host alone when the URL omits the port', () {
      expect(AppDrawer.serverAddress('http://192.168.1.13'), '192.168.1.13');
    });

    test('normalises host case and a trailing slash', () {
      expect(
        AppDrawer.serverAddress('HTTP://192.168.1.13:3689/'),
        '192.168.1.13:3689',
      );
    });

    test('an unparseable value falls back to the raw text', () {
      expect(AppDrawer.serverAddress('not a url'), 'not a url');
      expect(AppDrawer.serverAddress('  '), '');
    });
  });
}
