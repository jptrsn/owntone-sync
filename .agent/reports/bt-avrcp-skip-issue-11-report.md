# Issue capture: car head-unit AVRCP skip loss → #11 (+ ESP32 head-unit harness)

Session: 2026-11-24. Task: capture the user-reported intermittent "car Bluetooth
next/previous not detected" bug as a GitHub issue, **with reproduction performed by
this session**, for handoff to the OpenHands/software-factory fix pipeline.

**Outcome: [issue #11](https://github.com/jptrsn/owntone-sync/issues/11) opened (label
`bug`).** The bug did **not** reproduce in 8 scripted scenarios (listed below) — the
issue documents that honestly, plus the one structural finding it did yield, the
capture protocol for a real broken state, and the harness for re-running.

## GO/NO-GO CHECK
  What it was: reproduce head-unit skip loss using the connected Pixel 6 + ESP32.
  Did you run it:        YES — harness built, paired, and exercised (positive controls verified).
  What you observed: all 8 scenarios PASSED (skip delivered). No broken state induced.
  Verdict: **BLOCKED on the real trigger** — issue filed with evidence, ruled-out
  matrix, and the exact capture commands for the next real occurrence. Not "complete":
  no broken-state capture exists yet.

## What was done on the device (Pixel 6, serial 25071FDF600953, Android 16)

- Debug APK from HEAD `35695df` built + installed; app configured via UI automation:
  server `http://192.168.1.13:3689` (test-connection verified), SAF Music folder granted,
  **Brass (34 tracks)** synced (files in `/sdcard/Music/tracks`, 34).
- AntennaPod installed from F-Droid (`de.danoeh.antennapod_3120395.apk`) with a local
  2-episode podcast (hosted from the dev machine on `:8877`) as the differential player.
- ESP32 (D0WD-V3, CP2104 `/dev/cu.usbserial-02QAS1KB`) flashed with modified
  ESP-IDF v5.5.1 `a2dp_sink` example: A2DP sink + AVRCP CT, pairs as **CarHarness**,
  UART console (`next|prev|play|pause` → passthrough press/release, response logged).
  Sources under `/tmp/owntone-car/` (volatile — recreate per issue §"Reproduction recipe";
  the issue body carries the implementation detail).
- Baseline controls: `next` advanced queue (ids 1→2→3…), `pause` stopped; with
  AntennaPod owning the media-button session, `pause` hit **AntennaPod** — routing follows
  `MediaSessionService` arbitration like real hardware. `rsp_code 9 = ACCEPT` on every
  passthrough (ACCEPT ≠ delivery — trap noted in issue).

## Scenario matrix (all PASS — rules out the obvious theories)

R0 paused-skip · R1 remote-idle + BT power-cycle "car entry" · R2 AntennaPod actively
streaming (GAIN focus) then ours · R5 our-play then BT connect mid-playback · R6
force-stop → restored-paused launch → BT connect → head-unit PLAY-on-connect → ours ·
R9 background play via `cmd media_session dispatch play` · 8× mash with screen Dozing
(0/8 lost). All with in-test playback only, paused at every checkpoint (audio-safety).

## Key finding (in the issue)

`dumpsys media_session` showed `Media button session` pinned to our session while that
session's `active=false`, and `Last MediaButtonReceiver` pinned to our package; session
stack carries **three permanently-active sessions** (ours, remote, `com.samsung.samsungband`).
Media-button-session ownership (driven by audio-focus grants; audio_service never
abandons focus on pause; `enterPlayingState` calls `setActive(true)` **before**
`startForeground` with no retry) is the prime suspect surface. audio_service 0.18.13
`AudioService.java` line refs are in the issue.

## Side effects (disclosed)

- Server (192.168.1.13): remote-control session queue position advanced 214225→215261
  (calibrating the remote app's unlabelled transport row); player left `pause`; queue
  contents untouched; no writes made.
- Phone left: our debug build paused (item id 9/34), AntennaPod paused, CarHarness
  paired (disconnected at end), ESP32 powered with harness firmware.
- `/tmp` scratch: `owntone-car/` (firmware), `podsrv/` (feed), `ser.py` (serial bridge),
  `ui.py` (uiautomator tap helper). All volatile.

## For whoever continues

The issue is the contract. Do not re-derive the scenario matrix — it's recorded. The
missing artifact is a **real broken-state capture** (issue "Evidence to capture");
until then any fix is being validated against a harness that has never seen the bug
(verification-protocol §4: a green harness that can't fail proves nothing).
