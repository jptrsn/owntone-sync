# OwnTone Sync — Player-First UX Specification

**Status:** Draft for implementation
**Supersedes:** `.agent/player-spec.md`, `.agent/play-music-plan.md`
**Companion document:** `.agent/player-refactor-plan.md` (how to get there)

This document defines **what** we are building and **why**. It is deliberately
implementation-light. The refactor plan defines **how**.

---

## 1. Product thesis

Today the app is a **sync tool that recently grew a player**. The bottom nav
opens on a sync screen, the app bar says "OwnTone Sync", and playback is a
feature you find by scrolling past sync progress bars.

That is backwards. The user's actual loop is:

> Configure the server **once**. Then, every day, open the app and listen to music.

So: **the app is a music player.** Sync is a background capability with a
settings page, a progress indicator, and a history log — the same status a
podcast app gives its download queue.

Everything in this document follows from that single inversion.

### Design decisions taken (locked)

| Decision | Choice |
|---|---|
| Navigation | **Single Library screen + drawer.** No bottom nav. Sync, schedule, history, server config live behind the drawer. |
| Library scope | **Synced tracks only.** No MediaStore scan, no streaming from server. Every playable item has an OwnTone track ID. |
| Legacy event tracking | **Removed.** `MediaNotificationListener` and its permission are deleted. The built-in player is the sole source of play/skip events. |
| Refactor style | **Rewrite the playback core**, leave the sync pipeline alone apart from additive changes. |

### Non-goals (explicitly out of scope)

- Playing audio the app did not sync (device music, streaming, URLs).
- Equalizer, replay gain, crossfade, gapless tuning, sleep timer, speed control.
- Lyrics, scrobbling to anything other than OwnTone, Chromecast, Android Auto.
- Multi-user, cloud sync of playback state, library editing (tags, artwork).
- Offline-first *server* features (creating/editing playlists on the server).

These are not forbidden forever; they are forbidden in this milestone.

---

## 2. Reference players and what we take from each

We are not inventing a player. These are the specific behaviours we are copying,
and they are what the acceptance criteria below encode.

| Player | Stack | What we take |
|---|---|---|
| **Auxio** (`OxygenCobalt/Auxio`) | Kotlin, Media3/ExoPlayer | *Playback from a parent.* Every queue carries the collection it came from ("playing from **Road Trip**"). Shuffle is a real index permutation with a stable unshuffled order underneath, not a boolean flag. Playback state is persisted to a DB and restored on cold start. |
| **BlackHole** (`Sangwan5688/BlackHole`) | Flutter, `just_audio` + `audio_service` | The canonical Flutter handler shape: one `ConcatenatingAudioSource`, `MediaItem` carried as the **tag** on each `AudioSource`, `playbackEventStream` piped into `playbackState`, `sequenceStateStream` driving the current `mediaItem`. This is the pattern our current code is missing. |
| **Retro Music / Phonograph** | Kotlin | The mini-player → now-playing interaction: a docked bar that **expands by drag** into the full sheet, sharing artwork via a hero transition. Never a pushed route. |
| **`audio_service` official example** | Flutter | `AudioService.position` + `rxdart` combine-latest for the seek bar, and the `androidCompactActionIndices` notification contract. |
| **Gramophone / Symfonium** | Kotlin | Row interaction grammar: *tap row = play in context*, *⋮ / long-press = menu*. No overlaid play button fighting the row's tap target. |

**The single most important borrowed idea:** the *player* owns the queue. Not the
provider, not the UI. Everything on screen is a projection of streams the player
emits. Our current code owns a queue in Dart that the player has never heard of,
and that one mistake explains most of the visible bugs.

---

## 3. Personas and the core loop

**Primary (and effectively only) user: the owner-operator.**
Runs an OwnTone server at home. Has a phone with an SD card or a music folder.
Wants their playlists on the phone for the commute, the gym, and the car, and
wants the plays to count on the server so their smart playlists stay accurate.

**Day 1 (5 minutes, once):** point the app at the server, grant the music
folder, pick playlists, sync, set a schedule.

**Day 2 onward (daily, forever):** open app → tap a playlist → music plays →
lock phone → control from the lock screen and the car → plays land on the server
next time sync runs.

The app should make Day 2 effortless and Day 1 invisible afterwards.

---

## 4. User stories

Stories are grouped by epic. Each has acceptance criteria written so they can be
verified by hand on a device. **MUST** = required for the milestone. **SHOULD** =
required unless it blocks the milestone. **MAY** = nice to have.

