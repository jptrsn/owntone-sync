# PHASE U4: COMPLETE

Reframe, presentation-only: the app is named **Owntone Player** in every
release-facing surface (launcher label, MaterialApp title, drawer header,
About, pubspec description, F-Droid metadata, site/, README, release.sh,
feature graphics), the drawer is **Sync / History / Settings + a status
header** (Server, Storage, Schedule and About collapsed into a new Settings
destination), About's version now comes **from the package** (0.2.0, not the
stale "0.1.8" literal), and the empty state + About description read
**player-first**. No behaviour change: every navigation target keeps its
screen, logic, and state; the only new interactive element is the drawer's
server line, which is a tap target for the existing Server screen.

## GO/NO-GO CHECK

What it was: the phase's Verify block — visual pass per screen on device, no
behaviour change, `flutter analyze` and `flutter test` green (the static
guards are the backstop for anything that accidentally touches a guarded
file).
Did you run it:        YES
What you observed:

- Full visual pass on `emulator-5554` (AVD `OwnTone_U2_API_36`, launched
  windowed per the device plan, app left in its configured state —
  `http://192.168.1.13:3689` + Brass, 33 tracks; no `pm clear`), with an
  attached `flutter run` console for the whole session. Zero `E/flutter`
  lines from first launch through the end (invariant 29).
- **Library (reachable):** app bar "Library" + the quiet "Sync" icon
  (tooltip "Sync" = reachable), four tabs, "Brass / 33 tracks", no banner —
  the baseline is unchanged by the reframe.
- **Drawer (new shape):** header "Owntone Player" / "192.168.1.13:3689" /
  "Last synced 6h ago"; items Sync, History, Settings; divider; "Sync now"
  (enabled). No "Server not responding" line in `reachable` (it renders
  only in `unreachable`), no offline line at all (settled decision 3).
- **Drawer server line tap:** tapping "192.168.1.13:3689" opened the Server
  screen (URL pre-filled, Test connection present) — the URL is a tap
  target, not a headline.
- **Settings (new screen):** rendered with live subtitles —
  "Server / http://192.168.1.13:3689", "Storage / Folder access granted",
  "Schedule / Background sync", "About". Each of the four destinations
  opened and returned to it: Storage ("Music folder / Folder access granted
  / Change folder"), Schedule (full schedule screen, Enable disabled,
  02:00, days, conditions), Server (same screen as the drawer tap), About.
- **About (renamed + version from package):** "Owntone Player" /
  **"Version 0.2.0"** (read from the Android package via the new
  `getAppVersion` channel — the hard-coded "0.1.8" is gone) / "Your OwnTone
  library on your phone - synced home, played anywhere." / the server card.
- **Launcher label:** after the host-level ANR forced a launcher restart
  mid-pass, the launcher's dock showed the predicted app as
  **"Owntone Player"** — the renamed manifest label, live on device
  (independently, `dumpsys package` reports `versionName=0.2.0`).
- **History (from the drawer):** opened, shows the two "Sync Completed"
  rows from the U3 session.
- **Configured deep path unchanged:** app-bar sync icon → Sync screen
  straight to playlist selection ("1 playlists selected", Brass checked,
  Sync Options collapsed, no offline banner).
- **Mini player on the new screen:** played "House Party" from the Brass
  detail → mini player docked on Library (Pause/Next) → drawer → Settings
  **while playing: the mini player is docked on Settings** (title, artist,
  progress, Pause, Next) — the PlayerScaffold wrap (invariant 16) holds on
  the regroup's new destination. Returned to Library and paused (the button
  read "Play").
- Static guards: the rename added a guard to `test/static_guards_test.dart`
  (the old name "OwnTone Sync" must not reappear in lib/); all four
  pre-existing guards still pass. No guarded file was touched in a way that
  changes a guarded token.

## OBSERVED — things I did and saw, on the emulator, by hand

- `adb devices` empty (the foreign `RemoteDev_API_36` AVD was not running) →
  launched `OwnTone_U2_API_36` windowed; it took **emulator-5554** (the plan
  expected 5556 — the serial is whichever is free). Confirmed via
  `lsof -p <qemu-pid> | grep avd` that the serial is my AVD (invariant 42)
  before touching anything.
