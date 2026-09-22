import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/services.dart';

class OwnToneAudioHandler extends BaseAudioHandler with QueueHandler, SeekHandler {
  static const _eventChannel = MethodChannel('dev.educoder.owntone_sync/events');
  
  final AudioPlayer _audioPlayer;
  
  OwnToneAudioHandler() : _audioPlayer = AudioPlayer() {
    _audioPlayer.processingStateStream.listen((state) {
      if (state == ProcessingState.completed) {
        skipToNext();
      }
    });
    
    _audioPlayer.playbackEventStream.listen((event) {
      final position = _audioPlayer.position;
      playbackState.add(playbackState.value.copyWith(
        processingState: _mapProcessingState(_audioPlayer.processingState),
        playing: _audioPlayer.playing,
        updatePosition: position,
      ));
    });
  }

  AudioPlayer get audioPlayer => _audioPlayer;

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

  @override
  Future<void> play() async {
    await _audioPlayer.play();
  }

  @override
  Future<void> pause() async {
    await _audioPlayer.pause();
  }

  @override
  Future<void> stop() async {
    await _audioPlayer.stop();
  }

  @override
  Future<void> seek(Duration position) async {
    await _audioPlayer.seek(position);
  }

  @override
  Future<void> playMediaItem(MediaItem mediaItem) async {
    try {
      final uri = mediaItem.extras?['uri'] as String?;
      if (uri != null && uri.isNotEmpty) {
        queue.add([mediaItem]);
        this.mediaItem.add(mediaItem);
        await _audioPlayer.setUrl(uri);
        await _audioPlayer.play();
      }
    } catch (e) {
      // Playback error
    }
  }

  @override
  Future<void> skipToNext() async {
    try {
      super.skipToNext();
      await _trackSkipEvent();
    } catch (e) {
      // Queue exhausted or error
    }
  }

  @override
  Future<void> skipToPrevious() async {
    try {
      super.skipToPrevious();
      await _trackSkipEvent();
    } catch (e) {
      // Beginning of queue or error
    }
  }

  Future<void> _trackSkipEvent() async {
    try {
      final currentMedia = mediaItem.value;
      if (currentMedia != null) {
        await _eventChannel.invokeMethod('recordSkipEvent', {
          'trackId': int.tryParse(currentMedia.id),
        });
      }
    } catch (e) {
      // Event tracking may be disabled or channel not available
    }
  }

  @override
  Future<void> onTaskRemoved() async {
    await _audioPlayer.stop();
  }
}
