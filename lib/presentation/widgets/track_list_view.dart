import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/browse_provider.dart';
import '../controllers/playback_controller.dart';
import 'play_button.dart';

class TrackListView extends StatelessWidget {
  const TrackListView({super.key});

  String _formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<BrowseProvider>(
      builder: (context, provider, child) {
        if (provider.tracks.isEmpty) {
          return const Center(child: Text('No tracks found'));
        }

        return ListView.builder(
          itemCount: provider.tracks.length,
          itemBuilder: (context, index) {
            final track = provider.tracks[index];

            return PlayableTile(
              track: track,
              collection: provider.tracks,
              index: index,
              origin: const QueueOrigin.allTracks(),
              showContextMenu: true,
              child: ListTile(
                title: Text(track.title),
                subtitle: Text('${track.artist} • ${track.album}'),
                trailing: Text(
                  _formatDuration(track.lengthMs),
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
            );
          },
        );
      },
    );
  }
}
