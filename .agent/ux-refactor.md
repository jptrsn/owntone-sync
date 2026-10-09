# UX Refactor — Review and Build Plan

**Status:** ACCEPTED. The decisions in §6 are settled and the phases are the
work order.
**Reviewed:** 2026-10-08 · **Decisions taken:** 2026-10-08
**Scope:** Information architecture, navigation, and state presentation. The
playback core (handler, controller, index model — invariants 1–7, 19, 23–25) is
settled and is **not** in scope.

> ## ▶ Building a phase? Go straight to **§6 Build plan**.
>
> §6 carries the settled decisions, the five phases (U0–U4) with their build
> specs and acceptance tests, and the sequencing. It is self-contained — a
> session told to build one phase needs nothing above it.
>
> §§1–5 are the review that produced those phases: the screen inventory, the
> comparison against two reference players, the gap analysis, the ranked changes
> with rationale, and what was deliberately excluded. Read them for *why* a
> phase is shaped the way it is, or when a phase turns out to be wrong.

---

## What I inspected, ran, and did not look at

**Read in full:** `AGENTS.md`, `.agent/player-ux-spec.md`, `.agent/invariants.md`,
`.agent/blockers.md`, `.agent/player-refactor-plan.md` (§2 architecture), and every
file under `lib/presentation/` (all 13 screens/sheets, `app_drawer`, `mini_player`,
`player_scaffold`, `library_rows`, the two providers), `lib/main.dart`,
`lib/data/repositories/owntone_api_repository.dart`, and the error/status paths of
`BackgroundSyncWorker.kt` / `SyncProgressBroadcaster.kt`.

**Ran on `emulator-5554` (debug build of `main`, v0.2.0+18), attached
`flutter run` for the console, drove the UI with `uiautomator dump` + `input tap`:**

- **State 1 — on-LAN, server reachable (baseline).** Visited: Library (all four
  tabs), drawer, Sync (including expanded Sync Options), Schedule, Server, Storage,
  History (expanded), About, Brass playlist detail, Black Pumas album detail,
  Search (live query), Now Playing sheet, Queue sheet, the album-row context menu.
  Started playback in three different places; confirmed auto-queued context,
  sheet, and mini player all work.
- **State 2 — airplane mode** (`cmd connectivity airplane-mode enable`, verified
  `ENETUNREACH`). Cold-started the app twice. Visited every screen above in that
  state. Tapped **Sync while offline** and observed the outcome. Dismissed the
  banner, force-stopped, relaunched, and confirmed it returns.
- **State 3 — network up, server unreachable.** Set the app's URL to a closed port
  (`127.0.0.1`, twice: `:3689` and `:9999`) through the app's own Server
  Configuration screen, cold-started, and observed every screen. The URL change
  turned out to be destructive (see §3, G6) — I restored the real URL
  (`http://192.168.1.13:3689`) through the same screen and re-synced Brass + Soul
  (93 tracks, ~5.5 min) so the device ends in its original state. The server at
  `192.168.1.13` was never touched; every failure was induced app-side.
- **State 4 — never configured** (`pm clear`, last). Walked the complete first-run
  flow on device: notification prompt → Library empty state → Sync screen (storage
  permission → system storage prompt → SAF folder picker → folder-allow prompt →
  server not configured → Server Configuration → Load Playlists → select
  Brass + Soul → Sync). Re-synced (93 tracks, ~4 min). Final state verified:
  library populated, 2 playlists selected, no error surfaces, sync icon back to
  normal.

**Did not look at:** the Kotlin sync worker beyond its status/error message
formatting; the audio handler and controller (out of scope); physical-hardware
behaviours (Bluetooth/AVRCP, Doze — spec §7B); the two defects logged 2026-10-08
(empty Now Playing sheet space, detail-title overlap — left to separate work per
the task; §5 says where my proposals touch their screens or not); reference players
on device (I reasoned from knowledge of their UIs, stated in §2). Screenshots and
`uiautomator` dumps for every state × screen are in `/tmp/owntone_verify/`
(`s{1..4}_*.png`, `s{1..4}_*.xml`).

**Known instrument caveats applied:** `uiautomator dump` intermittently returns an
empty or stale window while the Now Playing sheet is open (invariant 29) — for that
screen I used dumps that succeeded plus screencaps; attribute values containing `"`
use single-quote delimiters (invariant 18), so all presence checks were raw
substring matches.

---

## 1. Screen inventory

Enumerated from code and confirmed on device. "Where" = how the user reaches it.

### Routes (full screens, pushed on `MaterialPageRoute`)

| # | Screen (file) | Where | What it contains | What it is for |
|---|---|---|---|---|
| 1 | **Library** `library_screen.dart` | Cold-start home; stays mounted forever | AppBar: drawer handle, "Library", sort popup (per-tab options), search icon, sync-status icon (spinner while syncing / `cloud_done` / `cloud_done` + red dot on error). Body: dismissible sync-error banner (when `_lastError` is set) above a `TabBar` (Playlists / Artists / Albums / Tracks) + four list views. Alternates to a full-screen spinner or the "No Music Synced / [Set up sync]" empty state. Mini player docked via `PlayerScaffold`. | Browsing and starting playback. The app's home. |
| 2 | **Playlist detail** `playlist_detail_screen.dart` | Playlist row tap (Library, Search) | Collapsing header (queue icon, "N tracks", title), **Play** + **Shuffle**, numbered track rows. Mini player docked. | Start/queue a playlist; play in context. |
| 3 | **Album detail** `album_detail_screen.dart` | Album row tap; Now Playing → "Go to album" | Collapsing header (art, artist, "N tracks • duration • year"), Play + Shuffle, track rows. Mini player docked. | Same, for albums. |
| 4 | **Artist detail** `artist_detail_screen.dart` | Artist row tap; Now Playing → "Go to artist" | Collapsing header (initials avatar, counts), Play + Shuffle, tracks grouped by album. Mini player docked. | Same, for artists. |
| 5 | **Search** `search_screen.dart` | Library app-bar search icon | Search field in the app bar, debounced query over the local DB, results grouped Playlists / Artists / Albums / Tracks; empty-query and no-results states. Mini player docked. | Find anything in the synced subset. |
| 6 | **Sync** `sync_screen.dart` | Drawer; app-bar sync icon; Library empty-state button; queue-exhausted snackbar action | Five states: *syncing* (progress card + Cancel); *no storage permission* (Grant Permission); *not configured* (Configure Server); *initial setup* (URL + Load Playlists); *playlist selection* ("N playlists selected" + Sync button, pending-events line, orange "Offline – showing cached playlists" banner when offline, Sync Options expansion: delete-orphaned toggle + schedule row, refreshable playlist checkboxes, red `lastError` footer). | Sync configuration and manual sync. **No mini player here** (plain `Scaffold`). |
| 7 | **Schedule** `schedule_config_screen.dart` | Drawer; Sync Options | Enable switch (+ battery-optimization dialog and orange warning banner when enabled without the exemption), missed-sync red banner, time picker, day chips, charging/Wi-Fi conditions, Save. | Background sync cadence. No mini player. |
| 8 | **Server** `server_config_screen.dart` | Drawer; Sync "not configured" view | URL form with local-network-only `http` validation; Save. Changing the URL from a non-empty value raises a **destructive** dialog (Cancel / Keep Files / Delete Files) that wipes all synced playlists, tracks, and history. | Point the app at a server. No mini player. |
| 9 | **Storage** `storage_screen.dart` | Drawer | "Music folder / Folder access granted (or No folder access)" card + Grant/Change button. No path, size, or file counts. | SAF folder grant. No mini player. |
| 10 | **History** `history_screen.dart` | Drawer | Expansion cards per sync run: status icon/color, Manual/Scheduled chip, relative time, "N playlists • N tracks downloaded", per-run Plays/Skips (or "No events"), per-playlist errors. | Audit sync runs and uploaded statistics. No mini player. |
| 11 | **About** `about_screen.dart` | Drawer | Icon, "OwnTone Sync", **"Version 0.1.8" (hard-coded; the app is 0.2.0+18)**, a self-description that leads with syncing, server-URL card. | Identity. No mini player. |

