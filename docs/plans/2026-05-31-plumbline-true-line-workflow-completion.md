# Plumbline True-Line Workflow Completion — Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.
> Work on a feature branch / worktree, never straight on `main`. Each task is TDD:
> add the failing contract assertion to the relevant `config/claude/tests/test_*.sh`
> first, watch it fail, then edit the governance markdown to pass.

**Goal:** Bring `/agileteam` from its current state (PRs #6/#7: Product Canvas + Vision
+ Plumbline Watcher) up to the user's full target workflow: a token-bounded council
challenge gate with user steering, an explicit Vision-GO → autonomous `/goal`-style run,
a minimum+dynamic team, a per-increment Code-reviewer→QA→Watcher creation chain, a
CLI iteration counter (N/M) + per-iteration Kanban view, a customer-usage acceptance
test with a council fallback, and a SMART retrospective that may also produce *no* change.

**Architecture:** All changes are **additive governance edits** to markdown agent/command
files (the runtime is prompt-driven, not code). The test layer is the existing static
contract suites under `config/claude/tests/` (assertion shell scripts wired into
`run_all.sh`). TDD = assertion-first. No agent self-confirms; the user is the only
authority at every gate; nothing weakens Gates A–D or the Reality Ledger.

**Tech Stack:** Markdown agent definitions, bash contract tests (`run_all.sh`), the
existing `plumbline-watcher`, `concilium` council, `kanban-md` (optional), `/goal` skill.

---

## State of the recent changes (PRs #6 & #7) — what shipped, what is missing

Verified 2026-05-31 by reading the merge diff (`5cffb44..226b632`) and grepping the
command file. **Already shipped (keep, do not rebuild):**

| Shipped | Where |
|---|---|
| Product Canvas gate (Phase 0.15), user-confirmed, no self-confirm | `agileteam.md`, `product-canvas.template.md` |
| Product Vision gate (Phase 0.4), PO writes `docs/vision/<f>.vision.md`, user-confirmed | `agileteam.md`, `product-owner.md`, `product-vision.template.md` |
| Plumbline Watcher agent + Gate E + contradiction ledger | `agileteam/plumbline-watcher.md`, `contradiction-ledger.template.md` |
| True-Line traceability fields + canvas/vision link-back | `agileteam.md`, `context-keeper.md` |
| Two contract suites (49 + 40 assertions), all green | `config/claude/tests/test_*.sh` |
| Bundle rebuilt to 87 incl. watcher (this session) | `a644061` |

**Missing vs. the user's target spec (grep-verified: 0 hits each in `agileteam.md`):**

| # | Gap | User requirement |
|---|---|---|
| G1 | **Council challenge gate** is not wired into `/agileteam` | A token-bounded 3-way council (Challenger of the requirement · Advisor for a better implementation · Critic of the underlying concept) runs before PRD finalization; friction-rich; produces a **user-facing summary**; orchestrator asks the user whether any legitimate point changes the product request. |
| G2 | **3-vs-4 council mismatch** | User says **3er Gespräch** (Challenger/Advisor/Critic). The repo's `concilium` has **4** bodies (market/tech/skeptic/distribution) with different framings. **Decision required (do not silently pick).** |
| G3 | **Vision-GO → autonomous `/goal` handoff** absent | After Vision is confirmed, user is told *where* `vision.md` lives and asked for the **initial GO**; from GO it ideally runs fully autonomously following `/goal` skill rules. |
| G4 | **Team-composition rule** absent | Orchestrator picks the most competent team; **default minimum: 1 code-reviewer, 1 QA, 1 product-owner**; all other roles product/architecture-dependent. |
| G5 | **Per-increment creation chain** absent | After *each* incremental code part: Code-reviewer → QA → **Watcher (vision adherence)**. Watcher ignores green tests; asks only "why & how does this increment serve the human customer's benefit?" |
| G6 | **Watcher pause/escalation nuance** under-specified for autonomy | Watcher pauses **only** on legitimate doubt of missing the Vision goal. First: orchestrator+team try to re-align the increment to `vision.md`. Only if **no correction can still reach the Vision goal** → inform user with situation + proposals. Otherwise keep running autonomously. |
| G7 | **CLI iteration visibility** absent | User always sees the pending Kanban tasks **for the current iteration**, plus an overall **iteration counter (e.g. 3/5)** so they can gauge remaining duration. |
| G8 | **Customer-usage acceptance test** absent | After completion, QA tests against a **customer-usage assumption** as well as possible. Grave deviation → product **cannot be accepted** → team uses the **council** to find a realistic solution = REAL customer value (shown, tested, plausibly functional). |
| G9 | **SMART retro + null-result** absent | Retro yields only changes that are calculably an improvement / prevent errors, each **SMART** (Sinnvoll, Messbar, Achievable, Realistisch, Time-based). System changes follow Plumbline's truth→value→growth logic. A retro **may legitimately produce no measures** when that is the truth (growth can be cultivation/deepening of existing value). |

