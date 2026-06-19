# DeepSeek Review Agent (Slice 2) — Phase 1 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL — use `superpowers:executing-plans` to implement this
> plan task-by-task, strictly TDD-first. **No production code before a failing test.** One
> atomic concern per task. Show every diff before applying. Commit atomically.
> `bash config/claude/tests/run_all.sh` MUST end with `ALL CHECKS PASSED` after every task,
> and `shellcheck` (run inside that suite) must stay clean for every new/edited `.sh`.
>
> **The tester owns the contract.** `config/claude/tests/test_deepseek_review.sh` is being
> written IN PARALLEL and is the binding acceptance contract. Where this plan's seam shape
> conflicts with that test, **the test wins** — re-shape the module to satisfy the test,
> never edit the test to match the plan. This plan plans *to* the REQ-DS acceptance criteria;
> the test makes them executable.

**Feature-Slug:** deepseek-review-agent · **Slice:** 2 of 4
**Branch:** `agileteam/deepseek-review-agent` (branched from `main`, per the OD-3 build-hygiene rule)
**Spec (frozen, user-confirmed 2026-06-19):**
`docs/prd/deepseek-review-agent.prd.md` (REQ-DS-001..016),
`docs/canvas/deepseek-review-agent.canvas.md` (CAN-DS-*, RISK-DS-*, Allowed change scope),
`docs/vision/deepseek-review-agent.vision.md`, `docs/traceability.md` (slice deepseek-review-agent).

**Goal:** Add a council-body/character RUNNER (`config/claude/lib/deepseek_review.py`) and a
typed PRESET + dynamic-resolver module (`config/claude/lib/council_presets.py`) that let a
`/concilium` body — a `concilium/<body>.md` prompt OR a character's extracted ` ```xml `
system prompt — run on a real foreign (non-Claude) OpenRouter model through the **reused**
Slice-1 `run_inference(...)` path. Wire `/concilium` (`concilium.md`, wiring-only,
`integration-fake`) to route a body through the runner. Fix Slice-1's stale default
(REQ-DS-016). All offline logic is `integration-fake`, 0 credits, green under `run_all.sh`;
one opt-in full-preset live smoke earns `real-boundary-smoke` for that run only.

**Honesty invariant (load-bearing, from the canvas — do not soften).** Slice 2 delivers a
**CAPABILITY + INTEGRATION, not a measured VALUE.** A body/character/preset really running and
returning a real position is allowed; "it caught more / is more diverse / is uncorrelated" is
the DEFERRED Slice-3 measurement (NGOAL-DS-003/011) and is NEVER claimed here. The diversity
check is a **necessary-not-sufficient** structural floor (RISK-DS-004 / RISK-B-007).

**Tech stack:** Python 3 (stdlib only — no third-party HTTP dep; the real transport + the real
catalog read are both reached only via reused Slice-1/OD-3 seams), Bash (`set -uo pipefail`) +
`lib.sh` assertions, `shellcheck`. No network, no real key in any offline test.

---

## Standing constraints (read before Task 0)

