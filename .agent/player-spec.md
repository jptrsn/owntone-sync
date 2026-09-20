# Intent: Embedded Music Player

## Description

Replace OwnTone Sync's broken notification-listener-based playback tracking with an embedded music player. The app will sync playlists from the OwnTone server, store music files on the user's device (via SAF), and provide playback with native media session support. Playback events (play, pause, skip) are tracked directly and synced back to the server.

## Business Context

- **Current state:** Playback tracking uses a NotificationListenerService that reads other apps' media notifications. This approach is fundamentally unreliable — it relies on Android's weakest surface area. The logcat revealed: duplicate callbacks from unregistered listeners, missing `STATE_SKIPPING_TO_NEXT` handler, and fuzzy metadata matching that can never work reliably.
- **User need:** The user syncs playlists from OwnTone to their device, expects to play them locally, and expects play/skip events to sync back to the server for accurate statistics.
- **Constraint:** Music files stay on external storage via SAF — they are NOT copied to app-private storage. The user owns the files and expects the same access level.
- **Constraint:** The user can still use any audio player, but OwnTone Sync's built-in player supersedes external tracking.
- **Architectural insight from Auxio reference:** Auxio uses ExoPlayer (Media3) with `MediaItem.Builder().setUri(uri)` to play directly from SAF/MediaStore URIs. No file copying needed. `audio_service` wraps this for background playback, notifications, and Bluetooth support.

## Completion Criteria

- [ ] User can play any synced track from Browse or Detail screens
- [ ] Playback continues when app is minimized (background playback)
- [ ] Notification shows current track with play/pause/next/previous controls
- [ ] Bluetooth/AVRCP controls (headset buttons, car stereo) work
- [ ] Shuffle mode: off, track, all
- [ ] Repeat mode: off, track, all
- [ ] Queue can be viewed and reordered
- [ ] Mini player bar appears at bottom of screen showing current track
- [ ] Full-screen now-playing screen with seek bar, album art, controls
- [ ] Play/skip events are tracked and synced back to OwnTone server during sync
- [ ] Playback queue rebuilds automatically when sync completes
- [ ] Flutter analyzer: 0 errors, 0 warnings
- [ ] Kotlin compiler: 0 errors

## Context

**Existing files to understand (read before implementing):**

| File | What to learn |
|---|---|
| `lib/data/models/track.dart` | Track model fields (id, title, artist, album, artworkUrl, path, etc.) |
| `lib/data/models/playlist.dart` | Playlist model fields |
| `lib/data/models/sync_history.dart` | History record model (plays/skips columns added recently) |
| `lib/data/repositories/local_database_repository.dart` | `getTracksForPlaylist()`, `getAllTracks()`, `getTracksByIds()` |
| `lib/data/repositories/owntone_api_repository.dart` | API methods: `getPlaylists()`, `getPlaylistTracks()`, `updateTrackStats()` |
| `lib/data/repositories/file_system_repository.dart` | `trackExists()`, `writeFile()`, `deleteTrack()` |
| `lib/data/database/database_helper.dart` | DB schema (synced_tracks, playlist_tracks, pending_events) |
| `lib/presentation/providers/sync_provider.dart` | Sync orchestration pattern (ChangeNotifier, MethodChannel) |
| `lib/presentation/providers/browse_provider.dart` | Browse state management |
| `lib/presentation/screens/sync_screen.dart` | Sync UI pattern (Progress indicator, buttons) |
| `lib/presentation/screens/playlist_detail_screen.dart` | Track list display pattern |
| `lib/presentation/screens/album_detail_screen.dart` | Album detail with artwork |
| `lib/presentation/screens/main_navigation_screen.dart` | Bottom nav structure |
| `lib/presentation/widgets/track_list_view.dart` | Track list widget (add play buttons) |
| `lib/presentation/widgets/album_list_view.dart` | Album list widget (add play buttons) |
| `lib/presentation/widgets/artist_list_view.dart` | Artist list widget (add play buttons) |
| `lib/main.dart` | App entry point (add player provider, audio service init) |
| `android/app/src/main/kotlin/dev/educoder/owntone_sync/BackgroundSyncWorker.kt` | Sync worker — add URI generation after download |
| `android/app/src/main/kotlin/dev/educoder/owntone_sync/MainActivity.kt` | Android entry (add audio service intent handling) |

