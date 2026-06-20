# PRD: OpenRouter Council-Runner GUI (Slice 4)

Status: finalized (canvas user-confirmed 2026-06-20; all Phase-0.15 open questions resolved)
Owner: requirements-analyst
Canvas: docs/canvas/openrouter-gui.canvas.md
Product Vision: docs/vision/openrouter-gui.vision.md (Status user-confirmed, Ben 2026-06-20, at the Phase-0 Vision gate; Phase 0 complete)
Traceability Matrix: docs/trace/openrouter-gui.trace.md (stub below)
Branch: agileteam/openrouter-gui

> This PRD is FINALIZED: the linked canvas reached Status: user-confirmed (Ben,
> 2026-06-20) and every Phase-0.15 open question (OQ-PROXY, OQ-UI, OQ-SCOPE, OQ-MVP,
> OQ-5, OQ-KEYSRC, OQ-HONESTY) is resolved and recorded inline below. The acceptance
> criteria are contracts.
>
> USER PRINCIPLED OVERRIDE (Ben, 2026-06-20) - SUPERSEDES OQ-5 and the spec-sanity
> "offline renders INJECTED/demo positions as the MVP value" framing. The bundled DEMO
> council violates the core Plumbline principle "real code or no code" (`placeholder` is a
> FORBIDDEN_TOKEN). Ben's directive: "nur echt und nur was geht. Fake=Demo, dann
> weglassen." Effect, reconciled through this PRD: (1) the DEMO is REMOVED from the product
> contract - no canned/demo/injected council is shown to the operator anywhere; (2) the GUI
> is LIVE-ONLY-REAL - paste->Run runs the REAL council live (gated by
> `COUNCIL_INFERENCE_LIVE=1` + key) and renders REAL positions, or honest classified
> errors/attrition, never a fake fallback; (3) offline-without-live (gate OFF / no key) =>
> a classified "live required to run the council" message, NOT a demo - the
> `--inject-council` seam survives ONLY as test infrastructure; (4) the evidence floor for
> the LIVE render path RISES to `real-boundary-smoke` (a real boundary is now crossed),
> while the offline-tested mechanics stay `integration-fake` (an honest raise, not a
> floor-launder); (5) UI/UX adds clearer role cards (character + model + position), the
> diversity / foreign-only block, a visible LIVE-status / attrition indicator, preset
> choice, and keeps the RISK-B-007 no-verdict disclosure. This override is a user-directed
> re-scope of a confirmed canvas; the canvas Status stays user-confirmed and this PRD stays
> finalized.
>
> Spec-sanity remediation (2026-06-20, Phase 0.5): the spec-auditor findings are applied
> as HARDENING/CLARIFICATION, not value reversals. New/changed: architecture = SUBPROCESS
> with key-in-child-env only (REQ-GUI-013, NFR-GUI-SEC-4); explicit real-path preconditions
> enforced fail-loud by the launcher (REQ-GUI-014, AC-7); the key-leak gate is MVP-critical
> at full strength incl. an induced-error leak test + generic-500 handler
> (REQ-GUI-005/REQ-GUI-015, NFR-GUI-OBS-1, SEC matrix, AC-8); wired-in-prod through the
> REAL launcher + from-wrong-cwd test (REQ-GUI-016, AC-9); mixed/partial render
> (REQ-GUI-017, AC-10); REQ-GUI-005 reworded as a STRUCTURAL guarantee (the key never
> enters the proxy's locals/output by construction; verified by the security suite's absence
> assertions), not a mutation and not a runtime self-scan. NOTE: the spec-sanity "MVP-honesty
> = offline renders INJECTED/demo positions as the MVP value" point is SUPERSEDED by the
> USER PRINCIPLED OVERRIDE above (LIVE-ONLY-REAL). The canvas Status (user-confirmed) and
> this PRD Status (finalized) are preserved - no confirmed product decision is re-opened.

## Summary

A thin local web application - the Council-Runner - that lets a single local operator
paste an idea or a diff, choose a `/concilium` preset (A/B/C), run the EXISTING,
frozen foreign-model council LIVE, and read each character's REAL position together with the
diversity / foreign-only status. It is presentation + a thin server-side proxy over the
vetted Slice-1/2 primitives. It re-implements NO inference, preset, key-handling, cap,
live-gate, or diversity logic. The API key stays server-side, header-only, never seen by
the browser.

LIVE-ONLY-REAL (USER PRINCIPLED OVERRIDE, Ben 2026-06-20): the GUI shows REAL council
positions (live) or NOTHING - "nur echt und nur was geht. Fake=Demo, dann weglassen."
There is NO canned/demo/injected council shown to the operator. When the council cannot
answer (live gate OFF, no key, rate-limit, unavailable, free-tier attrition per EXP-009)
the GUI shows an HONEST classified message, never a fake fallback.

