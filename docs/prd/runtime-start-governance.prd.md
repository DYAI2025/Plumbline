# PRD: Runtime Start Governance

Status: user-confirmed
Feature-Slug: runtime-start-governance
Slice: BL-002 / BL-003
Canvas: docs/canvas/runtime-start-governance.canvas.md
Vision: docs/vision/runtime-start-governance.vision.md

> Confirmed by Ben on 2026-06-18 via the `/agileteam` user-confirmation gate.

## 1. Summary

Dieses Feature bindet die bestehende Start-Klassifikation
(`config/claude/lib/plumbline_start.py`, aufgerufen über den Wrapper
`config/claude/bin/plumbline-start-check`) als **verbindliche Phase-0-Gating-Stufe in den
`/agileteam`-Befehlsfluss** ein und erzeugt eine real-boundary-Trace, die beweist, dass
`/agileteam` bei `VISION_MISSING` VOR Planning/Coding anhält.

**Enforcement-Architektur (User-Entscheidung Ben, 2026-06-18):** Das Gate ist ein
**command-level Gate innerhalb von `/agileteam`** — NICHT SessionStart, NICHT ein
PreToolUse-Hook. Begründung: SessionStart kann `/agileteam`-Planning strukturell nicht
blockieren (es zeigt nur ein Panel; nichts konsumiert das Verdict; `continue:true` kann
die Loop nicht anhalten). Der reale Konsum-/Halte-Punkt ist `/agileteam` selbst.

## 2. Problem Statement

`EXPLICIT`: BL-002 ist offen, weil `VISION_MISSING` sonst nur in Contract-/CLI-Schichten
existiert und kein realer Befehlsfluss das Verdict konsumiert und anhält.
`EXPLICIT`: BL-003 ist offen, weil ein behavioraler real-boundary-Trace nötig ist, der
zeigt, dass `/agileteam` tatsächlich VOR Planning gestoppt hat — nicht nur eine
hand-geschriebene Text-Snapshot (vgl. RISK-A-003).

**Evidenz-Befund (2026-06-18, gegen den realen Classifier verifiziert):** Die
Output-Strings (`Gate:`, `Planning allowed: NO`, `Coding allowed: NO`) und die
Branch-Logik existieren bereits in `plumbline_start.py`. PRD-present + Vision-unconfirmed
liefert `Gate: VISION_MISSING` (Kurzschluss in `plumbline_start.py:25`). Der Classifier
ist reines Python ohne Remote-Flags und läuft daher auch in LOCAL-Sessions.
Der echte Delta ist deshalb: (a) ein **verbindlicher command-level Gate-Schritt in
`/agileteam` Phase 0**, der den Classifier aufruft und bei `VISION_MISSING` Planning/Coding
verweigert; (b) ein behavioraler real-boundary-Trace als Evidence.

## 3. Goals

| ID | Goal | Status |
|---|---|---|
| GOAL-A-001 | `/agileteam` ruft in Phase 0 den Start-Classifier auf und konsumiert dessen Verdict als verbindliche Kontrollfluss-Vorbedingung (command-level Gate). | EXPLICIT |
| GOAL-A-002 | Fehlende bestätigte Vision erzeugt `VISION_MISSING`. | EXPLICIT |
| GOAL-A-003 | `/agileteam` verweigert den Eintritt in Planning/Coding, solange das Gate `VISION_MISSING` ist. | EXPLICIT |
| GOAL-A-004 | Ein behavioraler real-boundary-Trace belegt den Halt VOR Planning. | EXPLICIT |

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
| REQ-A-001 | `/agileteam` MUSS in Phase 0 (vor Planning/Coding) den Start-Classifier via `config/claude/bin/plumbline-start-check` aufrufen und dessen Verdict als **verbindliche Kontrollfluss-Vorbedingung** konsumieren: ist das Gate `VISION_MISSING`, verweigert `/agileteam` den Eintritt in Planning/Coding (command-level Gate, kein bloßer Doku-Hinweis). | SRC-A-001 | MUST |
| REQ-A-002 | Bei PRD-present + Vision-missing muss der Classifier `Gate: VISION_MISSING` liefern. | SRC-A-002 | MUST |
| REQ-A-003 | Bei `VISION_MISSING` muss `Planning allowed: NO` erscheinen, und `/agileteam` darf Planning nicht betreten. | SRC-A-003 | MUST |
| REQ-A-004 | Bei `VISION_MISSING` muss `Coding allowed: NO` erscheinen, und `/agileteam` darf Coding nicht betreten. | SRC-A-003 | MUST |
| REQ-A-005 | Bei `VISION_MISSING` darf `/agileteam` ausschließlich Vision Extraction + explizite User Confirmation als nächsten Schritt anbieten. | SRC-A-004 | MUST |
| REQ-A-006 | Es muss ein behavioraler real-boundary-Trace existieren, der zeigt, dass `/agileteam` bei PRD-present + Vision-missing VOR Planning angehalten hat. | SRC-A-002 | MUST |
| REQ-A-007 | Das command-level Gate muss in LOCAL-Sessions wirken (keine Abhängigkeit von Remote-Only-Flags wie `CLAUDE_CODE_REMOTE`/`AGILETEAM_FORCE_BOOTSTRAP`) und darf nicht als technischer Crash, sondern als steuernder Blocker wirken. | SRC-A-004 | MUST |
| REQ-A-011 | Defense-in-Depth-Backstop (User-Entscheidung Ben, 2026-06-18): Ein **PreToolUse-Hook** MUSS Planning-/Coding-Tool-Dispatch bei `VISION_MISSING` **harness-erzwungen** verweigern (`decision: deny` / non-zero), unabhängig von der Compliance des command-level Gates. Der Hook MUSS normale Sessions ohne `VISION_MISSING` ungehindert durchlassen (fail-open nur für nicht-betroffene Aktionen, fail-closed für die betroffenen). | SRC-A-003 | MUST |

