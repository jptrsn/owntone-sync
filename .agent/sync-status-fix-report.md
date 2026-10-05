# SYNC-STATUS FIX (DEFECT A + DEFECT B + DEFECT C): COMPLETE

Targeted hotfix on `audio_player`. Not a phase; report uses the
verification-protocol §6 structure. Fixes the three defects from
`.agent/backlog.md` (2026-10-04 entries):

- **A** — a sync where *every* playlist fails is recorded and displayed as
  `success`.
- **B** — the per-playlist failures of such a run are invisible in the
  summary (no run-level error, no banner).
- **C** — two remaining exit paths kill the scheduled-sync chain (no
  re-arm): user-cancel of a running sync, and — structurally — any other
  unhandled exit. Fixed structurally: `doWork()` now re-arms in a
  `finally`, and the three per-path `scheduleNextSync()` calls were
  removed.

Changed files: `android/.../BackgroundSyncWorker.kt` (A + C),
`lib/presentation/screens/history_screen.dart` (B),
`lib/presentation/providers/sync_provider.dart` (B),
`lib/presentation/screens/library_screen.dart` (B),
`lib/data/models/sync_history.dart` (comment).

Environment: `emulator-5554`, Android 16 (API 36), 1280×2856. OwnTone
server `http://192.168.1.13:3689` (invariant 10) — **never touched**; all
failures were induced app-side by swapping `flutter.server_url` in
SharedPreferences (app force-stopped, file edited under `run-as`, see
DEVIATIONS):

- dead loopback `http://127.0.0.1:3689` — instant connection refused, ~1s run
- blackhole `http://203.0.113.1:3689` — OkHttp 10s connect timeout → ~42s run
  (long enough to cancel/disable mid-run)

APK built and installed in place (`0.1.8+17`, app data preserved). All times
device-local EDT.

## GO/NO-GO CHECK
  What it was: (1) a run where every playlist fails must be recorded and
    surfaced as a failure with a visible run-level summary (A+B); (2) a user
    cancel of a *scheduled* run must end it as `cancelled` and still re-arm
    the next scheduled sync (C, cancel path); (3) disabling the schedule
    mid-run must end the run and leave nothing queued (C, disable path);
    (4) regression — a clean scheduled run on the real server still succeeds
    and re-arms; (5) regression — the refactored skip-today exit (per-path
    re-arm removed) still re-arms.
  Did you run it:        YES
  What you observed:
    - (1) dead-loopback run: worker log `(status=failed)`; DB row 14
      `failed` + `All 2 playlists failed to sync`; History row "Sync Failed"
      with the run-level message in red and per-playlist errors when
      expanded; Library banner + app-bar red dot (OBSERVED 1-3 below).
    - (2) blackhole scheduled run, notification Cancel tapped mid-run:
      "Sync cancelled by user" → `(status=cancelled)` →
      "Next sync scheduled for Mon Oct 05 18:53:00" 17ms later; re-armed
      job present in jobscheduler (OBSERVED 5).
    - (3) blackhole manual run, schedule disabled mid-run: run ended
      `(status=cancelled)`, NO "Next sync scheduled" after the disable,
      0 pending owntone work jobs (OBSERVED 4).
    - (4) real-server scheduled run: `(status=success)` in 3.6s, re-armed,
      clean UI (OBSERVED 6).
    - (5) charging-required run on an unplugged emulator: "Skipping
      scheduled sync - device is not plugged in" → "Next sync scheduled for
      Mon Oct 05 19:36:00" 17ms later (OBSERVED 7).

