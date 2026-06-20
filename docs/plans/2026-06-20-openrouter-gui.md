# Build Plan — OpenRouter Council-Runner GUI (Slice 4)

Phase 1 (planner) build plan. PLAN ONLY — no production code is written here; nothing is
committed. Branch: `agileteam/openrouter-gui` (branched from `main`, one feature per
branch surface).

- Feature-slug: `openrouter-gui`
- Canvas (user-confirmed, Ben 2026-06-20): `docs/canvas/openrouter-gui.canvas.md`
- PRD (finalized, REQ-GUI-001..017, AC-1..AC-10): `docs/prd/openrouter-gui.prd.md`
- Vision (user-confirmed): `docs/vision/openrouter-gui.vision.md`
- Spec-sanity: remediated 2026-06-20 (Phase 0.5) — hardening, not value reversal.

## Premise verification (read against the real files before planning — belegt)

The whole plan rests on the frozen Slice-1/2 primitive contract. Re-verified against the
real source at plan time (not from memory):

- `config/claude/lib/deepseek_review.py` exposes a `preset` subcommand whose parser
  (`p_pre`) carries exactly: `--preset` (default `council_presets.DEFAULT_PRESET`),
  `--subject`, `--dry-run`, `--live`, `--inject-response`, `--inject-error`,
  `--inject-catalog`, `--inject-call-counter`, and the shared `--json`.
- `_cmd_preset` assembles `{"code": overall, "positions": [...], "diversity": {...}}` where
  `overall = CODE_OK ("COUNCIL_INFERENCE_OK") if all(p["code"]==CODE_OK) else
  CODE_MODEL_UNAVAILABLE ("COUNCIL_MODEL_UNAVAILABLE")`, and `positions` is **always**
  populated per role (`role`, `character`, `model`, `code`, `position`). This is the
  load-bearing basis for the MIXED render (REQ-GUI-017): a non-OK overall STILL carries OK
  positions. Verified.
- `diversity` = `{distinct_bases, gate, disclosure}`; `disclosure` carries the RISK-B-007
  text. Verified.
- The character root resolves via `_characters_dir()` = `$DEEPSEEK_CHARACTERS_DIR` or the
  RELATIVE `concilium/characters`. From the wrong cwd with no env, every role resolves
  `character-missing`. This is the basis for the launcher cwd-pin + fail-loud precondition
  (REQ-GUI-014/016). Verified.
- The real transport arms ONLY under `--live` AND `COUNCIL_INFERENCE_LIVE=1`; otherwise
  transport is None and ZERO network calls occur (the live-gate the proxy mirrors, never
  re-implements). Verified.

If any of these drift before/during the build, STOP — the proxy is a pass-through; a
changed contract is a spec event, not a code workaround.

## Architecture (the spec-sanity decision the plan must encode)

A single local operator, loopback-only. Two real surfaces + static assets:

1. **`config/claude/gui/openrouter_gui_proxy.py`** — Python stdlib `http.server` only (no
   new deps). Serves the static UI on `GET`; accepts `POST /run {subject, preset, mode}`.
   - **Subprocess, not in-process import (REQ-GUI-013):** in `mode=live` it SHELLS OUT to
     `python3 config/claude/lib/deepseek_review.py preset --subject <subject> --preset
     <A|B|C> --json [--live]` as a CHILD process. The handler does NOT `import
     deepseek_review`/`council_inference` for the run path.
   - **Key in child env ONLY (NFR-GUI-SEC-4):** `OPENROUTER_API_KEY` is placed ONLY in the
     spawned child's `env=`; the HTTP handler NEVER reads the key into its own locals, so a
     handler traceback cannot close over or leak it. (The handler may read it ONLY to copy
     it into the child env in a function that does not retain it — or, preferably, pass the
     ambient env through to the child and never touch the variable by name in the handler.)
   - **Pass-through (REQ-GUI-010):** the child's stdout JSON is rendered to the browser
     **unchanged** — `code`, `positions[]`, `diversity{}`. No new fields; no transform.
   - **Inject-council seam (REQ-GUI-009) — the OFFLINE MVP path:** an injection point
     (constructor arg / env-gated canned-JSON path) that returns canned `preset`-shaped
     JSON WITHOUT spawning a subprocess, WITHOUT a key, WITHOUT any OpenRouter call. The
     offline MVP renders INJECTED/demo positions — NOT real council reasoning (MVP-honesty,
     spec-sanity decision 3).
   - **Key-absence ASSERTION (REQ-GUI-005), not a mutation:** the proxy asserts that served
     assets + every response body + logs contain no `OPENROUTER_API_KEY` sentinel — a
     denylist-ABSENCE check. It MUST NOT strip/rewrite the council JSON to "pass".
   - **Generic-500 + no-secret-logging (REQ-GUI-015, NFR-GUI-OBS-1):** any handler
     exception → a GENERIC 500 with NO traceback, NO request body, NO env in the response
     OR the log. The proxy logs no request bodies and no environment.
   - **Loopback default (REQ-GUI-007):** binds `127.0.0.1`; any non-loopback bind requires
     an explicit separate opt-in (OUT of MVP default).
   - **Live refusal when gate OFF (REQ-GUI-008):** `mode=live` while the server-side gate
     (`COUNCIL_INFERENCE_LIVE`) is OFF → REFUSE the live run (classified), do NOT silently
     downgrade to offline. No live run is in the MVP acceptance path.

