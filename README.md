# OwnTone Sync

Sync music from your [OwnTone](https://owntone.github.io/owntone-server/) server
to your Android device and play it offline — with your play counts, skip counts
and ratings synced back to the server.

Built for the case where your music lives on a server at home but you listen to
it on the train. Everything works with no network: the files, the artwork and
the player are all on the device, and statistics are queued and uploaded the
next time you sync.

## Install

Download the APK for your device from the
[latest release](https://github.com/jptrsn/owntone-sync/releases/latest), or add
this repository to [Obtainium](https://github.com/ImranR98/Obtainium) for
automatic updates:

```
https://github.com/jptrsn/owntone-sync
```

Most modern phones need `arm64-v8a`.

---

## User Guide

### First run

1. **Grant storage access.** Open the drawer → **Storage**, and pick the folder
   where music should be saved. Android's folder picker grants the app access to
   that folder only.
2. **Point it at your server.** Drawer → **Server**, and enter your OwnTone URL,
   for example `http://192.168.1.100:3689`. The device must be on the same
   network as the server to sync.
3. **Choose playlists.** Drawer → **Sync**, load the playlists from your server
   and tick the ones you want on the device.
4. **Sync.** Tap **Sync** and wait. Your library appears when it finishes — no
   restart needed.

### Your library

The app opens on your library, with tabs for **Playlists**, **Artists**,
**Albums** and **Tracks**. Each tab remembers its own sort order between
sessions, and the search icon in the toolbar searches titles, artists, albums
and playlist names.

Only music synced from OwnTone appears here. Other audio on your device is not
indexed.

### Playing music

**Tap any track to play it in context** — the rest of the list becomes the
queue, starting from the track you tapped. Tapping a track in an album plays the
album; tapping one in search results plays the results.

A player bar sits at the bottom whenever something is loaded. Tap or swipe it up
for the full **Now Playing** view: artwork, a seek bar, shuffle and repeat, and
a queue you can reorder by dragging or trim by swiping rows away.

Playlists, albums and artists each have **Play** and **Shuffle** buttons on
their detail screen. Long-press any row, or use its ⋮ menu, for **Play next**
and **Add to queue**.

Playback continues when the app is in the background or the screen is off, and
responds to lock-screen, notification and Bluetooth controls.

### Ratings

On the **Now Playing** screen, tap the artwork to reveal a five-star rating
strip, then press and drag sideways to set it — half stars, released to save.
Tracks can also be rated from the ⋮ menu on any row.

Ratings sync in both directions on the next sync. **If a rating changed on the
server since your last sync, the server's value wins.**

### Play and skip counts

The app records these itself while you listen and uploads them on the next sync.
A track counts as *played* once you have listened to 90% of it, or four minutes,
whichever comes first. Only deliberately moving on early — Next, Previous, or
picking another track — counts as a *skip*. Letting a track finish never counts
as a skip.

> **Upgrading from 0.1.x?** Earlier versions watched other music players'
> notifications to guess at this, which needed a notification-access permission
> and was never reliable. That is gone. The built-in player measures playback
> directly, and the permission is no longer requested.

### Album artwork

Artwork is read from the music files' own tags where present, and fetched from
your server where not. Either way it is cached on the device during sync, so it
displays offline. Tracks with no artwork in either place show a placeholder.

### Scheduled sync

Drawer → **Schedule** to sync automatically:

1. Enable automatic sync and pick the days and time.
2. Optionally require **charging** or **WiFi only**.
3. **Disable battery optimisation for the app when prompted.** Android will
   otherwise delay or skip background work, and syncs may not run on time.

A sync that fails — server down, no WiFi — does not stop the schedule; the next
one still runs.

### Sync status and history

The toolbar icon shows sync progress and turns into an error badge if the last
sync failed. Drawer → **History** lists past syncs with their duration, how many
playlists and tracks were handled, how many play and skip events were uploaded,
and any errors. A sync that could not reach your server is recorded as a
failure, and one where only some playlists failed is flagged as partial.

### Where files go

```
/storage/emulated/0/Music/      (or the folder you selected)
├── tracks/       Audio files
└── playlists/    M3U playlist files
```

Album artwork is cached in the app's private storage and removed if you
uninstall the app. Your music files are not touched — they are yours, and the
app only writes new ones.

### Using the files in another player

The synced files are normal audio files with normal M3U playlists, so any other
music player can read them. Note that play counts, skips and ratings from other
players are **not** tracked — only playback inside this app is sent back to
OwnTone.

---

## Configuration

### Server

Your OwnTone server must be reachable on the local network with its HTTP API
enabled, and must not require authentication beyond basic auth.

### Storage

Roughly 5–10 MB per MP3 and 30–50 MB per lossless track. Check free space before
syncing large playlists.

---

## Troubleshooting

**Playlists won't load**
Check the server URL, confirm the server is running (`systemctl status owntone`),
and make sure the device is on the same network.

**Sync fails immediately**
Check that folder access was granted (drawer → Storage), that there is free
space, and that the server URL is right.

**Scheduled syncs don't run**
Confirm the schedule is enabled and saved, and that battery optimisation is
disabled for the app — this is the usual cause. Note the schedule needs the
conditions you set to be met: "WiFi only" will not sync on mobile data.

**A track is skipped during playback**
Its file is missing or unreadable — usually deleted outside the app. A notice
names the track and playback continues. Re-sync to restore it.

**No album artwork**
Not every track has artwork, in its tags or on the server. If none appears at
all, confirm a sync has completed since updating — artwork is resolved during
sync, not on demand.

**Ratings not reaching the server**
Ratings upload on the next sync, not immediately. If one disappeared, the server
had a different value and won the conflict.

**Files not appearing in another music player**
Trigger a media scan, and check the files are under your chosen folder with M3U
files in `playlists/`.

---

## Developer Guide

Flutter app with an Android native layer: Kotlin handles background sync,
Storage Access Framework file operations and WorkManager scheduling, while
playback runs on `just_audio` behind `audio_service`.

```
lib/
├── data/            Models, repositories, SQLite schema
├── domain/          Permissions
└── presentation/
    ├── controllers/ PlaybackController — the single playback facade
    ├── services/    Audio handler, stats recorder, URI resolver
    ├── screens/     Library, Now Playing, Sync, History, Settings
    ├── widgets/     Rows, mini player, queue sheet, star rating
    └── providers/   Sync and browse state

android/app/src/main/kotlin/dev/educoder/owntone_sync/
├── MainActivity.kt            Method channels, permissions, SAF URIs
├── BackgroundSyncWorker.kt    Sync, event upload, rating and artwork resolution
├── OwnToneApiClient.kt        OwnTone HTTP API
├── DatabaseHelper.kt          SQLite, Kotlin side
├── FileOperations.kt          SAF I/O, artwork extraction and cache
└── SyncProgressBroadcaster.kt Progress notifications and EventChannel
```

The SQLite schema is owned by Dart (`database_helper.dart`, currently version 8)
and read by both sides; the Kotlin helper does not migrate, so schema changes
must go through the Dart migration chain.

### Building

```bash
flutter pub get
flutter run                  # debug
flutter build apk --release  # release
./release.sh                 # tag, build, publish a GitHub release
```

### Before changing anything

`.agent/` holds the working documentation for this codebase and is worth reading
before any non-trivial change:

- **`invariants.md`** — facts established the hard way, each with what breaks if
  it is undone. Start here. Several describe subtleties that look like tidy-up
  opportunities and are not.
- **`player-ux-spec.md`** — what the app is meant to do, as user stories with
  acceptance criteria.
- **`player-refactor-plan.md`** — architecture and the defect inventory behind
  it.
- **`verification-protocol.md`** — what counts as evidence that something works.
- **`backlog.md`** and **`blockers.md`** — known gaps and open defects.

---

## License

GNU General Public License v3.0 — see [LICENSE](LICENSE).
