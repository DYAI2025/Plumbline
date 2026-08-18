# /agileteam STEP 0–2: Measurement Contract + Cost Emission + Pure-Win Cleanups — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Work strictly TDD-first; show every diff in the terminal before applying; commit atomically; `bash config/claude/tests/run_all.sh` MUST end with `ALL CHECKS PASSED` after every task.

**Goal:** Make the `/agileteam` meta-loop *measurable* (a versioned, fail-closed metrics contract + real cost-per-validated-REQ emission) and remove dead weight (unused reviewer agent, dead claude-flow MCP boilerplate, undefined loop caps, a duplicate phase header, an oversized skill), without weakening any Plumbline invariant or breaking any of the ~200 grep-pinned test assertions.

**Architecture:** Three isolated, atomic waves. STEP 0 adds an emit-side allowlist that *imports* `process_health.DIRECTIONS` as the single source of truth (so the emit/analyse key-drift this fixes can never recur). STEP 1 adds `--tokens-total`/`--reqs-accepted` → `cost_per_req` computed as **cost per VALIDATED req** (denominator = REQs at/above the run's min-evidence, not green-but-fake). STEP 2 is six surgical cleanups, each guarded by the full test suite.

**Tech Stack:** Python 3 (stdlib only — `argparse`, `json`, `hashlib`), Bash test harness (`config/claude/tests/*.sh`, `set -uo pipefail`), `jq`, `shellcheck`. No third-party deps.

---

## ⚠️ Standing constraints for the whole wave (read before Task 0)

- **All token/cost figures are ESTIMATES** until STEP 0+1 make them measurable. State this explicitly in any status output. Do not present any reduction as a measured fact in this wave.
- **LOCKED — do NOT implement in this wave:** STEP 3 (Stop-hook enforcement) is **background design only** (see appendix); risk-router, digest-broker, and model-tiering are **fully locked** until the baseline program (incl. the 10 missing `bench-core-v1` fixtures, e.g. `T05`) lands.
- **No silent writes to shared config.** Every edit to `config/claude/commands/agileteam.md`, `config/claude/skills/**`, `core/**`, `code-reviewer.md`, or `config/claude/metrics/**` must be shown as a diff and approved before commit.
- **Atomic commits.** One logical change per commit. Never commit to `main`.
- **Green gate.** `bash config/claude/tests/run_all.sh` ends with `ALL CHECKS PASSED` before each commit. `shellcheck` runs over `config/claude/tests/*.sh` in that suite, so every new/edited `.sh` must be shellcheck-clean.

---

## Task 0: Isolate the work (branch/worktree)

**Files:** none (git only).

**Step 1 — Confirm we are not on a shared default branch and create an isolated branch.**

Run:
```bash
git -C "$REPO" status --short && git -C "$REPO" rev-parse --abbrev-ref HEAD
```
Expected: clean tree on `main`.

**Step 2 — Create the feature branch (ask the user first; do not auto-switch silently).**

```bash
git checkout -b feat/agileteam-step0-2-measurement
```
(Or a dedicated worktree per @superpowers:using-git-worktrees if the user prefers parallel isolation.)

**Step 3 — Establish the green baseline before any change.**

Run: `bash config/claude/tests/run_all.sh`
Expected: `ALL CHECKS PASSED` (shellcheck may be `skipped` locally — that is fine; CI runs it).

---

# STEP 0 — Versioned, fail-closed metrics contract

**Why:** Verified drift — the one real run in `metrics/runs.jsonl` emits metric keys (`tasks`, `devreview_loops_total`, `qa_returns`, …) that are **disjoint** from the keys `process_health.py` `DIRECTIONS` scores, so the SPC/drift detector scores nothing real. Fix: a fail-closed allowlist on the emit side, sourced from `DIRECTIONS` itself so it can never re-drift, plus a `metrics_schema_version` stamp.

**Design decision (record shape):**
- `metrics` = **only** allowlisted, scored keys (must be in `DIRECTIONS`). Unknown key → non-zero exit (fail closed).
- New `raw` object = free-form operational diagnostics (`tasks`, `devreview_loops_total`, …) — recorded for audit, **not** scored, **not** allowlisted. This keeps useful counts without polluting the scored set.
- New top-level `metrics_schema_version` integer.
- Historical `runs.jsonl` line is **not migrated** (it is a pre-contract audit record; `process_health.py` still reads it). The validator only gates new writes.

### Task 0.1: Failing test for the metrics contract

**Files:**
- Create: `config/claude/tests/test_metrics_contract.sh`

**Step 1 — Write the failing test.**

```bash
#!/usr/bin/env bash
#
# Contract test for the versioned, fail-closed metrics emitter (STEP 0/1).
# Round-trips emit_run.py --dry-run and asserts: schema version present,
# allowlisted keys pass, non-allowlisted keys fail closed, cost is per-validated-req.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"
EMIT="$REPO_DIR/config/claude/metrics/emit_run.py"

pass=0; fail=0
ok()   { printf '  ok   %s\n' "$1"; pass=$((pass+1)); }
bad()  { printf '  FAIL %s\n' "$1"; fail=$((fail+1)); }

echo "test_metrics_contract"

# 1) allowlisted metric round-trips and carries the schema version
out="$(python3 "$EMIT" --dry-run --metrics '{"first_pass":0.9}' 2>/dev/null)"
rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | python3 -c '
import json,sys
r=json.load(sys.stdin)
assert r.get("metrics_schema_version")==1, "schema version"
assert r["metrics"]["first_pass"]==0.9, "metric round-trip"
' 2>/dev/null; then ok "allowlisted metric round-trips with schema_version=1"; else bad "allowlisted metric round-trips with schema_version=1"; fi

# 2) NON-allowlisted metric key fails closed (the verified drift: 'tasks' is not scored)
out="$(python3 "$EMIT" --dry-run --metrics '{"tasks":6}' 2>&1)"; rc=$?
if [ "$rc" -ne 0 ] && printf '%s' "$out" | grep -q "tasks"; then
  ok "non-allowlisted metric key fails closed and names the key"
else bad "non-allowlisted metric key fails closed and names the key"; fi

# 3) operational counts go to raw, never rejected
out="$(python3 "$EMIT" --dry-run --metrics '{"mutation":0.8}' --raw '{"tasks":6,"devreview_loops_total":8}' 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | python3 -c '
import json,sys
r=json.load(sys.stdin)
assert r["raw"]["tasks"]==6 and r["raw"]["devreview_loops_total"]==8
assert "tasks" not in r["metrics"]
' 2>/dev/null; then ok "operational counts accepted under raw, kept out of metrics"; else bad "operational counts accepted under raw, kept out of metrics"; fi

# 4) cost is per-VALIDATED-req: cost_per_req = tokens_total / reqs_accepted
out="$(python3 "$EMIT" --dry-run --metrics '{}' --tokens-total 120000 --reqs-accepted 4 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | python3 -c '
import json,sys
r=json.load(sys.stdin)
assert r["metrics"]["cost_per_req"]==30000.0, r["metrics"].get("cost_per_req")
assert r["raw"]["tokens_total"]==120000 and r["raw"]["reqs_accepted"]==4
' 2>/dev/null; then ok "cost_per_req = tokens/validated_reqs with provenance in raw"; else bad "cost_per_req = tokens/validated_reqs with provenance in raw"; fi

# 5) zero validated reqs does not divide by zero (denominator floored at 1)
out="$(python3 "$EMIT" --dry-run --metrics '{}' --tokens-total 1000 --reqs-accepted 0 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ] && printf '%s' "$out" | python3 -c '
import json,sys
assert json.load(sys.stdin)["metrics"]["cost_per_req"]==1000.0
' 2>/dev/null; then ok "zero validated reqs is div-by-zero safe"; else bad "zero validated reqs is div-by-zero safe"; fi

# 6) the allowlist IS process_health.DIRECTIONS (no drift): cost_per_req is scored, so it passes
out="$(python3 "$EMIT" --dry-run --metrics '{"cost_per_req":1234.5}' 2>/dev/null)"; rc=$?
if [ "$rc" -eq 0 ]; then ok "scored key cost_per_req is allowlisted (allowlist==DIRECTIONS)"; else bad "scored key cost_per_req is allowlisted (allowlist==DIRECTIONS)"; fi

printf '\ntest_metrics_contract: %d run, %d failed\n' "$((pass+fail))" "$fail"
[ "$fail" -eq 0 ]
```

**Step 2 — Run it; verify it FAILS (emitter has none of these features yet).**

Run: `bash config/claude/tests/test_metrics_contract.sh`
Expected: FAIL — assertions 1–6 fail (no `metrics_schema_version`, no allowlist, no `--raw`/`--tokens-total`/`--reqs-accepted`).

**Step 3 — Wire the test into the suite.**

Edit `config/claude/tests/run_all.sh`, immediately after the `metrics scripts compile` stage (after the `py_compile` block ending at line ~74), insert:
```bash
stage "metrics contract round-trip"
bash config/claude/tests/test_metrics_contract.sh || fail=1
```

**Step 4 — Confirm the suite now goes red on this stage (proves it is wired).**

Run: `bash config/claude/tests/run_all.sh`
Expected: ends `CHECKS FAILED`, with `test_metrics_contract` failing.

**Step 5 — Commit the failing test (red).**
```bash
git add config/claude/tests/test_metrics_contract.sh config/claude/tests/run_all.sh
git commit -m "test(metrics): add failing contract test for versioned fail-closed emitter"
```

### Task 0.2: Implement the allowlist + schema version (make 0.1 green, minus cost)

**Files:**
- Modify: `config/claude/metrics/emit_run.py`

**Step 1 — Add the allowlist + schema constant after the imports (after `import uuid`, line 37).**
```python

# Single source of truth for which metrics are SCORED. Importing DIRECTIONS from
# process_health (same directory) makes the emit-side allowlist incapable of
# drifting from the analyse-side scorer — the exact drift this contract closes.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from process_health import DIRECTIONS  # noqa: E402

ALLOWED_METRICS = frozenset(DIRECTIONS)
METRICS_SCHEMA_VERSION = 1
```

**Step 2 — Add a fail-closed validator (after `load_metrics`, ~line 98).**
```python
def validate_metrics(metrics):
    """Fail closed on any metric key not in the scored allowlist (DIRECTIONS)."""
    unknown = sorted(k for k in metrics if k not in ALLOWED_METRICS)
    if unknown:
        raise ValueError(
            "non-allowlisted metric key(s): " + ", ".join(unknown)
            + "\nallowed (process_health.DIRECTIONS): "
            + ", ".join(sorted(ALLOWED_METRICS))
            + "\nput operational counts under --raw instead."
        )
```

**Step 3 — Add `--raw` to `parse_args` (after `--metrics-file`, line 104).**
```python
    p.add_argument("--raw", default="{}",
                   help="free-form diagnostic counts (recorded, NOT scored/allowlisted)")
```

**Step 4 — Wire validation + schema version + raw into `main` (replace the `record = {...}` block, lines 124-135).**
```python
    metrics = load_metrics(args)
    raw = json.loads(args.raw)
    try:
        validate_metrics(metrics)
    except ValueError as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    record = {
        "run_id": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
                  + "-" + uuid.uuid4().hex[:6],
        "metrics_schema_version": METRICS_SCHEMA_VERSION,
        "corpus_id": args.corpus_id,
        "mode": args.mode,
        "baseline": bool(args.baseline),
        "process_branch": f"{branch}@{short}",
        "config_fingerprint": fingerprint(repo),
        "metrics": metrics,
        "raw": raw,
        "gate_outcomes": json.loads(args.gate_outcomes),
        "human_overrides": args.human_overrides,
    }
```

**Step 5 — Run the contract test; assertions 1, 2, 3, 6 PASS; 4 and 5 (cost) still FAIL.**

Run: `bash config/claude/tests/test_metrics_contract.sh`
Expected: 4 ok, 2 fail (the two cost assertions) — cost lands in Task 1.1.

**Step 6 — Verify nothing else broke (py_compile + whole suite except the cost asserts).**

Run: `python3 -m py_compile config/claude/metrics/emit_run.py` → no output (OK).
(The full suite still red ONLY on the two cost asserts — expected; do not commit until STEP 1 finishes the green.)

---

# STEP 1 — Real cost emission (cost per VALIDATED req)

### Task 1.1: Implement cost emission (makes the contract test fully green)

**Files:**
- Modify: `config/claude/metrics/emit_run.py`

**Step 1 — Add the cost helper (after `validate_metrics`).**
```python
def apply_cost(metrics, raw, tokens_total, reqs_accepted):
    """Emit cost-per-VALIDATED-req, not per green req.

    The caller passes reqs_accepted = the count of REQs whose evidence_class is
    at/above the run's min-evidence (the Reality-Ledger validated count) — NOT
    the count of green tests. tokens_total is the run's output-token total.
    Denominator floored at 1 so a zero-validated run cannot divide by zero.
    """
    if tokens_total is None:
        return
    reqs = reqs_accepted if reqs_accepted is not None else 0
    metrics["cost_per_req"] = tokens_total / max(reqs, 1)
    raw["tokens_total"] = tokens_total
    raw["reqs_accepted"] = reqs
```

**Step 2 — Add the cost args to `parse_args` (after `--raw`).**
```python
    p.add_argument("--tokens-total", type=int, default=None,
                   help="total output tokens for the run (numerator of cost_per_req)")
    p.add_argument("--reqs-accepted", type=int, default=None,
                   help="count of VALIDATED REQs (evidence_class >= min-evidence) — the denominator")
```

**Step 3 — Call `apply_cost` in `main` BEFORE `validate_metrics` (so the injected `cost_per_req` is validated like any metric).**

In the block from Step 0.2/Step 4, insert between `raw = json.loads(args.raw)` and the `try:`:
```python
    apply_cost(metrics, raw, args.tokens_total, args.reqs_accepted)
```

**Step 4 — Run the contract test; ALL 6 assertions PASS.**

Run: `bash config/claude/tests/test_metrics_contract.sh`
Expected: `6 run, 0 failed`.

**Step 5 — Run the FULL suite; must be unconditionally green.**

Run: `bash config/claude/tests/run_all.sh`
Expected: `ALL CHECKS PASSED`.

**Step 6 — Commit (green) — STEP 0 + STEP 1 land together as the measurement contract.**
```bash
git add config/claude/metrics/emit_run.py
git commit -m "feat(metrics): versioned fail-closed contract + cost-per-validated-req emission

- allowlist sourced from process_health.DIRECTIONS (no emit/analyse drift)
- metrics_schema_version stamp; operational counts move to raw
- --tokens-total/--reqs-accepted -> cost_per_req (validated denominator, div-0 safe)"
```

### Task 1.2: Point the orchestrator's METRICS-EMITTER at the validated denominator (shared-config edit — preview + approve)

**Files:**
- Modify: `config/claude/commands/agileteam.md` (Phase 3 METRICS-EMITTER, ~lines 579-581)

**Step 1 — Show the current text, then propose the additive edit (no pinned literal removed).**

Current (line ~579):
> - **METRICS-EMITTER:** write a run record (config_fingerprint + metrics + gate outcomes) to `metrics/runs.jsonl` (governance §2). Then **arm the learning loop**: `touch ~/.claude/.agileteam-reflection-pending`.

Proposed (append two sentences; keep the existing sentence verbatim):
> Pass **scored** metrics via `--metrics` (allowlisted to `process_health.DIRECTIONS`), operational counts via `--raw`, and cost via `--tokens-total` + `--reqs-accepted`, where **`--reqs-accepted` is the count of REQs whose Reality-Ledger `evidence-class` is at/above the run's `--min-evidence` (validated, not green)** — so `cost_per_req` is cost per *validated* requirement. A non-allowlisted metric key is rejected fail-closed.

**Step 2 — Apply, then run the full suite (the canvas/true-line/PRIL grep pins are untouched — this is additive prose).**

Run: `bash config/claude/tests/run_all.sh`
Expected: `ALL CHECKS PASSED`.

**Step 3 — Commit.**
```bash
git add config/claude/commands/agileteam.md
git commit -m "docs(agileteam): emit cost per VALIDATED req; route counts to --raw"
```

---

# STEP 2 — Pure-win cleanups (each independently green)

### Task 2.1: Delete the unused, Plumbline-blind `core/reviewer.md`

**Verified safe:** the command dispatches `code-reviewer` (= `code-reviewer.md`); `core/reviewer.md` (agent name `reviewer`) is never dispatched; it is **not** in `emit_run.py` COMPONENTS; no test references `core/reviewer`.

**Files:**
- Delete: `core/reviewer.md`

**Step 1 — Re-confirm it is unreferenced (abort if any hit appears outside generated snapshots).**
```bash
grep -rn "core/reviewer\|subagent_type[\": ]*reviewer\b\|\`reviewer\`" \
  --include=*.md --include=*.sh --include=*.py . \
  | grep -vE "agent-explorer\.html|docs/index\.html|code-reviewer"
```
Expected: no meaningful hits (only `code-reviewer` mentions, which are excluded).

**Step 2 — Delete and run the suite (frontmatter validator must still pass; no duplicate-name impact).**
```bash
git rm core/reviewer.md
bash config/claude/tests/run_all.sh
```
Expected: `ALL CHECKS PASSED`.

**Step 3 — Commit.**
```bash
git commit -m "chore(agents): remove unused, never-dispatched core/reviewer.md (code-reviewer is canonical)"
```
> Explorer note: `agent-explorer.html`/`docs/index.html` are generated snapshots not checked by the suite. Rebuild them once at Task 2.7.

### Task 2.2: Strip dead claude-flow MCP boilerplate from the 4 dispatched core agents

**Verified safe:** no test greps `claude-flow`/`memory_usage`. These `## MCP Tool Integration` sections reference non-existent `mcp__claude-flow__*` tools (runtime-ignored). Editing `core/{coder,planner,tester}.md` changes their fingerprint hash — expected/intended (versioning).

**Scope (this task):** remove ONLY the `## MCP Tool Integration` markdown section and any residual MCP-coordination prose line. **Do NOT** touch the `hooks:`/`model:`/`capabilities:` frontmatter in this wave (the "runtime ignores `hooks:`" claim is unverified — leave it; revisit only with evidence). Each file must still parse and keep `name` + `description`.

**Files:**
- Modify: `core/coder.md` — remove `## MCP Tool Integration` (line 220) through end-of-section; in `## Collaboration` drop the line `- Share all implementation decisions via MCP memory tools` and change the final sentence `... Always coordinate through memory.` → `... Focus on clarity, maintainability, and correctness.`
- Modify: `core/tester.md` — remove `## MCP Tool Integration` (line 340) through end-of-section.
- Modify: `core/researcher.md` — remove `## MCP Tool Integration` (line 121) through end-of-section.
- Modify: `core/planner.md` — remove `## MCP Tool Integration` (line 117) through end-of-section.

**Step 1 — For each file: delete from the `## MCP Tool Integration` header to the next top-level `## ` heading (or EOF), plus residual MCP lines as listed.** Confirm no `mcp__claude-flow` string remains:
```bash
grep -rn "claude-flow\|mcp__claude" core/*.md
```
Expected: no output.

**Step 2 — Run the suite (frontmatter parse + description + no-dup-names + py paths all green).**

Run: `bash config/claude/tests/run_all.sh`
Expected: `ALL CHECKS PASSED`.

**Step 3 — Commit (one atomic ballast removal).**
```bash
git add core/coder.md core/tester.md core/researcher.md core/planner.md
git commit -m "chore(agents): strip dead claude-flow MCP boilerplate from core agents"
```

### Task 2.3: Inline the loop-cap defaults into the command

**Verified safe:** `MAX_DEVREVIEW_LOOPS`/`MAX_QA_RETURNS` are referenced in the command (lines 517, 528, 571, 578) but defined ONLY in `docs/agileteam-spec-v3.md:99-100`. No test pins them.

**Files:**
- Modify: `config/claude/commands/agileteam.md` (Guard clause, after the "Resolve project parameters…" bullet, ~line 260)

**Step 1 — Add a defaults line (preview, then apply):**
```markdown
- **Loop caps (defaults, overridable at invocation):** `MAX_DEVREVIEW_LOOPS=4`,
  `MAX_QA_RETURNS=3` (from `docs/agileteam-spec-v3.md`). A standalone invocation of
  this command must use these unless the user overrides them — never run unbounded.
```

**Step 2 — Run the suite.** Expected: `ALL CHECKS PASSED`.

**Step 3 — Commit.**
```bash
git add config/claude/commands/agileteam.md
git commit -m "docs(agileteam): inline MAX_DEVREVIEW_LOOPS=4 / MAX_QA_RETURNS=3 defaults (no unbounded loops standalone)"
```

### Task 2.4: Fix the duplicate `### Phase 0.5` header

**Verified safe:** the only `Phase 0.5` test pin is `test_runtime_integrity_layer.sh:167`, which greps for `"PRIL Context Integrity gate"` — the *first* 0.5 (line 417), which we keep. The *second* 0.5 (spec-sanity, line 458) sits AFTER 0.6, so its number is wrong; renumber it to 0.7.

**Files:**
- Modify: `config/claude/commands/agileteam.md` (lines 458, 234-235, 53)

**Step 1 — Edits (exact):**
- Line 458: `### Phase 0.5 — Spec-sanity gate (ultrathink, ONCE)` → `### Phase 0.7 — Spec-sanity gate (ultrathink, ONCE)`
- Lines 234-235: `... Phase 0.5\n  spec-sanity, Phase 1 ...` → `... Phase 0.7\n  spec-sanity, Phase 1 ...`
- Line 53 tail: `... +  spec-sanity audit` → `... +  spec-sanity audit (Phase 0.7)`

**Step 2 — Confirm exactly one `### Phase 0.5` header remains and PRIL pin intact.**
```bash
grep -n "^### Phase 0\.\(5\|7\)" config/claude/commands/agileteam.md
grep -c "PRIL Context Integrity gate" config/claude/commands/agileteam.md   # must be >= 1
```
Expected: one `### Phase 0.5 — PRIL …`, one `### Phase 0.7 — Spec-sanity …`.

**Step 3 — Run the suite.** Expected: `ALL CHECKS PASSED` (incl. `runtime integrity layer tests`).

**Step 4 — Commit.**
```bash
git add config/claude/commands/agileteam.md
git commit -m "docs(agileteam): renumber duplicate Phase 0.5 spec-sanity gate to 0.7 (numeric=positional order)"
```

### Task 2.5: Trim `konfabulations-audit/SKILL.md` (preserve the claim-enum + behavioral literals)

**Verified safe:** no test greps the skill's internals; `test_web_bootstrap.sh:42` only asserts the FILE EXISTS at `skills/konfabulations-audit/SKILL.md`. Fingerprint hash changes — expected. **This is a behavioral gate skill — review the trimmed version carefully before applying.**

**MUST preserve (zwingend):** the frontmatter `name`+`description`; the four marks `belegt | ableitbar | ungeprüft | nicht behaupten` and the classification table; the non-negotiable "Grundsatz" (never close a gap by guessing); the escalation rule (no `ungeprüft`/`nicht behaupten` as a premise; exactly one remediation pass); the output format. **Remove only redundancy:** fold the `## Common Mistakes` table (it restates the classification + decision rule) into one line, and compress the verbose `## Wann verwenden` (it duplicates the frontmatter `description`).

**Files:**
- Modify: `config/claude/skills/konfabulations-audit/SKILL.md`

**Step 1 — Produce the trimmed draft and SHOW IT IN FULL for approval** (do not apply unreviewed). Target ≈ half the current length while keeping every preserved item above verbatim.

**Step 2 — Verify the load-bearing literals survive:**
```bash
for s in belegt ableitbar "ungeprüft" "nicht behaupten" brainstorming BLOCKER; do
  grep -q "$s" config/claude/skills/konfabulations-audit/SKILL.md && echo "ok $s" || echo "MISSING $s"
done
```
Expected: all `ok`.

**Step 3 — Run the suite** (frontmatter validator parses the skill; web-bootstrap file-exists check still passes). Expected: `ALL CHECKS PASSED`.

**Step 4 — Commit.**
```bash
git add config/claude/skills/konfabulations-audit/SKILL.md
git commit -m "refactor(skill): trim konfabulations-audit redundancy (claim-enum + escalation preserved)"
```

### Task 2.6: Conservative prose de-duplication — OPTIONAL, test-guarded, marginal

**Honest scope note:** estimated saving is small (~2–3k tokens off the resident prompt only) and this is the **highest-risk / lowest-reward** item because ~200 grep assertions pin command wording. The canvas-gate "restatements" at lines 68 / 138 / 344 are **role-differentiated** (rule statement / entry-condition checklist / workflow steps), not pure duplicates — do **not** collapse them. Only remove a block that is **verbatim** repeated AND leaves every pinned phrase present elsewhere.

**Mechanical procedure (per candidate, abort-on-red):**
1. Find a verbatim-repeated sentence: `grep -n "<sentence>" config/claude/commands/agileteam.md` → must show ≥2 identical hits.
2. Confirm none of the test files pins that specific occurrence by location (the suite uses `has` = presence, so one copy must remain): keep ≥1 copy of every pinned phrase.
3. Remove exactly one redundant copy.
4. Run `bash config/claude/tests/run_all.sh`. If **anything** goes red, `git checkout -- config/claude/commands/agileteam.md` and STOP — that copy was load-bearing.
5. If green and the removal saved real tokens, keep it.

**Decision gate:** if no clearly-verbatim, clearly-unpinned duplicate is found within ~15 min, **SKIP this task** and note it deferred. Do not force it.

**Step — Commit only if a safe removal was made:**
```bash
git add config/claude/commands/agileteam.md
git commit -m "docs(agileteam): remove a verbatim-duplicate restatement (all pinned literals retained)"
```

### Task 2.7: Regenerate the Agent Explorer snapshot (if toolchain available)

**Files:** `agent-explorer.html`, `docs/index.html` (generated).

**Step 1 — Rebuild after the agent edits (deletion + MCP strip).**
```bash
./build-explorer.sh
```
Expected: `wrote .../agent-explorer.html` + `synced .../docs/index.html`.
Requires `python3`+PyYAML, `pnpm`/node, and the `artifacts-builder` skill. **If the toolchain is unavailable, STOP and report the explorer as stale** (must be rebuilt before any release) — do not hand-edit the generated HTML. The test suite does not gate on the explorer, so the wave stays green either way.

**Step 2 — Commit (separate, generated artifact).**
```bash
git add agent-explorer.html docs/index.html
git commit -m "build(explorer): regenerate snapshot after core/reviewer removal + MCP-ballast strip"
```

---

## Final verification (whole wave)

**Step 1 — Full suite green:**
```bash
bash config/claude/tests/run_all.sh   # ALL CHECKS PASSED
```
**Step 2 — Cost loop now closeable (demonstrate the win is real, not asserted):**
```bash
python3 config/claude/metrics/emit_run.py --dry-run --metrics '{"mutation":0.81}' \
  --raw '{"tasks":6,"devreview_loops_total":8}' --tokens-total 240000 --reqs-accepted 6
# -> record carries metrics_schema_version, metrics.cost_per_req=40000.0, raw provenance
```
**Step 3 — Confirm the commit history is atomic** (`git log --oneline`): one commit per logical change.

---

## Appendix A — STEP 3 background design (DO NOT IMPLEMENT this wave)

Prepared only, for the next wave once this lands and a baseline window exists:
- **One real fail-closed Stop hook** under a **new filename** (NOT `pretool-plumbline-guard.sh`, which `test_runtime_integrity_layer.sh:156-160` asserts stays unregistered/inert). Sentinel-gated (mirror `stop-learning-loop.sh`) so normal sessions are untouched.
- On Stop/commit: derive changed files from `git diff --name-only` (ground truth, not the agent's list) → `plumbline-scope-check`; run `plumbline-context-check`; run `plumbline-reality-check --min-evidence integration`. Any non-zero → emit `{"decision":"block","reason":…}`; the hook itself never exits non-zero.
- Ship its contract test INTO `run_all.sh` in the same commit; register append-only behind its own dedup key (don't disturb the exactly-once `stop-learning-loop` registration that `test_web_bootstrap.sh` pins).

## Appendix B — Locked until the baseline program lands

Risk-router, digest-broker, and model-tiering remain **fully locked**. Prerequisite: author the 10 missing `bench-core-v1` fixtures (only `T04`, `T11` exist today; the manifest specifies 6 gap tasks incl. **`T05` docstring-lie**) and run a baseline sweep (≥2 baseline points, ≥3 runs/cell, Opus AND Haiku). Until then, every routing/tiering "quality-neutral" claim is unprovable and therefore forbidden by Plumbline's own creed.
