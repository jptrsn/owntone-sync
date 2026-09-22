# Plan: Play Music from Browse Screen

## Goal
Allow the user to play playlists, artists, albums, and tracks from the Browse tab. The PlayerProvider's methods are already partially implemented but never called from the UI.

## Current State Analysis

**What exists (already built, just unconnected):**
- `PlayButton` widget — plays individual tracks via `playerProvider.playTrack(track.id)`
- `PlayableTile` widget — wraps `ListTile` with a `PlayButton` overlay
- `MiniPlayer` — shows at bottom of screen when playing
- `PlayerScreen` — full-screen now playing with seek bar, controls, shuffle/repeat
- `PlayerProvider` has `playTrack(trackId)`, `loadPlaylist(playlistId)`, `loadAllTracks()`, `skipToNext()`, `skipToPrevious()`
- `MainNavigationScreen` has a `Stack` with `_screens` + `MiniPlayer` positioned above the nav bar

**What's broken:**
- `PlayButton` only calls `playerProvider.playTrack(track.id)` — a single track ID
- No "play all" / "queue" / "shuffle" actions exist for collections
- `PlayerProvider.playTrack()` doesn't load a queue — it just tries to play one track via MethodChannel
- `PlaylistListView`, `ArtistListView`, `AlbumListView` create **fake** `SyncedTrack` objects with no real `contentUri`
- Tap on playlist/artist/album navigates to detail screen — doesn't play anything
- `BrowseScreen` also has a `MiniPlayer` in its `bottomSheet` — **duplicate** with `MainNavigationScreen`

**The gap:**
- Tapping a playlist row → nothing happens (taps go to detail screen)
- Tapping a track row → calls `playTrack(trackId)` but no queue is loaded
- No way to load a playlist's tracks into the player's queue

## UI Elements Needed

### 1. Play button on playlist rows (`PlaylistListView`)
- **Tap:** Load playlist tracks into queue → play first track
- **Long-press:** Context menu: "Play All", "Shuffle"
- **Fix:** Remove fake `SyncedTrack` — use real playlist ID for play logic

### 2. Play button on artist rows (`ArtistListView`)
- **Tap:** Load artist tracks into queue → play first track
- **Long-press:** Context menu: "Play All", "Shuffle"
- **Fix:** Remove fake `SyncedTrack` — use real artist name for play logic

### 3. Play button on album rows (`AlbumListView`)
- **Tap:** Load album tracks into queue → play first track
- **Long-press:** Context menu: "Play All", "Shuffle"
- **Fix:** Remove fake `SyncedTrack` — use real album/artist name for play logic

### 4. Play button on track rows (`TrackListView`)
- **Tap:** Play that single track (reset queue to just this track)
- **Long-press:** Context menu: "Play", "Play Next", "Add to Queue"
- **Already works** — uses real `SyncedTrack` objects

### 5. Queue view in PlayerScreen
- Add a "queue" icon button in the AppBar that expands a bottom sheet showing the current queue
- Each queue item is a `ListTile` with track info + a drag handle for reorder
- Swipe-left to remove tracks from queue

## Behavior: What happens on tap

### Single tap on PLAYLIST
1. `PlayerProvider.playPlaylist(playlistId)` loads tracks from DB via `getTracksForPlaylist()`
2. Queue is populated with those `SyncedTrack` objects
3. First track begins playing
4. Mini player appears showing first track
5. PlayerScreen shows now-playing

### Single tap on ARTIST
1. `PlayerProvider.playArtist(artistName)` loads tracks from DB via `getTracksByArtist()`
2. Queue populated with those tracks (sorted by album/track number)
3. First track begins playing

### Single tap on ALBUM
1. `PlayerProvider.playAlbum(albumName, artistName)` loads tracks from DB via `getTracksByAlbum()`
2. Queue populated (sorted by disc/track number)
3. First track begins playing

### Single tap on TRACK
1. `PlayerProvider.playTrack(trackId)` — plays just that track, resets queue to single track
2. If already playing that track → toggle pause/resume

### Long-press (context menu)
- **Track:** "Play" (same as tap), "Play Next" (insert before current), "Add to Queue" (append to end)
- **Playlist/Artist/Album:** "Play All" (load queue + play first), "Shuffle" (load queue shuffled + play first)

