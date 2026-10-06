# Blockers and discovered defects

> **Currently open:** none. The 2026-10-02 scheduled-sync entry (two compounding
> defects, both present in released `main`) was fixed and device-verified on
> 2026-10-03. Everything dated 2026-09 is resolved; the 2026-10-02
> star-rendering entry is a struck misobservation, not a defect.

## 2026-09-28 — RESOLVED: the two 2026-09 entries were fixed and device-verified in Phase 7

- **2026-09-24 schema defect:** fixed by the v5→v6 migration
  (`database_helper.dart` `oldVersion < 6`): adds the two columns only when
  absent, deletes the orphaned `sync_history_playlists` children, creates
  `playback_state`. Verified in all three migration shapes and a real sync
  afterwards (history row written with non-null counts; server diff
  +14 plays / +4 skips). See `.agent/invariants.md` entry 8.
- **2026-09-27 empty-state dead end:** fixed by Phase 7 item 2
  (`LibraryScreen._onSyncCompleted` → queue reconcile +
  `BrowseProvider.loadData()`). Verified on a genuine fresh install
  (`pm clear`): empty state → configure URL → grant folder → load playlists →
  select Brass + Soul → sync 88 tracks → Library shows both playlists with
  **no app restart**. See `.agent/invariants.md` and the Phase 7 report.

Both entries below are kept as history.

---

## 2026-09-24 — `sync_history` missing `plays_synced`/`skips_synced` on fresh installs (found in Phase 3) — **RESOLVED 2026-09-28 in Phase 7**

**Symptom (observed on emulator-5554 during Phase 3 verification):** every sync
fails to write a history row:

```
E SQLiteDatabase: android.database.sqlite.SQLiteException:
table sync_history has no column named skips_synced (code 1 SQLITE_ERROR):
... INSERT INTO sync_history(...,skips_synced,...,plays_synced,...) ...
  at dev.educoder.owntone_sync.DatabaseHelper.insertSyncHistory(DatabaseHelper.kt:167)
  at dev.educoder.owntone_sync.BackgroundSyncWorker$doWork$2(BackgroundSyncWorker.kt:678)
```

The event upload itself succeeds (the error is caught; the worker reports
SUCCESS and the events are uploaded). But no `sync_history` row is written, so
the History screen shows nothing and `plays_synced`/`skips_synced` can never be
read back.

**Root cause:** the Dart schema is inconsistent between fresh installs and
upgrades.

- `lib/data/database/database_helper.dart` `_createDB` (fresh installs,
  version 5) creates `sync_history` **without** `plays_synced` /
  `skips_synced`.
- The `oldVersion < 3` migration adds those two columns, but it only runs for
  DBs that pre-date v3.
- The Kotlin worker (`android/.../DatabaseHelper.kt:161-162`) opens the same
  `owntone_sync.db` and, since Phase 0.5 made `playsSynced`/`skipsSynced`
  unconditional (always non-null), always includes both columns in the INSERT.

So on any fresh install the INSERT always fails. Before Phase 0.5 the columns
were included only when the (then-removable) event-tracking toggle was on,
which is why the defect stayed latent.

**Why this is not fixed in Phase 3:** Phase 3's go/no-go is the play/skip
counts on the OwnTone server, and those verified correct. Fixing this means a
schema change to `database_helper.dart` (add the columns to `_createDB` plus a
version-6 migration that must not double-add columns on v3-migrated DBs) — the
disposition table assigns `database_history`/`database_helper.dart` revisions
to Phase 7, and the binding constraints say not to modify the sync pipeline
beyond the named additive changes.

**Affected checks:** Phase 0.5's deferred half-verification ("newest
sync_history row has non-null plays_synced") and spec §7 step 12 / story D3
(History shows plays and skips uploaded per sync run). Phase 7 must fix the
schema before it can verify step 12.

**Not affected:** event recording, event upload, server counts — all verified
working in Phase 3.

---

## 2026-09-27 — Library never refreshes after a sync; first sync leaves a dead end (found during Phase 6 setup) — **RESOLVED 2026-09-28 in Phase 7**

