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
heute primär „behauptet", nicht im realen Befehlsfluss konsumiert. Kein realer Pfad
konsumiert das Verdict und hält an.

## 4. Value Proposition

| ID | Aussage | Status |
|---|---|---|
| CAN-A-007 | Runtime Start Governance verhindert, dass `/agileteam` auf unbestätigter Produktbasis plant oder codet. | EXPLICIT |
| CAN-A-008 | Dry-Run-Evidence macht die Governance prüfbar. | EXPLICIT |
| CAN-A-009 | Die Funktion stärkt Plumbline gegen Statusdrift und Scheinreife. | ASSUMPTION |

## 5. Lösungsskizze

| ID | Baustein | Beschreibung | Status |
|---|---|---|---|
| CAN-A-010 | Command-level Start Gate | Bestehende `plumbline_start`-Klassifikation wird über `config/claude/bin/plumbline-start-check` als verbindlicher Phase-0-Gate-Schritt in `/agileteam` aufgerufen; das Verdict wird als Kontrollfluss-Vorbedingung konsumiert (NICHT SessionStart, NICHT PreToolUse). | EXPLICIT |
| CAN-A-011 | Status Panel | `render_status_panel()` zeigt Gate, fehlende Artefakte und erlaubte nächste Schritte. | EXPLICIT (existiert) |
| CAN-A-012 | Blocking Semantics | `/agileteam` betritt bei `VISION_MISSING` weder Planning noch Coding. | EXPLICIT |
| CAN-A-013 | Real-Boundary Evidence | Behavioraler real-boundary-Trace belegt, dass `/agileteam` bei PRD-present + Vision-missing VOR Planning gestoppt hat. | EXPLICIT |
| CAN-A-014 | PreToolUse-Hook-Backstop | Harness-erzwungener Hook verweigert Planning-/Coding-Dispatch bei `VISION_MISSING` unabhängig von der Compliance des command-level Gates (Defense-in-Depth). | EXPLICIT (Ben 2026-06-18) |

## 6. Core use case

Ein User ruft `/agileteam` mit vorhandener PRD, aber ohne bestätigte Product Vision auf.
`/agileteam` ruft in Phase 0 `plumbline-start-check` auf, erhält `Gate: VISION_MISSING`,
zeigt `Planning allowed: NO`, `Coding allowed: NO` plus den einzig erlaubten nächsten
Schritt (Vision Extraction + explizite User Confirmation) und **betritt Planning/Coding
nicht**. Ein behavioraler real-boundary-Trace friert genau diesen Halt als Evidence ein.

## 7. Non-Goals

- Kein vollständiger Umbau der `/agileteam`-Pipeline (nur der Phase-0-Gate-Schritt wird hinzugefügt).
- Kein neues Product-Vision-Format.
- Kein fataler Crash bei fehlender Vision (das Gate ist steuernd, nicht abstürzend).
- Kein SessionStart-Enforcement (strukturell nicht halt-fähig — verworfen). Der PreToolUse-Hook ist hingegen IM Scope als harness-erzwungener Backstop (Ben 2026-06-18).
- Kein automatisches Simulieren der User Confirmation.
- Kein Claim von Production-Readiness ohne echte Runtime-/Boundary-Evidenz.

## 8. Risks / contradictions

| ID | Risiko | W'keit | Impact | Mitigation | Status |
|---|---|---:|---:|---|---|
| RISK-A-001 | Startlogik wird dupliziert statt wiederverwendet | mittel | hoch | `plumbline_start.py` als Source of Truth nutzen | CONFIRMED |
| RISK-A-002 | Gate wird fatal statt steuernd | mittel | mittel | Gate konsumiert das Verdict steuernd; verweigert Planning/Coding ohne technischen Crash | CONFIRMED |
| RISK-A-003 | Evidence belegt nur Text, nicht den realen Gate-Halt | mittel | hoch | Evidence MUSS behavioraler real-boundary-Trace des `/agileteam`-Gate-Pfads sein (HALT vor Planning); eine hand-geschriebene Snapshot ist NICHT hinreichend und darf den RED nicht herunterstufen | CONFIRMED |
| RISK-A-004 | User Confirmation wird implizit simuliert | niedrig | hoch | Confirmation nur als User-Block, nie automatisch setzen | CONFIRMED |

## 9. Evidence needed

- Testoutput Start-Gate (Classifier-Contract, REQ-A-002..004) — grün, `integration-fake`.
- Behavioraler real-boundary-Trace des `/agileteam`-Gate-Pfads mit `Gate: VISION_MISSING`,
  `Planning allowed: NO`, `Coding allowed: NO` UND nachweisbarem HALT vor Planning.
- Reality-Ledger-Klasse: Ziel `real-boundary-smoke` für den command-level Gate-Halt;
  reiner Lib-/CLI-Test bleibt `integration-fake` und ist für den Runtime-/Halt-Claim NICHT hinreichend.

## Allowed change scope

