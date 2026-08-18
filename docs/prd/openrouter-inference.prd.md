# PRD: OpenRouter Inference Path

Status: user-confirmed
Confirmed by user: yes (Ben, 2026-06-19, /agileteam Phase-0.5 gate)
Feature-Slug: openrouter-inference
Slice: 1 of 4 (foundation — inference path only)
Canvas: docs/canvas/openrouter-inference.canvas.md
Vision: docs/vision/openrouter-inference.vision.md (to be created by product-owner after this draft)
Owner: requirements-analyst

> This PRD is `draft`. The user confirms it at the Phase-0.5 gate; no agent may
> self-confirm. It is grounded in the **user-confirmed** canvas
> `docs/canvas/openrouter-inference.canvas.md` (confirmed by Ben, 2026-06-19) and
> stays strictly within that canvas's scope and non-goals.
>
> Confirmed product decisions encoded below come from the Phase-0.15 user gate
> (Ben, 2026-06-19): token-only hard cap (default `COUNCIL_MAX_TOKENS_PER_RUN=20000`,
> no USD cap this slice); free model as DEFAULT but user-configurable to any OpenRouter
> model id (availability verified at runtime, never hardcoded as truth); tests stay
> offline/fake (0 credits), with ONE opt-in tiny real smoke proving invocability for the
> probed model only.

> **Relationship to OD-3.** This slice EXTENDS the merged OpenRouter Council Backend
> (`config/claude/lib/council_backend.py`, slice OD-3, PRD
> `docs/prd/openrouter-council-backend.prd.md`). It reuses OD-3's key-handling
> (`OPENROUTER_API_KEY` as boolean presence; raw value only ever in the `Authorization`
> header; never logged/returned), its redaction discipline, the fixed-host POST pattern
> of `_fetch_catalog_ids`, the classify-don't-leak error model, and the `COUNCIL_*` code
> family. It closes the invocability gap OD-3 deliberately left at `RED(confidence)`:
> OD-3 proved the catalog/list-models endpoint is reachable (`real-boundary-smoke`) but
> **never ran a real completion** — "reachable ≠ invocable" (OD-3 OQ-B-004,
> NGOAL-B-004).

## 1. Summary

This feature adds a **real, governed OpenRouter inference path** to Plumbline:
`POST https://openrouter.ai/api/v1/chat/completions` with a configurable model id and a
messages array, behind hard, fail-closed budget guardrails. A caller gets back either a
completion text or a **classified** error code. The path proves invocability (for the one
probed model) rather than only reachability.

The budget guard is **token-only** in this slice: an explicit `max_tokens` is **sent** on
every request; the pre-call estimate is `input_token_estimate + max_tokens`; the estimate
is checked against `COUNCIL_MAX_TOKENS_PER_RUN` (default 20000) **before** the network
call and the run aborts fail-closed if it would exceed the cap. The estimate is labeled
approximate (`≈`) and reconciled against the real response `usage` after the call. There
is no USD cap this slice (clean later add) — and `.env.example` must loudly warn that the
token cap is **NOT** a USD guard.

Implementation uses the Python **stdlib `urllib` only** — no OpenAI/OpenRouter SDK — to
keep key-safety in-repo and to avoid SDK auto-retry silently multiplying spend. The
offline test suite is `integration-fake` (0 credits). Invocability is earned only by ONE
opt-in tiny real smoke, and only for the one model it probes; broader invocability and
estimate accuracy stay `RED(confidence)`.

## 2. Problem Statement

- `EXPLICIT` (CAN-INF-001): Plumbline can detect that OpenRouter models are *reachable*
  (OD-3 catalog smoke) but has **no real inference path** — it cannot send a prompt and
  get a completion back. "reachable ≠ invocable" is currently unanswered.
- `EXPLICIT` (CAN-INF-002): This is the foundation the next three slices (DeepSeek review
  agent, real 4-body council, GUI) build on.