---

## Task 0: Branch + baseline green

**Files:** none (setup)

**Step 1:** Create a worktree/branch off `main`.
Run: `cd /home/dyai/.claude/agents && git switch -c true-line-workflow-completion`

**Step 2:** Confirm the suite is green before changing anything.
Run: `bash config/claude/tests/run_all.sh`
Expected: `ALL CHECKS PASSED`

**Step 3:** Commit nothing yet (clean baseline).

---

## Task 1 (DECISION GATE — ask the user before coding): council shape

**This task has no code. It resolves G2, which blocks G1/G8.**

The user's spec says a **three**-voice council (Challenger · Advisor · Critic). The repo
ships a **four**-body `concilium` (market-realist · tech-arbiter · skeptic ·
distribution-realist). These are two different decompositions. Per Plumbline discipline,
**do not silently choose** — present the user three options and record the answer in this
plan before any council wiring:

- **Option A — Re-map (no new agents):** treat the user's three *functions* as lenses the
  existing four bodies already cover (Challenger≈skeptic on the requirement; Advisor≈
  tech-arbiter+distribution on a better build; Critic≈skeptic+market on the concept).
  `/agileteam` invokes `/concilium` as-is with a token cap. Cheapest; keeps the 4-body
  council. Risk: the "3er Gespräch" framing the user wants is not literally present.
- **Option B — Add a thin 3-role challenge mode** to `concilium` (`--mode=challenge`):
  three explicit roles Challenger/Advisor/Critic, token-bounded, used specifically as the
  `/agileteam` pre-PRD gate; the 4-body deep council stays for standalone `/concilium`.
- **Option C — Re-spec concilium to 3 bodies** (Challenger/Advisor/Critic), retiring or
  folding distribution/market/tech into them. Most faithful to the words; loses the
  distribution body added last session and its rationale.

**Step 1:** Ask the user (Skill `brainstorming` / AskUserQuestion). Record the choice
here as `COUNCIL-DECISION: A|B|C` with date + note. **Do not proceed to Task 2 until set.**

---

## Task 2: Council challenge gate in `/agileteam` (G1)

**Files:**
- Modify: `config/claude/commands/agileteam.md` (new Phase 0.16, after canvas, before PRD finalize)
- Modify: `config/claude/tests/test_true_line_governance.sh` (assertions first)
- (If COUNCIL-DECISION=B) Modify: `config/claude/commands/concilium.md` + add challenge-mode note

**Step 1: Write failing assertions** in `test_true_line_governance.sh`:
- command contains a council challenge gate section
- gate runs after Canvas-confirm and before PRD finalization
- gate is **token-bounded** (explicit cap stated)
- gate produces a **user-facing summary**
- orchestrator **asks the user** whether any legitimate point changes the product request
- council output may NOT auto-edit the Canvas/PRD; only the user reclassifies

**Step 2:** Run `bash config/claude/tests/test_true_line_governance.sh` → expect new lines FAIL.

