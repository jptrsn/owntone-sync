import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart';
import 'package:rxdart/rxdart.dart';

import 'shuffle_order.dart';

class OwnToneAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer _audioPlayer = AudioPlayer();

  /// The one ShuffleOrder instance that owns the play order. It is passed to
  /// every `setAudioSources` call; the player clears and re-seeds it per
  /// collection (`ConcatenatingAudioSource._init`), and the load path
  /// re-shuffles it with the starting track anchored at the head (just_audio
  /// `AudioPlayer._load`), so `playCollection` needs no explicit re-shuffle.
  /// Without it, `updateQueue` would silently swap in a fresh
  /// `DefaultShuffleOrder` whose random inserts break exact-position queue
  /// mutations.
  final ExactPositionShuffleOrder _shuffleOrder = ExactPositionShuffleOrder();

  /// Base indices in play order, re-emitted on every sequence state change.
  /// `currentIndex` indexes `sequence` (base order); this list maps play
  /// order to base indices (see the index-space invariant).
  final BehaviorSubject<List<int>> _shuffleIndicesSubject =
      BehaviorSubject<List<int>>.seeded(const []);

  Stream<List<int>> get shuffleIndicesStream => _shuffleIndicesSubject.stream;

  StreamSubscription<PlaybackEvent>? _playbackEventSubscription;
  StreamSubscription<SequenceState>? _sequenceSubscription;
  StreamSubscription<PlayerException>? _errorSubscription;

  OwnToneAudioHandler() {
    _setupSubscriptions();
  }

  final StreamController<MediaItem> _skippedTrackController =
      StreamController<MediaItem>.broadcast();

  /// Emits the [MediaItem] of a track that failed to play and was
  /// auto-advanced past (A9). The item is resolved from the
  /// [PlayerException.index] against the sequence, so it is unambiguous
  /// even though the player moves on immediately.
  Stream<MediaItem> get skippedTrackStream => _skippedTrackController.stream;

  /// Set when the user explicitly asks to move to a different track (UI
  /// button, media notification, or Bluetooth control), so the stats
  /// recorder can tell that move apart from natural completion, repeat
  /// looping, and the A9 error auto-advance. Consumed exactly once, by the
  /// recorder, on the next track change.
  bool _userInitiatedPending = false;

  /// Consumes the pending user-initiated transition marker, if any.
  ///
  /// The handler is the single funnel for every user-initiated track change
  /// (the controller, the media notification, and Bluetooth all call these
  /// same overrides), so this is the only place the signal can be marked.
  bool consumeUserInitiatedTransition() {
    final pending = _userInitiatedPending;
    _userInitiatedPending = false;
    return pending;
  }

  Object? get _currentMediaItemTag {
    final index = _audioPlayer.currentIndex;
    final sequence = _audioPlayer.sequence;
    if (index == null || index < 0 || index >= sequence.length) return null;
    return sequence[index].tag;
  }

  /// The player's decoded duration for the current source (null when nothing
  /// is loaded). Re-exposed so the controller can fall back to it when the
  /// track's metadata duration is missing.
  Stream<Duration?> get durationStream => _audioPlayer.durationStream;

  void _setupSubscriptions() {
    _playbackEventSubscription = _audioPlayer.playbackEventStream.listen((
      event,
    ) {
      final playing = _audioPlayer.playing;
      playbackState.add(
        playbackState.value.copyWith(
          controls: [
            MediaControl.skipToPrevious,
            if (playing) MediaControl.pause else MediaControl.play,
            MediaControl.skipToNext,
          ],
          systemActions: const {
            MediaAction.seek,
            MediaAction.seekForward,
            MediaAction.seekBackward,
          },
          androidCompactActionIndices: const [0, 1, 2],
          processingState: _mapProcessingState(event.processingState),
          playing: playing,
          // The platform only sends sparse position samples; just_audio
          // extrapolates the live position. audio_service sends
          // (updatePosition, updateTime, speed) to the media session, and
          // the system notification projects the playhead forward between
          // updates. Feeding the raw sparse sample here would reset the
          // projection baseline and make the playhead snap backwards.
          updatePosition: _audioPlayer.position,
          bufferedPosition: event.bufferedPosition,
          speed: _audioPlayer.speed,
          queueIndex: event.currentIndex,
        ),
      );
    });

    _sequenceSubscription = _audioPlayer.sequenceStateStream.listen((state) {
      final sequence = state.sequence;
      _shuffleIndicesSubject.add(state.shuffleIndices);
      if (sequence.isEmpty) {
        queue.add([]);
        mediaItem.add(null);
        return;
      }
      // Play order, not base order: with shuffle on, `sequence` is the
      // collection order and `shuffleIndices` is the map to play order.
      // Emitting `effectiveSequence` keeps the UI queue in step with what
      // actually plays. The current item still resolves through
      // `sequence[currentIndex]` — `currentIndex` is a BASE index.
      queue.add(state.effectiveSequence.map((s) => s.tag as MediaItem).toList());
      final i = state.currentIndex;
      mediaItem.add(
        (i != null && i >= 0 && i < sequence.length)
            ? sequence[i].tag as MediaItem
            : null,
      );
    });

    // FIX 5: Auto-advance past unplayable tracks (story A9).
    _errorSubscription = _audioPlayer.errorStream.listen((error) {
      if (kDebugMode) {
        print(
          '[OwnToneAudioHandler] PlayerException: '
          '${error.message} (code=${error.code}, index=${error.index})',
        );
      }
      playbackState.add(
        playbackState.value.copyWith(
          processingState: AudioProcessingState.error,
        ),
      );
      // Error auto-advance is not a user skip: clear any stale marker so the
      // advance cannot be misattributed to the user.
      _userInitiatedPending = false;
      final failedIndex = error.index;
      final sequence = _audioPlayer.sequence;
      if (failedIndex != null &&
          failedIndex >= 0 &&
          failedIndex < sequence.length) {
        final tag = sequence[failedIndex].tag;
        if (tag is MediaItem) {
          _skippedTrackController.add(tag);
        }
      }
      _audioPlayer.seekToNext();
    });
  }

  AudioProcessingState _mapProcessingState(ProcessingState state) {
    switch (state) {
      case ProcessingState.idle:
        return AudioProcessingState.idle;
      case ProcessingState.loading:
        return AudioProcessingState.loading;
      case ProcessingState.buffering:
        return AudioProcessingState.buffering;
      case ProcessingState.ready:
        return AudioProcessingState.ready;
      case ProcessingState.completed:
        return AudioProcessingState.completed;
    }
  }

  /// Load a collection of tracks and start playing from [startIndex].
  Future<void> playCollection(
    List<MediaItem> tracks, {
    int startIndex = 0,
  }) async {
    if (tracks.isEmpty) {
      if (kDebugMode) {
        print('[OwnToneAudioHandler] playCollection: empty tracks list');
      }
      return;
    }

    final audioSources = <IndexedAudioSource>[];
    for (final track in tracks) {
      final uriString = track.extras?['uri'] as String? ?? '';
      if (uriString.isEmpty) {
        if (kDebugMode) {
          print(
            '[OwnToneAudioHandler] Skipping track: '
            '${track.title} - empty URI',
          );
        }
        continue;
      }

      final source = AudioSource.uri(Uri.parse(uriString), tag: track);
      audioSources.add(source);
    }

    if (audioSources.isEmpty) {
      if (kDebugMode) {
        print('[OwnToneAudioHandler] playCollection: no valid sources');
      }
      return;
    }

    final actualStartIndex = startIndex.clamp(0, audioSources.length - 1);

    final startTag = audioSources[actualStartIndex].tag;
    final currentTag = _currentMediaItemTag;
    if (startTag is MediaItem &&
        currentTag is MediaItem &&
        currentTag.id != startTag.id) {
      // Starting a new collection moves off the current track.
      _userInitiatedPending = true;
    }

    await _audioPlayer.setAudioSources(
      audioSources,
      initialIndex: actualStartIndex,
      shuffleOrder: _shuffleOrder,
    );
    // play() returns a future that completes when playback stops,
    // so do not await it here.
    _audioPlayer.play();
  }

  @override
  Future<void> play() => _audioPlayer.play();

  @override
  Future<void> pause() => _audioPlayer.pause();

  @override
  Future<void> stop() async {
    _userInitiatedPending = false;
    await _audioPlayer.stop();
  }

  @override
  Future<void> seek(Duration position) => _audioPlayer.seek(position);

  @override
  Future<void> skipToNext() async {
    _userInitiatedPending = true;
    await _audioPlayer.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    final position = _audioPlayer.position;
    final index = _audioPlayer.currentIndex;
    if (index == null) return;

    // B5: Past ~3s, restart current track; before ~3s, go to previous.
    // `previousIndex` (not `index - 1`) is the previous track in PLAY order:
    // it resolves the play-order neighbour and returns a base index, and is
    // null when there is no previous (first in play order, repeat off).
    final previous = _audioPlayer.previousIndex;
    if (position > const Duration(seconds: 3)) {
      // Restarting the current track is not moving off it.
      await _audioPlayer.seek(Duration.zero, index: index);
    } else if (previous != null && previous != index) {
      // repeat-one reports the current track as its own previous; that is a
      // restart, not a move, so it must not set the intent flag.
      _userInitiatedPending = true;
      await _audioPlayer.seek(Duration.zero, index: previous);
    } else {
      // First track in play order (or repeat-one): restart, do not no-op.
      await _audioPlayer.seek(Duration.zero, index: index);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    if (index != _audioPlayer.currentIndex) {
      _userInitiatedPending = true;
    }
    await _audioPlayer.seek(Duration.zero, index: index);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode == AudioServiceShuffleMode.all;
    await _audioPlayer.setShuffleModeEnabled(enabled);
    if (enabled && _audioPlayer.audioSources.isNotEmpty) {
      // Re-shuffle with the current track anchored at the head of the play
      // order. Without this, the stored permutation's prefix (everything
      // before the current track's position in it) plays first, which
      // violates A3 ("toggling on mid-track reshuffles only the remaining
      // tracks"). A3's "off restores the original order" is free: the base
      // sequence is never mutated, so disabling just ignores this list.
      await _audioPlayer.shuffle();
      // just_audio 0.10.6 (Android) never delivers the order produced by the
      // shuffle() above to the platform: its "setShuffleOrder" method-channel
      // handler resolves the source by id from a cache that the top-level
      // playlist (empty id) is never stored in, and silently returns. Left
      // alone, the platform keeps playing the load-time order while the
      // Dart/UI state shows the new one, until the next queue mutation.
      // Push the order the way every working mutation does — a concatenating
      // call carrying the full indices. A same-index base move is a no-op on
      // the base list, and routed back to the moved track's own play position
      // it is a no-op on the play order (the GATE-verified mechanism that
      // moveQueueItem relies on).
      final current = _audioPlayer.currentIndex ?? 0;
      final pos = _audioPlayer.shuffleIndices.indexOf(current);
      _shuffleOrder.routeInsertAtPlayPosition(pos >= 0 ? pos : 0);
      await _audioPlayer.moveAudioSource(current, current);
    }
    playbackState.add(playbackState.value.copyWith(shuffleMode: shuffleMode));
  }

  @override
  Future<void> setRepeatMode(AudioServiceRepeatMode repeatMode) async {
    final loopMode = _repeatModeToLoopMode(repeatMode);
    await _audioPlayer.setLoopMode(loopMode);
    playbackState.add(playbackState.value.copyWith(repeatMode: repeatMode));
  }

  @override
  Future<void> addQueueItem(MediaItem mediaItem) async {
    final uriString = mediaItem.extras?['uri'] as String? ?? '';
    if (uriString.isEmpty) {
      if (kDebugMode) {
        print(
          '[OwnToneAudioHandler] addQueueItem: '
          'skipping ${mediaItem.title} - empty URI',
        );
      }
      return;
    }
    final source = AudioSource.uri(Uri.parse(uriString), tag: mediaItem);
    // Add-to-queue appends to the tail of the play order.
    _shuffleOrder.routeInsertAppend();
    await _audioPlayer.addAudioSource(source);
  }

  @override
  Future<void> insertQueueItem(int index, MediaItem mediaItem) async {
    final uriString = mediaItem.extras?['uri'] as String? ?? '';
    if (uriString.isEmpty) {
      if (kDebugMode) {
        print(
          '[OwnToneAudioHandler] insertQueueItem: '
          'skipping ${mediaItem.title} - empty URI',
        );
      }
      return;
    }
    final source = AudioSource.uri(Uri.parse(uriString), tag: mediaItem);
    // Play-next lands immediately after the currently playing track in the
    // play order. With shuffle off, play order IS base order, so the base
    // insertion index is the play position; with shuffle on, the base index
    // is only the slot the item occupies in the collection order and the
    // play position comes from the shuffle order.
    _shuffleOrder.routeInsertAtPlayPosition(_playPositionForInsert(index));
    await _audioPlayer.insertAudioSource(index, source);
  }

  /// The play position a new item inserted at base [index] should occupy.
  int _playPositionForInsert(int index) {
    if (!_audioPlayer.shuffleModeEnabled) return index;
    final order = _audioPlayer.shuffleIndices;
    final current = _audioPlayer.currentIndex;
    if (current == null) return order.length;
    final pos = order.indexOf(current);
    return pos >= 0 ? pos + 1 : order.length;
  }

  @override
  Future<void> removeQueueItem(MediaItem mediaItem) async {
    final index = _audioPlayer.sequence.indexWhere((src) {
      final tag = src.tag;
      return tag is MediaItem && tag.id == mediaItem.id;
    });
    if (index >= 0) {
      await _audioPlayer.removeAudioSourceAt(index);
    }
  }

  @override
  Future<void> updateQueue(List<MediaItem> queue) async {
    final audioSources = queue
        .where((item) {
          final uri = item.extras?['uri'] as String? ?? '';
          return uri.isNotEmpty;
        })
        .map(
          (item) => AudioSource.uri(
            Uri.parse(item.extras?['uri'] as String? ?? ''),
            tag: item,
          ),
        )
        .toList();

    await _audioPlayer.setAudioSources(audioSources, shuffleOrder: _shuffleOrder);
  }

  /// Reorders the queue item at play-order row [fromRow] to row [toRow].
  /// [toRow] is in post-removal coordinates, as ReorderableListView reports
  /// it.
  ///
  /// With shuffle off, play order IS base order, so this is a real base move.
  /// With shuffle on, the base order must stay untouched (A3: turning shuffle
  /// off restores the collection order), so the item is re-placed in the
  /// shuffle order via a same-index base move — the platform applies the
  /// shuffle-order update that rides on every concatenating move
  /// (verified on device, see invariants).
  Future<void> moveQueueItem(int fromRow, int toRow) async {
    final length = _audioPlayer.sequence.length;
    if (fromRow < 0 || fromRow >= length) return;
    if (toRow == fromRow) return;
    final target = toRow.clamp(0, length - 1);
    if (_audioPlayer.shuffleModeEnabled) {
      final base = _audioPlayer.shuffleIndices[fromRow];
      _shuffleOrder.routeInsertAtPlayPosition(target);
      await _audioPlayer.moveAudioSource(base, base);
    } else {
      await _audioPlayer.moveAudioSource(fromRow, target);
    }
  }

  /// Stops playback and empties the queue (A7 "clear queue"). Clearing the
  /// queue is not a user move off the current track, so any pending
  /// user-initiated marker is dropped with the stop.
  Future<void> clearQueue() async {
    await stop();
    await _audioPlayer.clearAudioSources();
  }

  LoopMode _repeatModeToLoopMode(AudioServiceRepeatMode repeatMode) {
    switch (repeatMode) {
      case AudioServiceRepeatMode.none:
        return LoopMode.off;
      case AudioServiceRepeatMode.all:
        return LoopMode.all;
      case AudioServiceRepeatMode.one:
        return LoopMode.one;
      case AudioServiceRepeatMode.group:
        return LoopMode.off;
    }
  }

  @override
  Future<void> onTaskRemoved() async {
    await _audioPlayer.stop();
  }

  Future<void> dispose() async {
    await _playbackEventSubscription?.cancel();
    await _sequenceSubscription?.cancel();
    await _errorSubscription?.cancel();
    await _skippedTrackController.close();
    await _audioPlayer.dispose();
  }
}