### Sheets and dialogs (modal)

| # | Sheet (file) | Where | What it is for |
|---|---|---|---|
| 12 | **Drawer** `app_drawer.dart` | Library hamburger | Header: "OwnTone" + raw server URL (or "Server not configured"). Items: Sync, Schedule, Server, Storage, History, About, divider, **Sync now** (starts a sync directly, or opens Sync if not configured). |
| 13 | **Now Playing** `player_screen.dart` | Mini player tap / swipe-up | Modal bottom sheet, 0.92 × screen height, drag handle, artwork (tap → rating overlay), title/artist/album, "Playing from …", seek bar with times, shuffle/prev/play/next/repeat, queue button, overflow (Go to album / Go to artist / Track info). |
| 14 | **Queue** `queue_sheet.dart` | Now Playing queue button | 0.8-height sheet: Clear-queue button (confirm dialog), reorderable/swipe-removable rows, ⋮ menu (Remove / Move to top / Move to bottom), auto-scroll to current, tap-to-jump. |
| 15 | **Row context menu** `library_rows.dart` | Track/playlist/album/artist row ⋮ or long-press | Track: Play next · Add to queue · Rate… · Go to album · Go to artist · Track info. Playlist: Play · Shuffle · Add to queue. Album: + Go to artist. Artist: Play all · Shuffle all · Add to queue. |
| 16 | **Rate sheet** `library_rows.dart` | Row menu "Rate…" | Title/artist + drag star control + "Release to save · synced on next sync" + Done. |
| 17 | **Track info dialog** `library_rows.dart` / `player_screen.dart` | Row menu; Now Playing overflow | Metadata (the sheet variant also shows the absolute local file path). |
| 18 | **Clear queue confirm** `queue_sheet.dart` | Queue sheet | Confirm playback stop. |
| 19 | **Change server confirm** `server_config_screen.dart` | Server Save on URL change | The destructive wipe dialog. |
| 20 | **Battery optimization** `schedule_config_screen.dart` | Schedule enable / "Fix" | Prompt + persistent orange warning banner while un-exempted. |

### The always-present chrome

- **Mini player** `mini_player.dart`: docked on Library, all three detail screens,
  and Search (every `PlayerScaffold` screen). Artwork, title, artist, thin progress
  bar, play/pause, next. Zero height with no track. **Absent on all six drawer
  destinations** — confirmed on device with a track actively playing: open Sync and
  the only way to control playback in-app is to navigate back to a `PlayerScaffold`
  screen.

### What is NOT a screen (for completeness)

- Sort is a popup menu in the Library app bar (per-tab options, persisted per
  category — B2).
- There is no "downloads", "storage usage", "playback settings", "now-playing
  options", or "account" surface of any kind.

---

## 2. Reference comparison

**Two players: Spotify and Auxio.** Basis of knowledge, stated plainly: I have not
run either on this device (installing store apps on the emulator is out of scope for
this session); I am reasoning from long familiarity with their UIs and public
documentation/screenshots. Where a claim is about a version-specific detail it is
marked as such.

### Spotify (subscription service, offline-capable)

- **Top level:** bottom tab bar — Home / Search / Your Library (mobile). Search is a
  *peer* of the library, not a modal.
- **Player:** a persistent mini-player docked above the tab bar on **every**
  screen; tap/drag expands to full Now Playing (shared-element artwork, never a
  pushed route). The player chrome survives all navigation, including Settings.
- **Configuration:** buried. Server, credentials, and sync machinery have **no UI
  presence at all** — "Downloads" is a content-management section inside Library
  (per-playlist/album download toggles, "Downloaded" badges on rows). A first-time
  user never sees a network address, a sync screen, or a sync status icon.
- **Offline model:** offline is not an error state in the UI. Downloaded content
  plays; non-downloaded content is greyed with an explicit "not available offline"
  marker *on the row*. There is no persistent banner, no badge, no exception text.
  The concept of "the server" is invisible; the app communicates content
  *availability*, not connection health.
- **Freshness:** Spotify also does not show "last synced" — but its absence is not
  signalled as anything at all.

### Auxio (Material 3 local library player)

- **Top level:** a few browse categories (Home/Artists/Albums/Playlists/Tracks —
  varies by version) behind a bottom bar or a single Home.
- **Player:** docked mini-player everywhere; full player on tap.
- **Configuration:** exactly **one** settings destination (a gear icon) holding a
  flat list: now-playing options, cache, theme, etc. Nothing about connectivity,
  because the product has none.
- **Offline model:** nonexistent as a state — the entire app, by construction, works
  with zero connectivity. There is no icon, banner, or message that could ever read
  as a fault.

