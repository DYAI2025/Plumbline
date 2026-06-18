# PRD: Runtime Start Governance

Status: user-confirmed
Feature-Slug: runtime-start-governance
Slice: BL-002 / BL-003
Canvas: docs/canvas/runtime-start-governance.canvas.md
Vision: docs/vision/runtime-start-governance.vision.md

> Confirmed by Ben on 2026-06-18 via the `/agileteam` user-confirmation gate.

## 1. Summary

Dieses Feature bindet die bestehende Start-Klassifikation
(`config/claude/lib/plumbline_start.py`) nicht-fatal in den realen `/agileteam`-/SessionStart-Pfad
ein und erzeugt eine Dry-Run-Fixture, die beweist, dass `VISION_MISSING` bei fehlender
bestätigter Product Vision Planning und Coding blockiert.

## 2. Problem Statement

`EXPLICIT`: BL-002 ist offen, weil `VISION_MISSING` sonst primär in Contract-/CLI-Schichten bleibt.
`EXPLICIT`: BL-003 ist offen, weil eine Live-/Dry-Run-Fixture nötig ist, um Start-Governance
nicht nur statisch zu behaupten.

**Evidenz-Befund (2026-06-18):** Die Output-Strings (`Gate:`, `Planning allowed: NO`,
`Coding allowed: NO`) und die Branch-Logik existieren bereits in `plumbline_start.py`.
Der echte Delta ist deshalb schmal: (a) nicht-fatale SessionStart-nahe Invokation,
(b) reproduzierbare Dry-Run-Evidence.

## 3. Goals

| ID | Goal | Status |
|---|---|---|
| GOAL-A-001 | `/agileteam` prüft vor Planning den Vision-Status. | EXPLICIT |
| GOAL-A-002 | Fehlende bestätigte Vision erzeugt `VISION_MISSING`. | EXPLICIT |
| GOAL-A-003 | Planning und Coding werden blockiert. | EXPLICIT |
| GOAL-A-004 | Dry-Run-Fixture belegt das Verhalten. | EXPLICIT |

## 4. Non-Goals

| ID | Non-Goal |
|---|---|
| NGOAL-A-001 | Kein Umbau der gesamten AgileTeam-Pipeline |
| NGOAL-A-002 | Kein automatisches Bestätigen der Product Vision |
| NGOAL-A-003 | Keine echte Produktionsbeobachtung |
| NGOAL-A-004 | Kein OpenRouter-/Council-Scope |

## 5. Functional Requirements

| ID | Requirement | Source | Priority |
|---|---|---|---|
| REQ-A-001 | `/agileteam` muss den Start-Classifier vor Planning/Coding aufrufen oder dessen Status verbindlich konsumieren. | SRC-A-001 | MUST |
| REQ-A-002 | Bei PRD-present + Vision-missing muss `Gate: VISION_MISSING` erscheinen. | SRC-A-002 | MUST |
| REQ-A-003 | Bei `VISION_MISSING` muss `Planning allowed: NO` erscheinen. | SRC-A-003 | MUST |
| REQ-A-004 | Bei `VISION_MISSING` muss `Coding allowed: NO` erscheinen. | SRC-A-003 | MUST |
| REQ-A-005 | Der erlaubte nächste Schritt muss Vision Extraction + explizite User Confirmation sein. | SRC-A-004 | MUST |
| REQ-A-006 | Es muss eine Dry-Run-Fixture geben, die den Fall PRD-present + Vision-missing belegt. | SRC-A-002 | MUST |
| REQ-A-007 | Das Gate darf nicht als technischer Crash wirken, sondern als steuernder Blocker (SessionStart bleibt `continue:true`). | SRC-A-004 | SHOULD |

## 6. Non-Functional Requirements

| ID | Requirement | Source | Priority |
|---|---|---|---|
| REQ-A-008 | Die Implementierung darf bestehende Startlogik nicht duplizieren (Reuse `plumbline_start.py`). | SRC-A-004 | SHOULD |
| REQ-A-009 | Die Ausgabe muss deterministisch testbar sein. | SRC-A-005 | MUST |
| REQ-A-010 | Die Evidence muss menschenlesbar und agentenlesbar sein. | SRC-A-005 | SHOULD |

## 7. Acceptance Criteria

### AC-A-001: Missing Vision Gate
Given eine `/agileteam`-Startanfrage mit vorhandener PRD
And keine bestätigte Product Vision existiert
When der Start-Classifier runtime-nah ausgeführt wird
Then die Ausgabe enthält `Gate: VISION_MISSING`

### AC-A-002: Planning Block
Given `Gate: VISION_MISSING`
When `/agileteam` den Status verarbeitet
Then die Ausgabe enthält `Planning allowed: NO`

### AC-A-003: Coding Block
Given `Gate: VISION_MISSING`
When `/agileteam` den Status verarbeitet
Then die Ausgabe enthält `Coding allowed: NO`

### AC-A-004: Next Allowed Step
Given `Gate: VISION_MISSING`
When der Status ausgegeben wird
Then der nächste erlaubte Schritt ist Vision Extraction plus explizite User Confirmation

### AC-A-005: Dry-Run Evidence
Given die Fixture für PRD-present + Vision-missing
When der entsprechende Test ausgeführt wird
Then eine Evidence-Datei oder Snapshot-Ausgabe belegt Gate, Blocking und Missing Artifact

## 8. Evidence Requirements

| ID | Evidence | Required For |
|---|---|---|
| EV-A-001 | Testoutput Start-Gate | REQ-A-001 bis REQ-A-004 |
| EV-A-002 | Dry-Run-Fixture (`docs/benchmarks/2026-06-18-runtime-start-governance.md`) | REQ-A-006 |
| EV-A-003 | Backlog-Link/Statusupdate | BL-002/BL-003 Closure |
| EV-A-004 | Command-Ausgabe oder Snapshot | AC-A-001 bis AC-A-005 |

## 9. Risks and Edge Cases

| ID | Edge Case | Expected Behavior |
|---|---|---|
| EDGE-A-001 | PRD fehlt ebenfalls | anderer Gate-Status, nicht `VISION_MISSING` allein |
| EDGE-A-002 | Vision existiert, aber nicht bestätigt | bestehende „missing confirmed intake artifacts"-Branch; `VISION_MISSING` nicht überdehnen |
| EDGE-A-003 | Start-Classifier nicht ausführbar | Fehler offenlegen, nicht Planning erlauben |
| EDGE-A-004 | User versucht Coding trotz Gate | Coding bleibt blockiert |

## 10. Implementation Notes

- Bestehende `plumbline_start.classify_start_state()` / `render_status_panel()` wiederverwenden.
- SessionStart-Hook (`config/claude/hooks/session-start.sh`) nicht-fatal erweitern.
- Test zuerst schreiben (TDD).
- Dry-Run-Fixture als Evidence unter `docs/benchmarks/` speichern.
- Keine User Confirmation simulieren.
- **Reality Ledger:** reiner Lib-/CLI-Test = `integration-fake`; SessionStart-nahe Einbindung
  muss `real-boundary-smoke` erreichen, sonst PASS(tests)/RED(confidence).

## 11. Definition of Done

- Alle MUST-Requirements erfüllt.
- AC-A-001 bis AC-A-005 testbar belegt.
- Dry-Run-Fixture vorhanden.
- Backlog/Planstatus für BL-002/BL-003 aktualisiert.
- User Confirmation liegt vor (Ben, 2026-06-18). ✔
