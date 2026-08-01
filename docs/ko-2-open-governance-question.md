# KO-2 — an open governance question, not a work item

**Status: OPEN. Deliberately NOT answered by building anything.**

## The question

> Why did the audit finding of **2026-06-04** not change the implementation decisions
> that followed it?

## The finding, and its date

`docs/GATE-ENFORCEMENT-AUDIT.md` was committed on **2026-06-04** (`2f73e03`). It states,
at line 57:

> **Everything that makes `/agileteam` distinctive *as governance* is `prompt-only`**

and at line 44:

> Genuinely fail-closed at runtime = a narrow PRIL core.

Caveat #1 (line 71) adds that the PRIL Stop hook was not active in this repo's own
sessions. Table 2 lists wired-in-prod, the Watcher verdicts, Gates A–E and the
independence invariant as having **zero** machine enforcement.

## What happened next

Eight weeks later, the PLUM-9…15 batch shipped ~6000 lines and five new gates. Four of
the five were invoked by nothing: the Stop hook resolved three CLIs, the new wrappers
appeared in zero hooks, and one of them was referenced nowhere in the 867-line
orchestrator. The batch's own documentation described them as "wired into a fail-closed
Stop hook."

So the June audit had already named the exact failure mode the July batch then committed
— in the batch built to close that failure mode.

## Why this is not a code task

The obvious response is to build something: a checker that verifies its own wiring, a
gate that audits the gates. **That response is the pattern under examination.** A finding
that a framework's governance is prompt-only was answered with more prompt-only
governance; answering it now with another enforcement layer would be the same move a
third time.

The `test_cli_wiring.sh` contract added in this batch is a fair regression guard for the
*mechanical* half — an unreachable wrapper is now a hard failure. It does not touch the
question above. Nothing mechanical does.

## What would actually answer it

Candidate lines of inquiry, none of them code:

- **Did the audit's conclusion ever reach the decision point?** It exists as a document.
  Was it read at the moment the batch was scoped, or was it written, filed, and not
  consulted again?
- **Is writing the honest audit doing the work of fixing it?** Publishing an accurate
  self-criticism produces the feeling of having addressed the problem. That is a known
  failure shape, and this repo's own stance — *make the implicit explicit* — was designed
  against it.
- **Was building the next gate simply the available move?** Gates are tractable,
  reviewable, and produce visible progress. "Stop building gates and measure whether they
  work" produces none of those things for days.
- **Is there a role gap?** The `/concilium` review noted that no role in
  `agileteam-roster.yml` owns *deletion* or *not-building*; every role adds.

## Relationship to the other open slice

KO-5 (`docs/plans/2026-07-30-escape-rate-corpus-slice.md`) asks whether the gates work.
KO-2 asks why knowing they were not wired changed nothing. They are independent: the
corpus could show the gates are load-bearing and this question would still stand.

## Disposition

Carry into a retrospective as a governance question with a human answer. **Do not close
it by implementing a gate.**