Priority: **P0** = the milestone is not shippable without it. **P1** = shippable
but visibly incomplete. **P2** = polish.

---

### Epic A — Playback core

> The behaviours that make it *a music player* rather than *a thing that makes noise*.

---

#### A1. Play a collection in context — P0

**As a** listener
**I want** tapping any track in a list to play that track *and continue into the rest of the list*
**So that** I can start an album in the middle without losing the album.

**MUST**
- Tapping a track row in a playlist, album, artist, or all-tracks list starts that track **and** loads the entire visible list as the queue, with the tapped track as the current index.
- The queue preserves the list's current sort order.
- The player records the queue's **origin** (e.g. playlist "Road Trip", album "Kid A", artist "Radiohead", or "All tracks") and it is displayed on the Now Playing screen as "Playing from …".
- When the last track finishes with repeat off, playback stops and the player remains parked on the last track (position 0), it does not clear the queue.

**MUST NOT**
- Tapping a track must never produce a one-item queue. *(This is the current behaviour and it is the single worst bug in the branch.)*

**Verify:** open an album with 10 tracks, tap track 4, confirm the queue sheet
shows all 10 with track 4 highlighted, and that track 5 plays automatically when
track 4 ends.

---

#### A2. Continuous auto-advance — P0

**As a** listener
**I want** the next track to start when the current one ends
**So that** I do not have to touch my phone.

**MUST**
- Track N ending advances to track N+1 with no user interaction, in the foreground, in the background, and with the screen locked.
- Advancing emits a **play** event for the completed track, never a skip event.
- Advancing past the end of the queue respects the repeat mode (A4).

**Verify:** start a 3-track queue near the end of track 1, lock the phone, and
confirm all three play through without waking the device.

---

#### A3. Shuffle that behaves like shuffle — P0

**MUST**
- Shuffle has two states: off, on. Toggling it is instant and does not interrupt playback.
- Turning shuffle **on** mid-track keeps the current track playing and reshuffles only the *remaining* tracks.
- Turning shuffle **off** restores the queue's original order, with the current track still current.
- Shuffle state is shown in the Now Playing controls and persists across app restarts.

**MUST NOT**
- Shuffle must never be implemented by pre-shuffling a Dart list at load time (current behaviour), because that destroys the unshuffled order permanently.

---

#### A4. Repeat modes — P0

**MUST**
- Three states cycled by one button: **off → repeat all → repeat one → off**.
- The button icon distinguishes all three states (`repeat` outlined, `repeat` filled, `repeat_one` filled).
- Repeat-one replays the same track indefinitely; each full replay counts as one play event.
- Repeat state persists across app restarts.

**MUST NOT**
- Repeat must not be a boolean. *(Current behaviour, and it is wired to nothing.)*

---

#### A5. Seek with an accurate position and duration — P0

**MUST**
- The seek bar's maximum is the **track's duration**, never the buffered position.
- The position indicator advances smoothly during playback (updates at least twice per second), not only when a playback event fires.
- Dragging the thumb shows the scrub target time while dragging and seeks once on release.
- Elapsed and remaining/total times are displayed as `m:ss` (or `h:mm:ss` for tracks over an hour).

**MUST NOT**
- Seeking must not, by itself, record a play event. *(Current behaviour: the only code path that records a play is inside `seek()`.)*

---

#### A6. Background playback and media session — P0

**MUST**
- Playback continues when the app is backgrounded, when the task is swiped away from recents is **not** required to continue (stopping is acceptable), and when the screen is off.
- A media notification shows artwork, title, artist, and **previous / play-pause / next** in the compact view.
- Lock screen and always-on display show the same metadata and controls.
- Bluetooth/AVRCP and wired-headset buttons control play, pause, next, previous. A double-press of a headset button skips next.
- Audio focus is respected: playback pauses for a phone call or another app taking focus, and ducks for short notifications.
- Unplugging headphones / disconnecting Bluetooth pauses playback (becoming-noisy).

**SHOULD**
- Dismissing the notification while paused stops the service and clears the mini player.

---

#### A7. Queue management — P1

**MUST**
- A queue view is reachable from Now Playing, showing every track with the current one highlighted.
- The user can reorder tracks by drag, and the reorder takes effect in the actual playback order immediately.
- The user can remove a track by swipe; removing the currently playing track advances to the next one.
- "Play next" inserts immediately after the current track. "Add to queue" appends to the end.

**SHOULD**
- The queue view scrolls to the current track when opened.
- A "clear queue" action exists and stops playback.

