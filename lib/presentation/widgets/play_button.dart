import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';
import '../../data/repositories/local_database_repository.dart';

class PlayButton extends StatelessWidget {
  final SyncedTrack track;
  final bool showNextIcon;

  const PlayButton({
    super.key,
    required this.track,
    this.showNextIcon = false,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, playerProvider, child) {
        final currentTrack = playerProvider.getCurrentlyPlayingTrack();
        final isPlaying = currentTrack != null && currentTrack.id == track.id;

        return IconButton(
          onPressed: () {
            playerProvider.playTrack(track.id);
          },
          icon: _buildIcon(isPlaying),
          tooltip: isPlaying
              ? 'Pause track'
              : 'Play track',
        );
      },
    );
  }

  Widget _buildIcon(bool isPlaying) {
    if (showNextIcon) {
      return const Icon(Icons.skip_next);
    }
    return isPlaying ? const Icon(Icons.pause) : const Icon(Icons.play_arrow);
  }
}

class PlayableTile extends StatelessWidget {
  final Widget child;
  final SyncedTrack track;
  final bool showNextIcon;

  const PlayableTile({
    super.key,
    required this.child,
    required this.track,
    this.showNextIcon = false,
  });

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        child,
        Positioned(
          right: 0,
          top: 0,
          bottom: 0,
          child: PlayButton(track: track, showNextIcon: showNextIcon),
        ),
      ],
    );
  }
}
