# Android Auto run — human prep (do before kickoff)

The overnight run (`.agent/overnight-android-auto.md`) is unattended:
anything interactive below must be done by a person, with the machine
available, **before** the kickoff prompt is pasted. Work top to bottom;
each box needs its result written in the line below it (the orchestrator
copies the sign-off into the ledger at Step 0).

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

## 2. Install the Desktop Head Unit (DHU)

- Android Studio → SDK Manager → **SDK Tools** →
  **Android Auto Desktop Head Unit Emulator** → install. (CLI equivalent:
  `sdkmanager --list` to find the package id, then install it.)
- The binary lands in `SDK_LOCATION/extras/google/auto/`;
  `chmod +x ./desktop-head-unit`.

- [ ] `./desktop-head-unit -v` prints a version: ____________________
  (full path + version — the orchestrator needs both at Step 0)

## 3. Phone side: `OwnTone_U2_API_36`

Launch it (windowed, as on this host) and:

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
4. Confirm the app's server config is still `http://192.168.1.13:3689`
   with Brass selected (the run must not re-sync Soul).

- [ ] AA app version: ____________________
- [ ] Developer mode enabled: yes
- [ ] "Add new cars" enabled: yes
- [ ] App server/Brass confirmed: yes

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

- [ ] OwnTone server reachable: `curl -s http://192.168.1.13:3689/status`
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
AVD serial: <serial>
Notes for the run: <anything the orchestrator should know>
```
