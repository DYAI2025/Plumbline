# Product Vision: OpenRouter Council Backend

Status: user-confirmed
Feature-Slug: openrouter-council-backend
Slice: OD-3
Canvas: docs/canvas/openrouter-council-backend.canvas.md

> Confirmed by Ben on 2026-06-18 via the `/agileteam` user-confirmation gate.
> M-B-003 resolved: `COUNCIL_4_MODEL` (4 slots, one per council body).

## Vision Statement

Plumbline soll `/concilium` optional mit echter Modell-Diversität ausführen können.
Council-Rollen sollen über OpenRouter-Modelle konfigurierbar sein, ihre Basis-Prompts
editierbar behalten und fail-closed abbrechen, wenn weniger als zwei unabhängige
Modell-Backends verfügbar sind.

## Target User

- `ASSUMPTION`: Plumbline-User, die Councils mit geringerer Modellkorrelation nutzen wollen.
- `ASSUMPTION`: Maintainer, die Council-Verhalten testbar und transparent halten müssen.
- `ASSUMPTION`: Agenten-Orchestratoren, die Modellslots und Prompts kontrolliert konfigurieren wollen.

## Problem

`EXPLICIT`: Der Council soll die Option auf OpenRouter-Modelle erhalten. Ohne echte
Modell-Diversität kann `/concilium` so wirken, als gäbe es mehrere Perspektiven, obwohl alle
vier Bodies durch dasselbe Modell oder denselben Backend-Pfad laufen.

## Value Proposition

`EXPLICIT`: User können Council-Modelle über `.env` konfigurieren (vier Slots, einer pro
Body), einschließlich möglicher Free-Modelle. Plumbline legt offen, welche Modelle genutzt
wurden, und bricht ab, wenn die Mindestdiversität (≥2 distinkte erreichbare Modell-IDs) nicht
erreicht wird.

## Product Outcome

- `/concilium` unterstützt ein OpenRouter-Backend.
- `OPENROUTER_API_KEY` wird aus `.env` oder Environment gelesen.
- `COUNCIL_1_MODEL` … `COUNCIL_4_MODEL` sind konfigurierbar (1 pro Body).
- Optional werden lowercase Aliase `council_1` … `council_4` akzeptiert.
- Basisprompts der vier Council-Rollen bleiben editierbar (`concilium/*.md`).
- Bei weniger als zwei erreichbaren unabhängigen Modell-IDs wird abgebrochen.
- Reports nennen die tatsächlich verwendeten Modelle.

## Success Signals

- `SS-B-001`: Config-Test liest alle vier Council-Modelle korrekt.
- `SS-B-002`: Secret-Redaction-Test verhindert API-Key-Leakage.
- `SS-B-003`: Fail-closed-Test bricht bei 0 oder 1 erreichbarem Modell ab.
- `SS-B-004`: Positive Fixture mit mindestens 2 Modellen erlaubt Council-Ausführung.
- `SS-B-005`: Council-Report zeigt pro Rolle Modell-ID und Promptquelle.
- `SS-B-006`: `.env.example` dokumentiert alle relevanten Variablen (inkl. Slot 4).

## Non-Goals

- Kein Commit echter API Keys.
- Kein automatisches Kaufen/Verwalten von OpenRouter-Credits.
- Kein Hardcoding dynamischer Free-Modell-Verfügbarkeit als Wahrheit.
- Kein Silent-Fallback auf Claude-only bei Fail-Closed.
- Kein Ersatz aller bestehenden Council-Prompts.

## Strategic Fit

Stärkt Plumbline als wahrheitstreues Orchestrierungssystem: Der Council darf nicht nur
plural aussehen, sondern muss seine Modellbasis offenlegen und bei unzureichender Diversität stoppen.

## User Confirmation

Confirmed by user: yes — Ben, 2026-06-18.
