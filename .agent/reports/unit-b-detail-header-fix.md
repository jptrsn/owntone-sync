# Unit B: detail-header geometry fix (collection detail screens) — COMPLETE

Fixes the defect measured in `.agent/blockers.md` 2026-10-13 (expanded:
`FlexibleSpaceBar` title overlaps the icon/artwork and track count) and
closes the 2026-10-08 entry's collapsed requirement (title constrained to
one line, fitting the collapsed bar). The arbiter is Unit A's geometry
guard, `test/detail_header_geometry_test.dart`, which was RED (3 failures,
one per screen, expanded phase only) before this fix.

## GO/NO-GO CHECK

What it was: `flutter test test/detail_header_geometry_test.dart` — the
guards pass expanded AND collapsed on all three screens.
Did you run it: YES
What you observed: 4/4 pass (seed + 3 screens). Before the fix: 1/4 — the
three expanded overlap assertions failed with rects matching the 2026-10-13
measurement (e.g. artist: title `72.2,142 → 314.2,170` over avatar
`24.2,112 → 96.2,184`).

## Changes (lib/ only)

1. **New** `lib/presentation/widgets/collection_detail_header.dart` —
   `CollectionDetailHeader`, the shared `FlexibleSpaceBar` for the three
   detail headers. One layout owner per visible scroll state:
   - `title`: `Text(name, maxLines: 1, overflow: ellipsis)` — the
     collapsed-state owner. With `pinned: true` the bar's `toolbarOpacity`
     is always 1 (verified in `app_bar.dart:1375`), so the title is visible
     in every scroll state; at full collapse the background is at opacity 0
     (verified in `flexible_space_bar.dart:244-275`), leaving the title as
     the only visible content.
   - `background`: the icon/artwork + metadata row, pinned to its natural
     height (`SizedBox(height: rowHeight)`) and anchored **top-left** (was
     bottom-left), wrapped in `_HeaderRowFade`, which reads
     `FlexibleSpaceBarSettings` and fades the row to opacity 0 at the
     collapse fraction where an 8 px safety margin still remains before the
     collapsing title sweep reaches the row's bottom edge. Both positions
     are linear in the collapse fraction (title: `barHeight - 16 -
     h·(1.5 - 0.5t)`; row: `24 + rowHeight - delta·t/4`), so the window is
     exact, not approximate.
2. **Edited** the three screens — each `flexibleSpace` is now
   `CollectionDetailHeader(name:, rowHeight:, row:)`; the row's internal
   structure (Row + icon/art + 16 px gap + meta, including the album's
   `Expanded(Column)` and its `mainAxisAlignment: end`) is byte-for-byte
   unchanged. `expandedHeight` (180/260/200), `pinned`, colours, the
   Play/Shuffle row: unchanged.

Why the row needed the height pin: an `Expanded` column makes the Row
stretch to the background's full height (measured: 220 px on the album
header), which pushes the bottom-aligned meta into the title zone even
when top-anchored — the album guard stayed RED on `title vs meta`
(title `202–230` over meta `228–244`) until the pin.

## OBSERVED (widget-test evidence; no device in this program)

- Guard file: expanded title rects now clear the icon/art/avatar and the
  meta on all three screens; collapsed phase (viewport 800×170, drag −300,
  bar height ≤ 57 pre-asserted) finds the name inside the `FlexibleSpaceBar`,
  clear of `Icons.arrow_back`, within the bar's right/bottom edges.
- Mid-scroll sweep (scratch probe, since deleted): sampled every screen at
  15 scroll offsets from fully expanded to fully collapsed. While the row
  is visible (opacity > 0) its bottom edge is always ≥ 8 px below the
  title's painted top edge; the row reaches opacity 0 before the gap
  closes (playlist: gap 6.2 px at the first fully-faded sample; album:
  11.8 px at opacity 0.19, then 0; artist: 12.8 px at opacity 0.35, then
  0). The two layers never claim the same region in any sampled state.
- Long-name check (scratch probe, since deleted): a 105-character playlist
  name collapsed — title one line (28 px), ellipsized to exactly the bar
  width (72 → 800 = bar right), clear of the back button (16–40).

## NOT VERIFIED — implemented but not exercised, and why

- **Device verification of both scroll states** on all three screens —
  no device in this program (scope agreed in `.agent/widget-test-task.md`
  "Where things stand"): the blockers stay OPEN until the user's device
  pass, including the long real names named in the 2026-10-08 entry.
- `flutter build apk --debug` — not a Unit B gate (pure widget change;
  analyze clean).

## DEVIATIONS — anything not done as the phase specified

- The task doc's Unit B fix line names `collapsedTitle` /
  `collapsedTitlePadding` — those parameters **do not exist in Flutter
  3.41.7** (grep of `packages/flutter/lib` finds no `collapsedTitle`;
  verified against the SDK source). Implemented the shape the doc's own
  caveat and the blockers' option (b) point to: `title` owns the collapsed
  state, the background row is re-anchored out of the title zone, with the
  adaptive fade the brief's "one layout owner per visible state" requires.
- One shared new widget file instead of three per-screen edits — the three
  screens need the identical layout-owner design; a single implementation
  makes the invariant testable in one place.
- `.agent/invariants.md` and the blockers' RESOLVED marks are **not**
  updated: they are whole-program DoD items (the 2026-10-13 entry says both
  "stay OPEN until Unit B's fix is device-verified"). Proposed invariant
  text for the orchestrator:

  > The `FlexibleSpaceBar` `title` and `background` are independent layers
  > of one stack. With `pinned: true` the title is visible in every scroll
  > state and is the collapsed-state owner of the name (`maxLines: 1`,
  > ellipsis); the background row is the expanded-state owner and must stay
  > out of the title zone in every scroll state — on Flutter 3.41.7 that
  > means top-anchored and faded out (via `FlexibleSpaceBarSettings`)
  > before the title sweep reaches it. `collection_detail_header.dart`
  > encodes this geometry; re-anchoring the row bottom-left, or dropping
  > the fade, re-opens the 2026-10-13 / 2026-10-08 defects (guards in
  > `test/detail_header_geometry_test.dart` catch the extremes).

## BUILD

- flutter analyze: No issues found! (0 errors, 0 warnings)
- flutter test (full suite): `00:08 +132: All tests passed!`
  (128 pre-existing + 4 guards; baseline before the fix: +129 -3)
- flutter test test/detail_header_geometry_test.dart:
  `00:08 +4: All tests passed!`

## UNKNOWN — behaviour you could not explain

- Why `RenderFlex` stretches a Row containing an `Expanded` column to the
  full incoming height (measured 220 px on the album header) instead of
  shrink-wrapping to its tallest non-flex child — the `SizedBox` pin makes
  the behaviour moot, but the mechanism is unverified against the SDK
  source and could matter for other layouts.
