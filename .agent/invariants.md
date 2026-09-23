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

### 9. Natural completion is a play, never a skip

**WHY:** the original implementation called `skipToNext()` on completion, which
recorded a skip. Finishing a track you love told OwnTone you skipped it.

**BREAKS IF UNDONE:** wrong data is written to the user's server and corrupts
their smart playlists — the failure this whole feature exists to correct.

**NOTE FOR PHASE 3:** the handler exposes no signal for *why* a track changed.
A natural end and a pressed Next both surface as a sequence change. The stats
recorder must not guess; an explicit user-intent signal is required.

---

## Environment

### 10. The OwnTone server is at `192.168.1.13`

It is on the LAN, **not** on the host machine. `10.0.2.2` (the emulator's host
alias) is wrong here and will not reach it.

### 11. `pending_events` cannot be read from the shell

It lives in app-private storage and the emulator image ships **no `sqlite3`
binary** (`/system/bin/sqlite3` does not exist on API 36).

**Verify play/skip counts against the OwnTone web UI instead** — note a track's
counts before, sync, then re-check. Do not burn time on `adb`/`run-as`
plumbing. If a check needs in-app visibility that does not exist yet, say so —
some of those views are story D3 and are meant to be built.

### 12. Put session logs and scratch files in `/tmp/owntone_verify/`

The opencode temp dir (`/var/folders/.../T/opencode/`) is wiped by an external
cleanup process during long sessions (observed twice in Phase 2, once while a
`flutter run` log file was the active evidence file — the log was lost to the
unlinked inode). `/tmp/owntone_verify/` is stable. When driving the UI,
`adb shell cat /sdcard/...` redirects into the temp dir also fail silently in
some shells — prefer `adb pull` to a file.

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
