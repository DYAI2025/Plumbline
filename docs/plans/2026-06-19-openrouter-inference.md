# Implementation Plan: OpenRouter Inference Path (Slice 1 of 4)

Feature-Slug: openrouter-inference
Branch: agileteam/openrouter-inference
Spec (FROZEN): docs/prd/openrouter-inference.prd.md (incl. Spec-sanity carried constraints I-1/I-2/I-3)
Canvas (user-confirmed): docs/canvas/openrouter-inference.canvas.md
Traceability: docs/traceability.md (slice `openrouter-inference`, TRC-INF-001..012)
Extends: OD-3 `config/claude/lib/council_backend.py` (reuse `_fetch_catalog_ids` POST
pattern ~L264-283, `urllib.error.HTTPError`-first classification ~L314-324,
`_env_int`/`_env_truthy`, `OPENROUTER_MODELS_URL` constant, `CODE_*` family).

> **Plan status:** TDD plan only. No production code or tests are written by this plan.
> Each task is test-first: the named test is authored in the RED state BEFORE the
> production change, then made green. Tasks are atomic and dependency-ordered.

## Architecture decision (ADR-level, within confirmed scope)

New sibling module **`config/claude/lib/council_inference.py`** (NOT extending
`council_backend.py`). Rationale: keeps OD-3's catalog/governance module unchanged
(smaller blast radius, independent test file), while reusing OD-3 helpers by import. The
canvas Allowed change scope lists both options; this plan picks the sibling and records it
here so scope is not re-opened. The module mirrors the OD-3 house style exactly:
deterministic, argparse CLI, `--json` per subcommand, classification-IS-success (exit 0),
an **injectable transport seam** for offline tests (the inference analogue of OD-3's
`--fake-reachable`), and the sentinel leak-check discipline.

Tests live in a new **`config/claude/tests/test_council_inference.sh`** (black-box CLI +
an `importlib` pure-core block, mirroring `test_council_backend.sh`).

### Module constants / seam contract (the coder implements EXACTLY this)

- `OPENROUTER_CHAT_URL = "https://openrouter.ai/api/v1/chat/completions"` — fixed module
  constant, no caller-supplied host (REQ-INF-002, zero SSRF).
- New codes added to the `COUNCIL_*` family:
  `COUNCIL_BUDGET_EXCEEDED`, `COUNCIL_INSUFFICIENT_CREDIT`, `COUNCIL_RATE_LIMITED`.
  Reused from OD-3: `COUNCIL_TIMEOUT`, `COUNCIL_MODEL_UNAVAILABLE`, `COUNCIL_MISSING_SECRET`.
- `estimate_input_tokens(messages) -> int` — the **named offline heuristic** (I-3). It is
  `ableitbar`, NOT `belegt`; its name and docstring MUST state it is an approximate guard,
  not the provider's native tokenizer.
- `estimate_total_tokens(input_estimate, max_tokens) -> int` = `input_estimate + max_tokens`
  (REQ-INF-005).
- Injectable transport seam: a CLI flag (`--fake-response <json>` / `--fake-error <class>`)
  AND a function-level seam (`transport=` parameter defaulting to the real
  `urllib`-based callable) so the pure logic is exercised with zero network and zero calls.
  The fake transport records call-count so "NO network call" is asserted as **zero calls**.

---

## Phase-1 tasks (TDD, dependency-ordered)

### Task 1 — RED scaffold: test file + module presence
**Goal:** Author `test_council_inference.sh` header (spec sources, seam/CLI contract doc
block mirroring `test_council_backend.sh`), assert the module file exists. Create
`council_inference.py` as a stub with the argparse skeleton + constants only (no logic), so
the suite is RED on behavior, not on import.
**Files:** `config/claude/tests/test_council_inference.sh` (new),
`config/claude/lib/council_inference.py` (new, skeleton).
**Test proves it:** `assert_file "council_inference module exists"`; `python3 -m py_compile`
of the new module succeeds.
**Done-criterion (machine-checkable):**
`python3 -m py_compile config/claude/lib/council_inference.py` exits 0 AND
`bash config/claude/tests/test_council_inference.sh` runs (RED is acceptable here, but the
file-presence + compile assertions pass).
**Maps:** REQ-INF-001 (scaffold), house-style seam contract.

