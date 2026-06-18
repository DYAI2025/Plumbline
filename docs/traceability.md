# Traceability Matrix

Status: user-confirmed (both slices, Ben, 2026-06-18)

This matrix threads REQ ↔ vision ↔ canvas ↔ acceptance ↔ evidence ↔ wired-in-prod ↔
evidence-class ↔ True-Line status. `evidence-class` ∈
`unit-fake | integration-fake | real-boundary-smoke | production-verified`. A feature
touching I/O / remote / UI that stays `*-fake` is RED regardless of green tests.

---

## Slice: Runtime Start Governance (BL-002 / BL-003)

- Feature-Slug: runtime-start-governance
- canvas-link: docs/canvas/runtime-start-governance.canvas.md
- vision-link: docs/vision/runtime-start-governance.vision.md

| Trace ID | Requirement | Canvas | Acceptance | Evidence | wired-in-prod? | evidence-class (target) | True-Line |
|---|---|---|---|---|---|---|---|
| TRC-A-001 | REQ-A-001 (command-level Gate konsumiert Verdict, HALT vor Planning) | CAN-A-010 | AC-A-001 | EV-A-002 | instruction-only (cmd); realer HALT via Hook TRC-A-011 | real-boundary-smoke | pass |
| TRC-A-002 | REQ-A-002 | CAN-A-011 | AC-A-001 | EV-A-001, EV-A-004 | instruction-only | integration-fake | pass |
| TRC-A-003 | REQ-A-003 | CAN-A-012 | AC-A-002 | EV-A-001, EV-A-002, EV-A-004 | yes — Hook denied Planning (trace §2) | real-boundary-smoke | pass |
| TRC-A-004 | REQ-A-004 | CAN-A-012 | AC-A-003 | EV-A-001, EV-A-002, EV-A-004 | yes — Hook denied Coding (trace §3) | real-boundary-smoke | pass |
| TRC-A-005 | REQ-A-005 | CAN-A-013 | AC-A-004 | EV-A-002, EV-A-004 | instruction-only | integration-fake | pass |
| TRC-A-006 | REQ-A-006 (behavioraler real-boundary-Trace) | CAN-A-013 | AC-A-005 | EV-A-002 | yes — trace artifact (real run) | real-boundary-smoke | pass |
| TRC-A-007 | REQ-A-007 (LOCAL-Session, steuernd nicht fatal) | CAN-A-012 | AC-A-002, AC-A-003 | EV-A-002, EV-A-004 | yes — Hook fail-open (trace §5 + tests) | real-boundary-smoke | pass |
| TRC-A-008 | REQ-A-008 (Reuse, keine Duplizierung) | CAN-A-010 | AC-A-001 | EV-A-001 | instruction-only (Reuse per Test geprüft) | integration-fake | pass |
| TRC-A-009 | REQ-A-009 | CAN-A-011 | AC-A-001..005 | EV-A-001, EV-A-004 | instruction-only | integration-fake | pass |
| TRC-A-010 | REQ-A-010 | CAN-A-013 | AC-A-005 | EV-A-002 | instruction-only | integration-fake | pass |
| TRC-A-011 | REQ-A-011 (PreToolUse-Hook-Backstop, harness-erzwungen) | CAN-A-014 | AC-A-006 | EV-A-005 | yes — install.sh→settings.json PreToolUse (trace §2-4) | real-boundary-smoke | pass |

**BL-002/BL-003 closure (F3) — Stand 2026-06-18:** Der **Hook-Backstop (TRC-A-011)** und die
darüber getragenen Planning/Coding-Block-Zeilen (TRC-A-003/004/006/007) haben
`real-boundary-smoke` erreicht: reale Planning/Coding-Dispatches werden an der PreToolUse-
Prozessgrenze verweigert (Trace §2-4), wired via `install.sh`→`settings.json`. Der
**command-level Gate-HALT durch ein lebendes Modell (TRC-A-001/002/005/008/009/010)** bleibt
`integration-fake` und liest **PASS(tests)/RED(confidence)** — der Runtime bietet keinen
skriptbaren Zugriff auf den Kontrollfluss des Orchestrators, um „Planning nicht betreten"
modellseitig zu beweisen. Dieser RED darf NICHT heruntergestuft werden; nur der User darf am
Acceptance-Gate reklassifizieren.

**User-Reklassifizierung am Acceptance-Gate (Ben, 2026-06-18):** Der Hook-Layer
(TRC-A-011 + getragene Block-Zeilen) wird als `real-boundary-smoke` **akzeptiert und
geschlossen** (BL-002). Der command-gate Live-Modell-HALT bleibt `RED(confidence)` und wird
**als Ceiling akzeptiert** (BL-003) — nicht als „proven" deklariert, da der Runtime keinen
Kontrollfluss-Probe bietet. Die `Bash`-Tool-Lücke ist als v1-Boundary akzeptiert (Follow-up
BL-005). Kein autonomes Schließen erfolgte vor dieser User-Entscheidung.

**EDGE-A-002 (F2, verifiziert):** PRD-present + Vision-vorhanden-aber-unconfirmed →
`VISION_MISSING` (Kurzschluss `plumbline_start.py:25`). `START_ARTIFACTS_MISSING` ist ein
separater Branch, nur erreichbar bei BESTÄTIGTER Vision + fehlendem Canvas/Traceability.

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