2. **`config/claude/bin/plumbline-council-gui`** — the launcher (bash, like the other
   `config/claude/bin/plumbline-*` wrappers).
   - **Pins cwd to repo-root** (and/or exports `DEEPSEEK_CHARACTERS_DIR`) so the relative
     `concilium/characters` resolves for the child (REQ-GUI-013).
   - **Enforces the 3 real-path preconditions FAIL-LOUD (REQ-GUI-014)** before driving the
     REAL council: (a) `OPENROUTER_API_KEY` present (env first, then `~/.openclaw/.env`;
     missing → classified `COUNCIL_MISSING_SECRET`, ZERO calls); (b) a catalog with ≥2
     DISTINCT free families (else `resolve_preset` aborts before any call); (c)
     cwd==repo-root or `DEEPSEEK_CHARACTERS_DIR` set (else every role `character-missing`).
   - **NEVER renders a plausible all-`character-missing` / all-error result as if the
     council ran with no opinion** — a missing precondition is a LOUD classified error.

3. **Static UI (REQ-GUI-002/003/004/011/012/017)** — vanilla JS, no build step:
   - `config/claude/gui/static/index.html` — paste box (`subject`), preset selector
     (A/B/C), mode (offline default), Run button, results region.
   - `config/claude/gui/static/app.js` — POST `{subject, preset, mode}`; render every
     `positions[]` entry (role/model + `position`, or the classified `code` when
     `position` is null); render the `diversity` block (`distinct_bases`, `gate`,
     `disclosure`); render the RISK-B-007 "no verdict" disclosure beside it; render the
     MIXED state honestly (OK positions AND per-role classified codes — never one error
     banner that hides OK positions, never a fake success); escape pasted/rendered content
     (no `eval`, no `innerHTML` of untrusted text — use `textContent`).
   - `config/claude/gui/static/style.css` — presentation only.

## Build-step → REQ/AC map

| Step | Artifact(s) | REQs covered | ACs | Reality-ledger class |
|------|-------------|--------------|-----|----------------------|
| S0 | (tests) `test_gui_proxy.sh`, `test_gui_security.sh` written RED first | — (drives all) | all | n/a |
| S1 | `openrouter_gui_proxy.py`: loopback bind + static serve + `POST /run` inject-council seam (offline) → pass-through render | REQ-GUI-001/002/003/009/010 | AC-1 | integration-fake |
| S2 | `app.js`/`index.html`/`style.css`: render positions[] + diversity + RISK-B-007 disclosure; escape input | REQ-GUI-002/003/004/011 | AC-1/AC-5 | integration-fake |
| S3 | Key-leak gate: served-assets + response-body + log absence ASSERTION (no mutation) | REQ-GUI-005/006 | AC-2 / SEC | integration-fake |
| S4 | Loopback-default assertion; live-gate OFF-by-default + live-refusal | REQ-GUI-007/008 | AC-3/AC-4 / SEC | integration-fake |
| S5 | Subprocess wiring + key-in-child-env-only (handler reads no key into locals) | REQ-GUI-013 | AC-9 / SEC | integration-fake |
| S6 | Induced-error leak resistance + generic-500 (malformed POST / oversized / broken pipe); no body/env logging | REQ-GUI-005/015 | AC-8 / SEC | integration-fake |
| S7 | Classified-error surfacing (non-OK `code` unchanged, no generic error/fake success) | REQ-GUI-012 | AC-6 | integration-fake |
| S8 | MIXED/partial render honesty (overall MODEL_UNAVAILABLE with some OK positions) | REQ-GUI-017 | AC-10 | integration-fake |
| S9 | `plumbline-council-gui` launcher: cwd-pin + 3 fail-loud preconditions; wired-in-prod headline run + from-wrong-cwd test | REQ-GUI-014/016 | AC-7/AC-9 / SEC | integration-fake |
| S10 | No-re-implementation source guard (no transport/preset/diversity re-derivation) | REQ-GUI-010 | SEC | integration-fake |
| S11 | Wire both test files into `run_all.sh`; author `docs/reality/openrouter-gui.evidence.jsonl` (one record per load-bearing REQ at `integration-fake`); complete `docs/trace/openrouter-gui.trace.md` | all (evidence) | all | integration-fake |

