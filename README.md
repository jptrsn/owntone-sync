# OwnTone Sync

A Flutter-based Android application that syncs music playlists from an OwnTone (formerly forked-daapd) server to your local device storage. Designed for users who want offline access to their music library without running a full music player app.

## Overview

OwnTone Sync downloads and maintains a local copy of selected playlists from your OwnTone server. It creates M3U playlist files that work with any Android music player (like Auxio, Vinyl Music Player, etc.), giving you the flexibility to use your preferred player while maintaining automated sync.

### Key Features

- **Playlist Sync**: Select which playlists to sync and keep them updated
- **Scheduled Sync**: Configure automatic syncs with cron-like scheduling
  - Daily, weekday, weekend, or custom day-of-week schedules
  - Time-of-day configuration
  - Conditional sync (WiFi-only, charging-only)
- **Smart File Management**:
  - Only downloads new/missing tracks
  - Optional cleanup of orphaned files
  - Deduplication across playlists
- **Offline Mode**: View cached playlists and sync when connection restored
- **Progress Tracking**: Real-time sync progress with cancellation support
- **M3U Playlist Generation**: Creates standard playlist files for compatibility

## User Guide

### Initial Setup

1. **Grant Permissions**: On first launch, grant storage permissions to allow file downloads
2. **Configure Server**: Enter your OwnTone server URL (e.g., `http://192.168.1.100:3689`)
3. **Load Playlists**: Tap "Load Playlists" to fetch available playlists from your server
4. **Select Playlists**: Check the playlists you want to sync

### Manual Sync

1. Navigate to the **Sync** tab
2. Select playlists using checkboxes
3. Optionally enable "Delete orphaned files" to remove tracks no longer in any selected playlist
4. Tap **Sync** to start downloading

#### During sync:
- View current playlist and track being downloaded
- See overall progress (tracks completed / total tracks)
- Cancel anytime (current track will finish downloading first)

### Scheduled Sync

1. Navigate to **Sync** tab
2. Tap **Sync Schedule** in the Sync Options card
3. Enable automatic sync
4. Configure schedule days and time
5. Configure conditions:
   - **Only when charging**: Prevent battery drain
   - **Only on WiFi**: Avoid mobile data usage
6. Save schedule

The app checks hourly if it's time to sync. Syncs occur within 1 hour following the scheduled time.

### File Locations

Downloaded music is stored in:
```
/storage/emulated/0/Music/
├── tracks/           # Audio files (artist_album_trackid.ext)
└── playlists/        # M3U playlist files
```

### Using Synced Music

After syncing, open your preferred music player app and:
1. Scan for new media (most apps do this automatically)
2. Navigate to playlists
3. Look for your synced playlists by name

## Developer Guide

### Architecture

The app follows a three-layer architecture:

```
lib/
├── data/                                    # Data Layer
│   ├── models/                              # Data models (Playlist, Track, SyncSchedule, etc.)
│   ├── repositories/                        # Data access
│   │   ├── owntone_api_repository.dart      # OwnTone API client
│   │   ├── local_database_repository.dart   # SQLite operations
│   │   └── file_system_repository.dart      # File I/O
│   └── database/
│       └── database_helper.dart             # SQLite schema
├── domain/                                  # Business Logic Layer
│   └── services/
│       ├── sync_service.dart                # Sync orchestration
│       └── permissions_service.dart         # Android permissions
└── presentation/                            # UI Layer
    ├── screens/                             # Full-page views
    ├── widgets/                             # Reusable UI components
    └── providers/                           # State management (Provider pattern)
```

### Database Schema

**synced_playlists**
- Stores playlists selected for sync
- `path` is the stable identifier (survives server database resets)

**synced_tracks**
- Downloaded track metadata and local file paths
- No foreign key constraints to allow orphan detection

**playlist_tracks**
- Join table linking playlists to tracks
- Cascade delete on playlist removal
- Intentionally no FK to tracks (orphan detection)

**playlist_cache**
- Caches playlist metadata for offline viewing

**pending_events**
- Stores playback events to sync back to server
- Future feature: track play/skip counts

### Key Technologies

