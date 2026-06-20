# Product Canvas: openrouter-gui

Status: user-confirmed
Owner: requirements-analyst
Confirmed by user: yes
Canvas file: docs/canvas/openrouter-gui.canvas.md

USER PRINCIPLED OVERRIDE: 2026-06-20 (Ben). This override SUPERSEDES the earlier
spec-sanity "MVP-honesty = offline renders INJECTED/demo positions" framing. The bundled
DEMO council VIOLATES a core Plumbline principle ("real code or no code"; `placeholder` is
a FORBIDDEN_TOKEN). Ben's directive: "nur echt und nur was geht. Fake=Demo, dann weglassen."
=> NO fake/demo as user-facing value anywhere. The GUI shows REAL council positions (live)
or NOTHING (an honest classified message) - it never shows a canned/demo council as the
product. This REVERSES OQ-5's earlier "offline/injected MVP is the acceptance path" choice:
the user-facing MVP is now LIVE-ONLY-REAL. The `--inject-council` seam REMAINS, but ONLY as
TEST infrastructure (tests inject real-shaped council JSON to exercise render/security
offline at 0 credits - that is test infra, NOT a user-facing fake). The evidence floor for
the live render path RISES to `real-boundary-smoke` (a real boundary is now crossed at
acceptance); the offline-tested mechanics (proxy/render/security/routing) stay
`integration-fake`. This raise is HONEST (a real boundary is now crossed), not a floor-launder.

Spec-sanity remediation: 2026-06-20 (Phase 0.5, spec-auditor findings applied). This pass
HARDENS and CLARIFIES the confirmed intake (architecture = subprocess; explicit real-path
preconditions; the key-leak gate is MVP-critical at full strength; wired-in-prod through the
real launcher; mixed/partial render; REQ-GUI-005 reworded as an assertion, not a mutation).
These are hardening/clarifications, NOT value reversals - the user's confirmed choices
(Council-Runner; thin proxy over frozen primitives; loopback-only; no new deps; no verdict)
are unchanged. NOTE: the spec-sanity "decision 3 = offline renders INJECTED/demo positions
as the MVP value" is NO LONGER in force - it is superseded by the USER PRINCIPLED OVERRIDE
above (LIVE-ONLY-REAL). The user-confirmed Status is preserved; the override is recorded as
the dated decision below and reconciled through every section.

> The Product Canvas is a mandatory pre-build value-alignment artifact. /agileteam
> may not finalize the PRD or enter development until this canvas is filled in well
> enough, saved, linked to PRD/Vision/traceability, and explicitly confirmed by the
> user. It does not replace the PRD, Product Vision, traceability, Reality Ledger,
> Watcher, or human-acceptance gates - it sits in front of them.
>
> Allowed Status values: draft | user-confirmed | blocked. Development entry
> requires Status: user-confirmed. No agent may self-confirm the canvas.

Slice: Slice 4 of the OpenRouter Council line (follows Slice 1 inference, Slice 2
deepseek-review-agent / `/concilium` presets, Slice 3a/3b measurement).

---

## 1. Problem

What real problem should be solved?

Status: CONFIRMED

Answer:
Running the foreign-model council today is a terminal-only act: a developer must know
the right `deepseek_review.py preset` invocation, the env gating, and how to read the
raw JSON (`positions`, `diversity.gate`, `diversity.disclosure`). There is no
low-friction way to paste an idea or a diff and SEE each council character's position
side by side together with the diversity / foreign-only status. That keeps the
already-vetted council primitive effectively unused for quick, exploratory "what would
the council say about this?" passes.

---

## 2. Target user / customer

Who has this problem?

Status: CONFIRMED

Answer:
Ben (the framework author) and any local developer who has the Plumbline repo checked
out, an `OPENROUTER_API_KEY` available server-side, and wants an interactive way to run
the existing council on an idea/diff. Single local operator. NOT a hosted/multi-user
product (see Non-goals).

---

## 3. Current workaround

How is the problem handled today?

Status: CONFIRMED

Answer:
Invoke the CLI by hand, e.g. `python3 config/claude/lib/deepseek_review.py preset
--preset A --subject "<text>" --json` (offline via `--inject-*`, or live behind
`--live` + `COUNCIL_INFERENCE_LIVE=1`), then read the raw JSON. There is no
presentation layer and no paste box; the diversity disclosure (RISK-B-007) is buried in
the JSON rather than surfaced beside the positions.

