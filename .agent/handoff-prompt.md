# Handoff prompt for working sessions

The standing instructions for agents live in **`AGENTS.md` at the repository
root**. Tools that read it automatically (Claude Code via `CLAUDE.md`, and
anything following the agents.md convention) need nothing from this file.

This file exists for harnesses that do **not** auto-load it. Paste the block
below, then append the task.

---

```
Read AGENTS.md at the repository root before doing anything else, and follow it.
It routes you to the documents in .agent/ that matter for this task and states
what "done" means.

Two things to confirm you have taken on board before you start, because they are
the ones sessions most often miss:

- Tell me your understanding of the task and what you intend to change, then
  WAIT for my confirmation before editing anything.
- The OwnTone server at 192.168.1.13 is the user's real music library. Read from
  it; do not modify it.

Your task:
```

*(append the task here — specific, with what success looks like)*

---

**Keep the block above byte-identical between sessions.** These sessions share a
KV cache, so an unchanged leading token sequence is nearly free to re-read after
the first. Put the task after the block, never inside it.

## Writing the task

The two failure modes, in roughly equal measure:

- **Under-specified** — "fix the sync bug" produces a session that guesses at
  which bug and what done looks like.
- **Over-constrained** — a wall of NEVER/ALWAYS makes an agent brittle and
  unable to handle the case you did not anticipate.

Aim between them: name the defect, point at the evidence (a blocker entry, a
file:line, an observed symptom), say what success looks like concretely, and
leave the method open unless you have a reason not to.

If a previous session diagnosed the problem, say so and link it — re-deriving a
diagnosis is the most common waste here. If the diagnosis might be wrong, say
that too, and give the session permission to disagree with it.