### What the comparison isolates

| Question | Spotify | Auxio | OwnTone Sync (v0.2.0) |
|---|---|---|---|
| What is top-level? | 3 tabs (Home, Search, Library) | Browse categories | 1 screen + 4 inner tabs; everything else is a **drawer** |
| Where does playback live? | Docked mini + full expand, on every screen | Same | Docked mini + 0.92-height sheet, but **gone on 6 of 11 destinations** |
| Where does configuration live? | No user-visible network config; "Downloads" section | One settings screen | **All six drawer items are sync configuration**; drawer header leads with the raw server URL |
| What does the app call itself? | Spotify | Auxio | **"OwnTone Sync"** (launcher label, About, app title) |
| How is "server unreachable" shown? | Not shown; per-row availability | N/A | Persistent red banner + red app-bar badge, raw `DioException`/`SocketException` text, reappears every cold start |
| How is "never configured" shown? | Onboarding flow | Storage/folder onboarding | A **red error banner** ("Server URL not configured") on the home screen, plus a five-step unconnected setup sequence |
| When is content fresh? | Not stated (and not signalled) | N/A | Not stated anywhere — only failure is ever communicated |

The structural point: both references are players whose *default, silent state is
"working"*, and whose configuration is a place you go to, not a status the app
performs for you. This app inverts that: its default visible state is a
connection-status assertion, and its only persistent status is a failure.

---

## 3. Gap analysis

### The connectivity states, as observed, and what each should say

The task's acceptance test: **in airplane mode with music synced, the app should
feel complete and working.** Recorded per state, per screen (S = Library, D =
drawer, Y = Sync, Sd = Schedule, Se = Server, St = Storage, H = History, A =
About, X = detail/search screens):

**State 1 — on-LAN, server reachable (baseline).**
Everything works; no error surfaces anywhere. The only connection information the
app shows is a plain `cloud_done` icon with tooltip "Sync" and the raw URL in the
drawer header. There is **no "last synced" information anywhere** — the library's
freshness is invisible. What it should communicate: quiet confirmation (icon) +
freshness ("last synced 2h ago" — the data already exists in `sync_history`).

**State 2 — airplane mode (the normal case).**
Observed on every screen, cold start:

| Surface | What is shown | Persists? | Reappears? | Blocks? |
|---|---|---|---|---|
| Library | **Red banner** above the tabs: `Failed to fetch playlists: DioException [connection error]: … SocketException: Connection failed (OS Error: Network is unreachable, errno = 101), address = 192.168.1.13, port = 3689` | **Yes — no auto-dismiss**, no timer | **Yes — on every cold start** (verified: dismissed, force-stopped, relaunched, back); also on any refresh that re-fails | No — browsing, search, playback all work; but it permanently displaces the first row of the home screen and turns the app-bar icon into a red-badge error state |
| Library app bar | `cloud_done` + red dot; tooltip = the full raw error | Yes, with the banner | Yes | No |
| Drawer | Unchanged: raw URL, **no indication at all** that the server is unreachable | — | — | — |
| Sync | Orange banner "Offline – showing cached playlists" (good wording) **+** playlist rows in grey italic "(offline)" **+ a red footer with the same raw `DioException` text, which has no dismiss button on this screen** | Red footer persists | Yes | No — but the **Sync button stays enabled**; tapping it runs a sync that is guaranteed to fail (verified: worker logs `ENETUNREACH`, UI returns, **a new "Sync Failed … 0 tracks downloaded … Manual" History row is written**, and the banner/badge flip to "All 2 playlists failed to sync") |
| Schedule / Server / Storage / About | No connectivity indication at all | — | — | — |
| Detail / Search / Now Playing | No banner (the error surface is Library-only) | — | — | — |
| Playback | **Fully functional** (played, seeked, sheet, mini player all worked) | — | — | No |

What it should communicate: that offline is the *expected* mode for a synced
library — at most a neutral, self-clearing note ("Offline — playing your synced
library"), and never red, never an exception string, never reappearing after a
dismissal within a session. The Sync screen already has the right orange banner;
the red footer should not exist next to it.

**State 3 — network up, server down (a genuine fault).**
Observed: identical treatment to State 2 — same red banner, same badge, same
reappearance cadence. The only visible difference is the exception text
("Connection refused" instead of "Network is unreachable"), and that text is
**actively misleading**: with `:3689` configured the message read
`address = 127.0.0.1, port = 37830`; with `:9999` it read `port = 43756`. Two
verified data points — the raw `SocketException` in this path reports a port the
user did not configure (a Dart VM artefact of refused-loopback connects), so the
"details" shown to the user are wrong, not merely technical.

What it should communicate: the one state where an error is justified — a specific,
actionable message ("Can't reach `192.168.1.13` — is your server running?"),
persistent until resolved, with the raw detail demoted to History if anywhere.
**The app does not distinguish States 2 and 3 at all**: there is no connectivity
test anywhere in `lib/` (zero references to a connectivity API); `_isOnline` is a
boolean flipped only by `fetchPlaylists()` success/failure, and it is only ever
read by the Sync screen. The app tests exactly one thing — "did the server answer
the one fetch made at cold start" — and treats every non-answer as a fault.

**State 4 — never configured (first run).**
Observed: the system notification-permission prompt is the app's *first* word.
Then the Library shows a **red error banner reading "Server URL not configured"**
(the never-configured state is stored in `_lastError` and rendered with the same
red error treatment as real failures) above the "No Music Synced / Sync some
playlists to start browsing your music / [Set up sync]" empty state; the app-bar
icon renders as `cloud_done` **plus red dot** — a "synced" checkmark with an error
badge, on a machine that has never synced. The drawer says "Server not
configured". Setup proceeded as: Sync screen → "Storage Permission Required" →
system storage prompt → SAF picker → "access files in Music?" prompt → "Server Not
Configured" view → Server screen (field **pre-filled with the example
`http://192.168.1.100:3689` as real, saveable text** — an unattended Save would
configure a dead server) → save → initial-setup view with the **stale red text
"Server URL not configured" still showing under the Load Playlists button** (the
startup error is never cleared when configuration completes) → Load Playlists →
select → sync → library populates.

What it should communicate: setup, not error. A guided flow (spec C1 SHOULD
already calls for server → folder → playlists → first sync, shown once), with the
notification prompt deferred until its purpose is visible.

### The divergences, classified