**Reference files to read (from cloned Auxio):**

| File | What to learn |
|---|---|
| `/tmp/auxio-repo/app/src/main/java/org/oxycblt/auxio/playback/service/MediaSessionHolder.kt` | How ExoPlayer connects to MediaSession, builds MediaItem, handles playback state |
| `/tmp/auxio-repo/app/src/main/java/org/oxycblt/auxio/playback/service/PlaybackServiceFragment.kt` | Service lifecycle, notification management |
| `/tmp/auxio-repo/musikr/src/main/java/org/oxycblt/musikr/fs/FS.kt` | File/URI model for playback |

**Key insight:** `just_audio` + `audio_service` wraps ExoPlayer/Media3. The `just_audio` PR #1576 fix for `content://` URI handling is required — either wait for merge or apply a local patch. **Alternative (safer):** Store SAF `content://` URIs in the database and use `just_audio`'s `AndroidAudioSource` which natively supports `content://` URIs in its native layer. The Dart HTTP proxy only intercepts when `headers` or `userAgent` are set — for plain track playback, no headers are needed.

## Units

The units are organized in dependency order. Units marked [P] can build in parallel.

### Unit 1: Audio Service Setup

**Dependencies:** None

**Description:** Set up the Flutter + Android foundation for `just_audio` + `audio_service`. This creates the `AudioPlayer` singleton, configures the background audio service, and wires up the Android manifest/service declarations.

**Implementation:**

1. Add dependencies to `pubspec.yaml`: `just_audio`, `audio_service`, `just_audio_background`
2. Create `lib/presentation/services/audio_handler.dart` — extends `BaseAudioHandler with QueueAudioHandler`, wraps `just_audio`'s `AudioPlayer`
3. Update `lib/main.dart` — add `AudioService.init()` before `runApp()`, add `JustAudioBackground.init()`
4. Update `android/app/src/main/AndroidManifest.xml` — add `<service>` for `AudioService`, `<receiver>` for `MediaButtonReceiver`, permissions (`FOREGROUND_SERVICE_MEDIA_PLAYBACK`, `WAKE_LOCK`)
5. Verify background playback works: play a track, minimize app, verify notification appears with controls

**Constraints:**
- Use `audio_service`'s generated `AudioPlayerAudioHandler` — do not write raw Android service code
- Keep it minimal: just verify audio plays and notification appears with play/pause
- Do NOT add any UI, queue management, or database integration yet

### Unit 2: Database — Content URI Storage

**Dependencies:** Unit 1

**Description:** Extend the database schema and sync pipeline to store SAF `content://` URIs alongside each track. These URIs are the playback handles that `just_audio`/ExoPlayer can use.

**Implementation:**

1. Read `lib/data/database/database_helper.dart` — add `content_uri TEXT` column to `synced_tracks` table (version 3 migration)
2. Read `lib/data/models/sync_history.dart` — does NOT need changes (this unit is about track data, not history)
3. Read `lib/data/repositories/local_database_repository.dart` — add `contentUri` field to `SyncedTrack` model
4. Read `android/app/.../BackgroundSyncWorker.kt` — after downloading a track (line ~474-493), generate its SAF `content://` URI and store it in `synced_tracks.content_uri`
5. Read `android/app/.../FileOperations.kt` — use `DocumentFile.getUri()` to get the content URI for the downloaded file
6. Add `contentUri` getter/setter to `lib/data/models/track.dart` (the model used by `LocalDatabaseRepository`)
7. Verify: sync a playlist, check DB has `content_uri` values for downloaded tracks

**Constraints:**
- The `content_uri` column is nullable — existing tracks without a URI are still playable if the user manually selects the folder again
- Only store the URI generated at download time, do not attempt to scan/re-scan existing files
- Keep `database_helper.dart` migration simple: `ALTER TABLE` only, no data migration needed

