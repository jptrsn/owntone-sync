import 'package:flutter_test/flutter_test.dart';

import 'package:owntone_sync/presentation/services/queue_indices.dart';

/// Index-space invariant (invariant 19): there is exactly one index space —
/// `sequence` (base order). `currentIndex` is a BASE index, never a play
/// position. `shuffleIndices` is the list of base indices in play order.
///
/// The two translations:
/// - highlight row: shuffle on ? shuffleIndices.indexOf(currentIndex) : currentIndex
/// - jump from row i: shuffle on ? shuffleIndices[i] : i
///
/// A previous session had this model exactly INVERTED (treating
/// `currentIndex` as a play position), which poisoned the queue-sheet
/// translations. These tests guard that specific mistake, so they use
/// permutations where the two models give different answers.
void main() {
  // Play order: base 2 first, then base 0, then base 1.
  // Every value below was chosen so the inverted model (base<->row swapped)
  // would produce a different answer.
  const List<int> perm = [2, 0, 1];

  group('highlight row (base index -> play-order row)', () {
    test('shuffle on: the row is indexOf in the play-order permutation '
        '(invariant 19)', () {
      expect(queueCurrentRow(perm, 0, true), 1);
      expect(queueCurrentRow(perm, 1, true), 2);
      expect(queueCurrentRow(perm, 2, true), 0);
    });

    test('shuffle off: the row IS the base index (invariant 19)', () {
      expect(queueCurrentRow(perm, 0, false), 0);
      expect(queueCurrentRow(perm, 1, false), 1);
      expect(queueCurrentRow(perm, 2, false), 2);
    });

    test('no current track highlights no row (invariant 19)', () {
      expect(queueCurrentRow(perm, null, true), isNull);
      expect(queueCurrentRow(perm, null, false), isNull);
    });
  });

  group('jump (play-order row -> base index)', () {
    test('shuffle on: row i plays base index shuffleIndices[i] '
        '(invariant 19)', () {
      expect(queueBaseIndexForRow(0, perm, true), 2);
      expect(queueBaseIndexForRow(1, perm, true), 0);
      expect(queueBaseIndexForRow(2, perm, true), 1);
    });

    test('shuffle off: row i plays base index i (invariant 19)', () {
      expect(queueBaseIndexForRow(0, perm, false), 0);
      expect(queueBaseIndexForRow(1, perm, false), 1);
      expect(queueBaseIndexForRow(2, perm, false), 2);
    });
  });

  group('the two translations are exact inverses (invariant 19)', () {
    test('jumping to the highlighted row lands on the current base index '
        'for every base index, shuffle on or off', () {
      final length = perm.length;
      final identity = List<int>.generate(length, (i) => i);
      for (final shuffleOn in [true, false]) {
        final indices = shuffleOn ? perm : identity;
        for (var base = 0; base < length; base++) {
          final row = queueCurrentRow(indices, base, shuffleOn);
          expect(row, isNotNull);
          expect(queueBaseIndexForRow(row!, indices, shuffleOn), base);
        }
      }
    });

    test('a larger real-world-sized permutation round-trips', () {
      const List<int> bigPerm = [3, 1, 4, 0, 2];
      for (var base = 0; base < bigPerm.length; base++) {
        final row = queueCurrentRow(bigPerm, base, true);
        expect(queueBaseIndexForRow(row!, bigPerm, true), base);
      }
      expect(queueCurrentRow(bigPerm, 3, true), 0);
      expect(queueBaseIndexForRow(4, bigPerm, true), 2);
    });
  });
}
