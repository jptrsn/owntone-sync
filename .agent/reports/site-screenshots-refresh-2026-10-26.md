PHASE: Site screenshot refresh (session-driven) — COMPLETE

GO/NO-GO CHECK
  What it was: the six PNGs in `site/assets/screenshots/` regenerated from the
  HEAD build (v0.3.3+22, incl. the invariant-54 lead-free playlist rows), with
  per-screen content-desc assertions before each capture, and zero server-side
  side effects from the playback captures.
  Did you run it:        YES
  What you observed: all six PNGs are 1280x2856; playlist-detail shows track
  rows with **no** numbered leading (0 digit nodes; titles/ratings/durations
  present via content-desc, e.g. `Good People\nThundersmack feat.Honeycomb •
  Brass\nRated 5.0 of 5\n2:58`); now-playing re-shot with artwork
  (`Bloodshot / Youngblood Brass Band / Unlearn`, `Playing from Unlearn`,
  143 KB vs 80 KB for a no-artwork track); queue sheet full of TMZ rows with
  `Clear queue` content-desc; server counts unchanged after playback.

OBSERVED — things you did and saw, on the emulator, by hand
  - Booted OwnTone_U2_API_36 (own PID), dnd on, animations 0, pm grant;
    `pm clear`; launched `flutter run --profile -t test/driver_main.dart`;
    `dumpsys package` confirmed **versionName=0.3.3** (previously the installed
    APK was 0.2.0 — stale-build hazard caught).
  - Drove first-run setup over raw `ext.flutter.driver` JSON-RPC (set_semantics
    → ByTooltipMessage/ByText/ByType taps, focused `enter_text` for the URL);
    tapped `Grant Permission` → uiautomator `Allow` → DocumentsUI (opened
    pre-set to Music) `USE THIS FOLDER` → `ALLOW`; `Load Playlists` → tapped
    `Brass` → verified `1 playlists selected` → Descendant-tapped the
    ElevatedButton `Sync`; after `logcat -c`, observed
    `Background sync completed: 33 tracks downloaded`.
  - Captured playlist-detail after `waitFor "Good People"` + a uiautomator
    assertion that counted **0** numbered leading nodes.
  - Captured album-detail after `find_scroll "Unlearn"`, `find_scroll
    "Pastime Paradise"`; artist-detail after `Too Many Zooz` (`6 albums • 13
    tracks`); search after `enter_text "zooz"` + `find_scroll "Bad Guy"`.
  - Playback pair with emulator music stream muted: tapped search result /
    album `Play`, paused < 2 s (MediaSession log: PLAYING→PAUSED, position
    11 ms), opened sheet via ByType `MiniPlayer`, captured now-playing then
    queue (gate: `Queue` tooltip; `Clear queue` present as content-desc).
    Tapped `Clear queue` afterwards.
  - Server safety checks before/after: `/api/player` stayed `state: stop`;
    `Bad Guy` (track 1867) play/skip = 14/0 both times (exact API baseline
    taken first); sync screen showed `No playback events waiting to sync`
    (outbox empty ⇒ nothing ever queued; `Bloodshot` 18/3 was pre-existing —
    its pre-value was not recorded before play, see NOT VERIFIED).
  - Torn down: killed my `flutter run` + emulator PID, `git checkout --
    pubspec.yaml pubspec.lock`, deleted `test/driver_main.dart`.
    `git status` shows only the six modified PNGs (plus another session's
    `.agent/android-auto-prep.md`, untouched).

NOT VERIFIED — implemented but not exercised, and why
  - Visual quality of the PNGs: the agent has no vision. A human must open all
    six before committing (sizes/dimensions/content-desc only are proven).
  - `Bloodshot` counts pre-playback were not recorded (baseline taken only for
    Bad Guy); the empty outbox line makes server-side change impossible, but
    the 18/3 was assumed pre-existing rather than proven.
  - The `flutter-agent-lens` screenshot tool itself was not used (profile
    builds lack `ext.flutter.inspector`; `adb exec-out screencap` was used,
    matching the Oct-22 pass).

