# OwnTone Sync — Player Refactor Plan

**Companion to:** `.agent/player-ux-spec.md` (what and why — read it first)
**This document:** current-state defects, target architecture, and the ordered
path from one to the other.
**Supersedes:** the original `player-spec.md` and `play-music-plan.md`, deleted
2026-10-02 (recoverable from git history)

---

## 1. Why the current branch does not work

The `audio_player` branch added ~2,600 lines across 29 files. The UI exists, the
dependencies are installed, the Android service is declared. It still does not
behave like a music player, and the reason is a single architectural mistake with
a long tail of consequences.

### 1.1 The root cause: two queues, and the player has neither

`PlayerProvider` holds `List<SyncedTrack> _queue`
([player_provider.dart:19](../lib/presentation/providers/player_provider.dart#L19)).
`OwnToneAudioHandler` wraps a `just_audio` `AudioPlayer` that is only ever handed
**one URL at a time** via `setUrl`
([audio_handler.dart:71](../lib/presentation/services/audio_handler.dart#L71)),
and `audio_service`'s `queue` subject is overwritten with a single-item list on
every play ([audio_handler.dart:69](../lib/presentation/services/audio_handler.dart#L69)).

The player therefore has no concept of "next". Everything that depends on the
player knowing its queue is broken:

| Symptom | Mechanism |
|---|---|
| Playback stops after one track | `processingStateStream == completed` calls `skipToNext()` ([audio_handler.dart:11-15](../lib/presentation/services/audio_handler.dart#L11-L15)); `QueueHandler.skipToNext` reads `queue.value`, finds one item, and no-ops. |
| Notification / Bluetooth next and previous do nothing | Same path. |
| "Play next" and "Add to queue" do nothing audible | They mutate `_queue` only ([player_provider.dart:197-215](../lib/presentation/providers/player_provider.dart#L197-L215)); the player never sees it. |
| Shuffle and repeat buttons do nothing | `toggleShuffle`/`toggleRepeat` flip booleans and call `notifyListeners()` ([player_provider.dart:230-238](../lib/presentation/providers/player_provider.dart#L230-L238)). Neither value is ever read by anything that plays audio. |
| Tapping a track destroys the album context | `playTrack` sets `_queue = [track]` ([player_provider.dart:141](../lib/presentation/providers/player_provider.dart#L141)). |
| Shuffling a collection is destructive | `playPlaylist(shuffle: true)` permanently shuffles the list ([player_provider.dart:75](../lib/presentation/providers/player_provider.dart#L75)); the original order cannot be restored. |
| Only the first track of a collection ever plays | `playPlaylist`, `playAlbum`, `playArtist`, `playAllTracks` all call `_playFirstTrack()`, which pushes exactly one `MediaItem` ([player_provider.dart:152-178](../lib/presentation/providers/player_provider.dart#L152-L178)). |

**This cannot be patched incrementally.** The handler and the provider must be
rebuilt around the player owning a real, multi-item audio source.

### 1.2 Statistics are recorded backwards

This matters more than the UI bugs, because it writes wrong data to the server.

- **Natural completion is recorded as a skip.** Completion calls `skipToNext()`
  ([audio_handler.dart:13](../lib/presentation/services/audio_handler.dart#L13)),
  which calls `_trackSkipEvent()`
  ([audio_handler.dart:83](../lib/presentation/services/audio_handler.dart#L83)).
  Finishing a song you love tells OwnTone you skipped it.
- **Plays are only recorded when you seek.** `_checkPlayCompletion()` has exactly
  one caller: `seek()`
  ([player_provider.dart:221](../lib/presentation/providers/player_provider.dart#L221)).
  Listening to a track end-to-end records nothing; dragging the slider to the end
  records a play.
- **Skip events name the wrong track.** `_trackSkipEvent` reads
  `mediaItem.value` *after* `super.skipToNext()` has already run
  ([audio_handler.dart:82-101](../lib/presentation/services/audio_handler.dart#L82-L101)),
  so it attributes the skip to whichever item is current at that moment.
- **No threshold logic and no de-duplication.** A repeat-one loop or a re-listen
  can write unbounded play events.

### 1.3 Position and duration are wrong

`player_screen.dart` assigns the **buffered position** to `_duration`
([player_screen.dart:38](../lib/presentation/screens/player_screen.dart#L38)), so
the seek bar's maximum is not the track length. Position is only sampled when a
`playbackState` event fires rather than from a continuous position stream, so the
thumb jumps rather than moves. `_buildSeekControl` also seeks on every `onChanged`
tick *and* on `onChangeEnd`
([player_screen.dart:~305](../lib/presentation/screens/player_screen.dart)),
which fights the player during a drag.

### 1.4 Provider wiring is duplicated

- `PlayerProvider` constructs its **own** `SyncProvider` when none is injected
  ([player_provider.dart:26](../lib/presentation/providers/player_provider.dart#L26)),
  and `main.dart` injects none
  ([main.dart:37](../lib/main.dart#L37)). There are two `SyncProvider` instances:
  one doing the syncing, and a second one that `PlayerProvider` listens to and
  which never syncs. Both initialise DB handles and shared prefs.
- `BrowseScreen` constructs a `BrowseProvider` in `initState`
  ([browse_screen.dart:25](../lib/presentation/screens/browse_screen.dart#L25))
  rather than taking it from the tree, so nothing else can trigger a refresh
  after sync.
- `PlayerProvider` reaches into `main.dart` for a global mutable
  `AudioHandler? audioHandler` and force-unwraps it
  ([player_provider.dart:28](../lib/presentation/providers/player_provider.dart#L28)),
  as do the widgets. A global nullable singleton is not testable and will crash
  if construction order ever changes.

### 1.5 Content URI resolution is expensive and not cached

`buildContentUri` walks the SAF tree with `DocumentFile.findFile` per path
segment, per track
([MainActivity.kt:300-320](../android/app/src/main/kotlin/dev/educoder/owntone_sync/MainActivity.kt#L300-L320)).
`findFile` is O(directory size) — it enumerates. For a 500-track queue this is
hundreds of enumerations over a method channel. Worse, `_resolveContentUri`
([player_provider.dart:52](../lib/presentation/providers/player_provider.dart#L52))
never writes the resolved URI back to `synced_tracks.content_uri`, so the cost is
paid again on every play.

The column is also inconsistently defaulted: `CREATE TABLE` gives it
`DEFAULT ''` ([database_helper.dart:72](../lib/data/database/database_helper.dart#L72))
while the v4 migration adds it nullable
([database_helper.dart:173](../lib/data/database/database_helper.dart#L173)), so
consumers must handle both `''` and `NULL`. There is no invalidation path when a
re-download changes a document ID.

### 1.6 Shell and layout problems

- The mini player is `Positioned(bottom: 56)` inside a `Stack` over the body
  ([main_navigation_screen.dart:56-61](../lib/presentation/screens/main_navigation_screen.dart#L56-L61)).
  It floats over content and does not inset it, so the last row of every list is
  covered and unreachable.
- `PlayableTile` stacks a `PlayButton` over the tile with `Positioned(right: 0)`
  ([play_button.dart:106-120](../lib/presentation/widgets/play_button.dart#L106-L120)),
  overlapping the tile's own trailing widget and its tap target.
- `PlayButton` renders a pause icon when its track is current but still calls
  `playTrack` on press
  ([play_button.dart:30-36](../lib/presentation/widgets/play_button.dart#L30-L36)),
  so "pause" restarts the track.
- `BrowseScreen` returns a `Scaffold` nested inside `MainNavigationScreen`'s
  `Scaffold` ([browse_screen.dart:53](../lib/presentation/screens/browse_screen.dart#L53)).
- Navigation opens on Sync and the app bar reads "OwnTone Sync"
  ([main_navigation_screen.dart:21,30](../lib/presentation/screens/main_navigation_screen.dart#L21-L30)).

### 1.7 Runtime crash: missing asset

`assets/images/placeholder_album_art.png` is referenced three times (mini player
and Now Playing) but does not exist on disk, and **`pubspec.yaml` declares no
`assets:` section at all**. Every artwork fallback path throws.

### 1.8 Dependency problems

- `just_audio_background` is declared in `pubspec.yaml` but never imported
  anywhere in `lib/`. It is mutually exclusive with `audio_service` — having both
  registered is a known source of duplicate-notification and session conflicts.
  **Remove it.**
- `just_audio: ^0.9.36` is old. Current `just_audio` (0.10.x) has the modern
  `setAudioSources` API, better `content://` handling, and `AudioSource.uri`
  tagging. Upgrade deliberately as part of the core rewrite, not incidentally.
- `rxdart` is present transitively but not a direct dependency; the standard
  seek-bar and state-combination recipes need it. **Add it explicitly.**

### 1.9 Error handling is silence

Ten `catch` blocks in the player path swallow the exception with an empty body or
a `kDebugMode` print. `_playFirstTrack` returns early when a URI is missing but
leaves `_isPlaying = true`
([player_provider.dart:157-174](../lib/presentation/providers/player_provider.dart#L157-L174)),
so the UI claims to be playing silence. Nothing is ever surfaced to the user.

---

## 2. Target architecture

### 2.1 Layering

```
┌──────────────────────────────────────────────────────────────┐
│ UI          LibraryScreen · detail screens · Drawer          │
│             MiniPlayer · NowPlayingSheet · QueueSheet        │
│             (all read streams; none hold playback state)     │
└───────────────────────────┬──────────────────────────────────┘
                            │ streams + intents
┌───────────────────────────┴──────────────────────────────────┐
│ PlaybackController  (thin Dart facade over the handler)      │
│   playCollection(origin, tracks, startIndex)                 │
│   toggleShuffle() · cycleRepeat() · playNext() · enqueue()   │
│   exposes: mediaItem · playbackState · queue · positionData  │
│            queueOrigin · shuffleMode · repeatMode            │
└───────────────────────────┬──────────────────────────────────┘
┌───────────────────────────┴──────────────────────────────────┐
│ OwnToneAudioHandler  (BaseAudioHandler + QueueHandler        │
│                       + SeekHandler)                         │
│   OWNS the queue as a single ConcatenatingAudioSource        │
│   MediaItem lives as the `tag` on each AudioSource           │
│   playbackEventStream ──► playbackState                      │
│   sequenceStateStream ──► mediaItem, queue                   │
│   delegates play/skip decisions to PlaybackStatsRecorder     │
└──────┬─────────────────────────────┬─────────────────────────┘
       │                             │
┌──────┴────────────────┐  ┌─────────┴──────────────────────┐
│ TrackUriResolver      │  │ PlaybackStatsRecorder          │
│ content:// resolution │  │ threshold logic, de-dup,       │
│ + cache-back to DB    │  │ writes pending_events          │
└──────┬────────────────┘  └─────────┬──────────────────────┘
       └───────────┬─────────────────┘
┌──────────────────┴───────────────────────────────────────────┐
│ Data  LocalDatabaseRepository · sqflite · SAF via Kotlin      │
│       (unchanged except additive)                             │
└──────────────────────────────────────────────────────────────┘
```

### 2.2 The rules that keep it correct

1. **The player owns the queue.** One `ConcatenatingAudioSource` (or
   `setAudioSources`) holds every track. `audio_service`'s `queue` subject is a
   *projection* of it, never an independent list.
2. **`MediaItem` rides as the `AudioSource` tag.** This is how `sequenceStateStream`
   can tell the UI what is playing without any Dart-side index bookkeeping.
3. **Shuffle is the player's.** `setShuffleModeEnabled` + `shuffle()`; read the
   effective order from `shuffleIndices`. Never pre-shuffle the source list.
4. **Repeat is the player's.** `setLoopMode(LoopMode.off | one | all)`.
5. **No global mutable singleton.** The handler is provided through the widget
   tree (`Provider<PlaybackController>`), constructed once in `main`.
6. **UI never stores playback state.** No `setState` copies of position, no
   `ChangeNotifier` mirrors of `isPlaying`. `StreamBuilder` over the controller's
   streams, always.
7. **Every swallowed error becomes a surfaced one.** Playback failures emit an
   error state the UI can render.

### 2.3 Key APIs to build against

| Concern | API |
|---|---|
| Queue | `ConcatenatingAudioSource` / `AudioPlayer.setAudioSources` |
| Track source | `AudioSource.uri(Uri.parse(contentUri), tag: mediaItem)` |
| Current item | `AudioPlayer.sequenceStateStream` → `currentSource.tag as MediaItem` |
| Playback state | `AudioPlayer.playbackEventStream` mapped into `playbackState` |
| Position | `AudioService.position` combined with duration via `rxdart` |
| Shuffle | `setShuffleModeEnabled`, `shuffle()`, `shuffleIndices` |
| Repeat | `setLoopMode` |
| Notification layout | `AudioServiceConfig.androidCompactActionIndices` |

### 2.4 New/changed data

| Change | Table / file | Notes |
|---|---|---|
| Normalise `content_uri` | `synced_tracks` | Single migration to make the column consistently nullable; treat `''` as null in code. |
| Cache resolved URIs | `synced_tracks.content_uri` | `TrackUriResolver` writes back on first resolution. Invalidate on re-download. |
| Persist playback state | new `playback_state` table (single row) or `SharedPreferences` | queue track IDs, origin, current index, position, shuffle, repeat. Prefer a table — queues can be long. |
| Play/skip events | `pending_events` (existing) | Unchanged schema. Only the writer changes. |

---

## 3. The path from here to there

Eight phases. Each is independently reviewable and ends with the app building and
running. Phases 1–3 are the load-bearing ones; do not begin phase 4 until phase 3
passes its verification on a device.

---

### Phase 0 — Clear the ground

**Goal:** remove what is known-dead or known-broken so later phases are not
working around it.

1. Remove `just_audio_background` from `pubspec.yaml` (unused, conflicts with `audio_service`).
2. Add `rxdart` as a direct dependency.
3. Upgrade `just_audio` and `audio_service` to current majors; record the resolved versions.
4. Create `assets/images/placeholder_album_art.png` and declare an `assets:` section in `pubspec.yaml`.
5. Delete `MediaNotificationListener.kt`, its `<service>` block and the
   `BIND_NOTIFICATION_LISTENER_SERVICE` permission from `AndroidManifest.xml`,
   the notification-listener branches in `MainActivity.kt`, and
   `eventTrackingEnabled` / `checkEventTrackingPermission` /
   `requestEventTrackingPermission` from `SyncProvider` and
   `ServerConfigScreen`. Leave `pending_events` and the sync worker's upload path
   completely alone.

**Verify:** `flutter analyze` clean, `flutter build apk --debug` succeeds, app
launches, sync still works end-to-end, no notification-listener permission prompt
appears anywhere.

**Status: COMPLETE.** Left one defect behind, addressed in Phase 0.5.

---

### Phase 0.5 — Un-gate the event upload path

**Goal:** repair a regression introduced by Phase 0. Small, surgical, one file.

Phase 0 removed the event-tracking toggle and all its Dart plumbing, but
`BackgroundSyncWorker.kt` still gates the event upload on a SharedPreferences
value that nothing writes any more:

```kotlin
// ~line 314
eventTrackingEnabled = prefs.getBoolean("flutter.event_tracking_enabled", false)
if (eventTrackingEnabled) { eventSyncResult = syncEvents(...) }
```

Nothing can ever set that key again, so the stored value is frozen permanently.
Queued play/skip events accumulate in `pending_events` and never upload — not
just until Phase 3, but forever. `plays_synced` / `skips_synced` stay `NULL`, and
the History screen shows nothing.

**Delete the gate. Do not re-default it.**

`getBoolean(key, default)` returns the *stored* value whenever the key exists,
and the pre-Phase-0 Dart code persisted it with
`setBool('event_tracking_enabled', …)`. Any user who turned the toggle on and
then off has `false` on disk. Changing the default from `false` to `true` would
fix only fresh installs and users who never touched the toggle, and would leave
everyone else permanently broken with no UI left to recover. The default is not
where the problem lives.

1. Remove the `eventTrackingEnabled` variable (~line 279) and the
   `prefs.getBoolean` read (~line 314).
2. Call `syncEvents()` unconditionally. It already early-returns when
   `pending_events` is empty ([~line 879](../android/app/src/main/kotlin/dev/educoder/owntone_sync/BackgroundSyncWorker.kt#L879)),
   so there is no cost when there is nothing to send.
3. Make `playsSynced` / `skipsSynced` unconditional at all three write sites
   (~lines 70-71, 690-691, 755-756) and drop the `eventTrackingEnabled`
   parameter from `handleInterruption` (~line 55) and its call site (~line 732).
4. Leave the orphaned `flutter.event_tracking_enabled` key on disk. Once nothing
   reads it, it is inert; deleting it is migration risk for no gain.

**Constraints:** one file. This removes a condition in front of an existing,
working upload path — it does not change download or upload semantics, and it is
within the "additive sync-side changes" allowance in §5.

**Verify:**
- `flutter analyze` clean; `flutter build apk --debug` succeeds.
- Insert a synthetic row and confirm it uploads and is cleared:
  ```
  adb -s emulator-5554 shell "run-as dev.educoder.owntone_sync sqlite3 \
    databases/owntone_sync.db \"INSERT INTO pending_events \
    (track_id,event_type,timestamp,synced,retry_count) \
    VALUES (<real_track_id>,'play',$(date +%s000),0,0);\""
  ```
  Run a sync → the row is gone from `pending_events`, and the newest
  `sync_history` row has non-null `plays_synced`.
- A sync with nothing queued still succeeds and writes `0`, not `NULL`.

**Note for Phase 7:** history rows now record `0` rather than `NULL` when a sync
uploads nothing. Confirm the History screen renders that as "no events" rather
than a bare "0 plays" — part of story D3.

---

### Phase 1 — Rebuild the audio handler

**Goal:** a correct, queue-owning handler. **No UI changes in this phase.**

Rewrite `lib/presentation/services/audio_handler.dart` from scratch against the
rules in §2.2. It must:

- Build a `ConcatenatingAudioSource` from a list of `MediaItem`s, each carried as
  the tag of an `AudioSource.uri`.
- Pipe `playbackEventStream` into `playbackState` with correct `controls`,
  `systemActions`, `androidCompactActionIndices`, `processingState`, `playing`,
  `updatePosition`, `bufferedPosition`, `speed`, and `queueIndex`.
- Drive `mediaItem` and `queue` from `sequenceStateStream`.
- Implement `skipToNext`, `skipToPrevious`, `skipToQueueItem`, `seek`,
  `setShuffleMode`, `setRepeatMode`, `addQueueItem`, `insertQueueItem`,
  `removeQueueItem`, `updateQueue` — all delegating to the player.
- Implement previous-restarts-current above a ~3s threshold (B5).
- Handle `PlayerException` / `PlayerInterruptedException` by emitting an error
  state and auto-advancing past unplayable items (A9).
- Emit **no** analytics of any kind — that is phase 3.

Write `lib/presentation/services/track_uri_resolver.dart`: resolves a
`SyncedTrack` to a playable URI, preferring a cached non-empty `content_uri`,
falling back to the Kotlin `buildContentUri`, and writing successful resolutions
back to the DB. Resolve a whole collection in one batch, off the UI thread.

**SHOULD:** replace the per-segment `DocumentFile.findFile` walk in
`MainActivity.buildContentUri` with a single `DocumentsContract.buildDocumentUriUsingTree`
construction from the tree URI plus relative path, falling back to the walk only
if that fails. This is the difference between hundreds of directory enumerations
and none.

**Verify:** a temporary debug button that loads 10 tracks and plays them proves:
auto-advance works, notification next/previous work, Bluetooth next/previous
work, shuffle and repeat work, a deleted file is skipped.

**Status: COMPLETE.** Report in `.agent/phase1-report.md`. Go/no-go passed:
`content://` playback works through `just_audio`'s native path, so the §6 top
risk did not materialise.

**What it actually built, and what later phases must know:**

- `setAudioSources` is used directly. `ConcatenatingAudioSource` is gone — do not
  reintroduce it.
- The handler is the sole owner of the queue. There is no Dart-side list. `queue`
  and `mediaItem` are derived from `sequenceStateStream`; `playbackState` is
  piped from `playbackEventStream`. **Do not add a parallel list in any later
  phase.**
- `updatePosition` emits `_audioPlayer.position` (extrapolated), NOT
  `event.updatePosition` (a sparse platform sample). Pairing a stale sample with
  a fresh `updateTime` resets the media session's projection and snaps the
  playhead backwards. Do not "simplify" this back.
- `playCollection` calls `_audioPlayer.play()` **without awaiting** — `play()`'s
  future completes when playback *stops*. Do not add an `await`.
- `dispose()` cancels all three subscriptions. Anything that constructs the
  handler owns calling it.
- `TrackUriResolver` exists but `resolveBatch` is a **sequential** loop over the
  per-track SAF walk. Deferred from this phase — see Phase 2.
- `MainActivity.buildContentUri` was **not** optimised. The per-segment
  `DocumentFile.findFile` walk is still there. Deferred — see Phase 2.

**Verification debt — implemented here, unverifiable until there is UI.** Each
item names the phase that must exercise it. None may be assumed working.

| Unverified behaviour | Verified in |
|---|---|
| `skipToPrevious` B5 branches (>3s restart vs <3s previous) | Phase 5 |
| Shuffle and repeat modes | Phase 5 |
| `addQueueItem` / `insertQueueItem` / `removeQueueItem` / `updateQueue` | Phase 5 |
| `seek` / `seekForward` / `seekBackward` system actions | Phase 5 |
| A9 error auto-advance (all 10 test tracks were playable) | Phase 7 |

**Two known gaps left open deliberately:**

1. The error listener advances past an unplayable track, but an unplayable
   **last** track leaves the player parked in the error state. A9 also wants a
   user-visible notice naming the skipped track, and an actionable message when
   every track is unplayable. Both need UI — Phase 4 builds the notice, Phase 7
   closes the behaviour.
2. `playCollection` always starts playing. A8 (restore-on-cold-start) needs a
   paused variant — Phase 7.

---

### Phase 2 — PlaybackController and provider wiring

**Goal:** one testable facade, correct dependency injection, no globals.

1. Create `lib/presentation/controllers/playback_controller.dart` exposing the
   intents and streams in §2.1. Include `queueOrigin` (a small value type:
   kind + id + display name) so "Playing from …" works.
2. `playCollection(origin, tracks, startIndex)` is the **only** way to start
   playback. Delete `playTrack`, `playAlbum`, `playArtist`, `playPlaylist`,
   `playAllTracks` as distinct code paths — they all become callers of
   `playCollection` with a different origin.
   The controller maps `SyncedTrack` → `MediaItem`, resolving each track's URI
   into `extras['uri']` and setting `artUri` from `artworkPath`. The handler's
   `playCollection(List<MediaItem>, startIndex)` takes it from there — the
   handler must stay ignorant of `SyncedTrack` and of the database.
3. **Delete `lib/presentation/providers/player_provider.dart` together with all
   six of its consumers' references** — `mini_player.dart`, `play_button.dart`,
   `player_screen.dart`, `artist_list_view.dart`, `album_list_view.dart`,
   `playlist_list_view.dart`. Phase 1 temporarily restored `PlayerProvider` to
   `main.dart` purely to keep those widgets from throwing; that crutch comes out
   here. Point each consumer at the controller. They are rewritten properly in
   Phases 4–6; here they only need to compile and not crash.
4. Remove the global `OwnToneAudioHandler? audioHandler` from `main.dart`;
   provide the controller through `MultiProvider`. Construct the handler once and
   hand it to the controller.
5. Make `BrowseProvider` a tree-provided singleton; remove the `initState`
   construction in `BrowseScreen`.
6. Ensure exactly one `SyncProvider` instance exists.
7. Add a `PositionData` stream (position + buffered + duration via
   `rxdart.combineLatest3`) for the seek bar. Use `AudioService.position` for the
   position component.
8. **Inherited from Phase 1 — URI resolution performance.** `resolveBatch` is
   currently a sequential loop, and `MainActivity.buildContentUri` still walks the
   SAF tree with `DocumentFile.findFile` per path segment (O(directory size) per
   segment, per track — §1.5). The controller resolves whole collections, so this
   is now on the hot path: a 500-track playlist means hundreds of enumerations
   before playback starts.
   - Replace the walk with a single `DocumentsContract.buildDocumentUriUsingTree`
     construction from the tree URI plus relative path, falling back to the walk
     only if that fails.
   - Write successful resolutions back to `synced_tracks.content_uri` so the cost
     is paid once, and prefer a cached non-empty value. Treat `''` as null.
   - Resolve off the UI thread; consider a single batched method-channel call.

**Do not** reintroduce a Dart-side queue list. The handler owns the queue; the
controller forwards intents and re-exposes the handler's streams.

**Verify:** `flutter analyze` clean; no file imports `main.dart` for
`audioHandler`; `grep -r "SyncProvider()" lib/` yields exactly one construction;
`grep -r "PlayerProvider" lib/` yields nothing. On the emulator, the debug FAB
still plays a collection through the controller, and a playlist of 100+ tracks
starts playing without a visible stall.

---

### Phase 3 — Correct statistics

**Goal:** the numbers that reach OwnTone are right. Do this before any UI polish.

Create `lib/presentation/services/playback_stats_recorder.dart`:

- Tracks **actual listened milliseconds** per playback pass, accumulated from the
  position stream while `playing` is true, and reset on track change or a
  backward seek that crosses below the threshold.
- Records a **play** at `min(0.9 × duration, 4 minutes)` of accumulated listening.
  At most one per pass. A repeat-one loop starts a new pass.
- Records a **skip** only from explicit user intents — `skipToNext`,
  `skipToPrevious`, `skipToQueueItem`, and starting a new collection — when the
  outgoing track is below threshold and above a ~2s floor.
- Records nothing on auto-advance, error-skip, pause, stop, or app death.
- Writes directly to `pending_events` via `LocalDatabaseRepository.insertEvent`
  rather than through the Kotlin method channel, so events persist even when the
  activity is gone. Remove `recordPlayEvent` / `recordSkipEvent` from the player
  method channel once nothing calls them.

**Inherited from Phase 1 — the position stream is now trustworthy.** `playbackState`
carries an extrapolated `updatePosition`, so accumulated-listening measurement can
be driven from `AudioService.position` / the controller's `PositionData`. Do not
re-derive position from raw platform events.

**Distinguishing auto-advance from a user skip.** The handler currently exposes no
signal for *why* the track changed — a natural end and a pressed Next both surface
as a sequence change. The recorder must not guess. Add an explicit intent signal:
have the controller/handler mark user-initiated transitions (`skipToNext`,
`skipToPrevious`, `skipToQueueItem`, new collection) so the recorder can tell them
from completion and from the A9 error-skip. Getting this wrong reproduces the
original bug in §1.2, where finishing a track was logged as a skip.

**Verify:** spec §7 steps 3 and 4 — play a track to completion, skip another, sync,
then read both tracks' play and skip counts in the OwnTone web UI at
`192.168.1.13`. This is also the first real exercise of the Phase 0.5 gate removal:
if the counts do not move, the upload path is still broken.

---

### Phase 4 — The shell

**Goal:** the app is a music player when you open it.

1. Delete `MainNavigationScreen`. Create `LibraryScreen` as `home`: an app bar
   with title, search action, sync-status action, and a drawer; a `TabBar` for
   Playlists / Artists / Albums / Tracks; body `TabBarView`.
2. Create `AppDrawer`: Sync, Schedule, Server, Storage, History, About, Sync now.
3. Create `PlayerScaffold` — a wrapper that composes `body` + docked
   `MiniPlayer` as a `Column`: `body` in an `Expanded`, `MiniPlayer` as the next
   child. The body genuinely shrinks; `MiniPlayer` is zero height when no track
   is loaded. **Never** a `Positioned` overlay, and **not**
   `Scaffold.bottomSheet` — the bottom sheet floats *over* the body without
   insetting it (only `bottomNavigationBar` and `persistentFooterButtons`
   shrink the body), so the last list row stays covered.
4. Rewrite `MiniPlayer`: streams only, artwork + title + artist + play/pause +
   next + thin progress bar, zero height when there is no current item, tap or
   swipe-up to open Now Playing.
5. Remove the nested `Scaffold` from `BrowseScreen` (or fold it into
   `LibraryScreen`).
6. Move the sync entry point out of the tab bar entirely.
7. **Remove the Phase 1 debug scaffolding**: delete
   `lib/presentation/widgets/debug_play_button.dart` and the `kDebugMode` branch
   in `main.dart`'s `MaterialApp.builder`. That branch currently wraps the whole
   app in an extra `Scaffold` to host the FAB — it must not survive into the real
   shell, where it would nest inside `LibraryScreen`'s own `Scaffold` and
   interfere with bottom insets and snackbars.
8. **Playback error notice (A9, part 1).** The handler already advances past an
   unplayable track. Surface it: a one-line, non-blocking snackbar naming the
   skipped track, driven off `AudioProcessingState.error`. Never a modal.

**Verify:** cold start lands on Library; the last row of every list is fully
tappable; there is exactly one mini player on screen at all times; no debug FAB
appears in a debug build.

---

### Phase 5 — Now Playing and the queue

1. Rewrite `player_screen.dart` as a **modal bottom sheet** (`NowPlayingSheet`),
   not a pushed route, so drag-to-dismiss works and the artwork can hero from
   the mini player.
2. Seek bar built on `PositionData`: max is the **duration**, seek on
   `onChangeEnd` only, scrub target shown during drag.
3. Controls: shuffle (2 states) · previous · play/pause · next · repeat (3
   states), all reading from and writing to the controller.
4. "Playing from <origin>" line.
5. `QueueSheet`: `ReorderableListView`, `Dismissible` rows, current-item
   highlight, auto-scroll to current on open, jump-to-track on tap.
6. Overflow: go to album, go to artist, track info.

**Inherited from Phase 4 — three things that will bite this phase:**

- **The A9 error notice becomes invisible exactly when it matters most.** Phase 4
  found that a snackbar shown while a pushed route is on top does not re-appear
  on the lower route after the route pops. That was acceptable when Now Playing
  was a rarely-open pushed route. This phase makes a sheet over Library the
  *normal* state while music is playing — which is precisely when an unplayable
  track fires. As specified, the user would never see the notice. Decide and
  implement one of: host the notice so it renders above the sheet, or surface it
  inside the sheet as well. Do not leave it dropping silently on the floor.
- **Do not add a `FloatingActionButton` to any screen.** Phase 4 A/B-verified on
  Flutter 3.41.7 that a `Scaffold` with a FAB suppresses messenger snackbars, and
  the mechanism is unknown. A round play/pause control on the sheet is the
  obvious place to reach for one — use a plain button, not a FAB, or the A9
  notice dies for a second and unrelated reason.
- **Navigation changes shape.** `MiniPlayer` currently *pushes* `PlayerScreen` as
  a route. Converting to `NowPlayingSheet` means the mini player presents a sheet
  instead. Update the mini player's tap and swipe-up handlers together with the
  sheet, and confirm the system back gesture dismisses the sheet rather than
  leaving the app.

**When verification says a feature is missing, suspect the harness first.**
Phase 4 lost significant time to a "snackbar never appears" defect that was a
`uiautomator` dump quoting artefact — see invariant 18. Dump attribute values
containing `"` switch that attribute to single-quote delimiters, so double-quoted
regexes silently miss the node. Use raw substring matching. This phase drives
more UI state than any other, so the trap is likelier here than anywhere.

**This phase clears most of Phase 1's verification debt.** All of the following
were implemented in the handler and have never been exercised. This is the first
phase with UI capable of driving them, so verifying them is part of the work, not
a bonus. Treat a failure here as a Phase 1 defect, not a Phase 5 one, and fix it
in the handler.

| Behaviour | What to check |
|---|---|
| `skipToPrevious` B5 | Past 3s → restarts current. Under 3s → previous track. At index 0 under 3s → restarts, does not no-op. |
| Shuffle | Toggling mid-track keeps the current track playing and reshuffles the rest; toggling off restores the original order with the current track still current (A3). |
| Repeat | All three states cycle and each behaves correctly, including repeat-one looping (A4). |
| Queue mutation | Reorder, swipe-remove, jump-to-track, "play next", "add to queue" all take effect in the real playback order — not just the displayed list. |
| Seek actions | `seek`, `seekForward`, `seekBackward` from both the sheet and the media session. |
| **Notification & Bluetooth transport (A6)** | See below — this one is a statistics-correctness risk, not a cosmetic check. |

**Notification and Bluetooth Next/Previous must route through the handler's
`skipToNext` / `skipToPrevious`.** Phase 3 added a consume-once user-intent flag
that those two methods set; a track change arriving *without* it is treated as
natural auto-advance and recorded as a **play**. So if a notification or headset
Next reaches the player by any path that bypasses those methods, the user's skip
is silently recorded as a play — wrong data on their server, with no error
anywhere.

Notification controls were last exercised in **Phase 1**, before the intent flag
existed, so this has never been checked in its current form. Phase 3 also logged
an unexplained observation: an injected `KEYCODE_MEDIA_NEXT` did not advance the
track while an on-screen tap on the same control did. That is *probably* an adb
injection artefact, but it is untested either way.

Check it directly: play a track past the 2s floor and below the play threshold,
press **Next on the notification**, then confirm a **skip** (not a play) was
recorded for it. Repeat for a Bluetooth/headset Next when doing the §7B
hardware pass.

**Watch for a shuffle/queue-order divergence.** `queue` is derived from
`sequenceState.sequence`. Confirm the queue sheet shows the *effective* play order
under shuffle and that the highlighted current item matches what is actually
playing — a mismatch here is the failure mode that killed the original design.

**Verify:** spec §7 steps 5 and 7; the seek bar reaches the end exactly when the
track does; every row in the table above observed on the emulator.

**Status: COMPLETE.** Report in `.agent/phase5-report.md`. The go/no-go passed
on all three counts: queue order matched actual play order under shuffle with
the highlight tracking correctly through auto-advance, Next and jump; server
play/skip counts after a shuffled session matched the tracks actually heard
(4 plays, 0 misattributions); and the A9 notice rendered with the sheet both
open and closed, including multi-track cascades with exactly one notice per
skipped track.

**What it built, and what later phases must know:**

- `queue` now emits `state.effectiveSequence` (play order). `mediaItem` still
  resolves `sequence[currentIndex]` (base order) and **must stay that way** —
  see invariant 19. The two live in different index spaces on purpose.
- `ExactPositionShuffleOrder` (`lib/presentation/services/shuffle_order.dart`)
  replaces `DefaultShuffleOrder`, whose insert lands at a random play position.
  One instance lives on the handler and is passed to **every** `setAudioSources`
  call, including `updateQueue`, which previously swapped in a fresh default.
- Reorder under shuffle is a base no-op move: base order is left untouched so
  A3's "shuffle off restores the original order" holds, and only the shuffle
  order moves. Verified on device.
- `shuffle()` is now called when shuffle is enabled and on `playCollection` when
  the flag is already set; the toggle alone never generated a new order.
- The A9 notice is owned by whichever surface is on top: the sheet hosts its own
  messenger via a `GlobalKey`, and the `LibraryScreen` listener suppresses while
  the sheet is open. Both paths verified.
- Phase 1's verification debt is cleared — B5 previous, shuffle, repeat, queue
  mutation and seek actions were all exercised.

**Inherited by Phase 6 — the one thing left untested in production:**
`ExactPositionShuffleOrder`'s one-shot insert routing (tail / after-current /
target play position) was verified only through a **temporary debug vehicle**
that called `PlaybackController.playNext` / `enqueue` directly. The vehicle was
removed. No production UI reaches those methods yet, because the library row
menus are Phase 6. When Phase 6 wires them up, that is the **first production
exercise of the routing** — check it explicitly rather than assuming the vehicle
settled it.

---

### Phase 6 — Rows, detail screens, and search

1. Delete `PlayableTile`. Rewrite `PlayButton` usages so rows follow the
   interaction grammar in the spec's §5: one tap target, laid-out trailing
   controls, ⋮ / long-press menus.
   **The row menu's "Play next" and "Add to queue" are the first production
   callers of `PlaybackController.playNext` / `enqueue`.** Phase 5 verified that
   path only through a temporary debug vehicle, since no UI reached it. With
   shuffle ON, confirm "Play next" lands the item immediately after the current
   **play** position and "Add to queue" lands it at the tail — not at a random
   play position, which is what `DefaultShuffleOrder` would have done and what
   `ExactPositionShuffleOrder` exists to prevent.
2. `TrackListView`, `PlaylistListView`, `ArtistListView`, `AlbumListView`: tap
   behaviour per the grammar; remove the fake `SyncedTrack` construction in the
   collection list views.
3. Add a now-playing indicator to the row matching the current media item.
4. Detail screens: collapsing header with Play and Shuffle actions; track list
   with play-in-context.
5. Add `SearchScreen` / search delegate over title, artist, album, playlist name.
   **Phase 4 shipped a placeholder**: the Library app bar already has the search
   affordance, and tapping it shows a "coming later" snackbar. Replace that, do
   not add a second entry point.
6. Sort-order selection and **persistence** for the library lists (spec B2).
   `BrowseProvider` holds `_sortOrder` in memory only — nothing writes it to
   `SharedPreferences`. Each of the four categories persists its own value.

**Row widgets must read streams, not mirrors.** The now-playing indicator in
item 3 is the first per-row consumer of playback state. Drive it from the
controller's `mediaItem` stream; do not introduce a `ChangeNotifier` that caches
"which track is playing" for the lists to read. That mirror is how the original
design rotted (§1.1, invariant 3).

**Wrap every screen in `PlayerScaffold`.** Phase 4 converted Library and the
three detail screens. Any new screen this phase adds — `SearchScreen` above all,
since results are playable — must dock the mini player the same way, and must
not use `Scaffold.bottomSheet` or a `Positioned` overlay to do it (see the
`PlayerScaffold` doc comment for why).
   Explicitly assigned here in Phase 4 (2026-09-24): it was out of Phase 4's
   scope and is owned by this phase, so Phase 6 does not lose it.

**Verify:** spec §7 step 2 from every list surface; B2 persistence across app
restarts.

---

### Phase 7 — Persistence, sync integration, and resilience

1. Persist and restore queue, origin, index, position, shuffle, repeat (A8).
   Restore **paused**.
   **Inherited from Phase 1:** `playCollection` always calls `play()`. Add a
   paused variant (a `startPaused` flag, or a separate `loadCollection`) rather
   than loading and immediately pausing, which produces an audible blip.
2. On sync completion, refresh `BrowseProvider` and reconcile the live queue:
   drop tracks that were deleted; if the current track was deleted, advance.
   Never interrupt playback otherwise (C2, C3).
3. **Make `content_uri` blanking deliberate instead of accidental.** Two halves
   of the same defect, in the same file:

   **(a) Stop the upsert blanking it.** Kotlin
   `DatabaseHelper.insertOrUpdateTrack` (`DatabaseHelper.kt:60-82`) writes via
   `insertWithOnConflict(..., CONFLICT_REPLACE)` and omits `content_uri` from the
   `ContentValues`. **`CONFLICT_REPLACE` deletes the conflicting row and inserts
   a new one**, so omitting a column does *not* preserve it — the old row is gone
   and the new one takes the column default. Leaving a column out cannot mean
   "keep it" while the write is an INSERT OR REPLACE.

   Change the write so omission means preserve. Preferred: **UPDATE first, INSERT
   only if zero rows affected**, building the `ContentValues` from the
   always-known metadata and adding `content_uri` / `artwork_path` **only when
   non-null**. Alternatives if that proves awkward: `INSERT … ON CONFLICT(id) DO
   UPDATE SET …` (check the SQLite version at the project's minSdk first), or
   read-merge-replace, which costs a read per track and is the weakest option.

   `artwork_path` has the same exposure — it *is* written (`:78`), but as
   `track.artworkPath`, which the worker passes as `null` at the download site.
   Confirm whether anything populates that column; if so it is being blanked on
   every re-sync too.

   **(b) Keep deliberate invalidation explicit.** A track that is genuinely
   **re-downloaded** gets a new document ID, so its `content_uri` must be
   cleared — but as an explicit write of `null`, not as a side effect of the
   upsert.

   **Verify:** sync a playlist, confirm `content_uri` is populated and playback
   starts without a resolver walk; re-sync **without** deleting the file and
   confirm the URI survives; then delete the local file, re-sync so the track is
   genuinely re-downloaded, and confirm the URI is refreshed rather than stale.
4. Surface sync errors as an app-bar badge plus a dismissible banner. (The
   playback-error snackbar is built in Phase 4.)
5. **Fix the `sync_history` schema first — nothing else in D3 can work until it
   is done.** Found during Phase 3, logged in `.agent/blockers.md`.

   `_createDB` creates `sync_history` **without** `plays_synced` / `skips_synced`
   ([database_helper.dart:102-112](../lib/data/database/database_helper.dart#L102));
   only the v2→v3 migration adds them. So a **fresh install** has a table missing
   both columns, while an upgraded install has them.

   Kotlin `insertSyncHistory` (`DatabaseHelper.kt:161-162`) writes those columns
   **only when non-null**. That is why this stayed hidden: before Phase 0.5 event
   tracking was gated off, the counts were null, the columns were omitted, and
   the insert succeeded. **Phase 0.5 made the counts unconditional, which exposed
   the latent mismatch** — the insert now fails every sync on any DB lacking the
   columns, and **no history rows are written at all**.

   **Who this actually affects — checked against the released tags.** Nobody is
   running this branch, so there is no live impact today. The risk is at release,
   and it is narrower than it first looks:

   | Released tag | DB version | `sync_history` columns |
   |---|---|---|
   | v0.1.0, v0.1.1 | 1 | present — added by the `< 3` migration on upgrade |
   | v0.1.5 – v0.1.7 | 2 | present — same |
   | **v0.1.8** (current `main`) | 3 | **absent on a fresh install** |

   Only **fresh installs of v0.1.8** are affected. Anyone who has been running
   the app since v0.1.7 or earlier came up through the `< 3` migration and has
   the columns. A fresh v0.1.8 install calls `_createDB` at version 3, so the
   `< 3` branch never runs and the columns are never added.

   Those users are fine on `main` only because its event-tracking gate defaults
   to false, keeping the counts null so the columns are omitted from the insert.
   The moment this branch ships, the gate is gone, the counts are unconditional,
   and their history silently stops being written.

   Fix by adding both columns to `_createDB` **and** a v6 migration that adds
   them when absent. The migration must tolerate a column that already exists,
   since every pre-v0.1.8 DB has them.

   **It also leaks orphan rows — clean them up.** Confirmed by pulling the DB
   off a fresh install on 2026-09-27: `sync_history` had **0 rows** while
   `sync_history_playlists` had **5, every one with `sync_id = -1`**. The failed
   parent insert returns `-1`, and the worker writes the child rows anyway with
   that as their foreign key. Nothing stops it because sqflite leaves
   `PRAGMA foreign_keys` **off** by default, so the FK declared in `_createDB` is
   never enforced. Every sync on an affected install adds more.

   So the fix has three parts: add the columns to `_createDB`, add a v6 migration
   that adds them when absent, and **delete the orphans** (`DELETE FROM
   sync_history_playlists WHERE sync_id NOT IN (SELECT id FROM sync_history)` —
   or simply `WHERE sync_id < 0`). Consider whether enabling `foreign_keys` is
   worth it; if you do, audit the other tables first, because it changes
   behaviour everywhere at once and that is a bigger change than this item.

   Verify **all three**, since each proves something the others cannot:
   - a DB shaped like a fresh v0.1.8 install (columns absent) → upgrade → sync →
     a history row appears. This is the path the bug actually lives on.
   - a DB that came up through the `< 3` migration (columns present) → upgrade →
     sync → still works, i.e. the v6 migration did not fail on existing columns.
   - after the migration, `sync_history_playlists` has no rows whose `sync_id`
     has no parent, and a subsequent sync writes a child row with a real one.

6. Show a pending-events count in the drawer or Sync screen (D3), and render
   `plays_synced` / `skips_synced` on the History screen. Note that since Phase
   0.5 these are `0` rather than `NULL` when a sync uploads nothing — display
   that as "no events", not a bare "0 plays".
7. **Close out A9 (part 2).** Phase 1 left the error path incomplete: an
   unplayable **last** track leaves the player parked in the error state, and
   there is no handling for a queue in which *every* track is unplayable. Fix
   both — the latter stops playback and shows an actionable message pointing at
   Sync.

   **What already exists, so you do not rebuild it:** Phase 4 built the notice
   itself and verified it end-to-end against a genuinely deleted file. The
   handler exposes `skippedTrackStream`, which resolves `PlayerException.index`
   against the live sequence and emits the failed `MediaItem` *before* calling
   `seekToNext()` — so the track named is always the right one. The controller
   re-exposes it as `skippedTrack`. Consume that stream; do not re-derive the
   failed track from `mediaItem` or `playbackState`, which race with the advance.

   What is left is the **behaviour at the edges**: the last-track case and the
   all-unplayable case. Neither has ever fired.

**Verify:** spec §7 steps 9, 10, 11, 12. For step 10, delete a synced file from
the SAF folder so the error path genuinely fires; confirm the skip notice appears
and playback continues, then repeat with the deleted file as the last track in
the queue.

---

### Phase 8 — Track ratings (view, edit, bidirectional sync)

**Goal:** a five-star rating with half-star precision on Now Playing, synced both
ways, server wins on conflict.

Depends on Phase 5's `NowPlayingSheet` and Phase 6's row work. Nothing in
Phases 2–7 depends on it.

**Confirmed against the OwnTone JSON API docs:** `rating` is an integer **0–100**
on the track object, and `PUT /api/library/tracks/{id}?rating=N` is documented and
settable — the same query-parameter shape `OwnToneApiClient.updateTrackStats`
already uses. Half-stars map onto 0–100 in tens (0.5★=10 … 5★=100), no rounding
loss. `Track.rating` already exists in the Dart API model
(`lib/data/models/track.dart:47`) and is parsed off the wire, then dropped at the
`Track` → `SyncedTrack` boundary. There is no DB column, no Kotlin field, no UI.

**Locked interaction design (user-specified):**

| Aspect | Decision |
|---|---|
| Scale | 5 stars, half-star steps → `rating = stars × 20` |
| Zero | Reachable by dragging fully left; stored and pushed as 0. **No unrated-vs-zero distinction** — both render as five empty stars |
| Gesture | Press-and-drag, **relative**: grab the current rating, horizontal movement adjusts it, a full screen-width sweep spans 0–5 (half-star ≈ 10% of width) |
| Vertical movement | Ignored while pressed, so the finger can move clear of the stars |
| Commit | On release |
| Placement | Overlaid on the current track's artwork, **hidden by default**, shown by tapping the artwork — HTML5-video-controls behaviour (tap toggles, auto-hide after a few seconds idle) |
| Other surfaces | Read-only stars on track rows; `Rate…` in the row ⋮ menu opening the same control |
| Write timing | Durable locally at once; the **sync worker** pushes at the next sync |
| Conflicts | **Server wins** |

#### Schema — DB version 7

One column on `synced_tracks`: `rating INTEGER NOT NULL DEFAULT 0` — the
displayed value, updated optimistically on edit.

One new table, **general over fields** so future field edits reuse it rather than
growing a parallel mechanism:

```sql
CREATE TABLE pending_track_edits (
  track_id   INTEGER NOT NULL,
  field      TEXT    NOT NULL,   -- 'rating' now; 'usermark' later
  new_value  TEXT    NOT NULL,   -- stringified; `field` determines interpretation
  base_value TEXT    NOT NULL,   -- server's value when the edit was made
  updated_at INTEGER NOT NULL,   -- epoch ms
  PRIMARY KEY (track_id, field)
)
```

No FK to `synced_tracks` — an edit must survive local deletion of the track,
since the server still has it. (Note also that `foreign_keys` is off by default,
so a declared FK would not be enforced anyway — see Phase 7 item 5.)

**The composite primary key gives last-write-wins for free.** A drag passing
through four values leaves one row, not four.

**`base_value` is the baseline, carried on the edit row rather than as a
`server_<field>` column per field.** This is what makes the design generalise:
adding another field later needs no new baseline column.

State is unambiguous:
- **no pending edit** — `synced_tracks.rating` *is* the last-known server value
- **pending edit** — `synced_tracks.rating` is the user's value (so display stays
  a plain column read, no join on hot paths); `base_value` is what the server had

**Critical upsert rule:** when the row already exists, **preserve the original
`base_value`** and overwrite only `new_value` and `updated_at`. Overwriting
`base_value` with the user's own previous edit destroys server-change detection —
the baseline must stay anchored to server truth. This is a one-line mistake with
an invisible failure mode.

**Why not `pending_events`:** it holds *accumulative* events (three plays = +3;
each row is independent data), has no payload column, deletes an event after 5
failures (`BackgroundSyncWorker.kt:954-958` — fine for a play count, wrong for a
deliberate user edit), and its `when (event.eventType)` has no `else`, so an
unrecognised type fails silently. Field edits are *last-write-wins state*, a
different thing.

#### Reconciliation — during sync, zero extra HTTP

`BackgroundSyncWorker.kt` already holds both sides at ~line 425: `uniqueTracks`
(fresh from `getPlaylistTracks`) and `existingTracks` (a `Map<Int, SyncedTrack>`
from the DB). Insert the pass there. Let **S** = the server's current value and
**E** = the `pending_track_edits` row for `(track_id, 'rating')`, if any:

| Condition | Meaning | Action |
|---|---|---|
| no `E`, `S != synced_tracks.rating` | server changed, no local edit | pull: set `rating = S` |
| no `E`, `S == synced_tracks.rating` | nothing changed | nothing |
| `E` exists, `S != E.base_value` | server changed (whether or not local did) | **server wins** — set `rating = S`, **delete `E`** |
| `E` exists, `S == E.base_value` | local edit only | `PUT`; on success **delete `E`** (`rating` already holds it) |

Row three implements server-precedence without needing to detect "both changed"
as a separate case. Deleting `E` **only on a successful PUT** is what makes a
failed push retry indefinitely — no 5-strike data loss.

**Coverage sweep (required).** The loop only sees tracks in currently selected
playlists, so an edit on a track that dropped out of every synced playlist would
never push. After the playlist loop, iterate any remaining `pending_track_edits`
rows and apply the same rules, fetching the server value per track via the
existing `getTrack(trackId)` (`OwnToneApiClient.kt:243`). Normally zero rows,
therefore zero requests.

**Pushing: use the bulk endpoint.** `PUT /api/library/tracks` with body
`{ "tracks": [ { "id": 1, "rating": 100 }, … ] }` sends every pending edit in one
request. Success is `204 No Content`. **On failure fall back to individual
`PUT /api/library/tracks/{id}?rating=N` calls** so one rejected track does not
strand the rest; delete each edit row only when its own write succeeded. Note
this body is JSON, unlike `updateTrackStats`, which sends a zero-byte body with
query params — do not copy that method wholesale.

#### The trap: existing rows are never refreshed

Track rows are written **only inside the download loop**
(`BackgroundSyncWorker.kt:509-529`), so a track already on disk never has its row
updated. Pulling server ratings needs a **targeted** update of the rating column
only — and after Phase 7 item 3, `insertOrUpdateTrack` will preserve omitted
columns, but a narrow `updateTrackRating` is still the right tool.

#### Files

**Dart:** `database_helper.dart` (bump to 7, add the column and table, add the
migration) · `local_database_repository.dart` (`SyncedTrack.rating`; upsert and
read helpers for `pending_track_edits`, honouring the preserve-`base_value`
rule) · `lib/presentation/widgets/star_rating.dart` **new** (an interactive
`RatingControl` and a compact read-only `StarRatingDisplay`) · `NowPlayingSheet`
(artwork tap-to-toggle overlay) · `library_rows.dart` (read-only stars, `Rate…`
in the ⋮ menu).

**Kotlin:** `OwnToneApiClient.kt` (`rating: Int = 0` on the `Track` data class;
a bulk-push method — no read-modify-write `getTrack`, since rating is absolute,
not a delta) · `DatabaseHelper.kt` (`SyncedTrack.rating`, `fromCursor`, a narrow
`updateTrackRating`, and `pending_track_edits` accessors) · `BackgroundSyncWorker.kt`
(the reconciliation pass and the sweep).

#### Verify

Gesture first — it is the part most likely to need rework:
1. Tap artwork → stars appear; tap again → hide; idle → auto-hide.
2. Press and drag right → rating rises in half-star steps; a full screen-width
   sweep covers 0→5.
3. While pressed, move vertically off the star row → rating unchanged, gesture
   not cancelled.
4. Release → value persists. Drag fully left → 0, five empty stars.

Round trip:
5. Rate a track 3.5★, sync, check that track in the OwnTone web UI — must read 70.
6. Change a rating **on the server**, sync, app shows the new value.
7. **Conflict:** change the same track's rating on the server *and* in the app,
   then sync → the server's value wins in both places.
8. Rate a track offline, force-stop, reopen → rating still shown. Restore
   network, sync, confirm it reaches the server.
9. Re-edit the same track twice before syncing → one row, and the push still
   detects a server-side change correctly (the `base_value` rule).
10. A sync that changes no ratings issues no rating PUTs at all.
11. Playback still works for tracks whose rating was updated (catches accidental
    `content_uri` blanking).

#### Keep it general while building it

- Do not hard-code `'rating'` outside the call sites. Schema, upsert helper,
  reconciliation loop and accessors all take `field` as a parameter.
- `new_value` / `base_value` stay `TEXT`. Rating stores `"70"`; a future field
  stores its own representation. No typed column per type.
- Keep the reconciliation rules field-agnostic — they only compare `S` against
  `base_value`.
- Do **not** build a generic field-edit UI. Generality belongs in storage and
  sync; the UI stays rating-specific until another field is scheduled.

**Adding a future field needs:** the field on the Kotlin `Track` class so `S` can
be read, its PUT parameter name, a `synced_tracks` column for last-known server
truth, and UI. The settable set is closed and small — `PUT
/api/library/tracks/{id}` accepts exactly `rating`, `play_count`, `skip_count`,
`usermark`, `time_played`, `time_skipped`.

**Tag editing is NOT possible with this API — do not plan for it.** `title`,
`artist`, `album`, `album_artist`, `genre` and `year` are not writable.
`PUT /api/queue/items/{id}` *does* accept them, but that edits an ephemeral
**queue item** (intended for overriding internet-radio metadata) and never
touches the library. The only other route would be editing file tags on disk plus
`PUT /api/rescan` — but this app holds synced *copies on the phone*, not the
server's originals, so local edits could never propagate. Server-side tag editing
needs an upstream API change. See `.agent/backlog.md`.

---

## 4. File-level disposition

| File | Action |
|---|---|
| `lib/presentation/services/audio_handler.dart` | **Rewritten — DONE** (phase 1). Later phases change it only to close the A9 gaps and add a paused load. |
| `lib/presentation/providers/player_provider.dart` | **Delete, with all six consumers' references** (phase 2) |
| `lib/presentation/controllers/playback_controller.dart` | **New** (phase 2) |
| `lib/presentation/services/track_uri_resolver.dart` | **Created** (phase 1); **batching + caching** (phase 2) |
| `lib/presentation/widgets/debug_play_button.dart` | **Temporary** (phase 1) → **Delete** (phase 4) |
| `lib/presentation/services/playback_stats_recorder.dart` | **New** (phase 3) |
| `lib/presentation/screens/main_navigation_screen.dart` | **Delete** → `LibraryScreen` (phase 4) |
| `lib/presentation/screens/library_screen.dart` | **New** (phase 4) |
| `lib/presentation/widgets/app_drawer.dart` | **New** (phase 4) |
| `lib/presentation/widgets/player_scaffold.dart` | **New** (phase 4) |
| `lib/presentation/widgets/mini_player.dart` | **Rewrite** (phase 4) |
| `lib/presentation/screens/player_screen.dart` | **Rewrite** as `NowPlayingSheet` (phase 5) |
| `lib/presentation/widgets/queue_sheet.dart` | **New** (phase 5) |
| `lib/presentation/widgets/play_button.dart` | **Rewrite**; delete `PlayableTile` (phase 6) |
| `lib/presentation/widgets/*_list_view.dart` | **Rewrite** row interaction (phase 6) |
| `lib/presentation/screens/browse_screen.dart` | **Fold into** `LibraryScreen` (phase 4) |
| `lib/presentation/screens/*_detail_screen.dart` | **Revise** headers + rows (phase 6) |
| `lib/presentation/screens/search_screen.dart` | **New** (phase 6) |
| `lib/main.dart` | **Revise**: no global handler, provider wiring, `LibraryScreen` home |
| `lib/presentation/providers/browse_provider.dart` | **Revise**: tree-provided, refresh-on-sync |
| `lib/presentation/providers/sync_provider.dart` | **Revise**: drop event-tracking toggle only |
| `lib/data/database/database_helper.dart` | **Revise**: `content_uri` normalisation, `playback_state` |
| `lib/data/repositories/local_database_repository.dart` | **Additive**: URI cache-back, playback state |
| `android/.../MediaNotificationListener.kt` | **Delete** (phase 0) |
| `android/.../MainActivity.kt` | **Revise**: drop listener + player event channels, faster `buildContentUri` |
| `android/app/src/main/AndroidManifest.xml` | **Revise**: drop listener service and permission |
| `android/.../BackgroundSyncWorker.kt` | **Revise**: remove the event-upload gate (phase 0.5). **Additive**: explicit `content_uri` invalidation on re-download (phase 7); rating reconciliation pass + coverage sweep (phase 8) |
| `android/.../DatabaseHelper.kt` | **Revise**: fix `insertOrUpdateTrack` blanking omitted columns under `CONFLICT_REPLACE` (phase 7). **Additive**: `rating`, narrow `updateTrackRating`, `pending_track_edits` accessors (phase 8) |
| `lib/presentation/widgets/star_rating.dart` | **New** (phase 8) |
| `lib/data/repositories/owntone_api_repository.dart`, `file_system_repository.dart` | **Unchanged** |

---

## 5. Working agreement for the implementing session

- Work **one phase per session or per branch commit**. Do not begin a phase until
  the previous phase's verification has been run.
- **Read `.agent/invariants.md` before starting, and update it before reporting.**
  It holds facts that constrain later work, each with what breaks if undone.
  Promote anything your phase established that a future phase must not undo, and
  record any concern that looked real but was already handled as a RESOLVED
  CONCERN. Later phases run in isolated sessions with no memory of yours and do
  not read phase reports — invariants is the only channel that reaches them.
- After every phase: `flutter analyze` (0 errors, 0 warnings) and
  `flutter build apk --debug`.
- Every phase must be **run and verified on a device**, not just analysed.
  `emulator-5554` (Android 16, API 36) is available: `flutter run -d emulator-5554`.
  A clean `flutter analyze` is necessary, never sufficient.
- The emulator covers lock-screen controls, the media notification, audio focus,
  background playback, and SAF grants. It does **not** cover Bluetooth/AVRCP,
  headset-unplug, or Doze — those three are listed in §7B of the UX spec and are
  deferred to a physical phone before the milestone ships, not skipped.
- The OwnTone server is at `192.168.1.13`, reachable directly from the emulator
  over the LAN. Use that address as-is for any phase that touches the server
  (the phase 0.5 round trip, the phase 0 regression check, phase 7). Do not
  assume the server is on the host machine.
- Do not modify the sync download/upload pipeline. The only sync-side changes
  permitted are the additive ones named in §4.
- Do not add dependencies beyond those named in phase 0.
- When something in the spec turns out to be wrong or impossible, write it down
  in `.agent/blockers.md` and stop that phase rather than improvising a different
  architecture.
- Prefer deleting the old code over adapting it. The old player code is the
  source of the bugs; carrying pieces of it forward carries the bugs forward.

---

## 6. Highest-risk items

| Risk | Why | Mitigation |
|---|---|---|
| `content://` URIs in `just_audio` | Historically flaky; the Dart HTTP proxy intercepts in some configurations | Use `AudioSource.uri` with no headers/userAgent so the native path handles it. Validate in phase 1 before building anything on top. |
| SAF permission loss | A persisted tree grant can be revoked by the system or the user | Detect on resolution failure and route the user to re-grant, rather than silently failing to play. |
| Stale `content_uri` after re-download | Document IDs change | Invalidate in the sync worker (phase 7); resolver must fall back rather than error. |
| `just_audio` / `audio_service` upgrade | Breaking API changes between majors | Do the upgrade in phase 0, alone, with nothing else in the commit. |
| Stats correctness | The whole point of the feature, and easy to get subtly wrong | Phase 3 is verified by reading the DB directly, not by trusting the UI. |