**Symptom (observed on emulator-5554, fresh AVD):** installed the app, granted
the folder, selected Brass plus one other playlist, and synced. The sync
succeeded — 95 files on disk under `/sdcard/Music/tracks` — but the Library
screen still showed the "No Music Synced" empty state with no tracks anywhere.
Force-stopping and relaunching the app made the whole library appear
immediately, so the data was in the database the entire time.

**Root cause:** `LibraryScreen` calls `BrowseProvider.loadData()` **only in
`initState`** (`lib/presentation/screens/library_screen.dart:38-46`). Nothing
listens for sync completion, so the UI holds whatever it read at startup.

**Why the first sync is the worst case, and not just "a stale list".** When
`BrowseProvider.hasContent` is false, `LibraryScreen` replaces the entire tabbed
body with the empty state. Switching tabs is what would otherwise trigger a
reload — `setCategory` calls `loadData()` — but with the empty state rendered
there are no tabs to switch. A first-time user therefore reaches a state with
**no in-app route out of it**: sync completes, the screen still says "No Music
Synced", and only killing and reopening the app recovers. It reads as a broken
install rather than a stale list.

**Where it gets fixed:** Phase 7 item 2 already requires "On sync completion,
refresh `BrowseProvider`" (stories C2/C3), so no new work needs scheduling — but
that item is written in terms of keeping a *populated* library current. Whoever
implements it must confirm the **empty → populated** transition specifically,
on a genuinely fresh install, without restarting the app. A refresh that only
reloads list contents will incidentally fix this because `hasContent` is
re-evaluated on rebuild — but it must be verified, not assumed.

**Not affected:** the sync pipeline, the database, file download, or playback.
Purely a UI refresh gap.

---

## 2026-10-02 — AFFECTS RELEASED `main`: scheduled sync chain can die permanently and cannot be revived from the UI — **RESOLVED 2026-10-03 on `audio_player` (device-verified)**

Two separate defects that compound. Both exist in released **v0.1.8** on `main`,
not just on `audio_player`. Found during the Phase 8 hardware pass on a physical
device; the code was then confirmed identical on `main`. Fixed on `audio_player`
2026-10-03 (a main hotfix would collide with the imminent merge); see the
"Fix + verification" section at the end of this entry.

Neither is caused by the refactor. Both are candidates for a fix released
independently of this branch.

### DEFECT-2 — saving a schedule enqueues nothing on Android 12+

`MainActivity.registerBackgroundSync` builds a `OneTimeWorkRequest` with **both**
`setInitialDelay(delayMillis, …)` and `setExpedited(…)`. WorkManager rejects that
combination: `.build()` throws

```
IllegalArgumentException: Expedited jobs cannot be delayed
```

on API 31+. The source comment reads *"Use OneTimeWorkRequest with calculated
delay and expedited flag"* — the author intended both, not knowing they are
mutually exclusive.

Consequences, all silent:

- The throw lands **before** `enqueueUniqueWork(..., ExistingWorkPolicy.REPLACE, …)`,
  so nothing is enqueued **and** nothing existing is replaced.
- It is swallowed by the enclosing `try/catch`, so the UI reports success.
- Enabling a schedule therefore does not start it.
- Changing a schedule's time does not take effect until **one sync later**,
  because `REPLACE` never runs and the old job survives. The worker's
  `scheduleNextSync` reads `flutter.sync_schedule` from prefs afterwards and
  picks up the new value then.

**Why it has gone unnoticed:** `BackgroundSyncWorker.scheduleNextSync` enqueues
*without* `setExpedited`, so it works. Any completed sync chains the next one, and
the chain is self-sustaining. A user who runs one manual sync after enabling a
schedule sees correct behaviour indefinitely. **Confirmed on a Pixel 10 running the
production build: scheduled syncs appear in history and work as expected.**

**Deterministic**, reproduced on the hardware-pass device and root-caused there.

### Chain fragility — `scheduleNextSync()` is missing from the failure path

`scheduleNextSync()` is called at exactly two places in `BackgroundSyncWorker`:
the success path, and the "skipping today" path — the latter carrying the comment
*"Still queue up tomorrow's attempt - skipping today must not break the recurring
schedule."*

