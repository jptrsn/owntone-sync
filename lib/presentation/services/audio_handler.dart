import 'package:audio_service/audio_service.dart';
import 'package:just_audio/just_audio.dart';

class OwnToneAudioHandler extends BaseAudioHandler with QueueHandler {
  final AudioPlayer _audioPlayer;

  OwnToneAudioHandler() : _audioPlayer = AudioPlayer();

  AudioPlayer get audioPlayer => _audioPlayer;

  @override
  Future<void> play() => _audioPlayer.play();

  @override
  Future<void> pause() => _audioPlayer.pause();

  @override
  Future<void> stop() => _audioPlayer.stop();

  @override
  Future<void> seek(Duration position) => _audioPlayer.seek(position);
}
