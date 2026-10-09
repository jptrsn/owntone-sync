# PHASE U1: COMPLETE

The four-state connectivity model (`unconfigured` / `reachable` / `offline` /
`unreachable`) replaces `_lastError` as what the UI reads. Failure
classification is a pure function of exception type + errno. Per-state
presentation follows the spec table; the drawer carries "Last synced"; the
Sync screen is de-duplicated to one state-driven banner.

## Changes

- `lib/utils/connectivity_state.dart` (new): `ConnectivityState` enum,
  `classifySyncFailure(Object)` (pure: type + `OSError.errorCode` only, never
  message text), `describeUnreachable(url)` (reuses U0's
  `parseServerUrlIdentity`).
- `test/connectivity_state_test.dart` (new): 17 unit tests, each citing the
  behaviour it guards (incl. "lying message" cases where the errno and the
  text disagree — the errno wins).
- `lib/presentation/providers/sync_provider.dart`: `_connectivity` +
  `connectivityState`; `lastSync` + `_loadLastSync()` (init and every sync
  completion); `fetchPlaylists()` classifies failures; `clearError()` acts
  only on `unreachable`; `setServerUrl()` resets to the unverified state;
  sync completion sets `reachable` on success/partial, failed/cancelled runs
  keep state (message log/History only); `startSync()` returns
  `Future<String?>`; `_isOnline` removed.
- `lib/presentation/screens/library_screen.dart`: unreachable-only persistent
  banner (human sentence naming the host, Retry → `fetchPlaylists`, no
  dismiss); per-state app-bar icon (`cloud_off` + red dot / `cloud_done` /
  `cloud_outlined`); the raw-error banner is gone.
- `lib/presentation/widgets/app_drawer.dart`: "Last synced Xm ago" header
  line; "Sync now" surfaces the `startSync` reason as a snackbar.
- `lib/presentation/screens/sync_screen.dart`: one state-driven banner
  (offline → "Offline - showing cached playlists" while a cache is shown;
  unreachable → the human sentence); the red footer, raw error text and raw
  refresh snackbar are gone; row styling keys on reachability.

## Verification — all four states, on a device

GO/NO-GO CHECK
  What it was: the `offline` airplane-mode acceptance test — cold start: no
  red, no banner, no badge, nothing; every screen browsable; playback
  starts, seeks, auto-advances; force-stop and relaunch: still nothing. Plus
  the closing check: states 2 and 3 visibly different without reading an
  errno.
  Did you run it:        YES
  What you observed: cold start in airplane mode logged
  `SocketException … errno = 101 … (state: ConnectivityState.offline)` and
  rendered zero indication anywhere (no banner, no error string in
  semantics, 0 red pixels in the app-bar icon zone by pixel count). All four
  tabs and Search browsed the cached library. A track played
  (`PLAYING`, position 26520 → 52591 → 78688), a slider tap seeked
  (78902 → 94072), and playback auto-advanced to the next track. Force-stop +
  relaunch (new PID): still nothing. The unreachable state, induced the same
  session, showed a persistent banner + solid red badge on the identical
  screen — the two states are visibly different without an errno.

OBSERVED — things I did and saw, on the emulator, by hand

- Cold start against the real server → logcat `Fetched 13 playlists from
  server`; app-bar icon tooltip "Sync" (quiet); no banner; drawer "Last
  synced 3h ago". (state 1: reachable)
- Airplane mode + force-stop + cold start → the acceptance test above, plus
  logcat line `errno = 101 … (state: ConnectivityState.offline)`.
  (state 2: offline)
- Server screen → `http://127.0.0.1:3689` ("Different server?" → Keep
  library) → cold start → logcat `errno = 111 …
  (state: ConnectivityState.unreachable)` — the same exception's message
  text reported `port = 44430` / `48998` (wrong, user had configured 3689)
  yet the state classified correctly: live proof the classifier reads the
  errno, not the text. UI: persistent banner "Can't reach 127.0.0.1 - is
  your server running?" with Retry; solid red badge (100/100 px cluster at
  1214,208); tooltip = the human sentence. Retry re-fetched, re-classified,
  banner persisted. Restored `http://192.168.1.13:3689` (Keep library) →
  banner cleared on save; cold start → "Fetched 13 playlists", quiet "Sync"
  tooltip. (state 3: unreachable)
