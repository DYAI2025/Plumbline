# Traceability Matrix: OpenRouter Council-Runner GUI (Slice 4)

Feature: openrouter-gui
Branch: agileteam/openrouter-gui
Canvas: docs/canvas/openrouter-gui.canvas.md (Status: user-confirmed, Ben 2026-06-20)
Product Vision: docs/vision/openrouter-gui.vision.md (Status: user-confirmed, Ben 2026-06-20)
PRD: docs/prd/openrouter-gui.prd.md (Status: finalized)
Reality Ledger: docs/reality/openrouter-gui.evidence.jsonl
True-Line status (feature): aligned

This matrix completes the TBD cells of the PRD stub (PRD section "Traceability matrix").
It maps each REQ-GUI / acceptance criterion to the test(s) proving it, the honest
evidence class, whether the capability is reached through the production composition root
(wired-in-prod), and the True-Line status.

## Reality-Ledger note (honest evidence floor)

**Split evidence floor (user override, Ben 2026-06-20 — "nur echt, kein Demo"):** the bundled
DEMO was REMOVED. The user-facing path is LIVE-ONLY-REAL — paste→Run runs the real council
live (or returns the classified `COUNCIL_LIVE_REQUIRED` when live is unavailable; never a fake).
The LIVE render path (REQ-GUI-001, REQ-GUI-008) was exercised across the real OpenRouter
boundary by the live smoke (`docs/benchmarks/2026-06-20-openrouter-gui-live-smoke.md`: 1/4
roles a real position, 3/4 honest classified attrition, leak-check 0) → those records are
`real-boundary-smoke`. The remaining 16 records are `integration-fake` — the offline render /
security / routing MECHANICS proven via the test-only `--inject-council` seam (0 credits). The
key-leak gate runs at FULL strength (the key is resident whenever the live path is usable). The
`real-boundary-smoke` is a wiring/capability smoke, NOT a quality/value verdict.

## REQ-to-test matrix

| REQ-ID | Acceptance criterion | Proving test(s) | Evidence class | Wired-in-prod? | True-Line status |
|--------|----------------------|-----------------|----------------|----------------|------------------|
| REQ-GUI-001 | AC-1 / AC-LIVE | live smoke (real POST /run crossed the OpenRouter boundary, real position rendered) + test_gui_proxy.sh::AC-1 (offline render mechanics via the inject seam) | real-boundary-smoke | yes - REAL launcher + real loopback socket POST /run; live boundary crossed | aligned |
| REQ-GUI-002 | AC-1 | test_gui_proxy.sh::REQ-GUI-002 (4 positions; roles, model id, position text) | integration-fake | yes - rendered through the real socket path (AC-1 socket POST) | aligned |
| REQ-GUI-003 | AC-1 | test_gui_proxy.sh::REQ-GUI-003 (distinct_bases + COUNCIL_DIVERSITY_OK) | integration-fake | yes - rendered through the real socket path (AC-1 socket POST) | aligned |
| REQ-GUI-004 | AC-5 | test_gui_proxy.sh::REQ-GUI-004/AC-5 (RISK-B-007 verbatim; no APPROVED/VERDICT) | integration-fake | yes - disclosure asserted on the real socket render (AC-1 socket POST) | aligned |
| REQ-GUI-005 | AC-2 / SEC | test_gui_security.sh::REQ-GUI-005/AC-2 (sentinel absent from assets, all bodies, logs) | integration-fake | yes - asserted on served assets + real socket response body | aligned |
| REQ-GUI-006 | SEC | test_gui_security.sh::REQ-GUI-006/NFR-GUI-SEC-4 (no urlopen/urllib/openrouter; key not in handler locals) | integration-fake | yes - source-level invariant over the prod proxy module | aligned |
| REQ-GUI-007 | AC-3 | test_gui_security.sh::REQ-GUI-007/AC-3 (bind_host 127.0.0.1, allow_non_loopback false by default; opt-in gate) | integration-fake | yes - reads the prod proxy `config` entrypoint | aligned |
| REQ-GUI-008 | AC-4 / AC-LIVE | live smoke (gate-on + secret crossed the real boundary) + test_gui_proxy.sh::AC-4 (gate-off -> COUNCIL_LIVE_REFUSED, 0 spawn; offline-no-live -> COUNCIL_LIVE_REQUIRED, no fake) | real-boundary-smoke | yes - the live gate proven BOTH ways: OFF refuses, ON crosses the real boundary | aligned |
| REQ-GUI-009 | AC-1 | test_gui_proxy.sh::AC-1/REQ-GUI-009 (offline spawn-count exactly 0 via inject-spawn-counter) | integration-fake | yes - paste->run->render over the real socket (AC-1 socket POST) | aligned |
| REQ-GUI-010 | SEC | test_gui_security.sh::REQ-GUI-006/010 (no transport/preset/diversity re-impl) + test_gui_proxy.sh::AC-1 pass-through | integration-fake | yes - pass-through verified on the real socket render | aligned |
| REQ-GUI-011 | SEC | test_gui_proxy.sh::REQ-GUI-011 (metachar subject no shell side-effect; script payload escaped) | integration-fake | yes - escaping asserted on the rendered output | aligned |
| REQ-GUI-012 | AC-6 | test_gui_proxy.sh::AC-6 (exact classified code surfaced; no fabricated OK; bad preset no traceback) | integration-fake | yes - classified code surfaced through the render entrypoint | aligned |
| REQ-GUI-013 | AC-9 / SEC | test_gui_security.sh::NFR-GUI-SEC-4 (key in child env only, not handler locals) + test_gui_proxy.sh spawn-counter seam | integration-fake | yes - real launcher (AC-9) drives the subprocess composition path | aligned |
| REQ-GUI-014 | AC-7 / SEC | test_gui_proxy.sh::AC-7 (missing-key -> COUNCIL_MISSING_SECRET) + AC-9 (wrong-cwd classified signal, no silent OK) | integration-fake | yes - preconditions enforced by the REAL launcher start (AC-9) | aligned |
| REQ-GUI-015 | AC-8 / SEC | test_gui_security.sh::AC-8 (malformed POST + >1MiB oversized over real socket: no leak, generic 500, no traceback/body/env) + broken-pipe | integration-fake | yes - induced-error paths driven over the real loopback socket | aligned |
| REQ-GUI-016 | AC-9 / SEC | test_gui_proxy.sh::AC-9 (REAL plumbline-council-gui launcher --self-check from repo-root + from-wrong-cwd) + AC-1 real socket POST /run 200, POST /unknown 404 | integration-fake | yes - the REAL launcher process AND the real loopback HTTP socket ARE the proof | aligned |
| REQ-GUI-017 | AC-10 | test_gui_proxy.sh::AC-10 (mixed COUNCIL_MODEL_UNAVAILABLE renders OK positions AND classified codes; 200 honest partial; no ALL_OK) | integration-fake | yes - mixed render exercised through the render entrypoint | aligned |
| REQ-GUI-018 | AC-11 | test_gui_proxy.sh (role cards: character+model+position/classified code; diversity/foreign-only block; LIVE-status/attrition indicator; preset choice; RISK-B-007 disclosure) + static assets render; live smoke shows the real-position + attrition render | integration-fake | yes - UI rendered through the real socket path + the live smoke | aligned |

