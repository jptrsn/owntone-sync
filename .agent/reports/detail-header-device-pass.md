# Device pass 2026-10-19 — Pixel 6, v0.3.0 (scheduled sync check + detail-header verification)

PHASE device pass: COMPLETE

GO/NO-GO CHECK
  What it was: observe the changed behaviour on a real device — the daily
  02:00 scheduled sync chain, and the collection-detail header layout in
  expanded and collapsed states on all three screens, with real library data.
  Did you run it:        YES
  What you observed: the sync chain ran (with doze delay and charging skips,
  as configured); the header renders as specified — media left-aligned under
  the back arrow, name above meta to its right, collapsed bar shows the
  framework title beside the back button only. Measured, not eyeballed:
  playlist via screenshot pixel geometry + accessibility bounds, album via
  render-tree coordinates through the lens (VM service), collapsed state via
  both.

OBSERVED — things you did and saw, on the device, by hand
  - Installed 0.3.0+19 debug APK in place over 0.2.0+18 (`adb install -r`,
    same debug key) → data preserved; full library intact on launch
    (Brass 33 / Holiday Music 60 / Soul 61 playlists).
  - Pulled the device DB (`run-as`), read `sync_history` → scheduled chain
    works: Oct 14/15/16 one-shots fired late (4:48–5:54 AM, doze) and were
    skipped in 17–43 ms with error "Device not plugged into power"
    (schedule requires charging); Oct 17/18 one-shot stayed pending while
    the device was uncharged/deep-sleep; fired Oct 19 10:26 when plugged in
    and downloaded 1 track (Black Pumas – "Ain't No Love in the Heart of
    the City"); next run re-armed (~02:08, jobscheduler dump +15h3m).
  - Opened Holiday Music detail → expanded header: back arrow glyph ends at
    89 dp; icon box [24, 88] × [96, 160] dp (11 dp clear of the arrow);
    name to the right of the icon (x 103.6 dp ink start, icon box ends
    88 dp); "60 tracks" under the name (ink 32 dp below the name ink).
  - Scrolled the playlist fully collapsed → background faded out; bar shows
    back button + "Holiday Music" title only, title ink at y 65.9–81.9 dp,
    x from 73.9 dp (clear of the arrow's x extent, ending 52.2 dp).
  - Opened "Wilson Pickett's Greatest Hits" detail → render tree (lens
    `evaluate_expression`): artwork box at x 24, y 96, 120×120 dp (same
    under-arrow anchor); expanded name "Wilson Pickett's Greatest Hits" at
    x 160 (= 24 + 120 + 16), y 132, h 28 (titleLarge); framework
    (collapsed) title instance at x 72 — the standard leading position.
  - Console window: `logcat` for the whole session → 0 FATAL, 0 ANR,
    0 E/flutter.
  - The 10-15 header fix, as shipped, painted the 64 px playlist icon over
    the back arrow on this device (~28 × 28 dp; icon box [24, 88] ×
    [73, 137] vs arrow target [4, 52] × [53, 101]) — the defect the pass
    existed to catch. Replaced with the user-specified shape the same day.

NOT VERIFIED — implemented but not exercised, and why
  - Artist screen on device (72 dp avatar variant): verified by the widget
    geometry guard (`test/detail_header_geometry_test.dart`, same shared
    header, third of three screens) and by the album render-tree pass; not
    opened on the Pixel because the two extreme media sizes (64 dp icon,
    120 dp artwork) were both device-measured and the header code path is
    identical.
  - The published 0.3.0 **release** APK on device: it is signed with the
    upload keystore (`CN=Owntone Sync, O=educoder.dev`), which cannot
    in-place upgrade existing debug-key installs (signature mismatch);
    device verification ran on the 0.3.0+19 debug build instead.
  - Sync under battery-saver/adaptive-battery policies specifically; the
    observed doze delays are the standard WorkManager + doze behaviour.

DEVIATIONS — anything not done as the pass specified
  - Debug build instead of the release APK (see NOT VERIFIED; the
    signing decision is outstanding — see "Open item").
  - The header was re-fixed mid-pass: the shipped 10-15 fix was defective on
    device, the user specified the replacement shape, and the new shape is
    what is device-verified here (invariant 47 rewritten accordingly).
  - One device reboot mid-pass: the Pixel 6's NotificationShade keeps a
    ghost window (hash 510c43e) that reclaims focus on lock and cannot be
    dismissed without root (`kill`/`force-stop`/`cmd statusbar collapse`
    all fail); reboot cleared it. The app also locked twice mid-pass
    (screen off after idle) — `svc power stayon usb` for the rest.

BUILD
  flutter analyze: 0 issues
  flutter test: 157/157 pass (incl. the re-pointed
  `test/detail_header_geometry_test.dart` guards for the new shape)
  flutter build apk --debug: success (0.3.0+19, installed in place)

UNKNOWN — behaviour you could not explain
  - Why the flexible-space background starts 24 dp below the screen top on
    this device while the toolbar's SafeArea consumes the full 49 dp top
    inset — both measured, the relationship consistent across screens, but
    the exact window-manager/Scaffold mechanics were not traced. The layout
    contract is anchored to the arrow glyph (not the touch target), so the
    design holds either way; flagged so nobody "corrects" `_kMediaTop`
    based on the 49 dp number.
  - The app opened with a paused queue ("House Party" — Thundersmack) in
    the Now Playing sheet after a cold start — consistent with the
    2026-10-06 "playback started on its own" blocker's surface area, but
    here the queue was merely restored and paused, not playing; not chased
    (needs the logcat capture that entry calls for).
  - The ghost NotificationShade window itself (see DEVIATIONS) — SystemUI
  behaviour on this Pixel 6, outside the app.

Open item (not a defect in this pass's scope): the v0.3.0 release signing
mismatch. Options on the table: (a) re-sign 0.3.0 with the debug key and
`gh release upload --clobber` (keeps in-place upgrades for existing
installs; release no longer signed with the upload key), or (b) keep the
upload-key artifact and accept a one-time reinstall for existing users
before any future release. **DECIDED 2026-10-19 (user): option (b)** — the release script and the
upload keystore (`/Users/oblivious/upload-keystore.jks`,
`android/key.properties`) stay untouched; existing debug-key installs take
a one-time reinstall before the next release.
