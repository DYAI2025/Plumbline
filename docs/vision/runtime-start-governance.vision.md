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

`EXPLICIT`: `VISION_MISSING` ist ohne realen Konsumpunkt nur teilweise beweisbar. Die
Klassifikationslogik existiert bereits (`config/claude/lib/plumbline_start.py`), aber kein
realer Befehlsfluss konsumiert ihr Verdict und hält an — daher kann `/agileteam` in der
Praxis trotzdem zu früh in Planning oder Coding kippen. Auflösung: ein command-level Gate
in `/agileteam` Phase 0 (NICHT SessionStart, das die Loop strukturell nicht anhalten kann).

## Value Proposition

`EXPLICIT`: Plumbline wird wahrheitstreuer, weil die Product-Vision-Pflicht nicht nur
dokumentiert, sondern im Startablauf sichtbar blockierend wirkt — und das per Dry-Run
reproduzierbar belegt ist.

## Product Outcome

- `/agileteam` erkennt in Phase 0 fehlende bestätigte Vision (über die bestehende Klassifikation, via `plumbline-start-check`).
- `/agileteam` zeigt einen klaren Statusblock (`render_status_panel`).
- `/agileteam` erlaubt Vision Extraction.
- `/agileteam` betritt Planning/Coding nicht, bis explizite User Confirmation vorliegt (command-level Gate).
- Ein PreToolUse-Hook verweigert Planning-/Coding-Dispatch bei `VISION_MISSING` harness-erzwungen (Defense-in-Depth-Backstop).
- Ein behavioraler real-boundary-Trace belegt den Halt VOR Planning.

## Success Signals

- `SS-A-001`: Test für PRD-present + Vision-missing läuft grün.
- `SS-A-002`: Real-boundary-Trace enthält `Gate: VISION_MISSING`.
- `SS-A-003`: Real-boundary-Trace enthält `Planning allowed: NO` und `/agileteam` betritt Planning nicht.
- `SS-A-004`: Real-boundary-Trace enthält `Coding allowed: NO` und `/agileteam` betritt Coding nicht.
- `SS-A-005`: Backlog-Status von BL-002/BL-003 kann mit `real-boundary-smoke`-Evidenz geschlossen werden (sonst PASS(tests)/RED(confidence)).

## Non-Goals

- Kein vollständiger Umbau der `/agileteam`-Pipeline (nur der Phase-0-Gate-Schritt).
- Kein neues Product-Vision-Format.
- Kein fataler Crash bei fehlender Vision (Gate ist steuernd).
- Kein SessionStart-Enforcement (strukturell nicht halt-fähig). Der PreToolUse-Hook ist hingegen der gewählte harness-erzwungene Backstop.
- Kein automatisches Simulieren der User Confirmation.
- Kein Claim von Production-Readiness ohne echte Runtime-/Boundary-Evidenz.

## Strategic Fit

Passt zum Plumbline-Prinzip: keine Schein-Fortschritte, keine impliziten Produktannahmen,
keine Coding-Aktivität ohne bestätigten Wertanker.

## User Confirmation

Confirmed by user: yes — Ben, 2026-06-18.
