# Phase U0 — Stop server config destroying the library

**Date:** 2026-10-08 · **Device:** emulator-5554 (Pixel 8, API 36) ·
**Spec:** `.agent/ux-refactor.md` §6, Phase U0 (ACCEPTED, 2026-10-08)

## Changes

| File | Change |
|---|---|
| `lib/utils/server_url.dart` | **New.** `ServerUrlIdentity` + pure `parseServerUrlIdentity()`: trim, lowercase scheme and host, strip trailing slashes, absent port → scheme default (80/443). Null = "cannot prove same server", never "server changed". |
| `lib/presentation/screens/server_config_screen.dart` | Save path reworked to the spec's three outcomes. Normalised-equal → save silently. Same host (port/scheme changed) → save, no wipe, "Server address updated." Different host → new "Different server?" dialog; **Keep library is the primary (Elevated) action**, i.e. the default; "Start fresh" leads to the existing files dialog (Cancel / Keep Files / Delete Files). Saving clears the surfaced error (`clearError()`) in every path. The wipe path reloads **all** browse categories after the reset. |
| `lib/presentation/providers/browse_provider.dart` | `loadData()` refactored onto a private `_loadCategory()`; new `reloadAll()` loads all four categories. Needed because `hasContent` spans all four lists and `loadData()` only touches the current tab — a current-tab-only reload after a wipe leaves the other tabs showing stale rows and keeps the tabbed UI up on an empty DB. |
| `test/server_url_test.dart` | **New.** 13 tests for the normalisation, citing U0 build items 1–3. |

**Screen-touch note** (per §6): the two known defects from 2026-10-08 live in
`player_screen.dart`'s sheet geometry and the detail screens' `SliverAppBar`s.
U0 touches neither file; nothing here conflicts with their fixes.

## Verification — the five U0 checks, on emulator-5554

Baseline before any change: URL `http://192.168.1.13:3689`, library Brass (33) + Soul (60) = 93 tracks, no error surfaces.

1. **Identical URL → save, no dialog, library intact.** Opened Server, tapped Save
   on the unedited field. No dialog; screen returned to Library; Brass 33 + Soul 60
   still shown. (The old code also passed this one — raw strings were equal — so it
   proves no regression, not the fix.)
2. **Trailing `/` → save, no dialog.** Field set to `http://192.168.1.13:3689/`,
   saved. **No dialog** — the old code's `newUrl != _originalServerUrl` comparison
   would have raised the wipe dialog here, so this is the check that proves the new
   code is live. Library intact. Saved the slash form, cold-started, and confirmed
   the startup fetch still works (no error surface — Dio resolves absolute paths
   against the base, so the slash is harmless). Then saved the no-slash form over
   the slash form: no dialog again (second normalised-equal data point).
3. **Port-only change → save, library intact.** Field set to
   `http://192.168.1.13:9999`, saved. No dialog; snackbar "Server address updated.";
   Brass 33 + Soul 60 intact. Restored `:3689` the same way (no dialog).