---

#### A8. Resume where I left off — P1

**As a** listener
**I want** the app to remember what I was playing
**So that** reopening it after a reboot does not mean rebuilding my queue.

**MUST**
- On cold start, the app restores the previous queue, the current track, the playback position, shuffle mode, and repeat mode — **paused**, never auto-playing.
- The mini player is visible immediately on cold start if there is restored state.

**SHOULD**
- Restoration survives the app being killed by the system, not just a clean exit.

---

#### A9. Graceful handling of missing files — P1

**As a** listener
**I want** a deleted or unreadable track to be skipped, not to kill playback
**So that** an out-of-date sync does not silence my commute.

**MUST**
- A track whose file cannot be opened is skipped automatically, and playback continues with the next track.
- A one-line, non-blocking notice names the skipped track (snackbar or similar); it must not be a modal dialog.
- If every track in the queue is unplayable, the player stops and shows an actionable message pointing at Sync.

**MUST NOT**
- A missing file must never cause a silent no-op where the UI claims to be playing. *(Current behaviour: `_playFirstTrack` returns early and leaves `_isPlaying = true`.)*

---

### Epic B — The player-first shell

> Where things live and how they look.

---

#### B1. The app opens on my music — P0

**MUST**
- Cold start lands on the **Library** screen, showing synced content, not on a sync screen.
- The drawer contains: Sync, Schedule, Server, Storage/Folder, History, About.
- No bottom navigation bar exists.
- The app bar shows the library title, a search affordance, and a **sync status affordance** (idle icon / animated progress / error badge) that opens the Sync screen.

**SHOULD**
- If nothing has been synced yet, Library shows a first-run empty state whose primary action is "Set up sync", which opens the sync configuration flow.

---

#### B2. Library browsing — P0

**MUST**
- Library has four categories: **Playlists, Artists, Albums, Tracks**, switched by tabs.
- Each category persists its own sort order between sessions.
- Album and artist rows show artwork (or a consistent generated/placeholder tile), name, and a secondary line (track count, year, artist).
- Tapping a **collection** row (playlist/artist/album) opens its detail screen. It does **not** immediately start playback.
- Tapping a **track** row plays in context per A1.
- Long-press (or ⋮) on any row opens a context menu.

**MUST NOT**
- A play button must not be overlaid on top of a row's existing content via a `Stack`. Row affordances must be laid out, not stacked. *(Current `PlayableTile` stacks a button over the tile's own trailing widget, producing overlapping hit targets.)*

---

#### B3. Collection detail screens — P0

**MUST**
- Playlist, album, and artist detail screens each have a header with artwork/title/metadata and two prominent actions: **Play** and **Shuffle**.
- **Play** replaces the queue with the collection in order, starting at track 1.
- **Shuffle** replaces the queue with the collection, enables shuffle, and starts at a random track.
- The track list below supports tap-to-play-in-context (A1) and the row context menu.

**SHOULD**
- The header collapses on scroll.
- Album detail groups by disc number when more than one disc is present.

---

#### B4. Mini player — P0

**MUST**
- A mini player is docked at the bottom of the Library and all detail screens whenever there is a current track (playing or paused).
- It shows artwork, title, artist, and a play/pause button, plus a next button.
- It shows a thin determinate progress bar for the current track.
- It is part of the layout, not an overlay: the content above it must be inset so that the last list item is fully reachable.
- Swiping it up, or tapping it, opens Now Playing.
- It is absent — occupying zero height — when there is no current track.

**MUST NOT**
- It must not be `Positioned` over the body inside a `Stack`. *(Current behaviour hides the final list row.)*
- There must never be two mini players on screen.

---

#### B5. Now Playing — P0

**MUST**
- Reachable by tapping or dragging up the mini player; dismissed by dragging down or the system back gesture.
- Shows: large artwork, title, artist, album, "Playing from <origin>", seek bar with times, and controls: shuffle, previous, play/pause, next, repeat.
- Has a queue affordance opening the queue view (A7).
- Has an overflow menu with at least: "Go to album", "Go to artist", "Track info".
- Reflects the track changing from *any* source — notification, Bluetooth, auto-advance — within one frame.

**SHOULD**
- Transitions from the mini player with the artwork as a shared element.
- Derives accent colours from the artwork.
- Previous, when more than ~3 seconds into a track, restarts the current track instead of going back; before that threshold it goes to the previous track.

---

#### B6. Search — P1