Architecture (spec-sanity decision 1): the proxy (Python stdlib `http.server`) SHELLS OUT
to `deepseek_review.py preset --json` as a CHILD process - it does NOT import the council
in-process. The `OPENROUTER_API_KEY` is placed ONLY in the subprocess child environment;
the proxy's HTTP handler never reads the key into its own locals (a handler traceback
cannot leak it). See REQ-GUI-013 / NFR-GUI-SEC-4.

LIVE-ONLY-REAL value path (USER PRINCIPLED OVERRIDE, Ben 2026-06-20; SUPERSEDES the earlier
spec-sanity "decision 3 = offline renders INJECTED/demo positions as the MVP value"): the
user-facing run path is the REAL live council. Paste->Run spawns
`deepseek_review.py preset --live` (gated by `COUNCIL_INFERENCE_LIVE=1` + key) and renders
REAL positions, or an honest classified message. The proxy's `--inject-council` seam (0
subprocess spawn, 0 key, 0 OpenRouter calls) REMAINS but is reachable ONLY by the offline
TEST suite, to prove the UI + proxy + render + leak-safety + wiring mechanics at 0 credits;
it injects real-shaped council JSON and is NOT a user-facing run mode and NEVER renders a
demo council to the operator. The LIVE render path crosses the real OpenRouter boundary and
carries a `real-boundary-smoke` evidence floor (see Evidence-class section). This PRD must
not be read as ever showing the operator an injected/demo council.

## Reuse contract (verified at intake - do NOT reimplement)

The proxy MUST drive the council through the existing entrypoint and render its JSON
unchanged. Verified premises (belegt - read against the real files at intake):

- Entrypoint: `config/claude/lib/deepseek_review.py` `preset` subcommand. Flags:
  `--preset` (default A), `--subject`, `--dry-run`, `--live`, `--inject-response`,
  `--inject-error`, `--inject-catalog`, `--inject-call-counter`, `--json`.
- Output JSON: top-level `code`; `positions` = list of per-role objects (`model`,
  `code`, `position`); `diversity` = `{distinct_bases, gate, disclosure}`.
- Live gate: real transport arms ONLY when `--live` AND env `COUNCIL_INFERENCE_LIVE=1`;
  otherwise transport is None and ZERO network calls occur.
- Key handling: `OPENROUTER_API_KEY` is read server-side and used ONLY in the
  `Authorization: Bearer <key>` header inside `council_inference._real_transport`; it is
  never returned and never logged.
- Offline test seam: `--inject-response` / `--inject-error` / `--inject-catalog` /
  `--inject-call-counter` drive the whole path with 0 credits / 0 network.

## Data model (request / response at the proxy boundary)

Browser -> proxy (POST, JSON):
- `subject` (string, required): the pasted idea or diff. Treated as opaque data.
- `preset` (enum: "A" | "B" | "C", default "A").
- `mode` (enum: "live" | "offline"). The USER-FACING run path is `live` (USER PRINCIPLED
  OVERRIDE, Ben 2026-06-20: LIVE-ONLY-REAL). "live" runs the REAL council and is honoured
  only when the server-side live gate is enabled (`COUNCIL_INFERENCE_LIVE=1` + key);
  otherwise the proxy REFUSES the run and returns a classified "live required to run the
  council" message - it NEVER downgrades to a demo and NEVER fabricates positions. The
  "offline" value drives the test-only `--inject-council` seam (real-shaped JSON, 0 calls)
  and is NOT exposed to the operator as a way to see council output - it exists so the
  offline test suite can exercise render/security mechanics at 0 credits.

Proxy -> browser (JSON): the `deepseek_review preset` JSON is passed through VERBATIM
(pass-through preserved per RISK-GUI-3 / REQ-GUI-010). The key-absence guarantee
(REQ-GUI-005) is STRUCTURAL, not a mutation (spec-sanity decision 7): the key never enters
the response, served assets, or logs by construction (it flows only to the child env,
REQ-GUI-013) - so the proxy does NOT transform, strip, or rewrite the council JSON, and it
does NOT run a runtime self-scan of its own output. (The verified contract carries no key
field; absence is guaranteed by construction and VERIFIED externally by the security suite's
sentinel-absence assertions, never enforced by a content rewrite.) No new fields invented;
`code`, `positions[]`, `diversity{}` passed through unchanged.

---

## Functional requirements (REQ-GUI-*)

### REQ-GUI-001 - Paste-and-run core flow (LIVE-ONLY-REAL)
The GUI MUST accept a pasted `subject` and a selected `preset` and trigger one REAL LIVE
council run via the existing `deepseek_review.py preset --live` entrypoint (gated by
`COUNCIL_INFERENCE_LIVE=1` + key), rendering REAL positions - or, when the council cannot
answer, an honest classified message (see REQ-GUI-008/012). The GUI MUST NOT show a
canned/demo/injected council to the operator (USER PRINCIPLED OVERRIDE, Ben 2026-06-20).
Atomic. Testable.

