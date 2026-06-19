# Product Canvas: Foreign-Model Council — Character/Preset Composition for /concilium (dynamic preference-ordered free-model resolver; DeepSeek the top preference when free-available)

Status: user-confirmed
Owner: requirements-analyst
Confirmed by user: yes
Confirmation date: 2026-06-19
Confirmation note: Ben confirmed the Phase-0.15 gate decisions (OQ-DS-4/5/6/7) on 2026-06-19; full-preset-live smoke override accepted; canvas confirmed user-confirmed. Spec-remediation (Ben, 2026-06-19): BLOCKER-1 RESOLVED by a new policy — the default model is a DYNAMIC, CATALOG-AWARE, PREFERENCE-ORDERED free-model resolver (REQ-DS-015), NOT a hardcoded "DeepSeek default". DeepSeek stays the TOP preference but only when free-available in the live catalog (currently it is NOT — 0 free DeepSeek ids), so the resolver skips to the next family; paid DeepSeek is ONLY ever an explicit override, never auto-selected.
Canvas file: docs/canvas/deepseek-review-agent.canvas.md
Feature-Slug: deepseek-review-agent
Slice: 2 of 4 (wire the Slice-1 inference path into `/concilium` so a council body runs on a real foreign OpenRouter model — uncorrelated, non-Claude cognition)

> The Product Canvas is a **mandatory pre-build value-alignment artifact**. `/agileteam`
> may not finalize the PRD or enter development until this canvas is filled in, saved,
> linked to PRD/Vision/traceability, and **explicitly confirmed by the user**.
>
> Allowed `Status` values: `draft` | `user-confirmed` | `blocked`. This canvas is
> **`user-confirmed`** (Ben, 2026-06-19). **No agent self-confirmed it** — the user
> explicitly confirmed the Phase-0.15 gate decisions. OQ-DS-1/2/3 were resolved at intake;
> OQ-DS-4/5/6/7 were resolved by the user at the Phase-0.15 gate (Ben, 2026-06-19) — see
> the Open Questions table. All product-critical gaps are now closed.

> **Provenance.** Inputs tagged `EXPLICIT (Ben, 2026-06-19)` come from the brainstorming
> gate / confirmed plan context — they are user-decisions, not agent assumptions. Inputs
> tagged `ASSUMPTION` are agent-derived and require user confirmation. Inputs tagged
> `OPEN QUESTION` are unresolved and are NOT guessed.