> Vorgeschlagen vom Orchestrator, geerdet am Repo. Final-OK durch den User am Pre-Build-Gate.

**Machine-parseable scope (PRIL `plumbline-scope-check`).** Clean one-path-per-line mirror of
the confirmed prose below, so the runtime scope guard can parse it (the prose bullets carry
inline descriptions the parser cannot read):

- `backlog.md`
- `.gitignore`
- `CLAUDE.md`
- `config/claude/commands/agileteam.md`
- `config/claude/install.sh`
- `config/claude/hooks/pretool-vision-gate.sh`
- `config/claude/tests/run_all.sh`
- `config/claude/tests/test_pretool_vision_gate_hook.sh`
- `config/claude/tests/test_runtime_start_governance_gate.sh`
- `config/claude/tests/test_agileteam_start_gate.sh`
- `docs/benchmarks/2026-06-18-runtime-start-governance.md`
- `docs/canvas/runtime-start-governance.canvas.md`
- `docs/prd/runtime-start-governance.prd.md`
- `docs/vision/runtime-start-governance.vision.md`
- `docs/traceability.md`
- `docs/plans/2026-06-18-runtime-start-governance.md`

Co-located sibling-feature intake — confirmed present on this shared intake branch (commit
`babd9e8`, Paket B OpenRouter Council Backend), **NOT modified by this build**; listed only so
the branch-spanning scope guard (`merge-base…HEAD`) does not misread pre-existing sibling
artifacts as out-of-scope edits:

- `docs/canvas/openrouter-council-backend.canvas.md`
- `docs/prd/openrouter-council-backend.prd.md`
- `docs/vision/openrouter-council-backend.vision.md`

- `config/claude/commands/agileteam.md` — **behaviorale Änderung erlaubt**: Hinzufügen
  eines verbindlichen Phase-0 command-level Gate-Schritts, der `plumbline-start-check`
  aufruft und bei `VISION_MISSING` den Eintritt in Planning/Coding verweigert. (Erweitert
  gegenüber dem ursprünglichen „nur Doku" — User-Entscheidung Ben, 2026-06-18.)
- `config/claude/bin/` und `config/claude/lib/` — Reuse von `plumbline_start.py` via dem
  bereits existierenden `config/claude/bin/plumbline-start-check`; KEINE Duplizierung der
  Klassifikationslogik. (Kein neuer Wrapper nötig — `plumbline-start-check` existiert.)
- `config/claude/hooks/` — **neuer PreToolUse-Hook** (Backstop, Ben 2026-06-18), plus
  dessen Registrierung in den Settings (analog Stop-Hook in `install.sh`).
- `config/claude/install.sh` — nur Hook-Registrierung (idempotent), falls dort verankert.
- `config/claude/tests/test_agileteam_start_gate.sh`
- `config/claude/tests/` (neue Tests: command-level Gate-Halt + PreToolUse-Hook deny/pass-through)
- `docs/benchmarks/2026-06-18-runtime-start-governance.md` (behavioraler real-boundary-Trace)
- `docs/canvas/runtime-start-governance.canvas.md`, `docs/vision/…`, `docs/prd/…`, `docs/traceability.md`
- `backlog.md` (BL-002/BL-003 Closure)

NICHT im Scope (bewusst eng gehalten):
- `config/claude/hooks/session-start.sh` — bleibt unverändert (SessionStart-Enforcement verworfen).
- `config/claude/lib/plumbline_start.py` — Klassifikationslogik bleibt unverändert (Reuse, keine Änderung).

Status: user-confirmed — Architektur (command-level Gate + PreToolUse-Hook-Backstop) UND
Scope-Detail (behaviorale `agileteam.md`-Änderung + neuer Hook + Settings-Registrierung)
am Pre-Build-USER-GATE bestätigt (Ben, 2026-06-18).

## 10. Traceability links

PRD: docs/prd/runtime-start-governance.prd.md
Product Vision: docs/vision/runtime-start-governance.vision.md
Traceability Matrix: docs/traceability.md
Related REQ IDs: REQ-A-001 … REQ-A-011
True-Line status: pass

## Open Questions (resolved at confirmation)

| ID | Frage | Auflösung |
|---|---|---|
| OQ-A-001 | Dry-Run unter `docs/evidence/` oder `docs/benchmarks/`? | `docs/benchmarks/` — Repo-Konvention (datierte Dateien); `docs/evidence/` existiert nicht. |
| OQ-A-002 | Welcher Command gilt als runtime-nah? | RESOLVED (Ben, 2026-06-18): command-level Gate INNERHALB von `/agileteam` Phase 0 (NICHT SessionStart, NICHT PreToolUse), das `plumbline-start-check` aufruft und das Verdict als Kontrollfluss-Vorbedingung konsumiert. Spec-sanity-Finding F1: SessionStart kann die Loop strukturell nicht anhalten. |

## User confirmation

Confirmed by user: yes
Confirmation date: 2026-06-18
Confirmation note: Ben bestätigte beide Slices über den /agileteam-Confirmation-Gate.
