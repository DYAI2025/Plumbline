# Plumbline — Development Plan (open work)

> Living roadmap of what is **not yet shipped to `main`**. Each item states the user
> value we expect from it. Honest status labels: `live on main` · `on feature branch
> (reviewed, not merged)` · `not started` · `contract-tested only (not yet live-run)`.
>
> Plumbline discipline applies to this file too: nothing here is claimed done until it
> is on `main` and exercised. See `metrics/SUMMARY-2026-05-30-dna-investigation.md` for
> the evidence philosophy ("tests green ≠ it works").

Last updated: 2026-05-31

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
| G6 | **Graded Watcher escalation** (re-align first, escalate only if the Vision goal is unreachable) | branch, reviewed ✓ | The team self-corrects toward your Vision and only interrupts you when a deviation genuinely can't be recovered — maximal autonomy, minimal false alarms. |
| G7 | **CLI iteration counter `N/M` + per-iteration Kanban** | branch, reviewed ✓ | You always see "iteration 3/5" and the open tasks for this round — so you can gauge how much is left without reading the agents' minds. |

**Merge action:** open a PR from `true-line-workflow-completion` → `main` after G8/G9/docs
land, with a final whole-branch integration review.

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
| **Live `/agileteam` dry-run of the True-Line layer** | contract-tested only (not yet live-run) | All new gates (Canvas/Vision/Watcher/council) currently prove the governance *text exists*, not that they *catch a real value contradiction at runtime*. A live dry-run on a tiny feature is the only `real-boundary` evidence — without it, the gates are `evidence-class: unit-fake` by our own standard. |
| **Council cognitive diversity (foreign-model MCP wiring)** | not wired | `/concilium`'s value depends on *uncorrelated* models (codex/gemini/qwen). They're installed but not wired as MCP tools, so the council currently runs as a structured single-model critique. Wiring them is the difference between real triangulation and one model arguing with itself. |

---

## Done & live on `main` (for context)

- 87 subagents, `/agileteam` v3, `/concilium` four-body council, `/honest-status`, `/bench-oracle`, `/reflect`(-skills).
- Product Canvas gate, Product Vision gate, Plumbline Watcher (Gate E), Reality Ledger, contradiction ledger — all merged via PRs #6/#7.
- The mutation-oracle benchmark suite + the honest negative result (`metrics/`).
- Live Agent Explorer on GitHub Pages.
