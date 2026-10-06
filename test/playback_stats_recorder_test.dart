import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:owntone_sync/data/repositories/local_database_repository.dart';
import 'package:owntone_sync/presentation/services/playback_stats_recorder.dart';

/// Drives the real [PlaybackStatsRecorder] with the four injected streams,
/// a controllable user-intent flag, and a capturing fake insertEvent — no
/// mocking package, exactly the seams the production constructor exposes.
class RecorderHarness {
  final StreamController<MediaItem?> mediaItem = StreamController<MediaItem?>();
  final StreamController<PlaybackState> playbackState =
      StreamController<PlaybackState>();
  final StreamController<Duration?> duration =
      StreamController<Duration?>();
  final StreamController<Duration> position = StreamController<Duration>();

  final List<PendingEvent> events = [];
  bool userInitiated = false;
  int consumeCalls = 0;

  late PlaybackStatsRecorder recorder;

  RecorderHarness() {
    recorder = PlaybackStatsRecorder(
      mediaItem: mediaItem.stream,
      playbackState: playbackState.stream,
      durationStream: duration.stream,
      position: position.stream,
      consumeUserInitiatedTransition: () {
        consumeCalls++;
        return userInitiated;
      },
      insertEvent: (event) async {
        events.add(event);
        return events.length;
      },
    );
    recorder.start();
  }

  void startTrack(int id, {Duration? trackDuration}) {
    mediaItem.add(MediaItem(
      id: id.toString(),
      title: 'Track $id',
      duration: trackDuration,
    ));
  }

  void setState({
    bool playing = true,
    AudioServiceRepeatMode repeatMode = AudioServiceRepeatMode.none,
  }) {
    playbackState.add(PlaybackState(playing: playing, repeatMode: repeatMode));
  }

  int _lastMs = 0;

  void setPosition(int milliseconds) {
    _lastMs = milliseconds;
    position.add(Duration(milliseconds: milliseconds));
  }

  /// Emits forward position ticks of at most [stepMs] until [totalMs],
  /// continuing from the last emitted position. Each delta is real
  /// listening time (the recorder's <=1000ms rule).
  void pumpListening(int totalMs, {int stepMs = 500}) {
    var pos = _lastMs;
    while (pos < totalMs) {
      pos += stepMs;
      if (pos > totalMs) pos = totalMs;
      setPosition(pos);
    }
  }

  /// Lets the recorder's async event writes settle.
  Future<void> settle() => Future<void>.delayed(const Duration(milliseconds: 10));

  List<PendingEvent> eventsFor(int trackId) =>
      events.where((e) => e.trackId == trackId).toList();

  List<String> eventTypesFor(int trackId) =>
      eventsFor(trackId).map((e) => e.eventType).toList();

  Future<void> dispose() async {
    recorder.dispose();
    await mediaItem.close();
    await playbackState.close();
    await duration.close();
    await position.close();
  }
}

