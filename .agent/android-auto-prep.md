# Android Auto run — human prep (do before kickoff)

The overnight run (`.agent/overnight-android-auto.md`) is unattended:
anything interactive below must be done by a person, with the machine
available, **before** the kickoff prompt is pasted. Work top to bottom;
each box needs its result written in the line below it (the orchestrator
copies the sign-off into the ledger at Step 0).

## PAUSED (2026-10-24, user decision — low priority)

State of the world when parked. Re-verify devices before resuming; the
box list below is still the contract, this section is what is already
true and what the 10-24 session learned.

**The AVD was wiped mid-session (2026-10-24 ~20:15).** Both emulators
died at once; a `Pixel_9_Pro_API_36` instance then appeared with **clean
userdata** — most likely relaunched with `-wipe-data` from the emulator
UI / Android Studio (unconfirmed; the instance that did it is dead).
The `OwnTone_U2_API_36` instance is gone (the AVD is still on disk).
Resulting state: `Pixel_9_Pro_API_36` runs as **emulator-5554** (it took
slot 0 once the other instance died — re-confirm AVD↔serial per
invariant 42), with AA = the `/product` stub only, our app not
installed, no Brass in `/sdcard/Music`, Play presumably signed out
(unverified). Nothing is unrecoverable: the app builds from this repo,
the tracks re-sync from the server, the AA bundle is below.

**Verified working (do not redo):**

- DHU: `~/Library/Android/sdk/extras/google/auto/desktop-head-unit`,
  `2.0-mac-arm64` (build 2022-03-30-438482292), executable, runs.
- Server: `curl -s http://192.168.1.13:3689/api/queue` → 200 (10-23).
- AA bundle:
  `~/Downloads/com.google.android.projection.gearhead_17.9.664044-release-179664044_1arch_7dpi_24lang_bfb42d979d63c0c6e9df455edd6b11cd_apkmirror.com.apkm`
  (37,770,743 B; SHA-256
  `b28d839219448d7c7e6b35d7b856d9a9a22f55f893a180acee5df54324f94052`,
  SHA-1 `3f4e3527e645ff15a4542da8d51504b87eade9b7`, MD5
  `428bd6c6abf943dbf057a7670c772bf9` — all match APKMirror's published
  values; signer CN=Android, O=Google Inc.).
- The install path was exercised and works: `pm uninstall --user 0
  com.google.android.projection.gearhead` (the `/product` stub), then
  `adb install-multiple base.apk split_config.arm64_v8a.apk
  split_config.xxhdpi.apk split_config.en.apk` (AVD density is 480 →
  xxhdpi) → `versionName=17.9.664044-release`, codePath under
  `/data/app` (10-24). Re-extract the bundle from the `.apkm` when
  resuming (the temp extraction dir is volatile).

**Blocker found (why prep stalled):** the sideloaded AA app installs
but will not launch. The launcher alias
`com.google.android.gearhead.vanagon.VnLaunchPadActivity` is
`enabled="false"` in the manifest (Play flips it on at install time);
shell cannot enable it (Android 14 `SecurityException` on component
state); and its target `VnLaunchPadInternalActivity` (runs in the
`:projection` process) opens and exits silently in ~140 ms on every
entry point tried (direct launch, `LAUNCH_ANDROID_AUTO_PHONE` action) —
no crash, no log. Play itself refuses to install AA on this AVD
("isn't compatible with your device anymore"), so the documented route
(sign in to Play + install/update AA, per
`developer.android.com/training/cars/testing/dhu`) is closed on this
device.

**Workaround found (not yet exercised — test this first on resume):**
AA's settings are a registered system-Settings entry:
`companion.settings.DefaultSettingsActivity` is **exported** with
`android.intent.action.APPLICATION_PREFERENCES` and
`com.android.settings.action.SETTINGS` filters (confirmed in the
installed APK's manifest, 10-24; it is the same entry e.foundation's
DHU guide uses — Settings → search "Android Auto"). If it renders, it
reaches developer mode (Version ×10), Start head unit server, and
"Add new cars to Android Auto" **without the app icon ever working**.
The documented connection procedure (official DHU page, 10-24 capture)
is exactly §4: developer mode → start head unit server → "Add new
cars" → `adb forward tcp:5277 tcp:5277` → run `./desktop-head-unit`
(no `--usb`; tunnel mode) → accept ToS on the phone.

**Rebuild needed on resume (all recoverable):** Play sign-in (user),
`flutter install`, sync Brass from `http://192.168.1.13:3689` (the run
must not re-sync Soul), AA bundle install as above. Then §3 boxes 2–4
and the §4 rehearsal. Note for the rebuild: storage on this AVD was
~500 M free of a 6 G data partition before the wipe — with fresh
userdata there is headroom now, but the overnight run's footprint has
not been measured.

## 1. Clean the working tree (Step 0 hard-gates on this)

