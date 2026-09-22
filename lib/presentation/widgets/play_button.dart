import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/player_provider.dart';
import '../../data/repositories/local_database_repository.dart';

class PlayButton extends StatelessWidget {
  final SyncedTrack track;
  final bool showNextIcon;
  final bool showContextMenu;

  const PlayButton({
    super.key,
    required this.track,
    this.showNextIcon = false,
    this.showContextMenu = false,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, playerProvider, child) {
        final currentTrack = playerProvider.getCurrentlyPlayingTrack();
        final isPlaying = currentTrack != null && currentTrack.id == track.id;

        return GestureDetector(
          onLongPress: showContextMenu
              ? () => _showPlayMenu(context, playerProvider, track)
              : null,
          child: IconButton(
            onPressed: () {
              playerProvider.playTrack(track.id);
            },
            icon: _buildIcon(isPlaying),
            tooltip: isPlaying
                ? 'Pause track'
                : 'Play track',
          ),
        );
      },
    );
  }

  void _showPlayMenu(
    BuildContext context,
    PlayerProvider provider,
    SyncedTrack track,
  ) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.play_arrow),
            title: const Text('Play'),
            onTap: () {
              provider.playTrack(track.id);
              Navigator.of(ctx).pop();
            },
          ),
          ListTile(
            leading: const Icon(Icons.skip_next),
            title: const Text('Play Next'),
            onTap: () {
              provider.playNext(track);
              Navigator.of(ctx).pop();
            },
          ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Add to Queue'),
            onTap: () {
              provider.addToQueue(track);
              Navigator.of(ctx).pop();
            },
          ),
        ],
      ),
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
  final bool showContextMenu;

  const PlayableTile({
    super.key,
    required this.child,
    required this.track,
    this.showNextIcon = false,
    this.showContextMenu = false,
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
          child: PlayButton(
            track: track,
            showNextIcon: showNextIcon,
            showContextMenu: showContextMenu,
          ),
        ),
      ],
    );
  }
}