---

## 4. Value proposition

What concrete human/customer value will this create?

Status: CONFIRMED

Answer:
A thin local web GUI - the Council-Runner - that lets the operator paste an idea or a
diff, pick a preset (A/B/C), invoke the EXISTING vetted council LIVE via a thin
server-side proxy, and read each character's REAL position plus the foreign-only /
diversity status in one view. Value = friction removed (no CLI/JSON literacy needed)
WITHOUT re-implementing or weakening any council logic and WITHOUT exposing the API key to
the browser.

LIVE-ONLY-REAL (USER PRINCIPLED OVERRIDE, Ben 2026-06-20): the GUI shows REAL council
positions (live) or NOTHING - "nur echt und nur was geht. Fake=Demo, dann weglassen."
There is NO canned/demo council as user-facing value. Paste->Run runs the REAL foreign
council live (gated by `COUNCIL_INFERENCE_LIVE=1` + an `OPENROUTER_API_KEY`) and renders
the REAL positions - or HONEST classified errors/attrition (rate-limit / unavailable /
missing-secret), NEVER a fake fallback. With no budget, the council runs on FREE models =>
real but rate-limited (intermittent attrition, per EXP-009); this is shown honestly
(classified), not beautified into a demo. When the live gate is OFF or no key is present,
the GUI shows a clear classified "live required to run the council" message - NOT a demo,
NOT fake positions. The `--inject-council` seam REMAINS but ONLY as TEST infrastructure
(tests inject real-shaped council JSON to exercise render/security offline at 0 credits) -
that is test infra, NOT a user-facing fake. The MVP value is the proven-safe, working
presentation+proxy surface over REAL live council output. This canvas must NOT be read as
ever showing a demo/injected council to the operator.

---

## 5. Success signal

How will we know this is valuable?

Status: CONFIRMED

Answer:
CONFIRMED (Ben, 2026-06-20, Phase 0.15) and re-scoped by the USER PRINCIPLED OVERRIDE
(Ben, 2026-06-20): the operator can, from a browser on 127.0.0.1, paste a subject, run
preset A LIVE (with `COUNCIL_INFERENCE_LIVE=1` + an `OPENROUTER_API_KEY`), and see the
per-role REAL positions + the diversity gate + the RISK-B-007 disclosure rendered in the
real `deepseek_review preset` JSON shape - OR an honest classified message (rate-limit /
unavailable / attrition / "live required") when the live council cannot answer. There is
NO demo/injected council shown to the operator. The live success signal is a
`real-boundary-smoke`: a real paste->Run->real-positions pass run at acceptance crosses the
real OpenRouter boundary and renders REAL council output (or honest classified attrition on
free models, per EXP-009). The OFFLINE proofs (proxy/render/security/routing exercised with
the test-only `--inject-council` seam) remain `integration-fake` and are how the mechanics
are proven at 0 credits - but the offline path is TEST infra, not a user-facing success
signal. The live toggle is still proven OFF-by-default by an offline test (when OFF, the
GUI shows the classified "live required" message, never a fake council). Success is
qualitative - "a live paste->Run renders REAL positions, or an honest classified message;
never a demo".

---

## 6. Core use case

What is the smallest meaningful use case?

Status: CONFIRMED

Answer:
Operator opens the local GUI -> pastes a subject (idea or diff) -> selects preset A ->
clicks Run -> proxy invokes the existing `deepseek_review.py preset` LIVE (gated by
`COUNCIL_INFERENCE_LIVE=1` + an `OPENROUTER_API_KEY`) -> GUI renders each role's model +
REAL position + the diversity block (distinct_bases, gate, disclosure), OR an honest
classified message (attrition / rate-limit / unavailable). If the live gate is OFF or no
key is present, the GUI shows a classified "live required to run the council" message - it
does NOT show a demo/injected council. (USER PRINCIPLED OVERRIDE, Ben 2026-06-20:
LIVE-ONLY-REAL; the earlier "offline/injected default" is superseded.)