## OBSERVED — things you did and saw, on the emulator, by hand
  - Installed the fixed debug APK in place (0.1.8+17, data preserved);
    library rendered with the existing playlists (Soul 59, Brass 33) → app
    up and reading the preserved DB.
  - Swapped the server URL to dead loopback via the prefs-file procedure,
    launched the app, pressed Sync now → worker logged
    "Background sync completed: 0 tracks downloaded in 950ms
    (status=failed)"; sync_history row 14 = `failed`,
    error_message `All 2 playlists failed to sync`; the two
    sync_history_playlists rows both carry
    "Unexpected error: Failed to connect to /127.0.0.1:3689".
  - Opened History → the 16:14 PM row renders "Sync Failed" (red) with
    "2 playlists • 0 tracks downloaded" and the red run-level line
    "All 2 playlists failed to sync"; expanding it lists Playlist 12 and
    Playlist 11 with their per-playlist errors. Library screen shows the
    red banner "All 2 playlists failed to sync" and the app-bar sync icon
    carries the error dot (553 red pixels in the icon region by screencap
    analysis; before the run the same region was a clean "Sync" tooltip
    with no banner).
  - Re-observed the failure UI in this session after the 17:13:42 scheduled
    failed run: bringing the app to the foreground, the Library dump
    contained the banner node "All 2 playlists failed to sync" again — the
    error state persists across process state and clears only on a clean
    success (see 6).
  - Chained-schedule survival through failures: each failed blackhole run
    (rows 15, 16, 18, 19, 20, 21, 22 — manual and scheduled) logged
    "Next sync scheduled for <next day 16:50/17:xx>" and the next one
    actually fired on the wall clock (17:13:00.075, 17:22:00.032,
    17:48:00.042, 17:59:00.035, 18:11:00.017 — all "Trigger type:
    scheduled", all within ~80ms of the saved time). A failed run no longer
    breaks the chain.
  - (C, disable path) Enabled the schedule (16:50, charging/wi-fi
    conditions off), set the blackhole URL, started a manual sync
    (17:02:52), then opened Schedule mid-run and disabled it (17:03:00,
    "Background sync disabled"). The run ended 17:03:13
    "(status=cancelled)" with NO "Next sync scheduled" after 17:03:00;
    row 17 = `cancelled`; `dumpsys jobscheduler` shows 0 pending owntone
    work jobs. Disabling mid-run still stops the schedule and kills the
    in-flight run.
  - (C, user-cancel path) Raised the "Music Sync" notification channel's
    importance to Default (Settings → OwnTone Sync → Notifications → Music
    Sync; see DEVIATIONS/UNKNOWN for why), enabled the schedule for
    18:53 (blackhole URL, conditions off). The job fired 18:53:00.042
    ("Trigger type: scheduled"). Opened the notification shade, found the
    "Syncing Music" card with its "Cancel" action
    (content-desc `Cancel`, bounds [168,1040][367,1184]) and tapped it
    ~18:53:12. Worker then logged, in order: 18:53:21.712 "Sync cancelled
    by user"; 18:53:21.722 "Background sync completed: 0 tracks downloaded
    in 21688ms (status=cancelled)"; 18:53:21.725 "Next sync scheduled for
    Mon Oct 05 18:53:00 EDT 2026". Row 23 = `cancelled`, trigger
    `scheduled`, 21688ms. `dumpsys jobscheduler`: exactly one pending
    owntone JobStatus, TIME=+23h55m (≈ tomorrow 18:53), NET constraint —
    the re-armed job is queued. (The cancel took ~9.5s to land because the
    worker notices `isStopped` at the next loop boundary after its 10s
    connect hang; WorkManager accepted it immediately.)
  - Confirmed the card was genuinely user-visible: Settings →
    Notifications → Notification history (enabled for this, see DEVIATIONS)
    lists "Recently dismissed: OwnTone Sync, 6:53 PM — 'Syncing Music' /
    'Reading existing tracks'".
  - (regression, happy path) Restored the real URL, set the schedule to
    19:17. The job fired 19:17:00.095 ("Trigger type: scheduled"),
    completed 19:17:03.708 "(status=success)", "Next sync scheduled for
    Mon Oct 05 19:17:00". Row 24 = `success`, 2 playlists / 0 tracks
    (library already current), sync_history_playlists: Soul (59) and Brass
    (33), no error_message. Re-armed job queued in jobscheduler. Library
    screen: banner gone, app bar back to a clean "Sync" — the 17:17
    failure state was cleared by the success.
  - (regression, skip path) Set the schedule's "only when charging" ON
    (emulator is on no power source at all), time 19:36. The job fired
    19:36:00.021: "Skipping scheduled sync - device is not plugged in" and,
    17ms later, "Next sync scheduled for Mon Oct 05 19:36:00 EDT 2026" —
    the skip exit (whose per-path `scheduleNextSync()` was removed) still
    re-arms via the `finally`. Row 25 = `skipped`,
    "Device not plugged into power".
  - (cleanup) Disabled the schedule ("Background sync disabled"), 0 pending
    owntone jobs, channel importance restored to Silent, real URL in
    place. Final DB rows 23/24/25 above are the last runs.

## NOT VERIFIED — implemented but not exercised, and why
  - **Partial-failure run** (exactly 1 of 2 playlists fails):
    `computeSyncStatus` returns `partial`, History renders amber
    "Sync Completed with Errors" with "1 of 2 playlists failed to sync",
    and the provider sets the banner. Not exercised: inducing it needs a
    server-side change (break one playlist mid-run) and the server is a
    live shared library that must not be touched. Code-path walk only —
    including that `failedPlaylists` counts
    `playlistDetails[*].error_message != null` and the partial branch of
    `statusMessage` is the same expression that produced the verified
    "All 2 … failed" string.
  - **`setForeground` refusal**
    (`ForegroundServiceStartNotAllowedException`): structurally covered by
    the same `finally` re-arm (it exits `doWorkInternal` the same way every
    other exit does) but not exercised — the app is foreground-service
    eligible on this emulator and the refusal cannot be induced on demand.
  - **The re-armed job firing**: every re-arm in this session targeted the
    *next day* at the saved H:M, so the actual fire of a next-day
    re-armed job was not observed (out of session). What was verified: the
    job is queued (JobStatus with correct TIME and NET constraint) and
    same-day queued jobs fire on the wall clock (the 17:13→18:11 chain
    above — each link was the previous run's re-arm firing).
  - **In-app Cancel button for a scheduled run**: the Sync screen's Cancel
    button never rendered for scheduled runs that start while the app is
    already alive (the provider only subscribes to the progress
    EventChannel at construction, via `checkIfSyncRunning`). The cancel was
    therefore delivered through the notification's Cancel action; both
    paths converge on a WorkManager cancel →
    `STOP_REASON_CANCELLED_BY_APP` (the notification action is
    `createCancelPendingIntent(workerId)`, the in-app button is
    `cancelAllWorkByTag("sync-task")`).
  - **History-screen rendering of `partial`** (amber color,
    `Icons.sync_problem`, title) — see the partial-failure entry above.
  - **`interrupted` (system stop, non-user) path** — unchanged by this
    fix (it pre-dates it and returns before the status derivation); not
    exercised here (needs a constraint flip mid-run, e.g. charging
    condition + unplug, which the emulator's all-false power state makes
    awkward to script).

## DEVIATIONS — anything not done as the phase specified
  - **Server URL swapped by editing SharedPreferences under `run-as`**
    (app force-stopped) instead of the Server Configuration screen: the
    in-UI URL change raises a destructive "reset app data" confirmation
    that would have wiped the user's playlists/tracks/history on the live
    setup. The edit writes the same `flutter.server_url` key the worker
    reads; the selected-playlists and schedule keys were preserved
    verbatim. (This is also the technique used by the 2026-10-03
    scheduled-sync fix.)
  - **Channel importance temporarily raised to Default** (restored to
    Silent afterwards): with the code's `IMPORTANCE_LOW`, the FGS card sits
    in the shade's "Silent" section, which does not surface in
    `uiautomator` dumps and whose header text opens notification settings
    when tapped (see UNKNOWN). Default is a documented per-channel user
    setting; the Cancel PendingIntent is identical at both importances.
  - **Cancel delivered via the notification action, not the in-app button**
    (see NOT VERIFIED).
  - **DB inspected via `adb exec-out run-as cat databases/owntone_sync.db`
    + host `sqlite3`**, and pending work via `dumpsys jobscheduler`.
    Invariant 11 steers play/skip-count checks to the server web UI (that
    steering is about counts, and none of the runs here uploaded events —
    `pending_events` was empty). The sync_history rows are otherwise
    visible in-app (History screen), which was cross-checked where the UI
    was open. This matches the 2026-10-03 fix's use of the WorkManager DB
    under `run-as`.
  - **Notification history left enabled** (system debug setting, turned on
    to confirm the card was presented; harmless to leave on).
  - **Accidental manual sync** (row 13, 16:03, success, 1 track "Funky
    Broadway" downloaded): a stray drawer tap early in the session started
    a real manual sync against the live server. It completed normally and
    changed nothing but that one already-missing track; noted so the row is
    not misread.

## BUILD
  flutter analyze: No issues found! (0 errors, 0 warnings)
  flutter build apk --debug: Build succeeded (app-debug.apk); installed in
  place on emulator-5554 (0.1.8+17, data preserved).

## UNKNOWN — behaviour you could not explain
  - **Why the LOW-importance sync card never appeared in the shade dump.**
    During the 17:13–18:11 runs (channel `sync_channel`,
    `IMPORTANCE_LOW`), `dumpsys notification` showed the active
    NotificationRecord and the card was posted, yet `uiautomator` dumps of
    the opened shade listed the other silent notification (Digital
    Wellbeing) inline but no "Syncing Music" card, and tapping the
    "Silent" header text navigated to notification *settings* rather than
    expanding the section. After raising the channel to Default the card
    rendered in the main list normally and was tappable. Whether a human
    finger can expand the Silent section on this SystemUI (the header may
    be a settings shortcut and the expand affordance elsewhere) is
    untested — I could not find a gesture that expanded it, so I stopped
    chasing it and used the importance setting instead. It is a
    SystemUI/shade-rendering question, not an app defect: the notification
    was posted, ongoing, and (per notification history) presented.
  - **Cancelled history rows store NULL in `error_message` when the cancel
    lands during the count loop.** The loop-top stop check
    (`BackgroundSyncWorker.kt:413-417`) sets `syncCancelled` but not
    `cancellationReason`, and the insert at :842 writes
    `cancellationReason` for cancelled runs — so rows 17 and 23 are NULL
    even though the code's *intent* (and the UI broadcast fallback,
    `cancellationReason ?: "Sync cancelled by user"`) says "Cancelled by
    user". Pre-existing shape (both the 17:03 disable-check row and the
    18:53 cancel row have it); no user-visible impact (History shows the
    "Sync Cancelled" title from `status`). Not fixed here — outside the
    three defects; flagged so nobody later "fixes" a different row to
    match it or vice versa.
  - The SystemUI "keyboard touchpad tutorial" overlay (`
    com.android.systemui.inputdevice.tutorial...`) appeared twice
    mid-session and stole focus, eating two tap sequences; dismissed with
    BACK. Cause unknown (emulator image quirk, likely the injected
    `input text` events). No app impact.
