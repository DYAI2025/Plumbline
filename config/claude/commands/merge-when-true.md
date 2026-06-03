---
description: Gate a PR/branch merge on Plumbline's TRUE-green standard — never on passing tests alone. Here "green" means the work *hangs true* (Reality-Ledger real-boundary, wired-in-prod, independence, confirmed customer value, no silently-downgraded RED), the CI *conclusion* is success (not merely `mergeable`), and `run_all.sh` is green on `main` AFTER the merge. Use to finish a reviewed branch / decide whether a PR may merge.
---

You are running **merge-when-true** — Plumbline's merge gate, *"does it hang true?"*
applied to the decision to integrate work into `main`.

## The one rule (read this first)

**"Green" is NEVER "the tests pass."** This repo exists because *"tests pass"* was once
mistaken for *"it works"* — a feature whose tests were all green while the real
integration was a no-op. A merge authorised on green tests alone is that incident,
re-armed. **Passing CI is necessary, never sufficient.** A merge is authorised only when
the work *hangs true* by every gate below. If any gate is RED or unknown, **do not merge —
even if CI is green.** Uncertainty resolves toward *not* merging; escalate to the user.

## Pre-merge gate — ALL must hold; any RED blocks the merge

1. **CI conclusion = success — not `mergeable`.** `gh pr checks <PR>` → every required
   check is `pass` (confirm the *conclusion*, not `status=CLEAN`/`mergeable=MERGEABLE`,
   which only mean "no failing *required* check"). A release-please / `GITHUB_TOKEN`-pushed
   branch may get **no CI run at all** — then run `bash config/claude/tests/run_all.sh` on
   the branch yourself and require `ALL CHECKS PASSED`. (A local run substitutes for an
   *absent* CI run; it does not excuse confirming any required check that *does* exist.)
2. **Reality Ledger.** Every requirement that touches I/O, a remote, an external API, or UI
   sits at `real-boundary-smoke` or `production-verified`. Anything still `*-fake` is **RED
   regardless of green tests**, and that RED was **not** silently downgraded.
3. **Wired-in-prod.** The real implementation has a test through the **production
   composition root** — not "exists in tests, never composed in prod."
4. **Independence.** Whoever wrote the code did **not** review it; review / security /
   validation did not merely echo the coder's reasoning. The diff was independently
   reviewed (spec-compliance *and* code-quality).
5. **True-Line / customer value.** The change stays true to the confirmed human customer
   value. Green tests, completed tasks, and agent consensus are **not** sufficient on their
   own — re-ask "did we build the right thing, and does it still serve the confirmed Vision?"
6. **Human gates intact.** Requirements/Canvas/product-judgment/acceptance gates that apply
   carry explicit human sign-off; no autonomous step slipped a human gate.
7. **Honesty.** No claim is unbacked by code/tests/logs; absent tooling is marked `MISSING`,
   not faked; no RED was laundered into a "documented limitation."

> If a gate does not apply to this change (e.g. a docs-only PR has no Reality-Ledger
> surface), say so explicitly — "N/A because …" — rather than silently skipping it. A
> skipped gate you can't justify is itself a RED.

## Merge (only once the gate holds)

1. **Watch CI to conclusion:** `gh pr checks <PR> --watch` (run it in the background so the
   session isn't blocked; you'll be notified on completion).
2. **On green AND gate-holds:** integrate, then re-verify on the result:
   ```bash
   git switch main && git pull
   gh pr merge <PR> --merge --delete-branch
   git pull
   bash config/claude/tests/run_all.sh        # MUST end: ALL CHECKS PASSED
   ```
3. **Post-merge truth.** `run_all.sh` must be green on `main` *after* the merge, not just on
   the branch. If `main` is RED → revert or fix immediately; **never leave `main` RED**.

## On CI red

`gh run view --log-failed <run-id>` → diagnose, fix on the branch, re-push, re-watch.
**Never merge red.** A red CI is a finding, not an obstacle to route around.

## Guardrails (each from a real incident this repo hit)

- **Never merge on `mergeable`/`CLEAN` alone.** It only means "no failing *required* check";
  a workflow-token-pushed branch gets no CI run, so `mergeable` can be true while nothing
  was ever tested.
- **"Green tests" ≠ "true."** Gates 2–3 are RED *regardless* of green tests; that is the
  whole point of this command. Do not let a green CI badge end the conversation.
- **Verify `main` after the merge, not just the branch** — a branch that was green can still
  land RED on `main` (e.g. a hardcoded value the repo has since moved past).

*This command encodes the merge-safety + True-Line invariants from `CLAUDE.md` and
`README.md`. It does not replace `/agileteam`'s gates or human acceptance — it is the final
"may this integrate?" check that refuses to treat green tests as done.*
