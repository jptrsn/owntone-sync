// Issue #21: end-of-queue left the media session projecting PLAYING with a
// frozen position because just_audio's play() keeps `playing` true through
// completion and the handler republished it verbatim.
//
// Guards (per .ai-dlc/night-2026-11-28/plans/21.md):
//   AC1 / A6 / A9 MUST-NOT / inv 24  — T1
//   AC2 / A8 / inv 16                — T2
//   AC4 / inv 55 (click funnel)      — T3
//   inv 9 / inv 13 (finish ≠ skip)   — T4
//   AC3 / A8 MUST / inv 25           — T5
//
// Harness rules followed (inv 36/48): plain test(), no mocking libraries,
// no network, no AudioService.init. Fake platform extracted to
// fake_just_audio_platform.dart (plan file set) per just_audio's own
// test/just_audio_test.dart pattern. T2 pumps MiniPlayer directly under a
// real PlaybackController (the helpers' pumpScreen pumps whole screens with
// channel mocks; only the controller seam is needed here) and overrides
// PlaybackController.positionData because AudioService.position needs the
// static handler installed by AudioService.init, which these tests do not
// run (documented deviation in the build report). T2 also carries a
// presence control: the button's StreamBuilder renders "Play" on its
// pre-first-value branch, so the test first proves the subscription can
// render Pause before trusting its absence (verification-protocol §4).

import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';
import 'package:provider/provider.dart';
import 'package:rxdart/rxdart.dart';

import 'package:owntone_sync/data/repositories/local_database_repository.dart';
import 'package:owntone_sync/presentation/controllers/playback_controller.dart';
import 'package:owntone_sync/presentation/services/audio_handler.dart';
import 'package:owntone_sync/presentation/services/playback_stats_recorder.dart';
import 'package:owntone_sync/presentation/widgets/mini_player.dart';
import 'package:owntone_sync/presentation/services/track_uri_resolver.dart';

import 'fake_just_audio_platform.dart';

MediaItem _track({int id = 42, Duration duration = const Duration(minutes: 3)}) {
  return MediaItem(
    id: id.toString(),
    title: 'Track $id',
    artist: 'Artist',
    duration: duration,
    extras: {'uri': 'file:///sdcard/Music/tracks/track_$id.mp3'},
  );
}

