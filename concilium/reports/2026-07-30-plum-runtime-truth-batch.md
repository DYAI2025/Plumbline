# Concilium — Runtime Truth Integrity batch (PLUM-9 … PLUM-15)

**Date:** 2026-07-30 · **Mode:** deep (four bodies) · **Subject:** the batch itself, not the framework.

## Framed subject

**(a) The idea.** Five runtime governance gates that check *governance truth* rather than
test results: a canonical machine-readable scope manifest, a pre-coding plan-vs-scope
drift gate, a runtime-state hygiene guard, evidence-target binding for the reality
ledger, a remote-state watcher, and generated-artifact provenance. Each was built because
a real pilot produced a measured false green or false red.

**(b) Underlying user goal (what any pivot must preserve).** A solo developer running
autonomous coding agents needs to know whether work is *actually* done — not that tests
are green, that an agent claimed done, or that Jira says Done.

**(c) Constellation.** ~95 subagent prompts (README says 86 — the count disagrees with
itself). The batch touched no agents: 5 CLIs, 4 test suites, ~273 assertions, ~6000 lines.

## Diversity disclosure — read this before weighing anything below

**All four bodies ran on Claude. Correlated blind spots are NOT covered.** Treat this as
a structured single-model critique, not cognitive diversity.

Two attempts were made to run the Skeptic seat on a foreign model and both failed:
`gpt-5.5` requires a newer Codex CLI than the installed 0.41.0; `gpt-5` is unavailable on
a ChatGPT-account login. The OpenRouter backend was also unavailable (`COUNCIL_BACKEND`
unset, no key).

`/concilium` declares a **hard floor of two independent bodies, where independence means
uncorrelated cognition, or abort and say so**. That floor was not met. Nothing aborted;
the run continued and produced this report. That is a declared fail-closed gate that did
not fire while the session proceeded anyway — structurally the same shape as the false
greens this batch was built to fix. It is recorded here rather than smoothed over, and it
is itself one of the review's findings (KO-3).

**Partial collision only.** Round 1 dispatched three bodies in parallel with no
cross-talk. The Skeptic ran last and *was* given the other three positions, so its
contract is effectively a one-sided round-2 reaction. A full round-2 collision was not
run: the user's decisions arrived and redirected the session to implementation. Stated
plainly so nobody reads more convergence into this than was earned.

## Round-1 positions

All four returned **`pull-pivot`**. Four-of-four agreement among four Claude bodies is
weak evidence, and the Skeptic said so explicitly: *"treat 4-0 here as evidence of
correlation, not of truth."* Its pivot vector also points somewhere none of the others
proposed.

### Market Realist
Demand is **observed at n=1 (the author) and imagined everywhere else**. Repo signals
(GitHub API, `supported`): 5 non-author stars, 0 forks, 0 watchers, 0 issues, 0
discussions, 81 author PRs / 0 external, 17 views / 5 uniques per 14 days. Explicitly
refused to count 559 clones / 395 unique cloners as adoption (`inferable`: crawlers —
flat on days with zero CI runs, ~79× more cloners than viewers, zero downstream action).
Market anchor: AI code review sells at $24–30/dev/mo and **comments rather than blocks**;
revealed preference is advisory correctness. Wedge ranking: PLUM-11 is the only gate that
needs no worldview; PLUM-10/12/14 are author-only. Pivot: publish the measured
false-green mechanisms as a public corpus, ship the hygiene checker standalone.

### Tech Arbiter
Verified the batch delivers *"documentation with an exit code"* against a framing that
claimed fail-closed enforcement: `plumbline-enforce.sh` resolved exactly three CLIs and
the four new wrappers appeared in **zero** hooks. PLUM-10/13 genuinely wired (they ride
`scope-check`/`reality-check`); PLUM-12/14/15 prompt-only; PLUM-11 in the orchestrator
**not at all**. Trust-root verdict: **"strong oracle, agent-controlled aperture"** — real
defence against accident and drift, none against an agent reasoning past a blocker. Also
found `tokens = proof_tokens or [dataset]` (near-circular default), `shell=True` with no
`timeout=`, and an `rglob("*")` full-tree walk per producer.

