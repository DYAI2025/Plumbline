# PRD: Foreign-Model Council Bodies + Character/Preset Composition for /concilium (Slice 2)

Feature-Slug: deepseek-review-agent
Slice: 2 of 4
Status: user-confirmed (Ben 2026-06-19; PRD + Vision confirmed together at the Phase-0 gate). Spec-remediation pass (Ben, 2026-06-19): BLOCKER-1 + HIGH-1/2 + MEDIUM-1/2 + Slice-1 stale-default applied in one pass, then frozen (no re-audit).
Owner: requirements-analyst
Canvas (confirmed): docs/canvas/deepseek-review-agent.canvas.md (Status: user-confirmed, Ben 2026-06-19)
Product Vision: docs/vision/deepseek-review-agent.vision.md (to be created by product-owner)
Traceability: docs/traceability.md (slice deepseek-review-agent; carries canvas-link)
Prefix: REQ-DS-*

> This PRD is bound to the confirmed Product Canvas above and may not be read apart from it.
> Every REQ traces to a CAN-DS-* / RISK-DS-* row. The honesty invariant is load-bearing:
> **Slice 2 delivers a CAPABILITY + INTEGRATION, not a measured VALUE.** A foreign body /
> character / preset really running and returning a real position is allowed; "it caught more
> / is more diverse / is uncorrelated" is the DEFERRED Slice-3 measurement (NGOAL-DS-003 /
> NGOAL-DS-011) and is NEVER claimed here.

---

## 0. Provenance & verified premises (`belegt`)

All foreign-file premises were opened and read on 2026-06-19 before becoming PRD premises
(gap rule / external-claim discipline). Classification: `belegt`.

| Premise | Verified artifact | Class |
|---|---|---|
| `run_inference(...)` entrypoint with injected `transport` seam (default `None` → 0 calls) | `config/claude/lib/council_inference.py:276` | belegt |
| Double live gate: `--live` AND `COUNCIL_INFERENCE_LIVE=1`, else `transport=None` | `config/claude/lib/council_inference.py:381,419-426` | belegt |
| Per-call token cap `DEFAULT_MAX_TOKENS_PER_RUN = 20000`, fail-closed `COUNCIL_BUDGET_EXCEEDED` before network | `config/claude/lib/council_inference.py:42,48` | belegt |
| Code family OK/BUDGET_EXCEEDED/MISSING_SECRET/INSUFFICIENT_CREDIT/RATE_LIMITED/MODEL_UNAVAILABLE/TIMEOUT | `config/claude/lib/council_inference.py:47-53` | belegt |
| Named input-token heuristic `estimate_input_tokens` + drift reconcile (I-3, `ableitbar`) | `config/claude/lib/council_inference.py:66,124,149` | belegt |
| Model resolution `--model > COUNCIL_INFERENCE_MODEL > free default` | `config/claude/lib/council_inference.py:220-224` | belegt |
| 2xx-no-completion / absent-usage → `COUNCIL_MODEL_UNAVAILABLE`, no body leak (I-1/I-2) | `config/claude/lib/council_inference.py:153-203` | belegt |
| Diversity gate `evaluate_gate` / `distinct_base_count` / `normalize_model_id` | `config/claude/lib/council_backend.py:101,125,152` | belegt |
| `evaluate_gate(config, reachable, fake_error)@152` reads a FULL config dict (`config["min_backends"]`, `config["backend"]`, `config["api_key_present"]`) — slots-coupled, NOT callable over a bare resolved-model list, NOT the preset entrypoint (HIGH-1) | `config/claude/lib/council_backend.py:152-179` | belegt |
| `distinct_base_count(reachable)` is the reusable preset primitive (≥2 distinct bases via `normalize_model_id`) | `config/claude/lib/council_backend.py:101,125` | belegt |
| Diversity disclosure: "necessary-not-sufficient guard (RISK-B-007); it does not prove real model diversity" lives in `concilium.md`, **NOT** in `council_backend.py` (HIGH-2 — citation corrected) | `config/claude/commands/concilium.md:104-107` | belegt |
| `_fetch_catalog_ids(api_key, timeout_seconds)`: ONE live GET to fixed `OPENROUTER_MODELS_URL` (no caller host → no SSRF), parses `data[].id`, raises `URLError`/`ValueError` for the caller to classify, never leaks the key — the catalog seam the resolver (REQ-DS-015) reuses | `config/claude/lib/council_backend.py:264-283` | belegt |
| NO free DeepSeek model in the live OpenRouter catalog (0 of 23 free); `meta-llama/llama-3.1-8b-instruct:free` (`council_inference.py:45`) no longer in catalog → hardcoded default is stale | live OpenRouter catalog check (Ben/analyst, 2026-06-19) + `council_inference.py:45` | belegt (catalog: `do-not-claim` that DeepSeek free exists) |
| Character library = 10 dirs, each with `references/role-contract.md`; `der-pruefer` present | `concilium/characters/*/references/role-contract.md` | belegt |
| XML system-prompt block: `## Direkt kopierbarer Systemprompt` heading then a fenced ` ```xml ` … ` ``` ` block | `concilium/characters/der-pruefer/references/role-contract.md:46-87`; `die-visionaerin/...:46-86` | belegt |
| `council_presets.py` absent (to be created); `concilium/presets.md` dropped (OQ-DS-4) | filesystem (verified absent) | belegt |

