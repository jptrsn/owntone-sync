import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/browse_provider.dart';
import '../controllers/playback_controller.dart';
import '../widgets/play_button.dart';
import '../screens/artist_detail_screen.dart';
import '../../data/repositories/local_database_repository.dart';

class ArtistListView extends StatelessWidget {
  const ArtistListView({super.key});

  Future<void> _playAll(
    BuildContext context,
    String artist, {
    bool shuffle = false,
  }) async {
    final controller = context.read<PlaybackController>();
    final tracks = await LocalDatabaseRepository().getTracksByArtist(artist);
    if (tracks.isEmpty) return;
    final startIndex = shuffle ? Random().nextInt(tracks.length) : 0;
    await controller.playCollection(
      QueueOrigin.artist(artist),
      tracks,
      startIndex: startIndex,
    );
    if (shuffle) await controller.toggleShuffle();
  }

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

            return GestureDetector(
              onLongPress: () {
                showModalBottomSheet(
                  context: context,
                  builder: (ctx) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        leading: const Icon(Icons.playlist_play),
                        title: const Text('Play All'),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _playAll(context, artist);
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.shuffle),
                        title: const Text('Shuffle'),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _playAll(context, artist, shuffle: true);
                        },
                      ),
                    ],
                  ),
                );
              },
              child: PlayableTile(
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
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => ArtistDetailScreen(artistName: artist),
                      ),
                    );
                  },
                ),
              ),
            );
          },
        );
      },
    );
  }
}
