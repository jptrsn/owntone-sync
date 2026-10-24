---
title: End-to-end verification on the Android Auto virtual device + report
status: pending
workflow: default
depends_on: [unit-02-aa-optin, unit-03-browse-tree, unit-04-car-mode-detection, unit-05-car-now-playing-ui]
quality_gates:
  - name: analyze
    command: flutter analyze
  - name: flutter-test
    command: flutter test
  - name: gradle-test
    command: ./gradlew -p android :app:testDebugUnitTest
  - name: build
    command: flutter build apk --debug
---

# Unit 06 — End-to-end verification + report

Run the full matrix on the Android Auto virtual device (unit-01 harness),
capture evidence per `verification-protocol.md`, and produce the report +
invariant updates. **If any matrix row could not be executed, this unit is
BLOCKED for that row — say so plainly; a green build is not evidence.**

## Matrix

Every row: action on the DHU (console command) → expected observation →
screenshot or other evidence. Use `screenshot <file>.png` for every row;
store them in `.agent/reports/<date>-android-auto/`.

### A. Discovery & session

| # | Action | Expect | Evidence |
|---|---|---|---|
| A1 | Fresh install, open AA media section | Owntone listed, label + icon correct | screenshot |
| A2 | `adb shell dumpsys media_session` while idle | our session present, state not playing, artwork/metadata populated | log |
| A3 | Play one track on the phone, watch the DHU | now-playing pill shows title/artist/artwork | screenshot |
| A4 | `keycode media_play_pause`, `media_next`, `media_previous` from the DHU prompt | playback responds (position/track changes) | screenshot + position log |
| A5 | Seek via the AA-rendered player (if exposed) | position jumps | screenshot |

### B. Browse & search (unit-03)

| # | Action | Expect | Evidence |
|---|---|---|---|
| B1 | Open app's browse view in AA | four sections | screenshot |
| B2 | Descend: Albums → one album; Artists → one artist; Playlists → one playlist | children render, correct titles | screenshots |
| B3 | Tap a track leaf | audio plays through car, pill updates | screenshot |
| B4 | Tap an album node (not a child) | collection plays from start | screenshot |
| B5 | Search: type a known artist | results render; playing best match works | screenshot |
| B6 | Search: gibberish query | empty state, no crash | screenshot |
| B7 | Play a track whose file is missing (induce from the app side per repo rule) | A9 advances, no hang; error visible | log + screenshot |

### C. Car mode UI (units 04/05)

| # | Action | Expect | Evidence |
|---|---|---|---|
| C1 | Tap the app tile in AA app bar | app opens on the car in **car mode** (horizontal Now Playing if a track loaded) | screenshot |
| C2 | Same at 1280x720 and at the wide-1080 config | layout correct at all three (no overflow/scroll) | 3 screenshots |
| C3 | Phone rotated to landscape, **no** car connected | phone UI stays (no false car mode) | screenshot + log |
| C4 | `restrict all` (driving): operate every control (transport, seek, rating, queue) | all operable; no keyboard appears | screenshots |
| C5 | `night` → dark variant; `day` → light | themes follow | 2 screenshots |
| C6 | Slide the rating control to 3 stars, then to 0 (press-and-slide, phone parity; record server rating first if it's a server-synced track; restore + confirm against API afterwards) | stars update during the drag, commit on release, DB 60 then 0, pending edit present | DB dump + API check + screenshots |
| C7 | Queue: open, tap another row, back | plays tapped track, back works | screenshots |
| C8 | A9 notice in car (skip of a failed track) | top banner appears, ≤5s dedupe holds | screenshot |
| C9 | Cold-launch the app from the car mid-playback | Now Playing shows current track at current position | screenshot |

### D. Lifecycle & robustness

| # | Action | Expect | Evidence |
|---|---|---|---|
| D1 | Close DHU mid-playback, restart, reconnect | app still listed; last queue/position resumable | screenshot |
| D2 | Force-stop the app while connected, relaunch | works (MBS startup scenario: service before activity) | log + screenshot |
| D3 | Clear app data, relaunch in the car | no crash; empty-library state; re-sync works | screenshot |
| D4 | Unplug/disconnect mid-track | phone playback continues, phone UI resumes (mini player/sheet) | screenshot on phone |
| D5 | `focus video off` then `on` (head unit hides/re-shows AA) | app state intact, no crash | screenshot |

### E. Cross-host regression

| # | Action | Expect | Evidence |
|---|---|---|---|
| E1 | (if a Gearslip APK is installable on the harness phone) connect a car (real, DHU-equivalent not possible — Gearslip speaks to the head unit directly; **only feasible with a physical car or LIVI**; otherwise mark BLOCKED-with-reason) | app listed in Gearslip media section; browse tree renders; transport + seek work | screenshot or BLOCKED note |
| E2 | Media Controller Test app (docs/android-testing-overview.md) against our session | metadata/queue/actions/state all reported sensibly | log |

## Report (`.agent/reports/`, template per verification-protocol.md §6)

Must contain:
- What was verified, per matrix row, with evidence references (screenshots
  live in the report folder).
- The exact DHU version, AA app version, phone image/model, API levels.
- The accent-color decision (unit-02) and browse-time-uri decision (unit-03)
  and any CarConnection outcome + fallback decision (unit-04).
- Server rating change(s): original value, new value, restore confirmation
  against the API.
- Any BLOCKED rows with reason.
- Size-table measurements for unit-05 (actual dp values measured on device
  vs the binding minimums).

## Invariant updates (`.agent/invariants.md`)

Add entries (numbered, with WHY / BREAKS IF UNDONE) for at least:
1. **mediaId scheme** (unit-03 table) — track id = DB id string; the
   encode/decode pair is the only place mediaIds are constructed/parsed.
2. **Car-mode detection** — `isCarMode` is true only on
   `CONNECTION_TYPE_PROJECTION` (or the documented fallback decision); no
   orientation heuristics as a trigger.
3. **Car rating commits** — go through the same `setTrackRating` path as
   the phone sheet; the car UI never writes ratings directly to the server.
4. **No auto-play on car connect** — initial session state must stay
   non-playing (Android Auto requirement; breaking it is a review rejection
   on Google Play for cars).

## Done means (this unit)

- All matrix rows executed or explicitly BLOCKED-with-reason.
- Report committed to `.agent/reports/`.
- `invariants.md` updated.
- All four quality gates green.
- Working tree left uncommitted (repo rule: no commits without being asked).