**Deliberate differences — driven by the real constraint (a synced subset from a
usually-unreachable server). Not defects; keep them:**

- **D1. The library is a subset, not the device library.** Reference players browse
  everything on disk or a complete catalog; this app browses the user's selected
  playlists. Consequence worth preserving: no device-wide scan, no "add files",
  and the sync surface must exist at all — there is no reference player with a
  server to configure.
- **D2. Server configuration exists.** Spotify hides all network config; Auxio has
  none. Here it must exist, *somewhere*. The defect is not its existence but its
  *frequency of appearance* (see D4–D7).
- **D3. Play/skip write-back and History.** No reference has this; it is the reason
  the sync exists (smart playlists). Keeping History visible is correct — it is the
  audit trail the user asked for.
- **D4. Single home + drawer instead of bottom tabs.** Spec B1 locked "no bottom
  nav" in Phase 4. That remains right for a library this size; the problem is what
  lives *inside* the drawer, not that a drawer exists.

**Problems — the sync-tool mental model leaking into the player:**

- **G1. Offline is framed as a fault (the headline).** One `String? _lastError` +
  one `bool _isOnline` is the entire connection model. Any failed contact
  (startup fetch, manual sync, refresh) becomes red text on the home screen and a
  red badge, with the raw library-internal message intact — including the line
  "This indicates an error which most likely cannot be solved by the library",
  which is a note *to a developer*, shown to the user. It is persistent,
  reappears on every cold start, and the only dismissal is per-session. States 2,
  3, and 4 are rendered identically. This is the class of problem the user's
  report names, and it is not a widget bug: the app has no concept of "offline is
  normal" at all.
- **G2. Startup is structured around the server.** `_initialize()` calls
  `fetchPlaylists()` unconditionally on every cold start; the *failure of that
  call* is the app's first word on every offline launch. The local library needs
  no network to render — the fetch is a background refresh that has been
  over-weighted into a boot gate for the UI's self-presentation.
- **G3. Freshness is invisible; only failure is communicated.** There is no
  "last synced" anywhere. A player living on a synced subset should lead with how
  current the local copy is; this one leads with whether the connection worked at
  09:12. The drawer header shows the raw URL (infrastructure detail) where a
  status line belongs.
- **G4. The sync UI is the app's navigation.** All six drawer destinations are
  sync-tool screens; the drawer is the only navigation in the app; the app-bar
  carries a permanent sync-status slot on the home screen; "Sync now" is a drawer
  action; the app is *named* "OwnTone Sync" (launcher label) and the About screen
  describes it as "Syncs playlists to the device, plays them offline, and sends
  play and skip counts back". Phase 4 moved sync out of the tabs, but every other
  surface still reads "sync tool with a player". This is, concretely, why the user
  still feels sync is the main value prop: the player is one of eleven
  destinations and is unnamed in the chrome; the sync machinery is named
  everywhere.
- **G5. The player disappears on the sync side.** The six drawer destinations use
  plain `Scaffold`, so the mini player — and thus all in-app playback control —
  vanishes whenever the user goes anywhere near sync (verified with music playing).
  Reference players keep the player on *every* screen. Two apps sharing a body.
- **G6. Server configuration is a wrecking ball.** Any change from a non-empty URL
  — including a one-character typo fix, or *restoring* the correct URL after a
  mis-edit — triggers "delete all synced playlists, tracks, and sync history"
  (Keep Files keeps the audio files, but the library metadata is gone and the
  library re-syncs; measured ~5.5 min for 93 tracks, more with artwork). There is
  no test-connection step, the example URL is pre-filled as saveable text, and
  after the wipe the UI desyncs from the DB: the Playlists tab kept showing stale
  in-memory rows while Artists went empty, the Sync screen reverted to the
  first-run "Load Playlists" view, and the stale red error text persisted under it.
  Verified end-to-end while producing State 3.
- **G7. Offline sync is recorded as a failure.** The Sync button and "Sync now"
  are enabled in airplane mode; a tap writes a "Sync Failed" History row and
  re-arms the error surfaces. The app records the user's normal state as an
  incident. (Related, separate, already-logged: the 2026-10-06 "Playlist 4 of 3"
  notification text is the same disease in the worker.)
- **G8. First run opens on an error.** Never-configured is stored in `_lastError`
  and shown as a red banner; the app-bar icon shows a synced-checkmark with an
  error dot; the notification prompt precedes any explanation of what the app is.
- **G9. Stale facts in the chrome.** About says "Version 0.1.8" (hard-coded;
  pubspec is `0.2.0+18`). The Now Playing / row Track-info dialogs show absolute
  internal file paths to the user.

---

## 4. Proposed changes

Ordered by value to the daily loop, not by ease. Each names the problem, the
change, the spec story it serves, the cost, and the risk. **P1 is the acceptance
test for this whole review.**

### P1 — A four-state connectivity model, with per-state presentation  *(highest value)*

**Problem (G1, G2, G8):** one error string + one boolean; offline = persistent red
exception text; states 2/3/4 indistinguishable; the unconfigured icon reads as
"synced + error".

**Change:** introduce an explicit, named state in `SyncProvider`, derived from
*both* a connectivity signal and a server-response signal:

| State | Derived from | Library app bar | Banner on home | Drawer header |
|---|---|---|---|---|
| `unconfigured` | no URL | neutral "setup" icon (e.g. outlined cloud, **no red dot**) | none — the empty state *is* the setup entry | "Not set up yet" |
| `reachable` | last server contact OK | `cloud_done` | none | server name/host + **"last synced Xm ago"** (P3) |
| `offline` | no connectivity (or no route) | neutral icon, **no badge** | none persistent; at most one auto-dismissing note ("Offline — playing your synced library"), once per session | "Offline" |
| `unreachable` | connectivity up, server refused/timeout | error badge (the only red state) | persistent, **human** text: "Can't reach `192.168.1.13:3689` — is your server running?" + a "Retry" action | host + "server not responding" |

Rules that fall out:

- **Raw exceptions never reach the UI.** `lastError` becomes `(kind, message)`;
  the full detail goes to History / logs only. (Kills the DioException text, the
  "cannot be solved by the library" line, and the wrong-port text in one stroke.)
- **The cold-start fetch stops being a boot gate.** It runs, but its failure only
  *classifies* the state; it no longer sets a user-visible error. (G2.)