**Step 3:** Add **Phase 0.16 — Council challenge gate** to `agileteam.md`:
- Invokes the council (per COUNCIL-DECISION) on the confirmed Canvas + raw idea.
- Three stances: **Challenger** (attacks the user's requirement — is it the right ask?),
  **Advisor** (proposes a materially better implementation/approach), **Critic** (attacks
  the underlying concept). Friction-driven, ≤2 collision rounds.
- **Hard token budget** (state a concrete cap, e.g. "≤ ~15k tokens total; ≤180 words per
  body per round; abort to summary on cap").
- Orchestrator distils a **≤1-page user summary** (top legitimate challenges + proposals)
  and **asks the user**: adopt none / adopt specific points (→ amend Canvas, re-confirm).
- The council **suggests, never seizes**: it cannot change Canvas/PRD; only the user can.

**Step 4:** Run the suite → expect PASS.

**Step 5:** Commit.

---

## Task 3: Vision-GO + autonomous `/goal` handoff (G3)

**Files:**
- Modify: `config/claude/commands/agileteam.md` (Phase 0.5 / new GO gate)
- Modify: `config/claude/tests/test_true_line_governance.sh`

**Step 1: Failing assertions:**
- after Vision confirm, command states **where** `docs/vision/<feature>.vision.md` lives and shows it to the user
- command has an explicit **initial GO** gate (user must say GO)
- command states that from GO it runs autonomously following `/goal` skill rules
- autonomy is bounded by the Watcher escalation rule (see Task 5)

**Step 2:** Run → FAIL.

**Step 3:** Edit `agileteam.md`: add **"Vision GO gate"** — present the saved Vision path,
ask for GO, and on GO hand off to an autonomous iterative run governed by `/goal` rules
(reference Skill `goal-planner` / `/goal`), subject to the per-increment chain + Watcher.

**Step 4:** Run → PASS. **Step 5:** Commit.

---

## Task 4: Minimum + dynamic team composition (G4)

**Files:**
- Modify: `config/claude/commands/agileteam.md` (team-selection section)
- Modify: `config/claude/tests/test_true_line_governance.sh`

**Step 1: Failing assertions:**
- command states orchestrator selects the most competent team
- **default minimum** explicitly: ≥1 `code-reviewer`, ≥1 `tester` (QA), ≥1 `product-owner`
- all other roles are **product/architecture-dependent** (chosen per feature)

**Step 2:** Run → FAIL.

**Step 3:** Add a **"Team composition"** subsection to `agileteam.md`: minimum trio always
present; orchestrator adds domain roles (backend-dev, security-reviewer, ml-developer, …)
based on the Canvas/PRD/architecture. Note the model-policy interaction (reviewer/QA/PO
are the Opus-recommended gates from the earlier investigation).

**Step 4:** Run → PASS. **Step 5:** Commit.

---

## Task 5: Per-increment creation chain + Watcher autonomy rule (G5, G6)

**Files:**
- Modify: `config/claude/commands/agileteam.md` (Phase 2 loop)
- Modify: `agileteam/plumbline-watcher.md` (per-increment + re-align-first rule)
- Modify: `config/claude/tests/test_true_line_governance.sh`

**Step 1: Failing assertions:**
- Phase 2 defines a per-increment chain **Code-reviewer → QA → Watcher** after *each*
  incremental code part
- Watcher's per-increment question is value-not-green ("why/how does this increment serve
  the human customer's benefit?")
- escalation rule: on doubt, **first** orchestrator+team try to re-align the increment to
  `vision.md`; **only if no correction can still reach the Vision goal** → inform the user
  with situation + proposals; otherwise continue autonomously
- watcher.md states the re-align-first-then-escalate ordering

**Step 2:** Run → FAIL.

**Step 3:** Edit both files: add the increment chain to Phase 2; add the graded
escalation (re-align → continue; unrecoverable deviation → pause + user) to `watcher.md`,
consistent with its existing pause-authority list (no duplication, reference it).

**Step 4:** Run → PASS. **Step 5:** Commit.

---

## Task 6: CLI iteration visibility — counter N/M + per-iteration Kanban (G7)

**Files:**
- Modify: `config/claude/commands/agileteam.md` (orchestrator reporting duties)
- Modify: `agileteam/context-keeper.md` (owns the iteration/Kanban state)
- Modify: `config/claude/tests/test_true_line_governance.sh`

**Step 1: Failing assertions:**
- command requires the orchestrator to show, each iteration, the **pending Kanban tasks
  for the current iteration**
- command requires an **overall iteration counter** in `N/M` form (e.g. `3/5`)
- context-keeper owns the iteration/Kanban progress state

**Step 2:** Run → FAIL.

**Step 3:** Edit files: orchestrator prints `Iteration N/M` + the current iteration's open
Kanban tasks (via `kanban-md`, falling back to TodoWrite) at each iteration boundary;
context-keeper tracks total planned iterations + remaining tasks.

**Step 4:** Run → PASS. **Step 5:** Commit.

---

## Task 7: Customer-usage acceptance test + council fallback (G8)

**Files:**
- Modify: `config/claude/commands/agileteam.md` (Phase 4 QA / acceptance)
- Modify: `core/tester.md` (customer-usage-assumption test duty)
- Modify: `config/claude/tests/test_true_line_governance.sh`

**Step 1: Failing assertions:**
- after completion, QA (`tester`) tests against a **customer-usage assumption** as well as
  possible
- a grave deviation here means the product **cannot be accepted**
- non-acceptance routes to the **council** to find a realistic solution defined as REAL
  customer value: shown, tested, plausibly functional
- this never weakens Gates A–D (additive)

**Step 2:** Run → FAIL.

**Step 3:** Edit files: add the customer-usage acceptance check to Phase 4 and the
tester's duties; on grave deviation, block acceptance and invoke the council (Task 2 gate)
for a realistic-value solution; loop bounded by `MAX_QA_RETURNS`.

**Step 4:** Run → PASS. **Step 5:** Commit.

---

## Task 8: SMART retrospective with legitimate null-result (G9)

**Files:**
- Modify: `agileteam/retro-analyst.md`
- Modify: `config/claude/commands/agileteam.md` (Phase 8 retro)
- Modify: `config/claude/tests/test_true_line_governance.sh`

**Step 1: Failing assertions:**
- retro proposals must be **SMART** (Sinnvoll/Messbar/Achievable/Realistisch/Time-based) and
  calculably improvement- or error-prevention-positive
- system changes follow Plumbline's **truth → value → growth** logic
- retro may legitimately produce **no measures** when changing nothing is the truthful,
  more-valuable outcome (growth via cultivation/deepening)
- proposals still route through the Watcher retro-challenge (already present)

**Step 2:** Run → FAIL.

**Step 3:** Edit `retro-analyst.md` + Phase 8: encode SMART + the truth/value/growth gate +
the explicit "no-measure is a valid outcome" clause.

**Step 4:** Run → PASS. **Step 5:** Commit.

---

## Task 9: Docs, README, spec-v3, bundle, full suite

**Files:**
- Modify: `docs/agileteam-spec-v3.md`, `docs/agileteam-governance.md`, `README.md`
- Run: `./build-explorer.sh` (or the surgical bundle patch) to keep `docs/index.html` ↔ `agent-explorer.html` in sync if any agent count changed
- Run: full suite

**Step 1:** Document every new gate/phase in spec-v3 + governance; update README workflow section + any counts.

**Step 2:** If COUNCIL-DECISION added/changed agents, rebuild both bundles and verify
`extract-agents.py` count == README == both bundles (the drift check that bit PR #6).

**Step 3:** Run `bash config/claude/tests/run_all.sh` → `ALL CHECKS PASSED`.

**Step 4:** Run `/honest-status` to separate *looks done* from *is done* (which gates are
contract-tested vs. only prose).

**Step 5:** Commit, push, open PR.

---

## Hard limits / honesty notes (read before claiming done)
- These contract tests prove the **governance text exists**, not that the Watcher/council
  actually catch a real value contradiction in a live run. After implementation, a real
  `/agileteam` dry-run on a tiny feature is the only `real-boundary` evidence — schedule it
  as a follow-up; until then the new gates are `evidence-class: unit-fake`.
- `/goal` autonomy + Watcher pause are in tension by design; Task 5's graded escalation is
  the resolution, but only a live run proves it doesn't either over-pause (kills autonomy)
  or under-pause (lets drift through). Flag both failure modes in the dry-run.
- Model policy: reviewer/QA/PO/Watcher are judgment gates → the earlier benchmark says
  Opus; the per-dispatch model param (not frontmatter) is the only effective lever.
