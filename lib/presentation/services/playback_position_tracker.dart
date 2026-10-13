import 'audio_handler.dart';

/// A8 persistence: what position to write, and when.
///
/// just_audio 0.10.6 re-broadcasts the sequence state on **every** playback
/// event — `AudioPlayer._currentIndexSubscription` (just_audio.dart) does
/// `_sequenceStateSubject.add(sequenceState.copyWith(currentIndex: ...))`
/// for each sparse platform position event, and again through the
/// load/seek/setLoopMode burst of a cold-start restore. Most of those
/// emissions carry an unchanged queue and an unchanged current track.
///
/// Treating every emission as a track change (the pre-QA-11 behaviour)
/// reset the tracked position to zero and persisted it each time: the
/// restore burst left the `playback_state` row at 0 while the live session
/// held the restored position, sparse platform events (~26–44 s apart,
/// invariant 1) re-zeroed the row mid-playback, and while paused — where
/// no position ticks flow to heal the row — the 0 stuck. Observed on the
/// Pixel 6 in QA-11 (/tmp/owntone_verify/qa11_*.db): kill-while-paused at
/// 61.3 s restored 0.
///
/// The rule this class encodes: **only a real current-track change resets
/// the position.** A re-emission with the same current track keeps the
/// live position, and [anchor] pins a restored position where a later
/// re-emission cannot dislodge it.
class PlaybackPositionTracker {
  /// The current track id derived from the last non-empty snapshot, or
  /// null before the first snapshot / after the queue was emptied.
  int? currentTrackId;

  /// The position the next persist should write: the live position from
  /// the latest tick, zeroed by a real track change, or the anchored
  /// restored position.
  Duration position = Duration.zero;

  int _lastPersistedMs = -1;

  /// Feed a non-empty sequence snapshot. Returns the position the caller
  /// should persist now.
  ///
  /// A change of the current track id resets [position] to zero (the new
  /// track starts at the beginning; the previous track's position must not
  /// be written under the new one) and suppresses tick persists until the
  /// first persist lands. An emission with the current track unchanged is a
  /// re-broadcast, not a track change: the live position is kept.
  Duration onSnapshot(SequenceSnapshot snap) {
    final i = snap.currentIndex;
    final id = (i != null && i >= 0 && i < snap.baseIds.length)
        ? snap.baseIds[i]
        : null;
    if (id != currentTrackId) {
      currentTrackId = id;
      position = Duration.zero;
      _lastPersistedMs = -1;
    }
    return position;
  }

  /// Feed a position tick. Returns true when a persist is due: at least
  /// 5000 ms from the last persisted position (the invariant-25(c) tick
  /// rule), and only once a persist has landed for the current track
  /// (`_lastPersistedMs >= 0`).
  bool onTick(Duration pos) {
    position = pos;
    if (_lastPersistedMs < 0) return false;
    return (pos.inMilliseconds - _lastPersistedMs).abs() >= 5000;
  }

  /// Record that a persist of [ms] actually landed in the DB, anchoring
  /// the next tick cadence to the value that was written.
  void markPersisted(int ms) {
    _lastPersistedMs = ms;
  }

  /// Cold-start restore: pin the tracked position to the restored value
  /// (the caller persists it immediately). The restore's load/seek burst
  /// keeps re-emitting the sequence state afterwards — including after the
  /// restore has returned — and those re-emissions must not reset the
  /// position back to zero (invariant 46).
  void anchor(int ms) {
    position = Duration(milliseconds: ms);
    _lastPersistedMs = ms;
  }
}