**MUST**
- A search affordance in the Library app bar searches title, artist, album, and playlist name across synced content.
- Results are grouped by type and each result is playable or openable.

**SHOULD**
- Results update as the user types, debounced.

---

#### B7. Consistent artwork and no missing assets — P0

**MUST**
- Every artwork slot has a defined fallback that renders without throwing.
- Any asset referenced in code exists on disk and is declared in `pubspec.yaml`.

*(Today `assets/images/placeholder_album_art.png` is referenced in three places,
does not exist, and `pubspec.yaml` declares no `assets:` section at all — this
throws at runtime in the mini player and Now Playing screen.)*

---

### Epic C — Sync, demoted to a setting

> Same capability, quieter placement.

---

#### C1. One-time setup that stays set up — P0

**MUST**
- Server URL, music folder grant, playlist selection, and schedule are all reachable from the drawer and unchanged in capability from today.
- Once configured, none of it appears on the Library screen.
- Re-entering setup never requires re-granting the folder unless the grant was actually lost.

**SHOULD**
- A guided first-run flow walks server → folder → playlists → first sync, and is not shown again afterwards.

---

#### C2. Sync is visible but not intrusive — P0

**MUST**
- Sync progress is shown in the app-bar affordance (B1) and in the Sync screen; it never blocks or covers the library.
- A sync failure surfaces as a badge on the affordance plus a dismissible banner, not a modal.
- Playback is unaffected by a sync running — including a sync that downloads or deletes files.

**MUST NOT**
- Sync must not stop, pause, or reorder the current playback queue.

---

#### C3. The library reflects the last sync — P1

**MUST**
- When a sync completes, the Library refreshes without the user pulling to refresh or restarting the app.
- Tracks deleted by sync are removed from the library views.
- If a track deleted by sync is in the current queue, it is removed from the queue; if it is the current track, playback advances (A9).

---

#### C4. Manual sync from anywhere — P2

**SHOULD**
- The drawer offers a "Sync now" action available from any screen.

---

### Epic D — Play and skip statistics

> The reason the player exists at all.

---

#### D1. Plays are counted accurately — P0

**As a** server owner
**I want** my OwnTone play counts to reflect what I actually listened to
**So that** my smart playlists stay meaningful.

**MUST**
- A **play** event is recorded when a track reaches a completion threshold — **the lesser of 90% of duration or 4 minutes of actual listening** — measured from real playback progress, not from a seek.
- Each track playback records at most one play event per pass.
- Seeking forward past the threshold without listening does **not** count as a play. Listening past the threshold and then seeking backwards does not double-count.
- Play events persist to `pending_events` immediately, survive app death, and are uploaded by the existing sync worker.

**MUST NOT**
- Natural track completion must never be recorded as a skip. *(Current behaviour: completion calls `skipToNext()`, which records a skip.)*

---

#### D2. Skips are counted accurately — P0

**MUST**
- A **skip** event is recorded only when the user explicitly moves off a track before the completion threshold — via next, previous, tapping another track, or selecting a queue item.
- Auto-advance, repeat-one looping, missing-file auto-skip, and app shutdown never record a skip.
- A skip in the first ~2 seconds of a track (scrubbing through a queue) SHOULD be suppressed.

---

#### D3. Statistics are observable — P1

**SHOULD**
- The History screen shows, per sync run, how many play and skip events were uploaded (columns already exist).
- A pending-events count is visible somewhere in the drawer or Sync screen, so the user can tell events are queued rather than lost.

---

#### D4. The legacy notification listener is gone — P0

**MUST**
- `MediaNotificationListener` and its service registration, the
  `BIND_NOTIFICATION_LISTENER_SERVICE` permission, the settings toggle, and the
  permission-request flow are all removed.
- Upgrading users lose no queued events: any rows already in `pending_events`
  still sync.

---

## 5. Interaction grammar (one table to settle every row)

Applied uniformly across Library, detail screens, search results, and the queue.

| Target | Tap | Long-press / ⋮ |
|---|---|---|
| **Track row** | Play in context (A1) | Play next · Add to queue · Go to album · Go to artist · Track info |
| **Playlist row** | Open detail | Play · Shuffle · Add to queue |
| **Album row** | Open detail | Play · Shuffle · Add to queue · Go to artist |
| **Artist row** | Open detail | Play all · Shuffle all · Add to queue |
| **Queue row** | Jump to that track | Remove · Move to top · Move to bottom |
| **Mini player** | Open Now Playing | — |

