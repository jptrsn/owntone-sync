import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/browse_provider.dart';
import 'library_rows.dart';

/// The Albums tab: tap opens the album detail screen; Play / Shuffle / Add
/// to queue / Go to artist live in the row menu.
class AlbumListView extends StatelessWidget {
  const AlbumListView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BrowseProvider>(
      builder: (context, provider, child) {
        if (provider.albums.isEmpty) {
          return const Center(child: Text('No albums found'));
        }

        return ListView.builder(
          itemCount: provider.albums.length,
          itemBuilder: (context, index) {
            final album = provider.albums[index];
            return AlbumRow(
              albumName: album['album'] as String,
              artistName: album['album_artist'] as String? ?? '',
              year: album['year'] as int? ?? 0,
              artworkPath: album['artwork_path'] as String?,
              trackCount: album['track_count'] as int? ?? 0,
            );
          },
        );
      },
    );
  }
}