- `EXPLICIT` (CAN-INF-003): A naive inference path can silently burn credits. The problem
  includes "spend money only on purpose, never by accident."

## 3. Goals

| ID | Goal | Source | Status |
|---|---|---|---|
| GOAL-INF-001 | Plumbline gains a real, single `chat/completions` inference call with reused key-handling. | CAN-INF-008 | EXPLICIT |
| GOAL-INF-002 | A configurable, fail-closed, token-only per-run budget cap, checked BEFORE the network call. | CAN-INF-009, OQ-1 | EXPLICIT |
| GOAL-INF-003 | A free dry-run mode that returns the estimate without any network call (0 credits). | CAN-INF-009 | EXPLICIT |
| GOAL-INF-004 | Classified error codes per failure class (budget / credit / rate-limit / unavailable / timeout), extending the `COUNCIL_*` family. | CAN-INF-010 | EXPLICIT |
| GOAL-INF-005 | Carry over OD-3 secret safety: key as presence, only in `Authorization`, never logged/returned. | CAN-INF-011 | EXPLICIT |
| GOAL-INF-006 | Offline tests stay network-free and spend 0 credits; ONE opt-in real smoke proves invocability for the probed model only. | CAN-INF-012, CAN-INF-014 | EXPLICIT |
| GOAL-INF-007 | A stable, reusable inference function callable by later slices (Slice 2 reviewer, Slice 3 council). | CAN-INF-005 | ASSUMPTION |

## 4. Non-Goals

| ID | Non-Goal | Source |
|---|---|---|
| NGOAL-INF-001 | The DeepSeek code-review agent (Slice 2). | CAN-NGOAL-INF-001 |
| NGOAL-INF-002 | Running the 4-body council for real / orchestration (Slice 3). | CAN-NGOAL-INF-002 |
| NGOAL-INF-003 | Any GUI (Slice 4). | CAN-NGOAL-INF-003 |
| NGOAL-INF-004 | Auto credit purchase / management / top-up. | CAN-NGOAL-INF-004 |
| NGOAL-INF-005 | Streaming, multi-turn conversation state, tool/function calling, model fallback chains. | CAN-NGOAL-INF-005 (ASSUMPTION) |
| NGOAL-INF-006 | Proving invocability of MORE than the one model the opt-in smoke probes; claiming all configured models are invocable. | CAN-NGOAL-INF-006 |
| NGOAL-INF-007 | A USD / max-cost cap in this slice (deferred; token-only here per OQ-1). | OQ-1 |
| NGOAL-INF-008 | Using any third-party SDK (OpenAI/OpenRouter client); stdlib `urllib` only this slice. | Sharpening #2 |
| NGOAL-INF-009 | Auto-retry on 429/5xx (no retry loop this slice; fail-closed instead). | Sharpening #2/#3 |

## 5. Functional Requirements