## Files to Modify

| File | Action |
|---|---|
| `lib/presentation/providers/player_provider.dart` | Add `playPlaylist(playlistId)`, `playArtist(artistName)`, `playAlbum(albumName, artistName)`, `playNext(SyncedTrack)`, `addToQueue(SyncedTrack)` |
| `lib/presentation/widgets/play_button.dart` | Add `onLongPress` callback to `PlayableTile`; add context menu option to `PlayButton` |
| `lib/presentation/widgets/playlist_list_view.dart` | Remove fake `SyncedTrack`; use real playlist ID; add `onTap` to play playlist |
| `lib/presentation/widgets/artist_list_view.dart` | Remove fake `SyncedTrack`; use real artist name; add `onTap` to play artist |
| `lib/presentation/widgets/album_list_view.dart` | Remove fake `SyncedTrack`; use real album/artist name; add `onTap` to play album |
| `lib/presentation/widgets/track_list_view.dart` | Add long-press context menu |
| `lib/presentation/screens/player_screen.dart` | Wire up the queue button to show a reorderable queue sheet |
| `lib/presentation/screens/browse_screen.dart` | Remove duplicate `MiniPlayer` bottomSheet (MainNavigationScreen already has one) |

## Step-by-Step Implementation

### Step 1: PlayerProvider — add queue methods
Add to `lib/presentation/providers/player_provider.dart`:

```dart
/// Play a playlist, load its tracks, play first
Future<void> playPlaylist(int playlistId, {bool shuffle = false}) async {
  _currentPlaylistId = playlistId;
  _queue = await _syncProvider.getTracksForPlaylist(playlistId) ?? [];
  if (shuffle) {
    _queue = List.from(_queue)
      ..shuffle();
  }
  await _loadQueueIntoAudioHandler();
  if (_queue.isNotEmpty) {
    _currentTrackId = _queue.first.id;
    _isPlaying = true;
    _currentTrackDuration = _queue.first.lengthMs > 0 
        ? Duration(milliseconds: _queue.first.lengthMs) 
        : null;
    notifyListeners();
  }
}

/// Play all tracks by an artist
Future<void> playArtist(String artistName, {bool shuffle = false}) async {
  _currentPlaylistId = null;
  _queue = await _syncProvider.getTracksByArtist(artistName) ?? [];
  if (shuffle) {
    _queue = List.from(_queue)..shuffle();
  }
  await _loadQueueIntoAudioHandler();
  if (_queue.isNotEmpty) {
    _currentTrackId = _queue.first.id;
    _isPlaying = true;
    _currentTrackDuration = _queue.first.lengthMs > 0 
        ? Duration(milliseconds: _queue.first.lengthMs) 
        : null;
    notifyListeners();
  }
}

/// Play all tracks in an album
Future<void> playAlbum(String albumName, String artistName, {bool shuffle = false}) async {
  _currentPlaylistId = null;
  _queue = await _syncProvider.getTracksByAlbum(albumName) ?? [];
  if (shuffle) {
    _queue = List.from(_queue)..shuffle();
  }
  await _loadQueueIntoAudioHandler();
  if (_queue.isNotEmpty) {
    _currentTrackId = _queue.first.id;
    _isPlaying = true;
    _currentTrackDuration = _queue.first.lengthMs > 0 
        ? Duration(milliseconds: _queue.first.lengthMs) 
        : null;
    notifyListeners();
  }
}

/// Play a single track, reset queue to just this track
Future<void> playTrack(int trackId) async {
  try {
    final track = await _syncProvider.getTrackById(trackId);
    if (track == null) return;
    
    await _playerChannel.invokeMethod('playTrack', {'trackId': trackId});
    _isPlaying = true;
    _currentTrackId = trackId;
    _currentPlaylistId = null;
    _queue = [track];
    _currentTrackDuration = track.lengthMs > 0 
        ? Duration(milliseconds: track.lengthMs) 
        : null;
    notifyListeners();
  } catch (e) {
    if (kDebugMode) {
      print('Error playing track: $e');
    }
  }
}

/// Insert track before current position (Play Next)
Future<void> playNext(SyncedTrack track) async {
  int currentIndex = _queue.indexWhere((t) => t.id == _currentTrackId);
  if (currentIndex == -1) currentIndex = 0;
  
  _queue.insert(currentIndex + 1, track);
  _queueVersion = _queue.length;
  await _loadQueueIntoAudioHandler();
  
  await _playerChannel.invokeMethod('playTrack', {'trackId': track.id});
  _isPlaying = true;
  _currentTrackId = track.id;
  _currentTrackDuration = track.lengthMs > 0 
      ? Duration(milliseconds: track.lengthMs) 
      : null;
  notifyListeners();
}

/// Append track to end of queue (Add to Queue)
Future<void> addToQueue(SyncedTrack track) async {
  _queue.add(track);
  _queueVersion = _queue.length;
  notifyListeners();
}
```

