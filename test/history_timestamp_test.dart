import 'package:flutter_test/flutter_test.dart';

import 'package:owntone_sync/presentation/screens/history_screen.dart';

/// Guards the fix for the 2026-10-17 blocker entry
/// "History date renders 'PMt' instead of 'at'" (blockers.md): a bare `a`
/// inside a DateFormat pattern is the AM/PM marker, so an unquoted `at`
/// rendered as "PMt", and `y` gave a 2-digit year ("Oct 9, 26"). The
/// quoted literal and `yyyy` are now pinned here (invariant 50).
///
/// `now` is pinned to Wednesday 2026-10-14 so the "this week" branch is
/// exercised with a Monday timestamp — on a Sunday (today at the time of
/// the fix) that branch is unreachable on device (startOfWeek == today,
/// so every past row falls into "older"), which is why the branch is
/// unit-tested rather than device-tested.
void main() {
  // Wednesday 2026-10-14, noon. Week under test: Sun 2026-10-11 – Sat 17.
  final now = DateTime(2026, 10, 14, 12, 0);

  int ts(DateTime d) => d.millisecondsSinceEpoch;

  group('today branch (plain Dart strings, never in a pattern)', () {
    test('under a minute: "a few seconds ago"', () {
      expect(formatSyncTimestamp(ts(DateTime(2026, 10, 14, 11, 59, 30)), now: now), 'a few seconds ago');
    });

    test('under an hour: "N minutes ago" (singular included)', () {
      expect(formatSyncTimestamp(ts(DateTime(2026, 10, 14, 11, 30)), now: now), '30 minutes ago');
      expect(formatSyncTimestamp(ts(DateTime(2026, 10, 14, 11, 59)), now: now), '1 minute ago');
    });

    test('same day, older: "N hours ago"', () {
      expect(formatSyncTimestamp(ts(DateTime(2026, 10, 14, 9, 0)), now: now), '3 hours ago');
    });
  });

  group('yesterday branch (literal "at" in the interpolated Dart string)', () {
    test('renders "Yesterday at h:mm a" (control: already-correct branch)', () {
      expect(formatSyncTimestamp(ts(DateTime(2026, 10, 13, 15, 12)), now: now), 'Yesterday at 3:12 PM');
      expect(formatSyncTimestamp(ts(DateTime(2026, 10, 13, 8, 5)), now: now), 'Yesterday at 8:05 AM');
    });
  });

  group('this-week branch (quoted literal in the pattern)', () {
    test('Monday timestamp renders "Monday at h:mm a" (blockers 2026-10-17)', () {
      expect(formatSyncTimestamp(ts(DateTime(2026, 10, 12, 15, 12)), now: now), 'Monday at 3:12 PM');
    });

    test('quoted literal is not the AM/PM marker (AM render, invariant 50)', () {
      expect(formatSyncTimestamp(ts(DateTime(2026, 10, 12, 3, 5)), now: now), 'Monday at 3:05 AM');
    });

    test('week start is Sunday: a Sunday row is still "this week"', () {
      expect(formatSyncTimestamp(ts(DateTime(2026, 10, 11, 15, 12)), now: now), 'Sunday at 3:12 PM');
    });
  });

  group('older branch (quoted literal + 4-digit year)', () {
    test('the entry\'s Oct 9 row renders "Oct 9, 2026 at 3:12 PM" (blockers 2026-10-17)', () {
      final result = formatSyncTimestamp(ts(DateTime(2026, 10, 9, 15, 12)), now: now);
      expect(result, 'Oct 9, 2026 at 3:12 PM');
      expect(result, isNot(contains('PMt')));
    });

    test('Saturday before the week start falls out of "this week" (invariant 50)', () {
      expect(formatSyncTimestamp(ts(DateTime(2026, 10, 10, 15, 12)), now: now), 'Oct 10, 2026 at 3:12 PM');
    });

    test('year before the week, AM: 4-digit year, quoted literal', () {
      expect(formatSyncTimestamp(ts(DateTime(2026, 9, 1, 7, 3)), now: now), 'Sep 1, 2026 at 7:03 AM');
    });
  });

  group('regression shape: no branch ever renders the mangled marker', () {
    test('no branch output contains "PMt" or "AMt" (invariant 50)', () {
      for (final candidate in [
        DateTime(2026, 10, 14, 11, 0),
        DateTime(2026, 10, 13, 15, 12),
        DateTime(2026, 10, 12, 15, 12),
        DateTime(2026, 10, 11, 15, 12),
        DateTime(2026, 10, 10, 15, 12),
        DateTime(2026, 10, 9, 15, 12),
        DateTime(2026, 1, 2, 15, 12),
      ]) {
        final result = formatSyncTimestamp(ts(candidate), now: now);
        expect(result, isNot(contains('PMt')), reason: 'from $candidate');
        expect(result, isNot(contains('AMt')), reason: 'from $candidate');
      }
    });
  });
}