### Unit 3: Player Provider + Background Sync Integration

**Dependencies:** Unit 1, Unit 2

**Description:** Create the `PlayerProvider` that loads the playback queue from the database and connects it to `audio_service`. Integrate with `BackgroundSyncWorker` so the queue rebuilds after each sync.

**Implementation:**

1. Read `lib/presentation/providers/sync_provider.dart` — follow the existing `ChangeNotifier` pattern
2. Create `lib/presentation/providers/player_provider.dart`:
   - `ChangeNotifier` subclass
   - `currentPlaylistId` — currently selected playlist for playback (or null for full library)
   - `isPlaying` — playback state
   - `shuffleMode` / `repeatMode` — playback modes
   - Methods: `loadPlaylist(int playlistId)`, `loadAllTracks()`, `playTrack(Track)`, `seek(Duration)`, `toggleShuffle()`, `toggleRepeat()`
   - Methods: `getQueueTrackCount()`, `getCurrentlyPlayingTrack()`
3. Read `lib/presentation/providers/browse_provider.dart` — for reference on how category browsing works
4. Update `BackgroundSyncWorker.kt` — after sync completes (around line 642-667), call a native channel method to notify Flutter that the queue should be rebuilt
5. In `PlayerProvider`, listen for sync completion via `SyncProvider.addListener()` and rebuild queue on sync success
6. Wire `PlayerProvider` into `main.dart` as a `ChangeNotifierProvider`

**Constraints:**
- Queue is built from `local_database_repository.getTracksForPlaylist(playlistId)` or `getAllTracks()`
- Each track's `content_uri` is used as the URI for `AudioServiceTrack` in `audio_service`
- Do NOT implement playback controls yet (Unit 4)

### Unit 4: Track List Integration (Play Buttons)

**Dependencies:** Unit 2, Unit 3

**Description:** Add play buttons to all existing track list widgets. Tapping a track adds it to the queue and starts playback.

**Implementation:**

1. Read `lib/presentation/widgets/track_list_view.dart` — wrap each `ListTile` in a `PlayButton` widget
2. Read `lib/presentation/widgets/playlist_list_view.dart` — add play button to each playlist row
3. Read `lib/presentation/widgets/artist_list_view.dart` — add play button to each artist row
4. Read `lib/presentation/widgets/album_list_view.dart` — add play button to each album row
5. Read `lib/presentation/screens/playlist_detail_screen.dart` — add play button to each track row
6. Read `lib/presentation/screens/album_detail_screen.dart` — add play button to each track row
7. Read `lib/presentation/screens/artist_detail_screen.dart` — add play button to each track row
8. Create `lib/presentation/widgets/play_button.dart` — a reusable `IconButton` that calls `playerProvider.playTrack(track)` on tap
9. Create `lib/presentation/widgets/playable_tile.dart` — wraps any track display with a `PlayButton`
10. Update all widget files to use `PlayButton` or `PlayableTile`

**Constraints:**
- Use `Consumer<PlayerProvider>` for accessing player state
- Play button icon should reflect current state: play (▶) if not playing, pause (⏸) if playing that track, next-track icon (⏭) if playing a different track
- Long-press on a track row shows a context menu: "Play", "Play Next", "Add to Queue", "View in Library"
- Do NOT create any new screens or layouts — just add icons to existing rows

### Unit 5: Full-Screen Player + Mini Player UI

**Dependencies:** Unit 3

**Description:** Build the full-screen now-playing view and the persistent mini player bar.

**Implementation:**

1. Read `lib/presentation/screens/album_detail_screen.dart` — for reference on how artwork display works (album art is already cached in app-private storage)
2. Create `lib/presentation/screens/player_screen.dart`:
   - Full-screen layout with: album art (large), track title/artist/album, seek bar with time labels, playback controls (shuffle/repeat/prev/play-pause/next)
   - Uses `Consumer<PlayerProvider>` + `StreamBuilder` for position updates
   - Seek bar uses `Slider` widget with `onChanged` for seeking
