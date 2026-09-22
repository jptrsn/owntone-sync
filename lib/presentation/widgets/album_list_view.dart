import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/browse_provider.dart';
import '../providers/player_provider.dart';
import '../widgets/play_button.dart';
import '../screens/album_detail_screen.dart';
import '../../data/repositories/local_database_repository.dart';

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
            final artworkPath = album['artwork_path'] as String?;
            final albumName = album['album'] as String;
            final artistName = album['album_artist'] as String;

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
                          final playerProvider =
                              context.read<PlayerProvider>();
                          playerProvider.playAlbum(albumName, artistName);
                          Navigator.of(ctx).pop();
                        },
                      ),
                      ListTile(
                        leading: const Icon(Icons.shuffle),
                        title: const Text('Shuffle'),
                        onTap: () {
                          final playerProvider =
                              context.read<PlayerProvider>();
                          playerProvider.playAlbum(
                            albumName,
                            artistName,
                            shuffle: true,
                          );
                          Navigator.of(ctx).pop();
                        },
                      ),
                    ],
                  ),
                );
              },
              child: PlayableTile(
                track: SyncedTrack(
                  id: index + 1,
                  title: albumName,
                  artist: artistName,
                  album: albumName,
                  albumArtist: artistName,
                  localPath: '',
                  serverPath: '',
                  downloadTimestamp: 0,
                  fileSize: 0,
                  genre: '',
                  lengthMs: 0,
                  trackNumber: 1,
                  discNumber: 1,
                  year: album['year'] as int? ?? 2024,
                  artworkUrl: '',
                  contentUri: '',
                ),
                child: ListTile(
                  leading: _buildAlbumArt(artworkPath),
                  title: Text(albumName),
                  subtitle: Text(artistName),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => AlbumDetailScreen(
                          albumName: albumName,
                          artistName: artistName,
                          artworkPath: artworkPath,
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

  Widget _buildAlbumArt(String? artworkPath) {
    if (artworkPath != null && artworkPath.isNotEmpty) {
      final file = File(artworkPath);
      if (file.existsSync() && file.lengthSync() > 0) {
        return ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: Image.file(
            file,
            width: 56,
            height: 56,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) => _buildPlaceholder(),
          ),
        );
      }
    }

    return _buildPlaceholder();
  }

  Widget _buildPlaceholder() {
    return Container(
      width: 56,
      height: 56,
      decoration: BoxDecoration(
        color: Colors.grey[300],
        borderRadius: BorderRadius.circular(4),
      ),
      child: const Icon(Icons.album),
    );
  }
}