Every REQ-GUI-001..017 and AC-1..AC-10 maps to at least one step above; the
`AC-LIVE` / `real-boundary-smoke` line is DEFERRED and OUT of this MVP (OQ-5).

## TDD order (tester's RED suites first; one falsifier per branch)

Independence: the tester derives the suites; the coder makes them green; the coder does
not review. Order is chosen so the leak gate + wired-in-prod + preconditions are BUILT and
PROVEN, never bolted on.

1. **S0 — RED suites first.** `test_gui_proxy.sh` (functional: AC-1/AC-4/AC-6/AC-7/AC-9/
   AC-10 + REQ-GUI-009 call-count==0) and `test_gui_security.sh` (AC-2/AC-3/AC-8 + SEC
   matrix: leak absence, loopback default, induced-error/generic-500, key-in-child-only,
   no-re-implementation). They MUST fail before any production code (no production code
   before a failing test). Use `config/claude/tests/lib.sh` helpers
   (`assert`, `assert_eq`, `assert_contains`, `assert_not_contains`, `assert_no_code_token`,
   `finish`). Leak/escape assertions use the param-passed `assert_not_contains` helper —
   **never `eval` over payload content** (Slice-2 eval-payload rule).
2. **S1→S2 — offline paste→run→render green (AC-1, AC-5).** Drive the inject-council seam;
   assert positions[] + diversity + disclosure render and the live-transport call counter
   is exactly 0 (REQ-GUI-009). This proves the happy offline path and the render contract.
3. **S3→S4 — security floor green (AC-2/AC-3/AC-4).** Leak-absence assertion over served
   assets + response bodies + logs; loopback-default assertion; live OFF-by-default +
   refuse-on-gate-OFF. Built early so it is a floor, not an afterthought.
4. **S5→S6 — key-in-child + induced-error leak resistance green (AC-8, REQ-GUI-013).**
   Assert the handler source reads no `OPENROUTER_API_KEY` into its locals
   (`assert_no_code_token` over the proxy, scoped like the Slice-3 import-purity guards);
   force malformed POST / oversized body / broken pipe and assert the key sentinel is
   absent from BOTH the response body AND captured stderr/log, and the response is a
   generic 500 with no traceback/body/env.
5. **S7→S8 — classified + mixed render green (AC-6, AC-10).** Inject a non-OK `code` and a
   MIXED preset response (`overall: COUNCIL_MODEL_UNAVAILABLE` with some OK positions); the
   MIXED test FAILS if the UI collapses to one error banner or hides OK positions — a
   per-branch falsifier, not an outcome-only assertion.
6. **S9 — wired-in-prod via the REAL launcher green (AC-7, AC-9) — built EARLY, not last.**
   A test STARTS the real `plumbline-council-gui` (not only an in-process handler) and
   drives the offline headline paste→run→render through it; a from-wrong-cwd start asserts
   fail-loud-or-resolve — NEVER a plausible all-`character-missing` render. This is the
   counter to the repo's signature "injectable seam green, real entrypoint dead"
   false-green: the launcher's cwd-pin + key-in-child + preconditions are exercised
   through the REAL entrypoint, offline (no real boundary crossed).
7. **S10 — no-re-implementation guard green (REQ-GUI-010).** `assert_no_code_token` /
   source scan over the proxy: no transport/preset/diversity/cap/live-gate re-derivation.
8. **S11 — wire into `run_all.sh`** (`bash config/claude/tests/test_gui_proxy.sh ||
   fail=1` and `... test_gui_security.sh || fail=1`, each under a `stage` line, in the
   existing pattern) and author the Reality Ledger + trace matrix. Confirm full
   `run_all.sh` green and `git status` clean.

## Reality Ledger (authored in Phase 3 / Gate C)

`docs/reality/openrouter-gui.evidence.jsonl` — one record per load-bearing REQ at its TRUE
class. **Every record is `integration-fake`** (OQ-5: the MVP crosses NO real boundary; the
real launcher is started and the headline path runs against canned/injected JSON, which
proves the entrypoint is WIRED without crossing the OpenRouter boundary). Do NOT raise any
class to clear the default `integration` floor; run `plumbline-reality-check
--min-evidence integration` (the honest floor for this slice). Avoid the FORBIDDEN_TOKENS
(`fake-only`/`mock-only`/`placeholder`/`unverified`) in the ledger text. NO
`real-boundary-smoke` record is expected here — it is deferred to the later live slice.

## Defense-in-depth gate sequence (Phase 3 → human acceptance)

