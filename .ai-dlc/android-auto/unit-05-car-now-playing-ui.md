---
title: Car-mode Now Playing screen (horizontal layout, large controls, rating)
status: pending
workflow: default
depends_on: [unit-04-car-mode-detection]
quality_gates:
  - name: analyze
    command: flutter analyze
  - name: flutter-test
    command: flutter test
  - name: build
    command: flutter build apk --debug
---

# Unit 05 — Car-mode Now Playing screen

**The user's core requirement:** on the car display the Now Playing screen
must be **horizontal (landscape), sized for the car's aspect ratio, with
controls that are large, highly visible, and easy to operate — especially
the rating control.**

Today the player is a portrait modal bottom sheet
(`player_screen.dart:NowPlayingSheet`): 92%-height, vertical `ListView`,
artwork at 55% screen width, a **tap-to-reveal rating overlay that
auto-hides after 5s**, 28–44dp icons, a popup menu, and a 4dp seek track.
Every one of those choices is wrong at driving distance. This unit adds a
**parallel car layout** — the phone sheet stays byte-for-byte for phone use
(phone UX is a non-goal to change).

Design references: `docs/android-playback-control-requirements.md` (MUST:
monochrome vector icons, stateful icons, max text in icon space; SHOULD:
now-playing indicator in queue), `docs/android-media-ux.md` (≤3-step flows,
audio-first), `docs/android-media-design.md` (MBS path: the host owns
browsing chrome; our activity owns the opened app screen).

## 1. When and what shows

- `isCarMode == true` (unit-04) → all app routes render in **car mode**.
- **Landing route in car mode:** if a `MediaItem` is loaded → the car Now
  Playing screen; otherwise → the library screen in a horizontal layout
  (secondary criterion below — keep it minimal: no search field, larger
  rows; it must not overflow).
- No modal bottom sheets in car mode (drag-to-dismiss is a phone idiom and
  the car has no drag affordance): anything the sheet version opened (queue,
  album, artist, info) becomes a **full-screen route** or is dropped.
  Scope decision: car mode offers **queue** (full-screen horizontal list)
  and drops go-to-album/go-to-artist/track-info (the car host's browse tree,
  unit-03, covers navigation; record this decision in the report).
- No keyboard surfaces in car mode, ever (search screen hidden from car
  navigation; if reached, show a "search on the phone" hint).
- Day/night: follow `platformBrightness` (verify the existing theme does;
  the DHU `night` command flips it — acceptance-tested).

## 2. Layout specification (car Now Playing)

Design space: **800x480 logical dp** (DHU 480p @ 160dpi — the smallest
target; everything scales up to 720p/1080p proportionally, verify at all
three). Fixed single screen: **no scrolling, no overflow, no keyboard.**

```
┌──────────────────────────────────────────────────────────────────────────┐
│  ┌────────────┐  Track title            (≤2 lines, 30sp, bold, ellipsize) │
│  │            │  Artist                 (≤1 line, 22sp)                    │
│  │            │  Album                  (≤1 line, 18sp, muted)             │
│  │            │                                                              │
│  │   Artwork  │  ★ ★ ★ ★ ☆    (rating row — always visible, press &      │
│  │            │   slide, half-star precision, 56dp stars, same as phone)  │
│  │   square   │                                                              │
│  │            │  0:42 ────────────────●────────────────  3:58              │
│  │            │                      (seek: 6dp track, 24dp thumb)         │
│  └────────────┘                                                              │
│        ⏮ 64dp          ⏯ 96dp          ⏭ 64dp                              │
│                                                                             │
│   [queue 48]  [shuffle 48]  [repeat 48]                                     │
└──────────────────────────────────────────────────────────────────────────┘
```

- **Artwork:** square, side = 70% of screen height (≈336dp at 480p), left
  margin 32dp, vertically centred. `FileImage` from `artUri` (existing
  `_artImageProvider` logic), placeholder on missing. Rounded 16dp.
- **Text block:** centred column between artwork and right edge, 24dp gap
  from artwork. Title `headlineMedium`-class (30sp), artist 22sp, album
  18sp muted. Max 2 / 1 / 1 lines with ellipsis.
