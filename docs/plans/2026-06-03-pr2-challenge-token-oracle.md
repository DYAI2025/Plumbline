# PR-2 — Challenge-Gate Token Oracle (Behavioral, Finding #2) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Work strictly TDD-first. Show every diff before applying. Commit atomically. `bash config/claude/tests/run_all.sh` MUST end with `ALL CHECKS PASSED` after every task, and `shellcheck` must stay clean.

**Goal:** Turn Finding #2 — *"the challenge gate's `≤ ~15k tokens total` bound is aspirational prose, not an enforced fact"* — into a **measured** result, by building a deterministic scoring instrument + a faithful, honest measurement procedure for the real `concilium --mode=challenge` gate.

**Architecture:** Two cleanly separated parts. **Part 1 (this PR, CI-safe):** a deterministic Python scorer `challenge_token_oracle.py` that takes captured run-data (per-role token counts + output text) and computes the two v1 verdicts — **O1** (total tokens ≤ bound — the decisive answer to Finding #2) and **O3** (the three role outputs are distinct — guards against consensus-theater) — plus its bash test module with synthetic fixtures (including a MISSING-not-faked case), a registered metric, and a leak-checked seeded fixture + runbook. **O2 (≤1-page summary) is deliberately deferred** (see Task 2 note): the one-pager is the gate's *distilled* output, not the sum of the three raw role contributions, so scoring it faithfully needs the orchestrator's distillation step captured — out of scope for this lean, faithful pilot. **Part 2 (gated, post-merge, NOT in CI):** an explicit procedure that dispatches the three *real* concilium challenge-mode body prompts against the seeded fixture as TEXT-ONLY subagents, captures each one's reported `subagent_tokens` + output, feeds the scorer, and emits one honest run to `runs.jsonl` on the `agileteam-improved` branch — never `main`.

**Tech Stack:** Python 3 (stdlib only — `json`, `argparse`, `re`), Bash test harness (`lib.sh`, `set -uo pipefail`), `shellcheck`. Reuses `config/claude/metrics/emit_run.py` + `process_health.py`. No new third-party deps.

**Why measurable here (verified 2026-06-03):** `emit_run.py` takes `--tokens-total` as an *input* (it does not self-measure), but this harness reports a real `subagent_tokens` figure on every dispatched subagent — so summing the three challenge-role subagents' reported tokens is a genuine, non-estimated measurement of the gate slice's cost. If that figure is unavailable in some environment, the run is recorded **MISSING**, never fabricated.

---

## Standing constraints (read before Task 0) — the Plumbline guardrails

- **Never commit to `main`.** Isolate on `feat/challenge-token-oracle` (Task 0). Multi-agent workspace: don't stash/switch others' branches/worktrees.
- **Code → `main`; measured runs → `agileteam-improved`.** Part 1 (instrument code) merges to `main` via PR. The Part-2 run's `runs.jsonl` record accumulates on `agileteam-improved` (per CLAUDE.md `main` stays the frozen baseline). **`runs.jsonl` must NOT be created/committed on `main` or the feature branch.**
- **Never fabricate (bench-oracle guardrail).** If a precondition is missing — token usage not reported, fixture leak, instrument not validated — STOP and report it. A null/negative result (the bound does NOT hold) is a valid, publishable result; a fabricated pass is misconduct.
- **MISSING discipline:** the scorer returns a distinct MISSING status (exit 2) when any per-role token figure is absent — it must NOT default a missing number to 0 or to "pass".
- **Validate the instrument before spending model tokens (bench-oracle guardrail).** The synthetic test fixtures (Task 3) must prove the scorer *discriminates* (a clearly-over-bound input fails O1; near-identical outputs fail O3; a missing token figure → MISSING) BEFORE any real model run in Part 2.
- **Leak check (bench-oracle guardrail).** The seeded Canvas/idea fixture must not telegraph "be terse" / "stay under 15k" or anything that trivially games the token count. Document the fixture's neutrality.
- **Bench isolation (learned rule).** In Part 2, the role subagents are **TEXT-ONLY** ("respond with your challenge as text; do NOT Write/Edit/Bash any files"); the seeded fixture is read-only; after the run verify `git status` clean and `run_all.sh` green.
- **Model disclosure + anti-Goodhart.** Every recorded result names the model that ran and the run count; the bound-hold is reported *with* the measured token total beside it (never a bare "passes"). State reach honestly: a few runs on one model can *refute* "the bound always holds" but cannot *establish* it generally.
- **Green gate before every commit:** `run_all.sh` ends `ALL CHECKS PASSED`.

---

## Task 0: Isolate the work

**Step 1 — Clean tree on `main`:** `git -C "$REPO" status --short && git rev-parse --abbrev-ref HEAD` → empty, `main`.
**Step 2 — Branch (ask before switching):** `git switch -c feat/challenge-token-oracle`.

---

## Task 1: Register the scored metric

**Files:** Modify `config/claude/metrics/process_health.py` (the `DIRECTIONS` dict).

**Step 1 — Failing check.** From repo root:
```bash
python3 -c "from importlib import import_module; import sys; sys.path.insert(0,'config/claude/metrics'); print('challenge_gate_tokens' in import_module('process_health').DIRECTIONS)"
```
Expected now: `False`. After Step 2: `True`.

**Step 2 — Add the key** to the `DIRECTIONS` dict (lower is better → `-1`), next to `cost_per_req`:
```python
    "challenge_gate_tokens": -1,
```

**Step 3 — Verify** the one-liner prints `True`, and that `emit_run.py` now accepts it:
```bash
python3 config/claude/metrics/emit_run.py --corpus-id smoke --mode full \
  --metrics '{"challenge_gate_tokens": 12345}' --out /tmp/smoke-runs.jsonl && tail -1 /tmp/smoke-runs.jsonl ; rm -f /tmp/smoke-runs.jsonl
```
Expected: a JSON record containing `challenge_gate_tokens`. (Writes to `/tmp`, NOT the repo.)

**Step 4 — Commit:**
```bash
git add config/claude/metrics/process_health.py
git commit -m "feat(metrics): register challenge_gate_tokens as a scored metric"
```
(Commit type `feat` — this is a real capability addition that should be visible in the changelog.)

---

## Task 2: The deterministic scorer (TDD)

**Files:** Create `config/claude/metrics/challenge_token_oracle.py`.

**Run-data input schema** (produced by the Part-2 procedure; for tests, synthetic):
```json
{
  "model": "opus",
  "bound": 15000,
  "roles": {
    "challenger": {"tokens": 4100, "text": "...challenge text..."},
    "advisor":    {"tokens": 3800, "text": "..."},
    "critic":     {"tokens": 4300, "text": "..."}
  }
}
```

**Step 1 — Failing test first** (the test module in Task 3 drives this; for now verify the CLI exists):
```bash
python3 config/claude/metrics/challenge_token_oracle.py score /dev/null
```
Expected now: `No such file`. After Step 2: a clean MISSING/malformed error with exit 2.

**Step 2 — Implement:**
```python
#!/usr/bin/env python3
"""challenge_token_oracle.py — deterministic scorer for the challenge-gate token oracle.

Reads a run-data JSON (per-role token counts + output text from a real
concilium --mode=challenge slice) and computes two v1 verdicts:

  O1  total tokens <= bound              (the decisive one — is "<=15k" real?)
  O3  the three role outputs are DISTINCT (friction, not consensus theater)

O2 ("<=1-page summary") is intentionally NOT scored in v1: the one-pager is the
gate's *distilled* output, not the sum of the three raw role contributions, so
scoring it faithfully requires capturing the orchestrator's distillation step.
Deferred to keep the pilot lean and the measurement valid (no wrong-thing proxy).

No model calls; pure scoring. Exit codes:
  0  all verdicts pass
  1  scored, but one or more verdicts FAIL (a valid, publishable negative result)
  2  MISSING/malformed — a per-role token figure or text is absent; NOT a pass.

Usage:
  challenge_token_oracle.py score <run-data.json> [--bound 15000] [--similarity-cap 0.6]
"""
from __future__ import annotations
import argparse
import json
import re
import sys

ROLES = ("challenger", "advisor", "critic")


def _words(text):
    return [w for w in re.findall(r"[A-Za-z0-9']+", (text or "").lower()) if w]


def _jaccard(a, b):
    sa, sb = set(a), set(b)
    if not sa and not sb:
        return 1.0
    return len(sa & sb) / len(sa | sb)


def score(data, bound, sim_cap):
    """Return (verdict_dict, exit_code). Fail closed to MISSING (2) on any gap."""
    roles = data.get("roles") or {}
    # MISSING: any role absent, or token figure not a number, or text empty.
    for r in ROLES:
        rd = roles.get(r)
        if not isinstance(rd, dict):
            return {"status": "MISSING", "reason": f"role '{r}' absent"}, 2
        if not isinstance(rd.get("tokens"), (int, float)):
            return {"status": "MISSING", "reason": f"role '{r}' token figure absent/non-numeric"}, 2
        if not (rd.get("text") or "").strip():
            return {"status": "MISSING", "reason": f"role '{r}' output text empty"}, 2

    total_tokens = sum(roles[r]["tokens"] for r in ROLES)
    role_words = {r: _words(roles[r]["text"]) for r in ROLES}
    pairs = (("challenger", "advisor"), ("challenger", "critic"), ("advisor", "critic"))
    max_sim = max(_jaccard(role_words[a], role_words[b]) for a, b in pairs)

    o1 = total_tokens <= bound
    o3 = max_sim <= sim_cap
    verdict = {
        "status": "SCORED",
        "model": data.get("model"),
        "bound": bound,
        "total_tokens": total_tokens,
        "O1_token_bound_hold": o1,
        "max_pairwise_similarity": round(max_sim, 4),
        "similarity_cap": sim_cap,
        "O3_roles_distinct": o3,
        "pass": bool(o1 and o3),
    }
    return verdict, (0 if verdict["pass"] else 1)


def main(argv):
    p = argparse.ArgumentParser(prog="challenge_token_oracle.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("score")
    s.add_argument("run_data")
    s.add_argument("--bound", type=int, default=15000)
    s.add_argument("--similarity-cap", type=float, default=0.6)
    args = p.parse_args(argv[1:])
    try:
        with open(args.run_data, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as e:
        print(json.dumps({"status": "MISSING", "reason": f"cannot read run-data: {e}"}))
        return 2
    verdict, code = score(data, args.bound, args.similarity_cap)
    print(json.dumps(verdict, indent=2, sort_keys=True))
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

**Step 3 — Add to the `py_compile` stage** in `run_all.sh` (append `config/claude/metrics/challenge_token_oracle.py` to that line).

**Step 4 — Commit:**
```bash
git add config/claude/metrics/challenge_token_oracle.py config/claude/tests/run_all.sh
git commit -m "feat(metrics): add deterministic challenge-gate token oracle scorer"
```

---

## Task 3: Scorer tests + synthetic fixtures (validate the instrument)

**Files:**
- Create fixtures under `config/claude/tests/fixtures/challenge_oracle/`:
  - `under_bound_distinct.json` — three distinct texts, tokens summing < 15000 → all pass (exit 0).
  - `over_bound.json` — same distinct texts, tokens summing > 15000 → O1 fail (exit 1).
  - `too_similar.json` — three near-identical texts, tokens < 15000 → O3 fail (exit 1).
  - `missing_tokens.json` — one role with `"tokens": null` → MISSING (exit 2). **The honesty test-the-test.**
- Create test module `config/claude/tests/test_challenge_token_oracle.sh`.

**Step 1 — Write the fixtures.** Make the three role texts in `under_bound_distinct.json` genuinely different (distinct vocabulary per role) so `max_pairwise_similarity` is low; in `too_similar.json` make all three nearly identical sentences. Token values are synthetic integers chosen to sit clearly under/over 15000.

**Step 2 — Write the test module** (uses `lib.sh`):
```bash
#!/usr/bin/env bash
# Tests the deterministic challenge-gate token oracle scorer. No model calls.
# Proves the instrument DISCRIMINATES (bench-oracle guardrail) before any real run:
# over-bound -> O1 fails, near-identical -> O3 fails, missing tokens -> MISSING (never a fake pass).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config/claude/tests/lib.sh
. "$DIR/lib.sh"
REPO="$(cd "$DIR/../../.." && pwd)"
OR="$REPO/config/claude/metrics/challenge_token_oracle.py"
FIX="$DIR/fixtures/challenge_oracle"

run() { python3 "$OR" score "$FIX/$1" >/dev/null 2>&1; echo $?; }
field() { python3 "$OR" score "$FIX/$1" 2>/dev/null | python3 -c "import json,sys;print(json.load(sys.stdin).get('$2'))"; }

assert_eq "under-bound+distinct exits 0 (pass)"        "0" "$(run under_bound_distinct.json)"
assert_eq "under-bound+distinct O1 holds"              "True" "$(field under_bound_distinct.json O1_token_bound_hold)"
assert_eq "over-bound exits 1 (scored fail)"           "1" "$(run over_bound.json)"
assert_eq "over-bound O1 fails"                        "False" "$(field over_bound.json O1_token_bound_hold)"
assert_eq "near-identical exits 1 (scored fail)"       "1" "$(run too_similar.json)"
assert_eq "near-identical O3 fails"                    "False" "$(field too_similar.json O3_roles_distinct)"
assert_eq "missing tokens -> MISSING (exit 2, NOT 0)"  "2" "$(run missing_tokens.json)"
assert_eq "missing tokens status is MISSING"           "MISSING" "$(field missing_tokens.json status)"

finish "challenge token oracle tests"
```

**Step 3 — Run + confirm discrimination:** `bash config/claude/tests/test_challenge_token_oracle.sh` → all `ok`. This is the instrument-validation gate: a missing token figure can never be a silent pass, and the over-bound / too-similar cases reden.

**Step 4 — Commit:**
```bash
git add config/claude/tests/fixtures/challenge_oracle/ config/claude/tests/test_challenge_token_oracle.sh
git commit -m "test: validate challenge token oracle scorer (discrimination + MISSING-not-faked)"
```

---

## Task 4: Wire the test module into `run_all.sh`

**Files:** Modify `config/claude/tests/run_all.sh`.

**Step 1 —** Add next to the other `test_*.sh` lines:
```bash
stage "challenge token oracle scorer tests"
bash config/claude/tests/test_challenge_token_oracle.sh || fail=1
```
**Step 2 —** `bash config/claude/tests/run_all.sh` → `ALL CHECKS PASSED`.
**Step 3 —** Commit: `git commit -am "test: wire challenge token oracle into run_all.sh"`.

---

## Task 5: Seeded fixture + runbook (the faithful Part-2 procedure)

**Files (committed; read-only inputs — fine to live in-repo, only dynamic builder *output* must stay out of the tree):**
- `metrics/corpus/challenge-token-oracle/CANVAS.md` — a realistic, neutral confirmed Product Canvas for a plausible feature.
- `metrics/corpus/challenge-token-oracle/IDEA.md` — the raw idea fed alongside the Canvas.
- `metrics/corpus/challenge-token-oracle/RUNBOOK.md` — the exact measurement procedure.

**Step 1 — Author CANVAS.md + IDEA.md.** Pick a mid-complexity feature (e.g. "a notifications digest service"). **Leak check:** the text must NOT mention tokens, brevity, "be concise", "15k", or anything that games the measurement. Record in RUNBOOK that the leak check was done and what was checked.

**Step 2 — Author RUNBOOK.md.** It must specify, step by step:
1. Pin the agent snapshot (a commit/tag) so the measured gate is reproducible.
2. Dispatch the **three real** challenge-mode body prompts — `concilium-skeptic` (Challenger), `concilium-market-realist` (Advisor), `concilium-tech-arbiter` (Critic) — each against `CANVAS.md` + `IDEA.md`, **TEXT-ONLY** ("respond with your challenge as text; do NOT Write/Edit/Bash any files"), honoring the gate's per-round word cap.
3. Force the model via the explicit dispatch `model` parameter (per-agent `model:` frontmatter is NOT honoured). Primary: **Opus** (the model the gate's judgment is validated on). Optional floor model (e.g. Haiku) to expose variance — clearly labelled.
4. Capture each role's reported `subagent_tokens` and its output text into `run-data.json` (a scratch file OUTSIDE the tree, e.g. `/tmp/...`). If a token figure is not reported → record `null` (the scorer will return MISSING; do NOT guess).
5. `python3 config/claude/metrics/challenge_token_oracle.py score /tmp/run-data.json` → capture the verdict.
6. Repeat N=3 per model; report the distribution (min/median/max total_tokens) and the bound-hold count, never a bare "passes".
7. **Emit** (on the `agileteam-improved` branch only): `python3 config/claude/metrics/emit_run.py --corpus-id challenge-token-oracle --mode full --metrics '{"challenge_gate_tokens": <median>}' --gate-outcomes '{"challenge_gate": "<pass|fail|MISSING>"}'`.
8. Write the honest report `metrics/bench-<date>-challenge-token-oracle.md` (tally, verdict, model + n, every limitation/leak/confound, and the explicit reach statement).
9. **Isolation check:** confirm `git status` clean and `run_all.sh` green afterward.

**Step 3 — Commit:**
```bash
git add metrics/corpus/challenge-token-oracle/
git commit -m "docs(metrics): add seeded fixture + runbook for the challenge token oracle"
```

---

## Task 6: Finalize Part 1 (the mergeable PR)

**Step 1 —** `git status` clean; `run_all.sh` → `ALL CHECKS PASSED` (now includes the scorer tests).
**Step 2 —** Open the PR (use `superpowers:finishing-a-development-branch`). Body: Part 1 delivers a *deterministic, CI-validated* token-oracle instrument; the actual measurement (Part 2) is a gated, model-dependent run whose result lands on `agileteam-improved`, not `main`. Link this plan + the design doc. Note Finding #2 is not yet *answered* — only made *answerable* — until Part 2 runs.
**Step 3 — Before merge:** verify the actual `ci` workflow conclusion is `success` (not just `mergeable`).

---

## Part 2 — Execute the measurement (GATED; post-merge; NOT in this PR)

> Costs real model tokens; model-dependent; result → `agileteam-improved`. Run only on explicit human go. Follow `RUNBOOK.md` exactly. Honor every standing constraint above — especially **never fabricate** and **MISSING-not-faked**. The headline output is the honest answer to Finding #2: *does the real challenge gate stay ≤15k, on which model, over how many runs — or does the bound need a real hard-stop?* A "the bound does NOT hold" result is a success of the instrument, and triggers the follow-up "real token hard-stop" ticket noted in the design doc.

---

## Definition of Done (Part 1)

- New: `challenge_token_oracle.py`, `test_challenge_token_oracle.sh`, 4 synthetic fixtures, the seeded `metrics/corpus/challenge-token-oracle/` (CANVAS/IDEA/RUNBOOK), `challenge_gate_tokens` registered in `DIRECTIONS`.
- Scorer is in the `py_compile` gate; test module wired into `run_all.sh`; `ALL CHECKS PASSED`; shellcheck clean.
- Instrument **discrimination proven**: over-bound → O1 fail, near-identical → O3 fail, missing tokens → MISSING (exit 2), under-bound+distinct → pass. The MISSING case is the explicit anti-fabrication guard.
- No `runs.jsonl` created on `main`/feature branch. No agent/command file modified.
- Commit types: `feat(metrics)` for the scorer + metric registration (real capability, changelog-visible), `test:`/`docs(metrics):` for the rest.
