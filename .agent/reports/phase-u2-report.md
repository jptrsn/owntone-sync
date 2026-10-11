# PHASE U2: COMPLETE

The six drawer destinations are wrapped in `PlayerScaffold`, so the docked
mini player survives navigating to each — visible while a track plays,
zero-height at idle. A completed fetch probe that classified `offline` now
disables the manual sync: the Sync button and the drawer's "Sync now" go
disabled with the helper sentence "You're offline - syncs when you're home",
and the guarded `startSync()` refuses before any worker run is enqueued, so
no History row is written for the normal away-from-LAN condition.
`unreachable` is untouched: a real fault keeps its working manual retry, and
the failure it writes is a record of that fault, exactly as before.

## Decisions (made before writing the offline guard, per the task)

### D1 — the guard keys on a *probed* offline, not the raw state

The spec's build item says "in state `offline`, disable Sync". Read literally,
the guard is `state == ConnectivityState.offline`. I did not build that. The
guard is `state == offline && lastProbeResult == offline`, where
`lastProbeResult` is the classification of the last `fetchPlaylists` that
**completed** against the current address (`null` while unverified; nulled by
`setServerUrl`).

Why: the `unverified` window — immediately after saving a URL (the save drops
state to unverified, invariant 40) and before the cold-start fetch resolves —
is also state `offline`. A literal guard would disable the Sync button there,
which is (a) asserting a fault no probe has established (invariant 39's
unknown rule: what cannot be proven is not asserted) and (b) disabling the
one control the retry→save recovery flow (invariant 40) needs to work: the
user saves the corrected URL and the natural next step is *tap Sync*. It would
also flash-disable on every online cold start, for the length of the fetch.
Verified on device both ways: probed-offline disables (GO/NO-GO 2), and the
unverified window after a save leaves the button enabled, with a tap that
proceeds and succeeds (GO/NO-GO 4).

### D2 — a stale `reachable` does not block

blockers.md 2026-10-10 (open): a worker completion for a run started against
the *previous* server can complete after a save and mark the new host
`reachable`. The guard deliberately does not fence that write: a run can only
reach that completion path if it **reached a server**, so a route existed at
some point during the current session; at worst the manual attempt fails for a
real reason, and that failure row is the same class of record the sanctioned
`unreachable` retry writes. The alternatives were rejected:
probe-before-sync adds up to the 10 s connect timeout to every sanctioned
`unreachable` retry (the very flow this phase must keep fast); fencing the
write needs the worker to stamp its URL into the completion event — a Kotlin
change, out of scope for a "small, low-risk, ships alone" phase. The blocker
stays OPEN; this report's NOT VERIFIED section notes the one mid-session
sequence it leaves unguarded.

## Changes

- `lib/utils/connectivity_state.dart`: `offlineSyncRefusal` const (the single
  user-facing sentence, shared by the control's helper text and the `startSync`
  refusal) and `shouldBlockManualSync(state, lastProbeResult)` — pure,
  `true` only for probed-offline, with the D1/D2 reasoning in its doc.
- `lib/presentation/providers/sync_provider.dart`: `_lastProbeResult`
  (written only by a completed `fetchPlaylists` — success → `reachable`,
  classified failure → the classification — and nulled by `setServerUrl`);
  `manualSyncBlocked` getter; `startSync()` checks the guard first and returns
  `offlineSyncRefusal` before any channel call (no enqueue, so no History row).
- `lib/presentation/screens/sync_screen.dart`: `Scaffold` → `PlayerScaffold`;
  the Sync `ElevatedButton` is disabled when `isSyncing || manualSyncBlocked`;
  the helper sentence renders under the "N playlists selected" row when
  blocked.
- `lib/presentation/widgets/app_drawer.dart`: "Sync now" `ListTile` gets
  `enabled: !manualSyncBlocked` and the helper sentence as its subtitle when
  blocked.
- `schedule_config_screen.dart`, `server_config_screen.dart`,
  `storage_screen.dart`, `history_screen.dart`, `about_screen.dart`:
  `Scaffold` → `PlayerScaffold` (import added each).
- `test/connectivity_state_test.dart`: 5 new tests for the pure guard
  (probed-offline blocks; unverified doesn't; stale reachable doesn't;
  unreachable keeps the attempt; unconfigured is setup, not refusal).
