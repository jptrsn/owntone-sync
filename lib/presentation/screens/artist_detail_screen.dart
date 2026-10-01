import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/local_database_repository.dart';
import '../controllers/playback_controller.dart';
import '../services/collection_playback.dart';
import '../widgets/player_scaffold.dart';
import '../widgets/library_rows.dart';
import 'album_detail_screen.dart';

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
    final tracks = await _dbRepo.getTracksByArtist(widget.artistName);
    if (!mounted) return;
    setState(() {
      _tracks = tracks;
      _isLoading = false;
    });
  }

  Map<String, List<SyncedTrack>> _groupByAlbum() {
    final grouped = <String, List<SyncedTrack>>{};
    for (final track in _tracks) {
      grouped.putIfAbsent(track.album, () => []).add(track);
    }
    return grouped;
  }

  QueueOrigin get _origin => QueueOrigin.artist(widget.artistName);

  @override
  Widget build(BuildContext context) {
    final controller = context.read<PlaybackController>();
    final colorScheme = Theme.of(context).colorScheme;
    final groups = _groupByAlbum();
    final entries = groups.entries.toList();
    final indexById = {
      for (var i = 0; i < _tracks.length; i++) _tracks[i].id: i,
    };

    return PlayerScaffold(
      body: CustomScrollView(
        slivers: [
          SliverAppBar(
            expandedHeight: 200,
            pinned: true,
            backgroundColor: colorScheme.surface,
            foregroundColor: colorScheme.onSurface,
            flexibleSpace: FlexibleSpaceBar(
              title: Text(widget.artistName),
              background: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 16),
                child: Align(
                  alignment: Alignment.bottomLeft,
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 36,
                        child: Text(
                          artistInitials(widget.artistName),
                          style: const TextStyle(fontSize: 24),
                        ),
                      ),
                      const SizedBox(width: 16),
                      if (!_isLoading && _tracks.isNotEmpty)
                        Text(
                          '${groups.length} ${groups.length == 1 ? 'album' : 'albums'} \u2022 ${_tracks.length} ${_tracks.length == 1 ? 'track' : 'tracks'}',
                          style: Theme.of(context).textTheme.titleMedium,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
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
                  final entry = entries[index];
                  final album = entry.key;
                  final tracks = entry.value;
                  final artworkPath = tracks.first.artworkPath;
                  // The section groups by album NAME; pass the full identity
                  // only when the section is uniform, so the detail screen
                  // shows exactly the tracks the section shows (same-named
                  // albums by other artists are excluded).
                  final artists = tracks.map((t) => t.albumArtist).toSet();
                  final years = tracks.map((t) => t.year).toSet();

                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      ListTile(
                        leading: AlbumArtTile(artworkPath: artworkPath),
                        title: Text(
                          album,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        subtitle:
                            Text('${tracks.length} ${tracks.length == 1 ? 'track' : 'tracks'}'),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () {
                          Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => AlbumDetailScreen(
                                albumName: album,
                                artistName: widget.artistName,
                                artworkPath: artworkPath,
                                albumArtist: artists.length == 1
                                    ? artists.first
                                    : null,
                                year: years.length == 1 ? years.first : null,
                              ),
                            ),
                          );
                        },
                      ),
                      for (final track in tracks)
                        TrackRow(
                          track: track,
                          collection: _tracks,
                          index: indexById[track.id]!,
                          origin: _origin,
                          secondary: track.album,
                          onRatingChanged: _loadTracks,
                        ),
                      const Divider(),
                    ],
                  );
                },
                childCount: entries.length,
              ),
            ),
        ],
      ),
    );
  }
}
