# Product Canvas: OpenRouter Council Backend

Status: user-confirmed
Owner: requirements-analyst
Confirmed by user: yes
Canvas file: docs/canvas/openrouter-council-backend.canvas.md
Feature-Slug: openrouter-council-backend
Slice: OD-3

> Confirmed by Ben on 2026-06-18 via the `/agileteam` user-confirmation gate
> ("Beide Slices bestätigen"). M-B-003 resolved by user: add `COUNCIL_4_MODEL`
> (one slot per body, 4 slots). No agent self-confirmed this canvas.

## 1. Problem

| ID | Feld | Inhalt | Status |
|---|---|---|---|
| CAN-B-001 | Problem | `/concilium` braucht Option auf echte Modell-Diversität über OpenRouter. | EXPLICIT |
| CAN-B-002 | Auswirkung | Ohne Diversitätsprüfung kann ein Council plural wirken, obwohl er nur ein Modell-/Backend-Muster nutzt. | ASSUMPTION |
| CAN-B-003 | Dringlichkeit | Hoch, weil Council-Ausgaben als Beratungs-/Prüfperspektiven genutzt werden. | ASSUMPTION |

## 2. Zielnutzer

| ID | Nutzergruppe | Bedürfnis | Status |
|---|---|---|---|
| CAN-B-004 | Plumbline-User | Konfigurierbare Council-Modelle nutzen. | ASSUMPTION |
| CAN-B-005 | Maintainer | Sicherstellen, dass keine Schein-Diversität entsteht. | ASSUMPTION |
| CAN-B-006 | Reviewer | Modell-, Prompt- und Backend-Evidence prüfen. | ASSUMPTION |

## 3. Current workaround

`/concilium` läuft heute Claude-only über vier Body-Prompts
(`concilium/{market-realist,tech-arbiter,skeptic,distribution-realist}.md`, Command
`config/claude/commands/concilium.md`). Es gibt keine konfigurierbaren externen Modelle
und keine Diversitäts-Prüfung — alle vier Bodies können faktisch durch dasselbe Modell laufen.

## 4. Value Proposition

| ID | Aussage | Status |
|---|---|---|
| CAN-B-007 | Council-Rollen können über OpenRouter-Modelle laufen. | EXPLICIT |
| CAN-B-008 | Mindestens zwei unabhängige erreichbare Modell-IDs sind Pflicht. | EXPLICIT |
| CAN-B-009 | Prompts bleiben editierbar und damit auditierbar. | EXPLICIT |
| CAN-B-010 | Free-Modelle sind optional nutzbar, aber nicht als stabile Wahrheit hart verdrahtet. | ASSUMPTION |

## 5. Lösungsskizze

| ID | Baustein | Beschreibung | Status |
|---|---|---|---|
| CAN-B-011 | OpenRouter Config | `.env` enthält API-Key und Council-Modelle. | EXPLICIT |
| CAN-B-012 | Model Slots | `COUNCIL_1..4_MODEL` (ein Slot pro Body); optional lowercase Aliase. | EXPLICIT (M-B-003 resolved) |
| CAN-B-013 | Prompt Loader | Council-Basisprompts werden aus `concilium/*.md` geladen. | EXPLICIT |
| CAN-B-014 | Diversity Gate | `<2` erreichbare unabhängige Modelle führt zu fail-closed. | EXPLICIT |
| CAN-B-015 | Report Disclosure | Report nennt genutzte Modelle und Promptquellen. | ASSUMPTION |
| CAN-B-016 | Fake Transport Tests | Tests laufen ohne Netzwerk und ohne echten Key. | ASSUMPTION |

## 6. Core use case

Ein User konfiguriert in `.env` vier OpenRouter-Modelle (`COUNCIL_1..4_MODEL`) plus
`OPENROUTER_API_KEY`. `/concilium` validiert Erreichbarkeit; bei ≥2 distinkten erreichbaren
Modell-IDs läuft der Council und der Report nennt pro Body Modell-ID + Promptquelle. Bei <2
bricht er fail-closed mit `COUNCIL_DIVERSITY_UNAVAILABLE` ab — kein stiller Claude-Fallback.

## 7. Non-Goals