- `test/sync_provider_connectivity_test.dart`: 7 new provider tests (refusal
  happens before the channel is touched; unverified after a save doesn't
  refuse; a save after an offline probe returns to unverified; unreachable
  passes; a stale completion establishing reachable doesn't refuse; a stale
  completion after an offline probe doesn't re-arm the block; a successful
  fetch after an offline probe lifts it). A mock-channel flag
  (`triggerBackgroundSyncInvoked`) proves the refused start never reaches the
  worker.

## Verification — all of it on a device

GO/NO-GO CHECK
  What it was: (1) with a track playing, every drawer destination shows a
  visible and functional mini player; (2) airplane-mode Sync does nothing and
  writes no History row; (3) `unreachable` still permits a manual sync;
  (4) the D1 positive: the unverified window after a save keeps the Sync
  control enabled, and a tap from it proceeds and succeeds.
  Did you run it:        YES
  What you observed: (1) the mini player rendered on all six wrapped
  destinations (Sync, Schedule, Server, Storage, History, About); Next was
  exercised on five of them and advanced the track each time; Pause/Play
  round-tripped on About; the list's last row ended exactly at the mini
  player's top edge (y=2586 on the 2688-px-tall Sync screen — the layout
  inset, not an overlay). (2) An airplane-mode cold start classified
  `offline` (logcat `errno = 101 … (state: ConnectivityState.offline)`); the
  Sync button was `enabled=false` with the helper sentence, the drawer's
  "Sync now" was `enabled=false clickable=false` with the subtitle, no banner
  or red anywhere, and History kept exactly its one pre-existing row;
  playback resumed in airplane mode. (3) Pointing the app at
  `http://127.0.0.1:3689` (Keep library) classified `unreachable` (logcat
  `errno = 111`; the exception's message reported the wrong port, 36190 — the
  classifier read the errno, per invariant 39); the persistent banner and red
  badge showed, the Sync button stayed `enabled=true` with no helper text, a
  tap ran the worker to completion (`status=failed`, ECONNREFUSED, 0 tracks)
  and wrote the "Sync Failed … All 1 playlists failed to sync" row. (4)
  Restoring `http://192.168.1.13:3689` dropped to unverified; the Sync button
  was `enabled=true` with no helper text (the literal-state guard would have
  disabled it), and a tap from that state ran to success (3.3 s, 0 new
  tracks, 6 pending playback events uploaded) and wrote a third, successful
  History row.

OBSERVED — things I did and saw, on the emulator, by hand

- Dedicated AVD `OwnTone_U2_API_36` (google_apis API 36, `pixel_9_pro`),
  serial `emulator-5558`, run windowed. First-run flow: notification prompt
  allowed, audio permission granted, SAF `Music` folder granted, URL saved,
  Brass selected (33 tracks), Sync → success in ~50 s, 33 files in
  `/sdcard/Music/tracks`, Library populated, quiet "Sync" icon.
- GO/NO-GO 1 per destination: opened each wrapped destination with a track
  playing — mini player visible on all six; tapped Next on Sync, Schedule,
  Server, Storage and History (track advanced on each, title changed); tapped
  Pause then Play on About (state round-tripped). Idle check: cleared the
  queue from the Now Playing sheet → the mini player nodes disappeared
  entirely (zero height) and the body used the full height.
- GO/NO-GO 2 per detail: airplane mode + force-stop + cold start → logcat
  `errno = 101 … offline`; zero error strings in the semantics tree; Sync
  button `enabled=false` + "You're offline - syncs when you're home"; drawer
  tile `enabled=false clickable=false` + subtitle; a tap on each did nothing
  (no snackbar, no logcat "Sync not started", no worker event); History still
  1 row; tapping the mini player resumed playback (PLAYING, position advancing
  in logcat).
