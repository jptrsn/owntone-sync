---
title: Android Auto test harness (DHU + phone + Android Auto app)
status: pending
workflow: default
depends_on: []
quality_gates:
  - name: build
    command: flutter build apk --debug
---

# Unit 01 — Test harness: Android Auto virtual device

Build the emulated Android Auto environment that every other unit verifies
against: the **Desktop Head Unit (DHU)** as the car, a **phone** (usually
`emulator-5554`, or a physical phone if connected), the official **Android
Auto app** on the phone, and Android Auto **developer mode** enabled so our
sideloaded debug build is accepted.

Reference: `docs/android-testing-dhu.md` (full DHU guide),
`docs/android-testing-overview.md` (developer mode + Media Controller Test).

## Setup steps (record the working commands as you go — the deliverable is a
reproducible script + notes, because the next session must be able to
rebuild this environment from scratch)

1. **DHU install.** SDK Manager → SDK Tools →
   *Android Auto Desktop Head Unit Emulator*. Binary lands in
   `SDK_LOCATION/extras/google/auto/`. `chmod +x ./desktop-head-unit`.
2. **Phone side.** Confirm the phone (emulator-5554 or physical) has the
   Android Auto app (`com.google.android.projection.gearhead`) installed from
   Play and updated. A GMS (Google Play) image is required for the
   emulator. Sign into Play on the phone.
3. **Developer mode on the phone.** Android Auto → Settings → About → tap
   **Version** 10 times → Allow development settings. This is what lets a
   sideloaded (non-Play) media app appear in the car UI. Verify the
   developer options menu is present.
4. **Head unit server + connection.** AA app overflow menu → **Start head
   unit server** (notification appears on the phone). Settings →
   "Previously connected cars" → confirm **Add new cars to Android Auto**
   is enabled.
   `adb -s <phone> forward tcp:5277 tcp:5277`
   Then run `./desktop-head-unit` (default ADB transport). Accept ToS on
   the phone screen on first connect.
5. **DHU smoke test.** The AA home screen renders in the DHU window.
   Console: `screenshot harness-connected.png`.
6. **Media harness sanity (verify the harness before trusting it —
   `verification-protocol.md` §4).** Confirm the DHU's media section can
   see *some* media app (e.g. the Media Controller Test app from
   `docs/android-testing-overview.md`, or any installed music app). If the
   harness cannot see a known-present media app, it is broken — fix the
   harness before any unit claims "the app is missing".

## Deliverables

- `scripts/aa-harness.md` (or `.sh`): exact, versioned commands (DHU path,
  sdkmanager package name, adb device, ports), plus the DHU config file used
  (`~/.android/headunit.ini` or `-c` file) with the resolutions this intent
  tests: **800x480 @ 160dpi** (480p, default), **1280x720** (720p), and a
  wide configuration **1920x1080 with margins** emulating a wide screen
  (`marginwidth`/`marginheight` per `docs/android-testing-dhu.md` "Video
  configuration").
- One screenshot proving step 5, one proving step 6.
- DHU console cheat-sheet for the verification matrix (unit-06):
  `tap x y`, `keycode {media_play,media_pause,media_next,media_previous,
  home,back,media}`, `dpad *` (rotary), `speed <m/s>`, `gear 101` (park),
  `day`/`night`, `focus video on`, `restrict {all,none}`,
  `screenshot <file>`.

## Completion criteria

### Success cases

- [ ] DHU boots and connects to the phone over the adb tunnel; AA home
      renders; screenshot saved.
- [ ] Android Auto developer mode confirmed enabled on the phone.
- [ ] A known-present media app is visible in the DHU's media section
      (harness sanity check passed).
- [ ] All three DHU resolutions boot and render AA (480p, 720p, wide-1080p).
- [ ] `flutter build apk --debug` artifact installs on the phone and
      launches.
- [ ] Script + notes committed such that a fresh session can rebuild the
      environment without guessing.

### Failure cases

- [ ] If the DHU shows a blank screen: apply the documented workaround
      (restart head unit server, restart DHU, re-grant permissions) and
      record what actually fixed it in the notes.
- [ ] If the emulator-5554 image lacks GMS/Play Store: document the exact
      image used or the switch to a physical phone; do not silently swap
      environments.

## Risks / unknowns

- DHU version behaviour may differ from the docs; record the installed DHU
  version in the notes.
- The phone emulator may need `adb forward` re-issued after each reboot.
- First-connect ToS/permissions may differ per AA app version; screenshot
  each dialog the first time it appears.