### REQ-GUI-002 - Render per-role positions
The GUI MUST render every entry of the response `positions[]` showing at least the
role/model and the position (or the classified `code` when position is null), one per
council character.

### REQ-GUI-003 - Render diversity / foreign-only status
The GUI MUST render the `diversity` block: `distinct_bases`, `gate`, and the
`disclosure` text, visibly beside the positions.

### REQ-GUI-004 - Honesty disclosure (no value verdict)
The GUI MUST display the RISK-B-007 disclosure verbatim from the response and MUST NOT
present the run as an approval/verdict or imply distinct ids prove cognitive diversity.
[OQ-HONESTY RESOLVED: a visible in-UI "no verdict" disclosure carrying RISK-B-007
(distinct ids != proven cognitive diversity) is shown beside the diversity block.]

### REQ-GUI-005 - Key never reaches the browser (a STRUCTURAL guarantee, not a runtime self-scan)
The served HTML/JS, and every HTTP response body from the proxy, MUST contain NO
`OPENROUTER_API_KEY` material. The proxy MUST NOT echo, template, or log the key.
This requirement is satisfied STRUCTURALLY, BY CONSTRUCTION: the key is never bound to a
handler local and never enters the proxy's output path - it flows only into the spawned
child's environment (REQ-GUI-013 / NFR-GUI-SEC-4), so there is nothing in the response,
served assets, or logs for the key to leak into. The proxy therefore does NOT perform a
runtime grep/denylist scan of its own output, and it does NOT transform, strip, or rewrite
the council JSON; the council JSON is passed through unchanged (pass-through preserved per
RISK-GUI-3 / REQ-GUI-010). The structural guarantee is VERIFIED externally by the security
suite's absence assertions - a SENTINEL key is held resident in env and asserted absent
from served assets, every response body, and captured stderr/log on both the happy path and
every induced-error path (spec-sanity decision 7; reworded 2026-06-20 as a wording
reconciliation, not a value change - the implementation is the stronger structural form, not
a self-scan the code does not perform). (Highest-severity; falsifiable - see SEC matrix.)

### REQ-GUI-006 - Server-side-only key read
The proxy MUST read the key server-side only and pass it to the council ONLY through the
existing transport's Authorization header. The proxy itself MUST NOT construct HTTP
requests to OpenRouter.
[OQ-KEYSRC RESOLVED: precedence is process env first, then `~/.openclaw/.env`.]

### REQ-GUI-007 - Loopback-only bind by default
The proxy MUST bind 127.0.0.1 by default. Binding any non-loopback interface MUST
require an explicit, separate opt-in (and is OUT of MVP scope by default).

### REQ-GUI-008 - Live gated; classified "live required" when the gate is OFF (no fake fallback)
The user-facing run is LIVE (USER PRINCIPLED OVERRIDE, Ben 2026-06-20: LIVE-ONLY-REAL). A
live run MUST require an explicit server-side gate mirroring the existing
`COUNCIL_INFERENCE_LIVE=1` contract (live OFF unless explicitly enabled) PLUS an
`OPENROUTER_API_KEY`. When the gate is OFF or no key is present, the proxy MUST refuse the
run and return a CLASSIFIED "live required to run the council" message - it MUST NOT
downgrade to a demo, MUST NOT inject canned positions, and MUST NOT fabricate a result.
When the live council cannot answer (rate-limit / unavailable / free-tier attrition per
EXP-009), the GUI MUST surface that classified state honestly (REQ-GUI-012), never a fake
fallback. The proxy MUST NOT fire any live call on page load or by default; live is reached
only by the explicit gated Run action.
[OVERRIDE supersedes OQ-5: the live toggle is proven OFF-by-default by an offline test
(when OFF, the GUI returns the classified "live required" message - itself an offline,
`integration-fake` proof), AND a LIVE run IS in the acceptance path - the live
paste->Run->REAL-positions smoke crosses the real boundary and is a `real-boundary-smoke`
(see Evidence-class floor).]

### REQ-GUI-009 - Offline TEST-ONLY injectability with a real-shaped council seam
The proxy MUST be drivable OFFLINE with an injected council (mirroring the existing
`--inject-*` seam) so the full render/security path is exercised by TESTS with 0 live
calls. This `--inject-council` seam is TEST infrastructure ONLY (USER PRINCIPLED OVERRIDE,
Ben 2026-06-20): it injects real-shaped council JSON to prove the mechanics offline at 0
credits; it MUST NOT be a user-facing run mode and MUST NOT render a demo council to the
operator. A test MUST assert the live-transport call count is exactly 0 in this offline
test mode.