- GO/NO-GO 3 per detail: Server screen → `http://127.0.0.1:3689` → "Different
  server?" → Keep library → cold start → logcat `errno = 111 … unreachable`
  (message text said port 36190, configured was 3689 — classifier read the
  errno); banner "Can't reach 127.0.0.1 - is your server running?" + Retry +
  solid red badge; Sync button `enabled=true`, no helper text; tapped Sync →
  worker ran and completed `status=failed` (ECONNREFUSED, 0 tracks, ~1 min);
  History grew by exactly the failed row ("1 playlists • 0 tracks downloaded /
  All 1 playlists failed to sync") over the successful one.
- GO/NO-GO 4 per detail: Server → `http://192.168.1.13:3689` → Keep library →
  (no cold start — the unverified window persists until the next fetch
  resolves) → Sync screen: button `enabled=true`, no helper text, the orange
  "Offline - showing cached playlists" banner present and true (the list is
  the cache); tapped Sync → worker ran, `status=success` in 3314 ms, 0 tracks
  downloaded (all present), "6 events synced" in logcat; History's new top row
  "Sync Completed … 1 playlists • 0 tracks downloaded"; app-bar icon back to
  the quiet "Sync" tooltip (the success earned `reachable`, invariant 40).
- U1 carry-over, now closed: Server → `http://192.168.1.254:3689` (an
  unassigned LAN address — app-side change only) → Keep library → cold start →
  logcat `DioException [connection timeout]: … 0:00:10.000000 …
  (state: ConnectivityState.unreachable)` — a genuine 10-second connect
  timeout, the branch U1 could only pin in unit tests; banner named the host
  ("Can't reach 192.168.1.254 - is your server running?"); tapped Retry → a
  second 10 s timeout and the banner persisted (a fault worth retrying).
- Restore: `http://192.168.1.13:3689` → Keep library → cold start → logcat
  "Fetched 13 playlists from server"; no banner, no badge, quiet "Sync"
  tooltip; Brass 33 tracks intact in the library.
- Emulator killed after the session (user instruction; only
  `emulator-5554`/`5556` of other sessions remained).

NOT VERIFIED — implemented but not exercised, and why

- Scheduled (WorkManager) sync runs under the guard: the guard covers the
  manual start only (`startSync`), per the spec's build item ("disable Sync
  and 'Sync now'"). A scheduled run that fires while offline still reaches the
  worker and still writes a failed row — the same residual as before U2.
  Flagged as an adjacent observation, not fixed: it is the worker's domain
  and changing it is not "small, low-risk, ships alone".
- The belt-and-braces refusal path on-device: the disabled control means a
  UI tap can never reach `startSync()` while blocked, so the on-device
  evidence is the disabled state; that the refusal itself never enqueues is
  proven by the provider test (`triggerBackgroundSyncInvoked` stayed false on
  a refused start).
- The D2 mid-session sequence (save while an offline run is in flight,
  completion marks the new host `reachable`, manual sync from there) —
  constructible but contrived; the two stale-completion provider tests cover
  the state logic. The underlying defect is the open blockers.md entry.
- `partial` status interacting with the guard — the completion handler's
  `partial → reachable` write predates U2 and the guard only reads it; not
  exercised this phase (carried from U1's NOT VERIFIED).

DEVIATIONS — anything not done as the phase specified

- The guard keys on a probed-offline, not the literal state `offline` —
  decision D1 above, the load-bearing interpretation of build item 2.
- The emulator was run **windowed**, not headless: the user's instruction for
  this session (other sessions share the host's emulators, so a visible
  window and a dedicated serial were required). Invariant 42's recommended
  launch flags (`-no-window`) were intentionally not used; the AVD's data
  partition was shrunk 10 G → 8 G so it fit the host's free disk.
- Fresh first-run state: the dedicated AVD had no app data, so first-run
  setup (notification prompt, permissions, SAF, URL, playlist selection) was
  part of the session. The system notification prompt on first launch is
  pre-existing behaviour; deferring it is U3's.

BUILD
  flutter analyze: No issues found!
  flutter test: All 104 tests passed (92 pre-existing + 12 new)
  flutter build apk --debug: built `app-debug.apk` (installed and exercised
  on-device)
  Kotlin: not run — no Kotlin changes in this phase (the guard is pure Dart;
  D2's rejected alternative was the only Kotlin-affecting option)

UNKNOWN — behaviour I could not explain

- The first `flutter build apk --debug` of the session printed "3 warnings"
  (Gradle, no detail captured before the output scrolled); every subsequent
  build was clean. No action; noted so a future session doesn't re-investigate
  a non-repro.
- 76 occurrences of the debug assertion "Looking up a deactivated widget's
  ancestor is unsafe" in the session logcat, all from `sync_screen.dart`'s
  `dispose()` calling `context.read<SyncProvider>()` on every pop of the Sync
  screen. **Pre-existing at `main`** (verified against U1's head; U2 does not
  touch that code). It is debug-only (release builds skip the assertion) and
  benign in effect (the listener is removed), but it is a real wart: the
  reference should be captured in `initState` instead. Reported, not fixed —
  out of scope for U2.
- The classifier's `SocketException` message for `127.0.0.1:3689` reported
  port 36190 (the wrong port) while the classification was correct — the
  errno-never-the-text rule (invariant 39) doing its job; the message-port
  discrepancy itself (where dio/Android picks up a port that isn't the
  configured one) is unexplained and harmless to the state model.
