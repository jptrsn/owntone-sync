# PHASE U3: COMPLETE

First run is now setup, not failure: a single guided flow (server URL with a
test-connection step → folder grant → playlist selection → first sync),
active only while `unconfigured`. The example URL is a hint, not saveable
pre-filled text. The system notification prompt no longer opens the app —
it arrives when the first *successful* sync completes, the moment its
purpose becomes visible. Configured users are untouched: the deep paths
(drawer → Sync/Server, app-bar sync icon) behave exactly as before, because
the only reordering the phase makes is in the not-yet-configured case, where
the folder grant used to come before the user had a server to sync from.

All of the Verify block ran end-to-end on `emulator-5556`
(`OwnTone_U2_API_36`, launched windowed per the device plan), with an
attached `flutter run` console for the whole session — **zero `E/flutter`
lines** from first launch through the second sync (invariant 29).

## GO/NO-GO CHECK

What it was: the phase's Verify block — `pm clear` → no red anywhere in the
first screen → one continuous flow to a populated library; test-connection
reports right/wrong before save; notification prompt appears at first
successful sync, not at launch.
Did you run it:        YES
What you observed: every clause of it, in one unbroken session:

- `pm clear` → launch: **no notification prompt** (it does not open the app
  any more), no red anywhere — Library showed the neutral `cloud_outlined`
  "Set up sync" affordance and the "No Music Synced / [Set up sync]" empty
  state, no banner (the `unconfigured` state renders nothing, invariant 41).
- One continuous flow: "Set up sync" → Sync screen opens on the **URL step**
  ("Server Not Configured") — not the storage step → Server screen (field
  empty, example only as hint) → wrong URL + Test connection → red
  "Can't reach 192.168.1.13 - is your server running?" → correct URL +
  Test connection → green "Connected to 192.168.1.13" → Save → Sync screen
  advances to "Storage Permission Required" → audio-permission dialog
  (Allow) → SAF picker → "USE THIS FOLDER" → "Allow OwnTone Sync to access
  files in Music?" (ALLOW) → "Server URL: … / [Load Playlists]" (no stale
  red text) → Load Playlists → live 13-playlist list → Brass selected →
  Sync → first sync completes (status=success) → Library populates
  (Brass, 33 tracks) with **no restart**, quiet "Sync" icon.
- At the first successful sync — and not before — the system prompt
  "Allow OwnTone Sync to send you notifications?" appeared; allowed.
- A second successful sync (which also repaired 4 tracks the first run
  aborted, see DEVIATIONS) produced **no re-prompt**: the check-before-
  request makes it first-successful-sync only.

## OBSERVED — things I did and saw, on the emulator, by hand

- `pm clear dev.educoder.owntone_sync` → `flutter run -d emulator-5556`
  (debug, console to `/tmp/owntone_verify/u3_run.log`) → first screen: no
  permission dialog, no banner, no red; semantics tree shows "No Music
  Synced", "Sync some playlists to start browsing your music.", app-bar
  affordance tooltip "Set up sync" (the neutral unconfigured icon).
- Tapped "Set up sync" → Sync screen renders the URL step first ("Server
  Not Configured / Configure your OwnTone server URL to get started. /
  [Configure Server]") — before U3 the storage-permission step came first.
- Server screen: the `EditText` node has `text=""` (empty — not
  pre-filled); screencap pixel check found the hint glyphs in the field
  (3,425 text pixels in the interior crop, pure-white background otherwise).
- Wrong-URL probe: typed `http://192.168.1.13:9999` (closed port on the
  live host — refused, not a timeout), tapped "Test connection" → inline
  result "Can't reach 192.168.1.13 - is your server running?" at the
  result slot; pixel check: 6,332 red-ish text pixels + 468 red icon
  pixels (the scheme error colour — unreachable is the only red).
- Right-URL probe: replaced the field with `http://192.168.1.13:3689`
  (editing reset the previous verdict), tapped "Test connection" →
  "Connected to 192.168.1.13"; pixel check: 3,384 green-ish pixels. Note:
  the server answers this endpoint with HTTP 400 (verified with curl
  before the run — `/api/now-playing` is not in the current OwnTone JSON
  API); the probe still reports "right", because any HTTP answer proves a
  live server (invariant 44).
- Save → popped back to Sync, which now shows step 2: "Storage Permission
  Required / [Grant Permission]" — the folder step now follows the URL
  step.
- Grant: system dialog "Allow OwnTone Sync to access music and audio on
  this device?" → Allow → SAF picker (already at the Music folder, showing
  its `playlists`/`tracks` children) → "USE THIS FOLDER" → "Allow OwnTone
  Sync to access files in Music?" → ALLOW.
- Step 3: Sync screen shows "Server URL: http://192.168.1.13:3689 /
  [Load Playlists]" — **no stale "Server URL not configured" red text**
  under the button (the U1 fix held), no offline banner (unverified +
  empty list renders nothing, invariant 41).