### Distribution Realist
Produced the review's strongest single number. In the repo that **authored** these gates:

| artifact | enforcement | coverage |
|---|---|---|
| Reality Ledger | **hook-enforced** | **9 / 9** |
| scope manifest (PLUM-10) | opt-in + prompt | **0** — `docs/scope/` did not exist |
| evidence targets (PLUM-13) | opt-in + prompt | **0** — `docs/evidence/` did not exist |
| provenance (PLUM-15) | opt-in block | **0** feature uses |

The only `.scope.json` in the tree was a test fixture. **Enforced → 100%;
prompt-suggested → ~0%.** Not a forecast — a measurement. Also: no plugin manifest, and
the README explicitly opts out of the one native install channel; fail-closed-by-default
would break a stranger's repo on first run.

### Skeptic (Advocatus Diaboli)
Declined to be the fourth vote. Five killer objections, all `supported` with file:line:

- **KO-1** — the arming marker `docs/context/.active-feature` is **gitignored**, so `rm`
  silently disarms every gate with zero git trace, while a *blank* marker blocks. Same
  threat, one keystroke apart, opposite handling.
- **KO-2** — `docs/GATE-ENFORCEMENT-AUDIT.md`, committed **2026-06-04**, already states
  *"Everything that makes `/agileteam` distinctive as governance is prompt-only."* Three
  bodies spent a round rediscovering a document already in the tree. The real finding is
  behavioural: the author published that audit and then shipped 6000 more lines of
  prompt-only governance.
- **KO-3** — this council is a live instance of the failure class (see disclosure above).
- **KO-4** — the block message names the exact missing token and is fed back to the agent
  that wrote the artifact: *"the gate hands the student the rubric and the missing
  answer, then re-grades."* No adversarial intent needed; helpfulness suffices.
- **KO-5** — `metrics/runs.jsonl` is **2 lines**, and no corpus measures false-done
  escape rate. Six gates built on six remembered incidents, each n=1, value asserted —
  in a repo whose own rules forbid exactly that for benchmark claims.

Conceded the Arbiter's oracle/aperture split **for provenance only** (the byte comparison
is genuinely agent-independent) and broke it elsewhere: when the agent controls *whether
the oracle runs*, oracle strength is not the binding constraint. Verdict on the layer:
*"a linter with a governance costume"* — real defence against accident, drift and
formatter damage; **no defence against an incentive**.

## Trajectory

**Resonance.** All four: the defects were real and measured; adding gate #6 is not the
binding constraint. Market and Distribution independently reached the same repo metrics
and both independently refused the clone-count trap. All four flagged that
fail-closed-by-default is right for the author and hostile to a stranger.

**Repulsion.** One sharp axis: Tech Arbiter prescribed *wire the gates into the hook*;
Distribution Realist prescribed *NOTICE-not-BLOCK first, or distribution makes it worse*.
Not reconcilable by env flags — the Skeptic showed why: OFF gives notice with extra
machinery, ON gives the mid-build block the author has already hit twice.

**Instability.** Market's pivot depends on reach being the binding constraint; it said its
own frame voids itself if Plumbline is a private instrument. **Resolved by the user:
both, sequenced consciously** — coverage and wiring now, corpus and packaging later.

**One claim that did not survive.** The Skeptic called the Tech Arbiter "checkably wrong"
about `plumbline-plan-check`. Verified: the Arbiter was right (its table recorded
plan-check as `yes:716` and named runtime-hygiene as the orphan); `plan-check` in
`commands/` = 1, `runtime-hygiene` = 0. The Skeptic conflated PLUM-12 with PLUM-11. Both
bodies agreed on the fact. Recorded because the most aggressive voice is not
automatically the correct one.

**One finding neither body reached, produced by orchestrator verification.** The Stop hook
registered in `~/.claude/settings.json` points at `_TOOLZ/plumbline_v1/Plumbline/…` —
a *different checkout*, HEAD `020c123` (2026-07-28), containing **none** of the four new
CLIs. On this machine the enforcement transport points at the pilot tree. The Skeptic got
closest, noting this repo's `.claude/settings.json` carries SessionStart only.