### Task 2 — `OPENROUTER_CHAT_URL` fixed-host constant (no SSRF)
**Goal:** Define the fixed completion URL as a module constant; no subcommand/flag accepts a
host/URL.
**Files:** `config/claude/lib/council_inference.py`.
**Test proves it:** importlib block asserts `m.OPENROUTER_CHAT_URL ==
"https://openrouter.ai/api/v1/chat/completions"` and that it starts with `https://` and is
a constant (not derived from argv/env). A grep-style assertion that no subcommand exposes a
`--url`/`--host` flag.
**Done-criterion:** `test_council_inference.sh` REQ-INF-002 assertions green.
**Maps:** REQ-INF-002, RISK-INF-001, TRC-INF-001.

### Task 3 — Input-token heuristic, explicit and named (I-3)
**Goal:** Implement `estimate_input_tokens(messages)` as a **named offline heuristic**
(docstring states `ableitbar`/approximate, not the provider tokenizer) and
`estimate_total_tokens = input + max_tokens`.
**Files:** `config/claude/lib/council_inference.py`.
**Test proves it (test-first):** `estimate` subcommand with a fixed messages fixture
returns a deterministic `input_token_estimate`; a second fixture twice the length yields a
larger estimate (monotonic); JSON includes both `input_token_estimate` and
`total_token_estimate == input + max_tokens`. Assert the field is labelled approximate
(e.g. an `"estimate_is_approximate": true` flag or `≈` in the human panel).
**Done-criterion:** REQ-INF-005 / I-3 estimate assertions green; `total == input + max_tokens`.
**Maps:** REQ-INF-005, I-3, TRC-INF-004.

### Task 4 — Explicit `max_tokens` ALWAYS in the request body (REQ-INF-004, build-time invariant)
**Goal:** The request-body builder MUST always include `max_tokens`. Expose a
`build-request` (dry-render) seam that returns the exact body dict so a test can assert the
field is present without a network call.
**Files:** `config/claude/lib/council_inference.py`.
**Test proves it (test-first):** `build-request --json` (or dry-run body echo) contains
`"max_tokens"` with the configured value AND `"model"` AND `"messages"`. A second assertion:
there is NO code path that emits a body lacking `max_tokens` (the builder has no optional
branch — exercised by calling it with default args and asserting the key is present).
**Done-criterion:** REQ-INF-004 assertions green; `max_tokens` present in every rendered body.
**Maps:** REQ-INF-004, EDGE-INF-004, TRC-INF-003.

### Task 5 — Pre-call cap check vs `COUNCIL_MAX_TOKENS_PER_RUN`, fail-closed, ZERO calls (REQ-INF-006)
**Goal:** Order is estimate → cap-check → (only then) transport. If
`total_token_estimate > COUNCIL_MAX_TOKENS_PER_RUN` (default 20000, via `_env_int`), abort
`COUNCIL_BUDGET_EXCEEDED` and make **no** transport call. Boundary: estimate == cap proceeds
(EDGE-INF-002).
**Files:** `config/claude/lib/council_inference.py`.
**Test proves it (test-first):** with a fake transport that records call-count: an estimate
`> cap` returns `COUNCIL_BUDGET_EXCEEDED` AND fake-transport call-count == 0 (the
**zero-call** assertion); an estimate `== cap` proceeds (one call); `COUNCIL_MAX_TOKENS_PER_RUN`
read from env (set to a small value to force the boundary, proving it is not hardcoded).
**Done-criterion:** REQ-INF-006 assertions green incl. `call_count==0` on over-cap and the
`==cap` proceed boundary.
**Maps:** REQ-INF-006, REQ-INF-007, NFR-INF-007, EDGE-INF-002/003, AC-INF-002/003, TRC-INF-004.

