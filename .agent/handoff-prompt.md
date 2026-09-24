# Handoff prompt for implementing sessions

Run this once per phase, substituting the phase number. Phases are defined in
§3 of `.agent/player-refactor-plan.md`. Start with Phase 0.

---

```
You are implementing a refactor of this Flutter app, defined in four documents
in this repo. Read ALL FOUR IN FULL before touching any code — they are
authoritative and supersede anything in .agent/player-spec.md or
.agent/play-music-plan.md (both obsolete; ignore them):

  .agent/player-ux-spec.md        — what we are building and why, plus the
                                    user stories and acceptance criteria
  .agent/player-refactor-plan.md  — the defect inventory, target architecture,
                                    and the phased implementation path
  .agent/verification-protocol.md — what counts as evidence, and the report
                                    format you must use. Short. Binding.
  .agent/invariants.md            — load-bearing facts established the hard way,
                                    each with what breaks if you undo it. Short.
                                    Binding. Read it last, before you start.

Phase reports in .agent/ (phase1-report.md and any later ones) are NOT in that
list. They are historical records of what one session did and saw — evidence,
not guidance. Do not derive constraints from them. Anything a report established
that still matters has been promoted into invariants.md; if a report seems to
imply a rule, check invariants.md instead.

Before writing code:
1. Read all four documents completely.
2. Read §1 of the refactor plan (the defect inventory) carefully — it cites
   file:line evidence for why the current code is broken. Verify those claims
   against the actual code rather than assuming they are still accurate.
3. Read the files this phase touches, per the disposition table in §4.
4. Tell me your understanding of this phase's scope and what you intend to
   change, and wait for my confirmation before editing.

Binding constraints (§5 of the refactor plan):
- Prefer deleting old code over adapting it. The existing player code is the
  source of the bugs; carrying pieces of it forward carries the bugs forward.
- Do not modify the sync download/upload pipeline. Only the additive sync-side
  changes named in §4 are permitted.
- Do not add dependencies beyond those named in Phase 0.
- After the phase: `flutter analyze` must report 0 errors and 0 warnings, and
  `flutter build apk --debug` must succeed. Show me the actual output.
- If something in the spec turns out to be wrong, impossible, or contradicted by
  the code, STOP. Write it to .agent/blockers.md and tell me. Do not improvise a
  different architecture.
- BEFORE flagging a risk or proposing a deviation, check .agent/invariants.md for
  a matching RESOLVED CONCERN. Raising a concern rather than improvising is
  correct and expected — this step only stops you re-deriving a question that was
  already settled on device in an earlier phase. If an invariant looks wrong to
  you, that is a blocker, not something to change silently.

Device verification:
- The OwnTone server is at `192.168.1.13`, reachable directly from the emulator
  over the LAN. Use that address as-is; do not assume it runs on the host.
- An Android emulator is available as `emulator-5554` (Android 16, API 36).
  Run the app on it with `flutter run -d emulator-5554` and verify this phase's
  behaviour yourself before reporting done. Do not report a phase complete on a
  clean `flutter analyze` alone.
- §7A of the UX spec lists what the emulator can verify and §7B lists the three
  checks that require real hardware. If this phase's verification falls in §7B,
  say so explicitly and hand me the steps rather than claiming it passed.
- Verification is MANUAL: drive the app's own UI on the emulator. Do not reach
  for adb or shell tooling to inspect app state. `pending_events` lives in
  app-private storage and the emulator image ships no `sqlite3` binary, so it
  cannot be read from the shell — do not waste time trying.
- To check that play and skip counts are correct, use the OwnTone web UI at
  `192.168.1.13` as the source of truth: note a track's play and skip counts
  before, then re-check them after a sync.
- If a step cannot be checked because the app has no view for it yet, say so
  rather than inventing a workaround. Some of those views are story D3 and are
  meant to be built.

When you believe the phase is done, BEFORE writing anything:
1. Re-read .agent/verification-protocol.md in full. Not from memory — open it.
2. Identify this phase's go/no-go check and run it, if you have not already.
   If you have not run it, the phase is BLOCKED, not complete.
3. Update .agent/invariants.md. Promote anything a future phase must not undo
   into it, in the format that file uses. If you hit a concern that looked real
   but turned out to be already handled, add it as a RESOLVED CONCERN on the
   relevant entry. Later phases run in isolated sessions and will not read your
   report — a fact that lives only there is a fact that gets lost.
4. Write your report using the exact template in §6 of the protocol. Every
   field is mandatory. Do not summarise it into prose.

Claims about behaviour must come from actions you performed and results you
observed on the emulator. A clean analyze and a successful build are not
evidence that anything works.

Your job this session is PHASE 3 ONLY, as defined in §3 of the refactor plan.
Do not begin any later phase. Do not do "while I'm here" cleanups that belong to
another phase.
```

**Keep everything above the final `PHASE <N>` line byte-identical between
sessions.** These sessions share a KV cache on the inference server, so an
unchanged leading token sequence is nearly free to re-read after the first
session — which is what makes four mandatory documents affordable. The phase
number is the only thing that varies, so it sits last. Editing the preamble per
phase, or moving the phase number earlier, throws that away.

---

## Per-phase notes

**Phase 0** — COMPLETE. Do the `just_audio` / `audio_service` major upgrade in
its own commit with nothing else in it. Everything downstream assumes this
ground is clear.

**Phase 0.5** — COMPLETE. Removed the sync worker's event-upload gate. Note that
its behavioural verification was not possible at the time: nothing writes
`pending_events` until Phase 3, so there were no events to upload. That check is
folded into Phase 3 below.

**Phase 1** — COMPLETE. The go/no-go passed: `content://` URIs play through
`just_audio`'s native path, so §6's top risk did not materialise. Two defects
found during its verification are now invariants 1 and 2 — do not undo them.
Phase 1 also left verification debt (shuffle, repeat, B5 previous, queue
mutation) that Phase 5 must exercise; see the table in its plan entry.

**Phase 3** — The whole point of the feature is that the numbers reaching OwnTone
are right, so verify against the server, not the app. Play a track to completion,
skip another, run a sync, then check both tracks' play and skip counts in the
OwnTone web UI. This is also the first real test of the Phase 0.5 gate removal —
if counts do not move, the upload path is still broken.

**Phase 7** — Sync against the real server at `192.168.1.13`, reachable directly
from the emulator over the LAN.