- **Flutter 3.5+**: Cross-platform UI framework
- **Provider**: State management
- **sqflite**: SQLite database
- **Dio**: HTTP client with download progress
- **workmanager**: Background task scheduling
- **path_provider**: File system access
- **permission_handler**: Android permissions

### OwnTone API

The app uses OwnTone's REST API and DAAP protocol:

**REST Endpoints:**
- `GET /api/library/playlists` - List playlists
- `GET /api/library/playlists/{id}/tracks` - List tracks in playlist
- `GET /api/library/tracks/{id}` - Get track metadata

**DAAP Downloads:**
- `GET /databases/1/items/{id}.dat` - Download track file
- Header: `Accept-Codecs: mpeg,alac,flac,wav`

File extensions determined from `Content-Type` header via HEAD request.

### Sync Logic

1. **Fetch server playlists** - Load current state from OwnTone
2. **Playlist recovery** - If playlist ID changed, recover by path
3. **Diff calculation** - Compare server vs local to find new/missing tracks
4. **Download tracks** - Only download if file doesn't exist locally
5. **Rebuild relationships** - Clear and rebuild playlist-track join table
6. **Generate M3U files** - Create playlist files with relative paths
7. **Cleanup** - Optionally delete orphaned tracks

### Background Sync

Background sync uses Android WorkManager:

1. **Registration** - When schedule enabled, register periodic task (hourly)
2. **Execution** - Background isolate runs every hour
3. **Schedule check** - `shouldSyncNow()` verifies time/day match
4. **Sync state** - Prevents concurrent runs and duplicate syncs
5. **Conditions** - WorkManager enforces WiFi/charging constraints

### Building

**Prerequisites:**
- Flutter SDK 3.5 or higher
- Android SDK (min SDK 26, target SDK 36)
- Android device or emulator

**Setup:**
```bash
flutter pub get
flutter run
```

### Testing

Manual testing checklist:
- [ ] Server configuration and validation
- [ ] Playlist loading (online and offline)
- [ ] Manual sync with progress tracking
- [ ] Sync cancellation
- [ ] Orphaned file deletion
- [ ] Schedule configuration
- [ ] Background sync execution
- [ ] Playlist recovery after server DB reset
- [ ] Permission handling

### Future Enhancements

**Browse Screen** (Planned)
- View downloaded music by playlist/artist/album/track
- Sort and filter options
- Track detail view with metadata

**History Screen** (Planned)
- Sync history log
- Statistics (tracks downloaded, storage used)
- Error tracking

**Event Sync** (Partially Implemented)
- Sync playback events back to OwnTone server
- Requires notification listener implementation

**iOS Support** (Unlikely)
- Would require adding music player functionality (blocking requirement)
- iOS doesn't allow third-party apps to generate playlists for Apple Music
- Repo author does not have access to appropriate hardware for testing

## Configuration

### Server Setup

Your OwnTone server must be:
- Accessible on your local network
- Running with remote access enabled
- Not requiring authentication (or using basic auth)

Example OwnTone configuration (`/etc/owntone.conf`):
```conf
general {
    websocket_port = 3688
    trusted_networks = { "any" }
}
```

### Storage Requirements

Storage usage depends on your library:
- Average MP3: ~5-10 MB per track
- Lossless FLAC: ~30-50 MB per track
- Ensure sufficient free space before syncing large playlists

### Network Requirements

- Local network access to OwnTone server

## Troubleshooting

**Playlists won't load**
- Verify server URL is correct
- Check server is running: `systemctl status owntone`
- Ensure device is on same network as server

**Sync fails immediately**
- Check storage permissions are granted
- Verify sufficient free space
- Check server logs for errors

**Background sync not working**
- Verify schedule is enabled and saved
- Check battery optimization isn't killing the app
- Review Android logs: `adb logcat | grep Background`

**Files not appearing in music player**
- Trigger media scan: Settings → Storage → Cached data → Clear
- Check file location: `/storage/emulated/0/Music/`
- Verify M3U files exist in `playlists/` directory

## License

[Add your license here]

## Contributing

[Add contribution guidelines if open source]

## Credits

Built with Flutter. Uses the OwnTone (forked-daapd) server project.