void main() {
  late RecorderHarness h;

  setUp(() {
    h = RecorderHarness();
  });

  tearDown(() async {
    await h.dispose();
  });

  const Duration threeMinutes = Duration(minutes: 3);

  test('natural completion records a play and never a skip '
      '(invariant 9 — the original defect this project exists to correct)',
      () async {
    h.startTrack(1, trackDuration: threeMinutes);
    h.setState();
    // Listens past the 90% threshold (162s of 180s), then the track ends
    // and the player auto-advances: the intent flag is NOT set.
    h.pumpListening(170000);
    await h.settle();
    expect(h.eventTypesFor(1), ['play']);
    expect(h.eventsFor(1).length, 1);

    h.userInitiated = false;
    h.startTrack(2, trackDuration: threeMinutes);
    await h.settle();

    // No skip may exist for the completed track — auto-advance is not a
    // user move (invariant 13: flag false = never a skip).
    expect(h.eventTypesFor(1), ['play']);
    expect(h.events.where((e) => e.eventType == 'skip'), isEmpty);
  });

  test('a user-initiated transition below threshold records a skip '
      '(invariant 13: the flag is the only skip signal)', () async {
    h.startTrack(1, trackDuration: threeMinutes);
    h.setState();
    h.pumpListening(10000); // 10s: above the 2s floor, far below 162s.
    await h.settle();
    expect(h.eventsFor(1), isEmpty);

    h.userInitiated = true;
    h.startTrack(2, trackDuration: threeMinutes);
    await h.settle();

    expect(h.eventTypesFor(1), ['skip']);
    expect(h.eventsFor(2), isEmpty);
  });

  test('play threshold is 90% of duration when that is under 4 minutes '
      '(invariant 15: min(0.9 x duration, 4 min))', () async {
    // 180s track: threshold = 162000ms (the 4-min cap does not bind).
    h.startTrack(1, trackDuration: threeMinutes);
    h.setState();
    h.pumpListening(161500);
    await h.settle();
    expect(h.eventsFor(1), isEmpty,
        reason: '161.5s < 162s must not be a play yet');
    h.pumpListening(162000);
    await h.settle();
    expect(h.eventTypesFor(1), ['play'],
        reason: 'crossing 162s (90% of 180s) must record the play');
  });

  test('play threshold is capped at 4 minutes for long tracks '
      '(invariant 15: min(0.9 x duration, 4 min))', () async {
    // 10-min track: 90% would be 540s, the cap makes it 240s.
    h.startTrack(1, trackDuration: const Duration(minutes: 10));
    h.setState();
    h.pumpListening(239500);
    await h.settle();
    expect(h.eventsFor(1), isEmpty,
        reason: '239.5s < 240s must not be a play yet');
    h.pumpListening(240000);
    await h.settle();
    expect(h.eventTypesFor(1), ['play'],
        reason: 'a 10-min track must count as played at 4 minutes, not 540s');
  });

  test('the ~2s floor suppresses a skip on a track barely started '
      '(invariant 15: pause-immediately noise must not become a skip)',
      () async {
    h.startTrack(1, trackDuration: threeMinutes);
    h.setState();
    h.pumpListening(1500); // below the 2000ms floor
    await h.settle();

    h.userInitiated = true;
    h.startTrack(2, trackDuration: threeMinutes);
    await h.settle();

    expect(h.eventsFor(1), isEmpty, reason: '1.5s is below the skip floor');
    expect(h.events, isEmpty);
  });

  test('at most one play per pass; a repeat-one restart starts a new pass '
      '(invariant 15)', () async {
    h.startTrack(1, trackDuration: threeMinutes);
    h.setState(repeatMode: AudioServiceRepeatMode.one);
    h.pumpListening(170000);
    await h.settle();
    expect(h.eventTypesFor(1), ['play']);

    // Keep listening to the end: still exactly one play for this pass.
    h.pumpListening(180000);
    await h.settle();
    expect(h.eventTypesFor(1), ['play']);

    // Repeat-one loop restart: the position jumps backwards to 0.
    h.setPosition(0);
    // The next forward tick resets the accumulator (0 < threshold) and,
    // because repeat mode is one, clears the play flag — a new pass begins.
    h.setPosition(500);
    // 161.5s more real listening crosses the 162s threshold of the new pass.
    h.pumpListening(162500);
    await h.settle();

    expect(h.eventTypesFor(1), ['play', 'play'],
        reason: 'one play per pass; the loop restart is a new pass');
  });

  test('seeking forward past the threshold does NOT manufacture a play — '
      'only accumulated listening counts (invariant 14)', () async {
    // 300s track: threshold = min(270s, 240s) = 240s.
    h.startTrack(1, trackDuration: const Duration(minutes: 5));
    h.setState();
    h.pumpListening(10000); // 10s of real listening
    await h.settle();

    // A forward seek jumps 210s in one delta (>1000ms): it must not count.
    h.setPosition(220000);
    await h.settle();
    expect(h.eventsFor(1), isEmpty,
        reason: 'absolute position 220s is under the 240s threshold, and '
            'even beyond it the seek itself is not listening');

    // Continue listening for 80s of real time after the seek: 10s + 80s =
    // 90s total, far below 240s — still no play.
    h.pumpListening(300000);
    await h.settle();
    expect(h.eventsFor(1), isEmpty,
        reason: 'only accumulated listening counts, not where the playhead '
            'was put');

    // The 90s of real listening IS a legitimate skip if the user moves on.
    h.userInitiated = true;
    h.startTrack(2, trackDuration: threeMinutes);
    await h.settle();
    expect(h.eventTypesFor(1), ['skip']);
  });

  test('an error-skip (A9 auto-advance) records nothing '
      '(invariants 13 and 24: the error path clears the intent flag)',
      () async {
    h.startTrack(1, trackDuration: threeMinutes);
    h.setState();
    h.pumpListening(30000); // 30s: would be a skip if attributed to the user
    await h.settle();

    // A9 advanced the player; consumeUserInitiatedTransition() returned
    // false because the error path cleared the marker.
    h.userInitiated = false;
    h.startTrack(2, trackDuration: threeMinutes);
    await h.settle();

    expect(h.eventsFor(1), isEmpty,
        reason: 'an auto-advance past a failed track is not a user skip');
  });

  test('a user move after the play was recorded does not also record a skip '
      '(invariant 15: a skip is only written below the threshold)',
      () async {
    h.startTrack(1, trackDuration: threeMinutes);
    h.setState();
    h.pumpListening(162000);
    await h.settle();
    expect(h.eventTypesFor(1), ['play']);

    h.userInitiated = true;
    h.startTrack(2, trackDuration: threeMinutes);
    await h.settle();

    expect(h.eventTypesFor(1), ['play'],
        reason: 'a fully-listened track is a play, not a play and a skip');
  });

  test('position ticks while paused do not count as listening '
      '(invariant 15: pause writes nothing)', () async {
    h.startTrack(1, trackDuration: threeMinutes);
    h.setState();
    h.pumpListening(5000); // 5s of real listening
    await h.settle();

    h.setState(playing: false);
    // 200 ticks of a frozen-then-drifting playhead while paused. If these
    // counted, the track would cross its 162s threshold.
    for (var i = 1; i <= 200; i++) {
      h.setPosition(5000 + i * 1000);
    }
    await h.settle();
    expect(h.eventsFor(1), isEmpty,
        reason: 'paused ticks must not accumulate listening time');

    h.userInitiated = true;
    h.startTrack(2, trackDuration: threeMinutes);
    await h.settle();
    // The 5s of real listening is a legitimate skip; a false play would
    // have suppressed it.
    expect(h.eventTypesFor(1), ['skip']);
  });

  test('a backward seek resets the accumulated time below the threshold '
      '(invariant 14: no second play for the same pass)', () async {
    h.startTrack(1, trackDuration: threeMinutes);
    h.setState();
    h.pumpListening(100000); // 100s < 162s
    await h.settle();
    expect(h.eventsFor(1), isEmpty);

    // Seek back to 10s; the next forward tick applies the reset.
    h.setPosition(10000);
    h.setPosition(10500);
    h.pumpListening(72500); // +62s of real listening
    await h.settle();
    expect(h.eventsFor(1), isEmpty,
        reason: '100s + 62s of wall listening must not count — the backward '
            'seek restarted the pass at 0');

    // Cross the threshold from the reset point: one play, from the new pass.
    h.pumpListening(172500);
    await h.settle();
    expect(h.eventTypesFor(1), ['play']);
  });

  test('the backward reset is deferred until the next forward tick of the '
      'same track, so a user skip in between still sees the old track\'s '
      'time (invariant 14)', () async {
    h.startTrack(1, trackDuration: threeMinutes);
    h.setState();
    h.pumpListening(10000); // 10s
    await h.settle();

    // User seeks back, then — before any forward tick — moves to the next
    // track. The reset is still pending, so the 10s is intact when the
    // skip is evaluated.
    h.setPosition(0);
    h.userInitiated = true;
    h.startTrack(2, trackDuration: threeMinutes);
    await h.settle();

    expect(h.eventTypesFor(1), ['skip'],
        reason: 'if the reset applied immediately the 10s would be wiped '
            'and the floor would suppress the skip');
  });
}
