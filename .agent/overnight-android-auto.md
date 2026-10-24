# Overnight run — Android Auto media support (run instantiation)

This document instantiates the unattended serial pipeline defined in
`.agent/overnight-pipeline.md` for the Android Auto build. **Precedence:**
this document governs this run — unit list, order, gates' run-specific
values, templates' filled values, and the decisions below. For everything
this document does not restate (roles, ledger format and rules, the
Unattended contract, hard-blocker mechanics, crash recovery, why the shape
is what it is), `.agent/overnight-pipeline.md` is authoritative and is read
first. Where the two differ, this one wins for this run; where this one is
silent, the process document applies unchanged.

The feature spec is the AI-DLC intent at `.ai-dlc/android-auto/`:
`intent.md` (constraints + completion criteria) and `unit-01` … `unit-06`
(the per-unit specs, each with success/failure completion criteria and
reference pointers into `.ai-dlc/android-auto/docs/`). The units are the
"phases" of this pipeline run.

## Kickoff

Paste this as the entire first message of a fresh session started at the
repo root, and nothing else:

```
Read .agent/overnight-pipeline.md, then read .agent/overnight-android-auto.md and execute this run from the start. This is the unattended overnight run the second document defines. Do not ask me questions — the documents contain the assumptions policy.
```

## Where things stand (as of authoring, 2026-10-23)

- The full plan is written and reviewed by the user:
  `.ai-dlc/android-auto/intent.md` + six unit files + committed reference
  docs under `.ai-dlc/android-auto/docs/`. **It is uncommitted** — the
  prep checklist (`.agent/android-auto-prep.md`) commits it before
  kickoff.
- Working tree also carries six modified `site/assets/screenshots/*.png`
  plus an untracked
  `.agent/reports/site-screenshots-refresh-report.md` from a site-refresh
  session — the prep checklist decides their fate so Step 0's clean-tree
  gate can pass.
- `main` is at `f7ae7dc` (v0.3.2+21). Invariants are current through
  **53**. Open blockers (newest first, all pre-date this run): the
  2026-10-15 `SyncScreen.dispose` debug-only FlutterError (tolerated in
  `test/screen_smoke_test.dart`), the 2026-10-10 setServerUrl generation
  fence, the 2026-10-08 sheet bottom-blank, and two 2026-10-06 cosmetics.
  None touch the media session, the browse path, or the player screen's
  rating commit path — but a build subagent that meets one of them must
  follow the blockers file's rules, not invent a fix.
- Phone AVD **`Pixel_9_Pro_API_36`** (API 36, `google_apis_playstore`
  image) is the designated phone side (designated 2026-10-23; the earlier
  `OwnTone_U2_API_36` designation — a `google_apis` image — is dropped:
  the Android Auto app needs a Play Store image). Fallback:
  `Pixel_9_API_35`. The AVD is fresh for this run: it may carry stale
  app data from an earlier session (0.2.0 era, Brass synced) — the
  current debug APK + server URL + Brass (33 tracks) are confirmed in
  human prep, not assumed.
- The Android Auto Desktop Head Unit **is installed** (2026-10-23):
  `~/Library/Android/sdk/extras/google/auto/desktop-head-unit`, version
  `2.0-mac-arm64` (build 2022-03-30-438482292), executable. The Android
  Auto app is **not yet on the phone AVD** — that is human prep
  (`.agent/android-auto-prep.md`), done before kickoff with a person at
  the machine (Play sign-in is interactive by nature).

## Units (serial, in this order)

| Run unit | Branch | Spec file | Subject (for the PR title) | Report |
|---|---|---|---|---|
| AA-U1 | `aa-u1` | `unit-01-test-harness.md` | Android Auto test harness (DHU + phone + AA app) | `.agent/reports/aa-u1-report.md` |
| AA-U2 | `aa-u2` | `unit-02-aa-optin.md` | Android Auto discovery opt-in (manifest + automotive_app_desc) | `.agent/reports/aa-u2-report.md` |
| AA-U3 | `aa-u3` | `unit-03-browse-tree.md` | Media browse tree + play-from callbacks | `.agent/reports/aa-u3-report.md` |
| AA-U4 | `aa-u4` | `unit-04-car-mode-detection.md` | Car-mode detection (CarConnection bridge) | `.agent/reports/aa-u4-report.md` |
| AA-U5 | `aa-u5` | `unit-05-car-now-playing-ui.md` | Car-mode Now Playing screen (horizontal, large controls, rating) | `.agent/reports/aa-u5-report.md` |
| AA-U6 | `aa-u6` | `unit-06-e2e-verification.md` | End-to-end verification on the AA virtual device + invariants | `.agent/reports/aa-u6-report.md` |

