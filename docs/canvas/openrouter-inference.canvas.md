# Product Canvas: OpenRouter Inference Path

Status: user-confirmed
Owner: requirements-analyst
Confirmed by user: yes
Canvas file: docs/canvas/openrouter-inference.canvas.md
Feature-Slug: openrouter-inference
Slice: 1 of 4 (foundation — inference path only)

> The Product Canvas is a **mandatory pre-build value-alignment artifact**. `/agileteam`
> may not finalize the PRD or enter development until this canvas is filled in, saved,
> linked to PRD/Vision/traceability, and **explicitly confirmed by the user**.
>
> Allowed `Status` values: `draft` | `user-confirmed` | `blocked`. This canvas is `draft`;
> no agent may self-confirm it. Two product-critical questions are open (OQ-1, OQ-2) — they
> are scoped to NOT block the canvas confirmation (one carries a documented default, the
> other resolves at smoke time), but the user is asked to settle them at the gate.

> **Provenance.** Inputs below tagged `EXPLICIT (Ben, 2026-06-19)` come from a
> brainstorming gate with the user; they are user-decisions, not agent assumptions.
> Inputs tagged `ASSUMPTION` are agent-derived and require user confirmation.

> **Relationship to OD-3.** This slice EXTENDS the already-merged OpenRouter Council
> Backend (`config/claude/lib/council_backend.py`, slice OD-3, canvas
> `docs/canvas/openrouter-council-backend.canvas.md`). It reuses OD-3's key-handling
> (`OPENROUTER_API_KEY` as boolean presence; raw value only ever in the `Authorization`
> header; never logged/returned), redaction discipline, and normalized-base concepts. It
> closes the invocability gap OD-3 deliberately left at `RED(confidence)`: OD-3 proved the
> catalog/list-models endpoint is reachable (`real-boundary-smoke`), but **never ran a real
> completion** — "reachable ≠ invocable" (OD-3 OQ-B-004, NGOAL-B-004).

---

## 1. Problem

| ID | Field | Content | Status |
|---|---|---|---|
| CAN-INF-001 | Problem | Plumbline can detect that OpenRouter models are *reachable* (OD-3 catalog smoke) but has **no real inference path** — it cannot actually send a prompt to a model and get a completion back. The central honesty claim "reachable ≠ invocable" is currently unanswered: a listed model may still return 402/429/5xx for the user's key/credit. | EXPLICIT (Ben, 2026-06-19) |
| CAN-INF-002 | Why now | This is the foundation the next three slices (DeepSeek review agent, real 4-body council, GUI) all build on. Without a governed, budget-safe inference call, none of them can run for real. | EXPLICIT (Ben, 2026-06-19) |
| CAN-INF-003 | Cost danger | A naive inference path can silently burn credits (runaway loops, large contexts, expensive models). The problem includes "spend money only on purpose, never by accident." | EXPLICIT (Ben, 2026-06-19) |

---

## 2. Target user / customer

| ID | User group | Need | Status |
|---|---|---|---|
| CAN-INF-004 | Plumbline maintainer / operator (Ben) | A real, governed OpenRouter completion call he can build the council/review agents on, with hard budget guardrails so experimentation can't run up an unexpected bill. | EXPLICIT (Ben, 2026-06-19) |
| CAN-INF-005 | Plumbline developer (later slices) | A stable, reusable inference function + classified error codes to call from the DeepSeek reviewer (Slice 2) and the live council (Slice 3). | ASSUMPTION |
| CAN-INF-006 | Reviewer / auditor | Evidence that the inference path is honestly classified: offline tests are `integration-fake`; invocability is `real-boundary-smoke` ONLY for the one model actually probed, and nothing more. | ASSUMPTION |

---

## 3. Current workaround

| ID | Content | Status |
|---|---|---|
| CAN-INF-007 | Today OD-3 only probes the **catalog** endpoint (`GET https://openrouter.ai/api/v1/models`) to count reachable distinct normalized bases. There is no completion call at all; `/concilium` runs Claude-only via the four body prompts. Any "does this model actually answer?" question is currently unanswerable inside Plumbline. There is also no per-run budget cap, no pre-call cost estimate, and no dry-run mode. | EXPLICIT (Ben, 2026-06-19) |