ARCHITECTURE (spec-sanity decision 1, SUBPROCESS - belegt against the real files): the
proxy (Python stdlib `http.server`) SHELLS OUT to `deepseek_review.py preset --json` as a
child process; it does NOT import the council in-process. The `OPENROUTER_API_KEY` lives
ONLY in the subprocess CHILD environment - the proxy's HTTP handler NEVER reads the key
into its own locals, so a handler traceback can never close over or leak it. The launcher
(`plumbline-council-gui`) PINS cwd to the repo-root (and/or exports
`DEEPSEEK_CHARACTERS_DIR`) so the relative character-slug root (`concilium/characters`)
resolves; otherwise every role would resolve `character-missing` (see RISK-GUI-7). USER
PRINCIPLED OVERRIDE (Ben 2026-06-20): the USER-FACING run path is the LIVE subprocess+key
path - paste->Run spawns `deepseek_review.py preset --live` and renders REAL positions (or
honest classified attrition). The proxy's `--inject-council` seam supplies canned
real-shaped JSON WITHOUT spawning the subprocess and WITHOUT a key, but it is reachable
ONLY by tests (to exercise render/security offline at 0 credits) - it is NOT a user-facing
run mode and never renders a demo council to the operator.

---

## 7. Non-goals

What should explicitly not be built?

Status: CONFIRMED

Answer:
- NO authentication / accounts / multi-user / sessions.
- NO network exposure beyond loopback by default (no 0.0.0.0 bind, no public deploy).
- NO persistence / run history / database (OQ-MVP CONFIRMED OUT of MVP scope).
- NO auth / multi-user, NO non-loopback bind / deploy (OQ-MVP CONFIRMED OUT).
- NO re-implementation of inference, presets, key handling, capping, the live gate, or
  the diversity check - the GUI is presentation + a thin proxy over the FROZEN primitives
  (`deepseek_review.py preset` -> `council_inference` -> `council_presets`).
- NO new runtime dependency / build step (OQ-PROXY/OQ-UI CONFIRMED: a single
  self-contained HTML + vanilla JS over Python stdlib `http.server`, no new deps).
- NO fake/demo council as user-facing value (USER PRINCIPLED OVERRIDE, Ben 2026-06-20,
  supersedes OQ-5): there is NO canned/demo/injected council shown to the operator
  anywhere. The GUI shows REAL live positions or an honest classified message - never a
  fake fallback. The `--inject-council` seam survives ONLY as test infrastructure.
- NO silent fake fallback when live is unavailable: when the live gate is OFF, the key is
  missing, or the council cannot answer (rate-limit / unavailable / attrition), the GUI
  shows an HONEST classified message - it does NOT substitute demo positions.
- NO value verdict: the GUI surfaces positions + the diversity disclosure; it must NOT
  imply that distinct ids prove cognitive diversity, nor that the council "approved" the
  idea.

---

## 8. Risks / contradictions

What could make this wrong, useless, unsafe, misleading, too broad, or misaligned?

Status: CONFIRMED

Answer:
- RISK-GUI-1 (key leakage - the crux): the `OPENROUTER_API_KEY` must be read by the
  EXISTING `council_inference` real transport ONLY, and ONLY inside the spawned
  subprocess CHILD env (decision 1) - the proxy handler never reads it into its own
  locals. It must NEVER reach the browser, NEVER appear in an HTTP response body, NEVER be
  logged, NEVER be embedded in the served HTML/JS. A leak here is the highest-severity
  failure of this feature. Spec-sanity hardening (decision 4): the leak gate is
  MVP-CRITICAL and runs at FULL strength in the MVP - it is NOT reduced by offline mode,
  because the key is resident on the machine whenever the (gated) real path is usable.
  The leak invariant is enforced by: (a) an INDUCED-ERROR leak test - force exceptions
  (malformed POST, oversized body, broken pipe) and assert the key is absent from BOTH the
  HTTP response body AND captured stderr/log; (b) a generic-500 handler that emits NO
  traceback, NO request body, and NO env in the response or log; (c) NO request-body
  logging and NO env logging anywhere in the proxy; (d) loopback-only by default, with a
  non-loopback bind requiring an explicit separate opt-in (RISK-GUI-2).
- RISK-GUI-2 (loopback binding): a default bind to anything but 127.0.0.1 exposes the
  proxy (and thus a key-holding endpoint) to the LAN. Default MUST be loopback-only.