- `flutter run -d emulator-5554` (console → `/tmp/owntone_verify/u4_run.log`)
  → app launched on the configured state; Library rendered as the baseline
  above. Two host-level ANR dialogs interrupted the pass ("Pixel Launcher
  isn't responding", then "System UI isn't responding"); both dismissed
  with "Close app", the pass continued, and the Flutter console stayed
  attached throughout — this was the emulated system, not the app.
- Opened the drawer (tap on the navigation handle) → saw the new header
  ("Owntone Player" / "192.168.1.13:3689" / "Last synced 6h ago") and the
  three items + Sync now.
- Tapped the "192.168.1.13:3689" line in the drawer header → Server
  Configuration opened with the saved URL and the Test-connection button.
- Drawer → Settings → saw the four grouped rows with live subtitles; opened
  and returned from Storage, Schedule, Server and About in turn.
- On About: saw "Owntone Player", "Version 0.2.0" (not 0.1.8), the new
  description, and the server card.
- Drawer → History → saw the two "Sync Completed" rows from U3.
- App-bar sync icon → Sync screen opened directly on playlist selection
  ("1 playlists selected", Brass checked) — the configured deep path.
- Library → Brass → tapped "House Party" → playback started (position
  advanced; the Library mini player showed Pause/Next); drawer → Settings
  while playing → the mini player was docked on the Settings screen
  (House Party / Thundersmack, progress, Pause, Next); back to Library,
  tapped the mini player button → paused (button read "Play").
- `dumpsys package dev.educoder.owntone_sync` → `versionName=0.2.0`.
- The Pixel launcher's dock after the ANR restart showed the app as
  "Predicted app: Owntone Player" (renamed launcher label).
- `adb -s emulator-5554 emu kill` → "OK: killing emulator, bye bye";
  `adb devices` empty; only the AVD I started was killed.

## NOT VERIFIED — implemented but not exercised, and why

- **The empty-state wording ("No music yet" / "Connect your server and
  sync a playlist to start listening.")** — the device was left in its
  configured state per the plan (no `pm clear`), so the empty state did not
  render. The change is copy-only in `library_screen.dart`'s existing
  empty-state branch; the U3 pass exercised that exact branch with the old
  copy.
- **The drawer's "Server not responding" line** — renders only in
  `unreachable`; producing that state on a configured device requires
  changing the live URL (e.g. a closed port) and restoring it, which is a
  behaviour/state change beyond a presentation pass. The condition is U1's
  device-verified `unreachable` classification (invariants 39–41); U4 adds
  one line of text to the header, gated on the same `connectivityState`.
- **The "Not set up yet" header line** — renders only in `unconfigured`
  (requires `pm clear`); same reason.
- **The site/ and F-Droid metadata edits** — these are plain-text/HTML/SVG
  files that ship as-is; I verified the replacements by re-scanning the
  tree (no "OwnTone Sync" remains outside the deliberate exceptions: the
  `changelogs/18.txt` historical release note, the LICENSE header line, and
  the guard test's own search string), but did not render the F-Droid page
  or the website.
- **`partial`-status syncs and the `offline` drawer** — no sync was
  triggered during the pass (presentation-only phase; a sync would write
  History rows on the user's real library). The guard that disables
  "Sync now" in verified-offline is U2's, unchanged.

## DEVIATIONS — anything not done as the phase specified

- **The AVD took emulator-5554, not the planned 5556.** The foreign
  `RemoteDev_API_36` AVD was not running when I launched (pre-launch
  `adb devices` was empty), so 5554 was free. Identity was confirmed per
  invariant 42 before any interaction; only my AVD was killed at the end.
- **A `git add -A` in the first commit (1c8bf37) swept in three unattended
  pipeline process files** (`overnight-pipeline.md`, `overnight-ledger.md`,
  `opencode.json`) that the pipeline definition says must never be
  committed. Fixed immediately with ecc6d10 (removed from the index; they
  are untracked again). No feature content was affected; the mistake and
  its fix are recorded here and in the ledger rather than rewritten away.
- **The rename reached four surfaces the phase block does not name**
  (F-Droid `AutoName`, `release.sh`'s release title/banners, the root
  `assets/feature_graphic.svg`, the README heading), plus the README's
  drawer paths, which the regroup made stale. All are release-facing
  name surfaces — leaving them on the old name would desync the next
  release from the binary. The package id, the repo name, `APK_PREFIX`,
  and the historical `changelogs/18.txt` / LICENSE line were deliberately
  not touched.

## BUILD

  flutter analyze:
    No issues found!
  flutter test:
    All 117 tests passed (112 pre-existing + 1 new rename guard in
    static_guards_test.dart + 4 new AppDrawer.serverAddress tests in
    app_drawer_test.dart)
  flutter build apk --debug:
    Built build/app/outputs/flutter-apk/app-debug.apk (installed and
    exercised on-device)
  Kotlin:
    ./gradlew :app:testDebugUnitTest (JDK 17): BUILD SUCCESSFUL —
    MainActivity.kt gained the getAppVersion channel method.

## UNKNOWN — behaviour I could not explain

- **Two host-level ANR dialogs (Pixel Launcher, then System UI)** wedged the
  emulated system mid-pass and were dismissed with "Close app". Cause
  unknown — the windowed swiftshader emulator under host load; the Flutter
  console stayed attached and clean throughout, and the app process was
  never the subject of an ANR, so this did not affect the app-side
  evidence. Noted per protocol §2 rather than attributed.
- **Why the implicit `getPackageInfo(packageName, 0)` in MainActivity
  failed to compile** ("Unresolved reference") while the explicit
  `applicationContext.packageManager.getPackageInfo(packageName, 0)` form
  compiled: I did not dig into the Kotlin receiver/overload resolution;
  the shipped code uses the explicit, canonical form and passes the
  device check.
