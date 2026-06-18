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
| TRC-B-001 | REQ-B-001 | CAN-B-011 | AC-B-006 | EV-B-002 | TBD | real-boundary-smoke | pass |
| TRC-B-002 | REQ-B-002 | CAN-B-011 | AC-B-001 | EV-B-001 | TBD | integration-fake | pass |
| TRC-B-003 | REQ-B-003 | CAN-B-011 | AC-B-009 | EV-B-003, EV-B-006 | TBD | integration-fake | pass |
| TRC-B-004 | REQ-B-004 | CAN-B-012 | AC-B-001 | EV-B-001 | TBD | integration-fake | pass |
| TRC-B-005 | REQ-B-005 | CAN-B-012 | AC-B-001 | EV-B-001 | TBD | integration-fake | pass |
| TRC-B-006 | REQ-B-006 | CAN-B-012 | AC-B-001 | EV-B-001 | TBD | integration-fake | pass |
| TRC-B-006b | REQ-B-006b | CAN-B-012 | AC-B-001 | EV-B-001 | TBD | integration-fake | pass |
| TRC-B-007 | REQ-B-007 | CAN-B-012 | AC-B-002 | EV-B-001 | TBD | integration-fake | pass |
| TRC-B-008 | REQ-B-008 | CAN-B-012 | AC-B-003 | EV-B-001 | TBD | integration-fake | pass |
| TRC-B-009 | REQ-B-009 | CAN-B-010 | EDGE-B-003 | EV-B-002 | TBD | integration-fake | pass |
| TRC-B-010 | REQ-B-010 | CAN-B-013 | AC-B-007 | EV-B-004 | TBD | integration-fake | pass |
| TRC-B-011 | REQ-B-011 | CAN-B-014 | AC-B-004..006 | EV-B-002 | TBD | real-boundary-smoke | pass |
| TRC-B-012 | REQ-B-012 | CAN-B-014 | AC-B-004, AC-B-005 | EV-B-002 | TBD | real-boundary-smoke | pass |
| TRC-B-013 | REQ-B-013 | CAN-B-014 | AC-B-010 | EV-B-002 | TBD | real-boundary-smoke | pass |
| TRC-B-014 | REQ-B-014 | CAN-B-015 | AC-B-008 | EV-B-005 | TBD | integration-fake | pass |
| TRC-B-015 | REQ-B-015 | CAN-B-016 | AC-B-001..010 | EV-B-001..005 | TBD | integration-fake | pass |
| TRC-B-016 | REQ-B-016 | CAN-B-011 | AC-B-009 | EV-B-003 | TBD | integration-fake | pass |
| TRC-B-017 | REQ-B-017 | CAN-B-014 | AC-B-004, AC-B-005, AC-B-010 | EV-B-002 | TBD | real-boundary-smoke | pass |
| TRC-B-018 | REQ-B-018 | CAN-B-011 | EDGE-B-004 | EV-B-002 | TBD | integration-fake | pass |
| TRC-B-019 | REQ-B-019 | CAN-B-013, CAN-B-015 | AC-B-008 | EV-B-004, EV-B-005 | TBD | integration-fake | pass |
| TRC-B-020 | REQ-B-020 | CAN-B-014 | AC-B-010 | EV-B-002 | TBD | integration-fake | pass |

---