The `catch (e: Exception)` handler returns **`Result.failure()`** and never
re-arms. Not `Result.retry()`, so WorkManager will not back off and retry either.

**So one failed scheduled sync kills the chain permanently** — server off, router
rebooting, phone off WiFi at the scheduled minute, storage full. And because
DEFECT-2 means the settings screen cannot enqueue anything, **toggling the
schedule off and on cannot revive it.** Only a manual sync can, and nothing tells
the user that; the schedule keeps displaying as enabled.

Someone wrote the line-218 comment specifically to protect the chain against a
skipped day, and the error path drops it anyway.

### Severity

Narrower than "scheduled sync is broken" — it works fine until the first failure.
But the failure is silent, permanent, and unrecoverable through the UI, on an app
whose core promise is unattended background syncing.

### Fix sketch

- Drop `setExpedited` from the delayed request (a scheduled sync is by definition
  not expedited), or drop `setInitialDelay` and express the schedule differently.
  Do **not** keep both.
- Call `scheduleNextSync()` on the failure path too, or return `Result.retry()`
  so WorkManager retries with backoff.
- Stop reporting success from the schedule-save handler when the enqueue threw.

### Confirming it on a working device (non-destructive)

Make one scheduled sync fail — disable WiFi before the scheduled minute, or point
the server URL at a closed port and restore it afterwards. Then check whether any
scheduled sync fires again without a manual one. If the chain is dead, confirmed.

### Fix + verification (2026-10-03, device: Pixel 6, Android 16 / API 36)

**The fix** (4 files):

- `MainActivity.kt` — the delayed request in `registerBackgroundSync()` no
  longer calls `setExpedited(...)`; the method now returns `Boolean` and
  `updateSyncSchedule` reports the real result. The manual "run now" request
  (no initial delay) is untouched — that pairing is legal.
- `BackgroundSyncWorker.kt` — the `catch (e: Exception)` path now calls
  `scheduleNextSync()` before `Result.failure()`, matching the success and
  skip paths.
- `sync_provider.dart` — `updateSyncSchedule` throws if the native side says
  the schedule was not registered.
- `schedule_config_screen.dart` — shows "Failed to save schedule" instead of a
  false success.

**Why re-arm rather than `Result.retry()`.** The recurring schedule is a
self-chaining one-time work: every finished run enqueues the next scheduled run.
`retry()` re-runs the same spec with backoff and only re-arms the chain if a
retry eventually succeeds via the success path — a failure outlasting the
retries (or the user disabling the schedule mid-retry) leaves the schedule dead
and unrevivable from the UI, the same state this entry describes. Re-arming is
the only choice that deterministically keeps the user's cadence.

**Verified on device (full evidence in `.agent/reports/scheduled-sync-fix-report.md`):**

1. **Arming** — saved a schedule ~50s out; the worker started at the second,
   `Trigger type: scheduled`, completed, re-armed; History row shows the
   "Scheduled" chip. Pre-fix this save threw and still reported success
   (reproduced 3× the day before).
2. **Replacement** — changed the time while a job was pending; WorkManager's DB
   held one spec at the new time (old spec gone); the new time fired, the old
   did not.
3. **Chain survival (the go/no-go)** — made one scheduled sync fail by removing
   `flutter.server_url` from prefs (the worker's outer catch threw at
   BackgroundSyncWorker.kt:305); the failure re-armed the next run, and after
   restoring the URL via the UI a subsequent scheduled sync fired and succeeded
   with no manual sync.
4. **Happy path** — every successful scheduled run re-armed the next
   (23:03 → 23:17 → 01:21 → 01:36); a genuine save shows the snackbar (pixel
   A/B: bottom bar present at +1s, gone at +5s).

**Not verified / known remaining gaps.** The "Failed to save schedule" negative
case (enqueue no longer throws in repro conditions). The closed-port / no-WiFi
failure mode from the suggestion above: by code path it is swallowed per-playlist
(BackgroundSyncWorker.kt:406–648) and never reaches the outer catch, so a dead
server is recorded as a "success" run with playlist errors — the missing-URL
condition was used for the chain test instead; the closed-port run itself was
not executed. Two adjacent pre-existing gaps remain, out of scope, backlog:
user-cancel of a running sync (CANCELLED_BY_APP → no re-arm) and setForeground
refusal (Result.failure → no re-arm) can still kill the schedule.

