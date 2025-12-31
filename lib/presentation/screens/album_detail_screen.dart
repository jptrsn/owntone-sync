import 'dart:io';
import 'package:flutter/material.dart';
import '../../data/repositories/local_database_repository.dart';

class AlbumDetailScreen extends StatefulWidget {
  final String albumName;
  final String artistName;
  final String? artworkPath;

  const AlbumDetailScreen({
    super.key,
    required this.albumName,
    required this.artistName,
    this.artworkPath,
  });

  @override
  State<AlbumDetailScreen> createState() => _AlbumDetailScreenState();
}

class _AlbumDetailScreenState extends State<AlbumDetailScreen> {
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
    final tracks = await _dbRepo.getTracksByAlbum(widget.albumName);
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

  String _formatTotalDuration() {
    final totalMs = _tracks.fold<int>(0, (sum, track) => sum + track.lengthMs);
    final duration = Duration(milliseconds: totalMs);
    final hours = duration.inHours;
    final minutes = duration.inMinutes % 60;

    if (hours > 0) {
      return '$hours hr $minutes min';
    }
    return '$minutes min';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.albumName),
        backgroundColor: Theme.of(context).colorScheme.inversePrimary,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _tracks.isEmpty
          ? const Center(child: Text('No tracks found'))
          : Column(
              children: [
                // Album header
                Container(
                  padding: const EdgeInsets.all(16),
                  child: Row(
                    children: [
                      // Album artwork
                      widget.artworkPath != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.file(
                                File(widget.artworkPath!),
                                width: 120,
                                height: 120,
                                fit: BoxFit.cover,
                                errorBuilder: (_, _, _) => Container(
                                  width: 120,
                                  height: 120,
                                  color: Colors.grey[300],
                                  child: const Icon(Icons.album, size: 60),
                                ),
                              ),
                            )
                          : Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                color: Colors.grey[300],
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Icon(Icons.album, size: 60),
                            ),
                      const SizedBox(width: 16),
                      // Album info
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.albumName,
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              widget.artistName,
                              style: TextStyle(
                                fontSize: 16,
                                color: Colors.grey[600],
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              '${_tracks.length} tracks • ${_formatTotalDuration()}',
                              style: Theme.of(context).textTheme.bodySmall,
                            ),
                            if (_tracks.first.year > 0) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${_tracks.first.year}',
                                style: Theme.of(context).textTheme.bodySmall,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const Divider(),
                // Track list
                Expanded(
                  child: ListView.builder(
                    itemCount: _tracks.length,
                    itemBuilder: (context, index) {
                      final track = _tracks[index];
                      return ListTile(
                        leading: track.trackNumber > 0
                            ? SizedBox(
                                width: 30,
                                child: Text(
                                  '${track.trackNumber}',
                                  textAlign: TextAlign.center,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              )
                            : const Icon(Icons.music_note),
                        title: Text(track.title),
                        subtitle: track.genre.isNotEmpty
                            ? Text(track.genre)
                            : null,
                        trailing: Text(
                          _formatDuration(track.lengthMs),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                      );
                    },
                  ),
                ),
              ],
            ),
    );
  }
}
