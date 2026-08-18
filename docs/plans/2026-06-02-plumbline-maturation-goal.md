# Plumbline Maturation — `/goal` Implementation Plan

> **For Claude:** REQUIRED SUB-SKILLS: gate this plan with `ultrathink-craftsmanship` + `konfabulations-audit` (Milestone M0) **before any coding**; then drive execution as an autonomous `goal-planner` (`/goal`) run, expanding gated milestones into bite-sized tasks via `superpowers:executing-plans` / `superpowers:subagent-driven-development` as each precondition clears. The Plumbline Watcher may pause; **the user is the final authority and the only release gate.**

**Goal:** Mature Plumbline from "measurable + cleaned" (post-STEP-0–2, PR #15) into a **production-grade, enforcement-backed, empirically-governed** agent framework — every "mandatory/fail-closed" gate gains real runtime teeth, the Kaizen loop becomes oracle-anchored and self-measuring, and the cost levers are adopted **only after their quality-neutrality is proven** on a complete benchmark corpus. Always true to the creed: *evidence over vibes, no laundering, human gates stay.*

**Architecture:** A GOAP (`/goal`) program over a milestone DAG. Enforcement and measurement land **first** (they make every later lever safe and provable); the previously-LOCKED cost levers land **last**, gated on a real baseline. Each milestone is TDD'd, defended by the existing diverse gates, and value-checked by the Watcher. "Done" is the creed's bar — real, wired-in-prod, validated, value-true — not green tests.

**Tech Stack:** Bash hooks + `jq` (Claude Code `settings.json` Stop/PostToolUse hooks), stdlib Python (`config/claude/{metrics,lib}/*.py`), the PRIL CLIs (`config/claude/bin/plumbline-*`), the deterministic bash test harness (`config/claude/tests/*.sh` + `run_all.sh`), the mutation-oracle corpus (`metrics/corpus/**`, `score.py`, `mutate.py`), `git` ground-truth.

---

## ⚠️ Honest scope ledger (read first — this is itself a Reality-Ledger entry on the plan)

- **All token/cost/recall figures here are ESTIMATES** until a real run emits them. STEP 0/1 (shipped) made cost *measurable*; this plan makes it *measured*. Never report an estimate as a measured fact.
- **Buildable now (no external dependency):** M0 (gate), M1 (doc fix), M2 (enforcement hook), M3 (measurement deepening), M5 (evidence-class vocab).
- **Gated / partly non-coding:** M4 (baseline program — needs *real `/agileteam` runs across Opus AND Haiku* to accumulate ≥2 baselines / ≥3 runs per cell; this is a data-collection program with cost and wall-clock, not a pure coding task). M6 (operator UX). 
- **LOCKED until M4 proves quality-neutrality:** M7 (digest broker, risk-tiered G5, tester split, reviewer scoping) and M8's auto-revert teeth. The autonomous loop **must not** adopt a cost lever before its escaped-defect-rate is shown unchanged on the *complete* corpus incl. `T05` — doing so would launder an unproven claim, the exact failure Plumbline exists to prevent.
- **The full "harness-enforced gate state machine" topology** (driver owns the phase FSM) is explicitly **OUT of this goal** — our analysis rated it "weeks not hours" and it must wait for a baseline. M2 ships only the *cheap, real* Stop-hook enforcement; the driver is a noted future epic (Appendix C).
- **Release is a human gate.** The autonomous loop runs the build, the Watcher bounds it, and the **user** releases (truthfully) or directs planned fixes. The loop never self-releases.
- **Recorded near-miss (M0 gate, 2026-06-02):** the independent gate caught that M2 as first drafted would have shipped a hook green-in-test but **inert-in-prod** (`PLUMBLINE_FEATURE` is never set by the runtime). Logged here as evidence the gate works — and as the reason the corrections below are *binding*.

---

## M0 GATE RESULT — binding amendments (independent ultrathink + konfabulations, GO-with-nits)

Verdict: **GO** to start M1, M3, M5 now; **GO for M2 only with C1+C2 folded into its Definition of Done.** These amendments are binding on the referenced milestones:

- **C1 (CRITICAL, M2):** the hook must **not** gate on `PLUMBLINE_FEATURE` (never set by the runtime → permanent no-op). Activation = a ground-truth marker the orchestrator writes: `docs/context/.active-feature` (the confirmed slug). The M2 contract test MUST assert the activation path fires **without the test itself setting any variable** — else M2 cannot claim S1. (Konfab: this claim was `nicht behaupten`; M2 must *make it true*, not assume it.)
- **C2 (CRITICAL, M2):** scope must diff the **whole feature surface** — `merge-base(HEAD,main)..HEAD` ∪ working-tree ∪ staged — not bare `git diff --name-only` (vacuous on a committed tree → fails open).
- **I1 (M2):** route all sub-command stderr to a `mktemp -d` dir with a `trap … EXIT` cleanup; never write `err.*` into the repo CWD.
- **I2 (M2):** the reality-check min-evidence must mirror the feature's **boundary class** (a pure-logic feature must not be blocked for lacking an integration-class ledger it never needed); gate on a `docs/context/.feature-boundary` marker, default to a structural/presence check otherwise. (Mind `plumbline_reality.FORBIDDEN_TOKENS` — `fake-only` is rejected by the token scan, so "presence-only" cannot be expressed as `--min-evidence fake-only`; the implementer TDDs the exact value.)
- **I3 (M4):** M4-Sub-A (corpus authoring) is the **long pole**, re-scoped as its own sized milestone with a hard exit gate: *each planted gap provably flips ≥1 mutation under `mutate.py`*. It is corpus engineering, not doc-filling, and is the hard precondition for M7/M8-revert.
- **I4 (M7):** the promotion rule must be **MDE-bounded honesty**: report "escaped_defect_rate neutral **within MDE X at n=Y**," never a bare "neutral." At `runs_per_cell:3` the bench can detect only gross regressions — a non-significant result may be underpowered, not truly neutral. The user authorizes the unlock.
- **M-1 (M3.1 rationale):** `config_fingerprint` all-`missing` was NOT an emit bug — the historical run was emitted *inside a target project* where Plumbline's component paths don't resolve vs `--repo`. The search-path fix (repo→`config/claude/`→`$CLAUDE_HOME`) is correct; build it for target-repo resolution, not a phantom bug.
- **M-2 (M8.2):** document the canary exit codes; do **not** overload `2` (PRIL uses `2=missing`). Pick non-colliding codes for promote/propose-revert/insufficient-n.
- **Missed items (M2):** add an **uninstall/deregister** path for `plumbline-enforce.sh` and specify its hook **timeout** (it shells out to git + 3 Python CLIs per Stop; `stop-learning-loop` uses `timeout:10`).

Konfab note: only claim #9 (M2 activation) was `nicht behaupten`; all other load-bearing claims verified `belegt`/`ableitbar` against the files. No other claim may enter code as a premise unverified.

---

# PART A — The `/goal` formulation

### Goal state (what "done" means)
Plumbline at a state where **every invariant the docs assert is either runtime-enforced or honestly marked as judgment-only**, the meta-loop **measures its own cost and defect-recall on ground truth**, and any orchestration-cost optimization carries **proof** (not an estimate) that it preserved defect-recall — all without weakening a human gate or laundering a finding.

### Success criteria (machine-checkable where possible)
- **S1 (enforcement):** a real fail-closed hook runs PRIL on `git diff` ground-truth at session-stop for an active feature; its contract test is in `run_all.sh`; the `pretool-plumbline-guard.sh`-not-registered pin still passes (new filename). Non-enforcement is no longer the *only* codified state.
- **S2 (measurement integrity):** `config_fingerprint` resolves to ≥1 non-`missing` component on a normal emit; `process_health.py` scores real emitted keys (no disjoint-key drift); `gate_outcomes` keys reconciled; a `rule-ledger.jsonl` records approved rules with `rule_id`.
- **S3 (baseline):** `metrics/corpus/bench-core-v1/fixtures/` contains every fixture its `manifest.json` specifies (incl. `T05`); `runs.jsonl` holds ≥2 baseline-tagged runs and ≥3 runs/arm for the bench cells (Opus AND Haiku).
- **S4 (vocab unified):** one canonical evidence-class crosswalk; a test asserts the 4-rung prose ladder is a strict coarsening of the 10-value schema enum, and `plumbline_reality.RANKS` is consistent with both; `reality-check` + all grep tests still pass.
- **S5 (operator value):** `/honest-status` rendered at the iteration boundary; every Watcher/gate pause writes a structured machine-readable reason; an interrupted run resumes from the first non-cleared gate (human gates re-validated by artifact hash).
- **S6 (cost levers PROVEN):** each adopted cost lever shows `escaped_defect_rate` unchanged on the complete corpus (incl. `T05`) and a measured token delta in `runs.jsonl` **before** promotion; the router reads RAW traceability columns (not the digest); review-only/docstring diffs default to the FULL path.
- **S7 (kaizen teeth):** `canary_gate.py` exists and, on a synthetic two-run series, exits 2 (propose-revert, never auto-execute) on a past-MDE regression and 0 within noise; every persisted rule carries a `named_metric` + `direction`.
- **S8 (no regression / creed intact):** `run_all.sh` ends `ALL CHECKS PASSED` at every milestone boundary; no human gate removed; no LOCKED item adopted without its proof.

### GOAP world-model (preconditions → effects), milestone DAG
```
M0 ultrathink+konfab gate        pre: plan exists                 eff: GO|REVISE (sets `plan_sound`)
M1 doc 0.5→0.7 propagation       pre: plan_sound                  eff: docs_consistent
M2 enforcement Stop-hook         pre: plan_sound                  eff: enforcement_live (S1)
M3 measurement deepening         pre: plan_sound                  eff: fingerprint_ok, rule_ledger (S2)
M5 evidence-class vocab unify    pre: plan_sound                  eff: vocab_unified (S4)
M4 baseline program              pre: M3 (cost emit) + fixtures   eff: baseline_ready (S3)   ← data+time dependency
M6 operator value (UX)           pre: M2 (pause plumbing reuse)   eff: operator_value (S5)
M7 cost levers (was LOCKED)      pre: M4 baseline_ready + M5      eff: cost_proven (S6)      ← UNLOCKS only here
M8 kaizen teeth                  pre: M3 + M4                     eff: kaizen_teeth (S7)
M9 final QA + truthful release   pre: all above green             eff: released | planned_fixes (human)
```

### The autonomous loop (the `/goal` ruleset — how M1…M8 actually run)
From the user's **GO** (granted only after M0 passes), iterate per `goal-planner`:
1. **Select** the lowest-id milestone whose preconditions are met and is not `done`.
2. **Decompose** it into bite-sized TDD tasks (Part B gives them for M1/M2/M3/M5; M4/M6/M7/M8 are expanded here when unblocked).
3. **Implement** test-first; **review** through the existing diverse gates (independent code-review + the relevant domain gate + security on a diff); **Watcher value-check** (`value-not-green`).
4. **Decide:** all green + value-true → mark milestone `done`, continue. Watcher pause / genuine risk of missing the goal / a **human-gated decision** (product choice, baseline-sufficiency call, anything irreversible) → **escalate to the user** with a factual situation + proposals. Otherwise continue autonomously.
5. **Replan** when a precondition fails (e.g. M7 selected but `baseline_ready` is false → M7 stays blocked, loop returns to accumulating M4 data or escalates that the baseline program needs real runs).
6. **Never** launder: a `*-fake`/not-wired/unproven-lever finding is surfaced verbatim; only the user reclassifies.

### Hard creed constraints on the loop (non-negotiable)
- Human gates stay: requirements/product decisions, baseline-sufficiency judgment, persistent global-config writes, and **release** are user-gated.
- LOCKED levers (M7/M8-revert) cannot be adopted before M4 `baseline_ready`; an estimate is never a promotion criterion.
- Every milestone boundary: `run_all.sh` green, no invariant weakened, evidence (test/log/oracle) attached to each "done".

---

# PART B — Milestones as tasks

## M0 — Pre-coding gate: ultrathink-craftsmanship + konfabulations-audit (the user's explicit gate)

**No code.** Before any implementation:

**Step 1:** Run Skill `ultrathink-craftsmanship` (full mode, **once**) over THIS plan: stress-test for bias, hidden coupling, weak evidence, sequencing errors, and craftsmanship risk. Focus especially on: is the enforcement-before-cost ordering right? Is anything marked "buildable now" secretly gated? Does M2's hook risk breaking a session?

**Step 2:** Couple to Skill `konfabulations-audit`: classify every external/empirical claim in this plan (`belegt | ableitbar | ungeprüft | nicht behaupten`). Any `ungeprüft`/`nicht behaupten` claim must NOT become a build premise — downgrade or verify it first.

**Step 3:** Produce a GO / REVISE verdict. On REVISE: apply the corrections to this plan (one pass), show the diff, re-confirm with the user. **GO requires explicit user confirmation** — the loop does not self-grant it.

**Exit:** `plan_sound = true` only on user GO.

---

## M1 — Propagate the `0.5→0.7` renumber to companion docs (buildable now)

**Why:** PR #15 renumbered the spec-sanity gate in the command; three companion docs still say `Phase 0.5`. Cosmetic, but a professional framework keeps its docs coherent.

**Files:**
- Modify: `docs/agileteam-spec-v3.md` (the spec-sanity gate header + the table row), `docs/agileteam-governance.md` (the `Phase 0.5 / Lauf` mention), `docs/templates/true-line-gate-check.template.md` (the `before Phase 0.5` mention).

**Step 1 — Discover exact occurrences** (line numbers shift):
```bash
grep -rn "Phase 0\.5\|Phase 0,5\|0\.5" docs/agileteam-spec-v3.md docs/agileteam-governance.md docs/templates/true-line-gate-check.template.md
```
**Step 2 — Decide per occurrence (judgment, not blind sed):** spec-v3 has **no PRIL gate**, so within spec-v3 "spec-sanity = 0.5" is internally consistent. The correct fix is a one-line **note** at the spec-v3 phase table — `> In the command pipeline, PRIL Context (0.5) and Scope Guard (0.6) precede spec-sanity, which runs at 0.7.` — rather than a misleading renumber that would create a 0.7 with no 0.5/0.6 in that doc. For governance/template, align the bare number to `0.7` only where it cross-references the *command's* pipeline.
**Step 3 — Verify no test pins these:** `grep -rn "Phase 0.5" config/claude/tests/` (only `test_runtime_integrity_layer.sh` pins the literal `"PRIL Context Integrity gate"`, untouched).
**Step 4 — `bash config/claude/tests/run_all.sh`** → `ALL CHECKS PASSED`.
**Step 5 — Commit:** `docs: reconcile spec-sanity phase number with command pipeline (0.7)` (stage only the three docs).

---

## M2 — Real fail-closed enforcement hook on git ground-truth (buildable now) — **the creed centerpiece**

**Why (verified):** today `.claude/settings.json` registers only SessionStart + the sentinel Stop learning-loop; the 4 PRIL CLIs are never invoked by the runtime; `pretool-plumbline-guard.sh` is deliberately inert and `test_runtime_integrity_layer.sh` *codifies* that it stays unregistered. This milestone gives "fail-closed" real teeth via a **new-filename** Stop hook (keeping that pin valid), reading `git diff` (not an agent-typed list).

**Files:**
- Create: `config/claude/hooks/plumbline-enforce.sh`  (NEW name — must not contain the string `pretool-plumbline-guard.sh`)
- Create: `config/claude/tests/test_pril_enforce_hook.sh`
- Modify: `config/claude/tests/run_all.sh` (wire the test)
- Modify: `config/claude/install.sh` (register the new hook, append-only, own dedup key)

### Task M2.1 — failing contract test
**Step 1 — Write `config/claude/tests/test_pril_enforce_hook.sh`** asserting:
1. **No-op off:** with no sentinel/`PLUMBLINE_FEATURE`, the hook prints nothing and exits 0.
2. **Blocks on real out-of-scope diff:** in a temp git repo with an active feature + a planted out-of-scope change, the hook emits a single JSON object with `.decision=="block"` and a reason naming the failing PRIL check.
3. **Reads git, not the agent:** the hook calls `git diff --name-only` (assert by planting a changed file that is NOT in any agent-authored list and confirming it is still caught).
4. **Honors `stop_hook_active`:** with `{"stop_hook_active":true}` on stdin it exits 0, empty stdout (no infinite loop).
5. **Never exits non-zero:** even on a malformed/garbage stdin it exits 0 (degrade to block-with-reason, never crash the session).
6. **Bash syntax valid** (`bash -n`).
**Step 2 — Wire into `run_all.sh`** after the `runtime integrity layer tests` stage:
```bash
stage "PRIL enforce hook tests"
bash config/claude/tests/test_pril_enforce_hook.sh || fail=1
```
**Step 3 — Run → FAILS** (hook does not exist). **Commit red.**

### Task M2.2 — implement the hook (make M2.1 green)
**Step 1 — Write `config/claude/hooks/plumbline-enforce.sh`** following the `stop-learning-loop.sh` safety contract (never exit non-zero; honor `stop_hook_active`; sentinel-gated so normal sessions are untouched). Skeleton:
```bash
#!/usr/bin/env bash
# Fail-closed PRIL enforcement Stop hook (git ground-truth). Sentinel-gated:
# active only for an /agileteam feature run (PLUMBLINE_FEATURE set + its canvas
# exists). NEW filename so test_runtime_integrity_layer.sh's "pretool guard not
# registered" pin stays valid. Never exits non-zero; honors stop_hook_active.
input="$(cat 2>/dev/null)"
active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)"
[ "$active" = "true" ] && exit 0
: "${CLAUDE_PROJECT_DIR:=$PWD}"
repo="$CLAUDE_PROJECT_DIR"; bin="$repo/config/claude/bin"
# C1 ACTIVATION — ground-truth marker the orchestrator writes (NOT an env var the
# runtime never sets). Normal sessions have no marker -> hook is a no-op.
marker="$repo/docs/context/.active-feature"
[ -f "$marker" ] || exit 0
feat="$(tr -d ' \t\n\r' < "$marker" 2>/dev/null)"
[ -n "$feat" ] && [ -f "$repo/docs/canvas/$feat.canvas.md" ] || exit 0
errd="$(mktemp -d)"; trap 'rm -rf "$errd"' EXIT          # I1 — stderr to tmp, never repo CWD
fails=""
# C2 SCOPE — full feature surface, not bare `git diff` (vacuous on a committed tree):
base="$(git -C "$repo" merge-base HEAD main 2>/dev/null || echo HEAD)"
{ git -C "$repo" diff --name-only "$base"...HEAD; git -C "$repo" diff --name-only; \
  git -C "$repo" diff --name-only --cached; } 2>/dev/null | sort -u > "$errd/changed"
"$bin/plumbline-scope-check" --repo "$repo" --feature "$feat" --changed-files "$errd/changed" >/dev/null 2>"$errd/scope" || fails="$fails scope"
"$bin/plumbline-context-check" --repo "$repo" --feature "$feat" >/dev/null 2>"$errd/ctx" || fails="$fails context"
# I2 — min-evidence mirrors the feature's boundary class (pure-logic must not be blocked):
min="integration"; [ -f "$repo/docs/context/.feature-boundary" ] || min="$DEFAULT_PRESENCE_CHECK"  # see binding amendment I2
"$bin/plumbline-reality-check" --repo "$repo" --feature "$feat" --min-evidence "$min" >/dev/null 2>"$errd/real" || fails="$fails reality"
if [ -n "$fails" ]; then
  reason="PRIL enforcement failed:$fails. Fix or escalate to the user; do not finish with a failing gate."
  jq -cn --arg r "$reason" '{decision:"block", reason:$r}' 2>/dev/null \
    || printf '{"decision":"block","reason":"PRIL enforcement failed:%s"}' "$fails"
fi
exit 0
```
(Refine error-file handling to temp paths; keep it shellcheck-clean: quote all expansions, `set` omitted intentionally so a sub-command failure never aborts the hook.)
**Step 2 — Run the contract test → all pass.** **Step 3 — Full suite green** (esp. the still-passing `optional pretool guard is not activated` pin — different filename). **Commit green.**

### Task M2.3 — register it (append-only, own dedup key)
**Step 1 — In `config/claude/install.sh`**, add a registration mirroring the stop-learning-loop function but dedup-keyed on `plumbline-enforce\.sh`, appended to `.hooks.Stop` (and optionally a PostToolUse matcher `Edit|Write|MultiEdit` as a later refinement). Do **not** disturb the existing stop-learning-loop registration (the `test_web_bootstrap.sh` exactly-once pin).
**Step 2 — Extend `test_pril_enforce_hook.sh`** (or `test_web_bootstrap.sh`) to assert: after install, the new hook is registered exactly once AND the pretool-guard string is still absent AND stop-learning-loop is still registered exactly once.
**Step 3 — Suite green. Commit.**

> **Watcher value-check (M2):** does this serve real customer value? Yes — it converts "fail-closed" from prose addressed to a cooperative LLM into a runtime property, directly serving the creed ("prove it is done"). Additive; no human gate touched.

---

## M3 — Measurement deepening (buildable now)

**Why (verified):** `config_fingerprint` was all-`missing` in the only real run (path resolution); approved rules carry no provenance; `gate_outcomes` keys drifted. Close these so the Kaizen loop's attribution is real.

### Task M3.1 — resolve `config_fingerprint` paths (K3)
**Files:** Modify `config/claude/metrics/emit_run.py` (`sha256_file`/`fingerprint`/`COMPONENTS`).
- **Test first** (`config/claude/tests/test_metrics_contract.sh` — extend): a normal `--dry-run` emit produces a `config_fingerprint` with **≥1 non-`missing`** component, and a missing component is emitted as `missing:<relpath>` (not bare `missing`).
- **Implement:** resolve each COMPONENT against an ordered search-path (repo root → `config/claude/` → `$CLAUDE_HOME`); emit `missing:<relpath>` on a true miss. Add `--fail-on-missing-fingerprint` (default off; intended ON for `agileteam-bench`).
- Suite green. Commit.

### Task M3.2 — rule-ledger provenance scaffold (K5)
**Files:** Create `config/claude/metrics/rule_ledger.py` + `bin/plumbline-rule-ledger`; extend `emit_run.py` with `--active-rules`.
- **Test first:** appending a rule writes `{rule_id, approved_at(from arg), level, target_file, named_metric, direction}` to `metrics/rule-ledger.jsonl`; a record with `--active-rules` round-trips. (No `Date.now()` in scripts — pass `approved_at` in.)
- **Implement** minimally; **write only on explicit input** (mirrors the human y/n gate — no new silent-write path).
- Suite green. Commit.

### Task M3.3 — reconcile `gate_outcomes` keys
- Document the canonical gate-outcome keys (`gateA_verification` … `gateD_judgment`, `phase0_5_spec_sanity`) in `emit_run.py` help + governance; optionally validate them. No behavior change beyond validation. Suite green. Commit.

---

## M5 — Unify the evidence-class vocabulary (buildable now — the critic's #1 missed lever)

**Why (verified):** two load-bearing vocabularies — the command's 4-rung prose ladder (`unit-fake→integration-fake→real-boundary-smoke→production-verified`) and the 10-value schema enum (`reality-ledger-evidence.schema.json`, ranked 0–5 in `plumbline_reality.RANKS`). Every routing/tiering lever (M7) keys on this; an un-reconciled enum is "a classifier built on sand."

**Files:** Create `docs/reality-evidence-crosswalk.md`; create `config/claude/tests/test_evidence_vocab.sh`; (no behavior change to `plumbline_reality.py` unless an inconsistency is found).
- **Test first (`test_evidence_vocab.sh`):** assert the 4-rung prose ladder is a **strict coarsening** of the schema enum — every prose rung maps to exactly one schema rank, ranks are monotonic, and `plumbline_reality.RANKS` agrees with both (parse the schema JSON + the RANKS dict in Python; fail if any prose rung has no schema home or the order disagrees). Assert the crosswalk doc lists all 10 schema values with their rank + prose-equivalent (or `—` for the extra granularity values).
- **Implement:** author `docs/reality-evidence-crosswalk.md` (the canonical table); if the test exposes a real RANKS inconsistency, fix `plumbline_reality.py` (and re-run its fixtures). Wire `test_evidence_vocab.sh` into `run_all.sh`.
- Suite green. Commit.

---

## M4 — Baseline program (GATED: data + time; partly non-coding) — the gate for M7

**Why:** every cost lever's "quality-neutral" claim is unprovable at n=1 / 2-of-N fixtures. This milestone makes proof possible. **It is not pure coding** — it requires real runs.

**Sub-A (coding) — complete the corpus. → VERIFIED ALREADY COMPLETE (2026-06-02).**
Ground-truth check at execution time overturned this milestone's premise: `bench-core-v1` is already complete. All 12 tasks (T01–T12) are fully defined in `metrics/corpus/bench-core-v1/tasks.md` and scored in `rubric.md`; the manifest's `fixtures: []` means a **prompt-only task with no fixture file** — only T04/T11 need a vendor stub, and **both exist** (`fixtures/T04/vendor/ticketing_sdk.py`, `fixtures/T11/vendor/sms_sdk.py`); T05/T09 carry their diff inline in `tasks.md`. The "only T04,T11 exist / 8 fixtures missing / long pole" framing (here, in amendment I3, and in the M0 gate) was a **misreading of `fixtures/` directories vs the actual task+rubric definitions** — a propagated unverified premise, surfaced verbatim per the creed, not laundered into fabricated work. Also: `mutate.py`/`score.py` live in `pipe-core-v1` (mutation-scored), **NOT** `bench-core-v1`, which is **blind-judge-scored** (manifest: "an independent BLIND judge scores the arm output against rubric.md") — so amendment I3's "mutation provably takes" exit gate is **inapplicable to this corpus**. **Net: there is no Sub-A authoring work.** M4 collapses entirely to Sub-B (the sweep).

**Sub-B (data — ESCALATE) — baseline sweep.** Run `/agileteam-bench` (or scripted emits) to accumulate **≥2 baseline-tagged runs** and **≥3 runs/arm**, across **Opus AND Haiku** (the measured capability split). This costs tokens + wall-clock and needs a real target feature. **The loop ESCALATES here:** present the user the exact run matrix + cost estimate and let them authorize/parameterize it. Do not fabricate baseline data.

**Exit:** `baseline_ready = true` only when S3 holds. Until then M7 stays blocked.

---

## M6 — Operator value (GATED on M2 plumbing; expand when reached)

Design specs (expand to bite-sized tasks in-loop):
- **M6.1 Wire `/honest-status` at the G7 iteration boundary** of `agileteam.md` (show-only-when-RED): per-REQ evidence-class + not-wired items from the matrix. Additive; reuse existing columns.
- **M6.2 Structured pause-reason** on every non-pass Watcher/gate verdict (extend `true-line-gate-check.template.md` with `{failed-check, artifact:line, required user decision}` — additive fields, keep the pinned `PRIL check output:` etc.).
- **M6.3 Resumable run-ledger** (`docs/context/run-ledger.md`, owned by `context-keeper`): record per-gate CLEARED/PENDING/PAUSED + artifact hash; on re-invocation resume at the first non-cleared gate; **human gates re-validated by hash** (changed artifact → re-ask). Fail-closed to Phase-0 on missing/corrupt/partial ledger; all-observed-CLEARED is not completion unless an explicit `__RUN_COMPLETE__` marker was recorded after the final gate cleared.
Each: test-first where a check is executable (ledger round-trip; template slot presence), suite green, atomic commit, Watcher value-check.

---

## M7 — Cost levers (LOCKED until M4 `baseline_ready`) — adopt only with proof

Design specs; **do not start until S3 holds.** When unlocked, each lever is its own TDD task **plus a mandatory bench proof** before promotion:
- **M7.1 `context-keeper` value-digest broker** — hash-bound `docs/context/value-digest.md`; gates read it; **the risk-router reads RAW traceability columns, NOT the digest** (separate provenance — the verified correlated-failure mitigation). Proof: a mutation that silently alters vision/canvas must still flip the dependent gate RED (hash mismatch → forced re-read).
- **M7.2 Risk-tiered G5 cadence** — full chain on boundary increments, lean on logic; **hardened predicate: any review-only/docstring/contract diff defaults to FULL regardless of I/O surface** (the `T05` counterexample); Opus-or-disclose for model-tiered dispatch. Proof: `escaped_defect_rate` unchanged on the complete corpus incl. `T05`; token delta measured.
- **M7.3 Tester split** (heavy `test-designer` once / lean `qa-runner` per increment) — add the runner as a NEW component (do NOT rename `core/tester.md` → preserves the fingerprint spine). Proof: recall held on `bench-core-v1` test-plan corpus.
- **M7.4 Reviewer scoped hunk-diff** via `plumbline-scope-check`. Proof: non-wiring recall within noise on the reviewer-narrowing corpus.
**Promotion rule:** a lever is `done` only with its bench proof attached to `runs.jsonl`. No estimate promotes a lever.

---

## M8 — Kaizen teeth (GATED on M3 + M4)

- **M8.1** Extend the rule-ledger (M3.2) so `process_health.py` can segment a metric by `rule_id` (with vs without a rule).
- **M8.2 `config/claude/metrics/canary_gate.py`** — given a `rule_id` + `runs.jsonl`, compute the named metric on the canary corpus vs baseline; **exit 0 promote / 2 propose-revert (never auto-execute) / 3 insufficient-n.** Test-first on a **synthetic two-run series** (the only thing falsifiable before real data): past-MDE regression → exit 2 + names the rule; within-noise → exit 0; n<floor → exit 3. Commit.
- **M8.3** Wire `canary_gate.py` into `agileteam-bench` as the promote-to-stable gate. Human-gated revert (propose only).

---

## M9 — Final thorough QA + truthful release (human gate)

**Step 1 — Full deterministic QA:** `run_all.sh` green; every new CLI/hook has a contract test in the suite; `shellcheck` clean (CI).
**Step 2 — Reality QA (the creed):** render `/honest-status` over the whole program — separate *looks-done* from *is-done* per success criterion S1–S8; list any feature still `*-fake`/not-wired; list every estimate that is still an estimate (no measured proof). **No laundering** — surface RED verbatim.
**Step 3 — Independent judgment:** `product-owner` + `ultrathink-craftsmanship` (once): did we build the right thing; any bias; any claim that entered code/docs unverified (`konfabulations-audit`).
**Step 4 — Truthful release decision (USER):** present S1–S8 status + the honest reality ledger. The **user** releases (e.g. merge/tag) **or** directs planned fixes. If any S-criterion is RED or any cost lever is unproven, the honest outcome is **"planned fixes,"** not release. The loop never self-certifies "done."

---

# PART C — Execution & safety summary

- **Order is law:** M0 → {M1, M2, M3, M5} → M4 → {M6} → M7 → M8 → M9. M7/M8-revert are blocked until M4.
- **Per milestone:** TDD, diverse-gate review, Watcher value-check, `run_all.sh` green, atomic commits, diffs shown before shared-config writes.
- **Escalate (don't guess):** product decisions, M4 baseline authorization, any irreversible/global-config action, and release.
- **Branch:** run on a feature branch / worktree off `main` (never commit to `main`); finish via `superpowers:finishing-a-development-branch`.

## Appendix A — Mapping to the analysis
M2←STEP3/adherence-P1; M3←kaizen-K3/K5; M5←critic missed-lever #1; M4←critic missed-lever #2 (baseline) + STEP5; M6←user-value P2/P3/P4; M7←cost-altitude + team-topology (hardened); M8←kaizen-K4/K5.

## Appendix B — Locked / explicitly out of scope
Full "harness-enforced gate state-machine" driver topology (weeks; needs baseline). Foreign-model council cognitive-diversity (MCP wiring). Any model up/down-grade not via the orchestrator's explicit per-dispatch parameter.

## Appendix C — Future epic (not this goal)
`config/claude/bin/plumbline-run` deterministic phase-FSM driver (the LLM as a bounded per-phase worker). Revisit after M4 baseline proves the prose protocol's quality, so the driver's own "does it regress true-line quality?" question is answerable.