`ungeprüft` (must NOT be frozen as a brittle PRD premise): the EXACT live-model response
shape (RISK-DS-003 / CAN-DS-EVN-004) — confirmed only at the smoke; policy is fixed (prose,
no enforced JSON), exact shape stays `ungeprüft`.

---

## 1. Scope summary

A NEW council-body-runner (`config/claude/lib/deepseek_review.py`) plus a NEW typed presets
module (`config/claude/lib/council_presets.py`) that:
1. load a council body prompt (`concilium/<body>.md`) OR a CHARACTER (extract the ` ```xml `
   system-prompt block from `concilium/characters/<slug>/references/role-contract.md`),
   combine with the subject → `messages` array;
2. resolve a named PRESET (A/B/C, default A) → roles → character slugs → per-role models;
3. resolve the DEFAULT model dynamically (REQ-DS-015): a NAMED preference-ordered free-model
   resolver over the LIVE catalog (DeepSeek v4 → Qwen3.x → Kimi K2.7 → Kimi K2.6 → GLM 5.x →
   OpenRouter free-routing), reused only when no explicit `--model`/per-role/env override is set;
4. apply the OD-3 `distinct_base_count` primitive over the resolved model set (≥2 distinct bases);
5. delegate every real call to the Slice-1 `run_inference(...)` path (reused, not
   reimplemented): per-call token cap, key-safety, classified codes, double live gate;
6. wire `/concilium` (`concilium.md`, `integration-fake`) to route a body through the runner;
7. fix Slice-1's stale default (REQ-DS-016) so its own live path does not dead-end.

REUSED, NOT reimplemented (NGOAL-DS-005): transport, key-safety, budget cap, classified
`COUNCIL_*` family, live gate (`council_inference.py`); diversity gate (`council_backend.py`).

---

## 2. Requirements

### REQ-DS-001 — Council body-prompt loading → messages (CAN-DS-009/018, CAN-DS-EVN-001)
The runner reads a body prompt from `concilium/<body>.md` (READ-ONLY) and combines it with
the subject into an OpenAI-style `messages` array (system = body prompt, user = subject).

- **Given** a valid body name resolving to an existing `concilium/<body>.md`
  **When** the runner builds messages for a subject
  **Then** it returns `messages = [{role:"system", content:<body prompt>}, {role:"user", content:<subject>}]`, 0 network calls (injected transport / `transport=None`).
- **Given** a body name that does not resolve to a readable file
  **When** the runner attempts to load it
  **Then** it returns a named classified error (`prompt-missing` class, reusing `council_backend.load_prompt` semantics), never a fabricated prompt, never a different body.
- **Given** a body name containing a path separator / traversal / absolute path
  **When** the runner validates it
  **Then** it rejects it BEFORE any filesystem read (slug-only, realpath-containment), returning the missing/classified error.

### REQ-DS-002 — Character XML system-prompt extraction (CAN-DS-CHR-020/027, CAN-DS-EVN-CHR-008, RISK-DS-CHR-012)
For a character slug, the runner opens `concilium/characters/<slug>/references/role-contract.md`
(READ-ONLY) and extracts the FIRST fenced ` ```xml ` … ` ``` ` block under the
`## Direkt kopierbarer Systemprompt` heading; that XML is the body system prompt.

- **Given** a valid slug whose role-contract has the heading + one well-formed ` ```xml ` block
  **When** the runner extracts
  **Then** it returns the exact XML block content as the system prompt and builds `messages` with the subject; 0 network calls.
- **Given** a missing character directory OR missing `references/role-contract.md`
  **Then** a named classified error (`character-missing`), never a fabricated prompt, never a substituted character.
- **Given** the heading `## Direkt kopierbarer Systemprompt` is absent
  **Then** a named classified error (`xml-block-missing`), no fabrication.
- **Given** a malformed/unclosed ` ```xml ` fence, OR an empty extracted block
  **Then** a named classified error (`xml-block-malformed` / `xml-block-empty`), no fabrication, no silent truncation.
- **Given** a slug with a path separator / traversal
  **Then** rejected before any read (slug-only validation), classified error.

> Robustness floor (RISK-DS-CHR-012): a missing/malformed/empty block NEVER yields a partial,
> wrong, or empty system prompt presented as valid — it always classifies and refuses.

### REQ-DS-003 — Typed presets module (CAN-DS-PRE-021, OQ-DS-4 RESOLVED)
Presets live in `config/claude/lib/council_presets.py` as typed, importable Python — **NO
markdown-parse layer**. Each preset = an ordered list of roles; each role = `{role_name,
character_slug, model (optional)}`.

- **Given** the module is imported
  **Then** it exposes at least presets A/B/C with default = A:
  - **A "Maximale Produktspannung"** = Visionaerin · Pruefer · Nutzeranwalt · Macherin
    (slugs: `die-visionaerin`, `der-pruefer`, `der-nutzeranwalt`, `die-macherin`)
  - **B "Software-Architektur & Risiko"** = Systemdenker · Risiko-Waechterin · Macherin · Minimalist
    (slugs: `der-systemdenker`, `die-risiko-waechterin`, `die-macherin`, `der-minimalist`)
  - **C "Kontroverse & neue Ideen"** = Visionaerin · Provokateur · Uebersetzerin · Marktschaerferin
    (slugs: `die-visionaerin`, `der-provokateur`, `die-uebersetzerin`, `die-marktschaerferin`)
- **Given** each role
  **Then** its `model` field is OPTIONAL; unset → a free OpenRouter default at resolution time.
- **Given** preset A
  **Then** all four slugs resolve against the committed library (der-pruefer present, roster=10; RISK-DS-PRE-013 RESOLVED).

### REQ-DS-004 — Preset resolution, fail-closed (CAN-DS-PRE-028, CAN-DS-EVN-PRE-009, RISK-DS-PRE-013/014/015)
`--preset <name>` resolves each role → character slug → model, preserving role order.

- **Given** a known preset whose roles all resolve
  **When** resolved
  **Then** it returns an ordered list of `{role_name, character_slug, model, prompt_source}` with role ordering preserved; 0 network calls.
- **Given** an unknown preset name
  **Then** fail-closed with a distinct named error (`unknown-preset`), no silent default.
- **Given** a role naming a character slug not in the library
  **Then** fail-closed with a distinct named error (`unknown-character-slug`), never drop the role, never substitute a character, **never silent Claude-fallback**.
- **Given** a role whose model cannot be resolved (no per-role field, no env, and no free default available at runtime)
  **Then** fail-closed with a distinct named error (`model-unresolvable`), never silent fallback.

> **FORBIDDEN (RISK-DS-PRE-015, hard rule):** silent Claude substitution. If a role cannot
> run foreign, the runner returns its classified `COUNCIL_*` code; ANY fallback is DISCLOSED
> in output (model id + that it is a fallback). The default behavior is fail-closed.

- **FALSIFYING (MEDIUM-1) — Given** any unresolvable role (unknown slug / model-unresolvable /
  foreign model unavailable)
  **Then** the result object contains the named `COUNCIL_*` / `unknown-character-slug` /
  `model-unresolvable` code AND contains **NO model id outside the resolved foreign set** — i.e.
  **no Claude-family id** (no `anthropic/*`, no `claude-*`) anywhere in the returned structure.
  A test asserts the runner has **NO Claude-fallback code path**: grepping the runner source for a
  Claude-family model literal in any fallback branch returns zero, and an injected
  all-roles-unavailable preset yields only classified codes with zero Claude-family ids in output.
  This is FALSIFYING (fails if a Claude-fallback path is ever added), not narrative.

### REQ-DS-005 — Per-role model resolution precedence (CAN-DS-PRE-022, OQ-DS-5 RESOLVED)
Per role: **per-role `model` field > env override > free default**. Availability is
runtime-verified, never hardcoded as stable truth.

- **Given** a role with a `model` field set
  **Then** that model is used (highest precedence).
- **Given** a role with no `model` field but a matching env override present
  **Then** the env override is used.
- **Given** a role with neither
  **Then** the free OpenRouter default is used.
- **Given** any resolved model
  **Then** the resolution NEVER asserts the model is reachable; reachability is confirmed only at the live boundary (smoke), and an unreachable model classifies a `COUNCIL_*` code.

> NOT the positional `COUNCIL_1..4_MODEL` slots — a preset is a self-contained reproducible
> composition (OQ-DS-5 rationale): no coupling to env ordering; works for >4 / named roles.

### REQ-DS-006 — Diversity check over the resolved preset (CAN-DS-PRE-023/025, RISK-DS-PRE-016, RISK-DS-004) — HIGH-1 CORRECTED
After resolution, apply the OD-3 primitive `council_backend.distinct_base_count([...resolved
models])` (with `council_backend.normalize_model_id`) over the resolved model set; threshold
**≥2 distinct normalized base models** to proceed, `COUNCIL_DIVERSITY_UNAVAILABLE` on `<2`.

> **HIGH-1 (binding):** `evaluate_gate(config, reachable, fake_error)@152` is **NOT reused for
> presets.** It needs a FULL config dict and is built around the positional `COUNCIL_n_MODEL`
> env slots that OQ-DS-5 rejected — it is not callable over a bare resolved-model list.
> `evaluate_gate@152 exists, but slots-coupled — not the preset entrypoint.` The actually-reusable
> primitive is `distinct_base_count` + `normalize_model_id`; this REQ uses exactly that.

- **Given** a resolved preset with ≥2 distinct normalized base models (via `distinct_base_count`)
  **Then** the check proceeds (`COUNCIL_DIVERSITY_OK`).
- **Given** a resolved preset collapsing to <2 distinct normalized base models
  **Then** the check aborts `COUNCIL_DIVERSITY_UNAVAILABLE`, surfaced not hidden.
- **Given** any proceed result
  **Then** the disclosure carries RISK-B-007 verbatim, quoting the canonical wording from
  `config/claude/commands/concilium.md:104-107` (HIGH-2 — the real source; this wording is **NOT**
  in `council_backend.py`): *"This is a **necessary-not-sufficient** guard (RISK-B-007); it does
  **not** prove real model diversity."* The check is a STRUCTURAL floor only, not proof of
  perspective diversity (distinct model ids ≠ uncorrelated cognition).

### REQ-DS-007 — Position wrapping (CAN-DS-009/018, RISK-DS-003)
On a completion, the runner returns the body/character's real position as the model's PROSE
text, wrapped with the model id + prompt source (+ character slug for character bodies). No
enforced structured-JSON.

- **Given** an injected model completion (offline)
  **When** wrapped
  **Then** the result discloses `{position: <prose>, model: <id>, prompt_source: <concilium/<body>.md OR character slug+role-contract path>}`.
- **Given** a malformed / empty / refused / 2xx-no-completion response
  **Then** `COUNCIL_MODEL_UNAVAILABLE` (reused), never crash, never fabricate a position, never sell an empty body as a real position.

### REQ-DS-008 — Budget semantics: PER-CALL cap, no aggregate cap (CAN-DS-010/016, RISK-DS-006, RISK-DS-PRE-017, OQ-DS-6)
The token cap (`COUNCIL_MAX_TOKENS_PER_RUN`, reused) is enforced **PER inference CALL (per
role)**, fail-closed BEFORE the network call, via `estimate_total_tokens = input_token_estimate
+ max_tokens`.

- **Given** a single role whose input estimate + max_tokens exceeds the cap
  **When** the runner checks before any call
  **Then** it returns `COUNCIL_BUDGET_EXCEEDED` BEFORE any network call (proven offline). No chunking (NGOAL-DS-006).
- **Given** a full preset = N roles = N calls
  **Then** total spend is up to N× the per-call cap; **there is NO preset-level aggregate cap in this slice** — a known, accepted property (Ben, 2026-06-19, OQ-DS-6). An aggregate cap is a possible later slice.
- **Given** any per-role call
  **Then** it independently fails closed on its own cap / credit / rate / timeout — one role's failure neither consumes nor fakes the others.

> Explicit budget statement (load-bearing): per-call cap only; full preset = N× cap total; no
> aggregate cap this slice; each per-role call fail-closed on its own.
>
> **MEDIUM-2 (load-bearing, couples to BLOCKER-1):** the no-aggregate-cap property is only
> **~$0-bounded while the resolved models are free-tier**. A paid override (e.g. paid DeepSeek)
> × a large preset has **NO aggregate ceiling this slice** — accepted, user-disclosed, and never
> auto-selected: the dynamic resolver (REQ-DS-015) only ever auto-picks a `:free` model, so a
> paid model can enter only via an explicit `--model`/env/per-role override.

### REQ-DS-009 — Live gate, OFF by default (CAN-DS-012, RISK-DS-009, reused)
Real network calls fire ONLY with `--live` AND `COUNCIL_INFERENCE_LIVE=1`. Default
`transport=None` → 0 network calls.

- **Given** neither / only one of (`--live`, `COUNCIL_INFERENCE_LIVE=1`)
  **Then** `transport=None`, 0 network calls (offline-classified path).
- **Given** both
  **Then** the one real POST per call is armed.
- **A test asserts the gate is OFF by default** (offline) — `run_all.sh` makes ZERO live calls.

### REQ-DS-010 — Offline test suite, `integration-fake`, 0 credits (CAN-DS-014/025, CAN-DS-EVN-001/CHR-008/PRE-009)
All of the following are exercised network-free via the injected transport seam, 0 credits,
green under `run_all.sh` (`config/claude/tests/test_deepseek_review.sh`):
character XML extraction (valid + all failure branches); body-prompt loading; preset
resolution + ALL fail-closed branches (unknown-preset, unknown-character-slug,
model-unresolvable); per-role model resolution precedence; diversity check over resolved set via
`distinct_base_count` (proceed + <2-bases abort); position-wrapping (model id + prompt source);
budget fail-closed per call; key leak-check (key never in any output); live-gate-off-by-default;
**the dynamic resolver (REQ-DS-015) over an INJECTED fake catalog id list — each family-priority
branch, the skip-unavailable-family path, the OpenRouter-free-route fallback, precedence, and
fail-closed on unreachable (injected) catalog**; **the FALSIFYING no-Claude-fallback assertion
(MEDIUM-1).**

- **Given** the offline suite runs
  **Then** every branch above is asserted, 0 network calls, key absent from all output, green under `run_all.sh`.
- **FALSIFYING (MEDIUM-1):** the suite FAILS if a Claude-fallback path is ever added — no
  Claude-family model id (`anthropic/*`, `claude-*`) in any classified-failure output for an
  all-unavailable injected preset, and no Claude-family literal in any runner fallback branch.

### REQ-DS-011 — Opt-in FULL-preset live smoke → real-boundary-smoke (CAN-DS-PRE-026, CAN-DS-EVN-PRE-010, OQ-DS-6 USER OVERRIDE)
ONE opt-in smoke runs a **FULL preset (all 4 roles) live** (`--live` + `COUNCIL_INFERENCE_LIVE=1`)
on a tiny subject; lives OUTSIDE `run_all.sh`; recorded in
`docs/benchmarks/2026-06-19-deepseek-review-smoke.md`.

- **Given** both live gates set and a tiny subject
  **When** the smoke runs the full preset
  **Then** each role returns its real prose position OR its own cleanly-classified `COUNCIL_*` code; leak-check = 0 across all calls; the benchmark records each role's model id + character slug + classified result.
- **Then** it earns `real-boundary-smoke` for **that full-preset run** (each role/character/model run for real) — USER OVERRIDE accepted: 4 live calls = 4× token spend; bounded per call; free default ~$0.
- **Then** the benchmark explicitly records what it does NOT prove: no catch-rate, no cry-wolf, no proven diversity, no quality lift (CAN-DS-EVN-007, RISK-DS-001/002).
- **Given** the smoke construction
  **Then** the subject/prompt are fixed independently of any expected position (RISK-DS-005: never hand-feed the instrument it measures).

### REQ-DS-012 — `/concilium` wiring is `integration-fake` (CAN-DS-019, CAN-DS-EVN-005, RISK-DS-011)
`config/claude/commands/concilium.md` is edited for orchestration WIRING ONLY (route a body
through the runner). Live orchestrator obedience is NOT proven by code.

- **Given** the `concilium.md` edit
  **Then** it instructs routing a body through `deepseek_review.py`; this is recorded as `integration-fake` in the Reality Ledger, distinct from the `real-boundary-smoke` full-preset run. The four body prompts (`concilium/*.md`) stay READ-ONLY (NGOAL-DS-008); `concilium/characters/**` stays READ-ONLY (NGOAL-DS-009).

### REQ-DS-013 — Key safety, no new surface (CAN-DS-010, RISK-DS-008, reused)
The runner adds NO new key-handling surface: `OPENROUTER_API_KEY` is read as boolean presence
only and used ONLY inside the reused `run_inference(...)` Authorization header.

- **Given** any subcommand / result / error
  **Then** the raw key value NEVER appears in output, logs, or returned structures; a leak-check test asserts 0 occurrences.

### REQ-DS-014 — `.env.example` documentation (CAN-DS-EVN-002)
- **Given** any NEW env variable introduced (e.g. a per-role model env override naming scheme)
  **Then** it is documented in `.env.example`; reused budget/key vars present; `.env` stays gitignored.

### REQ-DS-015 — Dynamic default-model resolution (CAN-DS-RES-029, CAN-DS-EVN-RES-012, RISK-DS-007, BLOCKER-1 RESOLVED)
The DEFAULT model is resolved AT RUNTIME by a DYNAMIC, CATALOG-AWARE, PREFERENCE-ORDERED
free-model resolver. It walks a NAMED, editable preference-ordered FAMILY list and picks the
first family that is available as `:free` in the LIVE OpenRouter catalog; if none is
free-available, it falls back to OpenRouter free-model routing (any available `:free` catalog id,
or `openrouter/auto`). The resolver is ONLY the fallback when no explicit model is set.

- **Given** the resolver module is imported
  **Then** the preference list is a NAMED, editable constant of family/version match patterns, in
  order: **1. DeepSeek v4 · 2. Qwen3.x · 3. Kimi K2.7 · 4. Kimi K2.6 · 5. GLM 5.x** — each matched
  against `:free` catalog ids.
- **Given** model resolution for a role or the global default
  **Then** precedence is **explicit per-role/`--model` field > env override > dynamic resolver**;
  the resolver runs ONLY when no explicit model is set.
- **Given** the live catalog reachable (or, offline, an INJECTED fake catalog id list)
  **When** the resolver runs
  **Then** it reuses `council_backend._fetch_catalog_ids` (fixed OpenRouter host → **no new SSRF
  surface**), and is **injectable for offline tests** (inject a fake catalog id list → **0 network
  calls, 0 credits**).
- **Given** an injected catalog where DeepSeek-v4-`:free` is present
  **Then** the resolver picks the DeepSeek `:free` id (DeepSeek is the TOP preference when
  free-available).
- **Given** an injected catalog where DeepSeek is absent but Qwen3.x-`:free` is present
  **Then** the resolver SKIPS DeepSeek and picks the Qwen3.x `:free` id (the
  "skip-unavailable-family" path). (Today's REAL catalog: 0 free DeepSeek → DeepSeek is skipped.)
- **Given** an injected catalog where NONE of the five families is `:free`
  **Then** the resolver falls back to OpenRouter free-model routing (an available `:free` catalog
  id, or `openrouter/auto`).
- **Given** the catalog is unreachable (injected error, or live failure)
  **Then** the resolver **fails closed** with a classified `COUNCIL_*` code — it does **NOT**
  silently pick a stale/unverified model. Availability is runtime-verified, NEVER assumed.
- **Given** any auto-selection
  **Then** the resolver only ever auto-selects a `:free` model. **Paid DeepSeek (or any paid id) is
  never auto-selected** — it can enter only via an explicit `--model`/env/per-role override (couples
  to REQ-DS-008 MEDIUM-2: ~$0 free-tier budget bound).
- Offline tests assert each family-priority branch, the skip-unavailable-family path, the
  OpenRouter-free-route fallback, the precedence ladder, and the fail-closed-on-unreachable path —
  all via injected catalog, 0 network calls, 0 credits (CAN-DS-EVN-RES-012); the LIVE catalog read
  is exercised only behind the existing double live gate, never in `run_all.sh`.

### REQ-DS-016 — Slice-1 stale-default fix (Slice-1 contract preserved, BLOCKER-1, user approved)
`council_inference.py:45` `DEFAULT_INFERENCE_MODEL = "meta-llama/llama-3.1-8b-instruct:free"` is
stale/unavailable in the live catalog, so Slice-1's own live path dead-ends. Slice 2 fixes it
EITHER by updating the constant to a currently-available free id, OR (cleaner) by routing Slice-1's
default through the new dynamic resolver (REQ-DS-015) — whichever PRESERVES the Slice-1 contract +
tests (no regression to cap / key / classified codes / live-gate / drift reconcile).

- **Given** the Slice-1 default resolution path (`--model > COUNCIL_INFERENCE_MODEL > free default`)
  **When** no `--model`/env is set
  **Then** it resolves to a currently-available free id (directly, or via REQ-DS-015), never the
  stale `meta-llama/llama-3.1-8b-instruct:free`.
- **Given** the full Slice-1 offline test suite
  **Then** it stays green — the cap, key-safety, `COUNCIL_*` codes, double live gate, and the
  input-token drift reconcile are unchanged (no regression). The fix is the only behavioral delta.

---

## 3. Carried constraints (Slice-1 spec-sanity, binding)

| ID | Constraint | REQ tie |
|---|---|---|
| I-1 | Usage block absent → `COUNCIL_MODEL_UNAVAILABLE`, NO fabricated token numbers. | REQ-DS-007 |
| I-2 | 2xx with no usable completion → `COUNCIL_MODEL_UNAVAILABLE`, NO response-body leak. | REQ-DS-007 |
| I-3 | The input-token estimate is a NAMED heuristic (`estimate_input_tokens`, `ableitbar`), NOT a billing oracle — disclosed as such; the smoke must not hand-feed it. | REQ-DS-008, REQ-DS-011 |

---

## 4. Non-functional requirements

| ID | NFR | Detail |
|---|---|---|
| NFR-DS-SEC-1 | Key safety | `OPENROUTER_API_KEY` presence-only, header-only, never logged/returned; leak-check test (REQ-DS-013). |
| NFR-DS-SEC-2 | Budget | Per-call token cap fail-closed before network; no aggregate cap this slice (stated, accepted); each call independently bounded (REQ-DS-008). |
| NFR-DS-SEC-3 | SSRF | No caller-supplied host; the only outbounds are the reused `run_inference(...)` to OpenRouter's fixed endpoint AND the resolver's reuse of `council_backend._fetch_catalog_ids` to the fixed `OPENROUTER_MODELS_URL` — **no new SSRF surface** (REQ-DS-015). Slug-only validation + realpath-containment for any filesystem read (REQ-DS-001/002). |
| NFR-DS-DET-1 | Determinism | Preset resolution, XML extraction, message-building, and the diversity gate are pure/deterministic and offline-testable; order-independent inputs → stable output. |
| NFR-DS-OUT-1 | No secret in output | No raw env dump; classified errors and positions carry no secret. |
| NFR-DS-ISO-1 | CI isolation | Live smoke OUTSIDE `run_all.sh`, double-gated; offline path makes 0 network calls (REQ-DS-009). |

---

## 5. Risks (links to canvas RISK-DS-*)

| REQ | Canvas risk(s) |
|---|---|
| REQ-DS-002 | RISK-DS-CHR-012 (brittle XML extraction) |
| REQ-DS-004 | RISK-DS-PRE-013 (unknown slug — RESOLVED for A), RISK-DS-PRE-014 (unknown preset), RISK-DS-PRE-015 (silent Claude-fallback FORBIDDEN — MEDIUM-1 falsifier) |
| REQ-DS-006 | RISK-DS-PRE-016 (<2 bases), RISK-DS-004 / RISK-B-007 (distinct ids ≠ uncorrelated; canonical wording from `concilium.md:104-107`, HIGH-2); `distinct_base_count` not `evaluate_gate` (HIGH-1) |
| REQ-DS-015 | RISK-DS-007 (free-model flakiness / preferred family may be absent — resolver runtime-verifies & fails closed) |
| REQ-DS-016 | RISK-DS-007 (stale default dead-ends Slice-1 live path) |
| REQ-DS-007 | RISK-DS-003 (response shape) |
| REQ-DS-008 | RISK-DS-006 (budget bypass), RISK-DS-PRE-017 (full-preset cost — accepted, per-call) |
| REQ-DS-009 | RISK-DS-009 (CI credit spend) |
| REQ-DS-011 | RISK-DS-001/002 (over-claim value), RISK-DS-005 (hand-feed), RISK-DS-007 (free-model flakiness) |
| REQ-DS-012 | RISK-DS-011 (integration-fake mistaken for live), RISK-DS-010 (scope creep) |
| REQ-DS-013 | RISK-DS-008 (key leak) |

---

## 6. Traceability stub (TRC-DS-* — REQ → evidence class)

> Full matrix maintained in `docs/traceability.md` (carries `canvas-link` to the confirmed
> canvas). Minimal stub here; expand at planning.

| TRC | REQ | Acceptance test (offline unless noted) | Evidence class |
|---|---|---|---|
| TRC-DS-001 | REQ-DS-001 | body-prompt load + missing + traversal | integration-fake |
| TRC-DS-002 | REQ-DS-002 | XML extract: valid + missing-dir + missing-heading + malformed-fence + empty | integration-fake |
| TRC-DS-003 | REQ-DS-003 | presets module import: A/B/C present, default A, slugs resolve | integration-fake |
| TRC-DS-004 | REQ-DS-004 | resolution: known OK + unknown-preset + unknown-slug + model-unresolvable (each named error) | integration-fake |
| TRC-DS-005 | REQ-DS-005 | precedence: field > env > free default | integration-fake |
| TRC-DS-006 | REQ-DS-006 | diversity gate: ≥2 proceed + <2 abort + RISK-B-007 disclosure | integration-fake |
| TRC-DS-007 | REQ-DS-007 | position wrap + malformed/empty/refused → MODEL_UNAVAILABLE | integration-fake |
| TRC-DS-008 | REQ-DS-008 | per-call budget fail-closed; full preset = N× cap, no aggregate | integration-fake |
| TRC-DS-009 | REQ-DS-009 | live gate OFF by default → 0 network calls | integration-fake |
| TRC-DS-010 | REQ-DS-010 | full offline suite green under run_all.sh | integration-fake |
| TRC-DS-011 | REQ-DS-011 | FULL-preset (4 roles) live smoke, leak-check=0, records non-claims | real-boundary-smoke (full-preset run) |
| TRC-DS-012 | REQ-DS-012 | concilium.md wiring | integration-fake |
| TRC-DS-013 | REQ-DS-013 | key leak-check = 0 | integration-fake |
| TRC-DS-014 | REQ-DS-014 | .env.example documents new vars | integration-fake |
| TRC-DS-015 | REQ-DS-015 | dynamic resolver over INJECTED catalog: each family branch + skip-unavailable + free-route fallback + precedence + fail-closed-on-unreachable; named editable preference constant; no-Claude-fallback falsifier | integration-fake |
| TRC-DS-016 | REQ-DS-016 | Slice-1 default resolves to an available free id (never stale); Slice-1 suite green, no cap/key/codes/live-gate/drift regression | integration-fake |

Reality Ledger floor (`docs/reality/deepseek-review-agent.evidence.jsonl`, authored in
Phase 3 / Gate C): one record per load-bearing REQ at its TRUE class — `integration-fake`
for all offline logic and the `concilium.md` wiring; `real-boundary-smoke` ONLY for the
full-preset live smoke (REQ-DS-011). The diversity/quality lift is NOT a Slice-2 evidence
record (Slice-3 deferred, NGOAL-DS-003/011). Do NOT raise any ledger class to clear a default
floor.

---

## 7. Out of scope (non-goals — see canvas §7)

NGOAL-DS-002 (GUI), NGOAL-DS-003/011 (diversity/quality lift measurement — Slice 3),
NGOAL-DS-004 (multi-model live fan-out beyond the one full-preset smoke, streaming,
multi-turn, tool-calling), NGOAL-DS-005 (re-implementing reused infra), NGOAL-DS-006
(chunking), NGOAL-DS-007 (credit management), NGOAL-DS-008 (editing `concilium/*.md`),
NGOAL-DS-009 (editing `concilium/characters/**`), NGOAL-DS-010 REVISED (any live call inside
`run_all.sh` — the suite stays 0-credit; full-preset-live in the OPT-IN smoke is now allowed
per OQ-DS-6).

---

## 8. Definition of Ready

- [x] Canvas user-confirmed (Ben, 2026-06-19) — docs/canvas/deepseek-review-agent.canvas.md
- [x] All foreign-file premises verified `belegt` (§0)
- [x] Every REQ-DS-* atomic, testable, traced to a CAN-DS-* / RISK-DS-* row
- [x] All OPEN QUESTIONS resolved (OQ-DS-1..7) — no remaining BLOCKER
- [x] Spec-auditor findings remediated in one pass (BLOCKER-1 → REQ-DS-015 dynamic resolver; HIGH-1 → REQ-DS-006 uses `distinct_base_count` not `evaluate_gate`; HIGH-2 → RISK-B-007 cited to `concilium.md:104-107`; MEDIUM-1 → falsifying no-Claude-fallback in REQ-DS-004/010; MEDIUM-2 → ~$0-only-while-free in REQ-DS-008; Slice-1 stale default → REQ-DS-016) — then FROZEN (no re-audit)
- [x] Allowed change scope machine-parseable, `concilium/presets.md` removed, scope-check passes (resolver lands in `council_presets.py`/`deepseek_review.py` — already in scope; no new module file)
- [x] Product Vision created + user-confirmed (product-owner) — Phase 0 completes only when BOTH PRD and Vision are user-confirmed (Vision §1 updated for the dynamic resolver in this remediation)