### Task 6 — Dry-run returns estimate with ZERO calls (REQ-INF-008)
**Goal:** `--dry-run` returns the approximate estimate (input + total) WITHOUT any transport
call (0 credits).
**Files:** `config/claude/lib/council_inference.py`.
**Test proves it (test-first):** `infer --dry-run` against the fake transport returns the
estimate fields AND fake-transport call-count == 0.
**Done-criterion:** REQ-INF-008 assertions green; `call_count==0`.
**Maps:** REQ-INF-008, AC-INF-004, GOAL-INF-003, TRC-INF-005.

### Task 7 — Happy path: single POST, completion text returned (REQ-INF-001)
**Goal:** Within-cap, non-dry-run: perform exactly ONE POST via the seam; on a valid 2xx
JSON body with `choices[].message.content`, return the completion text.
**Files:** `config/claude/lib/council_inference.py`.
**Test proves it (test-first):** fake transport returns a valid completion JSON; result
contains the completion text AND fake-transport call-count == 1.
**Done-criterion:** REQ-INF-001 assertions green; `call_count==1`; completion text surfaced.
**Maps:** REQ-INF-001, REQ-INF-003 (stdlib urllib only — assert no SDK import), AC-INF-003,
TRC-INF-001/002.

### Task 8 — Post-call reconciliation: BOTH input-estimate vs `usage.prompt_tokens` AND total (I-3)
**Goal:** After a real (faked) call, compare the approximate **input** estimate against
`usage.prompt_tokens` AND the **total** estimate against `prompt_tokens + completion_tokens`,
surfacing both real counts and both deltas (so the heuristic's drift is MEASURED).
**Files:** `config/claude/lib/council_inference.py`.
**Test proves it (test-first):** fake transport returns a completion with
`usage.prompt_tokens` and `usage.completion_tokens`; result surfaces
`usage_prompt_tokens`, `usage_completion_tokens`, `input_estimate_delta` (vs prompt_tokens),
and `total_estimate_delta` — both, per I-3.
**Done-criterion:** REQ-INF-009 / I-3 assertions green; both deltas present.
**Maps:** REQ-INF-009, I-3, AC-INF-005, TRC-INF-006.

### Task 9 — Graceful degrade when `usage` absent/misshaped (I-1)
**Goal:** Reconciliation MUST degrade gracefully: a 2xx with a usable completion but
**missing/misshaped `usage`** does not crash and does not fabricate counts — it surfaces the
completion with `usage`-derived fields null/absent and a note, OR (per I-1 wording) classifies
`COUNCIL_MODEL_UNAVAILABLE` if there is no usable completion either. The `usage` premise is
`ableitbar`/`ungeprüft`, never assumed present.
**Files:** `config/claude/lib/council_inference.py`.
**Test proves it (test-first):** (a) 2xx with completion but no `usage` → result returns the
completion, reconciliation fields null, no traceback; (b) the `cost` field is NEVER required
(a body without `cost` is not an error — reconciliation uses `usage` only).
**Done-criterion:** I-1 assertions green; no `Traceback`/`KeyError` in output; `cost` never
required.
**Maps:** REQ-INF-018 (usage/cost premise ungeprüft), I-1, EDGE-INF-010, TRC-INF-012.

### Task 10 — Distinct classified errors: 402 / 429(+Retry-After, no retry) / 5xx / timeout / malformed (REQ-INF-012/013)
**Goal:** Classify into DISTINCT codes (NOT collapsed like OD-3's catalog path):
HTTP 402 → `COUNCIL_INSUFFICIENT_CREDIT`; HTTP 429 → `COUNCIL_RATE_LIMITED` (record
`Retry-After` if present, do NOT auto-retry); HTTP 5xx / other non-2xx →
`COUNCIL_MODEL_UNAVAILABLE`; connection error / socket timeout → `COUNCIL_TIMEOUT`;
non-JSON / wrong-shape → `COUNCIL_MODEL_UNAVAILABLE`. Reuse OD-3's `HTTPError`-first ordering.
**Files:** `config/claude/lib/council_inference.py`.
**Test proves it (test-first):** fake-error injections for each class assert the distinct
code; the 429 case asserts the recorded `Retry-After` value AND fake-transport
call-count == 1 (the **no-auto-retry** assertion); a single assertion proves 402 and 5xx do
NOT collapse to the same code.
**Done-criterion:** REQ-INF-012/013 assertions green; 429 call_count==1; 402≠5xx code.
**Maps:** REQ-INF-012, REQ-INF-013, AC-INF-006..009, EDGE-INF-005..008, TRC-INF-009.

### Task 11 — 2xx-but-no-usable-completion → `COUNCIL_MODEL_UNAVAILABLE` (I-2)
**Goal:** A 2xx whose body parses as JSON but lacks a usable completion
(missing/empty `choices[].message.content`, or an `{"error": ...}` body) raises no
exception → MUST be classified `COUNCIL_MODEL_UNAVAILABLE` (deterministic, not a crash, not a
false success). This is the I-2 uncovered failure mode, folding into EDGE-INF-009/011.
**Files:** `config/claude/lib/council_inference.py`.
**Test proves it (test-first):** (a) 2xx body `{"choices":[{"message":{"content":""}}]}`
(empty content) → `COUNCIL_MODEL_UNAVAILABLE`, not success; (b) 2xx body `{"error":{...}}`
→ `COUNCIL_MODEL_UNAVAILABLE`; (c) non-JSON 2xx → `COUNCIL_MODEL_UNAVAILABLE`. No traceback.
**Done-criterion:** I-2 assertions green; empty-content 2xx is NOT a success; no `Traceback`.
**Maps:** REQ-INF-012 (malformed), I-2, EDGE-INF-009/011, AC-INF-010, TRC-INF-009.

### Task 12 — Missing key fail-closed, no network call (REQ-INF-011)
**Goal:** A real (non-dry-run) call with `OPENROUTER_API_KEY` absent → `COUNCIL_MISSING_SECRET`,
no env dump, NO transport call. Key read as boolean presence; raw value only in the
`Authorization: Bearer <key>` header inside the real transport.
**Files:** `config/claude/lib/council_inference.py`.
**Test proves it (test-first):** no key + non-dry-run → `COUNCIL_MISSING_SECRET` AND
fake-transport call-count == 0 AND output contains no `OPENROUTER_API_KEY=` dump.
**Done-criterion:** REQ-INF-011 assertions green; `call_count==0`; no env-name dump.
**Maps:** REQ-INF-011, AC-INF-012, EDGE-INF-001, GOAL-INF-005, TRC-INF-008.

### Task 13 — Secret redaction: sentinel never in ANY output path (NFR-INF-001)
**Goal:** The raw key never appears in config/result/error output. Mirror OD-3's sentinel
leak-check across the inference subcommands (estimate, dry-run, infer-success, every error
class).
**Files:** `config/claude/lib/council_inference.py`,
`config/claude/tests/test_council_inference.sh`.
**Test proves it (test-first):** with `OPENROUTER_API_KEY=<SENTINEL>` set, scan every
subcommand's output for the sentinel and for `Bearer ` / `sk-or-` → LEAK count 0.
**Done-criterion:** NFR-INF-001 assertions green; sentinel absent from all paths.
**Maps:** NFR-INF-001, REQ-INF-011, AC-INF-011, TRC-INF-008.

### Task 14 — Configurable model, free default, runtime-verified (NOT hardcoded as truth) (REQ-INF-010)
**Goal:** Model id resolves from `COUNCIL_INFERENCE_MODEL` (any OpenRouter id), defaulting to
a free model id; the default's availability is treated as runtime-verified (consistent with
OD-3 NGOAL-B-002), NOT asserted stable-true. A user-set value overrides.
**Files:** `config/claude/lib/council_inference.py`.
**Test proves it (test-first):** unset → resolves to the configured free default and the
result/disclosure does NOT claim it is guaranteed-available (a flag like
`"model_availability": "runtime-verified"` rather than `"available": true`); a user-set
`COUNCIL_INFERENCE_MODEL=foo/bar` overrides the default.
**Done-criterion:** REQ-INF-010 assertions green; override works; no hardcoded-availability claim.
**Maps:** REQ-INF-010, AC-INF-013, GOAL-INF-001, TRC-INF-007.

### Task 15 — Classification-is-success: no raw traceback reaches output (REQ-INF-014)
**Goal:** Every classified outcome is exit-0 / a returned dict; malformed CLI input and every
error class produce a classified payload, never a Python traceback. (Unknown subcommand /
argparse error stays non-zero, per OD-3.)
**Files:** `config/claude/lib/council_inference.py`.
**Test proves it (test-first):** across all error injections and a malformed `--fake-response`,
assert output contains no `Traceback|JSONDecodeError|KeyError` and exit code 0 for classified
results.
**Done-criterion:** REQ-INF-014 assertions green; no traceback strings; exit 0 on classified.
**Maps:** REQ-INF-014, NFR-INF-002, TRC-INF-009.

### Task 16 — Reusable stable signature (REQ-INF-019)
**Goal:** A stable result object (consistent keys: `code`, `decision`/`status`, completion
text field, estimate fields, reconciliation fields) so Slice 2/3 callers branch
deterministically on `code`.
**Files:** `config/claude/lib/council_inference.py`.
**Test proves it (test-first):** importlib block calls the public inference function directly
(not just the CLI) with an injected `transport=` fake and asserts the returned dict has the
documented stable keys for both a success and an error case.
**Done-criterion:** REQ-INF-019 assertions green; public function callable with `transport=`
seam; stable keys present.
**Maps:** REQ-INF-019, GOAL-INF-007, TRC-INF-001.

### Task 17 — `.env.example`: budget var + LOUD USD warning + model field (NFR-INF-004/005)
**Goal:** Append the inference block: `COUNCIL_MAX_TOKENS_PER_RUN=20000`, a LOUD comment that
the cap is **token-only, NOT a USD/spend guard**, and `COUNCIL_INFERENCE_MODEL=` (free
default, runtime-verified). `.env` stays gitignored (already line 12).
**Files:** `.env.example`.
**Test proves it (test-first):** `test_council_inference.sh` greps `.env.example` for
`COUNCIL_MAX_TOKENS_PER_RUN=20000`, for the loud USD-warning marker
(e.g. `NOT a USD` / `WARNING`), and for `COUNCIL_INFERENCE_MODEL`; asserts `.env` is in
`.gitignore`.
**Done-criterion:** EV-INF-005 grep assertions green; cap default 20000 + USD warning + model
field present; `.gitignore` contains `.env`.
**Maps:** NFR-INF-004, NFR-INF-005, Sharpening #5, EV-INF-005, CAN-INF-EVN-002.

### Task 18 — Wire `test_council_inference.sh` into `run_all.sh` + py_compile
**Goal:** Add a `stage`/`bash config/claude/tests/test_council_inference.sh || fail=1` entry,
and add `config/claude/lib/council_inference.py` to the `py_compile` stage.
**Files:** `config/claude/tests/run_all.sh`.
**Test proves it (test-first):** running `bash config/claude/tests/run_all.sh` executes the
new stage (its banner appears in output) and the suite stays green.
**Done-criterion:** `bash config/claude/tests/run_all.sh` prints the inference stage banner
and exits 0 (ALL CHECKS PASSED); `git status` clean of stray files.
**Maps:** REQ-INF-015, AC-INF-014, CAN-INF-EVN-001, TRC-INF-010.

### Task 19 — Opt-in real smoke harness, OUTSIDE `run_all.sh`, env-gated (REQ-INF-016/017)
**Goal:** A separate harness (e.g. `config/claude/tests/smoke_council_inference.sh` — note:
this filename is NOT in the listed scope, so the smoke harness is instead added as a guarded
block that lives only when explicitly enabled; if a new file is needed, the smoke runner is
the orchestrator-run command documented in the benchmark, not a tracked test). It is gated by
an explicit env flag (e.g. `PLUMBLINE_INFERENCE_SMOKE=1`) so it can NEVER run in CI /
`run_all.sh`. Free model by default, configurable via `COUNCIL_INFERENCE_MODEL`. It
classifies-not-crashes: a non-empty completion OR a classified code (a free-model 402/429 is
NOT a code failure). Leak-check = 0.
**Files:** documented as an orchestrator-run invocation in
`docs/benchmarks/2026-06-19-openrouter-inference-smoke.md` (Phase 3). The smoke uses the SAME
`council_inference.py infer` CLI with the REAL transport (no `--fake-*`), against a live key
from `~/.openclaw/.env`. **It is never added to `run_all.sh`.**
**Test proves it:** the offline suite has a guard assertion that NO inference test performs a
real network probe (mirrors OD-3's reality-ledger guard); the smoke itself is evidence, not a
CI test.
**Done-criterion (Phase 3):** smoke run recorded in the benchmark file with a real captured
result (completion OR classified code), leak-check = 0; `run_all.sh` contains no real-network
inference call.
**Maps:** REQ-INF-016, REQ-INF-017, RISK-INF-007, AC-INF-015, EV-INF-006, TRC-INF-011.

### Task 20 — Smoke benchmark doc + OQ-3 contract verification (Phase 3)
**Goal:** Write `docs/benchmarks/2026-06-19-openrouter-inference-smoke.md` mirroring the OD-3
smoke doc: a "what this proves / does not" table; the live request/response shape and the
`usage.*` fields the reconciliation relies on, CONFIRMED at the smoke (OQ-3, EV-INF-007);
note presence/absence of any `cost` field; leak-check = 0. The chat/completions contract is
verified HERE, not hardcoded from memory.
**Files:** `docs/benchmarks/2026-06-19-openrouter-inference-smoke.md` (new; plain `#` heading,
no `---` frontmatter, per the additive-doc tripwire).
**Test proves it:** doc review (EV-INF-006/007). No `mcp__<family>__` literal is quoted in the
doc (avoid the dependencies-doc tripwire).
**Done-criterion (Phase 3):** benchmark file exists, records the live shape + `usage` fields +
`cost`-field note + leak-check 0; OQ-3 marked verified-at-smoke (for the probed model only).
**Maps:** REQ-INF-018, OQ-3, AC-INF-016, EV-INF-007, TRC-INF-012.

### Task 21 — Reality Ledger evidence.jsonl (Phase 3, honest classes)
**Goal:** Write `docs/reality/openrouter-inference.evidence.jsonl` mirroring the OD-3
evidence format: offline rows `integration-fake` (per REQ-INF-*), and the invocability +
post-call `usage` reconciliation rows `real-boundary-smoke` **for the ONE probed model only**.
Estimate-accuracy, broader invocability, and the `cost`-field assumption stay
`RED(confidence)` / `ungeprüft` (OQ-3) — recorded honestly, NOT downgraded.
**Files:** `docs/reality/openrouter-inference.evidence.jsonl` (new).
**Test proves it:** the `test_evidence_vocab.sh` stage (already in `run_all.sh`) validates the
evidence-class vocabulary; each row uses a valid class.
**Done-criterion (Phase 3):** evidence file present; offline rows `integration-fake`; smoke
rows `real-boundary-smoke` scoped to the one model; RED items present and NOT downgraded;
`run_all.sh` evidence-vocab stage green.
**Maps:** EV-INF-008, CAN-INF-EVN-005, RISK-INF-006, all TRC-INF-*.

### Task 22 — Traceability wired-in-prod + backlog + CLAUDE.md updates (Phase 3)
**Goal:** Flip the `wired-in-prod?` TBD cells in `docs/traceability.md` for TRC-INF-001..012
to their honest verified state (offline → tests int-fake; invocability/reconcile → smoke;
OQ-3 → verified-at-smoke for the one model); add a backlog row for the inference slice; add a
short CLAUDE.md process note if a recurring pattern is found (interactive gate — only on
explicit approval, per the learning loop).
**Files:** `docs/traceability.md`, `backlog.md`, `CLAUDE.md` (CLAUDE.md only if a rule is
approved).
**Test proves it:** doc review at Gate C/D; `run_all.sh` frontmatter validator stays green
(traceability/backlog are existing tracked docs).
**Done-criterion (Phase 3):** TRC-INF-* `wired-in-prod?` cells updated honestly; backlog row
added; `run_all.sh` green; `git status` shows only in-scope files.
**Maps:** all TRC-INF-*, DoD.

---

## Critical path

Task 1 → 2 → 3 → 4 → 5 → 7 → (8, 9, 10, 11 parallel) → 13 → 18 (offline green) →
[Phase 3] 19 → 20 → 21 → 22.
Tasks 6, 12, 14, 15, 16 are near-leaf and can interleave after Task 5/7. Task 17 (.env) is
independent and can land any time before Task 18.

## Honesty constraints (binding DoD — state these in every gate)

- **Offline tests are `integration-fake`** — fake transport, no network, no real key, 0
  credits. Green offline tests are NEVER treated as proof of real invocability.
- **The smoke earns `real-boundary-smoke` for ONE model only** (the probed model). No claim
  is made about other configured models.
- **Estimate-accuracy and broader invocability stay `RED(confidence)`.** I-3: the input
  heuristic's drift is MEASURED at the smoke (both deltas) and recorded, never asserted exact.
- **OQ-3 (chat/completions request/response shape incl. `usage.*`) is `ungeprüft`** until the
  smoke. The coder MUST NOT freeze the contract from memory; `usage` is `ableitbar` not
  `belegt` (I-1); a `cost` field is never assumed present and never relied on for
  reconciliation.
- **RED may not be silently downgraded; only the user reclassifies at the acceptance gate.**

## Constraint coverage (I-1 / I-2 / I-3)

- **I-1 (usage provenance / graceful degrade):** Task 9 (usage absent/misshaped → graceful,
  no fabricated counts, `cost` never required), Task 21 (recorded `ungeprüft`/`RED`).
- **I-2 (2xx-no-completion → `COUNCIL_MODEL_UNAVAILABLE`):** Task 11 (empty content,
  `{"error":...}` body, non-JSON 2xx all classified, deterministic, no crash).
- **I-3 (cap honesty / named heuristic + dual reconciliation):** Task 3 (named offline
  heuristic, approximate-labelled), Task 8 (reconcile BOTH input-estimate vs
  `usage.prompt_tokens` AND total), Task 17 (LOUD `.env.example` USD warning), Task 21
  (estimate-accuracy stays `RED(confidence)`, drift measured at smoke).

## Definition of Done (slice)

1. All MUST REQ-INF-001..018 satisfied; offline suite green under `run_all.sh` (0 credits).
2. `.env.example`: token-only cap default 20000 + LOUD USD warning + configurable model;
   `.env` gitignored.
3. Opt-in smoke (outside `run_all.sh`, env-gated) recorded in the benchmark: non-empty
   completion OR classified code, leak-check 0, OQ-3 contract verified-at-smoke.
4. `docs/reality/openrouter-inference.evidence.jsonl` + `docs/traceability.md` updated with
   honest classes; RED not downgraded.
5. `git status` clean of stray files; `run_all.sh` green; bench inputs never staged in-tree.
6. User confirmation at the acceptance gate (only the user reclassifies any RED).
