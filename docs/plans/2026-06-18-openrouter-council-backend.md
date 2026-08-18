# OpenRouter Council Backend — Phase 1 Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL — use `superpowers:executing-plans` to implement this
> plan task-by-task, strictly TDD-first. **No production code before a failing test.** One
> atomic concern per task. Show every diff before applying. Commit atomically.
> `bash config/claude/tests/run_all.sh` MUST end with `ALL CHECKS PASSED` after every task,
> and `shellcheck` (run inside that suite) must stay clean for every new/edited `.sh`.

**Feature-Slug:** openrouter-council-backend · **Slice:** OD-3 (B)
**Branch:** `agileteam/openrouter-council-backend`
**Spec (frozen, user-confirmed 2026-06-18):**
`docs/prd/openrouter-council-backend.prd.md`, `docs/canvas/…canvas.md`,
`docs/vision/…vision.md`, `docs/traceability.md` (Slice OD-3).

**Goal:** Add an optional OpenRouter backend to `/concilium`: a deterministic,
offline-testable Python lib (`config/claude/lib/council_backend.py`) mirroring the
house style of `plumbline_start.py` (pure classifier functions + `render_*` panel +
`argparse` CLI + injectable fake transport), the `/concilium` backend wiring + docs, the
`.env.example` knobs, the test module wired into `run_all.sh`, and updated traceability
wired-in-prod cells. Council bodies = the four files
`concilium/{market-realist,tech-arbiter,skeptic,distribution-realist}.md` (READ-ONLY).

**Tech stack:** Python 3 (stdlib only — no `requests`/no third-party HTTP dep; the real
transport seam is injected, the default fake transport needs nothing), Bash
(`set -uo pipefail`) + `lib.sh` assertions, `shellcheck`. No network, no real key in any
test.

**Architecture (house-style mirror of `plumbline_start.py`):** one module of *pure*
functions — `load_council_config`, `normalize_model_id`, `evaluate_diversity`,
`redact_secrets`, `load_role_prompt`, `build_report` — plus a `render_*` deterministic
panel and an `argparse` `main()` with a `--json` seam. The OpenRouter call sits behind a
**`transport` callable parameter** that defaults to an in-module `fake_transport`; tests
inject their own fake, so no test touches the network or a key. The real HTTP transport
is the *only* part that is `integration-fake` until a real-boundary smoke runs.

---

## Standing constraints (read before Task 0)

- **Stay inside the canvas Allowed change scope** (machine-parseable list, canvas §9):
  `.env.example`, `config/claude/lib/council_backend.py`,
  `config/claude/commands/concilium.md`, `config/claude/tests/test_council_backend.sh`,
  `config/claude/tests/run_all.sh`, `docs/traceability.md`, this plan file, `.gitignore`.
  `concilium/*.md` are **READ-ONLY** (Source of Truth — never edit to make a test pass).
- **Test-the-test:** no behavior lands without a *failing* test observed first (RED→GREEN),
  and every fail-closed / redaction check carries a negative fixture proven to fail.
- **No hardcoded real Free-model IDs as truth** (REQ-B-009, NGOAL-B-002). Fixtures use
  obviously-synthetic slugs (e.g. `vendor-a/model-x`, `vendor-a/model-x:nitro`).
- **Never print the raw key.** `OPENROUTER_API_KEY` must not appear in config dumps,
  errors, reports, or test output (REQ-B-016).
- **No silent fallback to Claude-only while fail-closed is active** (REQ-B-013); an
  explicit Claude-only mode is allowed *only with disclosure* (EDGE-B-007 / AC-B-010).
- **Green gate before every commit:** `run_all.sh` ends with `ALL CHECKS PASSED`.

---

## Reality-Ledger / honesty DoD (binding — do not soften)

- The default `fake_transport` makes the lib tests **`integration-fake`**, never
  `real-boundary-smoke`. **All-mock-green is NOT proof of real model diversity.** The
  "echte Diversität" claim stays **PASS(tests) / RED(confidence)** per the Reality Ledger
  until EV-B-007 (an optional real-boundary smoke, outside repo/tests, no key leak) runs.
  Tasks must not relabel any `*-fake` trace cell as `real-boundary-smoke` "verified".
- The diversity gate (base-slug normalization) is **necessary, not sufficient**: it
  removes variant-alias Schein-Diversität but cannot prove two genuinely different slugs
  aren't the same/mirrored model (RISK-B-007). The plan implements the gate and *documents
  this limitation*; it does not claim the gate proves diversity.
