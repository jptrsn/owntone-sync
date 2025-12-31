import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/browse_provider.dart';
import '../screens/playlist_detail_screen.dart';

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
            final trackCount = playlist['track_count'] as int;

            return ListTile(
              leading: const Icon(Icons.queue_music),
              title: Text(playlist['name'] as String),
              subtitle: Text(
                '$trackCount ${trackCount == 1 ? 'track' : 'tracks'}',
              ),
              trailing: const Icon(Icons.chevron_right),
              onTap: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PlaylistDetailScreen(
                      playlistId: playlist['id'] as int,
                      playlistName: playlist['name'] as String,
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}