Order rationale: the intent's DAG (01 → {02 → 03, 04 → 05} → 06) with the
pipeline's serial rule (decision 1 in the process doc) gives exactly
U1 → U2 → U3 → U4 → U5 → U6.

Per-unit notes:

- **AA-U1 is an environment unit.** Its "build" is the harness: DHU install
  check, connection, developer-mode confirmation, the three DHU
  resolutions, and the harness-sanity check (a known-present media app is
  visible). Its code deliverable is the setup script/notes + screenshots.
  Every later unit assumes the harness from U1 still works; if a later
  unit finds it broken, the build subagent repairs the harness *within the
  unit* (harness breakage is not a spec change) and records what broke in
  ASSUMPTIONS.
- **AA-U4 has a sanctioned soft-blocker** — see decision 6 below. No other
  unit may treat a `BLOCKED:` return as soft.
- **AA-U5's rating interaction is settled** (user decision): phone-parity
  press-and-slide reusing `RatingControl` — the unit spec already says so;
  do not re-litigate tap-to-set.
- **AA-U6 may produce no feature code.** Its PR carries the E2E report, the
  `invariants.md` updates (minimum: mediaId scheme, car-mode detection,
  car rating commit path, no-auto-play), and any small fixes the matrix
  forces. An empty-diff code review is fine: the reviewer reviews the
  report's evidence quality and the invariant entries against the code.

## Decisions already made — do not re-litigate

1. **Serial, U1→U6.** The phone AVD and the single DHU on the host are
   hard serialization points; a moving `main` under in-flight builds is
   the 4 a.m. integration failure the pipeline exists to avoid (process
   doc, decision 1).
2. **Branches `aa-u1`…`aa-u6`, base `main`, merge commits** (repo
   convention, PRs go to `main`).
3. **Soft-only unattended guard.** No `opencode.json` changes. The
   Unattended contract (process doc) is embedded byte-identical in every
   subagent prompt.
4. **Review rounds capped at 3** (process doc, decision 5).
5. **Commit + push authorized** at the points the process doc names, for
   these branches. Nothing else.
6. **AA-U4 CarConnection soft-blocker.** The one known risk that could sink
   an otherwise-good night: `CarConnection` may not report
   `CONNECTION_TYPE_PROJECTION` under *emulated* Android Auto (the docs
   describe it for real projection). If AA-U4's build subagent returns
   `BLOCKED:` **on detection only** — i.e. the Kotlin bridge + Dart
   controller + tests are complete and committed, the debug-only override
   (unit-05 §5) flips car mode on the harness, and the logcat evidence is
   in the report — the orchestrator records a ledger entry
   `AA-U4 SOFT-BLOCKED (detection)`, marks the unit's PR as
   "merge-with-flag", and the run **continues to U5 using the debug
   override for all car-mode verification**. The final summary flags it
   for a human with the evidence. Any other U4 failure shape (no AA
   connection at all, app crash in the car, bridge not built) is a **hard**
   blocker per the process doc.
7. **The phone AVD stays up across units; the DHU process is killed at
   each unit's end.** Deviation from the process doc's "kill the AVD when
   the unit is done", on purpose: AA's pairing/ToS/developer-mode state
   lives on the phone side and re-establishing it costs the night; the
   DHU is cheap to restart and its per-unit `adb forward` is re-issued
   anyway. Hard-blocker cleanup (process doc) still kills the AVD.
8. **Server rating change (AA-U6 C6)** follows the repo rule: record the
   original rating first, restore afterwards, confirm the restore against
   the API, and put all four values in the report. No other server
   mutation is permitted by any unit.
