# Invariants

**Load-bearing facts. Read before every phase. Do not undo anything here
without explicit approval.**

Each entry records something that was established the hard way, usually after a
defect. They look like details worth tidying up. They are not — each one is
holding something together, and the WHY explains what.

If you believe an invariant is wrong, write it up in `.agent/blockers.md` and
stop. Do not silently change it.

**RESOLVED CONCERN** fields exist because a later session independently
re-derived a worry that was already settled. If your concern matches one, it is
answered — proceed.

---

## Playback

### 1. `updatePosition` emits the extrapolated player position

`audio_handler.dart`, in the `playbackEventStream` listener:
`updatePosition: _audioPlayer.position` — **not** `event.updatePosition`.

**WHY:** `audio_service` sends `(updatePosition, updateTime, speed)` to the
media session. Both the Android notification and `PlaybackState.position`
project the playhead forward from that triple, and `copyWith` stamps a fresh
`updateTime` on every emission.

**BREAKS IF UNDONE:** `event.updatePosition` is a sparse platform sample,
often frozen at the track-start value. Pairing a stale position with a current
timestamp resets the projection baseline, and the playhead snaps backwards.
(Found and fixed during Phase 1 verification.)

**RESOLVED CONCERN:** platform `PlaybackEvent`s arrive only every ~26–44s for
`content://` sources. This does **not** make position stall.
`PlaybackState.position` is a computed getter that extrapolates between events,
and `AudioService.position` emits on its own ticker. Verified on device: the
notification playhead advanced smoothly for ~60s with events that sparse. If a
seek bar stalls, the bug is in the handler's emission or in the `PositionData`
wiring — not in `AudioService.position`, and not a reason to find a different
position source.

**RESOLVED CONCERN (Phase 3):** while verifying stats on device,
`AudioService.position` was observed advancing smoothly in ~16–200ms steps
(e.g. 2:43→2:58→4:11→4:19→5:51 over the observed window) with `content://`
sources, while paused it held its last value exactly (4:11 frozen across three
dumps; 0:01 frozen on a paused track). Confirms the Phase 1 resolved concern:
the ticker-driven stream is a usable listening-time clock for the stats
recorder (see invariant 14). No stall was seen in ~80 minutes of playback.

**RESOLVED CONCERN (Phase 2):** the PlayerScreen "Bad state: Stream has already
been listened to" was in the `PositionData` wiring, not in position itself.
Root cause: `PlaybackController.positionData` exposed the raw `Rx.combineLatest3`
result — a single-subscription stream that cannot be re-listened after a
listener cancels. Reopening PlayerScreen re-subscribed and threw. Fixed by
having the controller own the one subscription and re-expose a `BehaviorSubject`
(see invariant 10). Seek-bar position advanced smoothly in real time in the
same session (4:01→4:17 over ~16s), confirming `AudioService.position` works.

### 2. `playCollection` does not await `play()`

`audio_handler.dart`: `_audioPlayer.play();` with no `await`.

**WHY:** `AudioPlayer.play()`'s future completes when playback **stops**, not
when it starts.

**BREAKS IF UNDONE:** awaiting it hangs `playCollection` for the entire
duration of playback.

### 3. The player owns the queue. There is no Dart-side queue list.

`queue` and `mediaItem` are derived from `sequenceStateStream`. `playbackState`
is piped from `playbackEventStream`.

**WHY:** this is the entire point of the refactor. §1.1 of the refactor plan
documents the original failure: a Dart list in `PlayerProvider` alongside a
player that had been handed a single-item source, so the player had no concept
of "next".

**BREAKS IF UNDONE:** auto-advance, notification next/previous, Bluetooth
controls, "add to queue", shuffle and repeat all silently stop working — the
exact bug set this project exists to fix. A parallel list has been
reintroduced once already, during a Phase 1 attempt, under the name
`_backingQueue`. Watch for it under any name.

### 4. `setAudioSources`, not `ConcatenatingAudioSource`

