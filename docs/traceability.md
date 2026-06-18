# Traceability Matrix

Status: user-confirmed (OpenRouter Council Backend slice, Ben, 2026-06-18)

This matrix threads REQ ↔ vision ↔ canvas ↔ acceptance ↔ evidence ↔ wired-in-prod ↔
evidence-class ↔ True-Line status. `evidence-class` ∈
`unit-fake | integration-fake | real-boundary-smoke | production-verified`. A feature
touching I/O / remote / UI that stays `*-fake` is RED regardless of green tests.

---

## Slice: OpenRouter Council Backend (OD-3)

- Feature-Slug: openrouter-council-backend
- canvas-link: docs/canvas/openrouter-council-backend.canvas.md
- vision-link: docs/vision/openrouter-council-backend.vision.md

| Trace ID | Requirement | Canvas | Acceptance | Evidence | wired-in-prod? | evidence-class (target) | True-Line |
|---|---|---|---|---|---|---|---|
| TRC-B-001 | REQ-B-001 | CAN-B-011 | AC-B-006 | EV-B-002 | cmd instruction-only (int-fake) | real-boundary-smoke | pass |
| TRC-B-002 | REQ-B-002 | CAN-B-011 | AC-B-001 | EV-B-001 | yes — tests (int-fake) | integration-fake | pass |
| TRC-B-003 | REQ-B-003 | CAN-B-011 | AC-B-009 | EV-B-003, EV-B-006 | yes — .env.example + .gitignore | integration-fake | pass |
| TRC-B-004 | REQ-B-004 | CAN-B-012 | AC-B-001 | EV-B-001 | yes — tests (int-fake) | integration-fake | pass |
| TRC-B-005 | REQ-B-005 | CAN-B-012 | AC-B-001 | EV-B-001 | yes — tests (int-fake) | integration-fake | pass |
| TRC-B-006 | REQ-B-006 | CAN-B-012 | AC-B-001 | EV-B-001 | yes — tests (int-fake) | integration-fake | pass |
| TRC-B-006b | REQ-B-006b | CAN-B-012 | AC-B-001 | EV-B-001 | yes — tests (int-fake) | integration-fake | pass |
| TRC-B-007 | REQ-B-007 | CAN-B-012 | AC-B-002 | EV-B-001 | yes — tests (int-fake) | integration-fake | pass |
| TRC-B-008 | REQ-B-008 | CAN-B-012 | AC-B-003 | EV-B-001 | yes — tests (int-fake) | integration-fake | pass |
| TRC-B-009 | REQ-B-009 | CAN-B-010 | EDGE-B-003 | EV-B-002 | yes — tests (int-fake) | integration-fake | pass |
| TRC-B-010 | REQ-B-010 | CAN-B-013 | AC-B-007 | EV-B-004 | yes — tests (int-fake) | integration-fake | pass |
| TRC-B-011 | REQ-B-011 | CAN-B-014 | AC-B-004..006, EV-B-007 | EV-B-002, smoke §1/§2 | real-boundary-smoke: catalog reachability live-verified; invocability RED(conf) | real-boundary-smoke | pass |
| TRC-B-012 | REQ-B-012 | CAN-B-014 | AC-B-004, AC-B-005 | EV-B-002 | gate logic tested (int-fake); real RED(conf) | real-boundary-smoke | pass |
| TRC-B-013 | REQ-B-013 | CAN-B-014 | AC-B-010 | EV-B-002 | logic tested (int-fake); real RED(conf) | real-boundary-smoke | pass |
| TRC-B-014 | REQ-B-014 | CAN-B-015 | AC-B-008 | EV-B-005 | yes — tests (int-fake) | integration-fake | pass |
| TRC-B-015 | REQ-B-015 | CAN-B-016 | AC-B-001..010 | EV-B-001..005 | yes — tests run offline | integration-fake | pass |
| TRC-B-016 | REQ-B-016 | CAN-B-011 | AC-B-009 | EV-B-003 | yes — tests (int-fake) | integration-fake | pass |
| TRC-B-017 | REQ-B-017 | CAN-B-014 | AC-B-004, AC-B-005, AC-B-010 | EV-B-002 | logic tested (int-fake); real RED(conf) | real-boundary-smoke | pass |
| TRC-B-018 | REQ-B-018 | CAN-B-011 | EDGE-B-004 | EV-B-002 | yes — tests (int-fake) | integration-fake | pass |
| TRC-B-019 | REQ-B-019 | CAN-B-013, CAN-B-015 | AC-B-008 | EV-B-004, EV-B-005 | yes — tests (int-fake) | integration-fake | pass |
| TRC-B-020 | REQ-B-020 | CAN-B-014 | AC-B-010 | EV-B-002 | cmd instruction-only (int-fake) | integration-fake | pass |

**Reality Ledger (OD-3, honest ceiling) — updated 2026-06-18 after the real-boundary smoke:**
- The config/redaction/prompt/report/fail-closed LOGIC is `integration-fake` (offline, injected reachability).
- **TRC-B-011 reachability is now `real-boundary-smoke`:** the catalog-/list-models method was run
  **live against the OpenRouter API** with a real key (`docs/benchmarks/2026-06-18-openrouter-council-backend-smoke.md`
  §1: two distinct normalized bases reachable → proceed; §2: `:nitro`/`:floor` collapse to one → abort).
  The key never leaked (leak-check = 0).
- **Still `PASS(tests)/RED(confidence)`:** **invocability** (reachable ≠ invocable — a listed model may
  still 402/429; no completion probe was run, NGOAL-B-004) and **deep model diversity** (RISK-B-007 —
  two distinct base slugs could still be mirrored/similar models). The command-gate wiring
  (TRC-B-001/B-020) remains `cmd instruction-only (int-fake)`.
This RED may not be downgraded; only the user may reclassify at the acceptance gate.

**User acceptance (Ben, 2026-06-18):** OD-3 accepted — catalog-reachability + normalized-base
diversity gate accepted as `real-boundary-smoke`; **invocability and deep model diversity
accepted as ceiling at `RED(confidence)`** (a paid completion probe was not required). The
invocability probe remains an optional future step; not claimed proven.

---