---

## 2026-10-02 — NOT A DEFECT: rate-sheet star rendering

The Phase 8 hardware-pass report lists "Rate-sheet star rendering (gray outline
blobs, no amber fill, row overflows right edge)" as a visual defect in the release
build.

**Retested by hand on the device: rendering is correct.** Struck — do not fix, and
do not carry it forward as a known defect.

Two reasons it was a misobservation, recorded so the same conclusion is not
re-reached:

- An **unrated** track correctly renders five grey outlines. `_starIcon` lights a
  star only when `halfStars > index * 2`, and a track whose *local* rating is 0
  shows no fill no matter what the server holds — server ratings only reach the
  local DB through a sync's reconciliation pass. The row's own read-only stars
  (shown only when `rating > 0`) are the control: amber on the row but grey in the
  sheet would be a real bug; grey in both is correct.
- The overflow claim does not survive arithmetic: 5 stars × 28 logical px + 16 px
  internal padding = 156 px, in a `MainAxisSize.min` centred `Row` inside a sheet
  with 24 px side padding. That cannot reach the right edge on any phone.

Both observations came from screencap pixel analysis — the instrument behind two
earlier false conclusions in this project (invariants 18 and 29). See
verification-protocol §4: a negative result from your own harness is a claim about
two things.

---

## 2026-10-06 — OPEN: two defects observed on a real device after upgrading to v0.2.0

Reported from first real-world use: a Pixel upgraded from v0.1.8, manual sync of
a ~1,700-track library where every file was already on the device but no artwork
had been cached.

### (a) "Playlist 4 of 3" during the artwork pass — confirmed by code read

`SyncProgressBroadcaster.kt:91` formats the sync notification as:

```kotlin
.setSubText("Playlist ${currentPlaylistIndex + 1}/$totalPlaylists • Track …")
```

and the artwork resolution pass (`BackgroundSyncWorker.kt:989`) passes
`totalPlaylists` as **both** the index and the total, because it runs after the
playlist loop and has no meaningful playlist index. With 3 playlists that renders
`3 + 1` of `3`. `syncEvents` sidesteps the same problem by passing `0, 1`.

The track counter is wrong in that phase too: it reports `tracksProcessed` /
`totalTracks` carried over from the download phase while actually working through
a different set (tracks lacking artwork).

**Fix direction:** a phase that is not per-playlist should not render a playlist
counter at all. Either suppress the sub-text for non-playlist phases, or pass a
sentinel the formatter recognises — do not paper over it with arithmetic. The
same applies to the track counter during that phase.

Cosmetic, but it is the most visible part of a long sync.

### (b) Playback started on its own after the sync completed — NOT app code

A track began playing with no user action, immediately after a ~1,700-track sync
finished.

**This is not the app calling play().** Every playback trigger in Dart was
checked: there are exactly four `play()` / `playCollection()` call sites and all
four are user-initiated (a track row tap, the mini player button, the Now Playing
button, the collection Play/Shuffle actions). `_onSyncCompleted`
(`library_screen.dart:95`) does only two things — `reconcileQueue()` and
`BrowseProvider.loadData()` — and `reconcileQueue` early-returns when nothing was
deleted, which is this case: every track was already present.

So something **external** asked the MediaSession to play. Unconfirmed candidates:
a Bluetooth device connecting and sending PLAY, a stray media-button event,
Android's media-resumption feature, or the sync foreground service ending and
leaving the media session as the active one.

**Cause unknown, and not determinable from source.** Diagnosing it needs logcat
from the moment it happens:

```
adb logcat -d | grep -iE "MediaButton|MediaSession|KEYCODE_MEDIA|audio_service|OwnToneAudioHandler"
```

That will show whether a media button arrived and from where. Do not guess at a
fix without it — this project has lost sessions to exactly that
(verification-protocol §4).

Two contextual notes: it followed an unusually long sync, so it may be scale- or
duration-dependent; and spontaneous playback is user-hostile in a way the
"Playlist 4 of 3" bug is not. Of the two, this is the one that matters.
