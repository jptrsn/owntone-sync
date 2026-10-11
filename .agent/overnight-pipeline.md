# Overnight pipeline — run U3 and U4 unattended (process definition)

This document is the authoritative process definition for an unattended
overnight run that takes the UX refactor from "U2 pushed, no PR" to
"U4 merged".
It is written to be executed by a **fresh session** with no other context.
It is process documentation, not a phase deliverable — **never stage or
commit this file or the ledger it maintains**.

## Kickoff

Paste this as the entire first message of a fresh session started at the repo
root, and nothing else:

```
Read .agent/overnight-pipeline.md and execute it from the start. This is the
unattended overnight run it defines. Do not ask me questions — the document
contains the assumptions policy.
```

## Where things stand (as of authoring, 2026-10-11)

- U0, U1, U2 are built, device-verified and reported
  (`.agent/reports/phase-u0-report.md`, `phase-u1-report.md`,
  `phase-u2-report.md`). Invariants are current through **43**; blockers
  current (2026-10-10 entry is open, U2 accounted for it — decision D2).
- U2's code is committed on branch **`ux-u2`** (head `de7214a`) and **pushed
  to origin. No PR exists for it yet.** The pipeline's Step 0 opens it.
- U3 (first run as setup) and U4 (reframe, incl. rename) are specified in
  §6 of `.agent/ux-refactor.md` and sequenced U3 → U4.
