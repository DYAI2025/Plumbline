# Plumbline Authenticity Roadmap

> **For Claude:** This is a PRIORITIZED PROGRAM ROADMAP, not a single TDD task list. Near-term waves (A, B) carry task-level detail and reference the existing per-feature plans; later items (C council, D website) are design briefs that each need their own `superpowers:brainstorming` → `writing-plans` pass before execution. Execute waves in order; each wave ends with `bash config/claude/tests/run_all.sh` green and integrates via `/merge-when-true`.

**Goal:** Close every verified gap between what Plumbline *claims* and what it *enforces or honestly discloses* — front door first, then the gates, then the council, then amplification — so the framework actually lives its own creed.

**The one prioritization lens (authenticity impact):** Plumbline's thesis is *"looks-done ≠ is-done; radical honesty."* So rank work by **how much it converts a CLAIM into an ENFORCED REALITY or an HONEST DISCLOSURE.** The biggest hypocrisies (a radical-honesty project that oversells on its front page; gates that are prose, not enforcement; a "diverse council" that is single-model) are the highest-value targets — regardless of effort.

**Architecture:** Four waves. **A — First-contact honesty** (README + clean install + dependency boundary). **B — Truth beyond markdown** (convert prose-gates into machine-enforced gates; dispatch-model verification is the keystone). **C — Council epistemic diversity** (multi-model, fail-closed; own design pass). **D — Amplification** (website) — deliberately LAST so we never amplify an inauthentic message.

**Tech Stack:** Bash (`install.sh`, tests), Python 3 stdlib (`plumbline_update.py`, PRIL `lib/*.py`, metrics), `runs.jsonl` ledger + `process_health.py`, GitHub Actions (CI), Markdown (docs/agents/commands), and — Wave C only — an HTTP client to OpenRouter (key-gated).

---

## Status of what already shipped this session (feeds the waves; do not redo)

