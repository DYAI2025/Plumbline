# Plumbline — Development Plan (open work)

> Living roadmap of what is **not yet shipped to `main`**. Each item states the user
> value we expect from it. Honest status labels: `live on main` · `on feature branch
> (reviewed, not merged)` · `not started` · `contract-tested only (not yet live-run)`.
>
> Plumbline discipline applies to this file too: nothing here is claimed done until it
> is on `main` and exercised. See `metrics/SUMMARY-2026-05-30-dna-investigation.md` for
> the evidence philosophy ("tests green ≠ it works").

Last updated: 2026-06-13

---

## In flight — branch `true-line-workflow-completion` (reviewed, awaiting merge)

These extend `/agileteam` into a full **customer-value-governed** pipeline. Each was
TDD'd (contract assertions first) and passed an independent code review.

| ID | Feature | Status | User value (1–2 sentences) |
|----|---------|--------|----------------------------|
| G1 | **Council challenge gate** (Phase 0.16, `concilium --mode=challenge`, token-bounded) | branch, reviewed ✓ | Before a line of code, three adversarial voices stress-test *whether you're even building the right thing* — so you don't spend a sprint perfecting an idea that should have changed. |
| G3 | **Vision-GO gate → autonomous run** | branch, reviewed ✓ | You confirm the Product Vision once, then the team runs autonomously toward it — you get hands-off delivery without losing the single human checkpoint that matters. |
| G4 | **Minimum + dynamic team composition** | branch, reviewed ✓ | Every build always has a reviewer, QA, and product-owner; other specialists are added per architecture — you get right-sized teams instead of a fixed cast that's wrong for the job. |
| G5 | **Per-increment Code-reviewer → QA → Watcher chain** | branch, reviewed ✓ | Every increment is checked for customer value *as it's built*, not just at the end — drift is caught early, when it's cheap to fix. |
| G6 | **Graded Watcher escalation** (re-align first, escalate only if unreachable) | live on main · ⚠ **superseded by OD-2** (2026-06-03) | ~~maximal autonomy~~ — **TIGHTENED:** bounded autonomy is restricted to pure code-writing; **any** deviation from the user-confirmed Product Canvas must **hard-block** and force an interactive human gate. See Decisions below. |
| G7 | **CLI iteration counter `N/M` + per-iteration Kanban** | branch, reviewed ✓ | You always see "iteration 3/5" and the open tasks for this round — so you can gauge how much is left without reading the agents' minds. |

**Status correction (2026-06-03):** this section is **stale**. G1/G3/G4 and the
per-increment chain (G5) are **live on `main`** (merged via the v0.11/v0.12 release flow;
verified in `concilium.md` / `agileteam.md` and guarded by the PR-1 gate-contract tests).
The "branch, reviewed" labels above predate that merge.

## Decisions (2026-06-03 — anchored via `/agileteam` directive)

- **OD-1:** Wave A (front-door integrity) started 2026-06-03.
- **OD-2 — Bounded-autonomy hardening (supersedes G6):** autonomy is restricted to **pure
  code-writing**. **Any** deviation from the user-confirmed Product Canvas MUST **hard-block
  the run and force an interactive human y/n gate** — no autonomous re-alignment across a
  Canvas boundary. ⚠ **This reverses the current shipped behavior** (`agileteam.md`
  "re-align first; escalate only if the Vision goal is unreachable", ~:219-232) and
  intersects the G3 contract tests (`test_gate_contracts.sh` G3-C4 "Watcher escalates to the
  user" stays satisfied; the re-align-first prose itself changes). **Decision recorded here;
  implementation is a separate governance task (Roadmap Wave B / L3) — NOT yet on `main`.**
- **OD-3 — Council backend:** default to **OpenRouter free-tier auto-discovery**, **fail-closed**
  if <2 independent model backends are reachable (no single-model masquerade). Roadmap Wave C.
- **OD-4:** website (Roadmap Wave D) scheduled **after Wave B**.

---

## Not started

| ID | Feature | Status | User value (1–2 sentences) |
|----|---------|--------|----------------------------|
| G8 | **Customer-usage acceptance test + council fallback** | not started | QA tests the product the way a real customer would use it; a grave deviation blocks acceptance and convenes the council for a realistic fix — so "done" means *actually usable*, not just green. |
| G9 | **SMART retrospective with legitimate null-result** | not started | Retros only adopt changes that are Specific/Measurable/Achievable/Realistic/Time-bound — and may correctly decide to change *nothing* — so the framework improves on evidence, not on the urge to "do something". |
| T9 | **Docs: spec-v3 + governance + README** for the new gates | partial (README updated; spec/governance pending) | New users can understand and trust the value gates because they're documented, not just coded — lowering the barrier to adoption. |

---

## Validation debt (the honest gap)

| Item | Status | User value of closing it |
|------|--------|--------------------------|
| **Live `/agileteam` dry-run of the True-Line layer** | **partially closed 2026-06-13** — Watcher drift-detection now `real-boundary-smoke` ✓ ([evidence](docs/benchmarks/2026-06-13-true-line-live-validation.md): n=8, **catch 3/3 · cry-wolf 0/3**, **Opus 4.8**, verified from subagent logs); full 8-phase orchestration wiring still `contract-tested only` | The Watcher now carries **runtime** evidence that it catches a **blatant** planted value contradiction and **names the violated Canvas non-goal** — that judgment is no longer `unit-fake` by our own standard. Still open (see the evidence doc's "What this did NOT prove"): the orchestrator wiring that invokes the Watcher end-to-end + records the CONTRA + gates later phases; a multi-model result (the run was **Opus-4.8-only — the tier already known to work; no Haiku/Sonnet evidence**); and code-level/diff verification. The `subtle` arm paused 2/2 — disclosed as correct-but-over-sensitive conservatism, not a clean pass. |
| **Council cognitive diversity** | not wired — **OD-3 (2026-06-03):** default to **OpenRouter free-tier auto-discovery**, fail-closed if <2 independent backends reachable (Wave C, own design pass) | `/concilium`'s value depends on *uncorrelated* models. Today it runs as a structured single-model critique. OD-3's OpenRouter route (or a user API key for stronger models) is the path to real triangulation — gated **fail-closed** so it never silently degrades to single-model (the failure it exists to prevent). |

---

## Done & live on `main` (for context)

- 87 subagents, `/agileteam` v3, `/concilium` four-body council, `/honest-status`, `/bench-oracle`, `/reflect`(-skills).
- Product Canvas gate, Product Vision gate, Plumbline Watcher (Gate E), Reality Ledger, contradiction ledger — all merged via PRs #6/#7.
- The mutation-oracle benchmark suite + the honest negative result (`metrics/`).
- Live Agent Explorer on GitHub Pages.
