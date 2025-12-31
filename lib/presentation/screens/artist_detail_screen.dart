import 'package:flutter/material.dart';
import '../../data/repositories/local_database_repository.dart';
import 'album_detail_screen.dart';
import 'dart:io';

class ArtistDetailScreen extends StatefulWidget {
  final String artistName;

  const ArtistDetailScreen({super.key, required this.artistName});

  @override
  State<ArtistDetailScreen> createState() => _ArtistDetailScreenState();
}

class _ArtistDetailScreenState extends State<ArtistDetailScreen> {
  final LocalDatabaseRepository _dbRepo = LocalDatabaseRepository();
  List<SyncedTrack> _tracks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    setState(() => _isLoading = true);
    final tracks = await _dbRepo.getTracksByArtist(widget.artistName);
    setState(() {
      _tracks = tracks;
      _isLoading = false;
    });
  }

  String _formatDuration(int milliseconds) {
    final duration = Duration(milliseconds: milliseconds);
    final minutes = duration.inMinutes;
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  // Group tracks by album
  Map<String, List<SyncedTrack>> _groupByAlbum() {
    final grouped = <String, List<SyncedTrack>>{};
    for (final track in _tracks) {
      grouped.putIfAbsent(track.album, () => []).add(track);
    }
    return grouped;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.artistName),
        backgroundColor: Theme.of(context).colorScheme.surface,
        foregroundColor: Theme.of(context).colorScheme.onSurface,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _tracks.isEmpty
          ? const Center(child: Text('No tracks found'))
          : ListView(
              children: _groupByAlbum().entries.map((entry) {
                final album = entry.key;
                final tracks = entry.value;
                final artworkPath = tracks.first.artworkPath;

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ListTile(
                      leading: artworkPath != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(4),
                              child: Image.file(
                                File(artworkPath),
                                width: 56,
                                height: 56,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) =>
                                    const Icon(Icons.album),
                              ),
                            )
                          : const Icon(Icons.album),
                      title: Text(
                        album,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text('${tracks.length} tracks'),
                      trailing: const Icon(Icons.chevron_right),
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => AlbumDetailScreen(
                              albumName: album,
                              artistName: widget.artistName,
                              artworkPath: artworkPath,
                            ),
                          ),
                        );
                      },
                    ),
                    ...tracks.map(
                      (track) => Padding(
                        padding: const EdgeInsets.only(left: 16),
                        child: ListTile(
                          leading: track.trackNumber > 0
                              ? Text(
                                  '${track.trackNumber}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                )
                              : null,
                          title: Text(track.title),
                          trailing: Text(
                            _formatDuration(track.lengthMs),
                            style: Theme.of(context).textTheme.bodySmall,
                          ),
                        ),
                      ),
                    ),
                    const Divider(),
                  ],
                );
              }).toList(),
            ),
    );
  }
}
