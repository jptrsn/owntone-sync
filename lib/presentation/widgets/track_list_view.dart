import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../controllers/playback_controller.dart';
import '../providers/browse_provider.dart';
import 'library_rows.dart';

/// The Tracks tab: every synced track, tap plays in context (A1).
class TrackListView extends StatelessWidget {
  const TrackListView({super.key});

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
            return TrackRow(
              track: track,
              collection: provider.tracks,
              index: index,
              origin: const QueueOrigin.allTracks(),
              onRatingChanged: provider.refresh,
            );
          },
        );
      },
    );
  }
}
