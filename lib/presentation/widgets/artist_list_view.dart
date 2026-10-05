import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../providers/browse_provider.dart';
import 'library_rows.dart';

/// The Artists tab: tap opens the artist detail screen; Play all / Shuffle
/// all / Add to queue live in the row menu.
class ArtistListView extends StatelessWidget {
  const ArtistListView({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<BrowseProvider>(
      builder: (context, provider, child) {
        if (provider.artists.isEmpty) {
          return const Center(child: Text('No artists found'));
        }

        return ListView.builder(
          itemCount: provider.artists.length,
          itemBuilder: (context, index) {
            final artist = provider.artists[index];
            return ArtistRow(
              artistName: artist['artist'] as String,
              trackCount: artist['track_count'] as int,
              albumCount: artist['album_count'] as int? ?? 0,
            );
          },
        );
      },
    );
  }
}