### Step 2: PlayButton — add context menu support
Update `lib/presentation/widgets/play_button.dart`:

```dart
// PlayButton now takes onLongPress and can show context menu
class PlayButton extends StatelessWidget {
  final SyncedTrack track;
  final bool showNextIcon;
  final bool showContextMenu;

  const PlayButton({
    super.key,
    required this.track,
    this.showNextIcon = false,
    this.showContextMenu = false,
  });

  @override
  Widget build(BuildContext context) {
    return Consumer<PlayerProvider>(
      builder: (context, playerProvider, child) {
        final currentTrack = playerProvider.getCurrentlyPlayingTrack();
        final isPlaying = currentTrack != null && currentTrack.id == track.id;

        return GestureDetector(
          onLongPress: showContextMenu
              ? () => _showPlayMenu(context, playerProvider, track)
              : null,
          child: IconButton(
            onPressed: () {
              playerProvider.playTrack(track.id);
            },
            icon: _buildIcon(isPlaying),
            tooltip: isPlaying ? 'Pause track' : 'Play track',
          ),
        );
      },
    );
  }

  void _showPlayMenu(BuildContext context, PlayerProvider provider, SyncedTrack track) {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.play_arrow),
            title: const Text('Play'),
            onTap: () {
              provider.playTrack(track.id);
              Navigator.of(ctx).pop();
            },
          ),
          ListTile(
            leading: const Icon(Icons.skip_next),
            title: const Text('Play Next'),
            onTap: () {
              provider.playNext(track);
              Navigator.of(ctx).pop();
            },
          ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('Add to Queue'),
            onTap: () {
              provider.addToQueue(track);
              Navigator.of(ctx).pop();
            },
          ),
        ],
      ),
    );
  }
}
```

### Step 3: PlaylistListView — connect to player
Replace fake `SyncedTrack` with real playlist ID:

```dart
return GestureDetector(
  onLongPress: () {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.play_all),
            title: const Text('Play All'),
            onTap: () {
              final provider = context.read<PlayerProvider>();
              provider.playPlaylist(playlist['id'] as int);
              Navigator.of(ctx).pop();
            },
          ),
          ListTile(
            leading: const Icon(Icons.shuffle),
            title: const Text('Shuffle'),
            onTap: () {
              final provider = context.read<PlayerProvider>();
              provider.playPlaylist(playlist['id'] as int, shuffle: true);
              Navigator.of(ctx).pop();
            },
          ),
        ],
      ),
    );
  },
  child: PlayableTile(
    track: SyncedTrack(
      id: playlist['id'] as int, // fake ID for play button icon state only
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
      subtitle: Text('$trackCount ${trackCount == 1 ? 'track' : 'tracks'}'),
      trailing: const Icon(Icons.chevron_right),
      onTap: () {
        // Play playlist immediately, don't go to detail screen
        final provider = context.read<PlayerProvider>();
        provider.playPlaylist(playlist['id'] as int);
      },
    ),
  ),
);
```

### Step 4: ArtistListView — connect to player
Same pattern:

```dart
return GestureDetector(
  onLongPress: () {
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.play_all),
            title: const Text('Play All'),
            onTap: () {
              final provider = context.read<PlayerProvider>();
              provider.playArtist(artist);
              Navigator.of(ctx).pop();
            },
          ),
          ListTile(
            leading: const Icon(Icons.shuffle),
            title: const Text('Shuffle'),
            onTap: () {
              final provider = context.read<PlayerProvider>();
              provider.playArtist(artist, shuffle: true);
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
        final provider = context.read<PlayerProvider>();
        provider.playArtist(artist);
      },
    ),
  ),
);
```

