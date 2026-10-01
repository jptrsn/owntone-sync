import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../data/repositories/local_database_repository.dart';
import '../controllers/playback_controller.dart';
import '../widgets/player_scaffold.dart';
import '../widgets/library_rows.dart';

/// Search over the synced library: track title, artist, album, and playlist
/// name. Results are grouped by type; every result is playable or openable.
/// Reachable only from the Library app bar search affordance.
class SearchScreen extends StatefulWidget {
  const SearchScreen({super.key});

  @override
  State<SearchScreen> createState() => _SearchScreenState();
}

class _SearchScreenState extends State<SearchScreen> {
  final TextEditingController _textController = TextEditingController();
  late final PlaybackController _controller;
  Timer? _debounce;
  String _query = '';
  LibrarySearchResult? _result;
  bool _searching = false;

  @override
  void initState() {
    super.initState();
    _controller = context.read<PlaybackController>();
    // A rating can be committed on the Now Playing sheet while this screen
    // is mounted underneath it; the sheet only refreshes the BrowseProvider,
    // so rerun the search when the sheet closes.
    _controller.nowPlayingSheetOpen.addListener(_onSheetClosed);
  }

  void _onSheetClosed() {
    if (!_controller.nowPlayingSheetOpen.value && _query.isNotEmpty) {
      _search(_query);
    }
  }

  @override
  void dispose() {
    _controller.nowPlayingSheetOpen.removeListener(_onSheetClosed);
    _debounce?.cancel();
    _textController.dispose();
    super.dispose();
  }

  void _onChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _query = '';
        _result = null;
        _searching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 300), () => _search(value));
  }

  Future<void> _search(String value) async {
    final trimmed = value.trim();
    setState(() {
      _query = trimmed;
      _searching = true;
    });
    final result = await LocalDatabaseRepository().searchLibrary(trimmed);
    if (!mounted) return;
    setState(() {
      _result = result;
      _searching = false;
    });
  }

  void _clear() {
    _textController.clear();
    _onChanged('');
  }

  Widget _sectionHeader(String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          fontWeight: FontWeight.bold,
          fontSize: 14,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_query.isEmpty) {
      return const Center(
        child: Text('Search your library by track, artist, album, or playlist.'),
      );
    }
    if (_searching) {
      return const Center(child: CircularProgressIndicator());
    }
    final result = _result;
    if (result == null) {
      return const SizedBox.shrink();
    }
    final empty =
        result.playlists.isEmpty &&
        result.artists.isEmpty &&
        result.albums.isEmpty &&
        result.tracks.isEmpty;
    if (empty) {
      return Center(child: Text('No results for "$_query"'));
    }

    return ListView(
      children: [
        if (result.playlists.isNotEmpty) ...[
          _sectionHeader('Playlists'),
          for (final playlist in result.playlists)
            PlaylistRow(
              playlistId: playlist['id'] as int,
              playlistName: playlist['name'] as String,
              trackCount: playlist['track_count'] as int? ?? 0,
            ),
        ],
        if (result.artists.isNotEmpty) ...[
          _sectionHeader('Artists'),
          for (final artist in result.artists)
            ArtistRow(
              artistName: artist['artist'] as String,
              trackCount: artist['track_count'] as int? ?? 0,
              albumCount: artist['album_count'] as int? ?? 0,
            ),
        ],
        if (result.albums.isNotEmpty) ...[
          _sectionHeader('Albums'),
          for (final album in result.albums)
            AlbumRow(
              albumName: album['album'] as String,
              artistName: album['album_artist'] as String? ?? '',
              year: album['year'] as int? ?? 0,
              artworkPath: album['artwork_path'] as String?,
              trackCount: album['track_count'] as int? ?? 0,
            ),
        ],
        if (result.tracks.isNotEmpty) ...[
          _sectionHeader('Tracks'),
          for (var i = 0; i < result.tracks.length; i++)
            TrackRow(
              track: result.tracks[i],
              collection: result.tracks,
              index: i,
              // Search results are themselves the visible list, so a tapped
              // track plays in context over the other track results.
              origin: QueueOrigin.search(_query),
              onRatingChanged: () => _search(_query),
            ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return PlayerScaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: Expanded(
          child: TextField(
            controller: _textController,
            autofocus: true,
            decoration: InputDecoration(
              hintText: 'Search tracks, artists, albums, playlists',
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              suffixIcon: _textController.text.isEmpty
                  ? null
                  : IconButton(
                      tooltip: 'Clear',
                      icon: const Icon(Icons.clear),
                      onPressed: _clear,
                    ),
              border: InputBorder.none,
            ),
            onChanged: _onChanged,
          ),
        ),
      ),
      body: _buildBody(),
    );
  }
}
