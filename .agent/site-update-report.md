# Site update for v0.2.0

PHASE site-update: COMPLETE

GO/NO-GO CHECK
  What it was: Every edited page renders in a browser with no console errors,
    all local links resolve and navigate, the rendered text matches the
    v0.2.0 README, and no claim on the site describes removed behaviour
    (notification-listener tracking, the old sync-first UI, a separate player
    app, the "(optional)" playback-tracking toggle).
  Did you run it:        YES
  What you observed: Headless Chromium (Playwright 1.63) loaded all three
    pages from file:// — 0 console errors, 0 failed requests, 0 HTTP >= 400.
    All local link targets (styles.css, icon.svg, 4 screenshots, 3 cross-page
    links) exist and each linked .html page renders a body. Rendered
    innerText of all three pages dumped and inspected: new copy present,
    page structure (section headings) unchanged. All three pages were also
    opened in the user's GUI browser.

OBSERVED — things I did and saw
  - git checkout -b site-update main → new branch from e231a48 (main); the
    tests-branch README is the pre-0.2.0 one, main's README (05d0d1d) is the
    v0.2.0 rewrite and was used as the source of truth.
  - Read android/app/src/main/AndroidManifest.xml on main → no
    NotificationListenerService, no BIND_NOTIFICATION_LISTENER_SERVICE;
    POST_NOTIFICATIONS is still declared (sync progress + media notification),
    which the new copy reflects.
  - webfetch of the Google Play listing → 404. The app is not on the Play
    Store (index.html's Play CTAs were already commented out; README says
    GitHub releases + Obtainium).
  - Edited site/privacy.html (3 edits), site/index.html (8 edits),
    site/smart-playlists.html (4 edits), metadata/en-US/short_description.txt,
    metadata/en-US/full_description.txt, metadata/dev.educoder.owntone_sync.yml.
    git diff --stat: 6 files, +64/-46. No styles.css change; no new files
    besides this report.
  - Ran the render/link check (script kept at /tmp/owntone-site/verify.js) →
    "ALL CHECKS PASSED"; titles and section headings printed per page.
  - Ran rendered-text dump (textcheck.js) → all new copy visible in the DOM
    of all three pages; no stale claims in rendered output.
  - Grep of site/ + metadata/ for "notification", "tab", "optional",
    "other music player" (case-insensitive) plus a second sweep for
    "Auxio|Vinyl|PowerAmp|play.google|Offline Playback|for offline listening|
    music player app":
      - privacy.html "notification access" / "other music player" → the new
        negative statement ("does not request… cannot read… does not track
        what you play in any other music player"). Correct, left in.
      - index.html "optionally only while charging or on WiFi" → the charging/
        WiFi conditions exist in the current app. Correct, left in.
      - index.html + full_description.txt "per-tab sorting" → the current
        library has Playlists/Artists/Albums/Tracks tabs that each remember
        their sort order (README). Correct, left in.
      - index.html "permission to show notifications" → POST_NOTIFICATIONS,
        still requested (manifest). Correct, left in.
      - smart-playlists.html "other music players are not tracked" ×2 →
        accurate limitation, left in.
      - changelogs/18.txt "replacing the unreliable notification listener" →
        historical 0.2.0 changelog entry describing the removal. Correct,
        left in.
      - styles.css "comparison-table", smart-playlists.html "operator-table",
        yml "flutter@stable" → substring false positives ("tab" in table/
        stable). Left in.
      - index.html lines 35 and 149 "Download on Google Play" → inside
        HTML comments (not rendered; confirmed by text dump). Left in; see
        DEVIATIONS.
  - md5 of site/assets/screenshots/screenshot_{1,4}.png vs
    metadata/en-US/images/phoneScreenshots/screenshot_{1,4}.png → identical.
    The store-listing screenshots are the same stale images.

NOT VERIFIED — implemented but not exercised, and why
  - Visual layout of the rendered pages. Screenshots of the pages were
    captured, but this session's model cannot view images; verification is
    structural (no console errors, sections/headings intact, rendered text
    correct, all links load). The pages were opened in the user's browser for
    a human look.
  - The 7th feature card (Star Ratings): the grid is
    repeat(auto-fit, minmax(max(250px, calc(50% - 2rem)), 1fr)), so it should
    simply occupy the first cell of a new row, but I could not visually
    confirm the orphaned-cell layout.
  - metadata yml 0.2.0 build entry: recipe copied verbatim from the 0.1.3
    entry (same subdir, toolchain, gradle steps). Cannot be exercised outside
    F-Droid's build infrastructure.
  - External links (shields.io badges, owntone.github.io, GitHub,
    releases/latest) — unchanged by this work; only the Play Store URL was
    tested (404, expected).

DEVIATIONS — anything not done as specified
  - Screenshots NOT regenerated; old screenshot_{1..4}.png left in place in
    BOTH site/assets/screenshots/ and metadata/en-US/images/phoneScreenshots/
    (identical files). Reason: mid-session instruction — no containers and no
    device emulator may be run on this host. What capture on this host would
    have needed (and why it was blocked): an OwnTone server (no owntone
    binary, no formula, docker pull explicitly forbidden) and emulator-5554
    (explicitly not to be run). Requirements for each shot when it is done:
      1. Library — the app opens directly on the library (no bottom tab bar,
         no sync-first screen). Show the Playlists (or Artists) tab with
         several synced rows, album artwork visible in the rows, search icon
         in the toolbar.
      2. Now Playing with artwork — full Now Playing view (swiped up from the
         mini player bar): large album artwork, title/artist, seek bar,
         shuffle and repeat controls, a track mid-playback.
      3. Queue sheet — queue opened from Now Playing: upcoming tracks listed,
         rows draggable for reordering.
      4. Rating control — Now Playing with the five-star strip revealed by
         tapping the artwork (or the ⋮ menu on a row), showing a half-star
         rating set (e.g. 3.5) released/saved.
    To capture: emulator (e.g. emulator-5554) with a v0.2.0 build installed,
    an OwnTone server reachable from the device holding at least 2–3
    playlists with a handful of tracks each, some with embedded/served album
    artwork; complete a sync, start playback, then screenshot each state.
    On completion: overwrite the 4 PNGs in both locations and update the
    four <img> alt attributes in site/index.html (currently
    "Configure OwnTone Server", "Sync History", "Browse Tracks",
    "Sync Screen") to describe what the new shots actually show.
  - Updated metadata/dev.educoder.owntone_sync.yml beyond the two named
    description files: CurrentVersion 0.1.3 → 0.2.0, CurrentVersionCode
    8 → 18, and a 0.2.0 build entry (tag v0.2.0, verified to exist; version
    matches pubspec 0.2.0+18). Left stale, F-Droid would keep pointing users
    at 0.1.3.
  - smart-playlists.html final CTA: "Download on Google Play" pointed at a
    404 listing; changed to "Download the Latest Release" →
    github.com/jptrsn/owntone-sync/releases/latest (the distribution channel
    the README documents). Section structure untouched.
  - Left in place, knowingly stale/inert: the two commented-out Google Play
    CTA blocks in site/index.html (not rendered); the "Google Play Services:
    for app updates and license verification" boilerplate bullet in
    privacy.html (OS-level, not a distribution claim); alt text of the old
    screenshots (still matches the old images they describe, until the shots
    are retaken).

BUILD
  flutter analyze:      N/A — static HTML site, nothing to build
  flutter build apk --debug: N/A — no app code touched
  (Verified via git status: only the 6 content files + this report changed.)

UNKNOWN — behaviour I could not explain
  - The exact pre-0.2.0 content of the 4 PNGs (this session's model cannot
    view images); the task description says they show the deleted bottom tab
    bar and a sync-first launch screen, which I have not independently
    confirmed.
  - Whether the old screenshots are the only store-listing media: the
    feature_graphic.png was not checked (not described as stale, and images
    cannot be viewed here).

Pages changed
  - site/privacy.html — PRIORITY 1. Replaced the removed "Notification
    Access (optional)" permission block with "No Notification Access": the
    app's own player measures playback directly, events are stored locally
    and uploaded to the user's own OwnTone server on the next sync; no
    notification access, no other apps observed. "Playback Events (if
    enabled)" → always-on, player-measured; "playback tracking" removed from
    App Settings; added Ratings to the local data inventory; Last Updated →
    October 6, 2026. Follow-up (user correction): removed the
    "Google Play Services: for app updates and license verification" bullet
    from Network Communication (inaccurate — the app is not on Google Play
    and does not contact it) and added an explicit statement that the app is
    not available on Google Play and is distributed via GitHub releases /
    Obtainium.
  - site/index.html — PRIORITY 2. Title and hero now lead with playback.
    Features rewritten: Play Your Music (built-in player, in-context play,
    reorderable queue, shuffle/repeat, background + lock-screen + Bluetooth
    controls), Automatic Sync (charging/WiFi conditions), Browse (search,
    per-tab sorting, offline artwork), Star Ratings (new: half-star
    precision, two-way sync, server wins conflicts), Play & Skip Counts
    (built-in, nothing to enable, uploads on next sync), Sync History,
    Privacy First. Data Safety "Local storage only" now says statistics go
    only to the user's own server. FAQ: server needed for sync, offline
    playback/artwork; other players can read the files but their
    play/skip/rating activity is not tracked; permissions answer now says
    "permission to show notifications" and explicitly that the app does not
    request notification access.
  - site/smart-playlists.html — "playback tracking feature" / "Enable
    playback tracking" references (intro, tip callout, Smart Shuffle and
    Rediscover sync tips, final CTA) reworded: the player records events
    automatically and uploads on the next sync; plays from other players are
    not tracked. Play Store CTA → GitHub releases.
  - metadata/en-US/short_description.txt — now leads with playback
    ("Play your OwnTone playlists offline; stats and ratings sync back to
    the server", 78 chars ≤ F-Droid's 80).
  - metadata/en-US/full_description.txt — rewritten around the player
    (built-in player, queue/shuffle/repeat, offline artwork, half-star
    ratings, self-recorded play/skip counts, scheduled syncs); states the
    app plays only synced music, not all device audio, and that other
    players' activity is not reported back.
  - metadata/dev.educoder.owntone_sync.yml — see DEVIATIONS.
  - metadata/en-US/changelogs/ — 18.txt (0.2.0) is already accurate; 1.txt
    is historical. Unchanged.

Status of the pages branch: not touched, per instruction (stub, not deployed
from).

Deployment: changes are committed on branch site-update (off main). Nothing
pushed. The Pages workflow fires on pushes to main that touch site/**, so a
merge of site-update into main deploys the site.
