import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:flutter/foundation.dart';

import '../../data/repositories/local_database_repository.dart';

/// Records play and skip events for the current queue.
///
/// A **play** is recorded when the actual accumulated listening of one pass of
/// a track reaches the lesser of 90% of its duration or 4 minutes. At most one
/// play per pass; a repeat-one loop restart starts a new pass. Seeking forward
/// never counts as listening, and seeking backwards below the threshold resets
/// the accumulated time without allowing a second play for the same pass.
///
/// A **skip** is recorded only when an explicit user action (next, previous,
/// queue-item selection, or starting a new collection) moves off a track that
/// is below the play threshold and has been listened to for more than ~2s.
/// Auto-advance, repeat looping, error auto-skip, pause, stop, and app death
/// record nothing.
///
/// Events are written directly to `pending_events`; the sync worker uploads
/// them. This recorder never talks to the Kotlin side.
class PlaybackStatsRecorder {
  PlaybackStatsRecorder({
    required Stream<MediaItem?> mediaItem,
    required Stream<PlaybackState> playbackState,
    required Stream<Duration?> durationStream,
    required Stream<Duration> position,
    required bool Function() consumeUserInitiatedTransition,
    required Future<int> Function(PendingEvent event) insertEvent,
  })  : _mediaItem = mediaItem,
        _playbackState = playbackState,
        _durationStream = durationStream,
        _position = position,
        _consumeUserInitiatedTransition = consumeUserInitiatedTransition,
        _insertEvent = insertEvent;

  static const double _playFraction = 0.9;
  static const Duration _maxPlayThreshold = Duration(minutes: 4);
  static const Duration _skipFloor = Duration(seconds: 2);

  /// A position delta larger than this is a seek (or a timer gap), not
  /// listening. [AudioService.position] ticks every 16-200ms, so real
  /// listening deltas are far below this.
  static const int _maxTickJumpMs = 1000;

  final Stream<MediaItem?> _mediaItem;
  final Stream<PlaybackState> _playbackState;
  final Stream<Duration?> _durationStream;
  final Stream<Duration> _position;
  final bool Function() _consumeUserInitiatedTransition;
  final Future<int> Function(PendingEvent event) _insertEvent;

  StreamSubscription<MediaItem?>? _mediaItemSubscription;
  StreamSubscription<PlaybackState>? _playbackStateSubscription;
  StreamSubscription<Duration?>? _durationSubscription;
  StreamSubscription<Duration>? _positionSubscription;

  int? _currentTrackId;
  int _listenedMs = 0;
  bool _playRecorded = false;
  int? _lastPositionMs;
  Duration? _itemDuration;
  Duration? _decodedDuration;
  bool _playing = false;
  AudioServiceRepeatMode _repeatMode = AudioServiceRepeatMode.none;

  /// Set when a large backward position jump is seen. Applied on the next
  /// forward tick of the *same* track, so that a track change in between is
  /// handled first (the old track's skip must be evaluated before its
  /// accumulator is clobbered by the new track's first position tick).
  bool _pendingBackwardReset = false;
  int _pendingBackwardPositionMs = 0;

  Duration? get _duration {
    final decoded = _decodedDuration;
    if (decoded != null && decoded > Duration.zero) return decoded;
    final item = _itemDuration;
    if (item != null && item > Duration.zero) return item;
    return null;
  }

  /// The play threshold in milliseconds: the lesser of 90% of the duration
  /// or 4 minutes. Null while the duration is unknown.
  int? get _thresholdMs {
    final duration = _duration;
    if (duration == null) return null;
    final atFraction = (duration.inMilliseconds * _playFraction).toInt();
    return atFraction < _maxPlayThreshold.inMilliseconds
        ? atFraction
        : _maxPlayThreshold.inMilliseconds;
  }

  /// Subscribes to the playback streams. Call once.
  void start() {
    _mediaItemSubscription = _mediaItem.listen(_onMediaItem);
    _playbackStateSubscription = _playbackState.listen(_onPlaybackState);
    _durationSubscription = _durationStream.listen(_onDuration);
    _positionSubscription = _position.listen(_onPosition);
  }

  void dispose() {
    _mediaItemSubscription?.cancel();
    _playbackStateSubscription?.cancel();
    _durationSubscription?.cancel();
    _positionSubscription?.cancel();
  }

  void _onMediaItem(MediaItem? item) {
    final newId = item == null ? null : int.tryParse(item.id);
    if (newId == _currentTrackId) return;

    final userInitiated = _consumeUserInitiatedTransition();
    if (_currentTrackId != null && userInitiated) {
      _maybeRecordSkip();
    }

    _currentTrackId = newId;
    _listenedMs = 0;
    _playRecorded = false;
    _lastPositionMs = 0;
    _itemDuration = item?.duration;
    _pendingBackwardReset = false;
  }

  void _onPlaybackState(PlaybackState state) {
    _playing = state.playing;
    _repeatMode = state.repeatMode;
  }

  void _onDuration(Duration? duration) {
    _decodedDuration =
        (duration != null && duration > Duration.zero) ? duration : null;
    // The duration may arrive after enough time has already been listened;
    // the threshold crossing must still be recognised.
    _maybeRecordPlay();
  }

  void _onPosition(Duration position) {
    final positionMs = position.inMilliseconds;
    final last = _lastPositionMs;
    _lastPositionMs = positionMs;
    if (_currentTrackId == null || last == null || !_playing) return;

    final delta = positionMs - last;
    if (delta > _maxTickJumpMs) {
      // Forward seek or discontinuity: the jump itself is not listening.
      return;
    }
    if (delta < -_maxTickJumpMs) {
      // Backward jump: a repeat-one loop restart or a user seeking backwards.
      _pendingBackwardReset = true;
      _pendingBackwardPositionMs = positionMs;
      return;
    }
    if (delta <= 0) return;

    if (_pendingBackwardReset) {
      _pendingBackwardReset = false;
      final threshold = _thresholdMs;
      if (threshold == null || _pendingBackwardPositionMs < threshold) {
        _listenedMs = 0;
      }
      if (_repeatMode == AudioServiceRepeatMode.one) {
        // A repeat-one loop restart is a new pass.
        _playRecorded = false;
      }
    }

    _listenedMs += delta;
    _maybeRecordPlay();
  }

  void _maybeRecordPlay() {
    if (_currentTrackId == null || _playRecorded) return;
    final threshold = _thresholdMs;
    if (threshold == null || _listenedMs < threshold) return;
    _playRecorded = true;
    _record('play');
  }

  void _maybeRecordSkip() {
    if (_playRecorded) return;
    if (_listenedMs < _skipFloor.inMilliseconds) return;
    final threshold = _thresholdMs;
    if (threshold != null && _listenedMs >= threshold) return;
    _record('skip');
  }

  Future<void> _record(String eventType) async {
    final trackId = _currentTrackId;
    if (trackId == null) return;
    try {
      await _insertEvent(PendingEvent(
        trackId: trackId,
        eventType: eventType,
        timestamp: DateTime.now().millisecondsSinceEpoch ~/ 1000,
      ));
    } catch (e) {
      if (kDebugMode) {
        print(
          '[PlaybackStatsRecorder] failed to record $eventType '
          'for track $trackId: $e',
        );
      }
    }
  }
}