3. Create `lib/presentation/widgets/mini_player.dart`:
   - Compact bar at bottom of screen showing: album art (thumbnail), track title, artist, play/pause button
   - Tap opens `PlayerScreen`
   - Dismisses with swipe-down gesture
4. Update `lib/presentation/screens/main_navigation_screen.dart`:
   - Add `mini_player` below the `BottomNavigationBar` (or replace the body with a `Stack` + `NestedScrollView` pattern)
   - Adjust body height when mini player is visible
   - Add a small floating play indicator in bottom nav if music is playing
5. Update `lib/presentation/screens/browse_screen.dart` — wrap body in `Scaffold` with `bottomSheet` for mini player

**Constraints:**
- Album art uses `SyncedTrack.artworkPath` (already stored in app-private storage by the existing sync)
- Seek bar position is driven by `audio_service`'s `mediaItem` metadata and `PlaybackState` stream
- Do NOT implement volume slider — just the seek bar
- Mini player must not block the bottom navigation — place it above the nav bar, like Spotify's approach

### Unit 6: Event Tracking Integration

**Dependencies:** Unit 3

**Description:** Wire up explicit play/skip event tracking from the player back to the OwnTone server. This replaces the broken notification listener approach.

**Implementation:**

1. Read `lib/presentation/providers/player_provider.dart` — track explicit events:
   - When `playTrack(trackId)` is called AND the track reaches 90% completion → insert `PendingEvent(eventType: "play", trackId)`
   - When `skipToNext()` is called → insert `PendingEvent(eventType: "skip", trackId)` for the track that was skipped
   - Use `audio_service`'s `onSkipToNext()`, `onSkipToPrevious()`, `onPlay()`, `onPause()` callbacks
2. Read `lib/presentation/screens/server_config_screen.dart` — add toggle for "Track Playback Events" that controls `eventTrackingEnabled` in `SyncProvider`
3. Read `lib/data/repositories/local_database_repository.dart` — verify `insertEvent()` method exists and works correctly
4. Read `lib/data/models/sync_history.dart` — verify the `playsSynced`/`skipsSynced` columns (added in the recent spec)
5. Verify: enable event tracking, play a track for >90% → check `pending_events` table has a "play" event. Skip a track → check for a "skip" event.
6. Read `android/app/.../BackgroundSyncWorker.kt` — verify the `syncEvents()` function reads from `pending_events` and syncs back to the server (this already exists)

**Constraints:**
- Events are stored in `pending_events` table (already exists) with `event_type`, `track_id`, `timestamp`, `synced`
- Event sync happens during playlist sync (already implemented in `BackgroundSyncWorker.syncEvents()`)
- Do NOT modify the sync worker's event sync logic — it already works, it just needs the events to be created
- Use explicit callbacks from `audio_service` for events (not position extrapolation)

## Process

Each unit follows this pattern:
1. Read all referenced context files
2. Implement changes according to the description
3. Run `dart analyze` to verify Flutter code compiles
4. Run `flutter build apk --debug` to verify Android compiles
5. If errors: fix them, re-run verification
6. Output `COMPLETE` when all completion criteria for that unit are met
7. If blocked: document in `.agent/blockers.md`, output `BLOCKED`

## Constraints

- **Maximum 5 iterations per unit** before human review is required
- **Only modify files listed in Context** unless absolutely necessary
- **Do NOT use `audio_service`'s template code verbatim** — adapt it to the existing `provider` + `ChangeNotifier` architecture
- **Do NOT copy Auxio's full architecture** — use it as reference for specific patterns (MediaSession, URI handling), not as a blueprint to replicate
- **No external dependencies beyond**: `just_audio`, `audio_service`, `just_audio_background` (already in pubspec.yaml dependencies)
- **Do NOT modify the existing sync pipeline** except for adding URI storage (Unit 2)
- **Do NOT remove `MediaNotificationListener.kt`** — it can coexist with the built-in player
- **File paths are absolute** — use `/Users/oblivious/Documents/owntone_sync/` for all file references