**WHY:** `ConcatenatingAudioSource` is deprecated in `just_audio` 0.10.x.

**BREAKS IF UNDONE:** an earlier attempt nested a `ConcatenatingAudioSource`
inside `setAudioSources([...])`, mixing two incompatible APIs, so
`currentIndex` no longer indexed what the code assumed. There is no later phase
scheduled to migrate this — it is already done.

### 5. `BaseAudioHandler.playMediaItem` is an empty default

**WHY:** `audio_service` provides a no-op implementation.

**BREAKS IF UNDONE:** routing playback through it produces silence with no
error. The old `PlayerProvider` did exactly this, which is why list-row taps
were dead before Phase 2.

### 6. Fast-path content URIs must be tree-scoped, built via `buildDocumentUriUsingTree`

`MainActivity.buildContentUriFast` builds
`content://<authority>/tree/<treeDocId>/document/<treeDocId>/<relativePath>`
with `DocumentsContract.buildDocumentUriUsingTree(treeUri, documentId)`, where
`documentId = DocumentsContract.getTreeDocumentId(treeUri) + "/" + relativePath`.

**WHY:** the persisted grant from `ACTION_OPEN_DOCUMENT_TREE` only authorises
URIs that carry the tree (the `/tree/<treeDocId>/` prefix). A bare
`content://<authority>/document/<id>` URI is what `ACTION_OPEN_DOCUMENT`
produces, and reading one under a tree grant is denied with
`SecurityException: requires that you obtain access using ACTION_OPEN_DOCUMENT
or related APIs`. Verified on emulator-5554 for one file: the bare URI failed
`openFileDescriptor` with exactly that exception while the walk's
tree-scoped URI for the same file opened fine. Tree listing and writes keep
working because they go through `DocumentFile` objects derived from the tree
URI, which are well formed.

**WHY getTreeDocumentId, not lastPathSegment:** `treeUri.lastPathSegment` only
equals the tree document id when the stored tree URI is a bare tree URI. A
tree URI that already carries a `/document/` suffix would return the document
id instead, corrupting the built URI.

**BREAKS IF UNDONE:** every fast-path read is denied (SecurityException), all
tracks fall back to the O(directory-size) `findFile` walk, and any bare URIs
cached from a buggy build poison the DB. The `?: buildContentUriWalk(localPath)`
fallback must stay for tracks the fast path cannot resolve (no tree grant,
malformed stored URI).

**RESOLVED CONCERN:** `buildDocumentUriUsingTree` was previously declared
broken (an earlier version of this invariant claimed its `appendPath` produced
an unresolvable multi-segment document id). That was wrong — the original
failure came from passing the *relative path* as the `documentId` argument
instead of `treeDocId + "/" + relativePath`, misdiagnosed as a builder defect.
The builder emits exactly the correct tree-scoped form, with the document id
encoded as a single segment (verified byte-for-byte against the walk's
`DocumentFile.findFile(...).uri` on emulator-5554). Do NOT hand-roll the URI
around it again. Related safeguards: the DB v5 migration purges cached URIs
lacking a `/tree/` segment, and `TrackUriResolver` rejects any cached URI that
is not a `content://` URI containing `/tree/`.

### 7. `PlaybackController.positionData` is controller-subscribed, widget-shared

The rxdart combineLatest stream is listened to exactly once, by the controller,
and re-exposed through a `BehaviorSubject<PositionData>` (broadcast).

