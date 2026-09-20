import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';
import 'package:flutter/services.dart';

class OwnToneAudioHandler extends BaseAudioHandler with QueueHandler {
  static const _eventChannel = MethodChannel('dev.educoder.owntone_sync/events');
  
  final AudioPlayer _audioPlayer;
  
  int? _currentTrackId;
  Duration? _currentTrackDuration;

  OwnToneAudioHandler() : _audioPlayer = AudioPlayer();

  AudioPlayer get audioPlayer => _audioPlayer;

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
  Future<void> skipToPrevious() async {
    await super.skipToPrevious();
    await _trackSkipEvent();
  }

  @override
  Future<void> skipToNext() async {
    await super.skipToNext();
    await _trackSkipEvent();
  }

  Future<void> _trackSkipEvent() async {
    try {
      if (_currentTrackId != null) {
        await _eventChannel.invokeMethod('recordSkipEvent', {'trackId': _currentTrackId});
      }
    } catch (e) {
      // Event tracking may be disabled or channel not available
    }
  }

  Future<void> _trackPlayEvent() async {
    try {
      if (_currentTrackId != null && _currentTrackDuration != null) {
        await _eventChannel.invokeMethod('recordPlayEvent', {
          'trackId': _currentTrackId,
          'durationMs': _currentTrackDuration!.inMilliseconds
        });
      }
    } catch (e) {
      // Event tracking may be disabled or channel not available
    }
  }
}