## 6. Non-Functional Requirements

| ID | Requirement | Source | Priority |
|---|---|---|---|
| REQ-A-008 | Die Implementierung darf bestehende Startlogik nicht duplizieren — Reuse `plumbline_start.py` über den Wrapper `config/claude/bin/plumbline-start-check`; keine Neu-Implementierung der Klassifikationslogik in `agileteam.md`. | SRC-A-004 | MUST |
| REQ-A-009 | Die Ausgabe muss deterministisch testbar sein. | SRC-A-005 | MUST |
| REQ-A-010 | Die Evidence muss menschenlesbar und agentenlesbar sein. | SRC-A-005 | SHOULD |

## 7. Acceptance Criteria

### AC-A-001: Missing Vision Gate haltet /agileteam vor Planning
Given eine `/agileteam`-Startanfrage mit vorhandener PRD
And keine bestätigte Product Vision existiert
When `/agileteam` seinen Phase-0-Gate-Schritt durchläuft und `plumbline-start-check` aufruft
Then das Verdict ist `Gate: VISION_MISSING`
And `/agileteam` betritt weder Planning noch Coding, sondern stoppt am Gate

### AC-A-002: Planning Block
Given `/agileteam` hat `Gate: VISION_MISSING` erhalten
When `/agileteam` das Verdict konsumiert
Then die Ausgabe enthält `Planning allowed: NO`
And kein Planning-Schritt wird gestartet

### AC-A-003: Coding Block
Given `/agileteam` hat `Gate: VISION_MISSING` erhalten
When `/agileteam` das Verdict konsumiert
Then die Ausgabe enthält `Coding allowed: NO`
And kein Coding-Schritt wird gestartet

### AC-A-004: Next Allowed Step
Given `Gate: VISION_MISSING`
When `/agileteam` den Statusblock rendert
Then der einzig angebotene nächste Schritt ist Vision Extraction plus explizite User Confirmation

### AC-A-005: Real-Boundary Evidence
Given der command-level Gate-Pfad für PRD-present + Vision-missing
When ein behavioraler real-boundary-Trace des Gate-Pfads erzeugt wird
Then der Trace belegt Gate (`VISION_MISSING`), Blocking (`Planning/Coding allowed: NO`),
das Missing Artifact UND dass `/agileteam` VOR Planning angehalten hat
(Evidence-Klasse `real-boundary-smoke`; eine hand-geschriebene Text-Snapshot ist NICHT hinreichend)

### AC-A-006: PreToolUse Hook Backstop (harness-enforced)
Given `Gate: VISION_MISSING` und ein registrierter PreToolUse-Hook
When ein Planning-/Coding-Tool-Dispatch versucht wird (auch wenn das command-level Gate umgangen würde)
Then der Hook verweigert den Dispatch harness-erzwungen (`decision: deny` / non-zero)
And ein normaler Tool-Dispatch ohne `VISION_MISSING` wird NICHT behindert

## 8. Evidence Requirements

| ID | Evidence | Required For |
|---|---|---|
| EV-A-001 | Testoutput Start-Gate (Classifier-Contract, evidence-class `integration-fake`) | REQ-A-002 bis REQ-A-004 (Output-Strings) |
| EV-A-002 | Behavioraler real-boundary-Trace des `/agileteam`-Gate-Pfads (PRD-present + Vision-missing → HALT vor Planning), abgelegt unter `docs/benchmarks/2026-06-18-runtime-start-governance.md`; evidence-class `real-boundary-smoke` | REQ-A-001, REQ-A-006, REQ-A-007 |
| EV-A-003 | Backlog-Link/Statusupdate | BL-002/BL-003 Closure (NUR gültig, wenn EV-A-002 real-boundary-smoke erreicht) |
| EV-A-004 | Trace-/Command-Ausgabe des Gate-Pfads | AC-A-001 bis AC-A-005 |
| EV-A-005 | PreToolUse-Hook-Test: deny bei `VISION_MISSING`, pass-through sonst (+ Registrierung in settings) | REQ-A-011, AC-A-006 |

