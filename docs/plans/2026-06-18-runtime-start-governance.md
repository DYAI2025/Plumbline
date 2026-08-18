# Build Plan & Handoff: Runtime Start Governance (BL-002 / BL-003)

Branch: `agileteam/runtime-start-governance`
Status: Phase 0–1 complete, spec frozen, RED test contract written. **Build (Phase 2) not started.**
Confirmed by: Ben, 2026-06-18. Operating mode: CORE.

## Where we are (resume here)

| Phase | State |
|---|---|
| 0 Intake (canvas/vision/prd/traceability) | ✅ user-confirmed, committed `babd9e8` |
| 0.5 Spec-sanity (spec-auditor) | ✅ BLOCKER found → remediated (1 pass) |
| Watcher entry verdict | ✅ pass |
| Spec freeze (incl. DiD hook decision) | ✅ committed `5fb3110` |
| 1 TDD setup (tester + planner) | ✅ RED tests + this plan |
| 2 Build (coder/reviewer/security loop) | ⏳ NOT started — start here |

## Architecture (user-confirmed, two enforcement layers)

1. **Command-level gate** in `/agileteam` Phase 0: invoke `config/claude/bin/plumbline-start-check`,
   consume the verdict as a control-flow precondition, refuse planning/coding on `VISION_MISSING`.
   Behavioral change to `config/claude/commands/agileteam.md`. Must work in LOCAL sessions.
   **Honest ceiling: integration-fake** (grep proves the instruction exists, not live obedience).
2. **PreToolUse hook backstop** (harness-enforced): new `config/claude/hooks/pretool-start-gate.sh`
   + idempotent registration in `install.sh` (mirror `register_enforce_hook`, but into
   `.hooks.PreToolUse`). Denies planning/coding dispatch on `VISION_MISSING`, passes normal
   dispatch through. **This is the load-bearing real-boundary-smoke guarantee.**

### Resolved design decision — hook detection = **Option A**
The hook calls `plumbline-start-check --json` itself against the active feature
(reads `docs/context/.active-feature`), INDEPENDENTLY of whether the command-gate ran.
NOT Option B (marker written by command-gate) — that would couple the backstop to gate
compliance and defeat defense-in-depth.

## RED test contract (already written, untracked→committed this handoff)

- `config/claude/tests/test_pretool_vision_gate_hook.sh` — REQ-A-011/AC-A-006/EV-A-005, **real-boundary-smoke**. 8/12 RED (correct). Includes a 255 absent-sentinel + strict `is_deny()` so a missing hook is NOT mistaken for a deny (a false-green caught and fixed in Phase 1).
- `config/claude/tests/test_runtime_start_governance_gate.sh` — REQ-A-001..008 / AC-A-001..005 / EV-A-001/002/004, mostly **integration-fake**. 3/13 RED. The 10 green lines pin the classifier verdict (the input the gate consumes).

**Neither is wired into `run_all.sh` yet** — that is build task T1/T5 (wire as a `stage`).
**Reconciliation note:** these two files ARE the contract. The task list below references some
test names (`test_runtime_start_gate_hook.sh`, extending `test_agileteam_start_gate.sh`) — adopt
the EXISTING tester files instead of creating duplicates; rename only if needed, do not fork.

## Task sequence (atomic, TDD, dependency-ordered)

- **T0** Arm build: confirm branch + clean tree; write `docs/context/.active-feature` = `runtime-start-governance`; baseline `run_all.sh` green.
- **T1** Wire `test_pretool_vision_gate_hook.sh` into `run_all.sh` as a stage; confirm RED. (real-boundary-smoke)
- **T2** Implement `config/claude/hooks/pretool-start-gate.sh` (Option A detection; reuse `plumbline-start-check`, no logic dup; fail-closed for affected dispatch, fail-open/no-op otherwise; never crash session) → T1 green. (real-boundary-smoke)
- **T3** Failing test for idempotent `install.sh` registration under `.hooks.PreToolUse` (isolated `CLAUDE_HOME`, mirror `test_pril_enforce_hook.sh` §8); existing Stop hooks unregressed. (real-boundary-smoke)
- **T4** Add `register_pretool_start_hook` to `install.sh`; call in `INSTALL_HOOK` block → T3 green. (real-boundary-smoke)
- **T5** Wire `test_runtime_start_governance_gate.sh` into `run_all.sh`; confirm RED for the command-gate parts. (integration-fake — FLAGGED ceiling)
- **T6** Edit `config/claude/commands/agileteam.md`: add binding Phase-0 gate step invoking `plumbline-start-check` (mirror the Phase 0.5/0.6 fenced-bash pattern); consume verdict as precondition; remove the stale "remains unproven…" sentence (line ~30) → T5 green. Keep global `~/.claude/commands/agileteam.md` in sync. (integration-fake)
- **T7** Produce behavioral real-boundary trace `docs/benchmarks/2026-06-18-runtime-start-governance.md` (plain `#` heading, NO `---`). Must be a REAL run, not a hand-typed snapshot (RISK-A-003). **Feasibility ceiling:** the hook layer gives genuine real-boundary (a real planning/coding dispatch is denied); the command-gate halt may only reach integration-fake — mark precisely which layer the trace proves; do not let the hook launder the command-gate's weaker evidence.
- **T8** Update `docs/traceability.md` (`wired-in-prod?` cells) + `backlog.md` BL-002/003. **Closure (F3) conditional:** close ONLY if T7 reached genuine real-boundary-smoke for the halt; else rows read `PASS(tests)/RED(confidence)` and the slice does NOT close without explicit user reclassification.
- **T9** Full `run_all.sh` green (new stages incl. shellcheck); `git status` only in-scope files.

Then: Phase 3 gates (Gate A verify / Gate C validation+Reality-Ledger / Gate E plumbline-watcher),
Phase 3 metrics-emitter + arm learning loop, then the **human acceptance gate**.

## Honest end-state expectation (tell the user, don't surprise them)
The PreToolUse hook becomes the actual governance guarantee (real-boundary-smoke). The
command-gate is the orchestration/UX layer (integration-fake). If T7's live `/agileteam`
halt trace cannot reach real-boundary, **BL-003 closes only `PASS(tests)/RED(confidence)`**
per F3 — and that RED may not be silently downgraded; only the user may reclassify.

## Single biggest feasibility risk
T7: a genuine behavioral real-boundary trace of a live `/agileteam` session halting before
planning. The runtime gives no scriptable hook into the orchestrator's own control flow to
assert "planning was not entered." Mitigation: the hook layer (T2/T4) carries the hard proof;
plan for T7's command-gate portion to legitimately top out at integration-fake.

## Allowed change scope (user-confirmed)
`agileteam.md` (behavioral), `config/claude/hooks/` (new PreToolUse hook), `install.sh`
(registration), `config/claude/tests/**`, `config/claude/bin`/`lib` (reuse only, no logic dup),
`docs/benchmarks/…`, `docs/traceability.md`, `backlog.md`, `docs/context/.active-feature`.
NOT in scope: `session-start.sh`, `plumbline_start.py` logic.

## How to resume in a fresh session
1. `cd` repo, confirm branch `agileteam/runtime-start-governance`, `run_all.sh` green.
2. Start at T0. Use fresh `coder` per task (test-first), independent `code-reviewer` + `security-reviewer` on each diff. Keep `plumbline_start.py` logic and `session-start.sh` untouched.
3. Paket B (OpenRouter Council Backend, OD-3) intake is already confirmed/committed but NOT yet planned — separate build after A (or its own branch).