- Repo: `jptrsn/owntone-sync` (public), `gh` authenticated as `jptrsn`,
  merge style is **merge commits** (see PR #3), CI workflow
  `flutter-test.yaml` runs on PRs.

## Decisions already made — do not re-litigate

1. **Serial pipeline.** Per unit: build → PR → review → (fix → re-review)\* →
   merge → next unit. The user considered running the next unit's build in
   parallel with the current unit's review and **rejected it for the first
   unattended run**: U2 fixes and a U3 build can touch the same files
   (`sync_provider.dart`, `sync_screen.dart`), a single shared emulator is a
   hard serialization point anyway, and a moving base under an in-flight
   build is exactly the 4 a.m. integration failure this pipeline exists to
   avoid. Serial loses at most one review's worth of wall-clock; it buys a
   night with no merge-conflict class of failures.
2. **Soft-only unattended guard.** No `opencode.json` changes (user
   decision). The protection against a hung session is the **Unattended
   contract** below, embedded byte-identical in every subagent prompt.
   (Fact for context: with no `permission` block configured, opencode's
   default is to allow operations without approval, so the realistic
   hang vectors are the `question` tool and doom-loop recovery prompts —
   the contract covers the former; the latter is a known residual, and a
   doom-loop prompt means a human is needed, which is itself a finding.)
3. **Orchestrator/subagent split.** The fresh session (orchestrator) does all
   git/gh/PR mechanics, gate re-verification, ledger writes, and merge
   decisions. It never writes feature code. Work is delegated to fresh
   subagents (Task tool, `general`): one **build** subagent per unit, one
   **review** subagent per review round, one **fix** subagent per fix round.
   Fresh context per spawn is the context strategy — it replaces
   mid-session compaction for the heavy work (the generator–evaluator split
   also means the reviewer never sees the builder's reasoning).
4. **U4 runs to completion.** U4's rename has release consequences (store
   listing), but the user directed that the pipeline proceed as far as
   possible: U4 goes through the same review → merge flow as the others.
   The final summary flags the store-listing review so a human can look at
   it in the morning; the merge commit is the revert point if that review
   goes badly.
5. **Review rounds are capped at 3.** A third "changes requested" verdict is
   a hard blocker, not a fourth round (bounded overnight risk; a human
   adjudicates in the morning).
6. **Commit + push are authorized** at the points this document names. That
   is the explicit ask AGENTS.md requires; it does not authorize commits
   elsewhere (e.g. the orchestrator must not commit unrelated files).

## Roles

- **Orchestrator** — this session. Stays in the repo root on `main` (or the
  active unit branch during its loop). Keeps its context small: everything
  load-bearing goes in the ledger, not in conversation. Spawn one subagent
  at a time; never run two concurrently (decision 1).
- **Build subagent** — implements one phase in the main working tree on the
  unit branch, including device verification and the phase report.
- **Review subagent** — follows the `agentic-code-review` skill. Own
  `git worktree` under `/tmp`, read-only toward the repo, no device, no
  writes to GitHub. Returns the consolidated report + verdict.
- **Fix subagent** — takes the round's findings, fixes or rebuts them in the
  main working tree on the unit branch, re-runs gates, commits + pushes.

## The ledger

`.agent/reports/overnight-ledger.md` — append-only, the single source of
truth across subagent boundaries and orchestrator compaction. Created by the
orchestrator in Step 0. Entry format:

```
## <UTC timestamp> — <STEP NAME>
- actor:      orchestrator | build | review | fix
- state:      branch=<b> head=<sha> pr=<n+state> device=<serial|none>
- did:        <what happened, incl. any deviations>
- next:       <the exact next action, imperative>
```

Rules: the orchestrator appends after **every** gate, and never lets a
decision or state live only in its own context. Each subagent appends its own
final entry before returning. A session resuming after a crash reads this
document, then the ledger, and continues from the latest `next:` — see
**Crash recovery** below.

## Hard gates

An agent must never advance past a failed gate (no judgment calls). The
orchestrator enforces each by running the check itself, not by trusting the
subagent's summary.

| Gate | Between | Condition | How it is checked |
|---|---|---|---|
| `RUN_UNIQUE` | start | no other orchestration running | ledger absent, or last entry > 2 h old. If present and < 30 min old with `next:` not `PIPELINE COMPLETE` → stop and write a ledger entry saying so |
| `PREVIOUS_MERGED` | unit start | prior unit's PR merged | `gh pr view <n> --json state -q .state` → `MERGED` |
| `BUILD_VERIFIED` | build → PR | gates pass + report exists | orchestrator re-runs `flutter analyze` (exit 0) and `flutter test` (exit 0) in the tree; `.agent/reports/phase-u<n>-report.md` exists with the §6 sections; `git status --short` empty |
| `PR_OPEN` | build → review | PR exists with the report referenced | `gh pr view <n> --json number,url` |
| `REVIEW_POSTED` | review → decision | report posted on the PR | `gh api repos/jptrsn/owntone-sync/issues/<n>/comments` shows it |
| `REVIEW_PASSED` | review → merge | verdict APPROVE, no blocker/major | reviewer's verdict (see template) |
| `CI_GREEN` | merge | PR checks green | `gh pr checks <n>` — one re-run on red; still red = hard blocker |
| `MERGED` | unit end | PR merged | `gh pr view <n> --json state -q .state` → `MERGED` |

## Pipeline steps

### Step 0 — preflight and U2's PR

1. Create the ledger. Check `RUN_UNIQUE`.
2. `git fetch origin && git checkout main && git pull`. Confirm
   `git status --short` is empty (if not: stop — hard blocker, unknown state).
3. Confirm `gh auth status` works and `gh pr view` can see the repo.
4. Open the U2 PR (the branch is already pushed):
   `gh pr create --base main --head ux-u2` with title
   `Phase U2: keep the mini player on every drawer screen; stop logging
   offline syncs as failures` and a body of 2–3 lines plus a pointer to
   `.agent/reports/phase-u2-report.md`. Record PR number in the ledger.
5. Enter the **review loop** for the U2 PR (Step 2 below). When it is
   `MERGED`, proceed to U3.

### Step 1 — build unit N (N ∈ {3, 4})

1. Gate `PREVIOUS_MERGED`. Then:
   `git checkout main && git pull && git checkout -b ux-uN`.
2. Record the device plan in the ledger (which AVD, why — see Repo facts).
3. Spawn the **build subagent** (template below). Wait for its return.
4. Verify `BUILD_VERIFIED` (the orchestrator re-runs the gates itself).
   If the subagent returned `BLOCKED:` → hard blocker policy.
5. If the tree is not pushed, push: `git push -u origin ux-uN`.
6. Open the PR: `gh pr create --base main --head ux-uN` — title
   `Phase UN: <subject from the phase report>`, body: 2–3-line summary,
   "Full report: `.agent/reports/phase-uN-report.md`", and the one-line
   device-verification claim. Gate `PR_OPEN`.

### Step 2 — review loop for the unit's PR

1. Round = 1. Spawn the **review subagent** (template below) for the PR.
2. Post its full report as a PR comment (orchestrator does the `gh` write —
   the reviewer stays read-only). Gate `REVIEW_POSTED`.
3. If verdict is `APPROVE` → exit the loop (gate `REVIEW_PASSED`).
4. If verdict is `CHANGES_REQUESTED`:
   - if round = 3 → hard blocker (cap reached);
   - else spawn the **fix subagent** with the round's findings, wait, verify
     gates pass in the tree (the fix subagent also commits + pushes),
     round += 1, back to step 1.

### Step 3 — merge (every unit, incl. U4)

1. Gate `CI_GREEN`.
2. `gh pr merge <n> --merge` (merge commit — repo convention).
3. Gate `MERGED`. Ledger entry with the merge SHA.
4. `git checkout main && git pull`.

### Step 4 — U4

Run Steps 1–3 for U4 with no exception: build → PR → review loop → merge.
U4 is presentation-only (no behaviour change), so the build's device work
is a visual pass per its Verify block. The final summary (below) flags the
store-listing review for a human, per decision 4.

### Final summary (end of the run, success or blocker)

Ledger entry `PIPELINE COMPLETE` (or `PIPELINE STOPPED — <reason>`)
containing: every PR with its number, state and head SHA; what was merged;
what is left for the human (e.g. the store-listing review after U4's
rename); every ASSUMPTIONS and BLOCKED entry from the ledger; device state
(AVDs killed or not). The session's last message mirrors this summary.

## The unattended contract

The following block is **byte-identical in every subagent prompt** (it
follows the standing AGENTS.md block, which it also repeats — subagents do
not see this conversation). Do not paraphrase it per spawn.

```
Standing instructions: read AGENTS.md at the repository root before doing
anything else, and follow it. It routes you to the .agent/ documents that
matter for this task and states what "done" means.

This is an UNATTENDED run. There is no human at the terminal and nothing you
do will be approved interactively:
- NEVER call the `question` tool, and never run anything that blocks on
  input (no `git rebase -i`, no `--interactive` flags, no editors).
- If something is ambiguous, choose the minimal interpretation consistent
  with the phase spec, record it under ASSUMPTIONS in your report, and
  proceed. Do not widen scope to fix adjacent problems.
- If you are truly blocked (a gate fails three times on the same fix, the
  device is gone and cannot be recreated, the spec is ambiguous in a way
  that changes the shape of the build): stop working. Append a ledger
  entry to .agent/reports/overnight-ledger.md (reason, exact git/device
  state, the next action a human or fresh session would take), commit your
  current work ("WIP: " prefix if gates do not pass), push the branch, and
  return a summary that starts with "BLOCKED:".
```

## Hard blocker policy

A hard blocker stops the pipeline. It is not a failure to retry silently.
Triggers: `RUN_UNIQUE` tripped; `git status` not clean at Step 0; a subagent
returns `BLOCKED:`; a gate fails after the allowed retries; the review cap
(3 rounds) is reached; the OwnTone server unreachable for > 15 min during a
build; disk space < 5 GB; a doom-loop/recovery prompt appears (a human is
needed — that is the definition of the blocker).

On a hard blocker, the orchestrator: (1) appends a ledger entry with the
full state and the exact next action; (2) leaves every branch committed and
pushed; (3) leaves every AVD it started killed; (4) ends the run with the
final summary naming the blocker. It does not attempt the next unit.

## Repo facts (so subagents do not re-derive them)

- **Gates** ("done" per AGENTS.md): `flutter analyze` → 0 errors, 0
  warnings; `flutter test` → passes; `flutter build apk --debug` →
  succeeds; behaviour observed on a device; report in
  `.agent/reports/` using the `.agent/verification-protocol.md` §6 format
  (every field mandatory); `invariants.md` updated for anything a future
  session must not undo. Kotlin tests
  (`./gradlew :app:testDebugUnitTest`, JDK 17) only when Kotlin changed.
- **Server**: `http://192.168.1.13:3689` holds the user's real, curated
  library. Read freely; never modify (no playlist deletions, no edits).
  Induce failure cases from the app side. The device holds **Brass only
  (33 tracks)** — do not re-sync Soul.
- **Emulator**: check `flutter devices` first — other sessions on this host
  have used `emulator-5554`/`5556`. Prefer reusing the existing AVD
  `OwnTone_U2_API_36` (app installed, URL and Brass configured; U3's
  verification does `pm clear` for first-run state); create
  `OwnTone_U<N>_API_36` only if none exists (google_apis API 36,
  `pixel_9_pro`, **data partition ≤ 8G** — host disk constraint). Launch
  **windowed** (no `-no-window`; user preference for this host), always
  target with `-s <serial>`, and kill the AVD when the unit is done.
- **Device traps** (invariants 29, 42): for a rendering bug, attach
  `flutter run` and read the console — `E/flutter` lines are the evidence;
  `uiautomator dump` returns an empty window while the Now Playing sheet is
  open; a dump with no content-descs is not evidence of an empty screen.
  Trigger syncs from the Sync screen, not the shell (invariant 33).
- **Review grounding** (docs-mcp at 127.0.0.1:6280 — already indexed, no
  scraping needed for these): `flutter`, `just_audio`, `audio_service`,
  `dio`, `workmanager`, `owntone-server`, `provider`, `sqflite`,
  `path_provider`, `rxdart`, `code-review-guide`, `prompt engineering
  guide`.
- **Merge style**: merge commits. PRs go to `main`.

## Prompt templates

Each template = the unattended contract (above, verbatim) + the task block.
Spawn with the Task tool, `subagent_type: general`. The orchestrator fills
the `<…>` values; the contract and the standing lines are never edited.

### Build (Step 1)

```
Your task: build Phase <UN> of the UX refactor, as defined in §6 of
.agent/ux-refactor.md (read the phase's own block, the "Settled decisions",
and the Sequencing section). Branch ux-u<N> already exists and is checked
out; you are on it.

Read, in order: .agent/invariants.md (index, then everything relevant —
40-43 for U3; the whole UI section for U4), .agent/blockers.md,
.agent/ux-refactor.md §6, and the previous phase's report
(.agent/reports/phase-u<N-1>-report.md).

The phase's "Done means" is in AGENTS.md; the phase's own Verify block is
the acceptance test. Device plan: <ledger's device plan, incl. any
pm clear>.

Commits: commit AND push to origin ux-u<N> after each build step you have
verified (analyze + tests green at that point). Commit messages explain
why, per AGENTS.md. This pipeline's commit+push steps are the explicit
authorization AGENTS.md requires.

Before returning: flutter analyze, flutter test and flutter build
apk --debug all pass in the tree; the phase report is written
(.agent/reports/phase-u<N>-report.md, §6 format, every field);
invariants.md/blockers.md updated if the phase required it; git status
clean; the AVD you started is killed; a final ledger entry is appended.

Return (and only this):
- SUMMARY: what you built, one line per build step
- GATES: analyze / test / apk build results, verbatim tails
- DEVICE: the OBSERVED entries' one-line distillate (action → result)
- REPORT: path
- ASSUMPTIONS: list, or "none"
- BLOCKERS: anything you raised in .agent/blockers.md, or "none"
```

### Review (Step 2, per round)

```
Your task: an independent code review of PR <n> (<url>) on
jptrsn/owntone-sync. Load the `agentic-code-review` skill and follow it.

Repo facts: checkout at /Users/oblivious/Documents/owntone_sync (do all
work in your own worktree: git worktree add /tmp/owntone-review-pr<n>
ux-u<N>; flutter pub get there). The diff is `gh pr diff <n>` — never the
worktree's branch state. Quality gates to run in the worktree:
flutter analyze, flutter test (the phase's device verification is already
recorded in the phase report — cite it, do not re-run it). Grounding
libraries are pre-indexed in docs-mcp: <the list from Repo facts>.

Repo-specific review focus: .agent/invariants.md is a contract — a finding
that conflicts with a numbered invariant is a fact-check against the
invariant's WHY, not a style opinion. .agent/blockers.md lists open
defects that are deliberately unfixed; do not re-report them as new.
Phase spec: .agent/ux-refactor.md §6, phase <UN> block.

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

### Fix (Step 2, per round)

```
Your task: address the review findings below on branch ux-u<N> (checked
out in the main working tree; it is clean and pushed). For each finding:
fix it, or rebut it with evidence (cite the invariant, the spec line, or a
test) — a documented rebuttal counts as handled. Do not fix anything not
on the list.

FINDINGS (round <r>):
<orchestrator pastes the blocker/major findings verbatim>

Before returning: flutter analyze, flutter test and flutter build
apk --debug pass; any behaviour change was observed on the device per the
phase's Verify block (append the evidence to the phase report's OBSERVED
section); each finding's resolution appended to the phase report under a
"## Review round <r>" heading; committed AND pushed; a final ledger entry
appended.