- **OQ-B-004 (reachability METHOD) is an OPEN QUESTION** — `ungeprüft`. The lib must keep
  reachability behind the injected transport and must **not silently hardcode one
  definition** of "reachable" (catalog/list-models vs. probe-completion) nor assume
  `reachable == invocable` (a listed model can still 402/429 for the user's key/credits).
  Task 9 is the explicit impl-time live-API verification task and stays `ungeprüft` in
  prose until a human verifies it.

---

## Task list (atomic, dependency-ordered)

| ID | One-line | Primary REQ-IDs | Depends on |
|----|----------|-----------------|------------|
| T0 | Confirm clean tree on the feature branch (git only) | — | — |
| T1 | RED: create `test_council_backend.sh` + wire into `run_all.sh` (asserts module/CLI exist) | REQ-B-015 | T0 |
| T2 | Config loader: 4 uppercase slots + key read, no key exposure | REQ-B-002,004,005,006,006b | T1 |
| T3 | Lowercase aliases `council_1..4` + uppercase precedence | REQ-B-007, REQ-B-008 | T2 |
| T4 | Model-ID normalization (strip `:nitro/:floor/:exacto/:<variant>` → base slug) | REQ-B-011 | T1 |
| T5 | Diversity gate: count distinct normalized base IDs vs `COUNCIL_MIN_BACKENDS`, fail-closed `COUNCIL_DIVERSITY_UNAVAILABLE` | REQ-B-011,012,013,017,020 | T4 |
| T6 | Secret redaction helper (key never in config/error/report output) | REQ-B-016 | T2 |
| T7 | Prompt loader from `concilium/*.md`, deterministic fail-closed `prompt-missing` | REQ-B-010, REQ-B-019 | T1 |
| T8 | Report/disclosure formatter (role + model-ID + backend + prompt source) + CLI seam + injectable fake transport | REQ-B-014,019; REQ-B-015 | T5,T6,T7 |
| T9 | Reachability METHOD verification task (live OpenRouter API, OQ-B-004) — marked `ungeprüft` | REQ-B-011 (OQ-B-004) | T8 |
| T10 | `.env.example`: 4 slots + COUNCIL_* knobs (align PRD §7) + `.gitignore` `.env` | REQ-B-003, REQ-B-018 | T1 |
| T11 | `/concilium` wiring + docs: `COUNCIL_BACKEND` flag, no silent fallback, disclosure | REQ-B-001,013,020; AC-B-010 | T8,T10 |
| T12 | Update `docs/traceability.md` wired-in-prod cells (honest: fake cells stay fake) | all B traces | T11 |
| T13 | Full-suite green + clean-tree verification gate | DoD | T1–T12 |

---

## Task 0: Isolate the work

**Files:** none (git only).
- Confirm clean tree, branch is `agileteam/openrouter-council-backend`:
  `git -C "$REPO" status --short && git -C "$REPO" rev-parse --abbrev-ref HEAD`
- **Done-criterion (machine-checkable):** `git status --short` empty AND current branch
  `== agileteam/openrouter-council-backend`.

---

## Task 1: RED scaffold — test module + run_all wiring

**Goal:** Stand up the failing test harness *first* (test-first for the whole module).
**Files:** create `config/claude/tests/test_council_backend.sh`; edit
`config/claude/tests/run_all.sh`.
**Test (the test that proves it):** the new bash module sources `lib.sh`, asserts
`config/claude/lib/council_backend.py` exists and `python3 -m py_compile` of it succeeds,
and asserts `python3 config/claude/lib/council_backend.py --help` exits 0. Add a stage in
`run_all.sh` (`bash config/claude/tests/test_council_backend.sh || fail=1`) and add the new
module to the `py_compile` stage list.
**Expected RED:** suite fails because `council_backend.py` does not exist yet.
**Done-criterion:** `run_all.sh` now invokes the council stage and the suite is RED *only*
on the missing-module assertions (no syntax errors in the test, shellcheck clean). This is
the observed-failing baseline the rest of the tasks turn GREEN.

---

## Task 2: Config loader — 4 uppercase slots + key read (no exposure)

**Goal:** `load_council_config(env: Mapping) -> dict` reads `COUNCIL_1_MODEL..COUNCIL_4_MODEL`,
`OPENROUTER_API_KEY`, `COUNCIL_BACKEND`, `COUNCIL_FAIL_CLOSED`, `COUNCIL_MIN_BACKENDS`,
`COUNCIL_TIMEOUT_SECONDS` from an **injected env mapping** (not `os.environ` directly, so
tests need no global env). Returns four slot values + knobs; the key is held but the
returned dict must not surface it in any `str()`/repr/printed form.
**Files:** create `config/claude/lib/council_backend.py` (function `load_council_config`).
**Test:** AC-B-001 — pass a fake env with all four `COUNCIL_n_MODEL` set + `OPENROUTER_API_KEY`;
assert all four slots returned, and assert the rendered config panel / JSON does **not**
contain the key literal.
**Done-criterion (EV-B-001):** test passes; `grep -F "$FAKEKEY"` over the loader's
printed/JSON output finds **zero** matches; four slots present.

---

## Task 3: Lowercase aliases + uppercase precedence

**Goal:** support optional `council_1..4` lowercase aliases; **uppercase wins** when both
present.
**Files:** edit `council_backend.py` (`load_council_config`).
**Test:** AC-B-002 (lowercase-only env → values map into slots) AND AC-B-003 (both set →
`COUNCIL_1_MODEL` value wins). Both as separate assertions with distinct fixtures.
**Done-criterion (EV-B-001):** lowercase-only fixture yields the alias values in slots;
mixed fixture yields the uppercase value (assert exact slot string equality).

---

## Task 4: Model-ID normalization

**Goal:** `normalize_model_id(raw: str) -> str` strips known variant/price/provider
suffixes — `:nitro`, `:floor`, `:exacto`, and any `:<variant>` suffix — to the base slug,
so two variant IDs of one base model normalize to one slug. (Generic `:<variant>` strip,
not a closed list, per REQ-B-009: don't hardcode a fixed model list.)
**Files:** edit `council_backend.py` (`normalize_model_id`).
**Test:** table-driven — `vendor-a/model-x:nitro`, `vendor-a/model-x:floor`,
`vendor-a/model-x:exacto`, `vendor-a/model-x:somethingelse` all → `vendor-a/model-x`;
`vendor-a/model-x` (no suffix) → unchanged; `vendor-b/model-y` → unchanged (distinct).
**Done-criterion:** every table row asserts exact normalized output equality; the four
variant inputs collapse to one base slug.

---

## Task 5: Diversity gate — fail-closed on `< COUNCIL_MIN_BACKENDS`

**Goal:** `evaluate_diversity(slots, min_backends, reachable) -> dict` counts **distinct
normalized base slugs** among *reachable* configured models; if count `< min_backends`
(default 2) returns a fail-closed verdict carrying the exact token
`COUNCIL_DIVERSITY_UNAVAILABLE`; otherwise a may-proceed verdict. Network/reachability
failure is reported as **unavailability**, never as a successful council (REQ-B-017). No
silent Claude-only fallback while fail-closed (REQ-B-013).
**Files:** edit `council_backend.py` (`evaluate_diversity`).
**Test:** AC-B-004 (0 reachable → abort `COUNCIL_DIVERSITY_UNAVAILABLE`), AC-B-005 (1
reachable → abort), AC-B-006 (≥2 distinct *normalized* reachable → may proceed),
EDGE-B-002 (4 slots all variant-IDs of one base, e.g. `:nitro` vs `:floor` → normalize → 1
distinct → fail-closed). All use injected `reachable` data — no transport call.
**Done-criterion (EV-B-002):** 0- and 1-model and same-base cases each yield a verdict
whose message contains `COUNCIL_DIVERSITY_UNAVAILABLE` and `proceed == False`; the ≥2
distinct-base case yields `proceed == True`. Negative fixture (the same-base case) proven
to flip the gate.

---

## Task 6: Secret redaction

**Goal:** `redact_secrets(text: str, secret: str) -> str` replaces the key with a fixed
mask (e.g. `***REDACTED***`); applied by all panel/error/report rendering so the raw key
can never surface (RISK-B-001).
**Files:** edit `council_backend.py` (`redact_secrets` + apply in renderers).
**Test:** AC-B-009 — feed a config error / report string that *would* embed the key; assert
the raw key is absent and the mask present. Negative-shaped: a pre-redaction string
containing the key is shown (in the test only) to confirm the function actually removes it.
**Done-criterion (EV-B-003):** `grep -F "$FAKEKEY"` over every renderer's output = 0
matches across config, error, and report paths.

---

## Task 7: Prompt loader — `concilium/*.md`, fail-closed on missing

**Goal:** `load_role_prompt(body: str, base_dir) -> str` loads the editable base prompt
from `concilium/{market-realist,tech-arbiter,skeptic,distribution-realist}.md`; a missing
file yields a deterministic fail-closed error classified `prompt-missing` (EDGE-B-005). The
report must be able to name the prompt source path (REQ-B-019).
**Files:** edit `council_backend.py` (`load_role_prompt`). `concilium/*.md` READ-ONLY.
**Test:** AC-B-007 — point loader at a temp dir whose role file has known edited content;
assert the returned prompt equals that content (proves edits are honored, not a hardcoded
copy). Missing-file case → error string contains `prompt-missing`.
**Done-criterion (EV-B-004):** edited-file content round-trips exactly; missing-file path
returns a `prompt-missing`-classified fail-closed error (assert substring), no traceback
leak.

---

## Task 8: Report/disclosure formatter + CLI seam + injectable fake transport

**Goal:** `build_report(...)` emits, per role: role name, **used model ID**, backend name,
and prompt-source path (AC-B-008). Add `render_council_panel` (deterministic, mirrors
`render_status_panel`) and `main()` with `argparse` + `--json` seam (mirror
`plumbline_start.py`). Define an in-module **`fake_transport`** callable as the default
`transport` parameter so the CLI and tests run with zero network/key; the real HTTP
transport is a separate injectable callable (left as the only `integration-fake` seam).
**Files:** edit `council_backend.py` (`build_report`, `render_council_panel`, `main`,
`fake_transport`, `if __name__ == "__main__"`).
**Test:** AC-B-008 / SS-B-005 — run the CLI/report with the fake transport returning ≥2
distinct normalized models; assert the report text contains each role name, its model ID,
the backend name, and the prompt-source path; assert `--json` emits the same structured
data. Reconfirm no key in output.
**Done-criterion (EV-B-005):** report snapshot contains all four roles each with
model-ID + backend + prompt-source; `--json` round-trips; `grep -F "$FAKEKEY"` = 0.

---

## Task 9: Reachability METHOD verification (OQ-B-004 — live API, `ungeprüft`)

**Goal:** Resolve OQ-B-004 *at implementation time* against the **live OpenRouter API**:
determine whether reachability is checked via catalog/list-models or a probe-completion,
and confirm the `reachable ≠ invocable` distinction (a listed model can still 402/429 for
the user's key/credits). Wire the chosen METHOD into the real transport seam from T8. **Do
NOT silently hardcode one definition.** Until a human verifies against the live API, the
reachability premise stays **`ungeprüft`** and the real-diversity claim stays
RED(confidence).
**Files:** edit `council_backend.py` (real transport seam docstring/behavior only) — no
fixture/network in the test suite.
**Test:** *no automated test asserts live behavior* (would require a key/network — out of
scope per REQ-B-015). Instead: a code comment + the plan/traceability mark this
`ungeprüft`; the suite only asserts the fake transport seam is the default (already T8).
**Done-criterion:** the module documents the reachability METHOD as an explicit,
human-verifiable assumption (`ungeprüft until impl-verified against live OpenRouter API`);
no single definition is baked as truth; EV-B-007 (real-boundary smoke) remains future/
optional and is **not** claimed done. (This task is a *verification obligation*, not a
green-test claim — surface it to the human, do not auto-resolve.)

---

## Task 10: `.env.example` + `.gitignore`

**Goal:** Add `.env.example` exactly aligned to PRD §7 (`COUNCIL_BACKEND=mock`,
`COUNCIL_FAIL_CLOSED=true`, `COUNCIL_MIN_BACKENDS=2`, `COUNCIL_TIMEOUT_SECONDS=45`,
`OPENROUTER_API_KEY=` empty, `OPENROUTER_HTTP_REFERER=`, `OPENROUTER_APP_TITLE=Plumbline`,
`COUNCIL_1_MODEL..COUNCIL_4_MODEL=` empty, `council_1..4=` empty) with the "never commit
real secrets" header; ensure `.gitignore` ignores `.env` (REQ-B-003 / NGOAL-B-001).
**Files:** create `.env.example`; edit `.gitignore` (add `.env` if absent).
**Test (EV-B-006):** extend `test_council_backend.sh` — assert `.env.example` exists,
contains all four `COUNCIL_n_MODEL` keys + the four lowercase aliases + each `COUNCIL_*`
knob, has an empty `OPENROUTER_API_KEY=` value, and contains **no** value after
`OPENROUTER_API_KEY=` (grep `^OPENROUTER_API_KEY=$`); assert `.gitignore` contains `.env`.
**Done-criterion:** all grep assertions pass; `git check-ignore .env` returns `.env`.

---

## Task 11: `/concilium` backend wiring + docs

**Goal:** Document and wire the optional backend in `config/claude/commands/concilium.md`:
the `COUNCIL_BACKEND` feature flag (default `mock`; `openrouter` opt-in), that the four
bodies can run on `.env`-configured OpenRouter models via `council_backend.py`, the
fail-closed diversity gate (`COUNCIL_DIVERSITY_UNAVAILABLE`, no silent Claude-only
fallback), report disclosure of model IDs, and the explicit-Claude-only-with-disclosure
exception (EDGE-B-007 / AC-B-010). Keep `concilium/*.md` as prompt Source of Truth.
**Files:** edit `config/claude/commands/concilium.md`. (READ-ONLY: `concilium/*.md`.)
**Test:** extend `test_council_backend.sh` with `grep -qF` assertions that `concilium.md`
documents `COUNCIL_BACKEND`, `council_backend.py`, `COUNCIL_DIVERSITY_UNAVAILABLE`, "no
silent fallback" (or equivalent wired phrase), and the disclosure rule. **Wired-in-prod
guard:** assert the command file actually references `council_backend.py` (the production
composition root) — not merely that the lib exists in tests.
**Done-criterion:** all `grep -qF` assertions pass; `concilium.md` names `council_backend.py`
(proves the lib is composed in the prod command path, not test-only); frontmatter
unchanged (still parses, still has `description`); `build-explorer.sh` not required (no
agent frontmatter changed) — but if any `**/*.md` frontmatter shifts, re-run the validator.

---

## Task 12: Traceability — wired-in-prod cells (honest)

**Goal:** Update `docs/traceability.md` Slice OD-3 `wired-in-prod?` cells from `TBD` to
the honest state now that the lib is composed via `concilium.md`. **Do not** upgrade any
`integration-fake` evidence-class to `real-boundary-smoke`/`production-verified` — the
three reachability/diversity traces (TRC-B-001/011/012/013/017) keep their
`real-boundary-smoke` *target* but stay **RED(confidence)/fake-actual** until EV-B-007.
Mark them explicitly (e.g. `wired (lib) / RED(confidence) — fake-transport; real boundary = EV-B-007 pending`).
**Files:** edit `docs/traceability.md`. (Additive doc edit — no new frontmatter; keep the
existing `#` heading; do not introduce `mcp__<family>__` literals.)
**Test:** extend `test_council_backend.sh` — assert no Slice-OD-3 `wired-in-prod?` cell
still reads `TBD`, and assert the reachability/diversity rows still carry a `RED` /
`EV-B-007` marker (the honesty tripwire — green tests must not silently become
"production-verified").
**Done-criterion:** `grep` finds zero `TBD` in the OD-3 wired-in-prod column AND the
RED(confidence)/EV-B-007 marker present on the diversity/reachability rows;
`test_dependencies_doc.sh` still green (no new MCP family literal introduced).

---

## Task 13: Full-suite green + clean-tree gate

**Goal:** Final defense-in-depth verification.
**Files:** none.
**Test/commands:**
- `bash config/claude/tests/run_all.sh` → ends `ALL CHECKS PASSED` (shellcheck clean).
- `git status --short` clean except the in-scope changed files.
- `git diff --name-only` ⊆ the canvas Allowed change scope (no stray files, esp. nothing
  under `metrics/` or `concilium/*.md`).
**Done-criterion:** suite GREEN; changed-files set is a subset of the Allowed change scope;
no `*.md` duplicate-`name:` regression; reachability/real-diversity honesty markers intact
(EV-B-007 still pending, not claimed done).

---

## Definition of Done (slice)

- All MUST requirements (incl. REQ-B-006b) covered by a passing test: config loader (4
  slots + alias + precedence), normalization, diversity fail-closed
  (`COUNCIL_DIVERSITY_UNAVAILABLE`), redaction, prompt loader, report disclosure.
- `.env.example` (4 slots + knobs) present, `.env` gitignored, no real key.
- `/concilium` wired to `council_backend.py` behind `COUNCIL_BACKEND`; no silent fallback;
  disclosure documented.
- `test_council_backend.sh` wired into `run_all.sh`; full suite `ALL CHECKS PASSED`.
- Traceability OD-3 wired-in-prod cells updated honestly.
- **Honesty (binding):** fake-transport = `integration-fake`; all-mock-green is NOT proof
  of real diversity — the real-diversity claim stays **PASS(tests)/RED(confidence)** until
  EV-B-007 real-boundary smoke (out of repo/tests). OQ-B-004 reachability METHOD stays
  `ungeprüft` until human-verified against the live OpenRouter API.
- Human acceptance gate (Ben) before merge — green tests + agent consensus are not
  sufficient on their own (True-Line governance).