**WHY:** rxdart 0.28 `Rx.combineLatestN` returns a single-subscription stream
that **cannot be listened to again after a listener cancels** (verified on
device: open PlayerScreen → back → reopen → "Bad state: Stream has already been
listened to" rendered over the seek control). Any widget that `StreamBuilder`s
`positionData` directly on the raw combined stream will break on its second
mount. The mini player (Phase 4) will listen to the same stream too, so the
broadcast requirement is load-bearing.

**BREAKS IF UNDONE:** the PlayerScreen seek area renders an error widget every
time it is reopened; any second consumer of `positionData` throws.

---

## Sync and statistics

### 8. Event upload is not gated

`BackgroundSyncWorker.kt` calls `syncEvents()` unconditionally.

**WHY:** it used to read `flutter.event_tracking_enabled` from
SharedPreferences. Phase 0 removed the toggle and all its Dart plumbing, so
nothing writes that key any more.

**BREAKS IF UNDONE:** the stored value freezes permanently and queued play/skip
events never upload again. Re-defaulting the pref to `true` does **not** fix
it — `getBoolean` returns the stored value whenever the key exists, and the old
Dart code persisted it, so any user who toggled it off is stuck. Deleting the
gate is the fix. `syncEvents()` already early-returns cheaply when
`pending_events` is empty.

**Side effect:** history rows now record `0` rather than `NULL` for
`plays_synced` / `skips_synced` when a sync uploads nothing. Render that as
"no events", not a bare "0 plays".

**KNOWN DEFECT (see `.agent/blockers.md`, 2026-09-24):** on fresh installs the
`sync_history` table is missing `plays_synced`/`skips_synced` entirely
(`database_helper.dart` `_createDB` omits them; only the v2→v3 migration adds
them), so the worker's history-row INSERT fails and **no** history row is
written. The event upload itself works. Phase 7 must fix the schema before
story D3 / spec §7 step 12 can be verified.

### 9. Natural completion is a play, never a skip

**WHY:** the original implementation called `skipToNext()` on completion, which
recorded a skip. Finishing a track you love told OwnTone you skipped it.

**BREAKS IF UNDONE:** wrong data is written to the user's server and corrupts
their smart playlists — the failure this whole feature exists to correct.

**NOTE FOR PHASE 3:** the handler exposes no signal for *why* a track changed.
A natural end and a pressed Next both surface as a sequence change. The stats
recorder must not guess; an explicit user-intent signal is required.

**RESOLVED CONCERN (Phase 3):** the signal now exists — see invariant 13
(`consumeUserInitiatedTransition`). Verified on device: eight natural
completions produced plays and zero skips; two explicit user moves (start new
collection, press Next) each produced exactly one skip.

### 13. User-intent signal for track changes

`audio_handler.dart` carries a sticky `_userInitiatedPending` flag exposed as
`consumeUserInitiatedTransition()`. Set by: `skipToNext()`; `skipToPrevious()`
(only the index-changing branch — the >3s "restart current" branch must NOT
set it); `skipToQueueItem()` (only when the index actually changes);
`playCollection()` (only when the new start track differs from the current
one). Cleared by: the A9 error-skip path and `stop()`. The stats recorder
consumes it once per mediaItem change: `true` = user moved on (skip candidate),
`false` = auto-advance / loop wrap / error skip / fresh start (never a skip).

**WHY:** the player exposes no reason for a sequence change (invariant 9). The
sticky-consume pattern survives the ordering where the flag is set before the
mediaItem emission lands, and the error-path clear stops A9 auto-advance from
being attributed to the user.

**BREAKS IF UNDONE:** the §1.2 bug returns — natural completion, A9 skips, and
loop wraps become indistinguishable from user skips, corrupting skip counts.

### 14. The position stream is the clock for listening time

`AudioService.position` (= `createPositionStream(steps: 800)`) emits every
16–200ms **while playing** and not at all while paused/stalled (audio_service
0.18.19; `PlaybackState.position` is a computed extrapolation, so ticks are
smooth). `PlaybackStatsRecorder` accumulates forward deltas ≤1000ms while
`playing`; larger forward jumps are treated as seeks and never count as
listened time; a backward jump >1000ms defers a reset until the next forward
tick of the same track.

**WHY:** without the ≤1000ms guard a forward seek is counted as listened time
and can trigger a false play; without the backward-jump deferral the first
tick of a new track would wipe the outgoing track's accumulator before its
skip/play is evaluated.

**BREAKS IF UNDONE:** stats are wrong for anyone who seeks or skips quickly —
the original defect class this feature exists to fix.

### 15. Play/skip thresholds and event flow

Play: written when listened time ≥ `min(0.9 × duration, 4 min)`, at most once
per pass (a repeat-one restart is a new pass). Skip: written only on a
user-initiated track change with `2s ≤ listened < threshold`. Pause, stop,
seek, and app backgrounding write nothing. Events are `PendingEvent` rows
(Unix **seconds**) in `pending_events`, written synchronously by
`PlaybackStatsRecorder` via `LocalDatabaseRepository.insertEvent`; the only
uploader is `BackgroundSyncWorker.syncEvents`, which runs on every sync
(invariant 8) and deletes rows after successful upload.

**WHY:** these are the spec'd semantics (player-ux-spec D1/D2) verified against
the server on device. The 2s floor stops pause-immediately noise; the 4-min cap
stops long tracks from requiring near-full listening for a play.

**RESOLVED CONCERN (Phase 3):** "did the app lose events on death?" — the
recorder writes to the DB synchronously at the moment of the threshold crossing
or the user move, before any UI work; rows survive process death by
construction (sqflite commit). Verified indirectly: events recorded over
~80 minutes of playback were all present in `pending_events` when the manual
sync ran (worker logged each of the 11 events).

---

## UI

### 16. `PlayerScaffold` docks the mini player as a layout child (Column), never an overlay

`player_scaffold.dart`: `Scaffold` whose body is
`Column[Expanded(screen body), SafeArea(top: false, MiniPlayer())]`.

**WHY:** `Scaffold.bottomSheet` and `Positioned` both *overlay* the body
without insetting it — the list's last rows render under the mini player and
the final row is not fully tappable (the B4 requirement). A `Column` child
reserves real layout space. `MiniPlayer` returns zero height when no
`mediaItem`, so at idle the list uses the full height.

**BREAKS IF UNDONE:** bottom list rows hidden behind / under the player
strip; "last row of every list fully tappable" fails. Verified on device in
Phase 4 (Brass detail + 233-row Tracks tab).

### 17. The A9 skipped-track notice is hosted on the home route

`LibraryScreen`'s `State` (home route, mounted for the app's lifetime)
subscribes to `PlaybackController.skippedTrack` — a broadcast stream the
handler feeds from the error listener by resolving `PlayerException.index`
against the sequence (the item tag, unambiguous even though the player has
already auto-advanced) — and shows
`ScaffoldMessenger.of(context).showSnackBar` with the one-line text
`Skipped "<title>" - could not be played` (3s, non-modal). Dedup: same track
id within 5s is ignored.

