# Gate Verification & Hardening — Contract + Oracle (Design)

> **Status:** Design (validated via `superpowers:brainstorming`, 2026-06-03). This is the
> *design*, not yet a task-by-task plan. The implementation plan (PR-1…PR-3) is authored
> separately with `superpowers:writing-plans` / `/agileteam`, on an **isolated branch** —
> per the repo's multi-agent protocol, the build work is **not** done on `main`.

**Scope:** Harden and *verify* three `/agileteam` gates that today exist only as
orchestrator prose, behind a two-tier verification ladder — deterministic **Contract**
tests first, behavioral **Oracle** tests second (hybrid sequencing).

- **G1 · Council challenge gate** — `concilium --mode=challenge`, three roles, token-bounded, pre-PRD (Phase 0.16).
- **G3 · Vision-GO → autonomous run** — one human GO, autonomous to completion, *final* human gate preserved.
- **G4 · Minimal & dynamic team composition** — fixed minimum + architecture-driven specialists.

---

## Why this exists (the gap)

All three gates **already exist** as orchestration design (`concilium.md`,
`agileteam.md`). But every existing "test" for them is a **substring-presence check**
(`has "label" "$FILE" "string"` in `config/claude/tests/lib.sh`): it proves *"the prompt
still contains this phrase,"* never that the gate **fires**, stays bounded, pauses on real
risk, or composes the right team. That is exactly the *"looks done" vs. "actually done"*
gap this repo exists to expose.

### Two findings that justify the work (measured 2026-06-03)