Current uncommitted state (as of 2026-10-23):

- `.ai-dlc/` (the Android Auto plan — 19 files) — **commit it** (it is the
  spec the run executes; the commit message should say it is the AA
  intent + units + reference docs).
- `.agent/overnight-android-auto.md` + this file — commit with it (or in a
  second commit; either is fine).
- Six modified `site/assets/screenshots/*.png` + untracked
  `.agent/reports/site-screenshots-refresh-report.md` — decide: commit
  (if the refresh is finished and wanted) or `git checkout --` / discard.
  The run does not care which, only that the tree is clean.

- [ ] `git status --short` is empty: ____________________

## 2. Desktop Head Unit (DHU) — installed (verified 2026-10-23)

- Installed 2026-10-23: SDK Tools package `extras;google;auto`, binary at
  `~/Library/Android/sdk/extras/google/auto/desktop-head-unit`
  (executable, with its `config/` and `voice/` directories beside it —
  the `libusb` library must stay next to the binary).
- Only if a fresh host is ever used instead: Android Studio → SDK Manager
  → **SDK Tools** → **Android Auto Desktop Head Unit Emulator** →
  install; the binary lands in `SDK_LOCATION/extras/google/auto/`;
  `chmod +x ./desktop-head-unit`.

- [ ] `./desktop-head-unit -v` prints a version: `2.0-mac-arm64`
  (build 2022-03-30-438482292), path
  `~/Library/Android/sdk/extras/google/auto/desktop-head-unit` — re-run on
  the machine the run uses and confirm (the orchestrator needs both at
  Step 0)

## 3. Phone side: `Pixel_9_Pro_API_36` (Play image)

Designated 2026-10-23: the Android Auto app needs a GMS + Play Store
image, so the previous designation (`OwnTone_U2_API_36`, a `google_apis`
image) is dropped for this run. Fallback: `Pixel_9_API_35` (also a Play
image, API 35).

Launch `Pixel_9_Pro_API_36` (windowed, as on this host). Its adb serial
is launch-time — record it from `adb devices` (it will be `emulator-5554`
or `emulator-5556` depending on what else is running; confirm
AVD↔serial identity per invariant 42). Then:

1. **Android Auto app** installed and updated. Preferred: Play Store
   (requires a signed-in Google account on the AVD — if the AVD has no
   Play sign-in, sign in now; this is the one step that cannot be
   automated). Fallback: sideload the Android Auto APK via
   `adb -s <serial> install com.google.android.projection.gearhead-*.apk`
   (record where the APK came from).
2. **Developer mode in Android Auto:** Settings → About → tap **Version**
   10 times → Allow development settings. (Lets our sideloaded debug
   build appear in the car UI — without it the whole run fails at AA-U1
   A1.)
3. **AA Settings → "Previously connected cars" → enable "Add new cars to
   Android Auto".**
4. **App state:** this AVD carried the app in an earlier session (0.2.0
   era, Brass synced), so its data may be stale. Install the current
   debug APK, then confirm the server is `http://192.168.1.13:3689` with
   Brass (33 tracks) selected. If the data is gone, set the URL and sync
   Brass — the run must not re-sync Soul.

- [ ] AA app version: ____________________
- [ ] Developer mode enabled: yes
- [ ] "Add new cars" enabled: yes
- [ ] Current debug APK installed; server/Brass confirmed: yes
- [ ] AVD serial: ____________________

## 4. One-time connection rehearsal (recommended, catches ToS walls now)

1. AA app overflow menu → **Start head unit server** (notification
   appears).
2. `adb -s <serial> forward tcp:5277 tcp:5277`
3. Run `./desktop-head-unit`; accept the first-connect ToS/permissions on
   the phone screen if prompted (screenshot them — the AA-U1 report
   should show which dialogs appeared).
4. See the AA home screen render, then close the DHU.

- [ ] Rehearsal result: ____________________
  (If the ToS/permission wall has no obvious Allow, stop here and note
  exactly what it asks — the run will hard-block on it otherwise.)

## 5. Machine state

- [ ] OwnTone server reachable:
  `curl -s http://192.168.1.13:3689/api/queue` → HTTP 200
  (the original line's `/status` path does not exist in OwnTone — it
  404s; `/api/queue` is a read-only liveness probe. Verified 2026-10-23)
  → ____________________
- [ ] `flutter devices` shows the AVD; serial: ____________________
- [ ] Host can run the AVD + DHU + an opencode session overnight (RAM
  headroom, display attached — launches are windowed on this host, host
  not set to sleep/lock).

## Sign-off

```
Prep complete: <date> — <name>
DHU: <path> v<version>
AA app: <version> (source: <Play|sideload>)
AVD: <Pixel_9_Pro_API_36 or fallback used> / serial: <serial>
Notes for the run: <anything the orchestrator should know>
```