> **What this slice IS (the user's confirmed intent, OQ-DS-2 RESOLVED — Ben, 2026-06-19).**
> The integration target is **`/concilium`, NOT a standalone review CLI.** The real intent:
> bring foreign LLM agents (default model resolved dynamically by the preference-ordered
> free-model resolver — DeepSeek the top preference when free-available, else the next free
> family, else OpenRouter free-routing — or any explicitly-overridden OpenRouter model) into `/concilium` so
> the council's bodies actually run on **diverse foreign models instead of 4× Claude** —
> UNCORRELATED, non-Claude cognition that reduces shared bias blind spots and (the north-star
> goal) raises review/judgment quality. Slice 2 = wire the Slice-1 inference path
> (`config/claude/lib/council_inference.py`, `run_inference(...)`) into `/concilium` so a
> council body (or an optional foreign reviewer body) runs on a configurable OpenRouter model
> via a real completion — using that body's own prompt from `concilium/<body>.md` plus the
> subject — and returns the body's real position. It builds on OD-3's diversity gate
> (`config/claude/lib/council_backend.py`, ≥2 distinct normalized base models) and Slice 1's
> inference. (Verified against the repo: `/concilium` exists at
> `config/claude/commands/concilium.md`; the four body prompts are `concilium/market-realist.md`,
> `concilium/tech-arbiter.md`, `concilium/skeptic.md`, `concilium/distribution-realist.md`;
> the diversity gate `evaluate_gate` / `distinct_base_count` lives in `council_backend.py`.)

> **Honesty framing (this repo's invariant — explicit, load-bearing, user-understood).**
> The split between capability and measured value is the spine of this slice:
>
> - **Slice 2 delivers the CAPABILITY + INTEGRATION:** a `/concilium` body really runs on a
>   foreign (non-Claude) model and returns a real position. The evidence honestly splits:
>   - ONE opt-in real foreign-body run earns **`real-boundary-smoke`** for that ONE
>     body/model/run only;
>   - the `concilium.md` orchestration wiring is **`integration-fake`** — the markdown
>     *instructs* the orchestrator to route a body through the inference path; live obedience
>     by the orchestrator is unproven by code;
>   - all offline tests are **`integration-fake`** (injected transport, 0 credits).
> - **Slice 2 does NOT prove the QUALITY LIFT.** "A foreign agent catches more / reduces bias
>   blind spots / is genuinely uncorrelated" is the **DEFERRED Slice-3 measurement**
>   (Claude-only vs. multi-model catch-rate / cry-wolf delta; owner retro-analyst / metrics)
>   — the carried falsifier, and an explicit Non-goal here (NGOAL-DS-003).
>
> The Vision / value-prop state the GOAL — uncorrelated foreign perspective → fewer shared
> bias blind spots → higher review/judgment quality — as the **NORTH STAR**, while keeping the
> EVIDENCE honest: **capability now, measured value Slice 3.** The smoke must NOT hand-feed
> the value of an instrument it measures (Slice-1 retro rule): proving "a body ran on a foreign
> model and a real position came back" is allowed; asserting "the foreign body was better /
> more diverse" is forbidden here.

> **Relationship to Slice 1 (NOW ON MAIN).** This slice EXTENDS the already-merged
> OpenRouter inference path (`config/claude/lib/council_inference.py`, `run_inference(...)`,
> canvas `docs/canvas/openrouter-inference.canvas.md`). It reuses, unchanged: the
> `run_inference(...)` entrypoint + injected-transport seam; the token-only hard cap
> (`COUNCIL_MAX_TOKENS_PER_RUN`, default 20000, fail-closed BEFORE any network call); the
> key-safety discipline (`OPENROUTER_API_KEY` as boolean presence, raw value only in the
> `Authorization` header, never logged/returned); the classified `COUNCIL_*` code family
> (`OK / BUDGET_EXCEEDED / MISSING_SECRET / INSUFFICIENT_CREDIT / RATE_LIMITED /
> MODEL_UNAVAILABLE / TIMEOUT`); and the live gate (`--live` flag AND `COUNCIL_INFERENCE_LIVE=1`
> env, else `transport=None` → zero network calls). It also builds on OD-3's diversity gate
> in `council_backend.py` (`evaluate_gate` / `distinct_base_count`, ≥2 distinct normalized
> base models). Slice 2 wires a `/concilium` body ON TOP of these; it does NOT reimplement
> transport, budget, key handling, or the diversity gate.

> **SCOPE EXPANSION — Slice 2 now ALSO folds in the character library + role-composition
> presets (user decision, Ben, 2026-06-19).** The rows above (CAN-DS-001..019,
> RISK-DS-001..011) describe the SUBSTRATE: run one of the four existing `/concilium`
> bodies (`concilium/{market-realist,tech-arbiter,skeptic,distribution-realist}.md`) on a
> foreign model via the Slice-1 `run_inference(...)` path. The user decided to FOLD INTO
> this slice two further capabilities, captured in the new rows below (suffix `-CHR-*` and
> `-PRE-*`):
>
> 1. **Character loading.** The runner can load a CHARACTER from the committed library
>    `concilium/characters/<slug>/` as a runnable body. The body system prompt is the
>    fenced ` ```xml ` … ` ``` ` block under "## Direkt kopierbarer Systemprompt" in
>    `concilium/characters/<slug>/references/role-contract.md` — the runner EXTRACTS that
>    XML block and uses it as the body system prompt, combined with the subject.
>    (Verified against the repo: the block is a fenced ` ```xml ` region in
>    `concilium/characters/die-visionaerin/references/role-contract.md`.)
> 2. **Role-composition presets.** A named preset = a set of roles, each role mapped to a
>    character + a model (default = a free OpenRouter model). The three source presets
>    become loadable; `--preset <name>` resolves roles → character prompts → models, and
>    the OD-3 diversity gate (`council_backend.py` `evaluate_gate` / `distinct_base_count`,
>    ≥2 distinct normalized base models) checks the resolved set.
>
> **BLOCKER-1 REALITY — there is NO free DeepSeek model; the old hardcoded default is gone
> (verified against the live OpenRouter catalog + repo, Ben/analyst 2026-06-19, `belegt`/`do-not-claim`).**
> A live OpenRouter catalog check found **0 of 23 free models are DeepSeek** → "free DeepSeek
> default" is **`do-not-claim`**. Worse, Slice-1's hardcoded
> `DEFAULT_INFERENCE_MODEL = "meta-llama/llama-3.1-8b-instruct:free"`
> (`council_inference.py:45`, `belegt`) is **no longer in the catalog** → any hardcoded
> default goes stale. POLICY (Ben, 2026-06-19, BLOCKER-1 RESOLVED): the default model is
> resolved **AT RUNTIME** by a DYNAMIC, CATALOG-AWARE, PREFERENCE-ORDERED free-model
> resolver (new REQ-DS-015) that walks a NAMED, editable preference-ordered FAMILY list —
> **1. DeepSeek v4 · 2. Qwen3.x · 3. Kimi K2.7 · 4. Kimi K2.6 · 5. GLM 5.x** — matching each
> against `:free` ids in the LIVE catalog and picking the first free-available; **if none is
> free-available → fall back to OpenRouter free-model routing** (any available `:free`
> catalog id, or `openrouter/auto`). Resolution precedence: **explicit per-role/`--model`
> field > env override > dynamic resolver** (the resolver is ONLY the fallback when no
> explicit model is set). The resolver reuses `council_backend._fetch_catalog_ids`
> (`council_backend.py:264`, `belegt`; fixed OpenRouter host → no new SSRF surface) and is
> **injectable for offline tests** (inject a fake catalog id list → 0 network calls, 0
> credits). Availability is runtime-verified, NEVER assumed: if the catalog is unreachable
> the resolver **fails closed** with a classified `COUNCIL_*` code (never silently picks a
> stale/unverified model). DeepSeek stays the TOP preference but only when free-available
> (currently NOT → resolver skips to Qwen3.x…); **paid DeepSeek is ONLY ever used via an
> explicit `--model`/env/per-role override, never auto-selected** (it would incur cost). The
> feature-slug stays `deepseek-review-agent` (DeepSeek is the headline configurable model),
> but Slice 2 NO LONGER claims a realized "DeepSeek default."
>
> **VERIFIED-AGAINST-REPO FACTS (load-bearing, `belegt`).** Re-verified on 2026-06-19:
> - `concilium/characters/` contains **10** loadable character dirs, each with a
>   `references/role-contract.md`: `die-visionaerin`, `der-nutzeranwalt`, `die-macherin`,
>   `der-systemdenker`, `die-risiko-waechterin`, `der-provokateur`, `die-uebersetzerin`,
>   `der-minimalist`, `die-marktschaerferin`, **`der-pruefer`**.
> - **`der-pruefer` is NOW present in `concilium/characters/der-pruefer/`** (committed;
>   `references/role-contract.md` verified present, with the `## Direkt kopierbarer
>   Systemprompt` heading at line 46 and a fenced ` ```xml ` block at line 48). Preset A
>   ("Maximale Produktspannung") names **Pruefer** as a role → **preset A NOW fully
>   resolves against the committed library.** RISK-DS-PRE-013 is therefore RESOLVED and
>   OQ-DS-7 is closed (Ben, 2026-06-19) — der-pruefer was added upstream.
> - The diversity-gate entrypoints verified to exist in
>   `config/claude/lib/council_backend.py`: `normalize_model_id`, `distinct_base_count`,
>   `evaluate_gate`. **CAUTION (HIGH-1, `belegt`):** `evaluate_gate(config, reachable,
>   fake_error)@152` takes a FULL config dict (reads `config["min_backends"]`,
>   `config["backend"]`, `config["api_key_present"]`) and is built around the positional
>   `COUNCIL_n_MODEL` env slots that OQ-DS-5 rejected — it is **NOT callable over a bare
>   resolved-model list** and is **NOT** the preset entrypoint. For presets, reuse the
>   actually-reusable primitive `distinct_base_count([...resolved models])` (with
>   `normalize_model_id`); `evaluate_gate@152 exists, but slots-coupled — not the preset
>   entrypoint.`
> - **`_fetch_catalog_ids(api_key, timeout_seconds)` verified at
>   `config/claude/lib/council_backend.py:264`** (`belegt`): does the ONE live GET to the
>   fixed `OPENROUTER_MODELS_URL` (no caller-supplied host → no SSRF), parses `data[].id`,
>   raises `URLError`/`ValueError` for the caller to CLASSIFY, never leaks the key. This is
>   the catalog seam the new dynamic resolver (REQ-DS-015) reuses (injectable for offline
>   tests).
> - The Slice-1 inference contract verified in `config/claude/lib/council_inference.py`:
>   `run_inference(...)` with an injected `transport` seam (default `None` → 0 network
>   calls), the double live gate (`--live` AND `COUNCIL_INFERENCE_LIVE=1`), the per-call
>   token cap (`DEFAULT_MAX_TOKENS_PER_RUN = 20000`), the full `COUNCIL_*` code family,
>   and the named input-token heuristic `estimate_input_tokens` (I-3, `ableitbar`).
> - **No presets file exists yet** (`config/claude/lib/council_presets.py` absent) → it
>   will be CREATED by this slice. OQ-DS-4 is RESOLVED (Ben, 2026-06-19) =
>   `config/claude/lib/council_presets.py` (typed, importable Python; **NO markdown-parse
>   layer**); the `concilium/presets.md` alternative is DROPPED.
>
> **Honesty floor for the expansion (extends, does NOT relax, the existing one).**
> - Capability still ≠ value. **COST + smoke-depth rule (binding — USER OVERRIDE,
>   Ben 2026-06-19, OQ-DS-6):** the opt-in smoke runs a **FULL preset (all 4 roles)
>   LIVE** = 4 calls = 4× token spend, **ACCEPTED by the user**. This earns
>   `real-boundary-smoke` for **that full-preset run** (every role/character/model run for
>   real, real positions came back). The full-preset-live smoke proves the **CAPABILITY**
>   (a whole preset of foreign characters ran and real positions came back), NOT that it
>   caught more / is more diverse. Cost is bounded because: the free-model default keeps
>   it ~$0; **the token cap (`COUNCIL_MAX_TOKENS_PER_RUN`) applies PER CALL, so each of the
>   4 calls is independently bounded and fail-closed**; the smoke is opt-in, double-gated
>   (`--live` + `COUNCIL_INFERENCE_LIVE=1`), and lives OUTSIDE `run_all.sh`; per-role
>   failures are classified individually (a flaky free model on one role does NOT fake the
>   others — each role returns its own real position or its own `COUNCIL_*` code). The
>   **offline assembly** — role → character → model resolution, XML extraction,
>   diversity-gate check over the resolved set, role ordering, all fail-closed branches —
>   stays `integration-fake` (injected transport, 0 credits). `run_all.sh` MUST NOT make
>   any live call.
> - The diversity / quality LIFT ("a preset of foreign characters catches more / is
>   genuinely uncorrelated") remains the **DEFERRED Slice-3 measurement (NGOAL-DS-003 /
>   NGOAL-DS-011)**. The full-preset-live smoke proves the CAPABILITY, NOT the lift. Adding
>   presets and running a full preset live does NOT let Slice 2 claim it.
> - **RISK-DS-004 / OD-3 RISK-B-007 are reused verbatim:** distinct model ids ≠
>   uncorrelated cognition. A preset that resolves to N distinct characters on N distinct
>   model ids still does not prove uncorrelated cognition.

---

## 1. Problem

| ID | Field | Content | Status |
|---|---|---|---|
| CAN-DS-001 | Problem | `/concilium` convenes a multi-body council whose entire value rests on **diverse, uncorrelated perspectives under friction** — yet today every body runs on Claude-family cognition (effectively 4× Claude). A council where all bodies share the same model shares the same bias blind spots: the correlation the council exists to break is still present. Plumbline can now run a real, governed OpenRouter completion (Slice 1) and has a diversity gate that counts distinct base models (OD-3), but there is **no wiring that makes a `/concilium` body actually run on a real foreign (non-Claude) model**. So "diverse council" is aspirational — the foreign cognition is available but not plugged in. | EXPLICIT (Ben, 2026-06-19) |
| CAN-DS-002 | Why now | This is Slice 2 of 4, the next foundation layer: the real diversity-VALUE measurement (Slice 3) and the GUI (Slice 4) both depend on `/concilium` being able to run at least one body on a real foreign model through the governed inference path. Without this wiring, the diversity gate (OD-3) guards a council that is still single-cognition, and there is nothing for Slice 3 to measure. | EXPLICIT (Ben, 2026-06-19) |
| CAN-DS-003 | Honesty scope | The problem this slice solves is the *capability + integration gap* ("a `/concilium` body cannot run on a foreign model at all"), NOT the *value gap* ("does foreign cognition actually catch more / reduce blind spots"). Conflating the two is exactly the over-claim this canvas guards against; the value gap is the deferred Slice-3 measurement. | EXPLICIT (Ben, 2026-06-19) |

---

## 2. Target user / customer

| ID | User group | Need | Status |
|---|---|---|---|
| CAN-DS-004 | Plumbline maintainer / operator (Ben) | A real, governed way to make a `/concilium` body run on a foreign (non-Claude) model — the default model resolved by a dynamic preference-ordered free-model resolver (DeepSeek is the top preference when free-available and otherwise a configurable PAID override), any OpenRouter id — so the council brings genuinely uncorrelated cognition instead of 4× Claude, built on the Slice-1 inference path with the same hard budget and key-safety guardrails, exercisable without an unexpected bill (the resolver only ever auto-selects a `:free` model, never paid). | EXPLICIT (Ben, 2026-06-19) |
| CAN-DS-005 | Plumbline developer (Slice 3) | A stable, reusable council-body-runner that takes a body's prompt (`concilium/<body>.md`) + the subject, runs it on a configurable foreign model via `run_inference(...)`, and returns the body's real position (the model's PROSE position/review text, wrapped with model id + prompt source) — so the deferred diversity-VALUE measurement (Slice 3) has a real multi-model council to measure. | EXPLICIT (Ben, 2026-06-19) |
| CAN-DS-006 | Reviewer / auditor | Evidence that the capability is honestly classified: offline tests and the `concilium.md` orchestration wiring are `integration-fake`; ONE real foreign-body run is `real-boundary-smoke` for that ONE body/model/run only; and the diversity/quality-lift claim is explicitly NOT made here (deferred to Slice 3). | EXPLICIT (Ben, 2026-06-19) |

---

## 3. Current workaround

| ID | Content | Status |
|---|---|---|
| CAN-DS-007 | Today `/concilium`'s bodies all run on Claude-family cognition. The only OpenRouter capability that exists is the Slice-1 `council_inference.py` `run_inference(...)` path, which sends a generic `messages` array and returns a completion or a classified `COUNCIL_*` code — it is NOT yet called by `/concilium`, and `concilium.md` does NOT route any body through it. The OD-3 diversity gate in `council_backend.py` can *count* distinct base models but nothing *runs* a body on a foreign one. So getting a foreign-model perspective into the council is currently done by hand (copy/paste a body prompt into an external chat), with no budget guard, no key discipline, and no integration with the council flow. | EXPLICIT (Ben, 2026-06-19) |

---

## 4. Value proposition

| ID | Statement | Status |
|---|---|---|
| CAN-DS-008 | **NORTH STAR (goal, not yet measured).** `/concilium` runs its bodies on real foreign models → genuinely uncorrelated, non-Claude cognition → fewer shared bias blind spots → higher review/judgment quality. This is the *direction* the slice serves; the quality lift itself is the deferred Slice-3 measurement, not a Slice-2 claim. | EXPLICIT (Ben, 2026-06-19) |
| CAN-DS-009 | **DELIVERED CAPABILITY (Slice 2).** A `/concilium` body (or an optional foreign reviewer body) can run on a configurable foreign model via the Slice-1 `run_inference(...)` path: take the body's prompt from `concilium/<body>.md` + the subject → build a `messages` array → run on the dynamically resolved free model (preference-ordered free-model resolver, REQ-DS-015 — DeepSeek the top preference when free-available, else next family, else OpenRouter free-routing) / any explicitly-overridden OpenRouter model → return the body's real position as the model's **PROSE** position/review text, wrapped with the model id + prompt source. No enforced structured-JSON. | EXPLICIT (Ben, 2026-06-19) |
| CAN-DS-010 | It inherits Slice-1's guardrails for free: token-only hard cap (`COUNCIL_MAX_TOKENS_PER_RUN`, fail-closed before any network call), key-safety (`OPENROUTER_API_KEY` presence-only, header-only, never logged/returned), and the classified `COUNCIL_*` code family — so an oversized subject/diff or a credit/rate/timeout failure is handled deterministically, never by unbounded spend or a raw traceback. It also leans on OD-3's diversity gate (`council_backend.py`, ≥2 distinct normalized base models) so a configured council is checked for real model diversity. | EXPLICIT (Ben, 2026-06-19) |
| CAN-DS-011 | The DEFAULT model is resolved by a DYNAMIC, CATALOG-AWARE, PREFERENCE-ORDERED free-model resolver (REQ-DS-015), user-configurable to any OpenRouter model id. Resolution precedence: **explicit `--model`/per-role field > env override > dynamic resolver** (the resolver is ONLY the fallback when no explicit model is set). The resolver walks the named family list (DeepSeek v4 → Qwen3.x → Kimi K2.7 → Kimi K2.6 → GLM 5.x), matches each against `:free` ids in the LIVE catalog (reusing `council_backend._fetch_catalog_ids`), and falls back to OpenRouter free-routing if none is free-available; availability is runtime-verified, never hardcoded as stable truth, and an unreachable catalog fails closed with a classified `COUNCIL_*` code. DeepSeek is the top preference only when free-available (currently it is NOT → resolver skips it); paid DeepSeek is only ever an explicit override, never auto-selected. The exact response shape stays `ungeprüft` until the smoke; output is treated as prose, no structured-JSON is enforced. | EXPLICIT (Ben, 2026-06-19) |
| CAN-DS-012 | Tests stay offline / fake (0 credits): the body-prompt + subject → `messages` construction and the position-wrapping are exercised entirely offline via the Slice-1 injected-transport seam; the `concilium.md` orchestration wiring is `integration-fake`. Live invocability is proven by ONE opt-in tiny real foreign-body smoke OUTSIDE the offline suite. | EXPLICIT (Ben, 2026-06-19) |
| CAN-DS-013 | **This slice does NOT claim the diversity quality lift.** It claims only "a `/concilium` body really ran on a foreign model and returned a real position." Whether foreign cognition catches more / is genuinely uncorrelated is the deferred Slice-3 measurement. Stating the capability honestly while keeping the north star explicit (and refusing to over-claim) IS part of the value. | EXPLICIT (Ben, 2026-06-19) |
| CAN-DS-CHR-020 | **Character loading as a runnable body.** The runner can load any character from the committed library `concilium/characters/<slug>/` and run it as a body: it extracts the fenced ` ```xml ` … ` ``` ` system-prompt block under "## Direkt kopierbarer Systemprompt" in `concilium/characters/<slug>/references/role-contract.md`, uses that XML as the body system prompt + the subject, and runs it through the same Slice-1 `run_inference(...)` path with the same budget/key/code guardrails. This widens the available bodies from the 4 hardcoded `concilium/*.md` to the 10 committed characters — all reused as source of truth, never edited. | EXPLICIT (Ben, 2026-06-19) |
| CAN-DS-PRE-021 | **Preset selection.** `--preset <name>` loads a named role-composition preset and resolves it: each role → a character (slug) → a model (default = a free OpenRouter model; override allowed). The three source presets are loadable — A "Maximale Produktspannung" = Visionaerin·Pruefer·Nutzeranwalt·Macherin; B "Software-Architektur & Risiko" = Systemdenker·Risiko-Waechterin·Macherin·Minimalist; C "Kontroverse & neue Ideen" = Visionaerin·Provokateur·Uebersetzerin·Marktschaerferin. Default round = A. (Preset A's `der-pruefer` is now present — RISK-DS-PRE-013 RESOLVED. Any unresolvable slug still fail-closes with a named error, never silent fallback.) | EXPLICIT (Ben, 2026-06-19) |
| CAN-DS-PRE-022 | **Per-role → model mapping (OQ-DS-5 RESOLVED — Ben, 2026-06-19).** Each role in a preset carries an OPTIONAL per-role `model` field; resolution precedence is **per-role field > env override > free default** (unset → free default). This is a **per-preset model field per role**, NOT the positional `COUNCIL_1..4_MODEL` env slots — a preset is a self-contained reproducible composition that does not couple to environment ordering and does not break for >4 or named roles. Availability is runtime-verified, never hardcoded as stable truth. | EXPLICIT — OQ-DS-5 RESOLVED (Ben, 2026-06-19) |
| CAN-DS-PRE-023 | **Diversity gate over the resolved preset.** After a preset resolves to a concrete set of role→model bindings, the OD-3 diversity primitive `distinct_base_count([...resolved models])` (with `normalize_model_id`) is applied to the resolved model set, threshold ≥2 distinct normalized base models to proceed, `COUNCIL_DIVERSITY_UNAVAILABLE` on <2. (HIGH-1: the full `evaluate_gate(config, reachable, fake_error)` is NOT reused for presets — its config/`COUNCIL_n_MODEL`-slot contract is OD-3's CLI-env shape, not callable over a bare resolved-model list; `evaluate_gate@152 exists, but slots-coupled — not the preset entrypoint`.) A preset whose roles collapse to <2 distinct normalized base models trips the threshold (RISK-DS-PRE-016) — surfaced, not silently accepted. The gate remains a STRUCTURAL floor only (RISK-DS-004 / RISK-B-007: distinct ids ≠ uncorrelated cognition). | EXPLICIT (Ben, 2026-06-19) — HIGH-1 corrected |
| CAN-DS-RES-029 | **Dynamic default-model resolution (REQ-DS-015, BLOCKER-1).** The default model is resolved AT RUNTIME by a NAMED, editable PREFERENCE-ORDERED FAMILY list (DeepSeek v4 → Qwen3.x → Kimi K2.7 → Kimi K2.6 → GLM 5.x), each matched against `:free` ids in the LIVE catalog; first free-available wins, else fall back to OpenRouter free-model routing (any available `:free` id, or `openrouter/auto`). Precedence: explicit per-role/`--model` field > env override > dynamic resolver (the resolver is ONLY the no-explicit-model fallback). The resolver reuses `council_backend._fetch_catalog_ids` (fixed OpenRouter host → no new SSRF), is injectable for offline tests (fake catalog id list → 0 network calls, 0 credits), runtime-verifies availability (never assumes), and fails closed with a classified `COUNCIL_*` code on an unreachable catalog (never a stale/unverified pick). DeepSeek is the top preference only when free-available (currently NOT → resolver skips to Qwen3.x…); paid DeepSeek is only ever an explicit override, never auto-selected. | EXPLICIT (Ben, 2026-06-19) — BLOCKER-1 RESOLVED |

---

## 5. Success signal

| ID | Signal | Status |
|---|---|---|
| CAN-DS-014 | The full offline suite (`run_all.sh`) is green with the new council-body-runner: body-prompt + subject → `messages` construction, position-wrapping (model id + prompt source), clean handling of a malformed/empty/refused model response (never crashing or fabricating a position), budget-cap reuse, and key-redaction are all exercised network-free, 0 credits spent. | EXPLICIT (Ben, 2026-06-19) |
| CAN-DS-015 | ONE opt-in real foreign-body smoke runs a single `/concilium` body on a foreign model via the live path (`--live` + `COUNCIL_INFERENCE_LIVE=1`) on a tiny subject and gets back the body's real prose position (or a cleanly-classified `COUNCIL_*` code), with the key not leaking (leak-check = 0) — recorded in `docs/benchmarks/2026-06-19-deepseek-review-smoke.md`. This earns `real-boundary-smoke` for that ONE body/model/run ONLY. | EXPLICIT (Ben, 2026-06-19) |
| CAN-DS-016 | An oversized / over-cap subject/diff aborts fail-closed with `COUNCIL_BUDGET_EXCEEDED` BEFORE any network call (proven offline); no chunking this slice — OQ-DS-3 RESOLVED. | EXPLICIT (Ben, 2026-06-19) |
| CAN-DS-017 | The smoke benchmark does NOT assert or imply "the foreign body caught something Claude missed" / "the council is now more diverse / higher quality" — that claim is explicitly out of scope and deferred to Slice 3. The success signal is *a body ran on a foreign model and a real position came back*, not *the position was better or more diverse*. The `concilium.md` orchestration wiring is recorded as `integration-fake` (markdown instructs; live orchestrator obedience unproven). | EXPLICIT (Ben, 2026-06-19) |
| CAN-DS-CHR-024 | Offline (`integration-fake`, 0 credits): for a valid character slug, the runner extracts the ` ```xml ` system-prompt block from `references/role-contract.md` and builds the `messages` array from it + the subject; for a MISSING dir / MISSING or MALFORMED / empty XML block, it returns a named classified error (never crashes, never fabricates a prompt, never substitutes a different character) — all green under `run_all.sh`. | EXPLICIT (Ben, 2026-06-19) |
| CAN-DS-PRE-025 | Offline (`integration-fake`, 0 credits): the FULL preset assembly is exercised network-free — `--preset <name>` resolves roles → character slugs → models, builds each body's `messages`, preserves role ordering, and runs the resolved model set through the OD-3 diversity gate. Unknown preset / unknown character slug / role with no available model each fail-closed with a named error (no silent fallback); a preset resolving to <2 distinct base models trips the diversity gate. All green under `run_all.sh`. | EXPLICIT (Ben, 2026-06-19) |
| CAN-DS-PRE-026 | ONE opt-in real-boundary smoke runs a **FULL preset (all 4 roles) live** (`--live` + `COUNCIL_INFERENCE_LIVE=1`) on a tiny subject → each role returns its real prose position (or its own cleanly-classified `COUNCIL_*` code), leak-check = 0 across all calls, recorded in `docs/benchmarks/2026-06-19-deepseek-review-smoke.md`. Earns `real-boundary-smoke` for **that full-preset run** (each role/character/model run for real). USER OVERRIDE (Ben, 2026-06-19, OQ-DS-6): 4 live calls = 4× token spend ACCEPTED. Cost stays bounded — free-model default ~$0; the token cap is enforced PER CALL so each of the 4 calls is independently bounded/fail-closed; per-role failures are classified individually (one flaky role does not fake the others). `run_all.sh` makes ZERO live calls. The smoke proves the CAPABILITY, NOT diversity/quality lift. | EXPLICIT — USER OVERRIDE (Ben, 2026-06-19) |

---

## 6. Core use case

| ID | Content | Status |
|---|---|---|
| CAN-DS-018 | `/concilium` runs a body on a foreign model. The path: (1) the council-body-runner reads the body's prompt from `concilium/<body>.md` (READ-ONLY) and combines it with the subject to build a `messages` array; (2) resolves the model via the dynamic preference-ordered free-model resolver (REQ-DS-015; explicit `--model`/per-role > env > resolver), user-configurable to any OpenRouter id; (3) delegates to the Slice-1 `run_inference(...)` — which applies the token-only cap fail-closed, the key-safety header discipline, dry-run/build-only, and the injected-transport seam; (4) on a completion, returns the body's real position as the model's PROSE text, wrapped with the model id + prompt source (no enforced structured-JSON); (5) on budget/credit/rate/timeout/unusable-output, returns the corresponding classified `COUNCIL_*` code — never a raw traceback, never a fabricated position. The raw key never enters output. The OD-3 diversity gate guards that the configured council has ≥2 distinct base models. | EXPLICIT (Ben, 2026-06-19) |
| CAN-DS-019 | The integration target is `/concilium` (OQ-DS-2 RESOLVED, Ben 2026-06-19) — NOT a standalone review CLI. The wiring lives in `concilium.md` (orchestration, `integration-fake`) plus the runner module. Whether ALL bodies or only an optional foreign reviewer body are routed to foreign models is configurable, not mandatory (see NGOAL-DS-004a). | EXPLICIT (Ben, 2026-06-19) |
| CAN-DS-CHR-027 | **Run a character as a body.** Path: (1) the runner takes a character slug → opens `concilium/characters/<slug>/references/role-contract.md` (READ-ONLY); (2) extracts the fenced ` ```xml ` … ` ``` ` block under "## Direkt kopierbarer Systemprompt"; (3) uses that XML as the body system prompt + the subject to build a `messages` array; (4) delegates to Slice-1 `run_inference(...)` (cap fail-closed, key-safety header discipline, injected-transport seam, live gate); (5) returns the character's real PROSE position wrapped with model id + character slug + prompt source. A missing dir / missing-or-malformed XML block / empty extraction returns a named classified error — never a fabricated prompt, never a wrong character. | EXPLICIT (Ben, 2026-06-19) |
| CAN-DS-PRE-028 | **Run a preset round.** Path: (1) `--preset <name>` selects a named preset; (2) resolve each role → character slug → model (per-role model field > env override > free default per role); (3) for each role build its body `messages` via character XML extraction (CAN-DS-CHR-027); (4) apply the OD-3 diversity gate to the resolved model set (≥2 distinct normalized bases); (5) OFFLINE the full assembly is `integration-fake` (injected transport, 0 credits); the LIVE smoke runs the **FULL preset (all 4 roles)** (CAN-DS-PRE-026, USER OVERRIDE OQ-DS-6). Unknown preset / unknown slug / role with no resolvable model / <2 distinct bases each fail-closed with a named error — never silent fallback, never a silent Claude substitution (RISK-DS-PRE-015). | EXPLICIT (Ben, 2026-06-19) |

---

## 7. Non-goals

| ID | Excluded (explicitly a LATER slice or out of scope) | Status |
|---|---|---|
| NGOAL-DS-001 | Running / orchestrating the FULL real 4-body council with all bodies live on foreign models (Slice 3 territory). Slice 2 proves ONE body/model/run live; full live orchestration stays `integration-fake` here. | EXPLICIT (Ben, 2026-06-19) |
| NGOAL-DS-002 | Any GUI (Slice 4). | EXPLICIT (Ben, 2026-06-19) |
| NGOAL-DS-003 | **Measuring or claiming the diversity VALUE / quality lift** — "the foreign body catches what Claude misses" / proven-uncorrelated-cognition / catch-rate / cry-wolf delta (Claude-only vs. multi-model). This is the DEFERRED Slice-3 measurement (owner retro-analyst / metrics). Slice 2 delivers the *capability + integration*, not the *proof of value*. | EXPLICIT (Ben, 2026-06-19) |
| NGOAL-DS-004 | Multi-model fan-out (running several bodies live at once), streaming responses, multi-turn conversations, and tool/function calling. | EXPLICIT (Ben, 2026-06-19) |
| NGOAL-DS-004a | **Forcing ALL council bodies onto foreign models.** Foreign-model routing is OPTIONAL / configurable, not mandatory — a single foreign reviewer body, or selected bodies, is sufficient for Slice 2. | EXPLICIT (Ben, 2026-06-19) |
| NGOAL-DS-005 | Re-implementing transport, budget enforcement, key handling, the classified-code family, or the diversity gate — these are REUSED from Slice 1's `council_inference.py` and OD-3's `council_backend.py`, not rebuilt. | EXPLICIT (Ben, 2026-06-19) |
| NGOAL-DS-006 | Large-subject/diff chunking / multi-call splitting. For Slice 2 an over-cap subject fails closed with `COUNCIL_BUDGET_EXCEEDED` (OQ-DS-3 RESOLVED); chunking is a later concern. | EXPLICIT (Ben, 2026-06-19) |
| NGOAL-DS-007 | Auto credit purchase / management / top-up (carried over from Slice 1). | EXPLICIT (Ben, 2026-06-19) |
| NGOAL-DS-008 | Editing the council body prompts: `concilium/*.md` is READ-ONLY (council prompts stay the source of truth — reused as-is, not edited). | EXPLICIT (Ben, 2026-06-19) |
| NGOAL-DS-009 | **Editing the character library:** `concilium/characters/**` is READ-ONLY — character prompts and their `role-contract.md` are loaded (XML extracted), never edited or generated by this slice. | EXPLICIT (Ben, 2026-06-19) |
| NGOAL-DS-010 | **Running ANY live call inside `run_all.sh` / the offline suite** (the suite stays 0-credit, injected-transport, `integration-fake`). NOTE (USER OVERRIDE, Ben 2026-06-19, OQ-DS-6): running a full 4-role preset LIVE is NO LONGER a non-goal — the opt-in smoke runs the FULL preset (4 roles) live by design (CAN-DS-PRE-026); 4× token spend is ACCEPTED, bounded per-call. The non-goal that REMAINS is any live call inside the suite. | EXPLICIT — REVISED by USER OVERRIDE (Ben, 2026-06-19) |
| NGOAL-DS-011 | **Measuring the preset-level diversity/quality lift** ("a preset of foreign characters catches more / is genuinely uncorrelated"). Still the deferred Slice-3 measurement (NGOAL-DS-003); adding presets does NOT let Slice 2 claim it. | EXPLICIT (Ben, 2026-06-19) |
| NGOAL-DS-012 | Still no GUI (Slice 4), no chunking (NGOAL-DS-006), no multi-model live fan-out (NGOAL-DS-004), and no editing of `concilium/*.md` or `concilium/characters/**`. | EXPLICIT (Ben, 2026-06-19) |

---

## 8. Risks / contradictions

| ID | Risk | Likelihood | Impact | Mitigation | Status |
|---|---|---:|---:|---|---|
| RISK-DS-001 | **Over-claiming the diversity value / quality lift** — presenting a working foreign body (or a single smoke) as evidence that the council is now more diverse / catches more than Claude. The single most dangerous miss for this slice. | medium | high | NGOAL-DS-003 makes the value claim explicitly out of scope; the smoke benchmark (CAN-DS-017) is forbidden from asserting catch/diversity/quality; the value is deferred to Slice 3 with a different owner. RED may not be downgraded. | CONFIRMED |
| RISK-DS-002 | **Asserted-not-measured value** — the canvas/PRD/Vision state the north star (uncorrelated foreign cognition → fewer blind spots → higher quality) and a reader treats the GOAL as if it were already EVIDENCE. The capability shipping does not validate the value. | high | high | Vision states the north star as GOAL; every value claim is explicitly tagged "Slice-3 measurement, not proven here"; the carried falsifier (Claude-only vs. multi-model catch-rate / cry-wolf delta) is named and owned by retro-analyst/metrics. Capability evidence may not be read as value evidence. | CONFIRMED |
| RISK-DS-003 | **Response-shape built on a false premise** — assuming the foreign model emits a position in a particular shape (e.g. a JSON schema) when it may emit prose, partial JSON, or refuse. Resolved: output is treated as PROSE, no structured-JSON enforced. | high | medium | Output is the model's prose position wrapped with model id + prompt source (OQ-DS-1 RESOLVED). The exact response shape stays `ungeprüft` until the smoke (CAN-DS-EVN-004); a malformed/empty/refused response must classify cleanly (`COUNCIL_MODEL_UNAVAILABLE` reuse) — never crash, never fabricate a position, never sell an empty body as a real position. Verify at the smoke, do not hardcode from memory. | CONFIRMED (shape policy) / `ungeprüft` (exact shape until smoke) |
| RISK-DS-004 | **Distinct model ids ≠ truly uncorrelated cognition (reuses OD-3's RISK-B-007).** The diversity gate counts distinct normalized base models; two distinct ids can still share training lineage / cognition, so "≥2 distinct bases" does NOT prove genuine perspective diversity. | medium | high | OD-3 already discloses this (RISK-B-007): the gate is a necessary structural floor, not proof of uncorrelated cognition. Slice 2 inherits the disclosure verbatim and does not strengthen the claim; genuine uncorrelatedness is part of the Slice-3 measurement, not asserted here. | CONFIRMED (reused, RISK-B-007) |
| RISK-DS-005 | **Smoke hand-feeds the instrument it measures** — constructing the smoke so the subject/prompt trivially elicits a "good" position, manufacturing the appearance of a working/valuable foreign body (Slice-1 retro rule). | medium | high | The smoke proves only "a body ran on a foreign model and a real position came back," with the subject and body prompt fixed independently of any expected position; it never tunes the input to produce a desired position, and never asserts diversity/quality. | CONFIRMED |
| RISK-DS-006 | **Budget cap bypass for large subjects** — a big subject/diff inflates the input token estimate; if the cap is checked only on `max_tokens` (output) and not on the input estimate, a large subject could slip through. | medium | high | Reuse Slice-1's `estimate_total_tokens = input_token_estimate + max_tokens` and the fail-closed cap check BEFORE the network call (OQ-DS-3 RESOLVED: fail-closed `COUNCIL_BUDGET_EXCEEDED`, no chunking). The input-token estimate is a NAMED heuristic (`ableitbar`), not a billing oracle — disclosed as such. | CONFIRMED |
| RISK-DS-007 | **Free-model flakiness / "reachable ≠ invocable"** — the dynamically-resolved free model (REQ-DS-015) or any explicitly-configured model can 402 / 429 / 5xx, be rate-limited, or be unavailable at run time; free tiers are especially flaky, AND the preferred free families may not be present in the catalog at all (today there is NO free DeepSeek → the resolver skips to the next family or to OpenRouter free-routing). | high | medium | Reuse Slice-1 classified codes per failure class; the smoke either returns a real position (proving the capability for that model) or a classified code (still honest). The resolver reads the LIVE catalog (`_fetch_catalog_ids`) so availability is runtime-verified, never hardcoded as stable truth; an unreachable catalog fails closed with a classified `COUNCIL_*` code (never a silent stale pick); the configured model is user-overridable to a paid id (paid is never auto-selected). | CONFIRMED (reused; resolver runtime-verifies) |
| RISK-DS-008 | **API key leak** into logs / returned position / error output. | low | high | Reuse Slice-1 discipline unchanged: key as boolean presence, only in `Authorization` header; redaction/leak-check test; no raw-env dump. The new runner layer adds NO new key-handling surface. | CONFIRMED (reused) |
| RISK-DS-009 | **Opt-in smoke spends credits in CI** — the real foreign-body smoke accidentally runs inside `run_all.sh`. | low | high | Reuse Slice-1 isolation: smoke is opt-in, double-gated (`--live` + `COUNCIL_INFERENCE_LIVE=1`), lives OUTSIDE `run_all.sh`; the offline path makes ZERO network calls (no injection → `transport=None`). | CONFIRMED (reused) |
| RISK-DS-010 | **Scope creep into Slice 3/4** (full live orchestration, fan-out, GUI, diversity measurement) during this integration slice. | medium | medium | Non-goals NGOAL-DS-001..004a; Allowed change scope is narrow + machine-parseable; `concilium/*.md` read-only; `concilium.md` edit is wiring-only and `integration-fake`. | CONFIRMED |
| RISK-DS-011 | **`integration-fake` wiring mistaken for live-proven orchestration** — `concilium.md` *instructs* the orchestrator to route a body through the inference path, but the orchestrator's live obedience is not proven by code; treating the markdown as if it were a tested code path over-claims. | medium | medium | The canvas/PRD/evidence record the `concilium.md` wiring as `integration-fake` (markdown instructs, live obedience unproven); only the ONE foreign-body smoke earns `real-boundary-smoke`, and for that ONE body/model/run only. | CONFIRMED |
| RISK-DS-CHR-012 | **Brittle XML extraction from `role-contract.md`** — the runner parses the fenced ` ```xml ` block out of a hand-maintained markdown file. A missing block, a malformed/unclosed fence, a renamed heading, multiple ` ```xml ` blocks, or an empty block could yield a wrong/partial/empty system prompt. | medium | high | Extraction MUST classify a missing/malformed/empty block as a named error and refuse to run that body — never fabricate, truncate-silently, or fall back to a different character. Robust-extraction cases are unit-tested offline (valid block; missing block; malformed fence; empty block; heading absent). Verify the real structure against ≥1 actual file (verified: `die-visionaerin`). | CONFIRMED |
| RISK-DS-PRE-013 | **A preset references a character/slug that does not exist** — originally preset A ("Maximale Produktspannung") named **Pruefer** while `der-pruefer` was absent. **RESOLVED (Ben, 2026-06-19, OQ-DS-7): `der-pruefer` was added upstream to `concilium/characters/der-pruefer/` (verified present, roster = 10) → preset A now fully resolves.** The general class (any preset can still drift from the library) is mitigated below. | high | high | RESOLVED for preset A (der-pruefer present). General mitigation retained: preset resolution MUST fail-closed with a named "unknown character slug" error for ANY unresolvable slug and NOT silently drop the role, substitute another character, or fall back to Claude — offline-tested with a synthetic unknown slug. | RESOLVED (der-pruefer added; general fail-closed retained) |
| RISK-DS-PRE-014 | **Unknown preset name / role with no available model** resolves to garbage or a silent default. | medium | high | Unknown `--preset`, and a role whose model cannot be resolved/reached, each fail-closed with a distinct named error; offline tests assert the named error per case; no silent fallback. | CONFIRMED |
| RISK-DS-PRE-015 | **Silent Claude-fallback hides that a role did not run foreign** — if a foreign model is unavailable and the runner quietly substitutes a Claude body, the council's whole purpose (uncorrelated non-Claude cognition) is defeated AND the substitution is invisible. | medium | high | A role that cannot run on its resolved foreign model returns its classified `COUNCIL_*` code; any fallback is DISCLOSED in the output (model id + that it is a fallback), never silent. The default behavior is fail-closed with the classified code, not auto-fallback. | CONFIRMED |
| RISK-DS-PRE-016 | **A preset resolves to <2 distinct base models → trips the diversity gate** — e.g. several roles default to the same free model, or overrides collapse the base set. | medium | medium | After resolution, run the OD-3 diversity gate (`evaluate_gate` / `distinct_base_count`) over the resolved model set; a <2-distinct-base result returns the gate's classified abort (`COUNCIL_DIVERSITY_UNAVAILABLE`), surfaced not hidden. The gate stays a structural floor only (RISK-DS-004 / RISK-B-007). | CONFIRMED |
| RISK-DS-PRE-017 | **Full-preset LIVE cost** — running all 4 preset roles live = 4 calls = 4× the single-call token spend. | medium | medium | **ACCEPTED by the user (Ben, 2026-06-19, OQ-DS-6): the smoke runs the FULL preset (4 roles) live by design.** Cost stays bounded because: the free-model default keeps it ~$0; **the token cap (`COUNCIL_MAX_TOKENS_PER_RUN`) is enforced PER CALL, so each of the 4 calls is independently bounded and fail-closed** (there is NO preset-level aggregate cap this slice — a known, accepted property); the smoke is opt-in, double-gated (`--live` + `COUNCIL_INFERENCE_LIVE=1`), lives OUTSIDE `run_all.sh`; per-role failures classify individually (a flaky role does not consume or fake the others). `run_all.sh` makes zero network calls. | CONFIRMED (4× accepted; per-call cap; ~$0 free default) |
| RISK-DS-PRE-018 | **Presets-file location/format chosen by guess** instead of by the user (Python module vs. parseable markdown table). | low | medium | **RESOLVED (Ben, 2026-06-19, OQ-DS-4): `config/claude/lib/council_presets.py` — typed, importable Python; NO markdown-parse layer.** The `concilium/presets.md` candidate is DROPPED and removed from the Allowed change scope. | RESOLVED (OQ-DS-4) |

---

## 9. Evidence needed

| ID | Evidence | Status |
|---|---|---|
| CAN-DS-EVN-001 | Offline tests (`integration-fake`, 0 credits): body-prompt (`concilium/<body>.md`) + subject → `messages` construction; position-wrapping (model id + prompt source) of an INJECTED model response; clean classification of a malformed/empty/refused response (never crash, never fabricate a position); budget cap fail-closed on an oversized subject; key never in output (leak-check). All green under `run_all.sh`. | EXPLICIT (Ben, 2026-06-19) |
| CAN-DS-EVN-002 | `.env.example` review: any new variable (e.g. a foreign-body model id, if added beyond the reused `COUNCIL_INFERENCE_MODEL`) documented; reused budget/key vars present; `.env` stays gitignored. | EXPLICIT (Ben, 2026-06-19) |
| CAN-DS-EVN-003 | ONE opt-in real-boundary smoke: a single `/concilium` body on a tiny subject → foreign model via `--live` + `COUNCIL_INFERENCE_LIVE=1` → real prose position (or cleanly-classified `COUNCIL_*` code), leak-check = 0, recorded in `docs/benchmarks/2026-06-19-deepseek-review-smoke.md`. Earns `real-boundary-smoke` for that ONE body/model/run ONLY. | EXPLICIT (Ben, 2026-06-19) |
| CAN-DS-EVN-004 | **External-output-shape verification (OQ-DS-1 RESOLVED — prose; exact shape `ungeprüft`):** at the smoke, the real foreign-model output shape is confirmed against the live model and recorded. Policy is fixed (prose position, no enforced structured-JSON); the EXACT response shape stays `ungeprüft` until the smoke and may not be frozen as a brittle PRD premise. | EXPLICIT (Ben, 2026-06-19) — exact shape `ungeprüft` until smoke |
| CAN-DS-EVN-005 | **`concilium.md` wiring is `integration-fake`:** the markdown instructs the orchestrator to route a body through the inference path; live orchestrator obedience is NOT proven by code and is recorded as `integration-fake`, distinct from the ONE `real-boundary-smoke` body run. | EXPLICIT (Ben, 2026-06-19) |
| CAN-DS-EVN-006 | **Reality Ledger:** offline = `integration-fake`; `concilium.md` orchestration wiring = `integration-fake`; ONE foreign-body run = `real-boundary-smoke` for that ONE body/model/run only. **The diversity/quality-lift claim is NOT asserted by this slice** — it stays a Slice-3 deferred measurement; nothing in Slice-2 evidence may be read as proving it. | EXPLICIT (Ben, 2026-06-19) |
| CAN-DS-EVN-007 | The smoke benchmark explicitly records what it does NOT prove (no catch-rate, no cry-wolf, no proven diversity, no quality lift) per CAN-DS-017 / RISK-DS-001 / RISK-DS-002. | EXPLICIT (Ben, 2026-06-19) |
| CAN-DS-EVN-CHR-008 | Offline character-extraction tests (`integration-fake`, 0 credits): valid slug → correct ` ```xml ` block extracted and used as system prompt; missing dir → named error; missing/renamed heading → named error; malformed/unclosed fence → named error; empty block → named error. Never fabricates a prompt, never substitutes a character. Green under `run_all.sh`. | EXPLICIT (Ben, 2026-06-19) |
| CAN-DS-EVN-PRE-009 | Offline preset-assembly tests (`integration-fake`, 0 credits): `--preset` resolves roles → slugs → models with role ordering preserved; unknown preset / unknown slug (incl. the real `der-pruefer` gap) / role-with-no-model each fail-closed with a distinct named error; resolved <2-distinct-base set trips the diversity gate; a foreign-unavailable role surfaces its classified code and any fallback is DISCLOSED, never silent. Green under `run_all.sh`. | EXPLICIT (Ben, 2026-06-19) |
| CAN-DS-EVN-PRE-010 | ONE opt-in real-boundary smoke runs a **FULL preset (all 4 roles) live** (CAN-DS-PRE-026, USER OVERRIDE OQ-DS-6); records each role's model id + character slug + classified result. Earns `real-boundary-smoke` for **that full-preset run** (each role/character/model run for real). The offline assembly stays `integration-fake`. The smoke records what it does NOT prove (no diversity/quality lift). | EXPLICIT — USER OVERRIDE (Ben, 2026-06-19) |
| CAN-DS-EVN-RES-012 | **Dynamic resolver offline tests (`integration-fake`, 0 credits, REQ-DS-015):** with an INJECTED fake catalog id list (0 network calls), the suite asserts each family-priority branch (DeepSeek-free-present → picks DeepSeek; DeepSeek-absent-but-Qwen-free → picks Qwen3.x; etc.), the "skip unavailable family" path, and the OpenRouter-free-route fallback when no preferred family is free; plus precedence (explicit `--model`/per-role > env > resolver) and fail-closed-with-classified-`COUNCIL_*`-code when the (injected) catalog is unreachable. The named preference list is asserted to be an editable constant. No credits, no network, green under `run_all.sh`. The LIVE catalog read (`_fetch_catalog_ids`) is exercised only behind the existing double live gate, never in `run_all.sh`. | EXPLICIT (Ben, 2026-06-19) — BLOCKER-1 |
| CAN-DS-EVN-PRE-011 | **Reality Ledger (expanded):** character extraction + preset assembly + diversity-gate-over-resolved-set + all fail-closed branches = `integration-fake`; `concilium.md` wiring = `integration-fake`; the FULL preset (4 roles) run live = `real-boundary-smoke` for that full-preset run (each role/character/model run for real) — USER OVERRIDE (Ben, 2026-06-19, OQ-DS-6). The preset-level diversity/quality lift is NOT asserted (Slice-3 deferred, NGOAL-DS-003/011) — the full-preset-live smoke proves the CAPABILITY, not the lift. | EXPLICIT — USER OVERRIDE (Ben, 2026-06-19) |

---

## Allowed change scope

> Proposed by the orchestrator, grounded against the repo. Final OK by the user at the
> pre-build gate. `concilium/*.md` is **read-only** (council prompts stay source of truth).

Machine-parseable scope (PRIL `plumbline-scope-check` / `plumbline_scope.py`): one
backtick-wrapped path per line so the runtime scope guard can parse it. (This intro line
intentionally does NOT start with `-`/`*`/`+` so the parser does not read it as a path.)

- `config/claude/lib/deepseek_review.py`
- `config/claude/lib/council_inference.py`
- `config/claude/lib/council_backend.py`
- `config/claude/lib/council_presets.py`
- `concilium/characters/*`
- `config/claude/commands/concilium.md`
- `config/claude/tests/test_deepseek_review.sh`
- `config/claude/tests/run_all.sh`
- `.env.example`
- `docs/canvas/deepseek-review-agent.canvas.md`
- `docs/prd/deepseek-review-agent.prd.md`
- `docs/vision/deepseek-review-agent.vision.md`
- `docs/traceability.md`
- `docs/plans/2026-06-19-deepseek-review-agent.md`
- `docs/reality/deepseek-review-agent.evidence.jsonl`
- `docs/benchmarks/2026-06-19-deepseek-review-smoke.md`
- `backlog.md`
- `CLAUDE.md`
- `explorer/extract-agents.py`

Human note (OQ-DS-2 RESOLVED — integration target is `/concilium`, NOT a standalone CLI).
This slice adds a NEW `config/claude/lib/deepseek_review.py` — the council-body-runner that
reads a body prompt from `concilium/<body>.md` + the subject, builds a `messages` array, and
calls the Slice-1 `run_inference(...)` path. `config/claude/commands/concilium.md` is edited
for the orchestration WIRING ONLY (route a body through the runner); that wiring is
`integration-fake` (markdown instructs, live obedience unproven). `council_inference.py` is
listed in case a small, additive seam (e.g. an exported helper) is needed — any edit must
preserve the Slice-1 contract (cap, key-safety, codes, live gate) and not regress its tests.
`council_backend.py` is listed for read/reuse of the OD-3 diversity gate
(`evaluate_gate` / `distinct_base_count`); any edit must preserve OD-3's contract and tests.
Note (READ-ONLY): the four body prompts under `concilium/` (the `concilium/*.md` files) are
NOT in write-scope — reused as source of truth, never edited. (This note intentionally does
NOT start with `-`/`*`/`+` so the parser does not read it as a path pattern.)

Scope expansion note (character library + presets, 2026-06-19). (Plain prose — NOT bullet
lines, so the PRIL scope parser does not slurp them as path patterns.)

(1) `concilium/characters/*` is listed READ-ONLY: the runner LOADS each character's
`references/role-contract.md` and EXTRACTS its xml system-prompt block; it does NOT edit or
generate any file under `concilium/characters/**` (NGOAL-DS-009). The glob is in the scope
list only so the PRIL scope guard recognizes these as legitimately-touched (read) artifacts;
no write occurs.

(2) Presets file: OQ-DS-4 RESOLVED (Ben, 2026-06-19) = `config/claude/lib/council_presets.py`
(typed, importable Python; NO markdown-parse layer). The `concilium/presets.md` candidate is
DROPPED and removed from this scope list.

(3) `der-pruefer` (preset A) is NOW present in the library (`concilium/characters/der-pruefer/`,
added upstream — OQ-DS-7 RESOLVED, RISK-DS-PRE-013 RESOLVED); it is loaded read-only like every
other character (NOT created or edited by this slice).

(4) Slice-1 stale-default fix (user approved, BLOCKER-1, Ben 2026-06-19). `council_inference.py`
is already in the write-scope list (a small additive Slice-1 seam was anticipated). Its line-45
default `DEFAULT_INFERENCE_MODEL = "meta-llama/llama-3.1-8b-instruct:free"` is stale/unavailable
in the live catalog; Slice 2 fixes it (REQ-DS-016) EITHER by updating the constant to a
currently-available free id OR (cleaner) by routing Slice-1's default through the new dynamic
resolver — whichever preserves the Slice-1 contract + tests (cap/key/codes/live-gate/drift), no
regression. The new resolver lands in `council_presets.py` (already in scope); no NEW module file
is added, so the scope list is unchanged for the resolver. If the resolver were instead placed in
its own module, that path would be added here — it is NOT, to keep the surface minimal.

Status: CONFIRMED (Ben, 2026-06-19 — scope reflects OQ-DS-2 RESOLVED = `/concilium`, the
character+presets expansion, OQ-DS-4 RESOLVED = `council_presets.py` only, and the read-only
`der-pruefer` now present; user-confirmed at the Phase-0.15 gate)

---

## 10. Traceability links

PRD: docs/prd/deepseek-review-agent.prd.md (not yet created — PRD finalization blocked until this canvas is user-confirmed)
Product Vision: docs/vision/deepseek-review-agent.vision.md (to be created by product-owner after PRD draft)
Traceability Matrix: docs/traceability.md (new slice: deepseek-review-agent; carries canvas-link to this file)
Related REQ IDs: REQ-DS-* (defined in docs/prd/deepseek-review-agent.prd.md)
True-Line status: user-confirmed (canvas confirmed by Ben, 2026-06-19; PRD finalization unblocked)

---

## Open Questions

| ID | Question | Resolution / Status |
|---|---|---|
| OQ-DS-1 | **Which model + what output shape** — a free DeepSeek variant by default, or a specific id? And what shape does the foreign body's output actually take (structured vs. prose)? | **RESOLVED (Ben, 2026-06-19), AMENDED by BLOCKER-1 (Ben, 2026-06-19).** The DEFAULT is NO LONGER a hardcoded "free DeepSeek" id (there is NO free DeepSeek in the live catalog) — it is the DYNAMIC, CATALOG-AWARE, PREFERENCE-ORDERED free-model resolver (REQ-DS-015): family list DeepSeek v4 → Qwen3.x → Kimi K2.7 → Kimi K2.6 → GLM 5.x, first free-available wins, else OpenRouter free-routing; precedence explicit `--model`/per-role > env > resolver; availability runtime-verified, never hardcoded; fail-closed on unreachable catalog. DeepSeek is the top preference only when free-available; paid DeepSeek is only ever an explicit override. Output = the model's **PROSE** position/review text wrapped with model id + prompt source; NO enforced structured-JSON. The EXACT response shape stays `ungeprüft` until the smoke (RISK-DS-003 / CAN-DS-EVN-004). |
| OQ-DS-2 | **Integration target** — (a) a standalone review CLI, OR (b) wire the inference path into `/concilium` so a council body runs on a real foreign model. | **RESOLVED (Ben, 2026-06-19) = (b) `/concilium`, NOT a standalone CLI.** Slice 2 wires the Slice-1 `run_inference(...)` path into `/concilium` so a council body (or an optional foreign reviewer body) runs on a configurable OpenRouter model via a real completion, using `concilium/<body>.md` + the subject, returning the body's real position. Drives the Allowed change scope (adds `concilium.md` wiring, `integration-fake`). |
| OQ-DS-3 | **Large-subject / over-cap handling** — fail-closed, or chunk? | **RESOLVED (Ben, 2026-06-19) = fail-closed with `COUNCIL_BUDGET_EXCEEDED` on an oversized subject/diff; NO chunking this slice.** Settles RISK-DS-006 and CAN-DS-016; chunking stays a later slice (NGOAL-DS-006). |
| OQ-DS-4 | **WHERE / in what FORMAT do presets live** — a Python config module vs. a parseable markdown table? | **RESOLVED (Ben, 2026-06-19) = `config/claude/lib/council_presets.py` — typed, importable Python, NO markdown-parse layer.** Mirrors how `council_backend.py` / `council_inference.py` live; directly unit-testable offline with no markdown-parsing layer to maintain. The `concilium/presets.md` candidate is DROPPED and removed from the Allowed change scope. |
| OQ-DS-5 | **Per-role → model mapping mechanism** — reuse OD-3's `COUNCIL_1..4_MODEL` env slots, or a per-preset model field (default free per role)? | **RESOLVED (Ben, 2026-06-19) = a per-preset model field per role.** Each role carries an OPTIONAL `model`; resolution precedence is **per-role field > env override > free default** (unset → free default). NOT the positional `COUNCIL_1..4_MODEL` slots — a preset is a self-contained reproducible composition that must not couple to environment ordering and must work for >4 / named roles. |
| OQ-DS-6 | **Smoke depth** — ONE preset role live + assembly offline, vs. full preset live? | **RESOLVED (Ben, 2026-06-19) = FULL preset (all 4 roles) live in the smoke — USER OVERRODE the one-role recommendation.** The opt-in smoke runs the FULL preset (4 roles) live → `real-boundary-smoke` for that full-preset run (CAN-DS-PRE-026). 4 live calls = 4× token spend ACCEPTED. Bounded: free-model default ~$0; the token cap applies PER CALL so each of the 4 calls is independently bounded/fail-closed; opt-in + double-gated (`--live` + `COUNCIL_INFERENCE_LIVE=1`) + OUTSIDE `run_all.sh`; per-role failures classified individually. The offline assembly stays `integration-fake`; `run_all.sh` makes zero live calls. Full-preset-live proves the CAPABILITY, not the diversity/quality lift (NGOAL-DS-003/011). |
| OQ-DS-7 | **`der-pruefer` resolution** — preset A names **Pruefer**, originally absent. How should preset A resolve? | **RESOLVED (Ben, 2026-06-19) = `der-pruefer` ADDED to `concilium/characters/der-pruefer/`** (committed; `references/role-contract.md` verified present with the `## Direkt kopierbarer Systemprompt` heading + a fenced ` ```xml ` block; roster now = 10). Preset A fully resolves. RISK-DS-PRE-013 RESOLVED. The character is loaded read-only like every other (NOT created/edited by this slice). The general fail-closed-on-unknown-slug behavior is retained for any future drift. |

---

## User confirmation

Confirmed by user: yes
Confirmation date: 2026-06-19
Confirmed by: Ben
Confirmation note: Ben explicitly confirmed the Phase-0.15 gate decisions on 2026-06-19:
OQ-DS-4 = `config/claude/lib/council_presets.py` (typed Python, no markdown layer);
OQ-DS-5 = per-preset model field per role (per-role field > env > free default);
OQ-DS-6 = FULL preset (all 4 roles) live in the smoke (user OVERRODE the one-role
recommendation; 4× token spend accepted, per-call token cap, free-default ~$0, opt-in +
double-gated + outside run_all); OQ-DS-7 = `der-pruefer` added to the library (roster = 10),
preset A resolves, RISK-DS-PRE-013 RESOLVED. Honesty invariant intact: capability ≠ value;
`concilium.md` wiring stays `integration-fake`; the diversity/quality LIFT stays the deferred
Slice-3 measurement (NGOAL-DS-003/011) — full-preset-live proves the CAPABILITY only. Canvas
Status set to `user-confirmed`; PRD finalization unblocked.
