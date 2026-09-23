import 'dart:math';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/browse_provider.dart';
import '../controllers/playback_controller.dart';
import '../widgets/play_button.dart';
import '../screens/playlist_detail_screen.dart';
import '../../data/repositories/local_database_repository.dart';

class PlaylistListView extends StatelessWidget {
  const PlaylistListView({super.key});

  Future<void> _playAll(
    BuildContext context,
    int playlistId,
    String playlistName, {
    bool shuffle = false,
  }) async {
    final controller = context.read<PlaybackController>();
    final tracks =
        await LocalDatabaseRepository().getTracksForPlaylist(playlistId);
    if (tracks.isEmpty) return;
    final startIndex = shuffle ? Random().nextInt(tracks.length) : 0;
    await controller.playCollection(
      QueueOrigin.playlist(playlistId, playlistName),
      tracks,
      startIndex: startIndex,
    );
    if (shuffle) await controller.toggleShuffle();
  }

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
                          _playAll(
                            context,
                            playlist['id'] as int,
                            playlist['name'] as String,
                          );
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.shuffle),
                        title: const Text('Shuffle'),
                        onTap: () {
                          Navigator.of(ctx).pop();
                          _playAll(
                            context,
                            playlist['id'] as int,
                            playlist['name'] as String,
                            shuffle: true,
                          );
                        },
                      ),
                    ],
                  ),
                );
              },
              child: PlayableTile(
                track: SyncedTrack(
                  id: playlist['id'] as int,
                  title: playlist['name'] as String,
                  artist: '',
                  album: '',
                  albumArtist: '',
                  localPath: '',
                  serverPath: '',
                  downloadTimestamp: 0,
                  fileSize: 0,
                  genre: '',
                  lengthMs: trackCount * 180000,
                  trackNumber: 1,
                  discNumber: 1,
                  year: 2024,
                  artworkUrl: '',
                  contentUri: '',
                ),
                child: ListTile(
                  leading: const Icon(Icons.queue_music),
                  title: Text(playlist['name'] as String),
                  subtitle: Text(
                    '$trackCount ${trackCount == 1 ? 'track' : 'tracks'}',
                  ),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => PlaylistDetailScreen(
                          playlistId: playlist['id'] as int,
                          playlistName: playlist['name'] as String,
                        ),
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
