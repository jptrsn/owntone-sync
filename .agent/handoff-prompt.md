# Handoff prompt for working sessions

The eight-phase player refactor is **complete and shipped** (v0.2.0, 2026-10-05).
This prompt is for ongoing work: fixing a defect, closing a backlog item, or
adding a feature.

Paste the block below, then append a short, specific statement of the task.
Everything inside the block stays byte-identical between sessions — see the note
after it.

---

```
You are working on OwnTone Sync, a Flutter/Android app that syncs music from an
OwnTone server and plays it offline. Read these FOUR documents in full before
touching any code. They are authoritative:

  .agent/player-ux-spec.md        — what the app is meant to do: user stories
                                    and acceptance criteria. Still live.
  .agent/invariants.md            — load-bearing facts established the hard way,
                                    each with what breaks if you undo it. Short
                                    entries, binding. Read it LAST, before you
                                    start.
  .agent/verification-protocol.md — what counts as evidence, and the report
                                    format you must use. Short. Binding.
  .agent/blockers.md              — open defects. Check whether what you are
                                    about to fix is already described here,
                                    often with a diagnosis.

Two more, read only if relevant:
  .agent/backlog.md               — unscheduled ideas. NOT a to-do list. Do not
                                    implement from it unless asked.
  .agent/player-refactor-plan.md  — MOSTLY HISTORICAL. Its §1 defect inventory
                                    describes code as it was BEFORE the refactor
                                    and every defect in it is fixed; do not
                                    verify it against today's code. Its §2
                                    (target architecture) is still accurate and
                                    is the part worth reading.

Reports in .agent/reports/ are historical evidence, not guidance. Do not derive
constraints from them. Anything still binding was promoted into invariants.md.

Before writing code:
1. Read the four documents completely.
2. Read the files your task touches, and verify any claim you have been given
   against the actual code rather than assuming it is still accurate.
3. Tell me your understanding of the task and what you intend to change, and
   wait for my confirmation before editing.

Binding constraints:
- Stay in scope. No "while I'm here" cleanups — raise them instead.
- Prefer deleting dead code over adapting it.
- Do not add dependencies without asking first. The project has deliberately
  kept its dependency list short.
- `flutter analyze` must report 0 errors and 0 warnings, `flutter test` must
  pass, and `flutter build apk --debug` must succeed. Show me the actual output.
- If something turns out to be wrong, impossible, or contradicted by the code,
  STOP. Write it to .agent/blockers.md and tell me. Do not improvise a different
  architecture.
- BEFORE flagging a risk or proposing a deviation, check invariants.md for a
  matching RESOLVED CONCERN. Raising a concern rather than improvising is
  correct and expected — this only stops you re-deriving something already
  settled on a device. If an invariant looks WRONG to you, that is a blocker,
  not something to change silently.

Tests:
- There is a suite: `flutter test` (Dart) and `./gradlew :app:testDebugUnitTest`
  (Kotlin JVM, needs JDK 17). CI runs analyze + flutter test on pull requests.
- Tests are derived from invariants.md, not from the implementation. If you add
  one, it must cite the invariant or requirement it guards. A test that merely
  restates current behaviour is worse than none: it makes fixing a bug harder
  while providing false assurance.
- A failing test is a finding. Do not adjust the test to match the code without
  saying so explicitly.

Device verification:
- The OwnTone server is at `192.168.1.13` — the user's real, curated library.
  DO NOT modify it: no deleting playlists, no editing tracks. Induce failures
  app-side. If a check needs a rating or count changed, record the original
  first and restore it, confirming the restore against the API.
- Emulator `emulator-5554` (Android 16, API 36): `flutter run -d emulator-5554`.
  A physical device may also be attached — check `flutter devices`.
- Verification is MANUAL: drive the app's own UI. A clean analyze and a
  successful build are not evidence that anything works.
- For a RENDERING bug, attach `flutter run` and read the console (invariant 29).
  Do not bisect with screencaps: framework errors log under the tag `E/flutter`,
  and `uiautomator dump` returns an empty window while the Now Playing sheet is
  open. Both obvious instruments fail silently on the same screen.
- If a check cannot be run, say so with the reason. Do not claim it.

When you believe the work is done, BEFORE writing anything:
1. Re-read .agent/verification-protocol.md in full. Open it, not from memory.
2. Run the check that is the whole point of the task. If you have not run it,
   the task is BLOCKED, not complete.
3. Update .agent/invariants.md with anything a future session must not undo, and
   add a RESOLVED CONCERN for any worry that turned out to be already handled.
   Later sessions do not read reports — invariants is the only channel that
   reaches them.
4. Write .agent/reports/<task-name>-report.md using the exact §6 template. Every
   field is mandatory. Do not summarise it into prose.
5. If you fixed something listed in blockers.md, mark that entry RESOLVED with
   what changed and what was verified.

Claims about behaviour must come from actions you performed and results you
observed. 
```

---

**Keep everything in that block byte-identical between sessions.** These sessions
share a KV cache on the inference server, so an unchanged leading token sequence
is nearly free to re-read after the first — which is what makes four mandatory
documents affordable. Put the task description *after* the block, never inside
it.

## Running more than one session at once

**Give each session its own git worktree.** Two sessions sharing one working
copy will clobber each other: a branch switch or a stash in one destroys
uncommitted work in the other. This nearly happened once.

```
git worktree add ../owntone-<task> -b <task>
```

## Current state

- v0.2.0 shipped 2026-10-05. DB schema at v8.
- Open defects: see `blockers.md`.
- Known gaps and unscheduled ideas: see `backlog.md`.
- One release check is still outstanding: a physical AVRCP button press
  (§7B-1 of the UX spec). The transport path beneath it is verified; only the
  physical button edge is untested.
