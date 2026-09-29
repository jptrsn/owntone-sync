import 'dart:math';

import 'package:just_audio/just_audio.dart';

/// A [ShuffleOrder] that places inserted items at exact, deterministic play
/// positions instead of [DefaultShuffleOrder]'s random ones.
///
/// [DefaultShuffleOrder.insert] drops each new item at a random play position,
/// so play-next / add-to-queue / reorder land wherever the dice say while
/// shuffle is on. The owning handler decides where an insert belongs by
/// calling [routeInsertAppend] / [routeInsertAtPlayPosition] immediately
/// before the player mutation that triggers [insert]. An unrouted insert is
/// appended to the tail.
///
/// [shuffle] mirrors [DefaultShuffleOrder.shuffle]: a random permutation with
/// [initialIndex] anchored at the head of the play order.
///
/// [insert] and [removeRange] keep the same base-index bookkeeping as
/// [DefaultShuffleOrder] (offset on insert; remove + offset on removeRange),
/// which composes correctly for every mutation path the player performs,
/// including the remove+insert pair that the player's move operation issues
/// (the offsets cancel when the move is a no-op on the base list, and net to
/// the true base shift when it is not).
class ExactPositionShuffleOrder extends ShuffleOrder {
  ExactPositionShuffleOrder({Random? random}) : _random = random ?? Random();

  final Random _random;

  /// Base indices in play order.
  @override
  final List<int> indices = [];

  int? _nextInsertAtPlayPosition;

  /// The next [insert] appends the new items to the tail of the play order
  /// (add-to-queue).
  void routeInsertAppend() {
    _nextInsertAtPlayPosition = null;
  }

  /// The next [insert] places the new items at [playPosition] in the play
  /// order, in post-removal coordinates when the same player mutation removed
  /// an item first (play-next, reorder).
  void routeInsertAtPlayPosition(int playPosition) {
    _nextInsertAtPlayPosition = playPosition;
  }

  /// Replaces the current play order with [order] (base indices in play
  /// order). A8 restore: the persisted permutation is seeded here after the
  /// load (which re-randomised [indices] but harmlessly, because the load
  /// ran with shuffle off) and before shuffle is re-enabled, so the restored
  /// order is the one that was persisted, not a fresh random one.
  void seedIndices(List<int> order) {
    indices
      ..clear()
      ..addAll(order);
    _nextInsertAtPlayPosition = null;
  }

  @override
  void shuffle({int? initialIndex}) {
    assert(initialIndex == null || indices.contains(initialIndex));
    if (indices.length <= 1) return;
    indices.shuffle(_random);
    if (initialIndex == null) return;

    const initialPos = 0;
    final swapPos = indices.indexOf(initialIndex);
    // Swap the indices at initialPos and swapPos.
    final swapIndex = indices[initialPos];
    indices[initialPos] = initialIndex;
    indices[swapPos] = swapIndex;
  }

  @override
  void insert(int index, int count) {
    final atPlayPosition = _nextInsertAtPlayPosition;
    _nextInsertAtPlayPosition = null;
    // Offset indices after insertion point.
    for (var i = 0; i < indices.length; i++) {
      if (indices[i] >= index) {
        indices[i] += count;
      }
    }
    final newIndices = List.generate(count, (i) => index + i);
    if (atPlayPosition == null) {
      indices.addAll(newIndices);
    } else {
      final at = atPlayPosition.clamp(0, indices.length);
      indices.insertAll(at, newIndices);
    }
  }

  @override
  void removeRange(int start, int end) {
    final count = end - start;
    // Remove old indices.
    final oldIndices = List.generate(count, (i) => start + i).toSet();
    indices.removeWhere(oldIndices.contains);
    // Offset indices after deletion point.
    for (var i = 0; i < indices.length; i++) {
      if (indices[i] >= end) {
        indices[i] -= count;
      }
    }
  }

  @override
  void clear() {
    indices.clear();
    _nextInsertAtPlayPosition = null;
  }
}