- Gate A (independent code-reviewer): per-branch falsifier check — each claimed detection/
  decision path (offline render, leak gate, generic-500, mixed render, fail-loud
  preconditions) has ≥1 test that FAILS if that branch is removed. A branch with no
  path-specific test is RED, not covered.
- Gate B (security-reviewer): SEC matrix — leak absence (browser + logs + induced error),
  loopback default, key-in-child-only, no `eval` of payload, no re-implementation drift.
- Gate C (Reality Ledger authored, `plumbline-reality-check` green at `integration`).
- Gate D (product-owner / judgment): does the offline MVP honestly say it renders
  INJECTED/demo positions, not real council reasoning? No value verdict implied.
- Gate E (`plumbline-watcher` True-Line): canvas/PRD/vision all `user-confirmed`/finalized
  and self-consistent; scope confirmed parseable.
- Human acceptance (Ben).

## Key risks & sequencing

- **"Injectable seam green, real entrypoint dead" (the repo's signature false-green).**
  The inject-council seam can be 91/91 green while the real subprocess launcher path is
  never reached. MITIGATION: build the REAL `plumbline-council-gui` launcher path EARLY
  (S9, not last); ship a paired FALSIFYING test (counter-based — fails if the real wiring
  is reverted), plus the from-wrong-cwd test; run the wired-in-prod headline through the
  REAL launcher before acceptance.
- **Key leak (highest severity).** The key is resident whenever the real path is usable, so
  the leak gate runs at FULL strength in the offline MVP — NOT reduced by offline mode.
  MITIGATION: key in child env only; handler reads no key into locals (source-asserted);
  induced-error/generic-500; no body/env logging; leak-absence asserted over assets +
  bodies + logs.
- **No `eval` over payload content in tests.** Use `assert_not_contains` (param-passed
  `printf '%s' | grep -qF --`), never `eval` — a backtick/`$()` in a legitimate diff/system
  prompt payload would execute (Slice-2 incident). A test that forces production to mangle
  its own output to pass is the defect, not the content.
- **bash-3.2-safe tests (CI macOS is the source of truth).** Do NOT wrap any heredoc inside
  `$(...)` in the new test files — redirect a heredoc to a tempfile and read the file. The
  `test_shell_portability.sh` guard flags odd-quote-parity `$()`-heredocs;
  `grep -nE '=\s*"\$\(.*<<'` over the new tests must return nothing. Confirm the `ci`
  workflow `conclusion=success` on EVERY OS before merge — never trust local-green /
  `mergeable` alone.
- **Bench/test isolation.** Offline tests perform 0 live calls and write NO stray tracked
  files; start the proxy on an ephemeral loopback port and tear it down; `git status` clean
  and `run_all.sh` green after every run. Any subprocess spawned by a test must run with the
  inject seam (no key, no network).
- **Plausible-empty-render trap (RISK-GUI-7).** A wrong-cwd / no-key / single-family run
  must FAIL LOUD with a classified error — the from-wrong-cwd test asserts it never renders
  a plausible all-`character-missing` result as "the council had no opinion".
- **Pass-through integrity (RISK-GUI-3).** The proxy renders the child JSON unchanged; the
  key-absence guard is an ASSERTION, never a content rewrite. A guard that strips/rewrites
  to pass is the defect.
- **No hardcoded model ids / versions.** The proxy/launcher re-uses the frozen primitives'
  resolution; it introduces NO hardcoded model id or version of its own.

## Out of scope / non-goals (do not build)

Auth / accounts / multi-user / sessions; persistence / run history / database; non-loopback
bind / public deploy; any re-implementation of inference / presets / key handling / caps /
the live gate / the diversity check; any new runtime dependency or build step; any live run
in the MVP acceptance path (live toggle EXISTS, proven OFF-by-default, but no live boundary
is crossed); any value verdict.

## Allowed change scope (machine-parseable — already validated with plumbline-scope-check)

- `config/claude/gui/openrouter_gui_proxy.py`
- `config/claude/gui/static/index.html`
- `config/claude/gui/static/app.js`
- `config/claude/gui/static/style.css`
- `config/claude/bin/plumbline-council-gui`
- `config/claude/tests/test_gui_proxy.sh`
- `config/claude/tests/test_gui_security.sh`
- `config/claude/tests/run_all.sh`
- `docs/canvas/openrouter-gui.canvas.md`
- `docs/prd/openrouter-gui.prd.md`
- `docs/vision/openrouter-gui.vision.md`
- `docs/reality/openrouter-gui.evidence.jsonl`
- `docs/trace/openrouter-gui.trace.md`
- `docs/plans/2026-06-20-openrouter-gui.md`
- `CLAUDE.md`