9. **Gearslip regression (AA-U6 E1) is out of environment** (Gearslip
   talks to a head unit directly; the harness has no real car/LIVI). It is
   reported as BLOCKED-with-reason, never attempted.
10. **AA app on the phone AVD:** the AVD is a Play image
    (`google_apis_playstore`), so Play Store install is the primary path
    (sign in if needed — human prep); if Play is unavailable, sideload
    the Android Auto APK via `adb install` and record version + source in
    the ledger. Either way, the version is recorded in the AA-U1 report.

## Gates (run-specific values)

All process-doc gates apply unchanged with these substitutions: unit
branches `aa-uN`, reports `.agent/reports/aa-uN-report.md`, PRs titled
`AA-U<n>: <subject>`. Run-specific additions:

| Gate | Between | Condition | How it is checked |
|---|---|---|---|
| `PREP_DONE` | before Step 0 work | human prep checklist complete | orchestrator runs: `SDK_LOCATION/extras/google/auto/desktop-head-unit -v` exits 0; `adb -s <avd> shell pm list packages \| grep projection.gearhead` matches; prep sign-off line copied into the ledger |
| `HARNESS_OK` | build → PR (every unit after U1) | the DHU connected and the app is reachable in AA for this unit's checks | the unit report's OBSERVED section contains the DHU screenshot names from its matrix rows; orchestrator confirms the files exist in the report folder |
| `RATING_RESTORED` | AA-U6 build → PR | the C6 server rating was restored | report contains original/new/restored values + API confirmation line |

## Pipeline steps (this run)

### Step 0 — preflight

1. Create the ledger. Check `RUN_UNIQUE`.
2. `git fetch origin && git checkout main && git pull`. Confirm
   `git status --short` is empty — if not, hard blocker (the prep
   checklist exists precisely to make this pass; a dirty tree at kickoff
   means prep was skipped or the night started mid-change).
3. Confirm `gh auth status` and `gh pr view` work.
4. Check `PREP_DONE`. Record the DHU version and AA app version in the
   ledger (the orchestrator reads them from the prep sign-off note).
5. Proceed to AA-U1. (There is no "open the existing PR" step this run —
   nothing is pushed yet.)

### Steps 1–6 — one per unit (process doc Steps 1–3, repeated)

For `N` in 1..6: gate `PREVIOUS_MERGED` (for N=1, "nothing prior" — the
gate is satisfied by the clean main + PREP_DONE); create branch `aa-uN`;
record the device plan in the ledger (below); spawn the build subagent
(template below); verify `BUILD_VERIFIED` + (N≥2) `HARNESS_OK` itself;
push; open the PR (`PR_OPEN`); run the review loop (max 3 rounds,
`REVIEW_POSTED`/`REVIEW_PASSED`); merge on `CI_GREEN`; ledger the merge
SHA. For AA-U4, apply decision 6's soft-blocker path instead of stopping.

**Device plan (ledgered at each unit start):** phone
`Pixel_9_Pro_API_36` (Play image), launched windowed, `-s <serial>`
everywhere (serial is launch-time — record it from `adb devices` in the
ledger; confirm AVD↔serial identity per invariant 42); DHU on the host
(`~/Library/Android/sdk/extras/google/auto/desktop-head-unit`) at the
resolution(s) the unit's matrix requires (U1: all three; U2–U5: 480p
default; U6: per its matrix); `adb -s <serial> forward tcp:5277 tcp:5277`
re-issued per DHU session; DHU process killed and forward removed at unit
end (decision 7). No `pm clear` of the app for U2–U5 (U1's harness work
may need it only for the fresh-install row — U6 D3 does its own clear +
re-sync); the device holds Brass (33 tracks) after prep — **do not
re-sync Soul** (repo rule).

### Final summary (process doc format)

Plus, for this run: DHU version + AA app version; the CarConnection
outcome (real detection vs debug override — decision 6); the C6 rating
restore values; E1's BLOCKED-with-reason line; which DHU resolutions each
unit verified at; device state (AVD left running per decision 7 — named as
left-alive in the summary, since a human is expected to continue the
morning session on it).

## Unattended contract

Embedded **byte-identical** (copied from `.agent/overnight-pipeline.md`,
"Do not paraphrase") in every subagent prompt, after the standing
AGENTS.md line it already contains. The orchestrator copies it from the
process document at spawn time and does not edit it.