- "Load Playlists" → live fetch (13 playlists: All Music, Brass, Five
  Stars, Holiday Music, Master, …); selected Brass → "1 playlists
  selected"; tapped Sync.
- First sync: worker log "Found 33 existing files in tracks directory"
  then "Need to download 33 tracks / 0 tracks already on device" (the
  download-skip keys on `synced_tracks` rows, which `pm clear` wiped —
  `BackgroundSyncWorker.kt:501-504`; same shape as the U2 fresh install) →
  4 tracks aborted mid-download with `SocketException: Software caused
  connection abort` (transient LAN; worker contained each: "Deleted
  partial file after error", continued) → "Background sync completed: 29
  tracks downloaded in 538689ms (status=success)".
- **The moment the completion was processed, the notification prompt
  appeared** ("Allow OwnTone Sync to send you notifications?") — it had
  not appeared at launch; allowed it.
- Back to Library: populated without restart — Playlists tab shows
  "Brass / 33 tracks", all four tabs present, app-bar icon the quiet
  "Sync" (the success earned `reachable`, invariant 40).
- Drawer (configured state): header "OwnTone / http://192.168.1.13:3689 /
  Last synced 2m ago"; all six destinations + "Sync now" intact.
- Server deep path: field shows the saved URL (`text="http://192.168.1.13:3689"`
  — a hint is not a value) and the Test-connection button is present.
- App-bar sync icon → Sync screen straight to playlist selection ("1
  playlists selected", Brass checked) — the configured deep path is
  unchanged by the reorder.
- Second sync from that view: "Background sync completed: 4 tracks
  downloaded in 156866ms (status=success)" — exactly the 4 the first run
  aborted; **no notification re-prompt**; History's top row "Sync
  Completed / 1 minute ago / 1 playlists • 4 tracks downloaded" with the
  "Manual" chip.
- Console for the whole session: 0 `E/flutter` lines.

## NOT VERIFIED — implemented but not exercised, and why

- The probe's `offline` wording branch ("No network route to that address
  - check your connection.", orange): the errno-101 shape is unit-tested
  (`server_probe_test.dart` → `isProbeSuccess` false → `failedOffline`),
  and the on-device refusal exercised the sibling `unreachable` branch of
  the same catch; the offline branch needs airplane mode with the Server
  screen open, which the AVD left before I set it up.
- Saving a URL the probe judged "wrong": by design Save is not gated on
  the probe (it reports, it does not block — the spec's "reports
  right/wrong before save"). Only the right-then-save path was exercised;
  saving a dead URL falls into the existing `unreachable` flow (U1),
  which is unchanged.
- `partial` also triggering the deferred prompt: the completion handler
  keys on `success` or `partial`; only `success` was device-exercised.
  A `partial` needs a playlist to fail, which I did not induce.
- The "Don't allow" notification path (re-prompt on the next successful
  sync): I allowed on device; the re-request semantics are the Android
  system's (a plain denial lets the next request ask again; a permanent
  denial short-circuits). The code just re-issues the request.

## DEVIATIONS — anything not done as the phase specified

- **The probe endpoint 400s on the user's OwnTone.** P5 names "a cheap
  `GET /api/now-playing` probe"; the current OwnTone JSON API docs have no
  `/api/now-playing` (the equivalent is `/api/queue?id=now_playing`), and
  the live server answers the spec-literal path with a 400 page. Because
  the verdict treats any HTTP answer as a live server, the spec-literal
  endpoint works as specified — I kept it and recorded the 400 as
  load-bearing in invariant 44, so nobody later "fixes" the probe to
  require a 2xx and marks every real server as wrong.
- The first sync re-downloaded all 33 tracks despite the files being on
  disk: expected consequence of `pm clear` (the download-skip reads
  `synced_tracks`, not the directory — `BackgroundSyncWorker.kt:501-504`).
  An adjacent observation, not U3's: a fresh install could re-adopt the
  existing files instead of re-downloading; left untouched (worker
  semantics are out of scope for this phase).
- The example URL text is unchanged (`http://192.168.1.100:3689`); only
  its role changed (pre-filled → hint). P7 (U4) reframes the copy.
- The emulator was run **windowed**, not headless: the device plan for
  this host (invariant 42's `-no-window` intentionally not used).

## BUILD

flutter analyze:
  No issues found!
flutter test:
  All 112 tests passed (104 pre-existing + 8 new in
  test/server_probe_test.dart)
flutter build apk --debug:
  Built build/app/outputs/flutter-apk/app-debug.apk (installed and
  exercised on-device)
Kotlin:
  not run — no Kotlin changes in this phase (the probe and the prompt
  deferral are pure Dart; the worker is untouched)

## UNKNOWN — behaviour I could not explain

- The 4 `SocketException: Software caused connection abort` failures
  mid-download (transient, self-contained, repaired by the next sync):
  consistent with the emulated LAN, but the exact trigger is not
  knowable from here. The worker's per-track containment did exactly what
  its design says; no app-side anomaly observed.
