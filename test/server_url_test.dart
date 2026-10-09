import 'package:flutter_test/flutter_test.dart';

import 'package:owntone_sync/utils/server_url.dart';

/// Phase U0 (ux-refactor.md §6): a server-URL change must not look like a
/// server change when only the text changed. Normalisation rules, straight
/// from the build spec: trim whitespace, lowercase the scheme and host,
/// strip a trailing '/', and treat an absent port as the scheme default.
///
/// The three outcomes this feeds:
/// - normalised values equal  -> save silently, no dialog, no wipe
/// - same host, other change  -> save, no wipe (same machine)
/// - different host           -> ask, keeping the library is the default
///
/// These tests guard the first two outcomes at the point they are decided.
void main() {
  group('cosmetic differences are not a server change (U0, build item 1)',
      () {
    test('identical URLs are equal', () {
      expect(
        parseServerUrlIdentity('http://192.168.1.13:3689'),
        parseServerUrlIdentity('http://192.168.1.13:3689'),
      );
    });

    test('a trailing slash (or several) does not change the identity', () {
      const base = 'http://192.168.1.13:3689';
      expect(parseServerUrlIdentity(base),
          parseServerUrlIdentity('$base/'));
      expect(parseServerUrlIdentity(base),
          parseServerUrlIdentity('$base//'));
    });

    test('surrounding whitespace does not change the identity', () {
      const base = 'http://192.168.1.13:3689';
      expect(parseServerUrlIdentity(base), parseServerUrlIdentity(' $base '));
      expect(parseServerUrlIdentity(base), parseServerUrlIdentity('$base\n'));
    });

    test('scheme case does not change the identity', () {
      expect(
        parseServerUrlIdentity('http://192.168.1.13:3689'),
        parseServerUrlIdentity('HTTP://192.168.1.13:3689'),
      );
    });

    test('host case does not change the identity', () {
      expect(
        parseServerUrlIdentity('http://HomeBox.local:3689'),
        parseServerUrlIdentity('http://homebox.local:3689'),
      );
    });

    test('an omitted port is the scheme default (80 for http, 443 for https)',
        () {
      expect(
        parseServerUrlIdentity('http://192.168.1.13'),
        parseServerUrlIdentity('http://192.168.1.13:80'),
      );
      expect(
        parseServerUrlIdentity('https://example.com'),
        parseServerUrlIdentity('https://example.com:443'),
      );
    });
  });

  group('real differences are not hidden (U0, build items 1-2)', () {
    test('a different port is a different identity', () {
      expect(
        parseServerUrlIdentity('http://192.168.1.13:3689') ==
            parseServerUrlIdentity('http://192.168.1.13:9999'),
        false,
      );
    });

    test('a different scheme with no port is a different identity', () {
      // 80 vs 443 - the defaulted ports differ, so the identities do.
      expect(
        parseServerUrlIdentity('http://192.168.1.13') ==
            parseServerUrlIdentity('https://192.168.1.13'),
        false,
      );
    });

    test('a different path is a different identity', () {
      expect(
        parseServerUrlIdentity('http://192.168.1.13:3689') ==
            parseServerUrlIdentity('http://192.168.1.13:3689/sub'),
        false,
      );
      // ...but a trailing slash on the path still does not change it.
      expect(
        parseServerUrlIdentity('http://192.168.1.13:3689/sub'),
        parseServerUrlIdentity('http://192.168.1.13:3689/sub/'),
      );
    });
  });

  group('the host is the same-machine signal (U0, build item 2)', () {
    test('same host, different port: the hosts match', () {
      final a = parseServerUrlIdentity('http://192.168.1.13:3689')!;
      final b = parseServerUrlIdentity('http://192.168.1.13:9999')!;
      expect(a == b, false);
      expect(a.host, b.host);
    });

    test('same host, different scheme: the hosts match', () {
      final a = parseServerUrlIdentity('http://192.168.1.13:3689')!;
      final b = parseServerUrlIdentity('https://192.168.1.13:3689')!;
      expect(a == b, false);
      expect(a.host, b.host);
    });

    test('a different host never matches, however it is written', () {
      final a = parseServerUrlIdentity('http://192.168.1.13:3689')!;
      final b = parseServerUrlIdentity('http://192.168.1.99:3689')!;
      expect(a.host, isNot(b.host));
      final c = parseServerUrlIdentity('HTTP://HOMEBOX.LOCAL:3689')!;
      expect(a.host, isNot(c.host));
    });
  });

  group('unparseable input is "unknown", never "changed" (U0, build item 3)',
      () {
    test('empty and blank input parses to null', () {
      expect(parseServerUrlIdentity(''), isNull);
      expect(parseServerUrlIdentity('   '), isNull);
    });

    test('non-http(s) or hostless input parses to null', () {
      expect(parseServerUrlIdentity('ftp://192.168.1.13:3689'), isNull);
      expect(parseServerUrlIdentity('192.168.1.13:3689'), isNull);
      expect(parseServerUrlIdentity('http://'), isNull);
    });
  });
}