### REQ-GUI-010 - No re-implementation of council logic
The proxy MUST invoke the existing entrypoint and pass its JSON through; it MUST define
no inference, preset, cap, key-derivation, live-gate, or diversity logic of its own.
(Falsifier: a test asserting the proxy source contains no transport/preset/diversity
re-implementation, scoped like the Slice-3 import-purity guards.)

### REQ-GUI-011 - Input treated as opaque data (no injection)
Pasted `subject` content MUST be handled as data: no `eval`, no shell interpolation of
the payload, and rendering MUST escape it so diff/XML/shell-meta content cannot execute
or break the page. (Learned: Slice-2 eval-payload incident.)

### REQ-GUI-012 - Classified-error surfacing
When the council returns a classified non-OK `code` (e.g. unknown-preset,
model-unresolvable, catalog-unreachable, a transport-error class), the GUI MUST surface
that classified code to the operator unchanged - never a generic "error", never a
fabricated success.

### REQ-GUI-013 - Subprocess architecture; key in child env only (spec-sanity decision 1)
The proxy MUST drive the council by SHELLING OUT to `deepseek_review.py preset --json` as
a CHILD process; it MUST NOT import the council in-process. The `OPENROUTER_API_KEY` MUST
be passed ONLY in the spawned child's environment; the proxy's HTTP handler MUST NOT read
the key into its own locals (so a handler traceback cannot close over or leak it). The
launcher MUST pin cwd to the repo-root (and/or set `DEEPSEEK_CHARACTERS_DIR`) so the
relative character root `concilium/characters` resolves. Atomic. Testable.

### REQ-GUI-014 - Real-path preconditions enforced fail-loud (spec-sanity decision 2)
Driving the REAL council (live, including a live dry-run) has THREE preconditions, each of
which the launcher MUST enforce with a LOUD, classified error rather than a plausible
empty/error render: (a) `OPENROUTER_API_KEY` present in env (council_inference checks key
presence BEFORE the inject seam - missing key => `COUNCIL_MISSING_SECRET`, ZERO calls);
(b) a catalog (offline `--inject-catalog`, or the live `/api/v1/models` fetch) with >=2
DISTINCT free families (else `resolve_preset` aborts before any call); (c) cwd == repo-root
or `DEEPSEEK_CHARACTERS_DIR` set (else every role resolves `character-missing`). The
launcher MUST NEVER render a plausible all-`character-missing` / all-error result as if the
council ran with no opinion. Atomic. Testable.

### REQ-GUI-015 - Induced-error key-leak resistance + generic-500 (spec-sanity decision 4)
The proxy MUST NOT leak key material under induced errors. Forcing an exception (malformed
POST, oversized body, broken pipe) MUST NOT place key material in the HTTP response body OR
in stderr/logs. The proxy MUST emit a GENERIC 500 with NO traceback, NO request body, and
NO environment in the response or log. The proxy MUST NOT log request bodies and MUST NOT
log the environment. (The key-leak gate is MVP-critical and runs at full strength in the
MVP - it is NOT reduced by offline mode, because the key is resident whenever the real path
is usable.) Atomic. Testable.

### REQ-GUI-016 - Wired-in-prod via the real launcher (spec-sanity decision 5)
The headline paste->run->render MUST be exercised through the REAL `plumbline-council-gui`
launcher start - not only an injected in-process handler - so the launcher's cwd-pin,
key-in-child, and precondition enforcement are real, not dead code. A from-wrong-cwd test
MUST assert fail-loud-or-resolve (never a plausible all-`character-missing` render). This
guards the repo's signature "injectable seam green, real entrypoint dead" false-green
(CLAUDE.md). Atomic. Testable.

### REQ-GUI-017 - Mixed/partial render honesty (spec-sanity decision 6)
When `deepseek_review preset` returns `overall: COUNCIL_MODEL_UNAVAILABLE` because SOME
roles are non-OK while OTHERS are OK, the response still carries a full per-role
`positions[]` (OK roles with a `position`; non-OK roles with their classified `code` and
`position: null`). The GUI MUST render this MIXED state honestly - showing the OK positions
AND the per-role classified codes - never collapsing it to a single error banner that hides
the OK positions, and never presenting it as a full success. (The all-error case from
REQ-GUI-012 still renders as classified errors.) Atomic. Testable.

### REQ-GUI-018 - LIVE-status / attrition indicator + clearer presentation (USER OVERRIDE, Ben 2026-06-20)
The GUI MUST present, beside the run, a visible LIVE-status / attrition indicator that
honestly shows whether the run was a REAL live call and its outcome class (real positions /
rate-limited / unavailable / attrition / "live required - gate OFF or no key") - so the
operator can NEVER mistake a non-answer for a council opinion. The GUI MUST render the
per-role result as clear ROLE CARDS (character name + model id + position, or the per-role
classified code when position is null), present the diversity / foreign-only block
(REQ-GUI-003), expose the preset choice (A/B/C), and keep the RISK-B-007 no-verdict
disclosure (REQ-GUI-004) visible. No demo/injected council is ever shown to the operator
(REQ-GUI-001/008/009). Atomic. Testable.