Rows have **one** primary tap target. Trailing controls are laid out in the row,
never stacked on top of it.

---

## 6. State model the UI must reflect

Every screen renders from the same observable state. No screen may hold its own
copy of "what is playing".

| State | Consumed by |
|---|---|
| Current media item (track identity + metadata) | Mini player, Now Playing, row "now playing" indicator |
| Playing / paused / buffering / error | Mini player, Now Playing, row icons, notification |
| Position and duration | Now Playing seek bar, mini player progress bar |
| Queue (ordered list) and current index | Queue view, next/previous enablement |
| Queue origin ("Playing from …") | Now Playing |
| Shuffle mode, repeat mode | Now Playing controls |
| Sync status (idle / running + progress / error) | App-bar affordance, Sync screen |

---

## 7. Acceptance test script (manual, end-to-end)

Requires a reachable OwnTone server and at least two synced playlists.

An Android emulator is available as **`emulator-5554`** (Android 16, API 36) and
covers most of this script. The OwnTone server is at **`192.168.1.13`** and is
reachable directly from the emulator over the LAN — use that address as-is.

### 7A. Verifiable on the emulator

1. Fresh install → app opens to Library empty state → complete setup → sync →
   Library populates without restart.
2. Tap an album → tap track 4 → all 10 tracks are queued, track 4 is current.
3. Let track 4 finish → track 5 starts automatically. Note track 4's play count
   in the OwnTone web UI beforehand; after the next sync it must have gone up by
   exactly one, and its skip count must be unchanged.
4. Tap next during track 5 → after the next sync, track 5's **skip** count in
   OwnTone has gone up by one and its play count is unchanged.
5. Lock the phone → lock-screen controls show correct art and metadata →
   next/previous work → Now Playing reflects the change when unlocked.
6. **(hardware only — see 7B)** Connect Bluetooth → controls work → disconnect
   → playback pauses.
7. Toggle shuffle mid-track → current track keeps playing, rest reshuffles →
   toggle off → original order restored.
8. Cycle repeat through all three states and verify each.
9. Force-stop the app → reopen → queue, track, position, shuffle and repeat are
   restored, paused.
10. Delete a synced file outside the app → play its queue → it is skipped with a
    notice, and playback continues.
11. Start a sync while playing → playback is unaffected → library refreshes on
    completion.
12. Sync again → History shows plays and skips uploaded → the counts match what
    step 3 and 4 produced.

Every step above except step 6 runs on `emulator-5554`. Step numbering is stable
and referenced by the refactor plan — do not renumber.

**This script is performed by hand**, on the emulator, through the app's own UI.
Install and launch with `flutter run -d emulator-5554`. Step 9's force-stop is
done from Android Settings → Apps → OwnTone Sync → Force stop.

**How to check play and skip counts.** The OwnTone server at `192.168.1.13` is
the source of truth. Open its web UI, find the track, and read its play and skip
counts before and after. Do not try to read the app's local `pending_events`
table: it lives in app-private storage and the emulator image ships no `sqlite3`
binary, so there is no convenient way to inspect it from the shell.

Where an in-app view is needed to make a step checkable — a pending-events count,
or the per-sync play/skip totals on the History screen — that view is part of
story D3 and should be built rather than worked around.

### 7B. Requires real hardware

Three checks the emulator cannot honestly exercise. They are **not** optional —
they are deferred, and must be run on a phone before the milestone ships.

| Check | Story | Why the emulator can't |
|---|---|---|
| Bluetooth / AVRCP: car stereo and headset buttons control playback; double-press skips | A6 | No real Bluetooth stack or AVRCP peer. |
| Unplugging headphones / disconnecting BT pauses playback | A6 | `AUDIO_BECOMING_NOISY` is a protected broadcast and cannot be faked from adb. |
| Playback survives extended background and Doze | A2, A6 | Emulator power management does not reflect real Doze behaviour. |

Everything else — lock-screen controls, the media notification, audio focus loss
to a call or another app, background playback, SAF folder grants — does work on
the emulator and should be verified there rather than deferred.

---

## 8. Definition of done

- Every **P0 MUST** above is verified on `emulator-5554`, and the three §7B
  checks are verified on a physical phone.
- `flutter analyze` reports 0 errors and 0 warnings.
- `flutter build apk --release` succeeds.
- No reference to `MediaNotificationListener` remains in Kotlin, Dart, or the
  manifest.
- No asset referenced in Dart is missing from `pubspec.yaml`.
- The acceptance script in §7 passes in one sitting without a restart.