- RISK-GUI-3 (re-implementation drift): if the proxy reaches around the CLI/library and
  re-derives any council logic, it can diverge from the vetted behavior and the gate.
  Premise to enforce: the proxy calls the existing entrypoint and renders its JSON
  unchanged.
- RISK-GUI-4 (live cost / free-tier attrition - re-scoped by the USER OVERRIDE): the
  council on free models is rate-limited and underpowered (EXP-009, n=2, 100% free-tier
  attrition; directional cry-wolf hint). The USER PRINCIPLED OVERRIDE makes the GUI
  LIVE-ONLY-REAL, so a live run IS the user-facing path - but it is still gated behind an
  EXPLICIT user action (paste->Run) AND the `COUNCIL_INFERENCE_LIVE=1` + key gate; it never
  fires live on page load or by default. With no budget the council runs on FREE models =>
  real but rate-limited; attrition is shown HONESTLY (classified rate-limit/unavailable),
  never hidden behind a demo. Premise: live is reachable only by an explicit gated user
  action; free-tier attrition surfaces as an honest classified message, never a fake
  fallback. (NOTE: "default to the offline/injected path" is SUPERSEDED - offline/injected
  is now test-only infra, not a user-facing run mode.)
- RISK-GUI-5 (honesty / misleading UI): rendering positions without the RISK-B-007
  disclosure could imply proven cognitive diversity or a value verdict. Premise: the
  disclosure travels with the diversity block and is shown.
- RISK-GUI-6 (injection via pasted content): pasted diffs/ideas containing shell-meta or
  XML-ish content must not break the proxy or the rendering. Treat all input as data;
  no `eval`; no shell interpolation of payloads (learned: Slice-2 eval-payload incident).
- RISK-GUI-7 (silent dead-end on a misconfigured real path - spec-sanity decision 2,
  belegt): driving the REAL council (live, even a live dry-run) has THREE explicit
  preconditions, EACH enforced by the launcher with a LOUD, classified error:
  (a) the `OPENROUTER_API_KEY` is present in env - `council_inference` checks key presence
  BEFORE the inject seam on the real (non-dry-run) path, so a real run with no key returns
  `COUNCIL_MISSING_SECRET` with ZERO calls (verified council_inference.py line 342-344);
  (b) a catalog (`--inject-catalog` offline, or the live `/api/v1/models` fetch) with >=2
  DISTINCT free families, else `resolve_preset` returns `decision==abort` BEFORE any call
  (verified deepseek_review.py `_cmd_preset`); (c) cwd == repo-root (or
  `DEEPSEEK_CHARACTERS_DIR` set) so `concilium/characters` resolves, else EVERY role
  returns per-role `code: character-missing, position: null` and `overall:
  COUNCIL_MODEL_UNAVAILABLE` (verified `_characters_dir` default + `build_character_messages`).
  The danger: a wrong-cwd or no-key run produces a PLAUSIBLE all-`character-missing` /
  all-error render that READS like "the council had no opinion". Premise: the launcher
  MUST FAIL LOUD with a clear classified error when a precondition is missing - it must
  NEVER render a plausible all-`character-missing`/all-error result as if the council ran.
- RISK-GUI-8 (mixed/partial render honesty - spec-sanity decision 6, belegt):
  `deepseek_review preset` returns `overall: COUNCIL_MODEL_UNAVAILABLE` if ANY role is
  non-OK but STILL returns a full per-role `positions[]` (some `COUNCIL_INFERENCE_OK` with
  a real `position`, some classified with `position: null`) (verified `_cmd_preset`:
  `overall = CODE_OK if all(...) else CODE_MODEL_UNAVAILABLE`, positions always populated).
  Premise: the GUI MUST render the MIXED state honestly - the OK positions AND the per-role
  classified codes - never a single error banner that hides the OK positions, and never a
  fake all-success. (The all-error case still renders as classified errors.)