---

## Non-functional requirements (NFR-GUI-*)

- NFR-GUI-SEC-1 (key confidentiality): satisfies REQ-GUI-005/006. The key appears only
  in the transport Authorization header, server-side. Falsifiable by grepping served
  assets + all response bodies + logs for key material.
- NFR-GUI-SEC-2 (loopback default): satisfies REQ-GUI-007. Default bind 127.0.0.1.
- NFR-GUI-SEC-3 (no accidental cost): satisfies REQ-GUI-008. Offline default; live gated
  OFF by default.
- NFR-GUI-PORT-1 (no new runtime deps / no build step): a single self-contained HTML +
  vanilla JS over Python stdlib `http.server`. [OQ-PROXY / OQ-UI RESOLVED: stdlib
  `http.server`, no new deps; one self-contained HTML + vanilla JS, precedent
  agent-explorer.html.]
- NFR-GUI-PORT-2 (bash-3.2-safe tests): tests are bash `config/claude/tests/test_*.sh`,
  wired into `run_all.sh`, with NO `$()`-wrapped heredocs (the new
  `test_shell_portability.sh` guard flags odd-quote-parity `$()`-heredocs; redirect
  heredocs to a tempfile instead). CI macOS bash 3.2 is the source of truth.
- NFR-GUI-PORT-3 (bench/test isolation): offline tests perform 0 live calls and write no
  stray tracked files; `git status` clean and `run_all.sh` green after every run.
- NFR-GUI-SEC-4 (key in child env only - spec-sanity decision 1): satisfies REQ-GUI-013.
  The `OPENROUTER_API_KEY` is placed ONLY in the spawned subprocess child env; the proxy's
  HTTP handler never reads it into its own locals. Falsifiable: the handler source reads no
  `OPENROUTER_API_KEY`; an induced handler traceback contains no key material.
- NFR-GUI-OBS-1 (no secret logging - hardened, spec-sanity decision 4): satisfies
  REQ-GUI-005/015. Proxy logs MUST NOT contain key material, request bodies, or the
  environment. On any error the proxy emits a GENERIC 500 (no traceback/body/env in the
  response or log). Falsifiable by an induced-error test asserting the key sentinel is
  absent from BOTH the response body and captured stderr/log.

## Security matrix (REQ -> threat -> control -> falsifier)

| REQ | Threat | Control | Falsifying test |
|-----|--------|---------|-----------------|
| REQ-GUI-005 | Key leaked to browser | Key only in transport header; never templated/echoed | grep served HTML/JS + all response bodies for key sentinel -> must be absent |
| REQ-GUI-005 | Key leaked to logs | No key/raw-body logging | grep proxy log output for key sentinel -> absent |
| REQ-GUI-007 | LAN exposure of key endpoint | Default bind 127.0.0.1 | assert configured bind host == 127.0.0.1 by default |
| REQ-GUI-008 | Accidental live cost | Offline default; live gated by COUNCIL_INFERENCE_LIVE-style env | assert offline mode call-count == 0; assert live gate OFF by default |
| REQ-GUI-011 | Injection via pasted payload | Data-only handling; no eval; escaped render | payload with backtick/$()/`<script>` does not execute and is escaped (use param-passed grep helper, NOT eval - Slice-2 rule) |
| REQ-GUI-010 | Re-implementation drift | Pass-through proxy over frozen entrypoint | source contains no transport/preset/diversity re-derivation |
| REQ-GUI-013 | Key leaked via handler traceback | Key in subprocess child env only; handler never reads key into locals | handler source reads no OPENROUTER_API_KEY; induced handler traceback contains no key sentinel |
| REQ-GUI-014 | Plausible empty/error render masks misconfig | Launcher enforces 3 real-path preconditions fail-loud | wrong-cwd / no-key / single-family run yields a LOUD classified error, NOT a silent all-character-missing render |
| REQ-GUI-015 | Key leaked via induced error / 500 traceback | Generic-500 (no traceback/body/env); no body/env logging | malformed-POST/oversized/broken-pipe: key sentinel absent from response body AND stderr/log; response carries no traceback |
| REQ-GUI-016 | Real launcher dead, only injected handler tested | Headline flow exercised through real plumbline-council-gui start | a test starts the real launcher for paste->run->render; a from-wrong-cwd test asserts fail-loud-or-resolve |

## Evidence class floor (Reality Ledger - authored in Phase 3)

The floor is SPLIT (USER PRINCIPLED OVERRIDE, Ben 2026-06-20): the OFFLINE-tested mechanics
stay `integration-fake`; the LIVE render path RISES to `real-boundary-smoke` because the
GUI now crosses the real OpenRouter boundary as its user-facing value. The raise is HONEST
(a real boundary is now crossed), NOT a floor-launder - "never raise a class to clear a
floor" still holds.

