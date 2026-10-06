import 'package:flutter_test/flutter_test.dart';

import 'package:owntone_sync/presentation/widgets/star_rating.dart';

void main() {
  // Display rule (documented on ratingToHalfStars): round to the nearest
  // half-star, ties round up — in half-star units, round(rating / 10).
  group('ratingToHalfStars: the documented rounding rule', () {
    test('exact multiples of 10 map to whole half-star counts', () {
      expect(ratingToHalfStars(0), 0);
      expect(ratingToHalfStars(10), 1);
      expect(ratingToHalfStars(20), 2);
      expect(ratingToHalfStars(90), 9);
      expect(ratingToHalfStars(100), 10);
    });

    test('half-star ties round up (50 -> 5 half-stars = 2.5 stars)', () {
      expect(ratingToHalfStars(5), 1); // 0.5 -> 1
      expect(ratingToHalfStars(45), 5); // 4.5 -> 5
      expect(ratingToHalfStars(50), 5);
      expect(ratingToHalfStars(95), 10); // 9.5 -> 10
    });

    test('non-multiples-of-10 from the real library (55 and 62)', () {
      // The server accepts any 0-100 integer; the library contains ratings
      // that do not sit on a half-star boundary.
      expect(ratingToHalfStars(55), 6); // 5.5 -> 6 (3 stars)
      expect(ratingToHalfStars(62), 6); // 6.2 -> 6 (3 stars)
    });

    test('values between boundaries round to the nearest half-star', () {
      expect(ratingToHalfStars(4), 0); // 0.4 -> 0
      expect(ratingToHalfStars(14), 1); // 1.4 -> 1
      expect(ratingToHalfStars(16), 2); // 1.6 -> 2
      expect(ratingToHalfStars(64), 6); // 6.4 -> 6
    });
  });

  group('ratingToHalfStars: the 0-100 clamp', () {
    test('out-of-range input is clamped before rounding', () {
      expect(ratingToHalfStars(-1), 0);
      expect(ratingToHalfStars(-50), 0);
      expect(ratingToHalfStars(101), 10);
      expect(ratingToHalfStars(999), 10);
    });
  });
}