1. **G4's contract is already violated.** `agileteam.md:347` promises to staff
   `backend-dev`, `ml-developer`, `mobile-dev`, `system-architect`. **None is declared
   in-repo** (no `name:` frontmatter); they are pulled "from `~/.claude/agents/`"
   (`agileteam.md:287`) but Plumbline's own `install.sh` does not ship them. On a clean
   Plumbline install these dispatches resolve to nothing — the founding incident ("exists
   in design, never composed in reality"), inside the orchestrator itself. **A G4 contract
   test goes RED today, and that RED is the point.**
2. **The token bound is aspirational prose.** `"≤ ~15k tokens total"` (note the `~`,
   `concilium.md:29`, `agileteam.md:113,377`) is an *instruction to the model* — there is
   **no runtime mechanism** that counts tokens and stops. Contract can only assert the
   number is present and parseable; **only the Oracle** can prove a real challenge run
   stays under budget.

`bench-oracle.md`, `metrics/emit_run.py`, `metrics/process_health.py`, and
`metrics/corpus/` already exist — the Oracle tier has a natural host.

### Decisions taken in brainstorming

- **Goal:** harden *and verify* (not redesign) the three gates.
- **Definition of "verified":** two-tier ladder, **staggered** — Contract first, Oracle second.
- **Sequencing:** **Hybrid** — all three Contract tests now (cheap, immediate, surfaces the
  G4 RED), then a vertical Oracle pilot on G1, then replicate Oracle to G3/G4.

---

## Architecture — two tiers, split by cost and CI placement

**Tier 1 — Contract (deterministic, offline, per-commit).** New Bash module
`config/claude/tests/test_gate_contracts.sh`, wired into `run_all.sh` like the existing 13
modules, using `lib.sh`. Where substring `has` is insufficient (parse numbers, compare two
*sets* of role names, resolve a roster), a small helper `config/claude/lib/gate_contracts.py`
(py_compile-checked like the others). **No model calls** — runs in any CI in <1s.

**Tier 2 — Oracle (behavioral, model-dependent, bench/FULL only).** Reuses
`bench-oracle.md` + `metrics/emit_run.py` + `metrics/corpus/` + `runs.jsonl`. A thin
**gate-slice harness** invokes *only* the gate's sub-prompt against a seeded fixture,
captures output + token usage, asserts observable behavior mechanically. **Never** a full
`/agileteam` run (too expensive / non-deterministic). Never runs in per-commit CI.

**Cross-cutting invariants (both tiers):**

- **Every contract test gets a negative fixture** — a deliberately broken copy that *must*
  go RED. A test that cannot go red proves nothing.
- **RED stays RED** — no silent downgrade (Reality Ledger). The G4 finding *should* be
  initially red.
- **Missing oracle tooling → `MISSING`**, never faked green.
- **Model-dependence is disclosed** — if the bound only holds on Opus, that is in the run,
  not hidden.

**Data flow:** Contract → exit code (CI gate). Oracle → one record per run in `runs.jsonl`
→ `process_health.py` (SPC / drift), exactly like the existing bench.

---

## Tier 1 — Contract specs (deterministic, offline)

### G1 — challenge gate

- **G1-C1 · Bound parseable & consistent.** Extract the token number from `concilium.md`
  *and* `agileteam.md`; assert both present, numerically parseable, and **equal**.
- **G1-C2 · Per-round cap consistent.** `"≤180 words per role per round"` present and equal in both sources.
- **G1-C3 · Role-set equality.** The three roles {`Challenger`, `Advisor`, `Critic`} are
  identical **as a set** across `concilium.md` and `agileteam.md` (order-independent).
- **G1-C4 · Alias → body resolves.** Each challenge role maps to a real body prompt
  (`concilium-skeptic`, …); assert each referenced `subagent_type` exists as an agent file
  with matching `name:` frontmatter. (Prevents a G4-style dangling alias.)
- **G1-C5 · Phase-0.16 triple wiring.** `Phase 0.16` + the invocation
  `concilium --mode=challenge` appear consistently in (a) the phase table, (b) the detail
  section, (c) the workflow step; and `concilium.md` declares the `--mode=challenge`
  section. A missing site → RED.
- **G1-C6 · Intent invariant.** `"friction, not approval"` + `"≤1-page user-facing
  summary"` present — guards against the gate silently mutating into an *approval* gate.
- **G1-C7 · Negative fixture.** A broken copy (role set diverges / token numbers mismatch)
  **must** go RED.

*Today:* G1 is internally consistent → C1–C6 green; the value is **drift protection** + C4/C7 hardening.

### G3 — vision-GO → autonomous run

- **G3-C1 · Both bookends exist.** The **Vision-GO gate** (`agileteam.md:488-536`) **and**
  the **USER ACCEPTANCE GATE** (`:624-630`) are both present — autonomy sits *between* two
  human gates.
- **G3-C2 · Negative fixture = the core invariant.** A copy with the `USER ACCEPTANCE GATE`
  section **deleted** (simulating "autonomy ate the final gate") **must** go RED. This is
  *the* test protecting the promise *"without losing the final control point."*
- **G3-C3 · Bounded-autonomy clause.** `"the Watcher may pause; the user is the final authority"` present.
- **G3-C4 · Escalation asymmetry.** Uncertainty resolves toward the user — the Watcher
  escalates rather than continuing (`:228`).
- **G3-C5 · Vision goal immutable in re-alignment.** The clause that re-alignment may not
  modify/narrow/reinterpret the Vision goal, and any change requires explicit user
  re-confirmation (`:226`), is present.
- **G3-C6 · Owner separation.** The **Watcher** (not coder/orchestrator) owns the
  "can any correction still reach the goal" determination (`:228`).
- **G3-C7 · `/goal` wiring + path consistency.** Autonomous run references the
  `goal-planner` / `/goal` ruleset (`:502-504`); `docs/vision/<feature>.vision.md`
  consistent between phase table and detail.

### G4 — team composition (goes RED today)

Single source of truth: **roster manifest** `config/claude/agileteam-roster.yml`, declaring
each role `/agileteam` may staff with `source: in-repo | external:<collection>`. A test
binds manifest ↔ prose so they cannot drift.

- **G4-C1 · Fixed minimum exact.** Manifest minimum = **exactly** {`coder`, `code-reviewer`,
  `tester` (QA), `product-owner`} (set equality, `agileteam.md:343-350`).
- **G4-C2 · Every role resolves.** Each manifest entry is **either** in-repo (`name:`
  exists) **or** `external:<collection>` with a documented provider. Neither → **RED**. →
  the four specialists go RED today until classified.
- **G4-C3 · Prose ↔ manifest equality.** Every specialist named in `agileteam.md` is in the
  manifest and vice versa — no silent prose-only role.
- **G4-C4 · External deps documented in install path.** Each `external:` has a note in
  `SETUP.md` / `install.sh` so a clean install knows it needs them (wired-in-prod analog).
- **G4-C5 · Negative fixture.** A manifest entry naming a non-existent in-repo agent must go RED.

---

## Tier 2 — Oracle specs (behavioral, model-dependent, bench/FULL)

**Harness.** A thin runner invokes *only* the gate's sub-prompt against a seeded fixture,
measures output + tokens, checks mechanically (deterministic *oracle*, even though model
text varies — like the mutation-oracle corpora), and appends **one record per run** via
`emit_run.py` → `runs.jsonl` (corpus-id = gate-id, mode=full). `process_health.py` gives
SPC / drift. Bench/FULL only.

- **G1 (pilot) — "the bound is real, not aspirational."** Fixed Canvas + raw idea; run
  `concilium --mode=challenge`.
  - **O1 (the decisive one):** total tokens ≤ bound (15k). Over → **RED** → proves the
    bound needs a real mechanism (hard-stop / truncation), not a request. This converts
    prose into a measured fact.
  - O2: output ≤ ~1 page (word threshold). O3: the three roles produce *distinct*
    contributions (low overlap) — against "consensus theater."
- **G3 — "pause iff the Vision goal is genuinely at risk" (mutation oracle).** Two fixtures
  from one base: **A** = planted vision-risk → gate **must** pause/escalate; **B** = routine
  doubt → gate **must not** pause. Oracle: `pause(A)=true ∧ pause(B)=false`. Pause-on-
  everything (cry-wolf) and pause-never (rubber-stamp) both fail — the anti-Goodhart pair
  (catch vs. false-alarm). **Both numbers reported, never one alone.**
- **G4 — "roster tracks domain" (mutation oracle).** Seeded canvases ML / CRUD-backend /
  Mobile. Oracle: composer staffs the domain-correct specialist, omits irrelevant ones,
  **always** includes the fixed minimum. Change the domain → roster must change. "Staffs
  everyone" (no minimality) and "staffs the same" (no dynamism) both fail.

**Honesty (cross-cutting):** per-model disclosure (Opus-only effects explicit, never sold
as universal); missing foreign-model CLI → `MISSING`; cost small (1 / 2 / 3 fixtures ×
models, no full-pipeline run).

---

## Sequencing (hybrid)

- **PR-1 · Contract tier, all three (must merge green).** `test_gate_contracts.sh` +
  `lib/gate_contracts.py` + `agileteam-roster.yml` + negative fixtures under
  `tests/fixtures/gate_contracts/`, wired into `run_all.sh`. G1/G3 green; **G4-C2 starts
  RED** (the test-first proof of the gap). Since RED must not merge to `main`, PR-1 carries
  the **roster decision** (see Open Decisions) to turn C2 green. Commit type **`fix:`**
  (integrity hardening, changelog-visible).
- **PR-2 · Oracle pilot G1 (bench/FULL, not per-commit).** Gate-slice harness + G1 fixture
  + O1–O3 + emission to `runs.jsonl`. No CI-green requirement (model-dependent); instead a
  **documented bench run** with per-model results. If **O1 RED** (bound not held) → a
  follow-up ticket "real token hard-stop" (deliberately **out of scope** here — YAGNI).
- **PR-3 · Oracle G3 + G4.** Replicate the harness pattern; G3 reports the anti-Goodhart pair.

---

## Definition of Done (cross-cutting, binding)

- Every contract test has a negative fixture **observed** to go RED (test-the-test; not vacuous).
- **Bench isolation:** oracle / gate-slice agents are **TEXT-ONLY**; fixtures staged
  **outside** the repo or in a dedicated worktree; after each run `git status` is clean
  **and** `run_all.sh` is green (the prior corpus-pollution incident).
- `run_all.sh` green on the branch **before** merge (verify the CI *conclusion*, not just
  `mergeable`).
- No hardcoded version numbers in fixtures (read `VERSION` dynamically).
- `runs.jsonl` accumulates on `agileteam-improved`; `main` stays the frozen baseline.
- Explorer rebuild **only if** Open Decision resolves to (i) (new agent files); under (ii) it is skipped.
- Trace-IDs (G1-C1…, G3-C1…, G4-C1…, O1…) recorded in a small traceability note.

## Out of scope (YAGNI)

- No full `/agileteam` end-to-end oracle.
- No token hard-stop *implementation* (this design only **measures**; implementing a real
  cutoff is a follow-up triggered iff O1 goes RED).

## Open decisions (to resolve at implementation time)

- **OD-1 · The four missing specialists** (`backend-dev`, `ml-developer`, `mobile-dev`,
  `system-architect`): **(i)** ship them in-repo (Plumbline becomes self-contained; more
  work; triggers explorer rebuild) **vs. (ii)** declare them `external:<collection>` +
  document the dependency (cheap, honest; source *to be verified* — likely the claude-flow
  agent base). **Recommendation: (ii) now, (i) as a later self-containment path.** PR-1
  cannot merge green until OD-1 is resolved.

## Next step

Author the implementation plan for **PR-1** with `superpowers:writing-plans` (or run it via
`/agileteam`), TDD-first, on an isolated branch. Resolve **OD-1** before PR-1 can go green.
