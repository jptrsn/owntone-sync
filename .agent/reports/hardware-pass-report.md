# HARDWARE PASS (release gate): COMPLETE

Physical-device verification of the `--release` build, run on a Pixel 6.
Template per `verification-protocol.md` §6, extended with the §8 DoD
walkthrough requested for this pass. Every result is labeled with the
configuration it was produced in (charging state, Doze state, exemption
state, audio route), per the mid-test requirement that no charging run be
recorded as a Doze pass.

Environment:
- Device: Pixel 6 (serial 25071FDF600953), Android 16, 1080x2400 @ 420dpi.
- Build: `flutter build apk --release`, freshly installed, the only build on
  the device for the whole pass. Not debuggable — no `run-as`, no DB access;
  all verification via app UI, `uiautomator`, `dumpsys`, logcat (Kotlin tags
  only; Dart logs are stripped in release), and the OwnTone server API at
  `192.168.1.13:3689`.
- Server: shared, in external flux (invariant 27). Drift observed during the
  pass: Soul playlist 48 → 38 → 37 → 39 tracks; track 771 removed from Brass
  by another user.
- Scratch files in `/tmp/owntone_verify/` (invariant 12).

GO/NO-GO CHECK
  What it was: The three §7B real-hardware checks (player-ux-spec.md §7B)
  plus the §8 definition of done, on a physical phone.
  Did you run it:        YES (2 of 3 checks fully; 1 partial — see NOT VERIFIED)
  What you observed:
  - 7B-2 (BT disconnect pauses playback): PASS.
  - 7B-3 (playback/sync survives extended background + Doze): PASS in the
    app's supported configuration (battery-optimization-exempt; unplugged;
    deep Doze; on-time scheduled delivery).
  - 7B-1 (Bluetooth/AVRCP button control): PARTIAL — the media-button
    transport path (the IPC route lock-screen and AVRCP buttons use) is
    verified end-to-end; physical button events from a BT controller were
    not exercisable (no such device available; the paired device is an
    A2DP sink speaker).

