# Phase 7 report — Persistence, sync integration, and resilience

2026-09-28, verified on emulator-5554 (API 36), OwnTone at 192.168.1.13:3689.

---

PHASE 7: COMPLETE

GO/NO-GO CHECK
  What it was: spec §7 step 9 — force-stop the app → reopen → queue, track,
  position, shuffle and repeat are restored, paused. (The defining A8 check;
  steps 10–12 below are the phase's other spec'd checks and all ran too.)
  Did you run it:        YES
  What you observed: with a 33-track Brass queue, shuffle ON (a non-trivial
  permutation), repeat ALL, playing "Let Your Mind Be Free" at 293456 ms,
  `am force-stop` → relaunch: mini player shows the same track with 99%, a
  **Play** button (paused, per spec), shuffle ON, repeat ALL, and the full
  33-row queue (read from the queue sheet after scrolling to top) matched
  `[queue_ids[i] for i in saved shuffle_indices]` element-for-element —
  including tracks in positions far from the head, so the permutation was
  restored, not re-randomised.

OBSERVED — things you did and saw, on the emulator, by hand
  Item 5 (v6 migration), three shapes:
  - Pushed a v5 fixture DB (pre-existing columns absent) → app opened: v6;
    `plays_synced`/`skips_synced` added to `sync_history`; 5 orphaned
    `sync_history_playlists` rows (sync_id with no parent) deleted;
    `playback_state` created.
  - Pushed a v5 fixture that had already come up through the `<3` migration
    (columns present) → v6 with no duplicate-column error and data intact.
  - Fresh install (`pm clear`) → v6 directly.
  - A real sync after each shape wrote a history row with non-null counts.
  Item 6 (D3 UI):
  - Sync screen showed "18 playback events waiting to sync" before the test
    sync and "No playback events waiting to sync" after.
  - History screen row for that sync: "Plays 14 / Skips 4" (exactly the 18
    pending events); a later no-op sync row rendered "No events" (the
    Phase 0.5 `0`-not-`NULL` rule).
  Item 3 (content_uri):
  - After file deletions + a no-delete sync, a diff of all 95 cached
    `content_uri` values showed changes only where files were actually
    re-downloaded (1 of 95); resolver log: "[TrackUriResolver] 33 cached,
    0 walked (33 tracks)".
  Item 1 (A8), step 9: as in GO/NO-GO above.
  Item 7 (A9 closeout), step 10 — deleted real files from
    `/sdcard/Music/tracks/` and watched each case:
  - Mid-queue: deleted Human Nature's file, pressed Next → PlayerException
    (code=0, index=11) in logcat, skip notice, playback continued on the
    following track.
  - Chained failures: two consecutive deleted tracks (Car Alarm index=25,
    then Human Nature index=11) both failed in ~90 ms and the next healthy
    track (Almost Never) started playing.
  - Last track, repeat off: deleted the final track's file, Next from
    second-to-last → PlayerException (index=28) → player stopped cleanly
    (`dumpsys media_session` state=NONE, no error parking) and the
    "Queue ended - no more playable tracks" snackbar appeared.
  - All unplayable: single-track queue (via search) whose only file was
    deleted → PlayerException (index=0) → stopped with "No playable tracks
    in the queue - sync again to repair missing files" and a "Sync" action.
  Item 2 + step 11 (sync while playing):
  - With House Party playing, deleted Pastime Paradise's file, started a
    sync. The sync re-downloaded it (progress UI: "Downloading …", 88 tracks
    across 2 playlists). Playback was uninterrupted: `pending_events`
    shows natural-completion plays at real track-length intervals
    (20:43:51 → 20:48:02 → 20:51:41 → 20:55:26 → 20:58:46 → 21:03:06, gaps
    matching the five track durations 3:31/4:11/3:39/3:45/3:20), and at
    21:03:06 the player reached the re-downloaded Pastime Paradise and
    played it normally. On completion the library refreshed (Soul's count
    updated 62→55; queue reconcile was a no-op, all tracks alive).
  Item 4 (error banner):
  - Deselected all playlists → Sync → the provider's guard fired ("No
    playlists selected", no worker launched) → Library showed a red banner
    "No playlists selected" with a Dismiss button → tapping Dismiss removed
    it (`lastError` cleared).
  Empty-state dead end (blockers.md 2026-09-27), verified on a genuine fresh
  install:
  - `pm clear` → launch → notification-permission Allow → Library shows the
    "Server URL not configured" banner plus the "No Music Synced" empty
    state with "Set up sync".
  - "Set up sync" → "Storage Permission Required" → Grant → READ_MEDIA_AUDIO
    Allow → picked the Music folder → folder-grant ALLOW.
  - "Server Not Configured" → entered http://192.168.1.13:3689 → Save →
    "Load Playlists" (server playlists listed with track counts) → selected
    Brass + Soul → Sync → 88 tracks downloaded (~5 min).
  - Back to Library: Brass (33 tracks) and Soul (55 tracks) are listed —
    **no app restart**. The dead end is gone.
  - Playback from the fresh state works: played House Party →
    "[TrackUriResolver] 33 cached, 0 walked (33 tracks)", no errors.
  Step 12 (server counts), run in the earlier half of the phase:
  - Baseline `play_count`/`skip_count` captured from
    `GET /api/library/tracks/{id}` for all 95 synced tracks before the
    18-event sync; after: exactly +14 plays (one track +2, the rest +1) and
    +4 skips, all values non-negative — matching the app's recorded events.