---

## 4. Value proposition

| ID | Statement | Status |
|---|---|---|
| CAN-INF-008 | Plumbline gains a **real** OpenRouter inference path: `POST https://openrouter.ai/api/v1/chat/completions` with a model id, messages, and the reused key-handling — proving invocability (for the probed model) rather than only reachability. | EXPLICIT (Ben, 2026-06-19) |
| CAN-INF-009 | **Hard budget guardrails, fail-closed:** a configurable per-run limit from `.env` (e.g. `COUNCIL_MAX_TOKENS_PER_RUN`, optionally a max-USD), a pre-call cost **estimate**, a free **dry-run** mode, and a fail-closed abort if a run would exceed the cap. No auto credit management. | EXPLICIT (Ben, 2026-06-19) |
| CAN-INF-010 | **Classified error codes** for budget / timeout / credit / HTTP failures (extending OD-3's `COUNCIL_*` code family) so callers branch deterministically and no raw traceback leaks. | EXPLICIT (Ben, 2026-06-19) |
| CAN-INF-011 | Secret safety carried over from OD-3: `OPENROUTER_API_KEY` read as presence + used only in the `Authorization` header, never logged or returned; `.env` stays gitignored. | EXPLICIT (Ben, 2026-06-19) |
| CAN-INF-012 | Tests stay offline / fake (0 credits); invocability is proven by ONE opt-in tiny real smoke (a few cents) OUTSIDE the offline suite — same pattern as OD-3's catalog smoke. | EXPLICIT (Ben, 2026-06-19) |

---

## 5. Success signal

| ID | Signal | Status |
|---|---|---|
| CAN-INF-013 | The full offline test suite (`run_all.sh`) is green with the new inference module: config/budget-estimate/dry-run/error-classification logic exercised network-free, 0 credits spent. | EXPLICIT (Ben, 2026-06-19) |
| CAN-INF-014 | ONE opt-in real smoke sends a tiny `chat/completions` request to a cheap model and gets a non-empty completion back, with the key not leaking (leak-check = 0) — recorded in `docs/benchmarks/2026-06-19-openrouter-inference-smoke.md`. This earns `real-boundary-smoke` for invocability **of that one probed model only**. | EXPLICIT (Ben, 2026-06-19) |
| CAN-INF-015 | A run that would exceed the configured cap aborts fail-closed with the budget error code BEFORE any network call (proven offline). | EXPLICIT (Ben, 2026-06-19) |

---

## 6. Core use case

| ID | Content | Status |
|---|---|---|
| CAN-INF-016 | A caller invokes the inference function with a model id and a messages array. The path: (1) loads config + budget cap from `.env`; (2) computes a pre-call cost **estimate**; (3) if `dry-run`, returns the estimate WITHOUT a network call (0 credits); (4) if the estimate would exceed the cap, aborts fail-closed with the budget code; (5) otherwise does the single `POST .../chat/completions` with the key in the `Authorization` header only; (6) returns the completion text, or a **classified** error code on budget/timeout/credit/HTTP failure. The raw key never enters output. | EXPLICIT (Ben, 2026-06-19) |

---

## 7. Non-goals

| ID | Excluded (explicitly a LATER slice or out of scope) | Status |
|---|---|---|
| NGOAL-INF-001 | The DeepSeek code-review agent (Slice 2). | EXPLICIT (Ben, 2026-06-19) |
| NGOAL-INF-002 | Running the 4-body council for real / orchestration (Slice 3). | EXPLICIT (Ben, 2026-06-19) |
| NGOAL-INF-003 | Any GUI (Slice 4). | EXPLICIT (Ben, 2026-06-19) |
| NGOAL-INF-004 | Auto credit purchase / management / top-up. | EXPLICIT (Ben, 2026-06-19) |
| NGOAL-INF-005 | Streaming responses, multi-turn conversation state, tool/function calling, or model fallback chains — not in this foundation slice. | ASSUMPTION |
| NGOAL-INF-006 | Proving invocability of MORE than the one model the opt-in smoke probes, or claiming general "all configured models are invocable." | EXPLICIT (Ben, 2026-06-19) |

---

## 8. Risks / contradictions

| ID | Risk | Likelihood | Impact | Mitigation | Status |
|---|---|---:|---:|---|---|
| RISK-INF-001 | API key leaks into logs / returned dict / error output. | medium | high | Reuse OD-3 discipline: key as boolean presence, only in `Authorization` header; redaction test; no raw-env dump. | CONFIRMED |
| RISK-INF-002 | Budget cap is bypassable (estimate computed but not enforced, or enforced only after the call). | medium | high | Estimate + cap check run BEFORE the network call; fail-closed abort with classified code; proven offline. | CONFIRMED |
| RISK-INF-003 | The OpenRouter `chat/completions` request/response contract assumed by the coder is wrong (wrong field names, wrong cost/usage fields), so the budget estimate or completion parse is built on a false premise. | medium | high | External-API premise (see OQ-3): the exact request/response shape (esp. token/cost/`usage` fields) MUST be verified against the live OpenRouter API at the smoke, NOT hardcoded as truth from memory. Until verified it stays `ungeprüft`. | OPEN QUESTION |
| RISK-INF-004 | Cost **estimate ≠ actual cost**: a pre-call estimate cannot perfectly predict billed tokens (provider tokenizer differences, output length). The cap could be slightly over/undershot. | medium | medium | Estimate is a guard, framed as necessary-not-exact; the smoke is tiny (a few cents) to bound real exposure; honestly disclosed as an estimate. | CONFIRMED (residual) |
| RISK-INF-005 | "reachable ≠ invocable": a model listed in the catalog can still 402 (no credit) / 429 (rate limit) / 5xx at completion time. | high | medium | This is exactly the gap this slice exists to expose; classified error codes per failure class; the smoke either succeeds (proving invocability for that model) or returns a classified code (still honest). | CONFIRMED |
| RISK-INF-006 | Over-claiming evidence class: presenting offline tests or a single-model smoke as broader "invocability proven." | medium | high | Reality-Ledger framing: offline = `integration-fake`; smoke = `real-boundary-smoke` for the ONE probed model only. RED may not be downgraded; only the user reclassifies at the acceptance gate. | CONFIRMED |
| RISK-INF-007 | The opt-in smoke accidentally runs inside the offline suite / CI and spends credits. | low | high | Smoke is opt-in, gated (env flag), and lives OUTSIDE `run_all.sh` — same isolation pattern as OD-3's catalog smoke. | CONFIRMED |
| RISK-INF-008 | Scope creep into Slice 2/3/4 (review agent, council orchestration, GUI) during this foundation slice. | medium | medium | Non-goals NGOAL-INF-001..003 are explicit; Allowed change scope is narrow and machine-parseable. | CONFIRMED |

---

## 9. Evidence needed

| ID | Evidence | Status |
|---|---|---|
| CAN-INF-EVN-001 | Offline tests (`integration-fake`, 0 credits): config/cap loading, pre-call cost estimate, dry-run returns estimate with NO network call, fail-closed abort when estimate exceeds cap, classified error codes for budget/timeout/credit/HTTP, redaction (key never in output). All green under `run_all.sh`. | EXPLICIT (Ben, 2026-06-19) |
| CAN-INF-EVN-002 | `.env.example` review: new budget variable(s) documented, key field present and empty, `.env` gitignored. | EXPLICIT (Ben, 2026-06-19) |
| CAN-INF-EVN-003 | ONE opt-in real-boundary smoke against `POST https://openrouter.ai/api/v1/chat/completions` with a cheap model → non-empty completion, leak-check = 0, recorded in `docs/benchmarks/2026-06-19-openrouter-inference-smoke.md`. Earns `real-boundary-smoke` for invocability of that ONE model only. | EXPLICIT (Ben, 2026-06-19) |
| CAN-INF-EVN-004 | **External-API contract verification (OQ-3):** at the smoke, the real `chat/completions` request/response shape (model, messages, and the token/cost/`usage` fields the estimate relies on) is confirmed against the live API and recorded. Until then the contract is `ungeprüft` and may not be a finalized PRD premise. | OPEN QUESTION |
| CAN-INF-EVN-005 | **Reality Ledger:** offline = `integration-fake`. Invocability = `real-boundary-smoke` for the probed model ONLY; broader invocability / cost-accuracy stays `RED(confidence)` unless the user reclassifies at the acceptance gate. | EXPLICIT (Ben, 2026-06-19) |

---

## Allowed change scope

> Proposed by the orchestrator, grounded against the repo. Final OK by the user at the
> pre-build gate. `concilium/*.md` is **read-only** (council prompts stay source of truth).

**Machine-parseable scope (PRIL `plumbline-scope-check` / `plumbline_scope.py`).** One
backtick-wrapped path per line so the runtime scope guard can parse it:

- `config/claude/lib/council_backend.py`
- `config/claude/lib/council_inference.py`
- `config/claude/tests/test_council_backend.sh`
- `config/claude/tests/test_council_inference.sh`
- `config/claude/tests/run_all.sh`
- `.env.example`
- `.gitignore`
- `docs/canvas/openrouter-inference.canvas.md`
- `docs/prd/openrouter-inference.prd.md`
- `docs/vision/openrouter-inference.vision.md`
- `docs/traceability.md`
- `docs/plans/2026-06-19-openrouter-inference.md`
- `docs/reality/openrouter-inference.evidence.jsonl`
- `docs/benchmarks/2026-06-19-openrouter-inference-smoke.md`
- `backlog.md`
- `CLAUDE.md`

Human note: this slice may extend the existing OD-3 module
(`config/claude/lib/council_backend.py`) OR add a sibling
`config/claude/lib/council_inference.py` — both are listed so the planner/coder can pick
without re-opening scope. New tests may go in the existing OD-3 test file or a new
`test_council_inference.sh`; both are listed for the same reason. `concilium/*.md` is
NOT in scope (read-only).

Status: user-confirmed (scope-detail confirmed by Ben, 2026-06-19)

---

## 10. Traceability links

PRD: docs/prd/openrouter-inference.prd.md (not yet created — PRD finalization blocked until this canvas is user-confirmed)
Product Vision: docs/vision/openrouter-inference.vision.md (to be created by product-owner after PRD draft)
Traceability Matrix: docs/traceability.md (new slice: openrouter-inference; carries canvas-link to this file)
Related REQ IDs: TBD in PRD (proposed prefix REQ-INF-*)
True-Line status: pass

---

## Open Questions

| ID | Question | Resolution / Status |
|---|---|---|
| OQ-1 | **Default value for the per-run token cap** (`COUNCIL_MAX_TOKENS_PER_RUN`), and whether to ALSO enforce a max-USD cap in this slice. | **RESOLVED (Ben, 2026-06-19): token-only**, default `COUNCIL_MAX_TOKENS_PER_RUN=20000` (configurable in `.env`). No max-USD cap in this slice (clean later add). |
| OQ-2 | **Which cheap model** to use for the one opt-in invocability smoke (e.g. a low-cost DeepSeek model, or a free model). | **RESOLVED (Ben, 2026-06-19): free models are the DEFAULT**, but the model is **user-configurable** (any OpenRouter model id). Per OD-3 CAN-B-010 / NGOAL-B-002, the free model is NOT hardcoded as stable truth — its availability is verified at runtime (catalog/probe). The opt-in smoke uses the configured model (free by default). |
| OQ-3 | **OpenRouter `chat/completions` request/response contract** (exact field names, and the token/cost/`usage` fields the budget estimate relies on). | **OPEN QUESTION / external-API premise, `ungeprüft`.** Must be verified against the live OpenRouter API at implementation/smoke time; not hardcoded from memory. Bound to RISK-INF-003 and CAN-INF-EVN-004 so the coder cannot silently freeze an unverified contract. |

---

## User confirmation

Confirmed by user: yes
Confirmation date: 2026-06-19
Confirmation note: Ben confirmed at the /agileteam Phase-0.15 gate. OQ-1 resolved (token-only cap, default COUNCIL_MAX_TOKENS_PER_RUN=20000, no USD cap this slice). OQ-2 resolved (free models as default, user-configurable to any OpenRouter model; availability verified at runtime, not hardcoded). OQ-3 remains `ungeprüft` (external chat/completions contract — verify live at build/smoke).
