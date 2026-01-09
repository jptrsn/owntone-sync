## User Guide

### Initial Setup

1. **Grant Permissions**: On first launch, grant storage permissions and select your Music folder when prompted
2. **Configure Server**: Enter your OwnTone server URL (e.g., `http://192.168.1.100:3689`)
3. **Load Playlists**: Tap "Load Playlists" to fetch available playlists from your server
4. **Select Playlists**: Check the playlists you want to sync

### Manual Sync

1. Navigate to the **Sync** tab
2. Select playlists using checkboxes
3. Optionally enable "Delete orphaned files" to remove tracks no longer in any selected playlist
4. Tap **Sync** to start downloading

During sync, you'll see:
- Current playlist and track being processed
- Overall progress (tracks completed / total tracks)
- Cancel option (current track will finish downloading first)

### Scheduled Sync

1. Navigate to **Sync** tab
2. Tap **Sync Schedule** in the Sync Options card
3. Enable automatic sync
4. Configure schedule days and time
5. Configure conditions:
   - **Only when charging**: Prevent battery drain
   - **Only on WiFi**: Avoid mobile data usage
6. Save schedule

Background syncs run at the scheduled time you set (e.g., 2:00 AM daily). After each sync completes, the app automatically schedules the next occurrence.

**Note on battery optimization**: Android may delay or skip background syncs if battery optimization is enabled for the app. The app will prompt you to disable this when setting up scheduled syncs.

### Event Tracking

The app can track your music playback from other Android music players and sync play/skip statistics back to your OwnTone server.

To enable:
1. Navigate to **Sync** tab, then **Server Configuration**
2. Enable "Track Playback Events"
3. Grant notification listener permission when prompted

The app uses Android's NotificationListener to detect when tracks are played or skipped in music players like PowerAmp, Auxio, Vinyl Music Player, etc. Events are synced to your OwnTone server during the next sync.

### Browse

The **Browse** tab lets you view your synced music library by:
- Playlists
- Artists
- Albums
- Tracks

**Note**: This shows only the music synced from OwnTone, not all music files on your device. Other music players may have additional tracks that weren't synced by this app.

### History

The **History** tab shows a log of past sync operations including:
- Sync timestamp and duration
- Number of playlists synced
- Tracks downloaded and deleted
- Success/failure status
- Error messages (if any)

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
│   │   └── file_system_repository.dart      # File I/O coordination
│   └── database/
│       └── database_helper.dart             # SQLite schema
├── domain/                                  # Business Logic Layer
│   └── services/
│       └── permissions_service.dart         # Android permissions
└── presentation/                            # UI Layer
    ├── screens/                             # Full-page views
    ├── widgets/                             # Reusable UI components
    └── providers/                           # State management (Provider pattern)
```

**Android (Kotlin) components:**
```
android/app/src/main/kotlin/dev/educoder/owntone_sync/
├── MainActivity.kt                    # Main activity, handles permissions and method channels
├── BackgroundSyncWorker.kt            # WorkManager worker for background sync
├── MediaNotificationListener.kt       # NotificationListener for tracking playback events
├── OwnToneApiClient.kt               # HTTP client for OwnTone API
├── DatabaseHelper.kt                  # SQLite operations (Kotlin side)
├── FileOperations.kt                  # SAF file operations
└── SyncProgressBroadcaster.kt        # Progress notifications and EventChannel bridge
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
- Stores playback events (play/skip) to sync back to server
- Includes retry_count for failed sync attempts (max 5 retries)

**sync_history**
- Records of past sync operations with statistics

**sync_history_playlists**
- Details of which playlists were included in each sync

### Key Technologies

- **Flutter 3.5+**: Cross-platform UI framework
- **Provider**: State management
- **sqflite**: SQLite database
- **Dio**: HTTP client with download progress
- **workmanager**: Background task scheduling (Android WorkManager wrapper)
- **path_provider**: File system access
- **permission_handler**: Android permissions
- **Storage Access Framework (SAF)**: Android's secure file access system

### OwnTone API

The app uses OwnTone's REST API and DAAP protocol:

**REST Endpoints:**
- `GET /api/library/playlists` - List playlists
- `GET /api/library/playlists/{id}/tracks` - List tracks in playlist
- `GET /api/library/tracks/{id}` - Get track metadata
- `PUT /api/library/tracks/{id}` - Update track statistics (play count, skip count)