- REQ-GUI-001 (the LIVE paste->Run->REAL-positions path): `real-boundary-smoke`. The
  user-facing core flow crosses the real OpenRouter boundary; a real live smoke MUST be run
  at acceptance (on free models it may return honest classified attrition rather than full
  positions - that is still a real boundary crossed, recorded honestly, never a demo).
- REQ-GUI-002/003/009/011/012/018: `integration-fake` (render / diversity / classified-error
  / opaque-input / LIVE-status mechanics, provable offline with the TEST-ONLY injected
  council seam; no real boundary crossed by these unit/integration proofs).
- REQ-GUI-005/006/007/008: `integration-fake` for the gate/bind/leak/"live-required-refusal"
  proofs (provable offline); the live boundary itself is exercised by the REQ-GUI-001 smoke.
- REQ-GUI-013/014/015/016/017: `integration-fake`. The subprocess wiring, the launcher
  cwd-pin + fail-loud preconditions (REQ-GUI-014/016), the induced-error/generic-500 leak
  resistance (REQ-GUI-015), and the mixed render (REQ-GUI-017) are provable OFFLINE: the
  real launcher is started and the render path runs against the test-only injected seam
  (REQ-GUI-016 proves the real entrypoint is WIRED without crossing the real boundary).
- OVERRIDE supersedes OQ-5: a `real-boundary-smoke` record IS expected in the Phase-3
  Reality Ledger for the live REQ-GUI-001 path - it is NOT deferred to a later slice. The
  ledger class must match what each run actually did; never raise a class to clear a floor,
  and never claim `real-boundary-smoke` for a path that did not cross the real boundary.

---

## Acceptance criteria (Given/When/Then) - provisional, OQ-gated

AC-1 (REQ-GUI-002/003/009/018) - render/security MECHANICS proven offline via the TEST-ONLY seam:
- Given the proxy is running on 127.0.0.1 and a TEST drives it with the `--inject-council`
  TEST seam supplying real-shaped council JSON (test infrastructure only - NOT a user-facing
  mode, NOT a demo shown to the operator; USER PRINCIPLED OVERRIDE, Ben 2026-06-20),
- When the test posts `subject` + `preset=A` in offline test mode,
- Then the response renders each `positions[]` role and the `diversity` block from the
  real-shaped JSON (role cards + diversity + RISK-B-007 + LIVE-status indicator), AND the
  live-transport call count is exactly 0. (This proves the render/security mechanics at 0
  credits; the USER-FACING value path is the LIVE smoke - see AC-LIVE.)

AC-1L (REQ-GUI-001) - LIVE core value path (real-boundary-smoke):
- Given the proxy is running on 127.0.0.1, the live gate is ON (`COUNCIL_INFERENCE_LIVE=1`)
  and an `OPENROUTER_API_KEY` is present,
- When the operator pastes a `subject`, picks `preset=A`, and clicks Run,
- Then the GUI runs the REAL council live and renders REAL per-role positions + the diversity
  block + RISK-B-007 - OR, when the free-tier council cannot answer (rate-limit / unavailable
  / attrition, per EXP-009), an HONEST classified message via the LIVE-status indicator,
  NEVER a demo/injected fallback. This crosses the real OpenRouter boundary and is recorded
  as `real-boundary-smoke` (run at acceptance).

AC-2 (REQ-GUI-005) - key never in browser:
- Given the proxy is serving the GUI,
- When the served HTML/JS and every proxy response body are inspected,
- Then no `OPENROUTER_API_KEY` material is present.

AC-3 (REQ-GUI-007) - loopback default:
- Given default configuration,
- When the proxy starts,
- Then it binds 127.0.0.1 and not a non-loopback interface.

AC-4 (REQ-GUI-008) - live gate OFF => classified "live required", no fake fallback:
- Given no live gate env is set (or no key is present),
- When a run is requested,
- Then no real transport call occurs and the run is REFUSED with a CLASSIFIED "live required
  to run the council" message - NOT a silent downgrade, NOT a demo, NOT fabricated positions
  (USER PRINCIPLED OVERRIDE, Ben 2026-06-20). Proven OFFLINE (integration-fake) - no live
  call is made.

AC-5 (REQ-GUI-004) - honesty:
- Given a completed run,
- When positions are shown,
- Then the RISK-B-007 disclosure is shown and the UI states no value verdict.

AC-6 (REQ-GUI-012) - classified errors:
- Given the council returns a classified non-OK code,
- When the GUI renders the result,
- Then that exact classified code is surfaced (no generic error, no fake success).

AC-7 (REQ-GUI-014) - real-path preconditions fail loud:
- Given a real (live) run is attempted with a missing precondition (no key, OR a catalog
  with fewer than 2 distinct free families, OR cwd != repo-root with no DEEPSEEK_CHARACTERS_DIR),