DEVIATIONS — anything not done as the phase specified
  - The first `now-playing.png` captured `Bad Guy`, likely one of the 12
    Brass tracks synced without artwork (80 KB); re-shot from the `Unlearn`
    album (143 KB). First shot overwritten.
  - The earlier scripted attempt (`tool/refresh-site-screenshots.sh`) was
    deleted at the user's instruction before this pass; nothing from it ships.

BUILD
  flutter analyze: not re-run for this pass — no app code changed (temp
  driver entry + dev-dep added and removed; tree verified clean afterwards).
  flutter build apk --debug: not run (no code change).

UNKNOWN — behaviour you could not explain
  - `uiautomator dump` intermittently returns an unlabeled/empty Flutter tree
    even with semantics on (worked on retry; exact trigger not determined —
    animation race suspected).
  - After sync completes, the Library briefly showed `No playlists synced`
    (stale empty state) while the DB demonstrably held 33 tracks
    (`0 tracks downloaded` on re-sync, `Brass\n33 tracks` after a back-nav).
  - `scrollUntilVisible` is rejected as `Unsupported command kind` by this
    Flutter version's driver extension despite existing in the protocol
    (worked around with swipe-loop + 2 s waitFor).

Evidence: this report. The procedure is captured for re-runs at
`.opencode/skills/refresh-site-screenshots/` (SKILL.md + references/), routed
from AGENTS.md.

---

AMENDMENT (same session): album-row number slot 40 px → 32 px — COMPLETE

GO/NO-GO CHECK
  What it was: keep `track_number` on album rows (user reversal from an
  earlier "remove them" ask) but shrink the leading slot to fit 3 digits with
  acceptable padding; re-shoot `album-detail.png` from the changed build.
  Did you run it:        YES
  What you observed: `album-detail.png` (213 KB, 1280x2856) captured from the
  build containing the change; rows still render their numbers.

OBSERVED — things you did and saw, on the emulator, by hand
  - Changed both `SizedBox(width: 40)` wrappers in `library_rows.dart`'s
    `TrackRow` to 32 px (caller-supplied number + `isCurrent` `graphic_eq`
    slot, kept equal so rows stay aligned; 20 px icon still seats).
    bodyMedium digit ≈ 7.8 dp → 3 digits ≈ 24 px + ~4 px/side padding.
  - `flutter analyze` clean; `flutter test` 159 passed; `flutter build
    apk --debug` built; no test pinned the old width.
  - Booted my OwnTone_U2_AVd (its console happened to claim `emulator-5554`
    this time — confirmed via `adb -s … emu avd name` that the device I drove
    was my own process/AVD, 1280x2856), `flutter run --profile` →
    `versionName=0.3.3`; navigated Albums → `Unlearn`; rows present in
    content-desc with numbers: `1\nBloodshot\nBrass\nRated 4.0 of 5\n5:02`,
    `2\nAcousticon Theme…`; screencap → `album-detail.png`.
  - Torn down (killed my `flutter run` + qemu; `git checkout --
    pubspec.yaml pubspec.lock`; deleted `test/driver_main.dart`).

NOT VERIFIED — implemented but not exercised, and why
  - Visual judgment of "acceptable padding": needs the human's eyes on the PNG.

DEVIATIONS — anything not done as the phase specified
  - Invariant 54 updated in place (40→32 px + rationale) — user-directed
    change, not silent; the historical "stole 40 px" sentence kept as-is.
  - First two emulator launches died (GUI variant never registered with adb;
    the tool call's cleanup reaped one). A third launch with
    `</dev/null … & disown` survived. Lesson: detach fully.
  - `-gpu auto` GUI mode also broke snapshot loading (GLES renderer change →
    cold boot, userdata intact but `versionName` reverted in dumpsys until
    `flutter run` reinstalled); subsequent runs used `-no-window -no-audio`.

BUILD
  flutter analyze: No issues found!
  flutter build apk --debug: ✓ Built build/app/outputs/flutter-apk/app-debug.apk

UNKNOWN — behaviour you could not explain
  - The GUI emulator (`-gpu auto`) booted ("Boot completed") but never
    appeared in `adb devices` and eventually exited; the headless variant
    behaves normally. Suspected GPU/window-server interaction; not chased.