### Step 5: AlbumListView — connect to player
Same pattern:

```dart
return GestureDetector(
  onLongPress: () {
    final albumName = album['album'] as String;
    final artistName = album['album_artist'] as String;
    showModalBottomSheet(
      context: context,
      builder: (ctx) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(Icons.play_all),
            title: const Text('Play All'),
            onTap: () {
              final provider = context.read<PlayerProvider>();
              provider.playAlbum(albumName, artistName);
              Navigator.of(ctx).pop();
            },
          ),
          ListTile(
            leading: const Icon(Icons.shuffle),
            title: const Text('Shuffle'),
            onTap: () {
              final provider = context.read<PlayerProvider>();
              provider.playAlbum(albumName, artistName, shuffle: true);
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
        final provider = context.read<PlayerProvider>();
        provider.playAlbum(
          album['album'] as String,
          album['album_artist'] as String,
        );
      },
    ),
  ),
);
```

### Step 6: TrackListView — add context menu
Already uses real `SyncedTrack`. Add `onLongPress` to `PlayableTile`:

```dart
return PlayableTile(
  track: track,
  showContextMenu: true,
  child: ListTile(
    title: Text(track.title),
    subtitle: Text('${track.artist} • ${track.album}'),
    trailing: Text(
      _formatDuration(track.lengthMs),
      style: Theme.of(context).textTheme.bodySmall,
    ),
  ),
);
```

### Step 7: PlayerScreen — add queue view
In `PlayerScreen.build()`, add a queue icon in the AppBar:

```dart
actions: [
  IconButton(
    icon: const Icon(Icons.queue_music),
    onPressed: () => _showQueueSheet(context),
  ),
],
```

Where `_showQueueSheet` expands a bottom sheet:

```dart
void _showQueueSheet(BuildContext context) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => Consumer<PlayerProvider>(
      builder: (context, playerProvider, child) {
        return DraggableScrollableSheet(
          initialChildSize: 0.4,
          maxChildSize: 0.8,
          builder: (_, controller) => Column(
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      'Queue (${playerProvider.queue.length})',
                      style: Theme.of(context).textTheme.headlineSmall,
                    ),
                    const Spacer(),
                    IconButton(
                      icon: const Icon(Icons.clear_all),
                      onPressed: () {
                        // Clear queue
                      },
                    ),
                  ],
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: controller,
                  itemCount: playerProvider.queue.length,
                  itemBuilder: (ctx, index) {
                    final track = playerProvider.queue[index];
                    final isCurrent = track.id == playerProvider.currentTrackId;
                    return ListTile(
                      leading: Icon(
                        isCurrent ? Icons.musical_notes : Icons.music_note,
                        color: isCurrent 
                            ? Theme.of(context).colorScheme.primary 
                            : null,
                      ),
                      title: Text(track.title),
                      subtitle: Text(track.artist),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline),
                        onPressed: () {
                          // Remove from queue
                        },
                      ),
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}
```

### Step 8: Remove duplicate MiniPlayer from BrowseScreen
In `browse_screen.dart`, remove `bottomSheet: const MiniPlayer()`. `MainNavigationScreen` already has the `MiniPlayer` in its `Stack`.

```dart
// BEFORE:
return Scaffold(
  body: Column(...),
  bottomSheet: const MiniPlayer(), // REMOVE THIS
);

// AFTER:
return Scaffold(
  body: Column(...),
);
```

## Verification Steps

1. Run `dart analyze` — 0 errors
2. Run `flutter build apk --debug -d emulator-5554` — success
3. Test: Tap playlist → mini player appears, track plays
4. Test: Long-press playlist → context menu shows "Play All", "Shuffle"
5. Test: Tap artist → tracks play
6. Test: Tap album → tracks play
7. Test: Tap track → single track plays
8. Test: Long-press track → context menu shows "Play", "Play Next", "Add to Queue"
9. Test: Queue button in PlayerScreen → shows queue list
10. Test: Mini player opens PlayerScreen
