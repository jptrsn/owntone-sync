---
title: Android Auto (and Gearslip) media support for OwnTone Sync
passes: [dev]
active_pass: dev
workflow: default
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

# Intent: Android Auto (and Gearslip) media support

## Description

Make OwnTone Sync a first-class media app on the car screen so the driver can
browse the synced library, control playback, and rate tracks from the car —
through **regular Android Auto** (verified on the Android Auto Desktop Head
Unit virtual device), with the same opt-in working for **Gearslip** (which
discovers media apps the same way).

Three things are missing today, and this intent covers all three:

1. **Discovery.** The app exports a `MediaBrowserService`
   (`com.ryanheise.audioservice.AudioService`, via `audio_service` 0.18.19)
   but does not declare the Android Auto opt-in
   (`com.google.android.gms.car.application` meta-data +
   `res/xml/automotive_app_desc.xml`). Without it, no car host lists the app.
2. **Browse tree.** `OwnToneAudioHandler` never overrides
   `getChildren` / `getMediaItem` / `playFromMediaId` / `playFromSearch`
   (`audio_service` `BaseAudioHandler` defaults return `[]` / `null` / no-op),
   so a car host's browse UI is empty and tapping a track would do nothing.
3. **Car-facing UI.** The Now Playing experience is a portrait modal bottom
   sheet with a tap-to-reveal, auto-hiding rating overlay and small touch
   targets. On a car display (16:9 landscape, 800x480 and up, viewed at
   driving distance) it is unusable. A horizontal car layout with large,
   always-visible controls — especially the rating control — is required.

### Why MBS, not Car App Library

The **MediaBrowserService path** (not CAL templates) is chosen deliberately:
the app already ships a full MBS + MediaSession via `audio_service`, and the
user's core requirement — a custom Now Playing screen with a **rating
control** — cannot be drawn with CAL's `MediaPlaybackTemplate` (its actions
are transport + custom buttons only, no in-screen star widget). The
MBS "limited branding" path lets AA/Gearslip render the player chrome from
our session while our own activity still opens on the car display for the
full player screen.

### Also covered for free

Gearslip lists media apps when they "export a `MediaBrowserService` **and**
declare the Android Auto meta-data. Both halves are required"
(`Gearslip docs/BUILDING_APPS.md`, `Media apps` §). AARE uses the same
detection. So unit-02's opt-in + unit-03's browse tree serve both hosts with
zero host-specific code.

## Business context and constraints

- **Repo rules apply** (`AGENTS.md`): confirm scope before editing;
  `verification-protocol.md` defines evidence (a green build is not evidence
  — the defining check for this intent is *observing the app work in Android
  Auto on the virtual device*); open defects in `blockers.md`; anything a
  future session must not undo goes in `invariants.md`.
- **The OwnTone server at `192.168.1.13` holds the user's real library.**
  Read freely. When a verification step changes a track's rating, **record
  the original first, restore afterwards, and confirm the restore against
  the API.**
- **Playback invariants are binding** (`.agent/invariants.md`): the queue
  index-space model, A9 error auto-advance, and the rating-commit path
  (`PlaybackController` → `BrowseProvider` refresh, invariant 31) must not
  change. Car-mode rating commits must go through the **same**
  `LocalDatabaseRepository.setTrackRating` path the phone sheet uses, so
  sync pushes pending edits exactly as today.
- **No auto-play on connect.** Android Auto requires the initial
  `PlaybackState` to be STOPPED/PAUSED/NONE/ERROR and forbids starting audio
  through the car speakers without a user action. `audio_service` already
  starts at idle; do not "fix" this by auto-starting playback when the car
  connects (Gearslip *can* request a resume — that is a user action, which is
  fine).
- **Dependencies.** Adding `androidx.car:car-app` (for `CarConnection`
  detection) is the only new dependency; it is the officially documented
  way to detect projection and is small. Flag it in the report if the
  build pulls unexpected transitive weight.
- **Emulator baseline:** `emulator-5554` (phone) is the usual phone side;
  the head unit side is the **Desktop Head Unit (DHU)** — that is this
  intent's "Android Auto virtual device" (see unit-01). The AAOS emulator
  is documented in `docs/android-testing-aaos-emulator.md` as an alternate
  environment but is **out of scope** (it tests the app running *on* the car
  OS, a different architecture than phone-projected Android Auto).

## Non-goals

- No AAOS (car-OS) module, no `CarAppActivity`, no Car App Library service.
- No messaging, calls, navigation, or parked-experience features.
- No changes to the phone-side player UX (the portrait sheet stays as-is for
  phone use; car mode is an additional mode, not a replacement).
- No Gearslip/AARE-specific code paths — they are regression-checked, not
  designed for.
- No real-vehicle testing (documented as a follow-up).
- Lyrics: the app has no lyrics data; the car host's lyrics pane stays empty.
  Out of scope.

## Completion criteria

### Success cases

- [ ] **Listed in Android Auto.** On the DHU, the app appears in the media
      section (app bar / media picker) with the correct label, and its
      tile is tappable. (Observed on the DHU window.)
- [ ] **Browse tree renders.** Opening the app's browse view in AA shows the
      top-level sections (All tracks / Albums / Artists / Playlists);
      descending into one shows its children; a track leaf is playable.
      (Observed by tapping through on the DHU.)
- [ ] **Playback from the car.** Tapping a track in the browse view starts
      audio through the car speakers (DHU audio output); the now-playing
      pill shows title, artist, artwork; transport controls
      (play/pause/next/previous) and seek work from the AA-rendered player.
- [ ] **Search.** Typing a query in the car host's search returns results;
      playing the best match works.