**DAAP Downloads:**
- `GET /databases/1/items/{id}.dat` - Download track file
- Header: `Accept-Codecs: mpeg,alac,flac,wav`

File extensions determined from `Content-Type` header via HEAD request.

### Sync Logic

**Event Sync (runs first, if enabled):**
1. Fetch unsynced events from local database
2. Group events by track_id
3. For each track, fetch current stats from server
4. Accumulate new play/skip counts with server counts
5. Update timestamps (use most recent)
6. Send PUT request to update server
7. Delete successfully synced events
8. Retry failed events (up to 5 times, then delete)

**Playlist Sync:**
1. **Fetch server playlists** - Load current state from OwnTone
2. **Playlist recovery** - If playlist ID changed, recover by path
3. **Diff calculation** - Compare server vs local to find new/missing tracks
4. **Download tracks** - Only download if file doesn't exist locally
5. **Rebuild relationships** - Clear and rebuild playlist-track join table
6. **Generate M3U files** - Create playlist files with relative paths
7. **Cleanup** - Optionally delete orphaned tracks

### Background Sync

Background sync uses Android WorkManager:

1. **Registration** - When schedule enabled, calculate delay until next scheduled time and register one-time work request
2. **Execution** - Work runs at scheduled time if conditions met (WiFi, charging)
3. **Event sync** - If enabled, sync playback events first
4. **Playlist sync** - Download new tracks, update relationships
5. **Progress broadcasting** - Via foreground notification and EventChannel to Flutter
6. **Schedule next** - After completion, calculate and schedule tomorrow's sync
7. **History logging** - Record sync results in database

**WorkManager ensures:**
- Respects battery optimization settings
- Waits for required conditions (WiFi, charging)
- Survives app restarts and device reboots
- Provides foreground notification during sync

### Event Tracking

Event tracking uses Android's NotificationListenerService:

1. **Notification monitoring** - Listen for media notifications from music players
2. **MediaController extraction** - Get playback state from notification's MediaSession
3. **Position tracking** - Track last known position and timestamp for extrapolation
4. **State change detection**:
   - **Track change**: Extrapolate final position from last update, determine play vs skip
   - **Pause**: Update position and timestamp
   - **Stop**: Process track end with extrapolated position
5. **Event classification**:
   - **Play**: Track reached ≥90% completion
   - **Skip**: Track played ≥3 seconds but <90% completion
   - **Ignore**: Track played <3 seconds
6. **Track matching** - Fuzzy match against local database (title, artist, duration ±5s)
7. **Event storage** - Store in pending_events table for next sync

### Storage Access Framework (SAF)

All music file operations go through Android's SAF:

- User grants access to Music folder via system picker
- App stores persistent URI permission
- File operations use DocumentFile API
- Artwork stored in app-private storage (no SAF needed)
- M3U playlists use relative paths for compatibility

### Progress Communication

Sync progress flows from Kotlin to Flutter:

1. **BackgroundSyncWorker** updates progress
2. **SyncProgressBroadcaster** creates foreground notification
3. **EventChannel** broadcasts progress to Flutter
4. **SyncProvider** receives updates via stream
5. **UI** displays progress in real-time

### Building

**Prerequisites:**
- Flutter SDK 3.5 or higher
- Android SDK (min SDK 29, target SDK 34)
- Android device or emulator

**Setup:**
```bash
flutter pub get
flutter run
```

### Testing

Manual testing checklist:
- Server configuration and validation
- Playlist loading (online and offline)
- Manual sync with progress tracking
- Sync cancellation
- Orphaned file deletion
- Schedule configuration
- Background sync execution (check via notification)
- Playlist recovery after server DB reset
- Permission handling (storage, notification listener, battery optimization)
- Event tracking (play/skip detection in various music players)
- Event sync to server

## Configuration

### Server Setup

Your OwnTone server must be:
- Accessible on your local network
- Running with remote access enabled
- Not requiring authentication (or using basic auth)

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
- Check battery optimization is disabled for the app
- Review Android logs: `adb logcat | grep BackgroundSyncWorker`

**Files not appearing in music player**
- Trigger media scan: Settings → Storage → Cached data → Clear
- Check file location: `/storage/emulated/0/Music/`
- Verify M3U files exist in `playlists/` directory

**Event tracking not working**
- Verify notification listener permission is granted
- Check the setting is enabled in Server Configuration
- Review logs: `adb logcat | grep MediaNotificationListener`
- Some music players may not expose MediaSession properly