## Recommendation — SHARPEN

The gates are not the product and were never the detector; the discipline and the
measured corpus are. But three specific things in this batch are load-bearing and survive
every argument above: the **scope-parser fixes** (real bugs in a deterministic text
parser, reproduced against pre-fix code), the **provenance byte-comparison** (a genuine
agent-independent oracle), and **`GATE-ENFORCEMENT-AUDIT.md`** itself.

Decisions taken by the user during the review, and executed:

1. **Plumbline is both a private instrument and an intended product**, sequenced
   consciously: coverage + wiring now, corpus + packaging later.
2. **The four orphaned CLIs are now invoked by the Stop hook as advisory, default-ON,
   never blocking.** Default-ON because for a governance check off-by-default is
   *absence*, not safety (9/9 vs 0/9). Notice-only because these four need artifacts a
   feature may legitimately lack, and a high false-RED rate trains the human — the only
   oracle with a track record — to stop reading reds. **"Fail-closed" is explicitly not
   claimed for them.**
3. **KO-1 closed:** an absent marker while confirmed canvases exist *and* the tree is
   dirty now emits `PRIL_MARKER_ABSENT` instead of silently no-opping, with negative
   controls proving an ordinary un-armed session stays silent.
4. **`test_cli_wiring.sh`** makes an unreachable wrapper a hard failure, with `advisory`
   as a distinct declared class so the enforced/advisory distinction cannot erode.
5. **Doc corrections:** the batch-level "wired into a fail-closed Stop hook" overclaim is
   retracted in place; 279 → 273 assertions.

## Conditions and falsifiers

- **Skeptic's falsifier (flips to `pull-go`):** a measured escape-rate experiment on a
  corpus the agent did not author, showing armed gates reduce false-done escapes outside
  the noise band. Zero delta → `pull-kill` on the gate layer, preserving `CLAUDE.md` and
  the parser fixes. **This experiment is the next work and is now queued.**
- **Distribution's falsifier:** the next two `/agileteam` runs each produce their scope
  manifest and evidence targets *without the human being reminded*.
- **Market's falsifier:** one non-author installs Plumbline, is blocked by one of these
  gates on their own repo, and keeps it. Stars do not count.

## Open questions (unresolved — not papered over)

1. **KO-2 is unanswered.** Why did publishing the prompt-only audit in June not change
   what got built in July? That is a process question no gate can answer.
2. **The stale transport** needs a global settings change (user-owned file).
3. **KO-4 stands.** The block message still names the missing token to the agent that
   wrote the artifact. Withholding it was proposed; not implemented.
4. Whether any human other than the author has ever run `install.sh`.
5. `86` vs `~95` subagents across README and CLAUDE.md.

## Evidence-class ledger

| claim | class |
|---|---|
| 4 of 5 CLIs invoked by zero hooks; PLUM-11 absent from the orchestrator | **supported** (grep, verified by orchestrator) |
| enforced 9/9 vs prompt-suggested 0/9 coverage | **supported** (directory listing, verified) |
| marker is gitignored; `rm` silently disarms | **supported** (`.gitignore:8`, hook line 73) |
| `GATE-ENFORCEMENT-AUDIT.md` said prompt-only on 2026-06-04 | **supported** (git log + line 57) |
| `metrics/runs.jsonl` = 2 lines | **supported** |
| registered Stop hook points at another checkout | **supported** (settings + git log, verified) |
| assertion count 273, not 279 | **supported** (per-suite sum) |
| GitHub traffic/stars/forks figures | **supported** (API, two bodies independently) |
| 395 unique cloners are crawlers, not adopters | **inferable** — explicitly not claimed as fact |
| AI review sells at $24–30/dev/mo and only comments | **supported** (vendor pricing) |
| "false green from agents" is a budgeted purchase category | **unverified** — open question |
| any specific cloner is human | **do-not-claim** |
| gates reduce false-done escape rate | **unverified** — this is the experiment that would decide it |
