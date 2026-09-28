import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/browse_provider.dart';
import 'library_rows.dart';

/// The Playlists tab: tap opens the playlist detail screen (it does not
/// start playback); Play / Shuffle / Add to queue live in the row menu.
class PlaylistListView extends StatelessWidget {
  const PlaylistListView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BrowseProvider>(
      builder: (context, provider, child) {
        if (provider.playlists.isEmpty) {
          return const Center(child: Text('No playlists synced'));
        }

        return ListView.builder(
          itemCount: provider.playlists.length,
          itemBuilder: (context, index) {
            final playlist = provider.playlists[index];
            return PlaylistRow(
              playlistId: playlist['id'] as int,
              playlistName: playlist['name'] as String,
              trackCount: playlist['track_count'] as int,
            );
          },
        );
      },
    );
  }
}