## Hard blocker policy (run-specific additions)

Process-doc triggers apply, plus:

- DHU fails to connect after the documented workaround (process doc
  `docs/android-testing-dhu.md` "Troubleshoot": restart head unit server,
  restart DHU, re-grant) — harness is unrecoverable unattended.
- AA app throws an interactive wall the harness cannot pass (ToS re-accept
  needed, Play sign-in demanded mid-run, permission dialog with no
  known-allow answer).
- The phone AVD dies and cannot be relaunched (disk/host constraint).

On a hard blocker the orchestrator follows the process doc exactly
(ledger entry with full state + next action; branches committed and
pushed; AVD killed; DHU process killed; final summary naming the blocker).

## Repo facts (this run — subagents do not re-derive these)

- **Spec:** `.ai-dlc/android-auto/intent.md` (constraints, server rule,
  no-auto-play rule) + the unit file named in the build prompt. The
  unit's completion criteria (success + failure cases) are the
  acceptance tests; "Done means" is AGENTS.md's.
- **Grounding docs** (committed, read-only): `.ai-dlc/android-auto/docs/`
  — 12 pages of the official Android-for-cars docs (developer.android.com
  is **not** in docs-mcp; its fetcher redirect-loops on that host — the
  committed markdown is the authoritative local copy for this run).
- **Review grounding** (docs-mcp, pre-indexed): `flutter`, `just_audio`,
  `audio_service`, `dio`, `workmanager`, `owntone-server`, `provider`,
  `sqflite`, `path_provider`, `rxdart`, `code-review-guide`, `Gearslip`,
  `AARE`, `prompt engineering guide`.
- **Server:** `http://192.168.1.13:3689`, real curated library, read-only
  rule as stated in the intent. Device holds Brass only (33 tracks).
- **Device traps** (invariants 29, 42, 53): rendering bug → attach
  `flutter run`, read `E/flutter`; `uiautomator dump` is empty while a
  sheet is open; trigger syncs from the Sync screen; seed on-device data
  via `run-as` + base64 chunks per invariant 53 when a unit needs a
  specific DB state (e.g. a track with a known server rating for C6).
- **New dependency** (AA-U4 only): `androidx.car:car-app` — latest stable
  at build time, version recorded in the report; the build subagent notes
  any transitive-dependency surprise (intent context says the short
  dependency list is deliberate).
- **Merge style:** merge commits; PRs to `main`; CI = `flutter-test.yaml`.
- **Reports:** `.agent/verification-protocol.md` §6 format, every field;
  screenshots live in `.agent/reports/<date>-android-auto/` (AA-U6's
  matrix rows) and are referenced by name from the reports.

## Prompt templates (this run — fill `<…>` per spawn, never edit the
contract or the standing lines)

### Build (per unit)

```
<unattended contract, byte-identical from .agent/overnight-pipeline.md>

Your task: build AA-U<N> of the Android Auto run, as specified in
.ai-dlc/android-auto/<unit file>. You are on branch aa-u<N> (created and
pushed-base from main by the orchestrator; it exists and is checked out).

Read, in order: .agent/invariants.md (index, then everything touching the
media session, queue, rating commit path, or the screens this unit edits —
the unit file names its relevant areas), .agent/blockers.md (open entries
are deliberately unfixed — work around, never fix, unless your unit's spec
names the fix), .ai-dlc/android-auto/intent.md (constraints + server rule),
then the unit file in full, then the specific docs under
.ai-dlc/android-auto/docs/ that the unit cites. The unit's completion
criteria (success AND failure cases) are your acceptance tests.

Device plan: <the ledger's device plan line for this unit>. For AA-U1 the
unit file IS the setup procedure; produce its deliverables (script/notes,
screenshots, cheat-sheet) in the locations it names. For later units the
harness from AA-U1 exists — if it is broken, repair it and record what
broke under ASSUMPTIONS.

Commits: commit AND push to origin aa-u<N> after each verified step
(analyze + tests green at that point). Commit messages explain why, per
AGENTS.md. This pipeline's commit+push steps are the explicit
authorization AGENTS.md requires.

Before returning: flutter analyze, flutter test and flutter build apk
--debug all pass in the tree (plus ./gradlew -p android
:app:testDebugUnitTest if Kotlin changed — AA-U4 changes Kotlin); the unit
report is written (.agent/reports/aa-u<N>-report.md, §6 format, every
field, OBSERVED entries for every completion-criterion row you executed,
BLOCKED-with-reason for any row you could not); invariants.md/blockers.md
updated if the unit required it; git status clean; DHU process killed and
its adb forward removed; a final ledger entry appended.

Return (and only this):
- SUMMARY: what you built, one line per step
- GATES: analyze / test / apk build (and gradle test if applicable), verbatim tails
- DEVICE: the OBSERVED entries' one-line distillate (action → result)
- REPORT: path
- ASSUMPTIONS: list, or "none"
- BLOCKERS: anything you raised in .agent/blockers.md, or "none"
```

