---
name: refresh-site-screenshots
description: Use when asked to refresh, regenerate, or re-shoot the six site
  screenshots in site/assets/screenshots/ (playlist-detail, album-detail,
  artist-detail, search, now-playing, queue). Session-driven capture from the
  HEAD build on the dedicated AVD, not a standalone script.
---

# Refresh site screenshots

Regenerates the six PNGs on the marketing site by driving the real app on the
project AVD. A script was tried and abandoned: media availability, server
state, SAF dialogs, and lazy-list rendering make it brittle. A session drives
it, observing at every step. **A human reviews the images — the agent has no
vision; content-desc assertions prove the right screen rendered, not that it
looks good.**

## Constraints

MUST
- Drive UI only from the **HEAD build** (`flutter run --profile` installs it —
  verify `dumpsys package … versionName` equals pubspec after launch; the
  stale 0.2.0 on the AVD once produced silently-stale shots).
- Use the `OwnTone_U2_API_36` AVD and **only its own PIDs**; enumerate
  `adb devices` first and never touch `emulator-5554`, `emulator-5558`, or any
  physical device — other sessions own them. Kill what you started at the end.
- Before playback: mute emulator music (`cmd media_session volume --stream 3
  --set 0`), record the track's server counts (`GET
  /api/library/playlists/11/tracks`, match title), pause **within ~2 s** (under
  the A9 threshold → no event queued), then verify the sync screen still says
  `No playback events waiting to sync` and counts are unchanged.
- `adb logcat -c` before waiting for `Background sync completed` (plain
  `logcat -d` matches old history).
- Read the server at `http://192.168.1.13:3689` **read-only**, API paths under
  `/api/*` (not `/json/*`).
- Tear down: kill `flutter run` + your emulator PID, `git checkout --
  pubspec.yaml pubspec.lock`, `rm test/driver_main.dart`.

MUST NOT
- Tap a playlist row in **SyncScreen's** picker — it toggles selection and can
  unsync (deletes tracks). Verify `1 playlists selected` right before tapping
  the Sync button, and never after a sync has completed.
- Trust `uiautomator dump` on Flutter screens for text: it is flaky and often
  exposes **content-desc only** (with `&#10;` entities — html-unescape).
  Use the driver's own `waitFor` for gating assertions.
- Use `flutter-agent-lens` `widget`/`hot_restart` on profile builds —
  `ext.flutter.inspector`/`reassemble` do not exist there; relaunch
  `flutter run` for a clean state instead.

## Workflow

1. Boot AVD; prep: `cmd notification set_dnd on`, animation scales 0,
   `pm grant dev.educoder.owntone_sync android.permission.READ_MEDIA_AUDIO
   POST_NOTIFICATIONS`.
2. Temp driver entry: add `flutter_driver: {sdk: flutter}` to
   `dev_dependencies`, create `test/driver_main.dart`
   (`enableFlutterDriverExtension(); app.main();`), `flutter pub get`.
3. `flutter run --profile -d <serial> -t test/driver_main.dart` in background,
   log to file; extract VM URI (`http://127.0.0.1:PORT/…/` → `ws://`) once
   printed. Check `versionName` matches pubspec.
4. First run of a wiped app: complete setup via driver + uiautomator
   (server URL `http://192.168.1.13:3689`, `Grant Permission` → `Allow` →
   `USE THIS FOLDER` → `ALLOW`), then `Load Playlists` → tap `Brass` →
   verify `1 playlists selected` → Descendant-tap the ElevatedButton `Sync` →
   wait for `Background sync completed` in fresh logcat (33 tracks).
5. Capture the six screens per `references/screens.md` — every screen is
   gated by driver `waitFor`s and a uiautomator content-desc assertion
   **before** `adb exec-out screencap -p`.
6. Verify: each PNG is device size (`wm size`, 1280x2856 here) and > 40 KB;
   `now-playing.png` ≈ 140 KB indicates artwork rendered (~80 KB = missing
   artwork — pick a track whose album showed artwork).
7. Tear down (above), then ask the human to eyeball the PNGs; write the report
   to `.agent/reports/` per verification-protocol §6.

## References

- `references/driver.md` — raw RPC client source, exact command JSON, and the
  verified command/founder quirks (ByType `type` key, Descendant nested finders
  as JSON strings, swipe-loop instead of scrollUntilVisible, enter_text rules).
- `references/screens.md` — per-screen navigation steps, exact waitFor strings,
  and pre-capture assertions.