- **PR-1 — gate contract tier (G1/G3/G4)** on `main`: deterministic drift-guards; G3 negative fixture guards the final human gate; `agileteam-roster.yml`. → Wave B builds on this.
- **PR-2 — challenge-token oracle** on `main` + the **measured bench** (`metrics/bench-2026-06-03-challenge-token-oracle.md`, on `main` + `agileteam-improved`): proved the `≤15k` token bound was false (~103k), withdrew it, defined "tokens total", re-baselined to the structural bound. → the *pattern* (measure, don't assert) drives Wave B.
- **`/merge-when-true`** on `main`: human-facing merge gate where "green" = TRUE-green, not test-green. → Wave B adds the **machine-enforced** half (dispatch-model verification).
- **`docs/plans/2026-06-03-install-audit-fixes.md`** (uncommitted, ultrathink-gate PENDING — the gate agent hit the session limit): the TDD detail for the install bugs. **Wave A SUBSUMES it** — re-run the ultrathink gate on it before executing, then execute under Wave A.

---

## Master priority table (everything, ordered by authenticity impact)

| # | Item | Type | Authenticity impact | Effort | Wave |
|---|------|------|--------------------|--------|------|
| A1 | **README demotion**: "87 ready-to-use subagents" → honest count + recast the ~74 vendored claude-flow agents as a **tested-workload dependency**, not "team members" | disclosed-unactioned (our own concilium said it: `concilium/reports/2026-05-30-plumbline.md:58,110`) | **highest** — the loudest claim-vs-reality gap, on the most-read surface | low | **A** |
| A2 | **Dependency boundary doc** `DEPENDENCIES.md`: what is EXTERNAL vs SHIPPED vs REFERENCED-NOT-SHIPPED | verified gap (F1) | high — answers "what do I actually get" honestly | low | **A** |
| A3 | **Clean install**: PATH fix (your `command not found`), F4 macOS verification, F5 colon skill | verified bugs | high — first-contact trust | low | **A** |
| A4 | **Count derivation + drift-guard** (F8) coupled to `build-explorer.sh` | verified | medium — makes A1 self-true forever | low | **A** |
| A5 | **Install-model honesty** (F1/F2): "no MCP server, not a `/plugin`; some agents reference `mcp__claude-flow__*` → external optional" + fork-update override discoverability (F6) | verified gap | medium | low | **A** |
| B1 | **Dispatch-model enforcement gate**: PRIL reads `runs.jsonl` and FAILS the merge gate if the reviewer/validator did not run on the required model — frontmatter `model:` is inert, so trust the *log*, not the prose | disclosed (Gemini Prio 2; `CLAUDE.md`) | **highest structural** — makes the model-policy claim REAL; precondition to ever unlock M7 | medium | **B** |
| B2 | **Prose-gate → enforced-gate audit**: catalog which governance/PRIL gates are prompt-only vs. machine-checked; convert the highest-value ones (continues PR-1/PR-2 pattern) | new (the deepest theme) | **highest structural** | medium-high | **B** |
| B3 | **F3 agent-dir mount** (gated on verifying the "phantom agents" premise first — see install-audit-fixes P6) | verified-but-premise-unverified | medium | medium (risky) | **B** |
| C1 | **Multi-model council** (OpenRouter free-tier auto-config, or user-key curated models), **fail-closed**: <2 independent model backends → abort, never single-model masquerading as diversity | disclosed validation-debt (`2026-06-02-plumbline-maturation-goal.md:290`) + Gemini Prio 1 + your feature | **highest epistemic** — the reflection organ stops being an echo chamber | high (own design) | **C** |
| D1 | **Website** presenting Plumbline honestly (the bench, the negative results, the reality ledger, the live explorer) | new | medium — amplification | high (own design) | **D** |
| L1 | Sanitize dangling `mcp__claude-flow__*` refs in vendored agents | verified (root of F1) | medium | medium | folds into A2/B2 |
| L2 | **M7 risk-router / model-tiering** | LOCKED by our own creed until baseline + B1 | n/a (correctly frozen) | — | after B1 |
| L3 | **G6 autonomy decision**: dev-plan.md:26 says "G6=branch" but the re-align autonomy IS on `main` (`agileteam.md:219-232`) — reconcile the stale tracker; decide stricter human-gate-on-Canvas-deviation vs. keep bounded-autonomy (Vision immutable + escalate-to-user + final acceptance gate already preserved, guarded by PR-1 G3 tests) | needs human decision | medium | low | **B**-adjacent |

---

## WAVE A — First-Contact Authenticity (do first; highest impact/effort)

*Why first: a framework whose whole brand is radical honesty must not oversell on its README or fail to install. This is the loudest hypocrisy and the cheapest to fix. It is also the precondition for D (don't build a website around an inauthentic message).*

**A1 — README honesty (TDD-guarded).**
- Rewrite the headline: replace "87 ready-to-use subagents" with the **derived** count (from A4) + the council's own framing: *"N core, independently-engineered agents + ~M vendored-from-claude-flow agents shipped as a **tested workload / dependency** (prompts only — not individually benchmarked)."* Source the "tested workload" language from `concilium/reports/2026-05-30-plumbline.md:88,110`.
- TDD guard: a `run_all` check asserting the README does NOT claim a bare ready-to-use agent count that exceeds the count of *benchmarked* agents without the dependency caveat.
- Commit `fix(docs): demote agent-count marketing; recast vendored agents as a tested-workload dependency`.

**A2 — `DEPENDENCIES.md` (the boundary you asked for).**
Create `DEPENDENCIES.md` (linked from README + SETUP) stating exactly:
- **EXTERNAL — prerequisites, NOT shipped:** Claude Code (the runtime that loads agents/commands/hooks), `python3` (+`PyYAML`), `bash`, `git`, `jq`; CI also `shellcheck`. Plumbline does not install these.
- **SHIPPED in this repo — the deliverable:** all agent *prompts* (incl. the ~74 derived from claude-flow — we ship the **markdown**, not claude-flow's runtime), the 16 vendored skills, the commands, the hooks, the PRIL `bin/`+`lib/` (Python), the metrics harness + corpora, `install.sh`.
- **REFERENCED but NOT shipped (the honest caveat):** the **claude-flow MCP tools** (`mcp__claude-flow__*`) that some vendored agents' frontmatter lists — these need claude-flow's MCP server installed **separately**; without it those tool refs are inert (not an error). **We ship the agents that mention them; we do NOT ship/launch any MCP server.**
- TDD guard: a check that every `mcp__*` tool referenced in an agent is either (a) documented in `DEPENDENCIES.md` as external, or (b) flagged. (This also drives L1.)
- Commit `docs: add DEPENDENCIES.md (external vs shipped vs referenced-not-shipped)`.

**A3 — Clean install (PATH / F4 / F5).** Execute install-audit-fixes plan **P1 (F4 macOS + macOS CI), P2 (F5 colon), P3 (PATH fix + `plumbline doctor` PATH check + SETUP)** verbatim (TDD detail already written there). Re-run the **ultrathink gate** on that plan first (it was interrupted by the session limit).

**A4 — Count derivation + drift-guard (F8).** install-audit-fixes plan **P5**: derive counts from the explorer extractor; guard README against drift. (A1 consumes the derived number.)

**A5 — Install-model honesty + fork override (F1/F2/F6).** install-audit-fixes plan **P4**: README/SETUP state no-MCP/no-plugin; `plumbline doctor` surfaces the resolved update slug + the existing `--repo`/`PLUMBLINE_REPO` override.

**Wave A definition of done:** README count is derived + caveated; `DEPENDENCIES.md` exists and is guarded; `plumbline` is on-PATH-discoverable; `run_all` green on **ubuntu + macOS**; no colon names; install-model + fork-override documented. **First contact is now honest and working.**

---

## WAVE B — Truth-Verification Beyond Markdown (deepest structural authenticity)

*Why: this is the heart of your "technische Sicherheitsgates über Markdown hinaus." Plumbline's gates are prompts the model is asked to honor. The token bound we just proved was false prose. The model-policy is inert frontmatter. Converting the highest-value claims into machine-enforced checks is what makes Plumbline structurally — not rhetorically — true.*

**B1 — Dispatch-model enforcement (the keystone). Own brainstorm→plan pass; sketch:**
- **Claim today:** "review/security/validation/judgment is only trustworthy on Opus" (`CLAUDE.md`, the bench). **Reality:** nothing checks the model a sub-agent actually ran on; `model:` frontmatter is inert.
- **Enforce it:** at dispatch, the orchestrator must record the **actual model** per critical role into `runs.jsonl` (or a per-run dispatch ledger). PRIL (`plumbline-reality-check`) + the merge gate then **FAIL closed** if the `code-reviewer` / `security-reviewer` / `product-owner` / `production-validator` did not run on the required model. No log evidence → RED (treat like a `*-fake` Reality-Ledger entry).
- **Design questions (for the dedicated pass):** can the orchestrator capture the dispatched model reliably (the `subagent_tokens`-style usage we used in PR-2 suggests per-dispatch metadata is observable)? What's the ledger schema? How does this gate compose with `/merge-when-true` gate 1?
- Unblocks **L2 (M7)** honestly: only once model is enforced can a cost lever claim "quality-neutral."

**B2 — Prose-gate → enforced-gate audit. Own pass; sketch:**
- Catalog every governance/PRIL/True-Line gate: is it **prompt-only** (model asked to honor) or **machine-checked** (a test/script fails closed)? Output an honest table (this is itself a Reality-Ledger application to the framework).
- Convert the highest-authenticity prose-gates to enforced ones, reusing the **gate-contract (PR-1) + oracle (PR-2)** pattern. Candidates: wired-in-prod evidence-class, the independence rule (writer≠reviewer — could be checked from the dispatch ledger), no-silent-RED-downgrade.
- Honest output includes: which gates **cannot** be machine-enforced (genuinely need human/model judgment) — mark those clearly so the framework doesn't over-claim enforcement either.

**B3 — F3 agent-dir mount** — only after its premise is verified (install-audit-fixes P6 Task 6.0). Wave A's clean install + Wave B's enforcement make this safe to attempt last.

**L3 — G6 decision** (Wave-B-adjacent): reconcile the stale `dev-plan.md:26` and decide, explicitly with the user, whether a Canvas deviation should hard-stop with `y/n` (Gemini's stricter stance) or keep the current bounded-autonomy (Vision immutable + escalate-to-user + final acceptance gate, already on `main` and guarded by PR-1 G3 tests). **A design decision, not a bug.**

---

## WAVE C — Council Epistemic Diversity (deepest epistemic authenticity) — OWN FULL DESIGN PASS

*Your feature. The single-model council is the deepest epistemic limitation (disclosed, not hidden). This needs its own `brainstorming` + `writing-plans` pass — here is the BRIEF + the non-negotiable invariant, not a task list.*

**The invariant (Gemini Prio 1, non-negotiable):** the council is **fail-closed on diversity**. If fewer than **2 independent model backends** are actually reachable, `/concilium` **aborts** with an error — never a single-model run masquerading as a diverse council. Every report states which models actually ran (this disclosure already exists: `concilium.md:78-87`).

**Two routes (design both):**
1. **OpenRouter free-tier, zero-key-ish:** ship a config that **auto-discovers the *currently* free models** from OpenRouter's model list at runtime (do NOT hardcode model names — they churn) and seats N of them as council bodies for a short, token-bounded council.
2. **User-key curated:** the user enters one OpenRouter (or provider) API key once; we seat a curated set of stronger current models.
   - ⚠ **Konfabulation guard:** the specific models you named (deepseek-*, nemotron-120b, qwen-3.5, owl-alpha) are **examples to verify at design time** — I have NOT confirmed they exist / are free / are on OpenRouter. The design must **query the live model list**, not hardcode names, and disclose exactly what it seated.

**Open design questions:** secret handling (key never in repo/logs — reuse `plumbline-redact`); cost bounding per body; how OpenRouter bodies map to the four-body mandates; failure/timeout → fail-closed (the gemini-CLI-hung-on-interactive-prompts incident from the 2026-05-30 report is the cautionary tale); does this supersede or complement the existing `mcp__gemini__*` MCP route in `concilium.md:82`. **Authenticity impact is very high** — but only if fail-closed; a flaky free-model council that silently degrades to single-model would be *worse* than honest single-model.

---

## WAVE D — Amplification: Website (BACKLOG; after Wave A) — OWN DESIGN PASS

*Deliberately last among the "build" items: amplify only a message that is already true (Wave A). The site's content should BE Plumbline's differentiator — the honest one.*
- Present: the philosophy ("does it hang true?"), the **bench with its negative results** (the DNA investigation, the token-bound refutation), the Reality Ledger, the two-metric anti-Goodhart gate, and the **live Agent Explorer** (already at `docs/index.html` / GitHub Pages).
- Lead with the honesty, not an agent count. The site is where "radical honesty" becomes the marketing — authentically.
- Needs its own design pass (stack, hosting, content). Backlog.

---

## The smartest sequence, in one paragraph

**Make the front door honest and working (A) → make the gates real, not rhetorical (B) → make the council genuinely diverse (C) → amplify the now-true story (D).** Every wave converts a claim into enforced reality or honest disclosure — Plumbline's own philosophy applied to itself. A precedes D on principle: never amplify a message that isn't yet true. B precedes any cost-lever (M7) and any "we're rigorous" marketing, because rigor you can't enforce is just prose. C is the highest-ceiling item but gated on fail-closed design, or it becomes the very echo chamber it's meant to fix.

## Open decisions (human)

- **OD-1:** Confirm Wave A goes first (recommended) vs. you want the council (C) prioritized despite its larger design cost.
- **OD-2 (L3/G6):** stricter human-gate-on-Canvas-deviation, or keep bounded autonomy + just fix the stale `dev-plan.md` tracker?
- **OD-3 (C):** OpenRouter free-auto-discovery as the default council backend, with user-key as the upgrade — confirm this is the route to design.
- **OD-4:** Website (D) timing — straight after A, or after B/C land so it can show the enforcement story too?
