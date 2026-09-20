import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/browse_provider.dart';
import '../screens/album_detail_screen.dart';
import '../widgets/play_button.dart';
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

            return PlayableTile(
              track: SyncedTrack(
                id: index + 1,
                title: album['album'] as String,
                artist: album['album_artist'] as String,
                album: album['album'] as String,
                albumArtist: album['album_artist'] as String,
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
                title: Text(album['album'] as String),
                subtitle: Text(album['album_artist'] as String),
                trailing: const Icon(Icons.chevron_right),
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AlbumDetailScreen(
                        albumName: album['album'] as String,
                        artistName: album['album_artist'] as String,
                        artworkPath: artworkPath,
                      ),
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