- **No state ever blocks playback or browsing.** (Already true; making it a rule.)
- Dismissal semantics: the `offline` note, if shown at all, dismisses and stays
  dismissed for the session; the `unreachable` banner persists (it is a real
  fault) but is human-readable and retryable.

**Story:** the product thesis (spec §1) — "sync is a background capability"; C2
("visible but not intrusive"); the task's State-2 acceptance test.

**Cost:** moderate. State classification in `SyncProvider` (~a day), per-state
rendering in `library_screen.dart` (app-bar action + banner), drawer header line,
and the Sync screen's dual framing (keep the orange banner, drop the red footer —
it becomes state-driven). **One new dependency, flagged per the constraints:
`connectivity_plus`** (the standard small connectivity plugin; without it the only
classifier is "which errno did Dio return", which is how we ended up unable to
tell States 2 and 3 apart at all — that is exactly the defect). If a new
dependency is unacceptable, the fallback is to classify from the fetch outcome
plus a manual "I'm offline" heuristic, but I do not recommend it: the whole point
is distinguishing 2 from 3, and errno-sniffing is a lie.

**Risk:** misclassification (captive portals, metered data, a server that is up
but slow). Mitigation: prefer *neutral* over *error* when in doubt (an
unclassified non-answer renders as `offline`, never `unreachable`); the `unreachable`
label is used only for connection-refused / DNS-failure / timeout *while a
network path exists*; playback is gated on nothing in any state. Invariant watch:
none of the 36 invariants constrain this surface; the sync *pipeline* is untouched
(additive UI-side change only, per the working agreement).

### P2 — Keep the player visible on every screen

**Problem (G5):** all six drawer destinations drop the mini player; music keeps
playing but in-app control vanishes.

**Change:** wrap `SyncScreen`, `ScheduleConfigScreen`, `ServerConfigScreen`,
`StorageScreen`, `HistoryScreen`, `AboutScreen` in `PlayerScaffold` (they each take
an `appBar` — a one-line-per-screen change; `MiniPlayer` is zero-height at idle so
there is no cost when nothing plays).

**Story:** B4 (the mini player is "docked … whenever there is a current track" —
the settings screens are an oversight, not a design); the §2 comparison row "the
player chrome survives all navigation".

**Cost:** small (an hour).
**Risk:** low. Invariant 16 (dock by layout, never overlay) is *strengthened* by
this; the Phase-5 warning "no FAB on any scaffold that shows snackbars" is
respected (none of these screens adds a FAB; snackbars on these screens already
work via the app-level messenger). **Screen-touch note:** none of the two
2026-10-08 defects live on these screens.

### P3 — Communicate freshness, not just failure: "last synced"

**Problem (G3):** the user cannot tell how current the local library is; the only
status the app ever volunteers is a failure.

**Change:** read the newest `sync_history` row (data exists; History already
renders it) and show "Last synced 2h ago" / "Last sync failed 3d ago" in the
drawer header under the server line, and as the app-bar sync icon's tooltip.
First-sync-complete gets the icon's positive state.