Return (and only this):
- PER-FINDING: finding id → fixed (commit SHA) | rebutted (evidence)
- GATES: analyze / test / apk build results, verbatim tails
- DEVICE: what you observed, or "not applicable"
- ASSUMPTIONS: list, or "none"
```

## Crash recovery

If the orchestrator session dies mid-run, start a fresh session with the
Kickoff message. It will: read this document; read
`.agent/reports/overnight-ledger.md`; check `RUN_UNIQUE` (a ledger whose
last entry is < 30 min old with `next:` not `PIPELINE COMPLETE` means
another run may be live — stop); inspect `git status`, open PRs and
`gh pr checks` to establish ground truth; then continue from the latest
`next:`. Nothing in the pipeline is resumable only from conversation — the
ledger plus git/PR state is the complete state.

## Why this is shaped this way (for future readers)

- **File-based handoffs** (ledger + reports + PR comments), not
  conversation, because subagents have fresh context and the orchestrator
  compacts — anything that matters must survive both (ai-dlc harness
  pattern).
- **Fresh subagent per role** rather than one long session, because a
  multi-hour build in one context is where models lose coherence and start
  wrapping up early; the handoff artifacts (report, invariants, ledger)
  carry state instead of the window.
- **The orchestrator re-runs gates itself** because a subagent's "all
  green" is a claim, and this repo's standing rule is that claims are
  verified against the code (AGENTS.md).
- **Serial** because the alternatives each cost a class of failure the
  user has already paid for once (see Decisions, 1).
