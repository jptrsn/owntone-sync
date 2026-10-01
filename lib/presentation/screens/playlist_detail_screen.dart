import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/local_database_repository.dart';
import '../controllers/playback_controller.dart';
import '../services/collection_playback.dart';
import '../widgets/player_scaffold.dart';
import '../widgets/library_rows.dart';

class PlaylistDetailScreen extends StatefulWidget {
  final int playlistId;
  final String playlistName;

  const PlaylistDetailScreen({
    super.key,
    required this.playlistId,
    required this.playlistName,
  });

  @override
  State<PlaylistDetailScreen> createState() => _PlaylistDetailScreenState();
}

class _PlaylistDetailScreenState extends State<PlaylistDetailScreen> {
  final LocalDatabaseRepository _dbRepo = LocalDatabaseRepository();
  List<SyncedTrack> _tracks = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadTracks();
  }

  Future<void> _loadTracks() async {
    final tracks = await _dbRepo.getTracksForPlaylist(widget.playlistId);
    if (!mounted) return;
    setState(() {
      _tracks = tracks;
      _isLoading = false;
    });
  }

  QueueOrigin get _origin =>
      QueueOrigin.playlist(widget.playlistId, widget.playlistName);

  @override
  Widget build(BuildContext context) {
    final controller = context.read<PlaybackController>();
    final colorScheme = Theme.of(context).colorScheme;

    return PlayerScaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 180,
            // Pinned so the collapsed bar (title + back button) stays
            // reachable; the header itself collapses from expanded to the
            // compact bar on scroll (B3).
            pinned: true,
            backgroundColor: colorScheme.surface,
            foregroundColor: colorScheme.onSurface,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(widget.playlistName),
              background: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Row(
                    children: [
                      Icon(
                        Icons.queue_music,
                        size: 64,
                        color: colorScheme.surfaceContainerHighest,
                      ),
                      const SizedBox(width: 16),
                      if (!_isLoading && _tracks.isNotEmpty)
                        Text(
                          '${_tracks.length} ${_tracks.length == 1 ? 'track' : 'tracks'}',
                          style: Theme.of(context).textTheme.titleMedium,
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
              child: const Center(child: Text('No tracks in this playlist')),
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
                    onRatingChanged: _loadTracks,
                    leading: track.trackNumber > 0
                        ? Text(
                            '${track.trackNumber}',
                            style: Theme.of(context).textTheme.bodyMedium,
                          )
                        : const Icon(Icons.music_note, size: 20),
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
