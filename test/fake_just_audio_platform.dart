// A minimal JustAudioPlatform/AudioPlayerPlatform double following just_audio
// 0.10.6's own unit-test pattern (test/just_audio_test.dart): it records
// method requests in arrival order and lets tests push PlaybackEventMessage /
// PlayerDataMessage, echoing a platform event on pause/play/seek requests.
//
// No mocking library is installed (invariants 36/48 harness rules); this is
// the "extend the helpers" pattern of RecorderHarness
// (playback_stats_recorder_test.dart) and the channel mocks of
// widget_test_helpers.dart. just_audio_platform_interface is already in the
// dependency graph via just_audio (pubspec.lock) — zero new dependencies.
//
// Event fidelity (verified against the pinned 0.10.6 sources):
//  - play()/pause() flip playing via PlayerEvent, never the processingState
//    carried by the platform event (just_audio.dart AudioPlayer.play/pause);
//    completing therefore arrives with `playing` still true — the exact
//    ordering behind issue #21.
//  - seek() from completed emits a fresh event (updateTime changes), matching
//    just_audio's own seek() which always re-emits.

import 'dart:async';

// Transitive of just_audio, version-pinned in the lockfile by it; adding a
// direct dev-dependency needs the user's approval, this is the zero-dep path.
// ignore: depend_on_referenced_packages
import 'package:just_audio_platform_interface/just_audio_platform_interface.dart';

class FakeAudioPlayerPlatform extends AudioPlayerPlatform {
  FakeAudioPlayerPlatform(super.id);

  final StreamController<PlaybackEventMessage> _events =
      StreamController<PlaybackEventMessage>.broadcast();
  final StreamController<PlayerDataMessage> _data =
      StreamController<PlayerDataMessage>.broadcast();

  /// Platform-side contract calls, in arrival order.
  final List<String> requests = [];

  /// Positions passed to seek(), in arrival order.
  final List<Duration?> seekPositions = [];

  ProcessingStateMessage _processingState = ProcessingStateMessage.idle;
  int? _index;
  Duration _position = Duration.zero;
  Duration? _duration;

  @override
  Stream<PlaybackEventMessage> get playbackEventMessageStream => _events.stream;

  @override
  Stream<PlayerDataMessage> get playerDataMessageStream => _data.stream;

  void _emit() {
    _events.add(
      PlaybackEventMessage(
        processingState: _processingState,
        updateTime: DateTime.now(),
        updatePosition: _position,
        bufferedPosition: _position,
        duration: _duration,
        icyMetadata: null,
        currentIndex: _index,
        androidAudioSessionId: null,
      ),
    );
  }

  /// Natural completion of the last source while the platform is playing:
  /// processingState becomes completed, the position sits at the end, and
  /// `playing` is NOT touched (the just_audio 0.10.6 play() contract,
  /// just_audio.dart:1074-1078 — the exact ordering that produced #21).
  void completeNaturally() {
    _processingState = ProcessingStateMessage.completed;
    final duration = _duration;
    if (duration != null) _position = duration;
    _emit();
  }

  void close() {
    _events.close();
    _data.close();
  }

  @override
  Future<LoadResponse> load(LoadRequest request) async {
    requests.add('load');
    _processingState = ProcessingStateMessage.ready;
    _index = request.initialIndex ?? 0;
    _position = request.initialPosition ?? Duration.zero;
    _emit();
    return LoadResponse(duration: _duration);
  }

  @override
  Future<PlayResponse> play(PlayRequest request) async {
    requests.add('play');
    _data.add(PlayerDataMessage(playing: true));
    // A completed ExoPlayer accepts play() (playWhenReady=true) but stays
    // parked at the end of the last source until seeked — the device-verified
    // behaviour that makes the seek-zero in play() necessary.
    return PlayResponse();
  }

  @override
  Future<PauseResponse> pause(PauseRequest request) async {
    requests.add('pause');
    _data.add(PlayerDataMessage(playing: false));
    // Echo, preserving processingState (a pause on a completed player keeps
    // it completed — device witness: state PAUSED with completed metadata).
    _emit();
    return PauseResponse();
  }

  @override
  Future<SeekResponse> seek(SeekRequest request) async {
    requests.add('seek');
    seekPositions.add(request.position);
    if (request.position != null) _position = request.position!;
    if (request.index != null) _index = request.index;
    if (_processingState == ProcessingStateMessage.completed) {
      _processingState = ProcessingStateMessage.ready;
    }
    _emit();
    return SeekResponse();
  }

  @override
  Future<SetLoopModeResponse> setLoopMode(SetLoopModeRequest request) async {
    requests.add('setLoopMode');
    return SetLoopModeResponse();
  }

  @override
  Future<SetVolumeResponse> setVolume(SetVolumeRequest request) async {
    requests.add('setVolume');
    return SetVolumeResponse();
  }

  @override
  Future<SetSpeedResponse> setSpeed(SetSpeedRequest request) async {
    requests.add('setSpeed');
    return SetSpeedResponse();
  }

  @override
  Future<SetPitchResponse> setPitch(SetPitchRequest request) async {
    requests.add('setPitch');
    return SetPitchResponse();
  }

  @override
  Future<SetSkipSilenceResponse> setSkipSilence(
    SetSkipSilenceRequest request,
  ) async {
    requests.add('setSkipSilence');
    return SetSkipSilenceResponse();
  }

  @override
  Future<SetShuffleModeResponse> setShuffleMode(
    SetShuffleModeRequest request,
  ) async {
    requests.add('setShuffleMode');
    return SetShuffleModeResponse();
  }

  @override
  Future<SetShuffleOrderResponse> setShuffleOrder(
    SetShuffleOrderRequest request,
  ) async {
    requests.add('setShuffleOrder');
    return SetShuffleOrderResponse();
  }

  @override
  Future<SetAndroidAudioAttributesResponse> setAndroidAudioAttributes(
    SetAndroidAudioAttributesRequest request,
  ) async {
    requests.add('setAndroidAudioAttributes');
    return SetAndroidAudioAttributesResponse();
  }

  @override
  Future<DisposeResponse> dispose(DisposeRequest request) async {
    requests.add('dispose');
    close();
    return DisposeResponse();
  }
}

class FakeJustAudioPlatform extends JustAudioPlatform {
  final Map<String, FakeAudioPlayerPlatform> players = {};

  FakeAudioPlayerPlatform get only => players.values.single;

  @override
  Future<AudioPlayerPlatform> init(InitRequest request) async {
    final player = FakeAudioPlayerPlatform(request.id);
    players[request.id] = player;
    return player;
  }

  @override
  Future<DisposePlayerResponse> disposePlayer(
    DisposePlayerRequest request,
  ) async {
    players.remove(request.id)?.close();
    return DisposePlayerResponse();
  }

  @override
  Future<DisposeAllPlayersResponse> disposeAllPlayers(
    DisposeAllPlayersRequest request,
  ) async {
    for (final player in players.values) {
      player.close();
    }
    players.clear();
    return DisposeAllPlayersResponse();
  }
}