- **Rating row:** directly under the text block, **always visible** (no
  reveal gesture, no auto-hide — that is the phone behaviour and it is the
  user's stated pain point).
- **Seek:** full width of the text column. Track 6dp, thumb 24dp (min
  touch 48dp via hit padding). Times 18sp at both ends. Scrub-preview +
  seek-on-release (reuse `_SeekControl` behaviour, restyled).
- **Transport row:** horizontally centred across the **full screen width**
  (below both artwork and text column): prev 64dp icon / play-pause 96dp /
  next 64dp, even spacing. Hit targets ≥ 96dp square each (icon size +
  padding), so a glanceable thumb lands on the right control.
- **Secondary row:** queue / shuffle / repeat, 48dp icons, 64dp hit
  targets, left-aligned under the artwork. Shuffle/repeat state colours use
  the existing convention (primary when active) — must be distinguishable
  at a glance (also consider a small text label under each, 14sp, if
  verification shows ambiguity).
- **Queue (car):** full-screen route, horizontal row list: 48dp artwork
  thumbs, title 22sp / artist 18sp, current track highlighted (SHOULD
  requirement: now-playing indicator), large rows (≥ 72dp). Back = system.

### Size table (binding minimums, at 480p design space)

| Control | Icon / glyph | Hit target |
|---|---|---|
| Play / Pause | 96dp | 96×96dp |
| Previous / Next | 64dp | 96×96dp |
| Queue / Shuffle / Repeat | 48dp | 64×64dp |
| Rating control (5 stars) | 56dp star glyphs | full control ≥ 72dp tall, row-wide hit area |
| Seek thumb | 24dp on 6dp track | 48dp tall across the bar |
| Time labels | 18sp | n/a |
| Queue row | 48dp thumb | ≥ 72dp tall |

Everything above must also fit at 800x480 with 16dp safe margins on all
edges (the car display's bezel-safe area — use `SafeArea` + `MediaQuery`
padding, do not hard-code 800x480).

## 3. Rating control in car mode (the headline control)

**Reuse `RatingControl` as-is** (`lib/presentation/widgets/star_rating.dart`)
at a larger size — no fork, no new widget. The interaction must match the
phone exactly (user decision): press-and-slide, relative to the grab point,
half-star precision (0–100 in steps of 10), commit on release.

- **Interaction: press and slide** — identical semantics to the phone sheet
  (`RatingControl`'s own contract): the rating at the moment of the press is
  the baseline, horizontal movement adjusts it (a full screen-width sweep
  spans 0–5 stars, one half-star = 10% of screen width), vertical drift is
  ignored, the value commits on release. **Clearing = slide to 0**, same as
  the phone. A plain tap changes nothing: on the phone it toggles the
  overlay; in car mode there is no overlay, so the tap is a no-op — do not
  invent a tap-to-set behaviour.
- **Visibility:** the control is always rendered when a track is loaded —
  never hidden, never auto-dismissed, never behind a gesture. (The
  tap-to-reveal + 5s auto-hide overlay is the phone's `_AlbumArtWithRating`
  behaviour and the user's stated pain point; none of that comes to the car.)
- **Sizing:** `size: 56` (the phone uses 28). Keep the widget's internal hit
  padding and wrap it with extra vertical padding so the full-control hit
  height is ≥ 72dp (see size table).
- **State source / commit:** same as the phone sheet — load from
  `LocalDatabaseRepository.getTrackById(id)?.rating` on track change;
  **commit through the same path** (`LocalDatabaseRepository.setTrackRating`
  via the `_onRatingCommitted`-equivalent used at `player_screen.dart:88`)
  so the pending-edit/sync machinery (invariant 30) and the detail-screen
  refresh wiring (invariant 31) work unchanged. In car mode there is no
  "screen under the sheet" to refresh, but `BrowseProvider.refresh()` must
  still be called so the car library rows (and the browse tree's
  `subscribeToChildren` emission, unit-03) see the new rating.
- **Unrated affordance:** all stars unlit + a muted "Tap & slide to rate"
  hint to the right of the row (18sp). The phone needs no such hint because
  the overlay reveals on tap; in car mode the affordance must say it out
  loud so an unrated track is not mistaken for a broken control.

## 4. Behaviour while driving (DHU `restrict all`)

Media playback is allowed while moving; therefore **all** controls on this
screen must remain operable under `restrict all`. Verify explicitly in
unit-06 (play/pause, next/prev, seek, rating tap, queue open/close). Any
control that the OS blocks while driving is a finding to report (and a
candidate to drop from car mode), not a workaround.

## 5. Verification escape hatch

If unit-04 comes back BLOCKED (CarConnection not reporting projection on
the emulated AA), this unit is still fully verifiable via a **debug-only**
override: a `kDebugMode`-gated launch arg / dev settings toggle forcing
`isCarMode`. The override is deleted (or left clearly marked debug-only)
before this intent's report is written; the report states which path the
evidence came from.

## 6. Implementation notes

- New file preferred: `lib/presentation/screens/car_player_screen.dart`
  (the screen + layout). The rating control is the existing
  `RatingControl` (`lib/presentation/widgets/star_rating.dart`) at
  `size: 56` — no fork, no new widget. Route selection in the
  app shell (where `MainActivity`/home decides initial route + where
  `showNowPlayingSheet` is invoked — search for callers) branches on
  `isCarMode`.
- Do **not** refactor the phone sheet to share widgets with the car screen
  unless it is trivial (the sheet has hero animations, its own messenger,
  A9 notices — invariant 31 wiring lives there). Duplication with a clear
  comment is acceptable; a shared-abstract refactor is not in scope.
- A9 notices in car mode: the queue-exhausted / skipped-track messages must
  still surface — render them as a transient 1-line banner at the top of
  the car screen (snackbars are phone-idiom; a top banner is the car
  equivalent). Keep the 5s dedupe logic (`_lastNoticeTrackId`).
- Keep the existing `PlaybackController` as the single funnel (invariants):
  the car screen calls the same controller methods the sheet does
  (`play/pause/skipToNext/skipToPrevious/seek/toggleShuffle/cycleRepeat`).

## Completion criteria

### Success cases

- [ ] At **800x480**, **1280x720**, and **1920x1080 (wide margins)**: the
      car Now Playing screen renders with no overflow, no scroll, no
      keyboard, and the size table above is met (measure via
      `screenshot` + overlay or a debug bounds dump; record the numbers).
- [ ] Rating (press-and-slide, phone parity): slide to 3 stars → 3 stars
      light during the drag, commit on release, DB shows 60, pending edit
      exists; slide back to 0 → clears, DB shows 0; slide a rated track to
      5 stars → 5 stars, DB 100. Half-star precision is reachable (a 60±10
      value renders as the correct half-star). Verified against the local
      DB (and, once, against the server with original recorded + restored
      per the server rule).
- [ ] Rating drag feels right on the car display at all three resolutions:
      a full 0→5 sweep spans the screen width exactly as on the phone, and
      one half-star step is comfortably ≥ one finger-width at 480p. If the
      1920-wide config makes the sweep feel sluggish, the only permitted
      deviation is a fixed logical sweep width (e.g. 400dp) with identical
      relative semantics — record the decision in the report; the phone
      widget's behaviour must not change.
- [ ] Transport: all five controls (prev/play-pause/next/shuffle/repeat)
      work from the car screen with no app on the phone (phone screen off
      or locked).
- [ ] Seek: drag previews the time, release seeks (position stream moves).
- [ ] Queue: opens full-screen, current track highlighted, tapping another
      row plays it, back returns.
- [ ] A9: force the queue-exhausted path (play a queue of one missing file)
      → banner appears in the car screen, playback state is coherent.
- [ ] Day and night variants both verified (`day` / `night` DHU commands).
- [ ] No phone-side regression: portrait sheet UI unchanged on the phone
      (screenshot compare before/after).
- [ ] `flutter analyze` clean; layout widget tests (golden-free: overflow
      assertions at 800x480 and 1280x720, rating tap → commit callback,
      size-table spot checks) committed and green.

### Failure cases

- [ ] No current track in car mode: the screen (or library landing) shows a
      sensible empty state — no null-crash, no blank screen.
- [ ] Very long title/artist/album: ellipsized per the line limits, layout
      unchanged (no reflow pushing transport off-screen).
- [ ] Car mode entered mid-track (app cold-launched from the car while
      playing): Now Playing shows the current track at the right position
      (no restart from 0).
- [ ] Rating commit while offline/sync-in-progress: local commit still made
      (pending edit), no exception surfaces in the car UI.