## Acceptance-criteria coverage cross-check

| AC | REQ(s) | Test anchor |
|----|--------|-------------|
| AC-1 | REQ-GUI-001/002/003/009/016 | test_gui_proxy.sh::AC-1 (CLI render) + AC-1/REQ-GUI-016 real loopback socket POST /run |
| AC-2 | REQ-GUI-005 | test_gui_security.sh::REQ-GUI-005/AC-2 |
| AC-3 | REQ-GUI-007 | test_gui_security.sh::REQ-GUI-007/AC-3 (config --json) |
| AC-4 | REQ-GUI-008 | test_gui_proxy.sh::AC-4 |
| AC-5 | REQ-GUI-004 | test_gui_proxy.sh::REQ-GUI-004/AC-5 |
| AC-6 | REQ-GUI-012 | test_gui_proxy.sh::AC-6 |
| AC-7 | REQ-GUI-014 | test_gui_proxy.sh::AC-7 |
| AC-8 | REQ-GUI-005/015 | test_gui_security.sh::AC-8 (malformed + oversized over real socket) + broken-pipe |
| AC-9 | REQ-GUI-013/014/016 | test_gui_proxy.sh::AC-9 (real launcher --self-check; from-wrong-cwd) |
| AC-10 | REQ-GUI-017 | test_gui_proxy.sh::AC-10 |
| AC-LIVE | REQ-GUI-001/008 | EXERCISED - the live real-boundary smoke ran (docs/benchmarks/2026-06-20-openrouter-gui-live-smoke.md: real position + honest attrition, leak 0); the OFF-by-default refusal is also proven (AC-4) |
| AC-11 | REQ-GUI-018 | test_gui_proxy.sh (role cards + diversity + attrition indicator + preset + RISK-B-007) + the live smoke render |

## Wired-in-prod summary

The headline paste->run->render is proven reachable through the production composition root
two ways, both offline: (1) the REAL `config/claude/bin/plumbline-council-gui` launcher
started `--self-check` (its cwd-pin, key-in-child-env, and fail-loud preconditions are
exercised, not dead code); and (2) a real loopback HTTP socket POST to the served `/run`
route (with `/unknown` correctly 404ing). This directly guards the repo's signature
"injectable seam green, real entrypoint dead" false-green. The LIVE path additionally crossed
the real OpenRouter boundary in the live smoke (REQ-GUI-001/008 → `real-boundary-smoke`): the
served `POST /run` with the gate on + secret spawned the real council and rendered a real
position + honest classified attrition (leak-check 0). Offline-without-live returns the honest
`COUNCIL_LIVE_REQUIRED` — no demo, no fake fallback.