NOT VERIFIED — implemented but not exercised, and why
  - `reconcileQueue`'s removal path (a queue track deleted by a sync while
    playing): only the no-op path ran (step 11 re-downloaded its track). The
    code path is straightforward but has never fired on device.
  - Restore with the current track missing from the DB (the drop/remap
    branch of `restorePlaybackState`): all A9 deletions removed *files*, not
    DB rows, so restore always saw every track present.
  - Repeat-ONE + failed track terminal case (the `LoopMode.one` clause):
    covered by the same verified terminal logic, not fired individually.
  - The allFailed snackbar's "Sync" action: its presence and label were
    verified; tapping it (opens the Sync screen) was not exercised.
  - §7B hardware checks (Bluetooth, AUDIO_BECOMING_NOISY, Doze): deferred
    to a physical phone per spec — unchanged.

DEVIATIONS — anything not done as the phase specified
  - The spec script says install/launch via `flutter run`; I used a built
    debug APK with `adb install -r` so reinstalls preserved app data
    (`flutter install` in this environment once left the device with no
    package installed, and `flutter install` targets the release APK which
    is not built).
  - Step 9's force-stop was done via `adb shell am force-stop` instead of
    Settings → Apps → Force stop — same process-kill effect, chosen for
    repeatability.
  - The OwnTone server library is shared and was curated by other users
    during the phase (Soul shrank 62→59→55; four tracks vanished
    server-side). The step-12 diff was computed against a baseline captured
    in the same window, and the server-side changes are tracked in
    `.agent/invariants.md` (new entry on orphan semantics) — they are not
    app defects.
  - DB inspection used `run-as … cat databases/owntone_sync.db` + host
    sqlite3 for schema/queue-order facts the server cannot provide.
    Play/skip counts were verified against the server API, per invariant 11.

BUILD
  flutter analyze: No issues found (0 errors, 0 warnings)
  flutter build apk --debug: SUCCESS

UNKNOWN — behaviour you could not explain
  - Seeking (via Next) to a deleted file **while paused** put the media
    session in state=NONE with no PlayerException in logcat; pressing Play
    then triggered the load, which failed with PlayerException (index=25)
    and my handler advanced correctly (25 → 11 → healthy track playing).
    The initial silent stop looks like ExoPlayer's paused-load failure
    path not surfacing a PlayerEvent to just_audio; mechanism not confirmed
    (would need ExoPlayer-level logging). No user-visible defect: pressing
    Play recovers, and the playing-state path (the normal case) errors and
    handles exactly as verified.
  - The sync progress UI stayed at "Track 20/20"-style percentages well
    after the file list was exhausted (the event-upload phase has no
    fine-grained progress); cosmetic, not investigated.