- When the launcher/proxy processes it,
- Then it returns a LOUD, classified error (`COUNCIL_MISSING_SECRET` for no key; an abort
  before any call for the catalog case; `character-missing` per role for wrong cwd) - and
  NEVER renders a plausible all-`character-missing` / all-error result as if the council
  ran with no opinion. (Provable OFFLINE; ZERO live calls.)

AC-8 (REQ-GUI-005/015) - induced-error leak resistance + generic-500:
- Given the proxy is running,
- When an error is induced (malformed POST, oversized body, broken pipe),
- Then the key sentinel is absent from BOTH the response body AND captured stderr/log, and
  the response is a GENERIC 500 with no traceback, no request body, and no environment.

AC-9 (REQ-GUI-016) - wired-in-prod via real launcher:
- Given the REAL `plumbline-council-gui` launcher is started (not only an in-process handler),
- When the headline paste->run->render is exercised offline AND a from-wrong-cwd start is
  exercised,
- Then the offline paste->run->render renders correctly through the real launcher, AND the
  from-wrong-cwd run fails loud or resolves - NEVER a plausible all-`character-missing`
  render. (Proves the launcher cwd-pin + preconditions are wired; ZERO live calls.)

AC-10 (REQ-GUI-017) - mixed/partial render honesty:
- Given an injected preset response with `overall: COUNCIL_MODEL_UNAVAILABLE` where some
  roles are OK (`position` present) and some are classified (`position: null`),
- When the GUI renders it,
- Then it shows the OK positions AND the per-role classified codes - not a single error
  banner that hides the OK positions, and not a fake success.

AC-11 (REQ-GUI-018) - LIVE-status / attrition indicator honesty:
- Given any run outcome (real positions, rate-limit, unavailable, attrition, or
  "live required - gate OFF / no key"),
- When the GUI renders the result,
- Then a visible LIVE-status indicator shows whether the run was a REAL live call and its
  outcome class, so a non-answer can NEVER read as a council opinion, and no demo/injected
  council is ever shown. (USER PRINCIPLED OVERRIDE, Ben 2026-06-20.)

AC-LIVE (REQ-GUI-001/008) - the gated live real-boundary smoke - IN SCOPE (USER OVERRIDE):
- This AC is now IN the acceptance path (USER PRINCIPLED OVERRIDE, Ben 2026-06-20,
  SUPERSEDES OQ-5: the GUI is LIVE-ONLY-REAL). It is satisfied by AC-1L: a real live
  paste->Run that crosses the real OpenRouter boundary and renders REAL positions, or an
  honest classified attrition message on free models. Its evidence class is
  `real-boundary-smoke`, run at acceptance. AC-4 still proves the gate is OFF-by-default
  (the classified "live required" refusal) as an offline `integration-fake` proof.

## Definition of Ready (Phase 0 gate)

- [x] Canvas Status == user-confirmed (Ben, 2026-06-20; carries the USER PRINCIPLED OVERRIDE
      of 2026-06-20 as a dated decision - Status preserved).
- [x] Open questions OQ-PROXY, OQ-UI, OQ-SCOPE, OQ-MVP, OQ-5 (and OQ-KEYSRC, OQ-HONESTY)
      resolved by the user at the Phase-0.15 gate; answers recorded inline above. NOTE:
      OQ-MVP / OQ-5 are SUPERSEDED by the USER PRINCIPLED OVERRIDE (LIVE-ONLY-REAL).
- [x] Allowed change scope confirmed and validated with `plumbline-scope-check` (unchanged
      by the override - same path list).
- [x] Product Vision created by product-owner (docs/vision/openrouter-gui.vision.md,
      authored 2026-06-20, consistent with the user-confirmed canvas + the override).
- [x] Product Vision user-confirmed (Ben, 2026-06-20, at the Phase-0 Vision gate; Vision
      Status is `user-confirmed`, reconciled to the override). Phase 0 complete.
- [x] All REQ-GUI-* testable/atomic/contradiction-free (re-checked after OQ resolution, the
      2026-06-20 Phase-0.5 spec-sanity remediation: REQ-GUI-013..017, AND the 2026-06-20
      USER PRINCIPLED OVERRIDE: REQ-GUI-018, LIVE-ONLY-REAL reconciled across 001/008/009).
- [x] USER PRINCIPLED OVERRIDE (Ben, 2026-06-20) applied consistently across canvas + PRD +
      vision: DEMO removed from the product contract; LIVE-ONLY-REAL; classified
      "live required" message when the gate is OFF / no key; `--inject-council` kept as
      test-only infra; evidence floor for the live path RAISED to `real-boundary-smoke`
      (offline mechanics stay `integration-fake`); UI/UX = role cards + diversity block +
      LIVE-status/attrition indicator + preset choice + RISK-B-007. This is a user-directed
      re-scope; confirmed statuses preserved.