**WHY:** hosting it on a per-screen widget would kill the notice the moment
the user is on any other screen; the home route always stays mounted, and the
app-level ScaffoldMessenger renders the snackbar over the **topmost**
route's scaffold (verified: shown while a detail route was on top).

**RESOLVED CONCERN (Phase 4):** "a snackbar shown from a lower route never
renders while another route is on top" — FALSE. That conclusion was a
detection artifact: uiautomator dumps attributes whose values contain `"`
with *single-quoted* delimiters (`content-desc='...'`), so double-quoted
attribute regexes miss the snackbar node (see invariant 18). With raw
substring detection the snackbar was visible on the topmost route every time.

**RESOLVED CONCERN (Phase 4):** a snackbar shown while a pushed route is on
top does **not** re-appear on the lower route after that route is popped
(checked mid-display window; no route-disposal logic found in the 3.41.7
scaffold source — mechanism unknown). Accepted: A9 is a 3s transient notice
and the spec does not require it to survive route changes. Do **not**
re-engineer a custom toast layer for this.

**RESOLVED CONCERN (Phase 4):** custom overlay approaches were tried and
rejected on Flutter 3.41.7: (a) entries inserted into the *navigator's*
overlay are dropped when the navigator rebuilds its entries on route
push/pop; (b) entries in a *separate* app-level overlay above the navigator
survive, but the new "theater" architecture re-stamps z-order of route
content on route changes and paints it *above* the static entry (entry stays
mounted, goes invisible). The standard snackbar is the right tool.