- Kein Commit echter API Keys.
- Kein automatisches Kaufen/Verwalten von OpenRouter-Credits.
- Kein Hardcoding dynamischer Free-Modell-Verfügbarkeit als Wahrheit.
- Kein Silent-Fallback auf Claude-only bei Fail-Closed.
- Kein Ersatz aller bestehenden Council-Prompts.

## 8. Risks / contradictions

| ID | Risiko | W'keit | Impact | Mitigation | Status |
|---|---|---:|---:|---|---|
| RISK-B-001 | API-Key landet in Logs | mittel | hoch | Redaction-Test, keine Raw-Env-Ausgabe | CONFIRMED |
| RISK-B-002 | Free-Modell nicht verfügbar | hoch | mittel | Verfügbarkeit prüfen, keine feste Free-Liste | CONFIRMED |
| RISK-B-003 | Zwei Rollen nutzen dasselbe Modell | mittel | hoch | Unique-Modell-ID-Gate | CONFIRMED |
| RISK-B-004 | OpenRouter nicht erreichbar | mittel | mittel | Fail-closed mit klarer Meldung | CONFIRMED |
| RISK-B-005 | Silent-Fallback erzeugt Schein-Diversität | mittel | hoch | Fallback nur bei expliziter User-Konfiguration + Disclosure | CONFIRMED |
| RISK-B-006 | Prompt-Drift durch Duplikate | mittel | mittel | `concilium/*.md` als Source of Truth | CONFIRMED |

## 9. Evidence needed

- Config-Loader-Test (4 Slots, Alias, Precedence), Fail-Closed-Test, Redaction-Test,
  Prompt-Loader-Test, Model-Disclosure-Test, `.env.example`-Review — alle grün, ohne Netzwerk/echten Key.
- **Reality Ledger:** Unit-/Fake-Transport-Tests = `integration-fake`. Echte OpenRouter-Erreichbarkeit
  bleibt `*-fake` bis ein optionaler Real-Boundary-Smoke (außerhalb Repo/Tests, ohne Key-Leak) läuft →
  bis dahin PASS(tests)/RED(confidence) für den „echte Diversität"-Claim.

## Allowed change scope

> Vorgeschlagen vom Orchestrator, geerdet am Repo. Final-OK durch den User am Pre-Build-Gate.

- `config/claude/lib/` (neues Council-Backend-Modul, z.B. `council_backend.py`)
- `config/claude/commands/concilium.md` (Backend-Wiring + Doku)
- `concilium/*.md` (nur als Read-Source; Prompts bleiben Source of Truth)
- `config/claude/tests/` (neue Council-Backend-Tests)
- `.env.example` (Council-/OpenRouter-Variablen)
- `docs/canvas/openrouter-council-backend.canvas.md`, `docs/vision/…`, `docs/prd/…`, `docs/traceability.md`

Status: user-confirmed (Scope-Detail-OK ausstehend)

## 10. Traceability links

PRD: docs/prd/openrouter-council-backend.prd.md
Product Vision: docs/vision/openrouter-council-backend.vision.md
Traceability Matrix: docs/traceability.md
Related REQ IDs: REQ-B-001 … REQ-B-020 (+ REQ-B-006b für Slot 4)
True-Line status: pass

## Open Questions (resolved at confirmation)

| ID | Frage | Auflösung |
|---|---|---|
| OQ-B-001 | lowercase `council_1..4` Aliase oder canonical? | Aliase; canonical = uppercase. |
| OQ-B-002 / M-B-003 | 4 Bodies auf 3 Slots? | **`COUNCIL_4_MODEL` ergänzen → 4 Slots, 1 pro Body** (User-Entscheidung). |
| OQ-B-003 | canonical Prompt-Pfad? | `concilium/{market-realist,tech-arbiter,skeptic,distribution-realist}.md`. |
| OQ-B-004 | `openrouter/free` als schwächerer Diversity-Modus? | Erlaubt, aber zur Implementierungszeit gegen OpenRouter prüfen; nicht als Wahrheit hardcoden. |

## User confirmation

Confirmed by user: yes
Confirmation date: 2026-06-18
Confirmation note: Ben bestätigte beide Slices; M-B-003 → COUNCIL_4_MODEL (4 Slots).
