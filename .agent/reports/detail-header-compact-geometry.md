# Detail-header dead-band fix 2026-10-19 — compact geometry, Pixel 6 verification

PHASE dead-band fix: COMPLETE

GO/NO-GO CHECK
  What it was: the user reported a blank band between the detail header
  (media/name/meta) and the Play/Shuffle row and asked for the page content
  below the header to move up. Observe, measured on a real device, that the
  band is gone and nothing else in the header regressed (arrow clearance,
  single-name visibility through the collapse, collapsed bar).
  Did you run it:        YES
  What you observed: the dead band is gone — media bottom → Play button top
  is 15.8 dp (was 61 dp), and the bar is sized to its content. The media's
  on-screen position is unchanged from the previous revision (96.8 vs
  96.5 dp top on this device). The collapse still shows the name exactly
  once at every measured scroll state; the collapsed bar is unchanged.

ROOT CAUSE (render-tree ground truth, pre-fix)
  - The FlexibleSpaceBar background spans the full sliver extent (status
    inset P + expandedHeight = 49 + 164 = 213 dp on this Pixel) and arrives
    with a TIGHT height; `Padding.deflate` of a tight constraint is tight,
    so the Row filled the whole 113 dp content area (72 top / 28 bottom
    padding removed) instead of sizing to its 64 dp media.
  - The Row's default centring then split the 49 dp of slack 24.5/24.5
    around the media (media top 96.5 instead of 72), the 28 dp bottom
    margin sat below that, and the button sliver's 8 dp padding below the
    bar added the rest: 24.5 + 28 + 8 ≈ 61 dp of dead surface.
  - A secondary finding: the old constant top inset (72) made the
    media↔arrow clearance device-specific (32 dp on a 0-inset harness,
    7.5 dp on this 49 dp Pixel) purely via the centring slack.

THE FIX (lib/presentation/widgets/collection_detail_header.dart + the three
detail screens; contract pinned in invariant 47)
  - `expandedHeight = kToolbarHeight + mediaSize` on every call site
    (120/176/128), asserted in `_HeaderFade.build` against the measured
    `maxExtent`;
  - P-aware top inset: `P + kToolbarHeight - 16 + 8` — the media sits
    exactly 8 dp under the 24 dp arrow glyph on every device (`P` from
    `MediaQuery.paddingOf`);
  - the Row is top-pinned in an `Align(topCenter)` so leftover slack (if a
    call site ever violates the height contract) collects below the row,
    never around the media;
  - bottom margin 28 → 8 dp: bar ends 8 dp below the media; the
    Play/Shuffle row (next sliver) follows 16 dp below the media bottom;
  - the fade is a fixed hand-off at t = 0.5 (header 1→0 over 0.35–0.5,
    title 0→1 over 0.5–0.7). In the compact geometry the collapsed
    title's sweep band overlaps the expanded name for the entire collapse
    (the crossing is at negative t), so a derived window was meaningless;
    the contiguous pair makes the name visible exactly once at every t.

OBSERVED — things you did and saw, on the device, by hand
  - Installed the new 0.3.0 debug APK in place (`adb install -r`), relaunched.
  - Soul playlist detail, render tree (lens `evaluate_expression`):
    bar extent 168.8 dp = P + 120; arrow glyph [16, 64.8] × [40, 88.8];
    media [24, 96.8] × [88, 160.8] — 8.0 dp under the glyph (previous
    revision: 96.5, visually unchanged); name (104, 100.8) 43×28, meta
    (104, 132.8) 68×24; media bottom → bar bottom 8.0 dp.
  - Play button (a11y bounds) top at 176.6 dp → media bottom → Play top
    **15.8 dp** (pre-fix: 61 dp). The user's reported band is gone.
  - Drove the scroll via the render tree (`RenderViewport` position
    `jumpTo`): at t = 0.375 header fade 0.833 (formula: 1 − (0.375−0.35)/
    0.15 = 0.833 — exact); at t = 0.5 header 0.000 and title 0.000 (the
    hand-off instant — the name is painted nowhere); at t = 0.6 header
    0.000 and title 0.500 (Interval(0.5, 0.7) — exact); at t = 1.0 the
    title (72, 60.8) 43×28 at opacity 1.000, clear of the back button
    (title x 72 > button x 52).
  - Album detail ("A Charlie Brown Christmas"): artwork [24, 96.8] ×
    [144, 216.8] under a 224.8 dp bar; Play top 232.5 dp → 15.7 dp gap.
  - Screenshots: expanded (icon + name + meta under the toolbar, buttons
    directly below) and collapsed (back + title only) both correct.
  - Console window: `logcat` for the session → 0 FATAL, 0 ANR, 0 E/flutter.

NOT VERIFIED — implemented but not exercised, and why
  - Artist screen on device (72 dp avatar, E = 128): same shared header and
    same assert as the two device-measured screens; covered by the widget
    geometry guard. The two extreme media sizes (64 dp, 120 dp) were both
    device-measured.
  - Devices other than the 49 dp Pixel 6: the geometry is P-aware by
    construction and the 0-inset case is fully covered by the widget tests
    (which run at P = 0); a second real device was not available.
  - The published release APK: this pass ran on the debug build (the
    release signing decision was closed separately — the upload key stays).

DEVIATIONS — anything not done as the pass specified
  - The first device attempt this session hit the Pixel 6 ghost
    NotificationShade again (the device had locked between sessions);
    this time a wake + swipe-up unlock cleared it without a reboot.
    `svc power stayon usb` was left on.
  - The scroll states were driven by `jumpTo` through the VM service
    (precise t values) rather than by touch swipes (a 21 px swipe sits at
    the drag slop and does not move the list); the collapsed state was
    reached the same way.

BUILD
  flutter analyze: 0 issues
  flutter test: 157/157 pass (incl. the re-pointed
  `test/detail_header_geometry_test.dart` guards: media 8 dp under the
  arrow glyph, media bottom 8 dp above the bar bottom, Play 16 dp below
  the media, the t = 0.5 hand-off instant, title-alone just past it)
  flutter build apk --debug: success, installed in place

UNKNOWN — behaviour you could not explain
  - Nothing new. The pre-existing open item from
    `detail-header-device-pass.md` (why the flexible-space background and
    the toolbar SafeArea disagree on the status band by 25 dp) stands; the
    P-aware inset makes the design independent of that mechanics.

Open item (unchanged): none introduced. The 2026-10-13 blocker entry's
dead-band finding is now superseded by this contract — see invariant 47.
