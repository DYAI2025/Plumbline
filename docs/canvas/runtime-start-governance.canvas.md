# Product Canvas: Runtime Start Governance

Status: user-confirmed
Owner: requirements-analyst
Confirmed by user: yes
Canvas file: docs/canvas/runtime-start-governance.canvas.md
Feature-Slug: runtime-start-governance
Slice: BL-002 / BL-003

> Confirmed by Ben on 2026-06-18 via the `/agileteam` user-confirmation gate
> ("Beide Slices bestätigen"). No agent self-confirmed this canvas.

## 1. Problem

| ID | Feld | Inhalt | Status |
|---|---|---|---|
| CAN-A-001 | Problem | `VISION_MISSING` kann ohne Runtime-Integration als bloße Contract-/CLI-Behauptung verbleiben. | EXPLICIT |
| CAN-A-002 | Auswirkung | `/agileteam` könnte in Planning/Coding starten, obwohl keine bestätigte Product Vision existiert. | ASSUMPTION |
| CAN-A-003 | Dringlichkeit | Hoch, weil Plumbline Wahrheits- und Governance-Claims macht. | ASSUMPTION |

## 2. Zielnutzer

| ID | Nutzergruppe | Bedürfnis | Status |
|---|---|---|---|
| CAN-A-004 | Plumbline-Maintainer | Sie brauchen belastbare Evidence, dass Start-Gates wirken. | ASSUMPTION |
| CAN-A-005 | Coding-Agenten | Sie brauchen eindeutige Stop-/Go-Signale. | ASSUMPTION |
| CAN-A-006 | Reviewer | Sie müssen sehen, ob ein Slice auf bestätigter Produktabsicht basiert. | ASSUMPTION |

## 3. Current workaround

Heute existiert die Start-Klassifikation als deterministische Bibliothek
(`config/claude/lib/plumbline_start.py`) plus CLI-Test
(`config/claude/tests/test_agileteam_start_gate.sh`). Sie ist aber NICHT in den realen
Session-/Start-Pfad eingebunden und es gibt keine Live-Dry-Run-Evidence. Der Status wird
heute primär „behauptet", nicht runtime-nah vorgeführt.

## 4. Value Proposition

| ID | Aussage | Status |
|---|---|---|
| CAN-A-007 | Runtime Start Governance verhindert, dass `/agileteam` auf unbestätigter Produktbasis plant oder codet. | EXPLICIT |
| CAN-A-008 | Dry-Run-Evidence macht die Governance prüfbar. | EXPLICIT |
| CAN-A-009 | Die Funktion stärkt Plumbline gegen Statusdrift und Scheinreife. | ASSUMPTION |

## 5. Lösungsskizze

| ID | Baustein | Beschreibung | Status |
|---|---|---|---|
| CAN-A-010 | Start Classifier Integration | Bestehende `plumbline_start.classify_start_state()` wird in den SessionStart-/`/agileteam`-Startpfad eingebunden (nicht-fatal). | EXPLICIT |
| CAN-A-011 | Status Panel | `render_status_panel()` zeigt Gate, fehlende Artefakte und erlaubte nächste Schritte. | EXPLICIT (existiert) |
| CAN-A-012 | Blocking Semantics | Planning und Coding sind bei `VISION_MISSING` blockiert. | EXPLICIT |
| CAN-A-013 | Dry-Run Fixture | Reproduzierbare Evidence-Datei belegt PRD-present + Vision-missing. | EXPLICIT |

## 6. Core use case

Ein User ruft `/agileteam` mit vorhandener PRD, aber ohne bestätigte Product Vision auf.
Der Startpfad ruft die bestehende Klassifikation nicht-fatal auf und zeigt
`Gate: VISION_MISSING`, `Planning allowed: NO`, `Coding allowed: NO` plus den einzig
erlaubten nächsten Schritt (Vision Extraction + explizite User Confirmation). Eine
Dry-Run-Fixture friert genau dieses Verhalten als Evidence ein.

## 7. Non-Goals

- Kein vollständiger Umbau der `/agileteam`-Pipeline.
- Kein neues Product-Vision-Format.
- Kein fataler Crash bei fehlender Vision (SessionStart darf nicht brechen).
- Kein automatisches Simulieren der User Confirmation.
- Kein Claim von Production-Readiness ohne echte Runtime-/Boundary-Evidenz.

## 8. Risks / contradictions

| ID | Risiko | W'keit | Impact | Mitigation | Status |
|---|---|---:|---:|---|---|
| RISK-A-001 | Startlogik wird dupliziert statt wiederverwendet | mittel | hoch | `plumbline_start.py` als Source of Truth nutzen | CONFIRMED |
| RISK-A-002 | Gate wird fatal statt steuernd | mittel | mittel | Exit-/Status-Semantik testen; SessionStart bleibt `continue:true` | CONFIRMED |
| RISK-A-003 | Fixture belegt nur Text, nicht Startpfad | mittel | hoch | Fixture über realistischen Command-/Startpfad erzeugen | CONFIRMED |
| RISK-A-004 | User Confirmation wird implizit simuliert | niedrig | hoch | Confirmation nur als User-Block, nie automatisch setzen | CONFIRMED |

## 9. Evidence needed

- Testoutput Start-Gate (REQ-A-001..004) — grün.
- Dry-Run-Evidence-Datei mit `Gate: VISION_MISSING`, `Planning allowed: NO`, `Coding allowed: NO`.
- Reality-Ledger-Klasse: Ziel `real-boundary-smoke` für die SessionStart-nahe Einbindung;
  reiner Lib-/CLI-Test bleibt `integration-fake` und ist damit für den Runtime-Claim NICHT hinreichend.

## Allowed change scope

> Vorgeschlagen vom Orchestrator, geerdet am Repo. Final-OK durch den User am Pre-Build-Gate.

- `config/claude/lib/plumbline_start.py`
- `config/claude/hooks/session-start.sh`
- `config/claude/tests/test_agileteam_start_gate.sh`
- `config/claude/tests/` (neue Dry-Run-Test-Datei für dieses Feature)
- `config/claude/commands/agileteam.md` (nur Doku der Start-Governance)
- `docs/benchmarks/2026-06-18-runtime-start-governance.md` (Dry-Run-Evidence)
- `docs/canvas/runtime-start-governance.canvas.md`, `docs/vision/…`, `docs/prd/…`, `docs/traceability.md`
- `backlog.md` (BL-002/BL-003 Closure)

Status: user-confirmed (Scope-Detail-OK ausstehend)

## 10. Traceability links

PRD: docs/prd/runtime-start-governance.prd.md
Product Vision: docs/vision/runtime-start-governance.vision.md
Traceability Matrix: docs/traceability.md
Related REQ IDs: REQ-A-001 … REQ-A-010
True-Line status: pass

## Open Questions (resolved at confirmation)

| ID | Frage | Auflösung |
|---|---|---|
| OQ-A-001 | Dry-Run unter `docs/evidence/` oder `docs/benchmarks/`? | `docs/benchmarks/` — Repo-Konvention (datierte Dateien); `docs/evidence/` existiert nicht. |
| OQ-A-002 | Welcher Command gilt als runtime-nah? | SessionStart-Hook-nahe, nicht-fatale Invokation + reproduzierbare Dry-Run-Fixture. |

## User confirmation

Confirmed by user: yes
Confirmation date: 2026-06-18
Confirmation note: Ben bestätigte beide Slices über den /agileteam-Confirmation-Gate.
