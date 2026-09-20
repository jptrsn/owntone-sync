import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/browse_provider.dart';
import '../screens/artist_detail_screen.dart';
import '../widgets/play_button.dart';
import '../../data/repositories/local_database_repository.dart';

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

            return PlayableTile(
              track: SyncedTrack(
                id: index + 1,
                title: artist,
                artist: artist,
                album: 'Unknown Album',
                albumArtist: artist,
                localPath: '',
                serverPath: '',
                downloadTimestamp: 0,
                fileSize: 0,
                genre: '',
                lengthMs: 0,
                trackNumber: 1,
                discNumber: 1,
                year: 2024,
                artworkUrl: '',
                contentUri: '',
              ),
              child: ListTile(
                leading: const CircleAvatar(child: Icon(Icons.person)),
                title: Text(artist),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ArtistDetailScreen(artistName: artist),
                    ),
                  );
                },
              ),
            );
          },
        );
      },
    );
  }
}