4. **Host change → prompt, keep is the default, keeping leaves the library.**
   Field set to `http://192.168.1.99:3689`, saved. The "Different server?" dialog
   appeared, worded around the server ("…the same server at a new address — for
   example after your router assigned it a new IP…"), with **Keep library as the
   Elevated (primary/default) action** and Start fresh / Cancel as text buttons.
   Tapped Keep library → snackbar "Server address updated. Your library was kept.";
   Brass 33 + Soul 60 still present. Restored the real host via the same flow
   (dialog again, Keep library).
5. **Discard still works; Playlists tab matches the DB immediately.** Host changed
   to `http://192.168.1.99:3689` again → "Start fresh" → "Keep Files" → reset ran →
   snackbar "Server changed. Music files kept." The Library **immediately** showed
   the empty state ("No Music Synced") — no stale playlist rows, no tabbed UI
   holding stale Artists/Albums/Tracks (the `reloadAll()` path). The Sync screen
   showed the fresh "Load Playlists" view with **no stale red error text**
   (the `clearError()`-on-save path).

### Extra: "clear the error state on save" (build item 4), verified on a clean chain

- Airplane mode on → force-stop → cold start: red banner with the raw
  `DioException … Network is unreachable` text rendered (the pre-U1 G1 state;
  expected to still exist).
- Airplane mode off; same process (PID tracked, 10380); banner still present.
- Drawer → Server (screen verified) → Save the identical URL → returned to Library
  → **banner gone**, with no successful fetch in between (process never
  cold-started, so the clear came from the save path, not a re-fetch).

### Restore (device left in its original state)

After check 5 the device had an empty library and the fake host configured.
Restored: URL back to `http://192.168.1.13:3689` (host-change dialog → Keep
library), Sync screen → Load Playlists → reselected Brass + Soul → manual sync →
worker logged `Background sync completed: 93 tracks downloaded in 509478ms
(status=success)`. Final state verified: Library shows Brass 33 + Soul 60, no
error surfaces, URL correct in the drawer header, playback verified working
(media session `state=PLAYING`, position advanced 28.5s → 55.0s between samples),
then paused and the queue cleared (Clear queue → confirm) so no test queue
persists. Airplane mode confirmed off (`airplane_mode_on = 0`). The OwnTone
server at 192.168.1.13 was never touched; every failure was induced app-side.

## PHASE U0: COMPLETE

### GO/NO-GO CHECK

What it was: a server-URL change that is cosmetic (or a same-host change) must
not raise the destructive wipe dialog, and a host change must default to keeping
the library; an intentional discard must still work and leave the UI matching the
DB.

Did you run it: YES (all five checks above, on emulator-5554).

What you observed: checks 1–4 produced no dialog / no wipe with the library
intact; check 5 wiped cleanly and the Library matched the empty DB immediately
(empty state, no stale rows in any tab); restore re-synced 93 tracks with
status=success.

### OBSERVED — things I did and saw, on the emulator, by hand

- Saved the unedited URL → no dialog, Library with Brass 33 + Soul 60 (check 1).
- Saved `http://192.168.1.13:3689/` → no dialog (old code would have dialogued),
  library intact; cold start with the slash URL → no error surface; saved the
  no-slash form over it → no dialog (check 2).
- Saved `http://192.168.1.13:9999` → no dialog, snackbar "Server address updated.",
  library intact; restored `:3689` the same way (check 3).
- Saved `http://192.168.1.99:3689` → "Different server?" dialog, Keep library the
  primary action; tapping it kept Brass + Soul and showed "…Your library was
  kept." Restored the real host via the same dialog (check 4).
- Host change → "Start fresh" → "Keep Files" → reset → Library immediately showed
  "No Music Synced" (no stale rows in any tab); Sync screen in fresh-setup state
  with no stale red error text (check 5).
- Airplane-mode cold start → red DioException banner rendered; disabled airplane
  mode (same PID), saved the identical URL → banner gone (item 4).
- Re-sync after the wipe: worker log `93 tracks downloaded … status=success`;
  Library repopulated (Brass 33 + Soul 60); playback started from the Brass
  detail's Play button, media session PLAYING with the position advancing;
  queue cleared afterwards.

### NOT VERIFIED — implemented but not exercised, and why

- **Whitespace-only differences on device.** The form validator runs on the raw
  field text and rejects leading whitespace (`startsWith('http://')`) and (per
  `Uri.parse` behaviour) trailing whitespace, so whitespace cannot reach the
  save path through the UI. The normalisation is covered by unit tests
  (`test/server_url_test.dart`); the device checks used the trailing slash,
  which is the reachable cosmetic case.
- **The unparseable-URL branch of the save path** (a non-empty original or new
  value that fails `parseServerUrlIdentity`): it falls through to the
  host-change dialog (the conservative direction — never wipe without asking).
  Not exercisable through the UI because the same validator blocks such values.
  Guarded by unit tests for the parse function.
- **`_wipeAndSave`'s error path** (reset throws → red "Error resetting data"
  snackbar): not induced; no app-side failure mechanism for `resetAppData` was
  available, and inducing one risks real data state.
- **Kotlin side:** untouched; the Gradle unit-test run (see BUILD) is the
  backstop, not a behaviour verification.

### DEVIATIONS — anything not done as the phase specified

- **`BrowseProvider.reloadAll()` added** (not in the spec's file list). The spec
  says "reload browse data after any reset"; `loadData()` only reloads the
  *current* tab, and `hasContent` spans all four lists — so a current-tab-only
  reload would leave the other tabs showing stale rows and keep the tabbed UI up
  on an emptied DB (exactly the desync the review logged). `loadData()` was
  refactored onto a shared private `_loadCategory()`; behaviour for existing
  callers is unchanged (verified by the full Dart suite and by device checks 1–5,
  which exercised tabbed-library rendering).
- **Snackbar wording** on the non-wipe saves ("Server address updated." /
  "…Your library was kept.") and the second dialog's title ("Start fresh?") —
  the spec says "say so if anything is shown at all" and "word the choice around
  what the user knows"; exact strings were not prescribed.
- **Queue not reconciled after a wipe** (adjacent, not fixed, per scope): if a
  queue is live while the user wipes, the queued tracks disappear from the DB
  and play back through the A9 path (skip / "sync again" notice) instead of a
  clean clear. Pre-existing behaviour; the wipe path is U0's only new entry to
  `resetAppData`. Flagging here for a later phase.

### BUILD

flutter analyze: No issues found (0 errors, 0 warnings)
flutter test: All tests passed — 55 (42 pre-existing + 13 new in
`test/server_url_test.dart`)
flutter build apk --debug: Built `build/app/outputs/flutter-apk/app-debug.apk`
./gradlew :app:testDebugUnitTest (JDK 17): BUILD SUCCESSFUL

### UNKNOWN — behaviour I could not explain

- The app process died once during an airplane-mode verification cycle
  (~20:59, between a confirmed-alive PID and a later `am start` that cold-started
  a new PID). No FATAL/crash trace for the app in logcat; one earlier kill was
  my own `force-stop`. The error-clear-on-save check was re-run on a cycle where
  the PID was tracked end-to-end and survived, so the verification stands; the
  death itself is unexplained (emulator process management is the leading
  candidate; no code changed in between).
- The Now Playing sheet opened at some point during queue cleanup without a tap
  I can account for (a bottom-edge swipe that returned the *launcher* in the
  dump, after which the app came back with the sheet open). Mechanism unknown;
  did not affect any verification step (the queue was cleared and confirmed).