- [x] Spec-sanity remediation (Phase 0.5, 2026-06-20) applied consistently across canvas +
      PRD + vision (architecture=subprocess; fail-loud preconditions; MVP-critical leak
      gate; wired-in-prod; mixed render; REQ-GUI-005 = structural key-absence guarantee,
      verified by the security suite's absence assertions). These are hardening/
      clarifications, not value reversals; confirmed statuses preserved. (The spec-sanity
      "MVP-honesty = offline injected/demo positions as MVP value" point is superseded by
      the override above.)

---

## Traceability matrix (stub - completed in Phase 0/0.5)

canvas-link: docs/canvas/openrouter-gui.canvas.md

| REQ-ID | Acceptance test | Impl task | Pass evidence |
|--------|-----------------|-----------|---------------|
| REQ-GUI-001 | AC-1L / AC-LIVE (real-boundary-smoke) | TBD (planner) | TBD (Phase 3 ledger) |
| REQ-GUI-002 | AC-1 | TBD | TBD |
| REQ-GUI-003 | AC-1 | TBD | TBD |
| REQ-GUI-004 | AC-5 | TBD | TBD |
| REQ-GUI-005 | AC-2 / SEC | TBD | TBD |
| REQ-GUI-006 | SEC | TBD | TBD |
| REQ-GUI-007 | AC-3 | TBD | TBD |
| REQ-GUI-008 | AC-4 / AC-LIVE | TBD | TBD |
| REQ-GUI-009 | AC-1 (test-only seam) | TBD | TBD |
| REQ-GUI-010 | SEC | TBD | TBD |
| REQ-GUI-011 | SEC | TBD | TBD |
| REQ-GUI-012 | AC-6 | TBD | TBD |
| REQ-GUI-013 | AC-9 / SEC | TBD | TBD |
| REQ-GUI-014 | AC-7 / SEC | TBD | TBD |
| REQ-GUI-015 | AC-8 / SEC | TBD | TBD |
| REQ-GUI-016 | AC-9 / SEC | TBD | TBD |
| REQ-GUI-017 | AC-10 | TBD | TBD |
| REQ-GUI-018 | AC-11 / AC-1 | TBD | TBD |

## Open questions - ALL RESOLVED at the Phase-0.15 gate (Ben, 2026-06-20)

No open questions remain. Decisions (recorded inline above and in the canvas):
- OQ-PROXY = Python stdlib `http.server` (no new deps).
- OQ-UI = a single self-contained HTML + vanilla JS (precedent: agent-explorer.html).
- OQ-SCOPE = `config/claude/gui/` for proxy + static, `config/claude/tests/test_gui_*.sh`
  for tests (the validated Allowed change scope in the canvas).
- OQ-MVP = IN: paste -> run preset LIVE -> render REAL positions (or honest classified
  message), loopback-only, offline-testable mechanics. OUT: auth, multi-user, run
  history/persistence, non-loopback/deploy. [RE-SCOPED by the USER PRINCIPLED OVERRIDE
  below: run mode is LIVE-ONLY-REAL, not offline/injected.]
- OQ-5 = SUPERSEDED by the USER PRINCIPLED OVERRIDE below. (Was: offline/injected MVP, no
  live run in the acceptance path, floor `integration-fake`, live smoke deferred. Now:
  LIVE-ONLY-REAL; the live paste->Run->REAL-positions smoke IS in the acceptance path;
  floor for that path = `real-boundary-smoke`; offline mechanics stay `integration-fake`.)
- OQ-KEYSRC = process env first, then `~/.openclaw/.env`.
- OQ-HONESTY = a visible in-UI "no verdict" disclosure carrying RISK-B-007.

USER PRINCIPLED OVERRIDE (Ben, 2026-06-20): the bundled DEMO council violates "real code or
no code" (`placeholder` is a FORBIDDEN_TOKEN). Directive: "nur echt und nur was geht.
Fake=Demo, dann weglassen." => (1) DEMO removed from the product contract; (2) GUI is
LIVE-ONLY-REAL (paste->Run runs the REAL council live, gated by `COUNCIL_INFERENCE_LIVE=1`
+ key, and renders REAL positions or honest classified errors/attrition, never a fake
fallback); (3) gate-OFF / no-key => a classified "live required to run the council"
message, NOT a demo; (4) `--inject-council` kept ONLY as test infrastructure; (5) evidence
floor for the live render path RAISED to `real-boundary-smoke` (offline mechanics stay
`integration-fake`); (6) UI/UX = role cards + diversity block + LIVE-status/attrition
indicator + preset choice + RISK-B-007. Recorded as the dated decision in the canvas's User
confirmation section; reconciled across canvas + PRD + vision. Canvas Status / PRD Status
preserved.
