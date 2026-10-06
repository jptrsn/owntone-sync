PHASE 4: COMPLETE

GO/NO-GO CHECK
  What it was: plan §3 Phase 4 "Verify" — cold start lands on Library; the last
  row of every list is fully tappable; there is exactly one mini player on
  screen at all times; no debug FAB appears in a debug build.
  Did you run it:        YES
  What you observed:     All four sub-checks observed on emulator-5554 via
  uiautomator dumps, in a full pass and re-confirmed on the final build:
  (a) cold start renders the Library screen (app bar "Library" + search +
  sync-status icons, tabs Playlists/Artists/Albums/Tracks, Brass playlist row)
  with no bottom navigation and no mini player at idle; (b) on the Brass
  detail route and on the 233-row Tracks tab, the list's last visible row
  sits entirely above the docked mini player and its play button is tappable
  (tapped it; that track played); (c) playing any track docks exactly one
  mini player and no second player surface appears on any route; (d) no
  debug FAB is present in this debug build (the `kDebugMode` builder branch
  and `debug_play_button.dart` are deleted).

OBSERVED — things you did and saw, on the emulator, by hand
  - Cold-started the app → Library rendered (tabs + app bar + playlist list);
    no bottom nav, no mini player at idle, no debug FAB.
  - Tapped the hamburger → drawer opened showing OwnTone + server URL
    192.168.1.13 and Sync / Schedule / Server / Storage / History / About.
  - Tapped "Brass" (33 tracks) → playlist detail route opened with app bar
    "Brass" and the 33-track list.
  - Tapped a track's play button on the detail route → exactly one mini
    player docked under the list; the list visibly shrank (last visible row
    ends where the mini player begins); mini player showed title, artist and
    a moving progress bar.
  - Tapped the mini player → Now Playing (PlayerScreen) opened; reopened it
    via swipe-up on the mini player → opened again.
  - Scrolled to the bottom of the Brass list and of the Tracks tab (233
    rows); the final row was fully visible above the mini player; tapped its
    play button → that track played.
  - Drawer → "Sync now" → app-bar sync icon changed from the idle cloud icon
    to an animated progress indicator, then back to idle when sync finished.
  - Tapped the search action → one-line snackbar "Search is coming in a
    later update" (search itself is Phase 6).
  - A9: with the "Black Ice" file deleted from storage (backed up, restored
    afterwards) and the Brass detail route on top, tapped "Black Ice" play →
    within ~2.5s the one-line snackbar `Skipped "Black Ice" - could not be
    played` appeared over the detail route (exact text matched in the
    uiautomator dump); playback continued automatically and the mini player
    then showed "Space Cow" (the next track). Same behaviour observed with a
    second deleted file ("Skunk") reached by playing "Blues in the Attic" to
    natural end: auto-advance past the error, no modal, no interruption.
  - Restored both deleted files to /storage/emulated/0/Music/tracks/ and
    confirmed their presence.

NOT VERIFIED — implemented but not exercised, and why
  - First-run empty state ("No Music Synced" + "Set up sync"): the emulator's
    library has content, so the branch cannot be reached without wiping
    sync data; the code path exists in LibraryScreen.
  - Storage and About screens: created as minimal screens (approved scope)
    and reachable from the drawer; their specific content was not
    exercised beyond creation.
  - Sort-order selection/persistence (B2): deliberately not implemented —
    assigned to Phase 6 (plan §3 Phase 6 item 6, added this phase).
  - A9's "every track unplayable" actionable message: spec defers that to
    Phase 7 (plan §2 A9 note); this phase builds the per-track notice only.

DEVIATIONS — anything not done as the phase specified
  - Search action shows a "coming in a later update" snackbar instead of a
    real search (approved: search is Phase 6; the affordance must not be
    dead).
  - Storage/About are minimal placeholder screens (approved).
  - B2 sort-order persistence pushed explicitly to Phase 6 with a plan item
    (approved correction during phase review).
  - Plan text fix during the phase: §3 Phase 4 item 3 originally suggested
    `Scaffold.bottomSheet` for docking the mini player; corrected in-plan to
    the Column formulation (item 3 now states the bottomSheet trap
    explicitly).
  - No code deviation on A9: the notice is the standard ScaffoldMessenger
    snackbar as specified. A custom overlay/toast layer was prototyped and
    fully reverted after testing (no trace remains; see invariants 17/18).
  - A9 notice is driven by the handler's `PlayerException` listener via a
    dedicated broadcast stream (`skippedTrackStream`), not by watching
    `AudioProcessingState.error` — per the approved phase-review correction
    (the exception's `index` names the skipped track unambiguously; a state
    watch would race the auto-advance and misname the track).

BUILD
  flutter analyze: 0 errors, 0 warnings; 1 pre-existing info
  (sync_provider.dart:653 prefer_conditional_assignment, untouched).
  flutter build apk --debug: ✓ Built build/app/outputs/flutter-apk/app-debug.apk

UNKNOWN — behaviour you could not explain
  - A ScaffoldMessenger snackbar shown while a pushed route is on top does not
    re-appear on the route below after that route is popped, even mid-display
    window. The 3.41.7 scaffold source shows no route gating in
    `_updateSnackBar` (every root scaffold renders `_messengerSnackBar`), so
    the mechanism is unknown. Accepted: A9 is a 3s transient notice and the
    spec does not require survival across route changes (invariant 17).
  - On Flutter 3.41.7, a Scaffold with a `floatingActionButton` suppresses
    ScaffoldMessenger snackbars (A/B verified with quote-free text; no
    exception thrown). Mechanism unknown (invariant 17).
