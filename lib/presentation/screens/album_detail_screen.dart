import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/local_database_repository.dart';
import '../controllers/playback_controller.dart';
import '../services/collection_playback.dart';
import '../widgets/player_scaffold.dart';
import '../widgets/library_rows.dart';

class AlbumDetailScreen extends StatefulWidget {
  final String albumName;
  final String artistName;
  final String? artworkPath;

  /// Album identity used to disambiguate same-named albums across artists
  /// and years (the displayed row is one (album, artist, year) group).
  final String? albumArtist;
  final int? year;

  const AlbumDetailScreen({
    super.key,
    required this.albumName,
    required this.artistName,
    this.artworkPath,
    this.albumArtist,
    this.year,
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
    final tracks = await _dbRepo.getTracksByAlbum(
      widget.albumName,
      albumArtist: widget.albumArtist,
      year: widget.year,
    );
    if (!mounted) return;
    setState(() {
      _tracks = tracks;
      _isLoading = false;
    });
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

  QueueOrigin get _origin => QueueOrigin.album(widget.albumName);

  @override
  Widget build(BuildContext context) {
    final controller = context.read<PlaybackController>();
    final colorScheme = Theme.of(context).colorScheme;

    return PlayerScaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 260,
            pinned: true,
            backgroundColor: colorScheme.surface,
            foregroundColor: colorScheme.onSurface,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(widget.albumName),
              background: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Row(
                    children: [
                      AlbumArtTile(
                        artworkPath: widget.artworkPath,
                        size: 120,
                        borderRadius: 8,
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            Text(
                              widget.artistName,
                              style: Theme.of(context).textTheme.titleMedium,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                            if (!_isLoading && _tracks.isNotEmpty) ...[
                              const SizedBox(height: 4),
                              Text(
                                '${_tracks.length} ${_tracks.length == 1 ? 'track' : 'tracks'} \u2022 ${_formatTotalDuration()}'
                                '${_tracks.first.year > 0 ? ' \u2022 ${_tracks.first.year}' : ''}',
                                style: Theme.of(context).textTheme.bodySmall,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(
                children: [
                  FilledButton.icon(
                    onPressed:
                        _isLoading || _tracks.isEmpty
                            ? null
                            : () =>
                                playCollectionInOrder(controller, _origin, _tracks),
                    icon: const Icon(Icons.play_arrow),
                    label: const Text('Play'),
                  ),
                  const SizedBox(width: 8),
                  OutlinedButton.icon(
                    onPressed:
                        _isLoading || _tracks.isEmpty
                            ? null
                            : () => shuffleCollection(controller, _origin, _tracks),
                    icon: const Icon(Icons.shuffle),
                    label: const Text('Shuffle'),
                  ),
                ],
              ),
            ),
          ),
          if (_isLoading)
            const SliverToBoxAdapter(
              child: Padding(
                padding: EdgeInsets.all(32),
                child: Center(child: CircularProgressIndicator()),
              ),
            )
          else if (_tracks.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: const Center(child: Text('No tracks found')),
            )
          else
            SliverList(
              delegate: SliverChildBuilderDelegate(
                (context, index) {
                  final track = _tracks[index];
                  return TrackRow(
                    track: track,
                    collection: _tracks,
                    index: index,
                    origin: _origin,
                    leading: track.trackNumber > 0
                        ? Text(
                            '${track.trackNumber}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          )
                        : const Icon(Icons.music_note, size: 20),
                    secondary:
                        track.genre.isNotEmpty ? track.genre : null,
                  );
                },
                childCount: _tracks.length,
              ),
            ),
        ],
      ),
    );
  }
}