OBSERVED — things done and seen on the device, by hand (adb-driven)

  §7 script on the release build:
  - Step 1 — Fresh install → setup → sync → Library populated without
    restart: PASS (first sync ~15:12, 24 tracks, 3 playlists).
  - Step 2 — Albums tab → Black Pumas album → tap track 4 ("Fire", 771) →
    full 17-item queue loaded, Fire current. PASS. (Spec says "all 10
    tracks"; this album has 17 tracks in the synced subset — server album
    has 30, local holds 17 = Soul ∩ album. The earlier "missing row 6" was
    subset scope, not a bug.)
  - Step 3 — Natural completions auto-advanced; after the 17:35:55 sync
    ("Event sync completed: 10 events synced, 0 events deleted") server
    counters moved exactly as predicted: 771 3/0→4/0, 773 3/1→4/1,
    768 3/0→4/0, 770 2/0→3/0, 754 2/0→3/0, 753 4/0→5/0, 749 3/0→4/0,
    748 2/0→3/0, 757 3/2→4/2 (plays/skips). PASS.
  - Step 4 — In-app Next mid-track (16:52:56) → 777 skips 0→1, plays
    unchanged (3). PASS. (Invariant 9: natural completion = play, never
    skip.)
  - Step 5 — Lock-screen controls: PARTIAL (see NOT VERIFIED). Transport
    itself verified via the MediaSession command path (below).
  - Step 9 — Force-stop via system Settings (Apps → Force stop) → relaunch
    → Now Playing restored at 0:45/4:33 (17%), same track (766), same
    position, paused, full 17-item queue intact in the queue sheet. PASS.
    (App had also restored position earlier without force-stop; the session
    survived 13+ h of background overnight — process PID 7987 had ELAPSED
    17:10:59 this morning, i.e. the same process since 18:43 yesterday.)
  - Step 10 — Deleted 3 files from /sdcard/OwnToneMusic/tracks/ (854, 771,
    1872) → manual sync: 854 and 1872 re-downloaded with exact byte sizes;
    771 NOT re-downloaded because the server no longer lists it in any
    synced playlist (another user removed it from Brass). Playlist-scoped
    sync behaving as designed (invariant 26/27). PASS with the server-drift
    caveat; note 771 is now a local orphan (DB row, no file) — see UNKNOWN.
  - Step 12 — History screen shows per-sync play/skip totals; the
    17:35:55 sync's 10 events matched the server counters above. PASS.

  Rating drag (Epic D, device-width verification):
  - Drag mapping measured on this device: 10 rating units (half star) =
    108 physical px at this width; drag is relative to grab position;
    commit on release; rating 0 removes the "Rated" label from rows.
  - Car Alarm (1872): 40→50→70→50→10→0→40, every commit exact (row
    descriptors "Rated 2.5/3.5/2.5/0.5", label gone at 0, back to 2.0).
    A vertical-only drag was ignored (no change). Human Nature (1552)
    40→50→40; Ya'll Stay Up (1554) 60→50→60; Heart on my Sleeve (1877)
    verified 3.0 twice, untouched; Almost Never (1577) verified 60,
    untouched. All original values restored.
  - Final server check this morning (after the 00:05 scheduled sync, which
    ran the Phase-8 reconciliation pass): 1872=40, 1552=40, 1877=60,
    1554=60, 1577=60 — no rating was uploaded; nothing drifted.

  7B-1 (media-button/transport path; config: BT A2DP sink connected, app
  backgrounded, screen locked, on AC):
  - `cmd media_session dispatch play` resumed playback; `dispatch pause`
    paused; `dispatch next` advanced to the next item (766) — worker logged
    "Syncing track 755: +0 plays, +1 skips", server 755 3/0→3/1. This is
    the same command path lock-screen buttons and AVRCP passthrough use
    (MediaButtonReceiver = com.ryanheise.audioservice.MediaButtonReceiver;
    session actions=16252927). Invariant 13 verified on hardware:
    external transport next = skip, not play.

  7B-2 (becoming-noisy; config: RS2802 BT speaker as active A2DP sink,
  screen locked, app backgrounded, on AC):
  - Playback PLAYING at 101.769 s → `svc bluetooth disable` → session
    state PAUSED at 104.955 s. Position advanced only during the
    transition, then froze. System log confirms the broadcast
    (AS.AudioDeviceBroker: broadcast ACTION_AUDIO_BECOMING_NOISY).
    PASS. (The `SensorReceiverBase` log line at the same instant carried a
    PID that is not this app's process and the class does not exist in our
    just_audio 0.10.6 — it belongs to another app on the user's phone;
    attribution rests on the session-state transition, not that line.)
  - Speaker reconnected automatically after `svc bluetooth enable`.

  7B-3 (extended background + Doze; config: UNPLUGGED — software
  `dumpsys battery unplug` at 22:29:59, physical cable remained, restored
  with `dumpsys battery reset` at 11:5x this morning; app battery-
  optimization-EXEMPT — the supported configuration; screen locked):
  - Device reached deep Doze 20 s after the unplug: `dumpsys deviceidle`
    idling history (converted from the 11:45 dump): deep-idle Oct 1
    22:30:19 → maintenance windows 30 s each at 23:30:19, 01:30:49,
    05:31:19, 11:32:39 → normal at 11:44:50 (unlock).
  - The scheduled sync job (OneTimeWork, tag sync-task, fires 00:05:00
    EDT, constraints charging=false + NOT_METERED) fired ON TIME at 00:05
    while the device was in deep Doze, between maintenance windows:
    - probe file `Bill Withers_Use Me_Soul_854.mp3` (deleted at 21:47,
      141 files) re-appeared with mtime `2026-10-02 00:05`, exact original
      size 7,008,246 bytes; count back to 142.
    - App Sync History: "Sync Completed / Scheduled / 3 playlists • 1
      tracks downloaded / No events / Duration 5s", playlists Brass 33,
      Holiday Music 60, Soul 39 — matches the 21:44 server state.
    - Worker completed its success path: next job enqueued (u0a371/12,
      fires Oct 3 00:05, +23h59m53s at 11:44), constraints unchanged.
  - Interpretation (configuration matters): because the app is
    battery-optimization-exempt, its job is not deferred in deep Doze —
    on-time firing is the expected, supported behavior. This validates
    "scheduled delivery in deep Doze, exempted". It does NOT validate the
    non-supported configuration (no exemption → deferral to the next
    maintenance window, which would have been 01:30:49). That variant is
    untestable while the exemption is in effect and is recorded as NOT
    VERIFIED, not passed.
  - Playback session survived the entire period unchanged (paused at
    104.955 s; process uptime 17 h 10 m this morning).

  Defect #2 (found while arming the overnight test):
  - Saving an ENABLED sync schedule on this Android 16 device logs
    `MainActivity: Error registering background sync —
    java.lang.IllegalArgumentException: Expedited jobs cannot be delayed`.
    Reproduced 3×: 19:49:40, 19:57:38, 22:14:44 (the last triggered by
    the user's own re-save) — deterministic.
  - Root cause: `MainActivity.registerBackgroundSync()`
    (MainActivity.kt:552) builds a OneTimeWorkRequest with
    `setInitialDelay(...)` and, on API 31+, `setExpedited(RUN_AS_NON_
    EXPEDITED_WORK_REQUEST)` (MainActivity.kt:603-608). Android forbids
    the combination; the throw is in `Builder.build()`, BEFORE
    `enqueueUniqueWork(..., REPLACE, ...)` (MainActivity.kt:615), so the
    save enqueues nothing and the previous job (if any) is untouched.
    The catch is INSIDE the method, and the method-channel handler then
    returns `result.success(true)` unconditionally
    (MainActivity.kt:201-205), so Dart never sees an error.
  - Consequences:
    - The UI's "Schedule saved: Daily at HH:MM" snackbar
      (schedule_config_screen.dart:263-274) shows regardless — the app
      claims success while scheduling silently failed.
    - The battery-optimization prompt is NOT suppressed by this defect
      (hypothesis tested and rejected): the throw cannot cross the method
      channel (caught in Kotlin), and `_checkAndPromptBatteryOptimization()`
      is not on the save path at all — it fires only when the enable
      toggle is flipped on (schedule_config_screen.dart:110-112) or via
      the banner's Fix button (line 134). No
      REQUEST_IGNORE_BATTERY_OPTIMIZATIONS intent appears in logcat around
      the 22:14 save; the exemption was granted via system Settings
      (confirmed: `dumpsys deviceidle` → `Whitelist user apps:
      dev.educoder.owntone_sync`; the in-app orange warning banner also
      disappeared, proving the app's own check now reads exempted).
    - Self-heal: the worker's own `scheduleNextSync()` (BackgroundSync-
      Worker.kt:926) does NOT call setExpedited, so any completed manual
      sync re-establishes the chain. Note the two paths are inconsistent:
      MainActivity schedules "today if unpassed, else tomorrow"; the
      worker always schedules "tomorrow HH:MM" (+1 day, worker line 947).
  - Fix (suggested): drop the `setExpedited` call from
    `registerBackgroundSync()` (the worker path proves plain
    setInitialDelay works), or only set expedited when delayMillis is 0.

  DEFECT-1 (carried from the earlier session, closed as observed):
  - Sync view reverts to the selection screen ~2-2.5 s before worker
    completion on one long sync (evidence: sec_15 frame pixel-identical to
    idle selection screen except a 38-row strip; no mid-sync listener
    detach/attach; no cancelSync; no endOfStream/error ever called in
    SyncProgressBroadcaster.kt; correlated binder buffer exhaustion at
    15:19:53.668 from per-chunk setForeground notification spam).
    Intermittent (a 67 s sync completed cleanly). Data is safe (worker
    writes files + DB directly). Mechanism unprovable in release (Dart
    logs stripped) — recorded as observed defect, not as a verified
    mechanism.

  Free data points:
  - First-playback start < 1 s on LAN: tap 16:37:30.3 → first PLAYING
    sample ~16:37:31 at position 425 ms.
  - MediaSession position pushes are sparse (~50 s app-pushed snapshots;
    the system extrapolates between them).
  - No list-painting wedges observed on hardware in any list scrolling
    (invariant 32 remains emulator-only).
  - After every rating-sheet commit the list reloads and scrolls to top
    (scroll position not preserved) — UX observation.
  - Rate-sheet star rendering: stars render as thin gray outline blobs
    (4 of 5 visible, no amber fill even when a rating is set; the widget
    row extends past the right screen edge). State/commits are exact; this
    is a rendering defect in the release build on this device.

NOT VERIFIED — implemented but not exercised, and why
  - 7B-1 physical AVRCP/button events: no BT controller (headset/car
    stereo) available; the paired device is an A2DP sink and cannot send
    media-key events. The transport path underneath is verified (7B-1
    entry above); only the physical button edge is unexercised.
  - 7B-3 non-supported configuration (no battery-optimization exemption
    → Doze deferral to maintenance window): untestable while the
    exemption is active; would require revoking it and re-arming an
    overnight run.
  - §7 step 5 lock-screen UI: keyguard is not exposed to uiautomator on
    this build (dump returns the shade fallback), and lock-screen
    screen-off timing was not controllable via adb input. Transport
    commands verified via the equivalent MediaSession path instead.
  - §7 steps 7 (shuffle), 8 (repeat), 11 (sync while playing): not
    re-run on hardware this pass; verified on the emulator in earlier
    phases (shuffle: phase5-report; repeat + restore: phase7-report).
    No device-specific factors expected in those paths, but they were not
    part of this pass's evidence.
  - §7 step 10 in-playback skip-notice (A9): verified on the emulator in
    phase 7. On hardware this pass, the deleted files were re-downloaded
    by sync before any playback could encounter them (771 remained
    missing as an orphan — see UNKNOWN), so the on-device A9 skip path
    was not exercised.
  - Audio actually heard: all playback evidence is position/session-
    based; the harness cannot hear the speaker.

DEVIATIONS — anything not done as the spec says
  - §7 specifies `flutter run -d emulator-5554` (debug) by hand; this
    pass ran the `--release` build on a physical Pixel 6, driven via
    adb/uiautomator. That is the point of the hardware gate (release
    artifacts only exist there), but it is a deviation from the script's
    stated method.
  - `cmd media_session dispatch` used as the stand-in for lock-screen /
    BT buttons (same MediaSession IPC path; documented per action).
  - Deep-Doze configuration achieved with `dumpsys battery unplug`
    (software state; physical charger remained attached) + natural idle;
    restored with `dumpsys battery reset`. No `deviceidle force-idle`
    needed.
  - Schedule set to 00:05 (test artifact) and restored to Disabled
    (the user's original state) after the run; all sync jobs cancelled
    and verified absent.
  - 7B-2 used a speaker (A2DP sink) rather than "headphones"/headset —
    the spec's own trigger ("disconnecting BT pauses playback") was met.

BUILD
  flutter analyze: No issues found (re-run this morning, Oct 2 ~11:50).
  flutter build apk --release: succeeded; the resulting APK is the one
  installed on the device for the entire pass. No code was modified in
  this pass (test/verification only), so no new warnings could be
  introduced.

UNKNOWN — behaviour I could not explain
  - DEFECT-1 mechanism (sync-view early revert): binder exhaustion
    correlates, but the exact Dart-side event that flipped isSyncing off
    is not observable in the release build.
  - Fire (771) is now a local orphan: DB row present, file absent (server
    removed it from Brass). Orphan cleanup only runs if the delete-
    orphaned-files option is enabled. Not a defect per invariant 27, but
    the album queue will hit the A9 missing-file path if played.
  - The 21:53 `SensorReceiverBase` log line (PID 23432) is not from this
    app (class absent from our just_audio 0.10.6; app process was PID
    7987 with 17 h uptime). Attributed to another media app on the
    user's phone.
  - `dumpsys jobscheduler` "Minimum latency" for the sync job printed the
    same relative value across dumps 15 s apart (frozen/cached display).
    Cosmetic in the dump; absolute fire time was anchored on the worker's
    own log line instead.

Side effects on live user data (disclosed)
  - Playback events from testing, all legitimately uploaded via syncs:
    +1 play each on 771, 773, 768, 770, 754, 753, 749, 748, 757; +1 skip
    on 777 (in-app Next) and 755 (transport next). Track 766 was played
    45.3 s → 104.9 s during the 7B-2 test and left paused — no completion,
    so no play event yet; it will add one play when it eventually finishes.
  - Ratings: all five test ratings restored before any sync; server
    re-verified this morning at originals (40/40/60/60/60).
  - Server drift (other users): Soul 48→38→37→39 (two new tracks added
    overnight-adjacent: "It's Too Late", "Funky Broadway", auto-
    downloaded by the 21:44 sync); 771 removed from Brass.
  - Device left in the user's original state: schedule Disabled, battery
    spoof reset (AC true), no pending jobs, BT speaker reconnected,
    playback paused on 766 at 1:44, 142 files on disk, screen locked.

§8 DEFINITION OF DONE — walkthrough
  - Every P0 MUST verified on emulator-5554, and the three §7B checks on
    a physical phone: P0s were verified in prior phases (phase5-8
    reports); §7B on phone: 7B-2 PASS, 7B-3 PASS (supported config),
    7B-1 PARTIAL (transport path verified; physical button edge not
    exercisable without a BT controller).
  - flutter analyze 0 errors / 0 warnings: YES (re-run this pass).
  - flutter build apk --release succeeds: YES (this pass).
  - No MediaNotificationListener references (D4): verified in phase 8;
    no code changed since.
  - No missing pubspec assets: verified in prior phases; no code changed
    since.
  - Acceptance script §7 passes in one sitting without a restart: YES on
    the device, with the documented partials (step 5 lock-screen UI,
    7B-1 button edge) and steps 7/8/11 covered by the emulator phases.

Defects to carry forward
  - DEFECT-1 (sync-view early revert, binder-correlated, intermittent) —
    observed, mechanism unprovable in release; data safe.
  - DEFECT-2 (schedule save enqueues nothing on Android 12+; "Expedited
    jobs cannot be delayed"; success snackbar misleading) — deterministic,
    reproducible, root-caused; suggested fix above.
  - Rate-sheet star rendering (gray outline blobs, no amber fill, row
    overflows right edge) — visual, release build, this device; state
    handling is exact.
  - List scrolls to top after each rating-sheet commit — UX.