### Review (per round)

```
<unattended contract, byte-identical from .agent/overnight-pipeline.md>

Your task: an independent code review of PR <n> (<url>) on
jptrsn/owntone-sync. Load the `agentic-code-review` skill and follow it.

Repo facts: checkout at /Users/oblivious/Documents/owntone_sync (do all
work in your own worktree: git worktree add /tmp/owntone-review-pr<n>
aa-u<N>; flutter pub get there). The diff is `gh pr diff <n>` — never the
worktree's branch state. Quality gates to run in the worktree: flutter
analyze, flutter test (device verification is already recorded in the
unit report — cite it, do not re-run it; this run has no device access
from a review worktree). Grounding: docs-mcp libraries <the Review
grounding list from Repo facts>; for Android-for-cars behaviour the
authoritative local docs are .ai-dlc/android-auto/docs/ (read the ones the
unit cites) — developer.android.com is not reachable via docs-mcp.

Repo-specific review focus: .agent/invariants.md is a contract — a finding
that conflicts with a numbered invariant is a fact-check against the
invariant's WHY, not a style opinion. .agent/blockers.md lists open
defects that are deliberately unfixed; do not re-report them. The spec is
.ai-dlc/android-auto/<unit file> plus .ai-dlc/android-auto/intent.md
(constraints). The rating-commit path must remain the phone sheet's path
(setTrackRating → pending edit); the media session must not auto-play on
car connect; the mediaId scheme is the unit-03 table.

You are read-only toward the repo and GitHub: no edits to tracked files, no
push, no merge, no gh writes (no PR comments — the orchestrator posts
your report). Every finding needs evidence (file:line, a gate result, or a
concrete failure scenario); drop findings you cannot evidence.

Return the skill's consolidated report (findings table with severity,
type, file:line, evidence, suggested fix) plus, on the last line, exactly:
VERDICT: APPROVE   (no blocker/major findings)
or
VERDICT: CHANGES_REQUESTED  (at least one blocker or major)
```

### Fix (per round)

```
<unattended contract, byte-identical from .agent/overnight-pipeline.md>

Your task: address the review findings below on branch aa-u<N> (checked
out in the main working tree; it is clean and pushed). For each finding:
fix it, or rebut it with evidence (cite the invariant, the spec line, or a
test) — a documented rebuttal counts as handled. Do not fix anything not
on the list.

FINDINGS (round <r>):
<orchestrator pastes the blocker/major findings verbatim>

Before returning: flutter analyze, flutter test and flutter build apk
--debug pass (plus the gradle test if Kotlin changed); any behaviour
change was observed on the device per the unit's completion criteria
(append the evidence to the unit report's OBSERVED section); each finding's
resolution appended to the unit report under a "## Review round <r>"
heading; committed AND pushed; a final ledger entry appended.

Return (and only this):
- PER-FINDING: finding id → fixed (commit SHA) | rebutted (evidence)
- GATES: analyze / test / apk build results, verbatim tails
- DEVICE: what you observed, or "not applicable"
- ASSUMPTIONS: list, or "none"
```

## Crash recovery

Process doc, unchanged: fresh session with the Kickoff message reads this
document (and the process doc), then the ledger, checks `RUN_UNIQUE`,
establishes git/PR/AVD ground truth, and continues from the latest
`next:`.