**Story:** C1 ("once configured … invisible afterwards" — invisibility means
*quiet confidence*, which requires a positive status to exist), C3 ("the library
reflects the last sync" — currently only the *content* reflects it).

**Cost:** small (a query + two text slots).
**Risk:** negligible. (Do not add a live "syncing…" percentage to the app bar —
that would re-foreground the machinery; the existing spinner-while-syncing is the
right ceiling.)

### P4 — Stop recording offline sync as a failure

**Problem (G7):** Sync / "Sync now" work in airplane mode and produce "Sync
Failed" History rows + re-armed error surfaces for an expected condition.

**Change:** when state is `offline` (P1), disable the Sync button and "Sync now"
with helper text ("You're offline — syncs when you're home"). The `unreachable`
state keeps the button enabled (that is the state where a retry is useful). No
worker change: the app simply does not enqueue a run it knows cannot connect.

**Story:** C2; the State-2 acceptance test ("anything that makes it feel broken is
a finding" — a failure row in History is exactly that).

**Cost:** small.
**Risk:** a user who wants to force-try with connectivity *present* can (state
`unreachable` keeps it enabled); a user on flaky Wi-Fi sees the button flip
enabled/disabled with connectivity — that is the point, and the helper text says
why. (The schedule's charging/Wi-Fi conditions already exist on the worker side;
this is the manual-path twin.)

### P5 — First run: setup, not error, and guided

**Problem (G8 + G6-prefill):** cold start shows a red "Server URL not configured"
banner and a checkmark-with-error-dot before the user has done anything; the flow
is five unconnected screens; the example URL is saveable text; the notification
prompt precedes purpose; the stale red text survives completing configuration.

**Change:**
1. `unconfigured` never sets `_lastError` (P1 does half of this by making it a
   state, not an error).
2. The Library empty state's "Set up sync" opens a **single guided flow** (spec
   C1 SHOULD, already written): step 1 server URL **with a "Test connection"
   button** (cheap `GET /api/now-playing` probe, shows success/failure inline
   before anything is saved), step 2 folder grant, step 3 playlist selection,
   then the first sync. It is not shown again once a URL + folder + ≥1 playlist
   exist. The existing SyncScreen states are reused as the steps — this is
   mostly sequencing + one container, not new machinery.
3. The example URL becomes a *hint* (`hintText`), not pre-filled text.
4. The notification-permission request is deferred to the moment of the first
   *successful* sync ("we'll tell you when sync finishes" is now a true promise).

**Story:** C1 (the guided flow is a SHOULD on the current spec; "Day 1
invisible afterwards" requires Day 1 to have one narrative, not five screens).

**Cost:** moderate (sequencing + test-connection probe + hint change; the test
probe is ~20 lines on the existing repo).
**Risk:** the wizard must not break the already-configured deep paths (drawer →
Sync must behave exactly as today when configured — the flow activates only while
`unconfigured`); the test probe must not be a full `fetchPlaylists`.

### P6 — Make server configuration non-destructive and honest

**Problem (G6):** any URL change wipes library metadata; no test-connection;
post-wipe UI desyncs (stale Playlists rows, Sync screen back to first-run view,
stale red text).

**Change:**
1. Test-connection (from P5) is also available on the Server screen for
   configured users.
2. The destructive dialog fires **only when the host actually changes**. Same host
   with a different port (the typo case) saves directly — a wrong port is a
   `unreachable` state you can fix in 10 seconds, not a library wipe. (Cross-host
   keeps the wipe: tracks from another server are genuinely invalid.)
3. After any reset, `BrowseProvider.loadData()` runs immediately so the UI matches
   the DB (kills the stale-rows desync observed in State 3).
4. Saving a URL clears `_lastError` (kills the stale red text).

**Story:** C1 — "one-time setup that stays set up" implies a setup *mistake* is
cheap to correct.

**Cost:** small–medium.
**Risk:** low; sync pipeline untouched (UI-side only). The keep-files /
delete-files choice stays exactly as is for cross-host changes.

### P7 — Demote sync from the app's identity (wording + label)

**Problem (G4, G9):** the app is *named* "OwnTone Sync" in the launcher; About
says "Version 0.1.8" (stale) and self-describes as a syncer; the empty state says
"No Music Synced".

**Change:**
- Launcher label `android:label` → "OwnTone" (the package id and the server are
  unchanged). **This is a branding call — flagged as a question, not a decision**
  (store metadata and release notes would follow).
- About: version read from the package instead of the hard-coded string
  (`package_info` is already a transitive of Flutter's tooling; or read
  `pubspec`-generated constants — either way one line); description reframed:
  "Your OwnTone library on your phone — synced home, played anywhere."
- Empty state: "No music yet" + "Connect your server and sync a playlist to start
  listening" (same action, less absence-grammar).

**Story:** spec §1 ("the app is a music player").

**Cost:** small.
**Risk:** the rename is the user's call; everything else is cosmetic with zero
behaviour change.

### P8 — Make the drawer a status + player nav, not a settings index  *(question for the user)*

**Problem (G3, G4):** the drawer header leads with the raw server URL; the six
items are six peers with no player-facing content; from any detail/search screen
you must go back to Library to reach anything.

**Change (minimal version — recommended):** keep the six destinations, but put a
**status block** in the header: server host, connectivity state (P1), "last
synced" (P3) — the URL demoted to a tap target that opens Server. Keep "Sync now".
**Change (fuller version — optional):** group Schedule / Server / Storage / About
under one "Settings" destination, leaving the drawer as: status block, Sync,
History, Settings, divider, Sync now.

I am presenting this as a question rather than a recommendation: the minimal
version carries all the information value; the grouping is taste. If the user
prefers "one settings page" (the Auxio shape), the fuller version is ~half a day.

**Story:** C1; "Day 2 effortless".
**Cost:** minimal version small; fuller version small–medium.
**Risk:** low; no invariant touched. (The drawer exists only on the Library route
— making it global is *not* proposed; that is a bigger navigation change the spec
has not asked for.)

### Considered and deliberately not ranked (preference, not defect)

- **Search as a tab instead of a modal** (Spotify shape). Current placement
  satisfies B6 and the app is small enough that a pushed search is fine. Not
  proposing.
- **A "Downloads"-style per-playlist sync view** (Spotify shape) — this app's Sync
  screen *is* that view (playlists + selection + options). Not proposing.
- **Now Playing as a pushed route instead of a sheet** — spec-locked against this
  (Retro Music drag-expand interaction, Phase 5). Not proposing. (The sheet's
  205px empty space is the open 2026-10-08 defect — separate work.)

---

## 5. Explicitly out of scope

Considered, and NOT proposed, with reasons:

1. **The playback core.** Handler, controller, index model, stats recorder —
   invariants 1–7, 19, 23–25. The task forbids it; the evidence says it's settled.
   Every proposal above is navigation/layout/presentation.
2. **The two defects logged 2026-10-08** (empty Now Playing sheet space;
   detail-title overlap on collapsed `SliverAppBar`s). Separate work, per the task.
   **Screen-touch check:** none of P1–P8 modifies `player_screen.dart`'s sheet
   geometry or the detail screens' `FlexibleSpaceBar`s. P2 wraps the *drawer
   destinations* (none of which is a detail screen or the sheet). P1 changes the
   *Library* app-bar action and banner only. If the detail-title fix lands first,
   nothing here conflicts.
3. **The sync pipeline / worker semantics** (download, upload, rating
   reconciliation, schedule chaining). Additive UI-side classification only (P1,
   P4); the 2026-10-06 "Playlist 4 of 3" notification text stays with the worker
   work. P4's offline-disable is an app-side enqueue gate, not a worker change.
4. **Anything needing the server at playback time** — streaming, live playlist
   browsing, server-side playlist editing, device-wide audio indexing. The app
   plays the synced subset; the proposals preserve that property (P1 explicitly
   gates nothing on connectivity).
5. **Bluetooth/AVRCP, sleep timer, equalizer, lyrics, Android Auto.** Spec
   non-goals; untouched.
6. **A global drawer or bottom navigation.** Spec B1 locked single home + drawer;
   P8 works within it.
7. **The app rename decision itself.** P7 flags it; the store/release pipeline
   impact makes it the user's call.
8. **Reference-player verification on device.** My §2 comparison is from
   knowledge of those apps, not hands-on on this emulator; if any comparison claim
   is load-bearing for a decision, it should be spot-checked by installing the
   app before that decision is made. (Spotify needs an account; Auxio is on F-Droid/GitHub.)

**Dependencies:** exactly one new dependency across all proposals —
`connectivity_plus` (P1). Everything else is existing code.

**Invariants touched:** none broken. Watch-items: P1 must not gate the
`syncCompleted` → library refresh path (invariant: C3 refresh behaviour); P2 must
not introduce any FAB on a snackbar-showing scaffold (Phase-5 finding); P4 must
not change what a *successful* sync writes (History semantics stay).

---

## 6. Build plan — THE EXECUTABLE PART

Standing requirements for every phase (from `AGENTS.md`):
`flutter analyze` 0 errors / 0 warnings · `flutter test` passes ·
`flutter build apk --debug` succeeds · behaviour observed on a device ·
report in `.agent/reports/` · `invariants.md` updated · **do not commit or push.**

### Status

| Phase | State |
|---|---|
| **U0** Non-destructive server config | **COMPLETE** 2026-10-08 — `reports/phase-u0-report.md`. Do not redo. |
| **U1** Four-state connectivity model | **NEXT** |
| **U2** Player everywhere + offline sync guard | pending |
| **U3** First run as setup | pending |
| **U4** Reframe (incl. rename) | pending — do on a branch, it has release consequences |

### How to run a phase

The handoff is one line:

> Build Phase U*n* of the UX refactor, as defined in §6 of
> `.agent/ux-refactor.md`. Follow AGENTS.md.

Everything a session needs is in this section. Read the phase's own block, the
settled decisions below, and — for *why* a phase is shaped the way it is — §3
(gap analysis) and the matching P-item in §4. Do not re-derive decisions, and do
not expand scope into a later phase; raise adjacent problems in the report
instead.

Each phase block states what to **Build**, what to **Verify** on a device, and
what **not** to touch. Where a block marks something ⚠️ or in bold, it is a
decision that a previous session got wrong or that cost real time to establish —
treat those as binding rather than as emphasis.

---

### Settled decisions — do not reopen

Answered by the user 2026-10-08. Full wording and reasoning in §4 and the
per-phase blocks.

1. **No new dependency.** `connectivity_plus` declined. States are distinguished
   by classifying the failure itself, in one pure function.
2. **Drawer: full regroup** into Sync / History / Settings + a status header.
   Server, Storage, Schedule and About collapse into Settings.
3. **Offline shows nothing at all** — no banner, no note, no badge.
4. **Rename to "Owntone Player."** Launcher label, AppBar title, About,
   `pubspec.yaml` description, `metadata/en-US/`, `site/`. The package id
   `dev.educoder.owntone_sync` and the repo name do **not** change — changing a
   package id breaks upgrades for every existing install.
5. **"Last synced" in the drawer header only.**

---

### Phase U0 — Stop server config destroying the library

**First, because it is data loss and the fix is small.** Independent of
everything else; can ship alone.

#### The defect

`server_config_screen.dart`: changing the server URL from any non-empty value
raises a dialog that wipes all synced playlists, tracks and history. It fires on
**any** change — including re-entering the URL that is already configured, which
is how the UX review hit it by accident.

The wipe exists for a real reason: OwnTone track IDs are server-assigned, so
pointing at a *different* server makes stored metadata meaningless. But that is
not what "the text in this field changed" means.

#### Build

**1. Compare normalised values, not raw strings.** Before anything else, decide
whether the target actually changed. Normalise both old and new: trim
whitespace, lowercase the scheme and host, strip a trailing `/`, and treat an
absent port as the scheme default. A cosmetic difference must not reach the
dialog at all.

> This may be the whole bug. "Restoring the correct URL" triggering a wipe is
> consistent with a trailing slash or stray space comparing unequal.

**2. Three outcomes, by what changed:**

| Change | Behaviour |
|---|---|
| Normalised values equal | Save silently. No dialog, no wipe. |
| Same **host**, different port or scheme | Save. No wipe — it is the same machine. Say so if anything is shown at all. |
| Different **host** | Ask — but see below. |

**3. On a host change, the non-destructive option is the DEFAULT.** A home
server getting a new DHCP address is at least as likely as the user pointing at
a genuinely different server, and in that case the library is perfectly valid.
So: keep the library unless the user explicitly chooses otherwise, and word the
choice around what the user knows ("Is this the same music server?") rather than
around files.

**4. Clear the error state on save,** and reload browse data after any reset —
the review found the Playlists tab showing stale entries after a wipe.

#### Verify

- Re-enter the identical URL → saves, no dialog, library intact.
- Add a trailing `/`, or leading/trailing whitespace → saves, no dialog.
- Change the **port** only → saves, library intact.
- Change the **host** → prompt appears, keeping the library is the default, and
  choosing to keep it leaves playlists and tracks in place.
- Choosing to discard still works, and the Playlists tab matches the DB
  immediately afterwards (no stale rows).

#### Do not

Touch the first-run flow (U3), connectivity states (U1), or anything else.

---

### Phase U1 — Four-state connectivity model

**The phase that fixes the user's actual complaint.** Everything after it reads
the vocabulary it defines, so it goes before U2–U4.

#### The defect

One `String? _lastError` and one bool is the entire model. Airplane mode shows a
persistent red banner of raw `DioException`/`SocketException` text on the home
screen plus a red app-bar badge, returning on every cold start. Away-from-home,
a dead server, and never-configured all render identically. Tapping Sync offline
writes a "Sync Failed" History row and swaps in a second, different message for
the same condition.

Users sync music to play it away from the LAN. **Unreachable is the normal state
most of the time**, and the app reports it as a fault.

#### Build

**1. Four states** — `unconfigured` / `reachable` / `offline` / `unreachable` —
replacing `_lastError` as what the UI reads. Keep the error string for History
and logs; stop rendering it.

**2. Classify failures in a PURE FUNCTION. This is the load-bearing decision.**

    ConnectivityState classifySyncFailure(Object error)

Every platform-specific detail confined inside it. `ENETUNREACH` / no route →
`offline`. `ECONNREFUSED` or timeout with a route → `unreachable`.

⚠️ **Classify on exception TYPE and `errno` only. Never parse the message
text.** The review found that text actively wrong: with `:3689` configured the
message reported `port = 37830`; with `:9999`, `43756`. Substring matching will
pass in testing and fail in the field.

Two reasons for the pure function: it is unit-testable without a device, and if
errno classification proves unreliable there is exactly **one** place to swap in
a connectivity package.

**Add unit tests for it**, citing the behaviour each case guards — the suite
derives from stated behaviour, not from implementation.

**3. Per-state presentation:**

| State | Home banner | App-bar icon | Sync screen |
|---|---|---|---|
| `unconfigured` | none — first run is setup, not failure | neutral setup icon | prompt to configure |
| `reachable` | none | quiet | one state-driven banner |
| `offline` | **nothing at all** | neutral, non-red | one state-driven banner |
| `unreachable` | persistent, human, names the host; retry works | the one justified red badge | same |

The `offline` row is the point of the phase.

**4. "Last synced"** in the drawer header, from `sync_history`. This replaces
failure messaging as the app's status signal — freshness, not fault. Build the
header so U4's Settings destination is additive to it.

**5. De-duplicate the Sync screen** to one state-driven banner; clear error
state on successful fetch and on save.

#### Verify — all four states on a device

Produce each app-side only. **Never modify the OwnTone server at
`192.168.1.13`** — it is the user's live library.

1. `reachable`: quiet icon, "last synced …" in the drawer, nothing else.
2. **`offline` (airplane mode) — THE ACCEPTANCE TEST.** Cold start: no red, no
   banner, no badge, nothing. Every screen browsable. Playback starts, seeks,
   auto-advances. Force-stop and relaunch: still nothing.
3. `unreachable`: URL → `http://127.0.0.1:3689` (closed port, network up) →
   persistent human banner naming the host, red badge, retry works when the real
   URL is restored. Restore it.
4. `unconfigured`: `pm clear` → no red on first launch, neutral setup icon.
   **Do this LAST** — it destroys the synced library (~8 min to re-sync ~93
   tracks). If skipping, inspect the path in code and say so explicitly.

Then: **states 2 and 3 must be visibly different without reading an errno.**

#### Do not

Add a dependency · rename anything · touch first run (U3) · wrap drawer
destinations in `PlayerScaffold` (U2) · touch the playback core (invariants
1–7, 19, 23–25 are settled).

#### Carried into U1 from U0

- **`backlog.md` records an unexplained app process death during an
  airplane-mode cycle**, seen once in U0 with no crash trace, and the check was
  re-run cleanly. U1 cycles connectivity repeatedly by design, so this is the
  session most likely to see it again. **If it recurs, capture the full logcat
  immediately rather than re-running the check** — a second sighting in the
  phase that stresses this path is worth far more than a clean retry.
- U0 added **`BrowseProvider.reloadAll()`** because `loadData()` refreshes only
  the current tab while `hasContent` spans all four — that was the stale-rows
  desync in §3. If U1 refreshes the library on a state change, pick the right
  one.
- U0's `parseServerUrlIdentity` (`lib/utils/server_url.dart`) is the precedent
  for the pure-function-plus-unit-tests shape asked for here, including the
  rule that an unparseable input must resolve to "cannot prove" rather than to
  a destructive conclusion. `classifySyncFailure` should read the same way:
  unknown is not the same as failed.

---

### Phase U2 — Player everywhere, and stop logging offline sync as failure

Small, low-risk, ships alone. Independent of U3.

#### Build

1. Wrap the drawer destinations in `PlayerScaffold` so the mini player survives
   navigating to them. The player currently vanishes on all six.
2. In state `offline`, disable Sync and "Sync now" with helper text, and write
   **no** History row. State `unreachable` still allows a manual attempt — that
   is a real fault worth retrying.

#### Verify

With a track playing, open every drawer destination — mini player visible and
functional on each. Airplane-mode Sync tap does nothing and writes no History
row. `unreachable` still permits a manual sync.

---

### Phase U3 — First run as setup, not failure

P6 moved to U0, so this is P5 only.

#### Build

A guided first-run flow, active only while `unconfigured`: URL with a
test-connection step → folder grant → playlist selection. Hint text, not a
pre-filled saveable example URL. Defer the notification permission prompt to the
first *successful* sync rather than cold start.

#### Verify

`pm clear` → no red anywhere in the first screen → one continuous flow to a
populated library. Test-connection reports right/wrong before save. Notification
prompt appears at first successful sync, not at launch.

---

### Phase U4 — Reframe

Presentation on top of the new states. Last.

#### Build

1. **Rename to "Owntone Player"** — launcher label, AppBar title, About,
   `pubspec.yaml` description, `metadata/en-US/` short and full descriptions,
   `site/`. **Not** the package id, **not** the repo name.
2. **Drawer full regroup**: Sync / History / Settings + status header. Server,
   Storage, Schedule, About move into Settings.
3. **Version from the package**, not a literal. About currently says "Version
   0.1.8" while the app is 0.2.0+18.
4. Empty-state and label wording that reads player-first.

#### Verify

Visual pass per screen on device. No behaviour change. `flutter analyze` and
`flutter test` green — the static-guard tests are the backstop for anything that
accidentally touches a guarded file.

---

### Sequencing

```
U0  (data loss — independent, do first)
 └─ U1  (defines the state vocabulary everything else reads)
     ├─ U2  (independent of U3)
     └─ U3  (independent of U2)
         └─ U4  (presentation on top of the new states)
```

Any phase can be shipped and stopped on. None requires a later one to avoid
regressing.

### Known defects deliberately not in any phase

All in `blockers.md` (2026-10-08). Separate work:

- Now Playing sheet leaves ~205 logical px blank at the bottom.
- Detail-screen title overlaps the back button when the app bar collapses.
- **Search was entirely non-functional** — `search_screen.dart` passed an
  `Expanded` as `AppBar.title`, which throws a `ParentDataWidget` error, so the
  text field never rendered. Fixed and device-verified out-of-band 2026-10-08
  (one widget removed). See invariant 38.

A phase that happens to touch those screens should say so in its report, but
must not fold the fixes in.

**Correction to this review, recorded against repeating it.** §1 lists Search
as a working screen, §2 compares it against the reference players, and §5
decides not to change modal-vs-tab — all three assume a screen that could not
be used at all. The review measured structure (routes, widget trees, geometry)
without exercising each screen's primary input. Any future UX pass must type
into the fields, not only read the tree: a `ParentDataWidget` failure renders as
a plausible-looking node in a `uiautomator` dump.

---

## Appendix — the state-2 evidence trail (acceptance-test core)

- Cold start in airplane mode, `flutter run` console:
  `Failed to fetch playlists: DioException [connection error]: … SocketException:
  Connection failed (OS Error: Network is unreachable, errno = 101), address =
  192.168.1.13, port = 3689`
- Library dump (`s2_library.xml`): banner text present at
  `[120,348][1112,468]`, "Dismiss" at `[1136,336][1280,480]`, app-bar button
  tooltip = the same full text; tabs pushed down to y=564 (banner displaces the
  first content row).
- Dismissed (`s2_dismissed.xml`): banner gone, icon back to plain "Sync" — the
  app looks fine.
- Force-stop + relaunch (`s2_relaunch.xml`): **banner and badge are back**, same
  text. Persistent across sessions by construction (`_initialize` at
  `sync_provider.dart:88` calls `fetchPlaylists` at line 121; the banner string
  is set at line 364).
- Playback in the same state: "House Party" at 0:07 → seeking to 3%, Now Playing
  sheet fully functional (`s2_nowplaying.png`).
- Offline Sync tap: worker `ENETUNREACH`, `status=failed`, new History row
  "Sync Failed … 0 tracks downloaded … Manual" (`s2_history.xml`), banner text
  flips to "All 2 playlists failed to sync" — a second, different error message
  for the same condition, replacing the first.
- State 3 port artefact: `:3689` → message says `port = 37830`; `:9999` →
  `port = 43756` (two cold starts, both logged in the attached `flutter run`
  consoles).
