---
name: konfabulations-audit
description: Checks every external claim for evidence before the final answer and classifies it as supported, inferable, unverified, or do-not-claim. Companion to ultrathink-craftsmanship. Use when stating releases, APIs, prices, benchmarks, studies, product behavior, legal/medical/financial facts, claims about foreign codebases/files/org knowledge, or any numbers, names, dates, versions, quotes — and before any autonomous agent flow adopts a claim that could propagate.
---

# Konfabulations-Audit

Version: 1.0
Companion zu: `ultrathink-craftsmanship` (Phase 5)

## Zweck

Verhindere, dass unbelegte Behauptungen ("Konfabulationen") in eine Antwort, ein
Artefakt oder — besonders kritisch — in einen autonomen Agenten-Ablauf gelangen,
wo sie sich vervielfältigen und zur stillen Prämisse werden.

Das Audit ist ein **Verifikations-Gate für Claims**, kein Stil- oder Reasoning-Gate.
Es entscheidet pro Behauptung: behaupten (mit Beleg), abschwächen oder streichen.

## Grundsatz (nicht verhandelbar)

> Eine fehlende Information wird **niemals** "logisch" selbst geschlossen.
> Sie wird als Lücke markiert und — je nach Kontext — durch Quelle belegt,
> transparent als ungeprüft gekennzeichnet oder gar nicht behauptet.
> Das Schließen einer Wissenslücke durch plausibles Raten ist die Konfabulation,
> die dieser Skill abfängt.

## Wann verwenden

Aktiviere, sobald die Antwort eine **externe Behauptung** enthalten würde:

- aktuelle Releases, Versionen, APIs, Preise, Limits, Benchmarks, Studien
- Produkt-/Systemverhalten, das nicht direkt beobachtet wurde
- rechtliche, medizinische, finanzielle, regulatorische Fakten
- Aussagen über fremde Codebasen, Dateien, Dokumente oder Organisationswissen
  ohne tatsächlich gelesene Quelle
- jede konkrete Zahl, jeder Name, jedes Datum, jede Version, jedes Zitat

Nicht nötig bei rein internem Reasoning, eigener Meinung (als solche markiert),
oder Inhalten, die vollständig aus dem bereitgestellten Kontext ableitbar sind
(dann Status `ableitbar` mit Verweis).

## Klassifikation (die vier Marken)

| Marke | Bedeutung | Handlung |
|---|---|---|
| `belegt` | durch geprüfte Quelle / gelesene Datei / Tool-Ergebnis gedeckt | behaupten **mit** Quellenangabe |
| `ableitbar` | folgt zwingend aus bereitgestelltem Kontext/Daten | behaupten **mit** Verweis auf die Basis |
| `ungeprüft` | plausibel, aber ohne Beleg | abschwächen ("möglicherweise", "bitte prüfen") **oder** verifizieren |
| `nicht behaupten` | nicht verifizierbar / sicherheits-/faktenkritisch ohne Quelle | **streichen**; stattdessen Lücke benennen |

Entscheidungsregel: Im Zweifel runterstufen. `ungeprüft` ist nie eine Grundlage
für eine definitive Aussage oder für eine Annahme im autonomen Ablauf.

## Workflow

### Schritt 1 — Claims extrahieren
Liste jede atomare externe Behauptung im Entwurf. Eine Behauptung = eine prüfbare
Aussage. Zerlege Sammelaussagen ("X ist schneller und billiger" → zwei Claims).

### Schritt 2 — Belegquelle bestimmen
Für jeden Claim die *tatsächliche* Quelle benennen:
- gelesene Datei / Tool-Ergebnis / Suchergebnis mit URL → Kandidat `belegt`
- bereitgestellter Kontext, aus dem es zwingend folgt → `ableitbar`
- nur Trainingswissen / Erinnerung / Plausibilität → `ungeprüft` oder `nicht behaupten`

Trainingswissen über veränderliche Fakten (Preise, Releases, Amtsinhaber, Versionen)
ist **nie** automatisch `belegt`. Wenn ein Verifikationswerkzeug verfügbar ist
(Web-Suche, Doku-Tool, Datei lesen), nutze es, bevor du `belegt` vergibst.

### Schritt 3 — Verifizieren oder herabstufen
- `belegt`/`ableitbar` behalten, Quelle dranschreiben.
- `ungeprüft`: entweder jetzt verifizieren (→ `belegt`) oder im Text sichtbar
  abschwächen.
- `nicht behaupten`: aus der Antwort entfernen; an die Stelle tritt eine
  **explizite Lücke** (siehe Schritt 4).

### Schritt 4 — Lücken benennen statt füllen
Für jede entfernte/unhaltbare Behauptung: benenne die offene Frage präzise.
Im Spec-/Anforderungskontext gilt zwingend: Lücke an den **Menschen** zurückgeben
(gezieltes Nachfragen, z.B. via `brainstorming`), nicht selbst entscheiden.

### Schritt 5 — Audit ausgeben
Gib vor der finalen Antwort die Audit-Tabelle aus (siehe Ausgabeformat).
Bei Kopplung an `ultrathink-craftsmanship`: dies erfüllt dessen Phase 5.

## Ausgabeformat

```text
## Konfabulations-Audit
| # | Claim | Quelle | Marke | Handlung |
|---|-------|--------|-------|----------|
| 1 | ...   | ...    | belegt/ableitbar/ungeprüft/nicht behaupten | behalten/abschwächen/streichen |

Offene Lücken (nicht selbst zu schließen):
- [Frage 1 → an User / via brainstorming]
```

Im Kurzmodus genügt eine Claim-Liste mit Marken, wenn keine kritischen Claims
vorliegen.

## Eskalation in autonomen Abläufen

Wenn dieses Audit innerhalb eines Agenten-Workflows (z.B. /agileteam) läuft:

- **Kein** `ungeprüft`- oder `nicht behaupten`-Claim darf als Prämisse in eine
  spätere Phase übernommen werden.
- Tritt ein solcher Claim an einem Anforderungs-/Spec-Punkt auf → **BLOCKER**:
  Ablauf anhalten, Lücke per Nachfrage am Menschen schließen.
- Genau **ein** Remediation-Pass; das Audit selbst wird nicht endlos wiederholt.

## Common Mistakes

| Fehler | Korrektur |
|---|---|
| Trainingswissen zu veränderlichen Fakten als `belegt` führen | herabstufen, verifizieren oder als ungeprüft kennzeichnen |
| Lücke "logisch" selbst schließen | Lücke benennen, an Menschen zurückgeben |
| Sammelaussagen als einen Claim prüfen | in atomare Claims zerlegen |
| `ungeprüft` als definitive Aussage stehen lassen | abschwächen oder streichen |
| Audit nach der Antwort liefern | Audit läuft VOR der finalen Antwort |
