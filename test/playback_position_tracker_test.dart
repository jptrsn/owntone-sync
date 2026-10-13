import 'package:flutter_test/flutter_test.dart';
import 'package:owntone_sync/presentation/services/audio_handler.dart';
import 'package:owntone_sync/presentation/services/playback_position_tracker.dart';

/// Invariant 46 (position resets only on a real current-track change; a
/// restore anchors the persisted position) and invariant 25(c) (tick
/// persists are bounded to the 5000 ms rule). The QA-11 evidence
/// (/tmp/owntone_verify/qa11_*.db + the instrumented run) shows the
/// pre-fix failure these pin: just_audio 0.10.6 re-broadcasts the
/// sequence state on every playback event and in the restore's
/// load/seek burst, and treating each emission as a track change
/// persisted 0 over the restored/paused position.
void main() {
  SequenceSnapshot snap(
    List<int> ids,
    int? currentIndex, {
    List<int>? shuffleIndices,
  }) {
    return SequenceSnapshot(
      baseIds: List<int>.unmodifiable(ids),
      currentIndex: currentIndex,
      shuffleIndices:
          List<int>.unmodifiable(shuffleIndices ?? List<int>.of(ids)),
    );
  }

  final ids33 = List<int>.generate(33, (i) => 1800 + i); // stand-in queue

  group('invariant 46: re-emissions with an unchanged current track', () {
    test('keep the live position across same-track re-emissions', () {
      final t = PlaybackPositionTracker();
      t.onSnapshot(snap(ids33, 32)); // first sight: a track change, resets
      t.onTick(const Duration(milliseconds: 61300));
      t.markPersisted(61300);

      // Sparse platform events re-broadcast the identical state
      // (just_audio `_currentIndexSubscription`); none of them may zero
      // the position that a pause/restore just persisted.
      for (var i = 0; i < 5; i++) {
        expect(t.onSnapshot(snap(ids33, 32)), const Duration(milliseconds: 61300));
      }
      expect(t.position, const Duration(milliseconds: 61300));
    });

    test('restore burst: anchor wins over late re-emissions', () {
      // The instrumented QA-11 restore sequence: the platform settles the
      // current index mid-burst (0 -> 32), the seek lands, and a final
      // re-emission arrives after the restore has returned.
      final t = PlaybackPositionTracker();
      t.onSnapshot(snap(ids33, 0));
      t.onSnapshot(snap(ids33, 0));
      t.onSnapshot(snap(ids33, 32)); // platform settles: a real change
      t.onTick(const Duration(milliseconds: 61300)); // seek landed
      t.anchor(61300);
      expect(t.position, const Duration(milliseconds: 61300));

      // Late re-emission, same current track: the anchored position must
      // survive, not be reset to the load-time 0.
      expect(t.onSnapshot(snap(ids33, 32)), const Duration(milliseconds: 61300));
      expect(t.onSnapshot(snap(ids33, 32)), const Duration(milliseconds: 61300));
    });

    test('anchor re-arms the tick cadence from the restored value', () {
      final t = PlaybackPositionTracker();
      t.onSnapshot(snap(ids33, 32));
      t.anchor(61300);
      t.markPersisted(61300);

      // Resuming playback: ticks inside 5 s of the restored position do
      // not persist; the first tick at or beyond 5 s does.
      expect(t.onTick(const Duration(milliseconds: 63000)), isFalse);
      expect(t.onTick(const Duration(milliseconds: 66299)), isFalse);
      expect(t.onTick(const Duration(milliseconds: 66300)), isTrue);
    });
  });

  group('invariant 46: a real current-track change still resets', () {
    test('a different current track zeros the persisted position', () {
      final t = PlaybackPositionTracker();
      t.onSnapshot(snap(ids33, 32));
      t.onTick(const Duration(milliseconds: 61300));
      t.markPersisted(61300);

      // Auto-advance / skip: the previous track's position must not be
      // written under the new one (invariant 25's track-change rule).
      expect(t.onSnapshot(snap(ids33, 5)), Duration.zero);
      expect(t.position, Duration.zero);
      expect(t.currentTrackId, ids33[5]);
    });

    test('tick persists are suppressed until the reset persist lands', () {
      final t = PlaybackPositionTracker();
      t.onSnapshot(snap(ids33, 32));
      t.onTick(const Duration(milliseconds: 61300));
      t.markPersisted(61300);

      t.onSnapshot(snap(ids33, 5)); // track change: -1 again
      // The new track's ticks must not persist before its own 0-persist
      // has landed (the old track's position must not leak into it).
      expect(t.onTick(const Duration(milliseconds: 9000)), isFalse);
      t.markPersisted(0);
      expect(t.onTick(const Duration(milliseconds: 5000)), isTrue);
    });

    test('clearing the queue nulls the tracked track, so replaying it is a change', () {
      final t = PlaybackPositionTracker();
      t.onSnapshot(snap(ids33, 32));
      t.onTick(const Duration(milliseconds: 61300));
      t.currentTrackId = null; // the controller's empty-snapshot branch

      expect(t.onSnapshot(snap(ids33, 32)), Duration.zero);
    });
  });

  group('invariant 25(c): the tick rule', () {
    test('no persist within 5000 ms of the last persisted position', () {
      final t = PlaybackPositionTracker();
      t.onSnapshot(snap(ids33, 32));
      t.markPersisted(10000);

      expect(t.onTick(const Duration(milliseconds: 12000)), isFalse);
      expect(t.onTick(const Duration(milliseconds: 14999)), isFalse);
      expect(t.onTick(const Duration(milliseconds: 15000)), isTrue);
    });

    test('a backward jump of at least 5000 ms also triggers', () {
      final t = PlaybackPositionTracker();
      t.onSnapshot(snap(ids33, 32));
      t.markPersisted(60000);

      // User dragged the slider back past the 5 s window.
      expect(t.onTick(const Duration(milliseconds: 55001)), isFalse);
      expect(t.onTick(const Duration(milliseconds: 55000)), isTrue);
    });
  });
}