- RISK-GUI-9 (wired-in-prod - spec-sanity decision 5; the repo's signature false-green):
  the headline paste->run->render MUST be exercised through the REAL `plumbline-council-gui`
  start, not only an injected in-process handler - else the launcher (cwd-pin, key-in-child,
  precondition enforcement) is dead code green only in tests. This is the CLAUDE.md
  "injectable seam green, real entrypoint dead" failure class. Premise: a test starts the
  real launcher and a from-wrong-cwd test asserts fail-loud-or-resolve (NEVER a plausible
  all-`character-missing` render).
- CONTRADICTION CHECK: none found between this canvas and the confirmed primitives - the
  `preset` subcommand, the key-in-Authorization-header-only contract, the
  COUNCIL_INFERENCE_LIVE=1 gate, the `--inject-*` offline seam, and the
  `positions`/`diversity` JSON shape are all present in the real files (verified, see
  Evidence needed).
Residual product-risk acceptance CONFIRMED (Ben, 2026-06-20, Phase 0.15) and RE-SCOPED by
the USER PRINCIPLED OVERRIDE (Ben, 2026-06-20): the live-call-cost risk (RISK-GUI-4) is now
accepted as an EXPLICIT, gated, user-initiated cost - the GUI is LIVE-ONLY-REAL, so the
operator who clicks Run with the live gate on knowingly crosses the real boundary; free-tier
attrition is shown honestly (classified), never fired by default, never hidden behind a
demo. The honesty risk (RISK-GUI-5) is resolved by OQ-HONESTY: a visible in-UI "no verdict"
disclosure carries RISK-B-007 (distinct ids != proven cognitive diversity). The
no-fake-fallback principle (the override) is itself the resolution of the "demo masquerades
as the council" honesty risk: when live is unavailable the GUI shows a classified message,
never demo positions. All risks above are accepted with the stated premises.

---

## 9. Evidence needed

What must be verified before implementation can be considered real?

Status: CONFIRMED (foreign-primitive premises verified at intake; runtime evidence is build-phase)

Answer:
Foreign-primitive claims VERIFIED against the real files at intake (belegt):
- `deepseek_review.py` exposes a `preset` subcommand with
  `--preset/--subject/--dry-run/--live/--inject-response/--inject-error/--inject-catalog/--inject-call-counter`
  (verified: config/claude/lib/deepseek_review.py, the `p_pre` parser).
- The `preset` JSON output carries top-level `code`, a `positions` list (per role:
  model, code, position), and a `diversity` block with `distinct_bases`, `gate`,
  `disclosure` (verified: `_cmd_preset`, lines ~474-512).
- The real transport is armed ONLY when `--live` AND `COUNCIL_INFERENCE_LIVE=1`;
  otherwise transport is None => 0 calls (verified: `_make_transport` in
  deepseek_review.py; `_real_transport` gate in council_inference.py).
- The raw `OPENROUTER_API_KEY` is read server-side and placed ONLY in the
  `Authorization: Bearer <key>` header inside `_real_transport`; it is never returned or
  logged (verified: council_inference.py lines 16-17, 242-264, 342-373).
- Presets A, B, C exist; default is A (verified: council_presets.py).
- The diversity disclosure (RISK-B-007: distinct ids are a structural floor, NOT proof
  of cognitive diversity) is carried in the disclosure field (verified:
  council_presets.py lines 20-21, 101-105).
- Spec-sanity (decision 2/6) ADDITIONAL premises verified at this Phase-0.5 pass (belegt):
  - On the REAL (non-dry-run) path `council_inference` checks key presence BEFORE the
    inject seam - a missing key returns `COUNCIL_MISSING_SECRET`, ZERO calls (verified
    council_inference.py lines 340-344, branches precede inject_error/inject_response).
  - `_cmd_preset` returns `overall = COUNCIL_INFERENCE_OK` only if ALL roles are OK, else
    `COUNCIL_MODEL_UNAVAILABLE`, and ALWAYS returns a per-role `positions[]` (OK roles
    carry a `position`; non-OK roles carry their classified `code` and `position: null`)
    (verified deepseek_review.py `_cmd_preset`).
  - The character root is the RELATIVE `concilium/characters` (or `$DEEPSEEK_CHARACTERS_DIR`);
    from the wrong cwd every role resolves `character-missing` (verified `_characters_dir`,
    `build_character_messages` status `character-missing`). This is the basis for the
    launcher cwd-pin (decision 1) and the fail-loud precondition (RISK-GUI-7).
  - `resolve_preset` fails closed (`decision==abort`) BEFORE any call when the catalog
    lacks >=2 distinct free families (verified deepseek_review.py `_cmd_preset` abort branch).

Runtime evidence to produce DURING the build (Phase 3 Reality Ledger). The honest
evidence floor is SPLIT (USER PRINCIPLED OVERRIDE, Ben 2026-06-20):
- the OFFLINE-tested mechanics (proxy / render / security / routing / fail-loud
  preconditions / mixed render) stay `integration-fake` - they are provable offline with
  the test-only `--inject-council` seam at 0 credits; and
- the LIVE render path (paste->Run->REAL positions) RISES to `real-boundary-smoke`: the GUI
  now crosses the real OpenRouter boundary as its user-facing value, so a real live smoke
  MUST be run at acceptance. This raise is HONEST (a real boundary is now crossed), NOT a
  floor-launder - "never raise a class to clear a floor" still holds.
- An OFFLINE proxy test proving the paste->run->render path with the test-only injected
  council seam and a call-counter asserting ZERO live transport calls (integration-fake;
  test infra, not a user-facing demo).
- A test proving the proxy binds 127.0.0.1 by default and that the served HTML/JS and
  every HTTP response body contain NO key material (the leak-floor falsifier).
- A test proving the live toggle is OFF by default (the gate is OFF unless explicitly
  enabled) and that when OFF the GUI returns the classified "live required" message (NOT a
  demo, NOT fake positions) - this is itself an OFFLINE proof (integration-fake).
- (decision 4) An INDUCED-ERROR leak test: force exceptions (malformed POST, oversized
  body, broken pipe) and assert the key sentinel is absent from BOTH the response body AND
  captured stderr/log; assert the generic-500 handler emits no traceback/body/env
  (integration-fake).
- (decision 5, wired-in-prod) A test that starts the REAL `plumbline-council-gui` launcher
  (not only the in-process handler) and drives the headline paste->run->render offline,
  PLUS a from-wrong-cwd test asserting fail-loud-or-resolve - NEVER a plausible
  all-`character-missing` render (integration-fake; the launcher cwd-pin + precondition
  enforcement is exercised, no real boundary crossed).
- (decision 6) A MIXED-state render test: an injected preset response with some roles OK
  and some classified (`position: null`) renders the OK positions AND the per-role codes -
  not a single error banner, not a fake success (integration-fake).
- A LIVE real-boundary smoke IS in scope (USER PRINCIPLED OVERRIDE, supersedes OQ-5): a
  `real-boundary-smoke` record for the live paste->Run->REAL-positions path MUST be produced
  at acceptance (the GUI now crosses the real OpenRouter boundary as its user-facing value).
  On free models the smoke may legitimately return honest classified attrition (per EXP-009)
  rather than full positions - that is a real boundary crossed and is recorded honestly as
  `real-boundary-smoke`, NOT downgraded to a demo. Note: the wired-in-prod launcher test is
  ALSO exercised OFFLINE/injected (the launcher starts and the render path runs against the
  test-only injected seam) at `integration-fake` - it proves the real entrypoint is wired;
  the live smoke proves the real boundary is crossed.

---

## Allowed change scope

List the only repo-relative files, directories, or glob patterns that implementation
agents may edit for this feature. Machine-parseable (one path/glob per `-` line,
backtick-wrapped, parseable by `plumbline-scope-check`). CONFIRMED (Ben, 2026-06-20,
Phase 0.15, OQ-SCOPE) - the path list below is unchanged from the validated scope.

Status: CONFIRMED

Allowed change scope:

- `config/claude/gui/openrouter_gui_proxy.py`
- `config/claude/gui/static/index.html`
- `config/claude/gui/static/app.js`
- `config/claude/gui/static/style.css`
- `config/claude/bin/plumbline-council-gui`
- `config/claude/tests/test_gui_proxy.sh`
- `config/claude/tests/test_gui_security.sh`
- `config/claude/tests/run_all.sh`
- `config/claude/tests/lib.sh`
- `docs/canvas/openrouter-gui.canvas.md`
- `docs/prd/openrouter-gui.prd.md`
- `docs/vision/openrouter-gui.vision.md`
- `docs/reality/openrouter-gui.evidence.jsonl`
- `docs/trace/openrouter-gui.trace.md`
- `docs/plans/2026-06-20-openrouter-gui.md`
- `docs/benchmarks/2026-06-20-openrouter-gui-live-smoke.md`
- `CLAUDE.md`

---

## 10. Traceability links

PRD: docs/prd/openrouter-gui.prd.md
Product Vision: docs/vision/openrouter-gui.vision.md (to be created by product-owner)
Traceability Matrix: docs/trace/openrouter-gui.trace.md (stub in PRD; built in Phase 0/0.5)
Related REQ IDs: REQ-GUI-001 .. REQ-GUI-018 (REQ-GUI-018 added in the 2026-06-20 USER
PRINCIPLED OVERRIDE; REQ-GUI-013..017 added in the 2026-06-20
Phase-0.5 spec-sanity remediation; see PRD)
True-Line status: aligned

---

## User confirmation

Confirmed by user: yes
Confirmation date: 2026-06-20
Confirmation note:
Ben confirmed this canvas on 2026-06-20 via the Phase-0.15 AskUserQuestion gates. Decisions:
- Purpose = Council-Runner; Architecture = local web app + thin server-side proxy.
- OQ-PROXY = Python stdlib `http.server` (no new deps).
- OQ-UI = a single self-contained HTML + vanilla JS (precedent: agent-explorer.html).
- OQ-SCOPE = `config/claude/gui/` for proxy + static, `config/claude/tests/test_gui_*.sh`
  for tests (the already-validated Allowed change scope above).
- OQ-MVP = IN: paste -> run preset LIVE -> render REAL positions (or an honest classified
  message), loopback-only, offline-testable mechanics. OUT: auth, multi-user, run
  history/persistence, non-loopback/deploy. [RE-SCOPED by the OVERRIDE below: the run mode
  is LIVE-ONLY-REAL, not offline/injected; offline/injected is test-only infra.]
- OQ-5 = SUPERSEDED by the USER PRINCIPLED OVERRIDE below. (Was: offline/injected MVP; no
  live run in the acceptance path. Now: LIVE-ONLY-REAL; a live `real-boundary-smoke` IS in
  the acceptance path.)
- OQ-KEYSRC = process env first, then `~/.openclaw/.env`.
- OQ-HONESTY = a visible in-UI "no verdict" disclosure carrying RISK-B-007 (distinct ids
  != proven cognitive diversity).

DECISION - USER PRINCIPLED OVERRIDE (Ben, 2026-06-20):
The bundled DEMO council violates the core Plumbline principle "real code or no code"
(`placeholder` is a FORBIDDEN_TOKEN). Ben's directive: "nur echt und nur was geht.
Fake=Demo, dann weglassen." Effect on this canvas (reconciled through every section above):
1. The DEMO is REMOVED from the product contract. No canned/demo/injected council is shown
   to the operator anywhere. (Supersedes the spec-sanity "decision 3" MVP-honesty framing.)
2. The GUI is LIVE-ONLY-REAL: paste->Run runs the REAL council live (gated by
   `COUNCIL_INFERENCE_LIVE=1` + key) and shows REAL positions - or honest classified
   errors/attrition (rate-limit / unavailable), NEVER a fake fallback. With no budget the
   council runs on FREE models => real but rate-limited (per EXP-009); shown honestly.
3. Offline-without-live (gate OFF / no key) => a clear classified "live required to run the
   council" message - NOT a demo, NOT fake positions. The `--inject-council` seam REMAINS
   but ONLY as TEST infrastructure (inject real-shaped JSON to exercise render/security
   offline at 0 credits) - not a user-facing fake.
4. The evidence floor for the LIVE render path RISES to `real-boundary-smoke` (the GUI now
   crosses the real OpenRouter boundary). The offline-tested mechanics stay
   `integration-fake`. This raise is honest (a real boundary is now crossed), not a
   floor-launder.
5. UI/UX (encoded in the PRD): clearer role cards (character + model + position), the
   diversity / foreign-only block, a visible LIVE-status / attrition indicator, preset
   choice, and the RISK-B-007 no-verdict disclosure (kept).
Status: the canvas Status STAYS `user-confirmed` - this override is a user-directed
re-scope of a confirmed canvas, recorded as this dated decision and reconciled through
every section; it re-opens no decision that contradicts the user's own directive.