**BL-002/BL-003 Closure-Bedingung (F3):** Der Slice schließt NICHT auf der MUST-Liste
allein. Closure ist an EV-A-002 (`real-boundary-smoke`) gebunden — den behavioralen Trace,
der zeigt, dass `/agileteam` VOR Planning angehalten hat. Wird der reale Boundary nicht
erreicht, bleibt der Slice `PASS(tests)/RED(confidence)` und schließt NICHT ohne explizite
User-Reklassifizierung (eine hand-geschriebene Text-Snapshot darf den RED nicht
herunterstufen — vgl. RISK-A-003).

## 9. Risks and Edge Cases

| ID | Edge Case | Expected Behavior |
|---|---|---|
| EDGE-A-001 | PRD fehlt ebenfalls | anderer Gate-Status, nicht `VISION_MISSING` allein |
| EDGE-A-002 | PRD vorhanden + Vision vorhanden, aber NICHT bestätigt | Gate = `VISION_MISSING` (verifiziert: `plumbline_start.py:25` kurzschließt bei `has_prd and not has_confirmed_vision`, unabhängig davon ob ein Vision-Entwurf existiert). `START_ARTIFACTS_MISSING` ist hier NICHT der Branch — diesen erreicht der Classifier erst, wenn Vision BESTÄTIGT ist, aber andere Intake-Artefakte (Canvas/Traceability) fehlen. |
| EDGE-A-003 | PRD + bestätigte Vision, aber Canvas/Traceability fehlen | Gate = `START_ARTIFACTS_MISSING`; Planning/Coding bleiben blockiert (eigener Branch, nicht `VISION_MISSING`). |
| EDGE-A-004 | Start-Classifier nicht ausführbar | Fehler offenlegen, Planning NICHT erlauben (fail-closed) |
| EDGE-A-005 | User versucht Coding trotz Gate | Coding bleibt blockiert |

## 10. Implementation Notes

- Bestehende `plumbline_start.classify_start_state()` / `render_status_panel()` über den
  Wrapper `config/claude/bin/plumbline-start-check` wiederverwenden — NICHT duplizieren.
- **Command-level Gate:** `config/claude/commands/agileteam.md` erhält in Phase 0 einen
  verbindlichen Gate-Schritt, der `plumbline-start-check` aufruft und bei `VISION_MISSING`
  den Eintritt in Planning/Coding verweigert. Dies ist eine **behaviorale** Änderung an
  `agileteam.md`, kein bloßer Doku-Zusatz (vgl. erweitertes Allowed-Change-Scope im Canvas).
- **Zwei-Schichten-Enforcement (Defense-in-Depth, User-Entscheidung Ben 2026-06-18):**
  (1) command-level Gate in `/agileteam` (Orchestrierungs-/UX-Schicht, compliance-abhängig);
  (2) **PreToolUse-Hook als harness-erzwungener Backstop**, der Planning-/Coding-Dispatch
  bei `VISION_MISSING` hart verweigert — überlebt einen nicht-konformen Agenten. Der Hook
  wird in den Settings registriert (analog zur bestehenden Stop-Hook-Registrierung in
  `install.sh`); normale Sessions ohne `VISION_MISSING` bleiben unbehindert.
- NICHT SessionStart: SessionStart kann die `/agileteam`-Loop strukturell nicht anhalten
  (`continue:true` zeigt nur ein Panel). `session-start.sh` bleibt unverändert.
- Muss in LOCAL-Sessions wirken — keine Remote-Only-Flags.
- Falls ein dünner bin/lib-Wrapper für die Gate-Konsumierung nötig ist, ist er erlaubt
  (siehe Allowed-Change-Scope), darf aber keine Klassifikationslogik duplizieren.
- Test zuerst schreiben (TDD).
- Behavioralen real-boundary-Trace als Evidence unter `docs/benchmarks/` speichern.
- Keine User Confirmation simulieren.
- **Reality Ledger:** reiner Lib-/CLI-Test = `integration-fake`; der command-level
  Gate-Halt muss `real-boundary-smoke` erreichen, sonst PASS(tests)/RED(confidence).

## 11. Definition of Done

- Alle MUST-Requirements erfüllt.
- AC-A-001 bis AC-A-005 testbar belegt.
- Behavioraler real-boundary-Trace (EV-A-002, `real-boundary-smoke`) vorhanden, der den
  `/agileteam`-Halt VOR Planning bei `VISION_MISSING` zeigt.
- BL-002/BL-003 schließen NUR mit erreichter `real-boundary-smoke`-Evidence (EV-A-002);
  andernfalls PASS(tests)/RED(confidence) und keine Closure ohne explizite User-Reklassifizierung.
- Backlog/Planstatus für BL-002/BL-003 aktualisiert.
- User Confirmation liegt vor (Ben, 2026-06-18). ✔
