# pipe-core-v1 — full-pipeline bench harness for the agileteam DNA

The faithful counterpart to `bench-core-v1` (which probes single agents on test-PLAN
derivation). `pipe-core-v1` runs the **whole pipeline** (tester → coder → code-reviewer →
production-validator → product-owner) per task per arm, **builds real code**, and measures
the **built increment** with a deterministic ground-truth oracle — not a test plan, not a
subjective judgement.

> **This directory is the INSTRUMENT. Running it is the expensive step.** A full execution
> is multiple `/agileteam`-style sprints per task per arm (each ~hundreds of k tokens) ×
> ≥3 runs × 2 arms — i.e. millions of tokens / hours. Do NOT launch a full run without an
> explicit go-ahead. Build/verify the harness first (this is done); execute deliberately.

## The oracle that makes it faithful (and objective)
Every buildable task ships a **regression mutation**: a one-line break of the exact
dark-zone behaviour the DNA targets. After an arm builds the feature green, apply the
mutation and run **the arm's OWN test suite**:
- tests go **RED** → the arm's increment GUARDS the dark-zone (caught). 
- tests stay **GREEN** → the arm shipped the blind spot (escaped defect).

No judge needed for the primary metric — it is a deterministic test-run outcome on the
built code. (The T08 datapoint pioneered this; here it is generalised across tasks.)

## Task mix (7)
Buildable (mutation oracle) + control (false-positive at pipeline level) + review-diffs
(the reviewer-narrowing check, scored by blind judge):

| id | type | dark zone | oracle |
|---|---|---|---|
| `T08-account-deletion` | gap-build | wiring + fake-only (un-cued) | un-wire `store.delete_all` from `delete_account` → arm tests must go red |
| `T02-webhook` | gap-build | fake-only reality | make the webhook client call a no-op → arm tests must go red |
| `T03-cache` | gap-build | named-failure-mode | break the cache-error fallback (raise instead of fall back) → arm tests must go red |
| `CTRL-discount` | control-build | none (pure logic) | NO mutation; FALSE POSITIVE if the arm's pipeline invents a wiring/reality gap or blocks a clean increment |
| `RDIFF-A` | review-diff | broad scrutiny | 3 planted non-wiring defects; recall scored by blind judge (no wiring gap present) |
| `RDIFF-B` | review-diff | broad scrutiny | 3 planted security defects; recall scored |
| `RDIFF-C` | review-diff | broad scrutiny | 3 planted security/robustness defects; recall scored |

`RDIFF-*` are the reviewer-narrowing controls baked in from the start (the 2026-05-29
investigation): they ensure a "catches more dark-zone defects" result can never hide a
"degrades broad review" cost.

## Metrics (lower is better unless noted)
- **escaped-defect-rate** (primary) = mutation-not-caught / (gap-build tasks × runs).
- **pipeline false-positive-rate** = clean control increments wrongly blocked or flagged
  with a phantom gap / (control tasks × runs).
- **reviewer non-wiring-recall** (higher better) = planted defects flagged on RDIFF-* —
  guards against narrowing.
- **build success + cost** = did the arm reach green; tokens/wall-clock per run.
Report all per arm × (model). Anti-Goodhart: weight escaped-defect + reviewer-recall +
low-FP together; never trade one silently.

## Arms (pinned)
- `baseline` = agents @`ee77e4c` (agileteam v3, pre-DNA).
- `dna` = agents @`HEAD` (full DNA: gate+3 tester, wired-in-prod reviewer, reality PO, …).
Pin ONE agent snapshot per arm for the whole run (record commit in `config_fingerprint`).
`pin-arms.sh <commit> <outdir>` extracts the arm's relevant prompts
(tester, coder, code-reviewer, production-validator, product-owner, requirements-analyst).

## Per-(task, arm, run) procedure — gap-build / control-build
1. `cp -r tasks/<id> <work>/<id>__<arm>__r<n>` (fresh repo copy).
2. **tester** (arm-pinned) derives + writes acceptance/E2E tests into `tests/`.
3. **coder** (shared prompt — identical both arms) implements TDD until
   `pytest -q` is green.
4. **code-reviewer + production-validator + product-owner** (arm-pinned) review the diff →
   SHIP / BLOCK verdict (record).
5. **Oracle** (neutral, deterministic): apply `oracles/<id>` mutation, run the arm's own
   `pytest -q`. Record red (caught) / green (escaped). For controls: no mutation; record
   whether the pipeline raised a phantom gap or blocked.
6. Record build-success, verdict, oracle result, tokens.

## Per-RDIFF procedure — review-layer
Feed the wired diff (`review-diffs/<id>.md`) to the arm's **code-reviewer** (+ product-
owner) → findings + verdict. Blind-judge the findings against `oracles/RDIFF-<id>.md`
(planted defect list, judge-only). Record non-wiring-recall + verdict.

## Judging (blind, only where needed)
The mutation oracle needs NO judge (deterministic). Only RDIFF recall and the control
phantom-gap call use a blind judge: anonymise arm identity, de-jargon house terms, score
the underlying concern in any phrasing (per `bench-core-v1` discipline).

## Runs / power
≥3 runs/arm/task (build + review outputs are high-variance — see the reviewer-narrowing
investigation where N=1 misled). Run weak (haiku) AND strong (opus) producers to separate
floor-raising from ceiling. Report minimum-detectable-effect honestly.

## Honesty guards (baked in)
- Frozen corpus — edit = new version, re-baseline.
- Mutation oracle is deterministic and code-level — it measures the built increment, not a
  plan or an opinion.
- RDIFF-* controls ensure dark-zone gains can't hide broad-review regressions.
- Coder prompt is identical across arms — the only variable is the DNA-differing agents.
- A "0 escaped" with no control/RDIFF data is NOT a pass — all three metric families
  must be reported together.
