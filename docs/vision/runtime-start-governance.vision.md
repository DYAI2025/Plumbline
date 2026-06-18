# Product Vision: Runtime Start Governance

Status: user-confirmed
Feature-Slug: runtime-start-governance
Slice: BL-002 / BL-003
Canvas: docs/canvas/runtime-start-governance.canvas.md

> Confirmed by Ben on 2026-06-18 via the `/agileteam` user-confirmation gate.

## Vision Statement

Plumbline soll vor jedem `/agileteam`-Planning zuverlässig sichtbar machen, ob die
minimale Produktabsicht vorhanden ist. Wenn eine PRD oder Feature-Anfrage existiert, aber
keine bestätigte Product Vision vorliegt, muss der Startpfad `VISION_MISSING` anzeigen und
Planning sowie Coding blockieren.

## Target User

- `ASSUMPTION`: Plumbline-Maintainer, die Governance-Claims prüfbar machen wollen.
- `ASSUMPTION`: Coding-Agenten, die klare Stop-/Go-Signale brauchen.
- `ASSUMPTION`: Reviewer, die erkennen müssen, ob `/agileteam` auf gültiger Produktgrundlage arbeitet.

## Problem

`EXPLICIT`: `VISION_MISSING` ist ohne Runtime-Integration nur teilweise beweisbar. Die
Klassifikationslogik existiert bereits (`config/claude/lib/plumbline_start.py`), ist aber
nicht in den realen Start-Pfad eingebunden — daher kann `/agileteam` in der Praxis trotzdem
zu früh in Planning oder Coding kippen.

## Value Proposition

`EXPLICIT`: Plumbline wird wahrheitstreuer, weil die Product-Vision-Pflicht nicht nur
dokumentiert, sondern im Startablauf sichtbar blockierend wirkt — und das per Dry-Run
reproduzierbar belegt ist.

## Product Outcome

- `/agileteam` erkennt fehlende bestätigte Vision (über die bestehende Klassifikation).
- `/agileteam` zeigt einen klaren Statusblock (`render_status_panel`).
- `/agileteam` erlaubt Vision Extraction.
- `/agileteam` blockiert Planning und Coding bis zur expliziten User Confirmation.
- Eine Dry-Run-Fixture belegt das Verhalten.

## Success Signals

- `SS-A-001`: Test für PRD-present + Vision-missing läuft grün.
- `SS-A-002`: Dry-Run-Evidence enthält `Gate: VISION_MISSING`.
- `SS-A-003`: Dry-Run-Evidence enthält `Planning allowed: NO`.
- `SS-A-004`: Dry-Run-Evidence enthält `Coding allowed: NO`.
- `SS-A-005`: Backlog-Status von BL-002 und BL-003 kann mit Evidenz geschlossen werden.

## Non-Goals

- Kein vollständiger Umbau der `/agileteam`-Pipeline.
- Kein neues Product-Vision-Format.
- Kein fataler Crash bei fehlender Vision.
- Kein automatisches Simulieren der User Confirmation.
- Kein Claim von Production-Readiness ohne echte Runtime-/Boundary-Evidenz.

## Strategic Fit

Passt zum Plumbline-Prinzip: keine Schein-Fortschritte, keine impliziten Produktannahmen,
keine Coding-Aktivität ohne bestätigten Wertanker.

## User Confirmation

Confirmed by user: yes — Ben, 2026-06-18.