- `pm clear` → cold start → no red anywhere (zero error strings in
  semantics; 0 red clusters in the icon zone); neutral setup icon, tooltip
  "Set up sync"; empty state "No Music Synced / Set up sync"; drawer
  "Server not configured" with no last-synced line; logcat "Fetch playlists
  skipped - server URL not configured". The system notification prompt on
  first launch is pre-existing behaviour (deferring it is U3's).
  (state 4: unconfigured)
- Sync screen with 0 playlists selected, tapped Sync → snackbar "Select at
  least one playlist to sync"; logcat "Sync not started - no playlists
  selected"; no sync ran, no History row written. (startSync refusal path)
- Fresh install, saved a server URL → Sync screen showed "Server URL: …" +
  "Load Playlists" with **no** "Offline - showing cached playlists" banner.
  The pre-fix build showed that banner in this exact state — a false claim,
  nothing being cached. (the banner fix, DEVIATIONS)
- Restore: re-granted storage + SAF (Music folder), saved the URL, Load
  Playlists (13), selected Brass only, Sync → "Sync completed with status:
  success"; 33 files in `/sdcard/Music/tracks`; drawer "Last synced 10m
  ago"; Library populated (Brass, 33 tracks); quiet "Sync" tooltip; no
  banner.

NOT VERIFIED — implemented but not exercised, and why

- Scheduled (WorkManager) sync runs driving the state transition — only
  manual runs were exercised; the completion handler is the same code path
  for both (identical event stream), but no scheduled run was waited out in
  this phase.
- `partial` status → `reachable` — only `success` was observed; the branch
  is adjacent in code (`sync_provider.dart` sync-complete handler).
- `unreachable` via timeout (errno 110) — device induction produced
  ECONNREFUSED (111) only; the 110/`TimeoutException` branch is covered by
  the unit tests.
- DNS/VPN-class failure classification — cannot be induced without touching
  server-side config or device networking beyond airplane mode; the
  unknown → `offline` branch is covered by unit tests.

DEVIATIONS — anything not done as the phase specified

- The Sync-screen offline banner renders only while `availablePlaylists` is
  non-empty. The spec table says offline → "one state-driven banner", but
  the banner's wording ("showing cached playlists") is a claim about the
  list shown — false right after saving a URL (unverified, nothing cached),
  and observed as a false banner during verification. Kept per user decision
  at the time; encoded as invariant 41.
- Final device state holds **Brass only (33 tracks)** instead of the prior
  Brass + Soul (93): the 6 GB partition was 92 % full, and the user directed
  a smaller collection for further work. The previously synced files in
  `/sdcard/Music` were deleted (user-approved) and Brass re-downloaded.
- Device serial: most of the session ran on `emulator-5554`; when another
  session's AVD (`RemoteDev_API_36`) came up it took 5554 and mine moved to
  `emulator-5556`. All four states, the banner fix and the restore were
  verified on the same AVD (`Pixel_9_Pro_API_36`) across the serial change.
- A cold boot surfaced a GMS "Sign in with ease" overlay that owned the top
  window; backed out to the launcher and relaunched the app. No effect on
  app state.
- The carried airplane-mode process-death watch (backlog, from U0) did not
  recur: every PID change this phase was a deliberate force-stop, and the
  airplane-mode cycles ran clean.

BUILD
  flutter analyze: No issues found! (the two new files included)
  flutter test: All 72 tests passed (55 pre-existing + 17 new)
  flutter build apk --debug: built `app-debug.apk` (installed and exercised
  on-device)
  Kotlin: `./gradlew :app:testDebugUnitTest` with JDK 17 (Zulu) —
  BUILD SUCCESSFUL

UNKNOWN — behaviour I could not explain

- uiautomator dumps intermittently return zero text on this emulator
  (Impeller GLES backend): a dump with no content-descs is not evidence of
  an empty screen. Cost ~20 minutes of confusion before cross-checking with
  a second instrument. Now invariant 42.
- A failed streamed install on a full partition left the app uninstalled
  (`pm path` empty after `INSTALL_FAILED_INSUFFICIENT_STORAGE`): the failure
  is not atomic. Now invariant 42.
- A stable diagonal band of red pixels in the top-right of every screencap
  is a GPU artefact (present in pre-U1 baselines too) — nearly misread as a
  badge; a real badge is a dense solid cluster plus a semantics tooltip.
  Now invariant 42.