/// Loads [tracks] through the handler and lets the platform complete them
/// naturally while playing — the exact T1 sequence.
Future<({OwnToneAudioHandler handler, FakeAudioPlayerPlatform player})>
    _playToNaturalEndOfQueue(List<MediaItem> tracks) async {
  final platform = FakeJustAudioPlatform();
  JustAudioPlatform.instance = platform;
  final handler = OwnToneAudioHandler();
  await handler.playCollection(tracks);
  await pumpEventQueue();
  final player = platform.only;
  // Control for VERIFY-LIVE-4: play really was requested before completion,
  // i.e. the completed event arrives while the player data is playing=true.
  expect(player.requests, contains('play'));
  player.completeNaturally();
  await pumpEventQueue();
  return (handler: handler, player: player);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const audioSessionChannel = MethodChannel('com.ryanheise.audio_session');

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioSessionChannel, (
          MethodCall methodCall,
        ) async {
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(audioSessionChannel, null);
  });

  test(
    'T1 end-of-queue completed publishes a stopped-shape projection (AC1, '
    'A6, A9 MUST-NOT, inv 24)',
    () async {
      final fixture = await _playToNaturalEndOfQueue([_track()]);
      addTearDown(fixture.handler.dispose);

      expect(fixture.handler.playbackState.value.playing, isFalse);
      expect(
        fixture.handler.playbackState.value.processingState,
        AudioProcessingState.completed,
      );
      // completed + playing=false maps to STATE_PAUSED on the Java side
      // (AudioService.java:601-617).
      expect(fixture.player.requests, contains('pause'));
    },
  );

  testWidgets(
    'T2 mini player shows Play after end-of-queue (AC2, A8, inv 16)',
    (tester) async {
      late ({OwnToneAudioHandler handler, FakeAudioPlayerPlatform player})
          fixture;
      await tester.runAsync(() async {
        fixture = await _playToNaturalEndOfQueue([_track()]);
      });
      addTearDown(fixture.handler.dispose);

      final controller = _MiniPlayerHarnessController.forHandler(
        fixture.handler,
      );
      await tester.pumpWidget(
        Provider<PlaybackController>.value(
          value: controller,
          child: MaterialApp(home: const Scaffold(body: MiniPlayer())),
        ),
      );

      // Control (verification-protocol §4): the mini player's button is a
      // StreamBuilder whose pre-first-value branch also renders "Play", so
      // asserting "Play" alone cannot tell a settled projection from a dead
      // subscription. First prove the subscription CAN render Pause:
      // publish playing=true and pump until it appears. The 10-frame loop
      // is load-bearing: the handler's BehaviorSubject delivery needs more
      // than one pump (observed: tooltip still default after pump 1,
      // converged by pump 11).
      final healed = fixture.handler.playbackState.value;
      expect(healed.playing, isFalse);
      await tester.runAsync(() async {
        fixture.handler.playbackState.add(healed.copyWith(playing: true));
        await pumpEventQueue();
      });
      var sawPause = false;
      for (var i = 0; i < 30 && !sawPause; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        sawPause = find.byTooltip('Pause').evaluate().isNotEmpty;
      }
      expect(sawPause, isTrue, reason: 'harness cannot observe playing=true');

      // The state under test: restore the projection the end-of-queue heal
      // actually produced (playing=false + completed) and assert it renders
      // as Play with no Pause lingering.
      await tester.runAsync(() async {
        fixture.handler.playbackState.add(healed);
        await pumpEventQueue();
      });
      var settled = false;
      for (var i = 0; i < 30 && !settled; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        settled =
            find.byTooltip('Play').evaluate().isNotEmpty &&
            find.byTooltip('Pause').evaluate().isEmpty;
      }
      expect(find.byTooltip('Play'), findsOneWidget);
      expect(find.byTooltip('Pause'), findsNothing);
      await controller.shutdown();
    },
  );

  test(
    'T3 click(media) from completed issues seek then play (AC4, A6, inv 55)',
    () async {
      final fixture = await _playToNaturalEndOfQueue([_track()]);
      addTearDown(fixture.handler.dispose);

      // Projection is healed (playing=false), so BaseAudioHandler.click maps
      // onto play() (audio_service 0.18.19 audio_service.dart:3089-3105).
      await fixture.handler.click();
      await pumpEventQueue();

      final requests = fixture.player.requests;
      expect(requests.sublist(requests.length - 2), ['seek', 'play']);
      expect(
        fixture.player.seekPositions.last,
        Duration.zero,
        reason: 'play-from-completed must rewind (A4 control on device: '
            'play without seek leaves the projection PLAYING with position '
            'pinned at the end)',
      );
    },
  );

  test(
    'T4 natural end-of-queue heals without recording a skip (inv 9, inv 13)',
    () async {
      final platform = FakeJustAudioPlatform();
      JustAudioPlatform.instance = platform;
      final handler = OwnToneAudioHandler();
      addTearDown(handler.dispose);

      final position = StreamController<Duration>();
      final recorded = <PendingEvent>[];
      final recorder = PlaybackStatsRecorder(
        mediaItem: handler.mediaItem,
        playbackState: handler.playbackState,
        durationStream: handler.durationStream,
        position: position.stream,
        consumeUserInitiatedTransition: handler.consumeUserInitiatedTransition,
        insertEvent: (event) async {
          recorded.add(event);
          return recorded.length;
        },
      );
      addTearDown(recorder.dispose);
      recorder.start();

      const length = Duration(seconds: 10);
      await handler.playCollection([_track(duration: length)]);
      await pumpEventQueue();

      // Listen past the threshold (min(0.9 * 10s, 4min) = 9s) in <=1000ms
      // steps so every delta counts as listening.
      for (var ms = 500; ms <= 10000; ms += 500) {
        position.add(Duration(milliseconds: ms));
      }
      await pumpEventQueue();

      final player = platform.only;
      expect(player.requests, contains('play'));
      player.completeNaturally();
      await pumpEventQueue();

      // The heal's pause() must not fabricate or flip any stats event: the
      // finish is a 'play', never a 'skip'.
      expect(recorded.map((e) => e.eventType), ['play']);
      expect(recorded.single.trackId, 42);
      expect(handler.playbackState.value.playing, isFalse);

      await position.close();
    },
  );

  test(
    'T5 restore still leaves the projection paused (AC3, A8 MUST, inv 25)',
    () async {
      final platform = FakeJustAudioPlatform();
      JustAudioPlatform.instance = platform;
      final handler = OwnToneAudioHandler();
      addTearDown(handler.dispose);

      await handler.restoreCollection(
        tracks: [_track(id: 42), _track(id: 43)],
        startIndex: 1,
        position: const Duration(seconds: 37),
        repeatMode: AudioServiceRepeatMode.none,
        shuffleEnabled: false,
        shuffleIndices: const [0, 1],
      );
      await pumpEventQueue();

      final player = platform.only;
      expect(player.requests, isNot(contains('play')));
      expect(handler.playbackState.value.playing, isFalse);
      // Sanity: the restore did load/seek (paused-restore is real, not a
      // no-op that would trivially pass).
      expect(player.requests, containsAllInOrder(['load', 'seek']));
    },
  );
}

/// T2 harness: [PlaybackController.positionData] pulls
/// [AudioService.position], which requires the static handler installed by
/// `AudioService.init` (not run here — no AudioService.init per the plan's
/// harness rules). The override replaces only that one stream; the play/pause
/// button under test reads [PlaybackController.playbackState] verbatim.
class _MiniPlayerHarnessController extends PlaybackController {
  _MiniPlayerHarnessController._({
    required super.handler,
    required super.resolver,
    required super.dbRepo,
  });

  factory _MiniPlayerHarnessController.forHandler(
    OwnToneAudioHandler handler,
  ) {
    final dbRepo = LocalDatabaseRepository();
    return _MiniPlayerHarnessController._(
      handler: handler,
      resolver: TrackUriResolver(dbRepo: dbRepo),
      dbRepo: dbRepo,
    );
  }

  final BehaviorSubject<PositionData> _positionData =
      BehaviorSubject<PositionData>.seeded(
        const PositionData(
          position: Duration.zero,
          bufferedPosition: Duration.zero,
          duration: null,
        ),
      );

  @override
  Stream<PositionData> get positionData => _positionData.stream;

  Future<void> shutdown() async {
    await _positionData.close();
  }
}