- [ ] **Car mode engages.** When projected to the car, the Flutter UI
      switches to car mode (detected via `CarConnection`
      `CONNECTION_TYPE_PROJECTION`); when the connection ends, it returns to
      phone UI. (Observed: open app from the car, see horizontal layout;
      unplug, see portrait sheet UI.)
- [ ] **Horizontal Now Playing.** The car Now Playing screen renders
      horizontally at 800x480 (480p) **and** 1280x720 (720p) and a
      wide-margin 1920x1080 configuration, with no overflow, no scrolling
      to reach transport controls, and no keyboard.
- [ ] **Large, visible controls.** Transport and rating controls meet the
      size       targets in unit-05 (play/pause icon ≥ 96dp with ≥ 96dp hit area;
      prev/next ≥ 64dp; seek thumb ≥ 24dp on a ≥ 6dp track; rating control
      56dp star glyphs in a full-control hit area ≥ 72dp tall). The rating
      row is **always visible** (no tap-to-reveal) in car mode and uses the
      phone's press-and-slide gesture with half-star precision.
- [ ] **Rating from the car.** Sliding the rating control (press-and-slide,
      the same gesture and half-star precision as the phone sheet —
      user-confirmed parity) commits a rating through `setTrackRating`
      (verified in the local DB), the star state updates during the drag,
      commits on release, and the pending edit is present for the next sync
      push. Sliding back to zero clears it.
- [ ] **Drive simulation.** With the DHU in `restrict all` (driving) mode,
      the Now Playing screen remains fully operable and no text-entry UI
      appears.
- [ ] **Day/night.** DHU `night` mode renders the dark variant of the car UI.
- [ ] **Reconnect/resume.** Kill the DHU, restart it, reconnect: the app is
      still listed and the last session (queue + position) is resumable.
- [ ] **MediaBrowserService startup scenarios** (per
      `docs/android-testing-overview.md`): the app works when the service
      runs with no activity open; after force-stop + relaunch; after
      clear-data + relaunch (library re-synced).
- [ ] **Gearslip regression (if a Gearslip build is installable).** The app
      is listed as a media app and its browse tree renders in Gearslip's
      media screen. (If not achievable in this environment, note it as
      BLOCKED-with-reason in the report — the spec-level requirements are
      identical to AA's.)
- [ ] `flutter analyze` 0 errors / 0 warnings; `flutter test` green;
      `./gradlew :app:testDebugUnitTest` green; `flutter build apk --debug`
      succeeds.
- [ ] A report in `.agent/reports/` (template per
      `verification-protocol.md` §6) with DHU screenshots for each success
      case above; `invariants.md` updated with anything new a future
      session must not undo (minimum: the mediaId scheme, the car-mode
      detection mechanism, and the rating-commit path reuse).

### Failure cases

- [ ] Tapping a track whose audio file is missing fails **gracefully in the
      car**: playback advances per A9 (no hang, no crash), and the session
      surfaces a user-facing error state (never a dead now-playing pill).
- [ ] Car mode never engages on a plain landscape phone/tablet that is not
      projected (no false positives — verified by rotating the phone
      emulator to landscape with no car connection: phone UI stays).
- [ ] Search with no matches shows an empty state in the car, not a crash.
- [ ] Rating a track with an existing server rating: the local commit is
      still made as a pending edit (server value restored during
      verification per the server rule); the car UI shows the new value
      immediately.
- [ ] Disconnecting the car mid-track: playback continues on the phone
      (car mode exits, phone sheet/mini-player resumes state).
- [ ] Clear-data + relaunch in the car does not crash the service or the
      app, even with an empty library (browse tree shows empty state).

## References

Committed reference docs (fetched 2026-10-23 from the cited sources):

| File | Source |
|---|---|
| `docs/android-media-overview.md` | developer.android.com `/training/cars/media` |
| `docs/android-media-manifest.md` | `/training/cars/media/configure-manifest` |
| `docs/android-media-auto-optin.md` | `/training/cars/media/auto` |
| `docs/android-media-enable-playback.md` | `/training/cars/media/enable-playback` |
| `docs/android-media-distraction-safeguards.md` | `/training/cars/media/distraction-safeguards` |
| `docs/android-media-errors.md` | `/training/cars/media/errors` |
| `docs/android-testing-overview.md` | `/training/cars/testing` |
| `docs/android-testing-dhu.md` | `/training/cars/testing/dhu` |
| `docs/android-testing-aaos-emulator.md` | `/training/cars/testing/emulator` |
| `docs/android-media-design.md` | `/design/ui/cars/guides/app-types/create-media-apps` |
| `docs/android-playback-control-requirements.md` | `/design/ui/cars/guides/app-types/customize-playback-controls` |
| `docs/android-media-ux.md` | `/design/ui/cars/guides/app-types/media-apps` |

Indexed via docs-mcp: `Gearslip` (`docs/BUILDING_APPS.md` — media app
spec), `AARE` (README — media app detection table), `audio_service`
(pub.dev API docs — `getChildren`, `subscribeToChildren`,
`playFromMediaId`, `playFromSearch`, `search`), `just_audio`,
`flutter_api`, `android-emulator`.

## Unit DAG

```
unit-01-test-harness (DHU + phone + AA app)
  ├── unit-02-aa-optin (manifest + automotive_app_desc)
  │     └── unit-03-browse-tree (getChildren / play* / search)
  ├── unit-04-car-mode-detection (CarConnection bridge)
  │     └── unit-05-car-now-playing-ui (horizontal layout + big controls)
  └── unit-06-e2e-verification (full matrix + report + invariants)
        depends_on: 02, 03, 04, 05
```

unit-01 and unit-04 are independent and can be worked in parallel;
unit-05 is the design-heavy unit (see its layout spec).
