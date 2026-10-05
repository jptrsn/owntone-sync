import 'dart:math';

import 'package:audio_service/audio_service.dart';

import '../../data/repositories/local_database_repository.dart';
import '../controllers/playback_controller.dart';

/// Plays [tracks] in list order from the first track (B3 "Play").
Future<void> playCollectionInOrder(
  PlaybackController controller,
  QueueOrigin origin,
  List<SyncedTrack> tracks,
) {
  if (tracks.isEmpty) return Future.value();
  return controller.playCollection(origin, tracks, startIndex: 0);
}

/// Replaces the queue with [tracks] at a random start track and makes sure
/// shuffle ends up ON (B3 "Shuffle").
///
/// Shuffle is forced on rather than toggled: the button means "play this
/// collection shuffled", so it must not turn shuffle off when it is already
/// on. When the flag is already on, `playCollection` re-shuffles with the
/// starting track anchored at the head of the play order, so the chosen
/// random start track is the one that plays first either way.
Future<void> shuffleCollection(
  PlaybackController controller,
  QueueOrigin origin,
  List<SyncedTrack> tracks,
) async {
  if (tracks.isEmpty) return;
  final start = Random().nextInt(tracks.length);
  await controller.playCollection(origin, tracks, startIndex: start);
  if (controller.currentPlaybackState.shuffleMode !=
      AudioServiceShuffleMode.all) {
    await controller.toggleShuffle();
  }
}
