---
title: Car mode detection (CarConnection projection bridge)
status: pending
workflow: default
depends_on: [unit-01-test-harness]
quality_gates:
  - name: analyze
    command: flutter analyze
  - name: flutter-test
    command: flutter test
  - name: build
    command: flutter build apk --debug
---

# Unit 04 — Car mode detection

The Flutter UI must know whether it is being projected to a car so it can
switch to the car layout (unit-05). The officially documented mechanism for
a media app is `CarConnection` from `androidx.car:car-app`: observe
`getType()` and treat `CONNECTION_TYPE_PROJECTION` as "in Android Auto"
(`CONNECTION_TYPE_IN_CAR` would be AAOS — out of scope but harmless to
observe; `CONNECTION_TYPE_NONE` = phone).
Reference: `docs/android-media-distraction-safeguards.md` ("use the
`CarConnection` API to detect if a phone projects to a car screen ...
Confirm the value is equal to `CONNECTION_TYPE_PROJECTION`").

No `CarAppService` is needed — `CarConnection` is used here purely for
detection, which is the documented media-app pattern.

## Changes

1. **Dependency** (`android/app/build.gradle.kts`):
   `implementation("androidx.car:car-app:<latest-stable>")` — pick the
   latest stable at build time (compileSdk 35 / minSdk 27 are compatible);
   note the resolved version in the report.
2. **Kotlin bridge** (`MainActivity.kt`, following the existing
   MethodChannel pattern — `EVENTS_CHANNEL` / `STORAGE_CHANNEL` /
   `SYNC_CHANNEL` / `PLAYER_CHANNEL`):
   - New channel `dev.educoder.owntone_sync/car` (or extend an existing
     one — match local convention).
   - `onCreate`: create `CarConnection(this)`, call `startConnecting()`,
     observe `getType()` LiveData; push changes to Dart as event
     `"car.connectionType"` with int value; answer `car.isCar` → bool
     (`type == CONNECTION_TYPE_PROJECTION`).
   - Keep a single connection for the activity's lifetime; do not call
     `disconnect()` on pause (car mode can resume when the activity
     returns).
   - Log the raw type transitions under a tag (e.g. `OwnToneCar`) for
   verification.
3. **Dart side** (new small service, e.g.
   `lib/presentation/services/car_mode_controller.dart`):
   - `ValueNotifier<bool> isCarMode`; on init + app resume, call
     `car.isCar`; listen for pushed changes; expose the stream.
   - Wire it into the app's provider tree (next to `PlaybackController`).
   - **Phone-side invariant:** `isCarMode` must be false unless
     `CONNECTION_TYPE_PROJECTION` was actually observed — no
     orientation/aspect heuristics as a trigger (a landscape tablet is not
     a car; false positives are an intent-level failure case).

## Completion criteria

### Success cases

- [ ] On the DHU (car connected): `isCarMode` becomes true within 1s of
      AA projecting the app (verified by log line + UI switch in unit-05).
- [ ] On phone only (including phone rotated to landscape): false, always.
- [ ] Disconnect the car (close DHU / `focus video off` / unplug):
      `isCarMode` returns to false without app restart.
- [ ] Reconnect: flips true again.
- [ ] `flutter analyze` clean; no new lint warnings from the dependency.

### Failure cases

- [ ] App launched **cold while already projected** (kill app, open from
      the car): detection still reports true (the bridge must query on
      start, not only watch for changes).
- [ ] `CarConnection` fails to connect on the emulator image (possible):
      document the failure with logcat, and file the unit **BLOCKED** —
      do **not** fall back to heuristics silently. (If blocked, unit-05's
      car layout can still be verified by a debug-only override flag —
      see unit-05 "verification escape hatch".)

## Risks / unknowns

- `CarConnection` behaviour on **emulated** Android Auto (DHU) is the main
  unknown: the docs present it for real projection. The whole unit exists
  partly to answer that question on the harness. If it does not report
  `PROJECTION` under the DHU, the fallback (decide and record, do not guess):
  configuration-based detection — activity launched by AA gets
  landscape + car resolution; combine with "AA app is the foreground
  projection" signals. Any fallback MUST be written as an explicit decision
  in this unit's report section before implementation.
- `androidx.car:car-app` may pull transitive deps; check
  `flutter build apk` size delta and note it.