- **Stay inside the canvas Allowed change scope** (machine-parseable list, canvas §"Allowed
  change scope"). The load-bearing entries for the build:
  `config/claude/lib/deepseek_review.py`, `config/claude/lib/council_presets.py`,
  `config/claude/lib/council_inference.py`, `config/claude/lib/council_backend.py`,
  `config/claude/commands/concilium.md`, `config/claude/tests/test_deepseek_review.sh`,
  `config/claude/tests/run_all.sh`, `.env.example`, `docs/traceability.md`,
  `docs/plans/2026-06-19-deepseek-review-agent.md` (this file),
  `docs/reality/deepseek-review-agent.evidence.jsonl`,
  `docs/benchmarks/2026-06-19-deepseek-review-smoke.md`, `CLAUDE.md`.
  **`concilium/*.md` (the 4 bodies) and `concilium/characters/**` are READ-ONLY** (Source of
  Truth — never edit to make a test pass; NGOAL-DS-008/009). `concilium/characters/*` is in
  scope only so the PRIL scope guard does not redden on READS — no character file is modified.
- **Branch from `main`, one feature per branch surface** (OD-3 hygiene). The PRIL enforce Stop
  hook scopes the whole `merge-base(HEAD,main)…HEAD` surface; do not stack on a sibling feature.
- **Reuse, do not reimplement** (NGOAL-DS-005): transport, per-call token cap, key-safety,
  classified `COUNCIL_*` family, double live gate (`council_inference.py`); diversity primitive
  `distinct_base_count` + `normalize_model_id` and the catalog seam `_fetch_catalog_ids`
  (`council_backend.py`). Adding a re-implementation of any of these is a RED finding.
- **Test-the-test:** no behavior lands without a *failing* test observed first (RED→GREEN);
  every fail-closed / leak-check / no-Claude-fallback branch carries a negative fixture proven
  to fail if the branch is removed (per the "test per branch" build-hygiene rule).
- **No hardcoded real free-model ids as stable truth** (REQ-DS-005/015). Offline fixtures use
  obviously-synthetic catalog ids (`vendor-x/model-a:free`, plus DeepSeek/Qwen/etc. family
  *patterns* matched against an INJECTED catalog) — availability is runtime-verified only.
- **Never print the raw key.** `OPENROUTER_API_KEY` must never appear in any subcommand output,
  error, result structure, or test output (REQ-DS-013); a leak-check test asserts 0 occurrences.
- **No silent Claude substitution, ever** (RISK-DS-PRE-015, MEDIUM-1). A role that cannot run
  foreign returns its classified `COUNCIL_*` / `unknown-character-slug` / `model-unresolvable`
  code; ANY fallback is DISCLOSED. There is **no Claude-fallback code path** in the runner.
- **Avoid the ledger FORBIDDEN_TOKENS** in `docs/reality/*.evidence.jsonl` text:
  `fake-only` / `mock-only` / `placeholder` / `unverified`.
- **Green gate before every commit:** `run_all.sh` ends with `ALL CHECKS PASSED`; `git status`
  clean of stray files.

---

## Reality-Ledger / honesty DoD (binding — do not soften)

- Offline runner/preset/resolver/extraction logic + the `concilium.md` wiring are
  **`integration-fake`** (injected transport, injected catalog, 0 credits). All-offline-green
  is **NOT** proof of real foreign cognition, real invocability, or real diversity.
- **One** opt-in FULL-preset (4-role) live smoke (REQ-DS-011) earns **`real-boundary-smoke`**
  for **that full-preset run only** (each role/character/model run for real). It records each
  role's model id + character slug + classified result and **explicitly states what it does NOT
  prove** (no catch-rate, no cry-wolf, no proven diversity, no quality lift).
- The diversity / quality LIFT is **not a Slice-2 evidence record** — Slice-3 deferred.
- Create `docs/reality/deepseek-review-agent.evidence.jsonl` in Phase 3 (Gate C) with one record
  per load-bearing REQ at its TRUE class — `integration-fake` for all offline logic + the wiring;
  `real-boundary-smoke` ONLY for REQ-DS-011. Run
  `plumbline-reality-check --min-evidence integration-fake` — never raise a class to clear a floor.

---

## Module / function decomposition

Two new modules, house-style mirror of `council_inference.py` / `council_backend.py` (pure
classifier functions → stable result dicts → optional `render_*` panels → `argparse` CLI with a
`--json` seam). All "real" boundaries are reached ONLY via reused, injectable seams.

### A. `config/claude/lib/council_presets.py` — typed presets + dynamic resolver

Pure, importable Python — **NO markdown-parse layer** (OQ-DS-4). Distinct from the runner so the
resolver and rosters are unit-testable without the inference path.

| Symbol | Responsibility | REQ |
|---|---|---|
| `PRESETS: dict[str, list[dict]]` | Typed rosters A/B/C; each role `{role_name, character_slug, model?}`. Default name = `"A"`. | REQ-DS-003 |
| `DEFAULT_PRESET = "A"` | Named default. | REQ-DS-003 |
| `FREE_MODEL_FAMILY_PREFERENCE: tuple[dict,...]` | **NAMED, editable** preference-ordered family match list: 1 DeepSeek v4 · 2 Qwen3.x · 3 Kimi K2.7 · 4 Kimi K2.6 · 5 GLM 5.x. Each entry = `{name, match}` where `match` is a deterministic predicate/pattern over a catalog id. | REQ-DS-015 |
| `get_preset(name) -> list[dict]` | Return roster or raise/classify `unknown-preset`. | REQ-DS-004 |
| `resolve_preset(name, *, env, catalog_ids, character_loader) -> dict` | Resolve each role → `{role_name, character_slug, model, prompt_source}`, role order preserved; classify `unknown-preset` / `unknown-character-slug` / `model-unresolvable`. Returns a stable result dict carrying `roles`, `decision`, `code`. **0 network** (catalog injected). | REQ-DS-004/005 |
| `resolve_model(*, env, per_role_model, catalog_ids, role_key=None) -> dict` | Precedence ladder **explicit per-role/`--model` field > env override > dynamic resolver**; returns `{model, source: field\|env\|resolver, code}`. | REQ-DS-005/015 |
| `resolve_free_default(catalog_ids) -> dict` | The dynamic resolver core (below). Pure over an id list. | REQ-DS-015 |
| `family_match(entry, catalog_ids) -> str \| None` | First `:free` catalog id matching a family entry, else `None`. | REQ-DS-015 |
| `diversity_check(resolved_models) -> dict` | Wrap `council_backend.distinct_base_count([...])` + `normalize_model_id`; `>=2 → COUNCIL_DIVERSITY_OK`, `<2 → COUNCIL_DIVERSITY_UNAVAILABLE`; attach the RISK-B-007 disclosure string (verbatim, below). **NOT `evaluate_gate`** (HIGH-1). | REQ-DS-006 |
| `RISK_B_007_DISCLOSURE` (constant) | Verbatim: *"This is a **necessary-not-sufficient** guard (RISK-B-007); it does **not** prove real model diversity."* (canonical source `config/claude/commands/concilium.md:105-107`, HIGH-2 — NOT `council_backend.py`). | REQ-DS-006 |
| `main()/_parser()` | Optional CLI surface (`resolve-preset`, `resolve-model`, `diversity`) so the bash test can drive it; mirrors the `--json` seam. Inject catalog via `--inject-catalog '<json-list>'`; never live in `run_all.sh`. | REQ-DS-010/015 |

**Catalog seam (REQ-DS-015, the key offline lever).** `resolve_free_default` and
`resolve_preset` take `catalog_ids: list[str]` as a parameter. Offline: the bash test passes a
synthetic JSON list via `--inject-catalog` → **0 network, 0 credits**. Live: a thin
`fetch_catalog(env)` wrapper reuses `council_backend._fetch_catalog_ids(api_key, timeout)`
(fixed OpenRouter host → **no new SSRF surface**) and is reached ONLY behind the double live gate,
never in the offline suite. On `URLError`/`ValueError`/missing key → classify a `COUNCIL_*` code
(`COUNCIL_TIMEOUT` / `COUNCIL_MODEL_UNAVAILABLE` / `COUNCIL_MISSING_SECRET`) and **fail closed**;
never silently pick a stale id.

### B. `config/claude/lib/deepseek_review.py` — the runner CLI

Subcommands `run` (single body/character) + `preset` (resolve + optionally run a roster).
Delegates EVERY real call to `council_inference.run_inference(...)` — imports it, does not
re-implement transport/cap/key/codes/live-gate.

| Symbol | Responsibility | REQ |
|---|---|---|
| `load_body_messages(body, subject, *, prompts_dir) -> dict` | Reuse `council_backend.load_prompt(body, prompts_dir)` semantics (slug-only `_BODY_RE`, realpath-containment); on `status=="loaded"` build `messages=[{system:<prompt>},{user:<subject>}]`; on missing → `prompt-missing` classified, never fabricate, never substitute. | REQ-DS-001 |
| `extract_character_xml(slug, *, characters_dir) -> dict` | Open `concilium/characters/<slug>/references/role-contract.md` READ-ONLY; extract the FIRST ` ```xml ` block under `## Direkt kopierbarer Systemprompt`; classify `character-missing` / `xml-block-missing` / `xml-block-malformed` / `xml-block-empty`; slug-only validation before any read. (Algorithm below.) | REQ-DS-002 |
| `build_character_messages(slug, subject, *, characters_dir) -> dict` | `extract_character_xml` → `messages=[{system:<xml>},{user:<subject>}]`. | REQ-DS-002 |
| `wrap_position(result, *, model, prompt_source, character_slug=None) -> dict` | On `run_inference` OK → `{position:<completion prose>, model:<id>, prompt_source:<...>}` (+ `character_slug`); on any non-OK `COUNCIL_*` → pass the classified code through unchanged (never fabricate a position). | REQ-DS-007 |
| `run_body(...)` / `run_character(...)` | Build messages → compute `input_estimate` via `council_inference.estimate_input_tokens` (NEVER hand-feed it — Slice-1 retro rule) → call `run_inference(...)` with the per-call cap reused → `wrap_position`. | REQ-DS-007/008 |
| `run_preset(name, subject, *, env, catalog_ids, transport, ...)` | `council_presets.resolve_preset` → `diversity_check` over resolved set → per role build messages + `run_inference` (each independently fail-closed) → collect per-role `{role, character_slug, model, position\|code}`. Offline: injected transport + injected catalog. | REQ-DS-004/006/008/010 |
| `main()/_parser()` | `run --body|--character --subject [--preset]`, `--model`, `--inject-response`/`--inject-error`/`--inject-call-counter` (forwarded to the seam), `--inject-catalog`, `--live`. Live transport armed ONLY by `--live` AND `COUNCIL_INFERENCE_LIVE=1` (delegated to the Slice-1 gate logic — do not re-derive the gate). | REQ-DS-009/010/011 |

**No-Claude-fallback (MEDIUM-1, FALSIFYING).** Neither module contains any Claude-family model
literal (`anthropic/*`, `claude-*`) in any resolution/fallback branch. The
`FREE_MODEL_FAMILY_PREFERENCE` list contains only the five named free families + the
OpenRouter-free-route fallback. A grep of both module sources for a Claude-family literal in a
fallback branch returns zero (test-asserted); an all-roles-unavailable injected preset yields only
classified codes with **zero** Claude-family ids anywhere in output.

---

## XML-extraction algorithm (REQ-DS-002, robust to missing/malformed/empty)

Deterministic, line-oriented, no XML parser (the block is hand-maintained markdown, not
schema-valid XML — and the contract is "first fenced block under the heading", not "valid XML").

1. **Slug validation first** — reject any slug not matching `^[a-z0-9-]+$` (reuse
   `council_backend._BODY_RE` pattern) BEFORE any filesystem access → `character-missing` class
   (a traversal/separator slug never reads a file). Realpath-contain the resolved path inside
   `characters_dir`.
2. **Locate the file** — `concilium/characters/<slug>/references/role-contract.md`. Missing dir
   or missing file → `character-missing`.
3. **Find the heading** — scan for a line whose stripped text equals `## Direkt kopierbarer
   Systemprompt`. Absent → `xml-block-missing`.
4. **Find the first fence after the heading** — the FIRST line after the heading whose stripped
   text is exactly ` ```xml ` opens the block. If no ` ```xml ` fence appears before EOF (or
   before the next `## ` heading) → `xml-block-missing`.
5. **Find the closing fence** — the next line whose stripped text is exactly ` ``` `. If EOF is
   reached with no closing fence → `xml-block-malformed` (unclosed/malformed fence). No silent
   truncation.
6. **Extract + validate non-empty** — join the lines strictly between the fences. If the
   extracted content is empty or whitespace-only → `xml-block-empty`.
7. **Success** — return `{slug, system_prompt:<exact block>, prompt_source:"concilium/characters/<slug>/references/role-contract.md", status:"loaded"}`.

> Robustness floor (RISK-DS-CHR-012): every non-success path classifies and refuses — NEVER a
> partial/wrong/empty system prompt presented as valid, NEVER a substituted character. "First
> block under the heading" is explicit so multiple ` ```xml ` blocks are unambiguous. Verified
> against the real structure of `der-pruefer` (heading line 46, ` ```xml ` at 48, close at 87)
> and `die-visionaerin` — but the extractor reads structure, never hardcodes line numbers.

---

## Dynamic resolver algorithm (REQ-DS-015)

`resolve_free_default(catalog_ids)`:

1. For each entry in `FREE_MODEL_FAMILY_PREFERENCE` **in order** (DeepSeek v4 → Qwen3.x →
   Kimi K2.7 → Kimi K2.6 → GLM 5.x): compute `family_match(entry, catalog_ids)` = the first
   catalog id that (a) ends with `:free` AND (b) matches the family's deterministic pattern.
   Return the first non-`None` match (`{model:<id>, source:"resolver", family:<name>,
   code:COUNCIL_INFERENCE_OK}`).
2. **Skip-unavailable-family** falls out of step 1: an absent family yields `None` and the loop
   advances (today's real catalog: 0 free DeepSeek → DeepSeek is skipped to Qwen3.x).
3. **Free-route fallback** — if no named family matches, pick any available `:free` catalog id
   (deterministic: first sorted `:free` id), else `openrouter/auto`. (`{source:"free-route"}`.)
4. **Fail-closed** — `resolve_model`/`resolve_preset` only call the resolver with an already-
   fetched `catalog_ids`. If the catalog is **unreachable** (the live `fetch_catalog` raised, or
   the injected catalog signals an error sentinel), the CALLER classifies a `COUNCIL_*` code and
   fails closed — the resolver is never asked to invent a model from an empty/unknown catalog.
5. **Free-only guarantee** — every auto-selection is a `:free` id (or `openrouter/auto`); a PAID
   id (paid DeepSeek included) can enter ONLY via explicit `--model`/env/per-role override
   (couples to REQ-DS-008 MEDIUM-2: ~$0 bound holds only while resolved models are free-tier).

**Precedence ladder (`resolve_model`):** explicit per-role `model` field / `--model` → env
override → `resolve_free_default(catalog_ids)`. The resolver runs ONLY when no explicit model is
set. Asserted offline branch-by-branch via injected catalogs.

**Family `match` design.** Keep each `match` a simple, documented substring/regex over the
catalog id's base (e.g. DeepSeek = id contains `deepseek` and a v4 marker; Qwen3.x = `qwen3`;
Kimi K2.7/K2.6 = `kimi` + version token; GLM 5.x = `glm-5`). Patterns are deliberately loose-but-
named; the test drives them with synthetic ids so the *branch logic* (order, skip, fallback) is
falsifiable independent of any real catalog string. The list is asserted to be an editable
module constant (REQ-DS-015 / CAN-DS-EVN-RES-012).

---

## REQ-DS-016 — Slice-1 stale-default fix (no Slice-1 regression)

`council_inference.py:45` `DEFAULT_INFERENCE_MODEL = "meta-llama/llama-3.1-8b-instruct:free"` is
stale (no longer in the live catalog). Two allowed fixes; **prefer the resolver route** but
choose whichever keeps Slice-1's contract + tests green:

- **Option A (minimal):** replace the constant with a currently-available free id. Lowest blast
  radius; still a hardcoded id that can go stale again (the very smell that triggered this REQ) —
  acceptable only if Option B risks the Slice-1 contract.
- **Option B (cleaner, preferred):** route `resolve_model`'s "free default" branch through the
  new dynamic resolver when a catalog is available, falling back to the constant only when the
  resolver cannot run (offline/no-catalog). This removes the stale-id dead-end at its root.

**Guardrails either way (binding):** `resolve_model(env, cli_model)` keeps its exact signature and
the `--model > COUNCIL_INFERENCE_MODEL > free default` precedence. The full Slice-1 offline suite
(`test_council_inference.sh`) MUST stay green: cap, key-safety, `COUNCIL_*` codes, double live
gate, and the input-token **drift reconcile** unchanged. The ONLY behavioral delta is "free
default no longer resolves to the stale id." If Option B would change Slice-1's offline behavior
(e.g. require a catalog the offline suite cannot inject), fall back to Option A. Add a Slice-1-
level assertion (in `test_deepseek_review.sh` or by extending the Slice-1 default path test) that
the resolved free default is NEVER `meta-llama/llama-3.1-8b-instruct:free`.

---

## Build order (RED → GREEN, every branch offline-testable)

> The three offline seams that make every branch testable: **injected transport**
> (`--inject-response` / `--inject-error`, reused from Slice-1, default `transport=None` → 0
> calls), **injected catalog** (`--inject-catalog` JSON list → resolver runs network-free), and
> the **call counter** (`--inject-call-counter`, reused — proves 0/1 calls). No task lands without
> first observing its RED in `test_deepseek_review.sh`.

**Task 0 — Branch + scope sanity.** Confirm branch is off `main`; emit/validate the canvas
`Allowed change scope` is machine-parseable and run
`plumbline-scope-check --repo . --feature deepseek-review-agent --changed-files <planned list>`
(the scope already lives in the canvas; this proves it parses BEFORE build). RED baseline: run
`bash config/claude/tests/test_deepseek_review.sh` and confirm it fails (module/contract absent).

**Task 1 — `council_presets.py`: rosters + `get_preset` + `unknown-preset`.** Typed A/B/C with
the exact slugs (REQ-DS-003); default A; import + `get_preset` happy path + `unknown-preset`
fail-closed. (No network, no inference yet.) GREEN those assertions.

**Task 2 — Dynamic resolver (REQ-DS-015) over injected catalog.** `FREE_MODEL_FAMILY_PREFERENCE`
named constant + `family_match` + `resolve_free_default` + `resolve_model` precedence. Drive each
branch offline: DeepSeek-free-present → DeepSeek; DeepSeek-absent + Qwen-free → Qwen (skip path);
none-free → free-route fallback; precedence (field > env > resolver); catalog-unreachable →
fail-closed classified code. Assert the preference list is an editable constant.

**Task 3 — `resolve_preset` + per-role resolution + fail-closed branches.** Role order preserved;
`unknown-character-slug`, `model-unresolvable` each a distinct named code; **MEDIUM-1 falsifier**:
all-unavailable injected preset → only classified codes, **zero Claude-family ids**; grep-source
assertion of no Claude-family literal in any fallback branch.

**Task 4 — `diversity_check` (REQ-DS-006, HIGH-1).** Reuse `distinct_base_count` +
`normalize_model_id` over the resolved model set; ≥2 → `COUNCIL_DIVERSITY_OK`; <2 →
`COUNCIL_DIVERSITY_UNAVAILABLE`; proceed result carries the verbatim RISK-B-007 disclosure.
Assert `evaluate_gate` is NOT called by the preset path.

**Task 5 — `deepseek_review.py` body loading (REQ-DS-001).** Reuse `load_prompt` semantics; build
messages; `prompt-missing` + traversal-rejection branches. 0 network (`transport=None`).

**Task 6 — Character XML extraction (REQ-DS-002).** The extraction algorithm above; valid
(`der-pruefer` real file) + `character-missing` + `xml-block-missing` (no heading) +
`xml-block-malformed` (unclosed fence) + `xml-block-empty`; slug-traversal rejection. Use a
TEMP synthetic fixture dir for the malformed/empty/missing cases (do NOT edit
`concilium/characters/**`); use the real `der-pruefer` for the happy path.

**Task 7 — Position wrapping + budget + key-safety + live-gate (REQ-DS-007/008/009/013).** Wire
`run_body`/`run_character` to `run_inference` via injected transport: OK → wrapped position;
malformed/empty/refused/2xx-no-completion → `COUNCIL_MODEL_UNAVAILABLE`; over-cap subject →
`COUNCIL_BUDGET_EXCEEDED` BEFORE any call (call-counter = 0); key never in output (leak-check);
live gate OFF by default → 0 calls. `input_estimate` computed by `estimate_input_tokens`, never
hand-fed.

**Task 8 — `run_preset` end-to-end offline (REQ-DS-010).** Full assembly: resolve → diversity →
per-role build + `run_inference` (each independently fail-closed) over injected transport +
injected catalog; role ordering; per-role failure isolation (one role's classified code does not
fake the others). The whole offline suite green under `run_all.sh`, 0 network, 0 credits.

**Task 9 — REQ-DS-016 Slice-1 stale-default fix.** Apply Option B (preferred) or A; assert the
resolved free default is never the stale id; re-run `test_council_inference.sh` — must stay green
(no cap/key/codes/live-gate/drift regression).

**Task 10 — `concilium.md` wiring (REQ-DS-012, integration-fake).** Wiring-only edit: a section
instructing the orchestrator to route a body/character/preset through `deepseek_review.py`
(mirroring the existing OD-3 `gate`/`report` bash-block style). Recorded `integration-fake`. The
4 bodies + `concilium/characters/**` stay READ-ONLY. Do not quote any `mcp__<family>__` literal
absent from `DEPENDENCIES.md`.

**Task 11 — `.env.example` (REQ-DS-014).** Document any NEW env var (e.g. a per-role model env
override naming scheme, if one is introduced); confirm reused budget/key/live vars present; `.env`
stays gitignored. If no new var is introduced, state that explicitly (no spurious additions).

**Task 12 — Register in `run_all.sh`.** Add `bash config/claude/tests/test_deepseek_review.sh ||
fail=1` alongside the other council tests (after `test_council_inference.sh`). Confirm `run_all.sh`
ends `ALL CHECKS PASSED` and shellcheck stays clean.

**Task 13 — Reality ledger + traceability (Gate C prep).** Author
`docs/reality/deepseek-review-agent.evidence.jsonl` (one record per load-bearing REQ at its true
class) and update `docs/traceability.md` (slice rows TRC-DS-001..016, wired-in-prod cells). Run
`plumbline-reality-check --min-evidence integration-fake`.

**Task 14 (deferred to Phase 3 / opt-in, OUTSIDE `run_all.sh`) — full-preset live smoke
(REQ-DS-011).** With `--live` + `COUNCIL_INFERENCE_LIVE=1` on a tiny fixed subject, run a full
preset (4 roles) live; record each role's model id + character slug + classified result in
`docs/benchmarks/2026-06-19-deepseek-review-smoke.md`; leak-check = 0; record what it does NOT
prove. Subject fixed independently of any expected position (RISK-DS-005). This is the ONLY
`real-boundary-smoke` record; it never runs in CI.

---

## Validation commands

```bash
# The binding feature contract (tester-owned), offline, 0 credits:
bash config/claude/tests/test_deepseek_review.sh

# Slice-1 no-regression (REQ-DS-016 guardrail):
bash config/claude/tests/test_council_inference.sh

# Full CI suite — must end "ALL CHECKS PASSED" after every task (frontmatter, scope,
# governance, PRIL, shellcheck, all test modules):
bash config/claude/tests/run_all.sh

# Scope guard (Phase 0.6 / before build): prove the canvas scope parses & covers the diff:
config/claude/bin/plumbline-scope-check --repo . --feature deepseek-review-agent \
  --changed-files <space-separated changed files>

# Reality floor (Phase 3 / Gate C), honest class — never raise to clear the floor:
config/claude/bin/plumbline-reality-check --min-evidence integration-fake

# Manual resolver/preset spot-check, offline (injected catalog → 0 network):
python3 config/claude/lib/council_presets.py resolve-preset --preset A \
  --inject-catalog '["vendor-x/model-a:free","vendor-y/model-b:free"]' --json
python3 config/claude/lib/deepseek_review.py run --character der-pruefer \
  --subject "tiny" --inject-response '<fake-200-json>' --json

# OPT-IN full-preset live smoke (REQ-DS-011) — OUTSIDE run_all.sh, double-gated, 4 calls:
COUNCIL_INFERENCE_LIVE=1 python3 config/claude/lib/deepseek_review.py preset \
  --preset A --subject "<tiny fixed subject>" --live --json
# → record in docs/benchmarks/2026-06-19-deepseek-review-smoke.md
```

---

## Risks / rollback

| Risk | Mitigation / rollback |
|---|---|
| **REQ-DS-016 regresses Slice-1.** | Prefer Option B but fall back to Option A if Slice-1 offline behavior would change; the `test_council_inference.sh` green gate is the tripwire — if it reddens, revert to the constant-swap (Option A). Keep `resolve_model`'s signature + precedence byte-stable. |
| **Brittle XML extraction (RISK-DS-CHR-012).** | Read structure, never hardcode line numbers; classify every non-success path; offline-tested across all 5 branches with synthetic temp fixtures + the real `der-pruefer` happy path. Rollback = the extractor refuses (classified), never fabricates. |
| **Plan/test seam conflict.** | The tester's `test_deepseek_review.sh` wins; re-shape the module (subcommand names, flag names, result keys) to the test, do not edit the test. Resolve early at Task 0 RED baseline. |
| **Resolver over-claims a "DeepSeek default."** | The resolver only auto-picks a `:free` id; today 0 free DeepSeek → it SKIPS DeepSeek. No doc/benchmark claims a realized DeepSeek default (BLOCKER-1). |
| **Silent Claude fallback creeps in.** | MEDIUM-1 FALSIFYING test (grep-source + all-unavailable injected preset → zero Claude-family ids). Fails the suite if a Claude-fallback path is ever added. |
| **Live smoke spends in CI.** | Smoke is opt-in, double-gated (`--live` + `COUNCIL_INFERENCE_LIVE=1`), lives OUTSIDE `run_all.sh`; offline path `transport=None` → 0 calls (REQ-DS-009 test). |
| **Scope guard blocks the Stop gate.** | Canvas scope is machine-parseable; validate with `plumbline-scope-check` at Task 0; one feature per branch off `main` (no sibling stacking). |
| **Bench/builder pollutes the tree.** | No builder sub-agents with file tools run in-tree; this is a runner-build, not a bench. After every task verify `git status` clean + `run_all.sh` green; revert stray files. |
| **Over-claiming the diversity value.** | RISK-DS-001/002: the diversity check is necessary-not-sufficient (RISK-B-007 verbatim); the smoke records what it does NOT prove; quality lift stays Slice-3 (NGOAL-DS-003/011). |

---

## Traceability stub (REQ → task → evidence)

| REQ | Task | Evidence class |
|---|---|---|
| REQ-DS-001 | T5 | integration-fake |
| REQ-DS-002 | T6 | integration-fake |
| REQ-DS-003 | T1 | integration-fake |
| REQ-DS-004 | T1,T3 | integration-fake |
| REQ-DS-005 | T2,T3 | integration-fake |
| REQ-DS-006 | T4 | integration-fake |
| REQ-DS-007 | T7 | integration-fake |
| REQ-DS-008 | T7 | integration-fake |
| REQ-DS-009 | T7 | integration-fake |
| REQ-DS-010 | T8,T12 | integration-fake |
| REQ-DS-011 | T14 (opt-in) | real-boundary-smoke (full-preset run only) |
| REQ-DS-012 | T10 | integration-fake |
| REQ-DS-013 | T7 | integration-fake |
| REQ-DS-014 | T11 | integration-fake |
| REQ-DS-015 | T2,T3 | integration-fake |
| REQ-DS-016 | T9 | integration-fake |
