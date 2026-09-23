import 'dart:async';

import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/foundation.dart';

class OwnToneAudioHandler extends BaseAudioHandler
    with QueueHandler, SeekHandler {
  final AudioPlayer _audioPlayer = AudioPlayer();

  StreamSubscription<PlaybackEvent>? _playbackEventSubscription;
  StreamSubscription<SequenceState>? _sequenceSubscription;
  StreamSubscription<PlayerException>? _errorSubscription;

  OwnToneAudioHandler() {
    _setupSubscriptions();
  }

  /// The player's decoded duration for the current source (null when nothing
  /// is loaded). Re-exposed so the controller can fall back to it when the
  /// track's metadata duration is missing.
  Stream<Duration?> get durationStream => _audioPlayer.durationStream;

  void _setupSubscriptions() {
    _playbackEventSubscription = _audioPlayer.playbackEventStream.listen(
      (event) {
        final playing = _audioPlayer.playing;
        playbackState.add(playbackState.value.copyWith(
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
        ));
      },
    );

    _sequenceSubscription = _audioPlayer.sequenceStateStream.listen((state) {
      final sequence = state.sequence;
      if (sequence.isEmpty) {
        queue.add([]);
        mediaItem.add(null);
        return;
      }
      queue.add(sequence.map((s) => s.tag as MediaItem).toList());
      final i = state.currentIndex;
      mediaItem.add((i != null && i >= 0 && i < sequence.length)
          ? sequence[i].tag as MediaItem
          : null);
    });

    // FIX 5: Auto-advance past unplayable tracks (story A9).
    _errorSubscription = _audioPlayer.errorStream.listen((error) {
      if (kDebugMode) {
        print(
          '[OwnToneAudioHandler] PlayerException: '
          '${error.message} (code=${error.code}, index=${error.index})',
        );
      }
      playbackState.add(playbackState.value.copyWith(
        processingState: AudioProcessingState.error,
      ));
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

    final audioSources = <AudioSource>[];
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

      final source = AudioSource.uri(
        Uri.parse(uriString),
        tag: track,
      );
      audioSources.add(source);
    }

    if (audioSources.isEmpty) {
      if (kDebugMode) {
        print('[OwnToneAudioHandler] playCollection: no valid sources');
      }
      return;
    }

    final actualStartIndex = startIndex.clamp(0, audioSources.length - 1);
    await _audioPlayer.setAudioSources(
      audioSources,
      initialIndex: actualStartIndex,
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
  Future<void> stop() => _audioPlayer.stop();

  @override
  Future<void> seek(Duration position) => _audioPlayer.seek(position);

  @override
  Future<void> skipToNext() async {
    await _audioPlayer.seekToNext();
  }

  @override
  Future<void> skipToPrevious() async {
    final position = _audioPlayer.position;
    final index = _audioPlayer.currentIndex;

    // B5: Past ~3s, restart current track; before ~3s, go to previous.
    if (position > const Duration(seconds: 3) && index != null) {
      await _audioPlayer.seek(Duration.zero, index: index);
    } else if (index != null && index > 0) {
      await _audioPlayer.seek(Duration.zero, index: index - 1);
    } else if (index != null) {
      await _audioPlayer.seek(Duration.zero);
    }
  }

  @override
  Future<void> skipToQueueItem(int index) async {
    await _audioPlayer.seek(Duration.zero, index: index);
  }

  @override
  Future<void> setShuffleMode(AudioServiceShuffleMode shuffleMode) async {
    final enabled = shuffleMode == AudioServiceShuffleMode.all;
    await _audioPlayer.setShuffleModeEnabled(enabled);
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
    final source = AudioSource.uri(
      Uri.parse(uriString),
      tag: mediaItem,
    );
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
    final source = AudioSource.uri(
      Uri.parse(uriString),
      tag: mediaItem,
    );
    await _audioPlayer.insertAudioSource(index, source);
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

    await _audioPlayer.setAudioSources(audioSources);
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
    await _audioPlayer.dispose();
  }
}