**RESOLVED CONCERN (Phase 4), framework quirk:** on Flutter 3.41.7 a
`Scaffold` that has a `floatingActionButton` suppresses ScaffoldMessenger
snackbars (A/B verified with quote-free snackbar text: FAB present → no
snackbar; removed → snackbar renders; no exception). If a later phase adds a
FAB to a scaffold that also shows snackbars, expect this.

---

## Environment

### 10. The OwnTone server is at `192.168.1.13`

It is on the LAN, **not** on the host machine. `10.0.2.2` (the emulator's host
alias) is wrong here and will not reach it.

Ports: `:3689` is the JSON API (no authentication — curl from the host works),
`:3000` is the server web UI (login page) which proxies the same data. Track
stats live on the server as `play_count` / `skip_count` / `time_played` /
`time_skipped` on `GET /api/library/tracks/{id}` — that is exactly what the web
UI's stats display shows, so it is the source of truth for stats verification
(invariant 11). The app's configured URL is `http://192.168.1.13:3689`
(readable on the app's Server Configuration screen).

### 11. `pending_events` cannot be read from the shell

It lives in app-private storage and the emulator image ships **no `sqlite3`
binary** (`/system/bin/sqlite3` does not exist on API 36).

**Verify play/skip counts against the OwnTone web UI instead** — note a track's
counts before, sync, then re-check. Do not burn time on `adb`/`run-as`
plumbing. If a check needs in-app visibility that does not exist yet, say so —
some of those views are story D3 and are meant to be built.

**Driving the UI (Phase 3 practice, keep doing this):** the screend
subagent cannot see the emulator in this setup — drive it with
`adb -s emulator-5554 shell uiautomator dump` + `input tap`, parsing
`content-desc` (Flutter exposes semantics labels). Three traps found the hard
way: (1) the PlayerScreen controls row shifts down ~96px when the track title
wraps to two lines — always dump the button bounds *after* the track is known
before tapping Next/Pause; (2) since Phase 4 the mini player exists on the
library AND all detail screens (PlayerScaffold docks it under the body);
confirm which screen a dump shows before tapping mini-player coordinates;
(3) see invariant 18 — attribute-value quoting silently defeats
regex-based detection.

### 12. Put session logs and scratch files in `/tmp/owntone_verify/`

The opencode temp dir (`/var/folders/.../T/opencode/`) is wiped by an external
cleanup process during long sessions (observed twice in Phase 2, once while a
`flutter run` log file was the active evidence file — the log was lost to the
unlinked inode). `/tmp/owntone_verify/` is stable. When driving the UI,
`adb shell cat /sdcard/...` redirects into the temp dir also fail silently in
some shells — prefer `adb pull` to a file.

### 18. uiautomator XML: attribute quoting defeats regex detection

When an attribute value contains `"`, `uiautomator dump` emits that attribute
with **single-quoted** delimiters (`content-desc='Skipped "Black Ice" - ...'`)
instead of double-quoted ones. Regexes like `text="([^"]*)"` /
`content-desc="([^"]*)"` silently miss those nodes, which reads as "widget
not rendered" when it is visible.

**WHY:** cost one full Phase 4 debugging cycle: a working snackbar was
misdiagnosed as a cross-route rendering defect, and an entire (rejected)
toast-layer re-architecture was built on top of it.

**USE:** for presence checks, do a raw substring search of the whole XML file
for a distinctive fragment of the expected text (a fragment that contains no
quote character). Only parse attributes for *bounds* (which never contain
quotes).

---

## Maintaining this file

**Every phase, before writing your report:** promote anything a future phase
must not undo into this file, in the format above. A fact that only lives in a
phase report will be missed — reports are historical records, not guidance, and
a later session reading one gets a partial picture.

If you resolved a concern that looked real but wasn't, add it as a
**RESOLVED CONCERN** on the relevant entry. That field exists specifically to
stop the next session re-deriving it.

Keep entries short. This file is read in full, every phase, by everyone.