| ID | Requirement | Source | Priority |
|---|---|---|---|
| REQ-INF-001 | An inference function MUST accept a model id and a messages array and perform a SINGLE `POST https://openrouter.ai/api/v1/chat/completions`, returning the completion text or a classified error code. | CAN-INF-008, CAN-INF-016 | MUST |
| REQ-INF-002 | The target host/URL MUST be a fixed module constant (no caller-supplied host) — zero SSRF surface, same pattern as OD-3 `OPENROUTER_MODELS_URL` / `_fetch_catalog_ids`. | OD-3 reuse, RISK-INF-001 | MUST |
| REQ-INF-003 | The HTTP transport MUST be Python stdlib `urllib` only. No OpenAI/OpenRouter SDK. Rationale (recorded): SDK auto-retry can silently multiply spend, violating "spend only on purpose"; in-repo key handling is auditable. | Sharpening #2 | MUST |
| REQ-INF-004 | The inference request MUST set an explicit `max_tokens` field on the request body. A cap without a sent `max_tokens` is FORBIDDEN (it would be unenforceable). | Sharpening #1 (CRITICAL) | MUST |
| REQ-INF-005 | The pre-call token estimate MUST be `input_token_estimate + max_tokens`. The estimate MUST be labeled approximate (`≈`); it is a necessary-not-exact guard, not a billed-token prediction. | Sharpening #1, RISK-INF-004 | MUST |
| REQ-INF-006 | The estimate MUST be checked against `COUNCIL_MAX_TOKENS_PER_RUN` (default 20000, configurable in `.env`) BEFORE any network call. If the estimate would exceed the cap, the run MUST abort fail-closed with `COUNCIL_BUDGET_EXCEEDED` and make NO network call. | CAN-INF-009, CAN-INF-015, OQ-1, Sharpening #1, RISK-INF-002 | MUST |
| REQ-INF-007 | The budget cap MUST be token-only this slice. No USD/max-cost cap is enforced. | OQ-1, NGOAL-INF-007 | MUST |
| REQ-INF-008 | A dry-run mode MUST return the pre-call estimate WITHOUT any network call (0 credits). | CAN-INF-009, CAN-INF-016 | MUST |
| REQ-INF-009 | After a real call, the path MUST reconcile the approximate estimate against the response `usage` (`prompt_tokens` / `completion_tokens`) and surface the real token counts. | Sharpening #1, #4 | MUST |
| REQ-INF-010 | The model id MUST be user-configurable to any OpenRouter model id, defaulting to a free model. The free model MUST NOT be hardcoded as stable truth; its availability is verified at runtime (catalog/probe), consistent with OD-3 CAN-B-010 / NGOAL-B-002. | OQ-2, CAN-INF-016 | MUST |
| REQ-INF-011 | `OPENROUTER_API_KEY` MUST be read as boolean presence; its raw value MUST appear ONLY in the `Authorization: Bearer <key>` header and NEVER in any returned structure, log, error, or output. Missing key → classified `COUNCIL_MISSING_SECRET`, no env dump. | CAN-INF-011, RISK-INF-001, OD-3 REQ-B-016 reuse | MUST |
| REQ-INF-012 | Failures MUST be classified into DISTINCT codes by class, not collapsed: HTTP 402 → `COUNCIL_INSUFFICIENT_CREDIT`; HTTP 429 → `COUNCIL_RATE_LIMITED` (the response `Retry-After`, if present, is recorded — not acted on by an auto-retry loop); HTTP 5xx / other non-2xx → `COUNCIL_MODEL_UNAVAILABLE`; connection failure / socket timeout → `COUNCIL_TIMEOUT`; budget over cap → `COUNCIL_BUDGET_EXCEEDED`; malformed/non-JSON or wrong-shape response → `COUNCIL_MODEL_UNAVAILABLE`. The inference path MUST NOT collapse all `HTTPError` into one code (OD-3's catalog path does; the inference path must not). | CAN-INF-010, Sharpening #3, RISK-INF-005 | MUST |
| REQ-INF-013 | On HTTP 429 the path MUST fail closed (return the classified `COUNCIL_RATE_LIMITED` code). It MUST NOT auto-retry. | Sharpening #2, #3 | MUST |
| REQ-INF-014 | Classification IS success at the process boundary: every classified outcome is a normal (exit-0 / returned-dict) result; no raw Python traceback may reach output. | OD-3 reuse, RISK-INF-001 | MUST |
| REQ-INF-015 | Tests MUST run with NO network and NO real `OPENROUTER_API_KEY` and spend 0 credits. The transport seam MUST be injectable/fakeable so estimate, dry-run, cap-enforcement and error-classification logic are exercised offline. | CAN-INF-013, CAN-INF-EVN-001, OD-3 REQ-B-015 reuse | MUST |
| REQ-INF-016 | The opt-in real smoke MUST live OUTSIDE the offline suite (`run_all.sh`) and be gated by an explicit env flag, so it can never run in CI / the offline suite and spend credits. | CAN-INF-014, RISK-INF-007, OD-3 smoke-isolation reuse | MUST |
| REQ-INF-017 | The opt-in smoke MUST classify, not crash: it either returns a non-empty completion (invocability proven for that one model) OR returns one of the classified error codes (still honest). A free-model 402/429 is NOT a code failure. | Sharpening #6, CAN-INF-014, RISK-INF-005 | MUST |
| REQ-INF-018 | The response parse (completion text, and the `usage` fields the reconciliation relies on) MUST be treated as an external-API premise that is `ungeprüft` until verified against the live API at the smoke (OQ-3). The coder MUST NOT silently freeze an unverified contract; response `cost`/accounting fields MUST NOT be assumed present and MUST NOT be relied on for reconciliation (rely on `usage.prompt_tokens` / `usage.completion_tokens`). | OQ-3, Sharpening #4, RISK-INF-003, CAN-INF-EVN-004 | MUST |
| REQ-INF-019 | The inference function MUST be reusable (a stable signature returning a classified result object) so Slice 2/3 callers can branch deterministically on the code. | CAN-INF-005 | SHOULD |

## 6. Non-Functional / Security Requirements

| ID | Requirement | Source | Priority |
|---|---|---|---|
| NFR-INF-001 | The raw API key MUST never appear in logs, returned dicts, snapshots, error output, or test output (redaction test required). | RISK-INF-001, OD-3 REQ-B-016 reuse | MUST |
| NFR-INF-002 | A network failure / non-2xx MUST be reported as a classified inference failure, never as a successful completion. | RISK-INF-005, REQ-INF-012 | MUST |
| NFR-INF-003 | The request timeout MUST be configurable (reuse `COUNCIL_TIMEOUT_SECONDS`, OD-3 default 45). | OD-3 reuse | SHOULD |
| NFR-INF-004 | `.env` MUST stay gitignored; `.env.example` MUST carry the new budget variable and the key field present-and-empty. | CAN-INF-EVN-002 | MUST |
| NFR-INF-005 | `.env.example` MUST LOUDLY warn the cap is token-only and NOT a USD guard — an expensive model can cost real money at 20k tokens. | Sharpening #5 | MUST |
| NFR-INF-006 | No SDK / third-party HTTP dependency may be added; stdlib only (keeps DEPENDENCIES.md and supply-chain surface unchanged). | Sharpening #2 | MUST |
| NFR-INF-007 | The budget guard MUST be fail-closed by construction: the order is estimate → cap-check → (only then) network call. The cap check is NOT permitted to run only after the call. | RISK-INF-002 | MUST |

## 7. Proposed `.env.example` additions

```dotenv
# OpenRouter Inference Path (Slice 1) — extends the OD-3 Council backend.
# Never commit real secrets in .env.example.

# Per-run budget cap. TOKEN-ONLY this slice.
# !!! WARNING: THIS IS A TOKEN CAP, NOT A USD / SPEND GUARD. !!!
# An expensive model can cost real money even within 20000 tokens. There is NO
# USD cap in this slice. Choose your model and cap with that in mind.
COUNCIL_MAX_TOKENS_PER_RUN=20000

# Inference model. FREE model by default, but configurable to ANY OpenRouter model id.
# The free model is NOT guaranteed stable — its availability is verified at runtime
# (catalog/probe), never hardcoded as truth (see OD-3 NGOAL-B-002 / CAN-B-010).
COUNCIL_INFERENCE_MODEL=

# Reused from OD-3:
OPENROUTER_API_KEY=
COUNCIL_TIMEOUT_SECONDS=45
```

> Note: exact variable names (`COUNCIL_INFERENCE_MODEL`, the per-call `max_tokens`
> knob) are an ADR-level implementation detail the planner/coder may refine, provided
> the token-only cap default of 20000, the loud USD warning, and the configurable-model
> + runtime-verified-availability semantics are preserved.

## 8. Acceptance Criteria (Given / When / Then)

### AC-INF-001: Explicit max_tokens is sent
Given a caller invokes the inference function with a model id and messages
When the request body is built
Then it contains an explicit `max_tokens` field, and the estimate used for the cap is `input_token_estimate + max_tokens`

### AC-INF-002: Cap enforced BEFORE the network call (fail-closed)
Given `COUNCIL_MAX_TOKENS_PER_RUN=20000` and an estimate `> 20000`
When the inference function runs
Then it aborts with `COUNCIL_BUDGET_EXCEEDED` and makes NO network call (proven offline with a fake transport asserting zero calls)

### AC-INF-003: Within-cap proceeds
Given an estimate `<= COUNCIL_MAX_TOKENS_PER_RUN`
When the inference function runs against a fake transport returning a valid completion
Then it performs exactly one POST and returns the completion text

### AC-INF-004: Dry-run spends nothing
Given dry-run mode is requested
When the inference function runs
Then it returns the approximate (`≈`) estimate and makes NO network call (0 credits)

### AC-INF-005: Post-call reconciliation against usage
Given a fake transport returns a completion with `usage.prompt_tokens` and `usage.completion_tokens`
When the call completes
Then the result reconciles the approximate estimate against those real `usage` counts and surfaces both

### AC-INF-006: 402 classified as insufficient credit
Given the transport raises HTTP 402
When the inference function runs
Then it returns `COUNCIL_INSUFFICIENT_CREDIT` (not a generic unavailable), with no raw traceback and no key leak

### AC-INF-007: 429 classified as rate-limited, no auto-retry
Given the transport raises HTTP 429 with a `Retry-After` header
When the inference function runs
Then it returns `COUNCIL_RATE_LIMITED`, records the `Retry-After` value, and does NOT auto-retry (the fake transport asserts exactly one call)

### AC-INF-008: 5xx / other classified as unavailable
Given the transport raises HTTP 500 (or any other non-2xx not 402/429)
When the inference function runs
Then it returns `COUNCIL_MODEL_UNAVAILABLE`

### AC-INF-009: Timeout classified
Given the transport raises a connection error or socket timeout
When the inference function runs
Then it returns `COUNCIL_TIMEOUT`

### AC-INF-010: Malformed response classified, not crashed
Given the transport returns non-JSON or a JSON body missing the expected completion/usage shape
When the inference function runs
Then it returns `COUNCIL_MODEL_UNAVAILABLE` (classified, exit-0, no traceback)

### AC-INF-011: Secret redaction
Given `OPENROUTER_API_KEY` is set
When config, results, or any error are produced
Then the raw key never appears anywhere in output

### AC-INF-012: Missing key fail-closed
Given `OPENROUTER_API_KEY` is absent and a real (non-dry-run) call is requested
When the inference function runs
Then it returns `COUNCIL_MISSING_SECRET` with no env dump and no network call

### AC-INF-013: Configurable model, free default, runtime-verified
Given `COUNCIL_INFERENCE_MODEL` is unset
When the inference function resolves the model
Then it defaults to the configured free model id and treats its availability as runtime-verified (not asserted true), and a user-set value overrides it for any OpenRouter model id

### AC-INF-014: Offline suite spends nothing
Given the full offline suite (`run_all.sh`) runs with no network and no real key
When all inference tests execute
Then they are green and spend 0 credits (`integration-fake`)

### AC-INF-015: Opt-in smoke classifies, never crashes
Given the opt-in smoke is run with the env flag set and a real key against the configured (free-by-default) model
When the smoke executes
Then it either returns a non-empty completion (invocability proven for THAT model only) OR a classified error code (e.g. `COUNCIL_INSUFFICIENT_CREDIT` / `COUNCIL_RATE_LIMITED`), with leak-check = 0; a free-model 402/429 is a classified result, not a code failure

### AC-INF-016: External contract verified at smoke (not from memory)
Given the smoke runs against the live API
When the response is parsed
Then the actual `chat/completions` request/response shape and the `usage` fields the reconciliation relies on are confirmed and recorded; until then the contract stays `ungeprüft` and is not a finalized PRD premise

### AC-INF-017 [DEFERRED — Slice 3, forward criterion, NOT Slice-1 scope]: Diversity value is measured, not asserted
Given the multi-model council is wired for real (Slice 3)
When the diversity value of uncorrelated cognition is evaluated
Then Slice 3 MUST report a Claude-only vs multi-model catch-rate / cry-wolf delta (owner: retro-analyst / metrics). Recorded here so the "uncorrelated cognition is valuable" premise stays falsifiable; it is explicitly OUT of Slice-1 scope.

## 9. Evidence Requirements

| ID | Evidence | Required For | Evidence-class (target) |
|---|---|---|---|
| EV-INF-001 | Offline test output: explicit-`max_tokens` build, estimate = input+max_tokens, dry-run no-call, cap fail-closed BEFORE call (zero-call assertion). | REQ-INF-004..008, AC-INF-001..004 | integration-fake |
| EV-INF-002 | Offline test output: distinct classified codes for 402 / 429(+Retry-After, no retry) / 5xx / timeout / malformed; no-auto-retry assertion. | REQ-INF-012, REQ-INF-013, AC-INF-006..010 | integration-fake |
| EV-INF-003 | Offline reconciliation test: approximate estimate reconciled against fake `usage` counts. | REQ-INF-009, AC-INF-005 | integration-fake |
| EV-INF-004 | Redaction test: raw key never in any output (config/result/error). | NFR-INF-001, AC-INF-011, AC-INF-012 | integration-fake |
| EV-INF-005 | `.env.example` review: token-only cap default 20000, LOUD USD warning, key present-and-empty, `.env` gitignored. | NFR-INF-004, NFR-INF-005, CAN-INF-EVN-002 | n/a (doc review) |
| EV-INF-006 | ONE opt-in real-boundary smoke against `POST .../chat/completions` with the configured (free-by-default) model → non-empty completion OR classified code, leak-check = 0, recorded in `docs/benchmarks/2026-06-19-openrouter-inference-smoke.md`. | REQ-INF-016, REQ-INF-017, AC-INF-015 | real-boundary-smoke (that ONE model only) |
| EV-INF-007 | External-API contract verification at the smoke (OQ-3): real request/response shape + `usage` fields confirmed and recorded; absence/presence of any `cost` field noted. | REQ-INF-018, AC-INF-016, CAN-INF-EVN-004 | real-boundary-smoke |
| EV-INF-008 | Reality Ledger entry: offline = `integration-fake`; invocability = `real-boundary-smoke` for the probed model ONLY; broader invocability + estimate accuracy stay `RED(confidence)` unless the user reclassifies at the acceptance gate. | CAN-INF-EVN-005, RISK-INF-006 | mixed (see entry) |

## 10. Risks and Edge Cases

| ID | Edge Case | Expected Behavior |
|---|---|---|
| EDGE-INF-001 | `OPENROUTER_API_KEY` missing and a real call requested | `COUNCIL_MISSING_SECRET`, no env dump, no network call |
| EDGE-INF-002 | Estimate exactly equals the cap | proceed (cap is "exceed" → abort; equal is within cap) — single deterministic boundary rule, exercised in tests |
| EDGE-INF-003 | Estimate exceeds the cap | `COUNCIL_BUDGET_EXCEEDED`, NO network call |
| EDGE-INF-004 | Request built without `max_tokens` | FORBIDDEN — the path must not issue a capped call without a sent `max_tokens` (REQ-INF-004); this is a build-time invariant, not a runtime branch |
| EDGE-INF-005 | HTTP 402 (no/insufficient credit) | `COUNCIL_INSUFFICIENT_CREDIT` |
| EDGE-INF-006 | HTTP 429 (rate limit), `Retry-After` present | `COUNCIL_RATE_LIMITED`, record `Retry-After`, no auto-retry |
| EDGE-INF-007 | HTTP 5xx / other non-2xx | `COUNCIL_MODEL_UNAVAILABLE` |
| EDGE-INF-008 | Connection failure / socket timeout | `COUNCIL_TIMEOUT` |
| EDGE-INF-009 | Non-JSON or wrong-shape response (no completion / no `usage`) | `COUNCIL_MODEL_UNAVAILABLE`, classified, no traceback |
| EDGE-INF-010 | Response has no `cost` field | NOT an error — `cost` is never assumed; reconciliation uses `usage` only (REQ-INF-018) |
| EDGE-INF-011 | Empty completion text returned (2xx, but content empty) | surfaced honestly; the smoke treats a non-empty completion as the invocability proof, so an empty body does NOT prove invocability |
| EDGE-INF-012 | Configured free model is itself unavailable at smoke time | classified (402/429/unavailable), still honest; does NOT crash and does NOT claim invocability |

## 11. Implementation Notes

- May extend `config/claude/lib/council_backend.py` OR add a sibling
  `config/claude/lib/council_inference.py` (both in the user-confirmed scope). Reuse OD-3
  helpers: the fixed-host POST pattern of `_fetch_catalog_ids`, the `Authorization`-only
  key handling, `_env_int` / `_env_truthy`, and the `CODE_*` family. Add the new inference
  codes (`COUNCIL_BUDGET_EXCEEDED`, `COUNCIL_INSUFFICIENT_CREDIT`, `COUNCIL_RATE_LIMITED`)
  and reuse `COUNCIL_TIMEOUT` / `COUNCIL_MODEL_UNAVAILABLE` / `COUNCIL_MISSING_SECRET`.
- **stdlib `urllib` only.** A capped call sends `max_tokens`; the estimate guard runs
  before `urllib.request.urlopen`. No SDK, no auto-retry loop.
- **The cap is only real because `max_tokens` is sent.** A token cap that does not bound
  the request's own output is unenforceable; REQ-INF-004 makes the sent `max_tokens` a
  build-time invariant, not an optional knob.
- **The estimate is approximate (`≈`), the cap is fail-closed, the reconciliation is
  real.** A pre-call estimate cannot perfectly predict billed tokens (tokenizer
  differences, actual output length); it is a guard, not a billing oracle. Honest
  disclosure required; the smoke is tiny to bound real exposure (RISK-INF-004).
- **Do not assume a response `cost` field** (`nicht behaupten`, OQ-3): reconcile on
  `usage.prompt_tokens` / `usage.completion_tokens` (`ableitbar` — OpenAI-compatible shape;
  stays `ungeprüft` until verify-at-smoke per I-1 / REQ-INF-018, NOT `belegt`), not on any
  cost field (`ungeprüft`). Verify the full shape at the smoke before freezing it as a premise.
- **`.env.example` LOUD USD warning is mandatory** — the cap is token-only; 20k tokens of
  an expensive model is real money. The warning is part of the acceptance evidence
  (EV-INF-005), not optional polish.
- **No hardcoded free-model truth.** Default to a free model, verify availability at
  runtime via catalog/probe (consistent with OD-3 NGOAL-B-002); the user may set any
  OpenRouter model id.
- **Reality Ledger.** Offline transport-fake tests stay `integration-fake`. Invocability
  is `real-boundary-smoke` for the ONE probed model only. Broader invocability ("all
  configured models work") and estimate accuracy stay `RED(confidence)` until the user
  reclassifies at the acceptance gate. RED may NOT be silently downgraded; OQ-3 may NOT
  be downgraded to a mere "documented risk" and forwarded as a working premise — it stays
  `ungeprüft` until the smoke confirms it.
- **Diversity value (Slice 3, deferred).** The value of uncorrelated cognition is
  *asserted*, not *measured*, in this slice. AC-INF-017 records the forward measurement
  obligation so the premise stays falsifiable; it is OUT of Slice-1 scope.

## 12. Definition of Done

- All MUST requirements (REQ-INF-001..018) satisfied.
- Offline tests green under `run_all.sh`: explicit-`max_tokens`, estimate, dry-run
  (no-call), cap fail-closed BEFORE call (zero-call asserted), distinct classified codes
  (402/429+no-retry/5xx/timeout/malformed), reconciliation against fake `usage`,
  redaction, missing-key fail-closed. 0 credits spent.
- `.env.example` updated: token-only cap default 20000 + LOUD USD warning + configurable
  model field; `.env` gitignored.
- The opt-in real smoke (outside `run_all.sh`, env-gated) recorded in
  `docs/benchmarks/2026-06-19-openrouter-inference-smoke.md`: non-empty completion OR
  classified code, leak-check = 0, and the OQ-3 contract verified and recorded.
- Traceability matrix updated (new slice `openrouter-inference`, carries `canvas-link` to
  `docs/canvas/openrouter-inference.canvas.md`).
- **DoD does NOT treat green offline tests as proof of real invocability.** Offline green
  = `integration-fake`; real invocability is earned ONLY by the smoke, for the one probed
  model, and broader invocability + estimate accuracy remain `RED(confidence)`.
- User confirmation at the Phase-0.5 / acceptance gate (Status flips to `user-confirmed`
  ONLY by the user). This PRD is `draft` until then.

## 13. Open Questions (carried from canvas)

| ID | Question | Status |
|---|---|---|
| OQ-1 | Per-run token cap default + whether to also enforce a USD cap. | RESOLVED (Ben, 2026-06-19): token-only, default `COUNCIL_MAX_TOKENS_PER_RUN=20000`, no USD cap this slice. |
| OQ-2 | Which model for the opt-in smoke. | RESOLVED (Ben, 2026-06-19): free model as default, user-configurable to any OpenRouter model id; availability runtime-verified, not hardcoded. |
| OQ-3 | OpenRouter `chat/completions` request/response contract (field names; `usage`/cost fields the estimate/reconciliation rely on). | OPEN — external-API premise, `ungeprüft`. Verify against the live API at build/smoke (REQ-INF-018, EV-INF-007, AC-INF-016). May NOT be a finalized premise nor downgraded to a "documented risk" until confirmed. |

## Spec-sanity carried constraints (Phase 0.7, 2026-06-19 — PROCEED, no BLOCKER)

The spec-auditor returned **PROCEED**. Three IMPORTANT findings are frozen here as binding
planner/coder constraints (verified at Phase-1 tests + Gate B/verification), not a re-audit:

- **I-1 (provenance):** `usage.prompt_tokens` / `usage.completion_tokens` is `ableitbar`
  (OpenAI-compatible shape), NOT `belegt` — stays `ungeprüft` until the smoke (EV-INF-007).
  Reconciliation (REQ-INF-009) MUST degrade gracefully (→ `COUNCIL_MODEL_UNAVAILABLE`) if
  `usage` is absent/misshaped.
- **I-2 (uncovered failure mode):** a HTTP **2xx whose body lacks a usable completion**
  (missing/empty `choices[].message.content`, or an `{"error":…}` body) raises no exception and
  parses as JSON → it MUST be classified `COUNCIL_MODEL_UNAVAILABLE` (deterministic, not a crash,
  not a false success). Folds into EDGE-INF-009/011.
- **I-3 (cap honesty):** `input_token_estimate` is an offline **heuristic** (`ableitbar`, not
  `belegt`) — OpenRouter bills on the provider's native tokenizer Plumbline cannot reproduce.
  Code MUST name the heuristic; reconciliation MUST also compare the input estimate against the
  real `usage.prompt_tokens` (not only total) so the heuristic's drift is MEASURED at the smoke
  and recorded. The hard pre-call enforceable bound is the SENT `max_tokens` (output); the input
  side is approximate — disclose both.

**Spec FROZEN** at this point (Phase 0.7 complete). No requirements-analyst remediation round was
triggered (no BLOCKER).
