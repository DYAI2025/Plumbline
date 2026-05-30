# Untersuchung: Bringt die QA-DNA ("kritische semantische Glättung") etwas?

**Zeitraum:** 2026-05-29/30 · **Frage:** Macht die neue Test-Agenten-DNA die Tests
wirklich besser, oder fühlt es sich nur so an? · **Stand:** abgeschlossen.

## Auslöser
Realer Vorfall: die GBrain-Anbindung war ein No-Op (`client.add` existierte gar nicht),
Tests waren grün, niemand merkte es. Lektion: **"Tests grün ≠ funktioniert."** Daraus
bauten wir dem Test-Agenten eine Denk-Disziplin ein, die genau diese Lücke fangen soll
(Realitäts-Beleg-Klassen, "ist es in Produktion verdrahtet?", Real-Boundary statt Fake).

## Methode (fälschungssicher, kein Bauchgefühl)
Zwei Agenten-Versionen — **alt (ohne DNA)** vs. **neu (mit DNA)** — bekommen dieselbe
Aufgabe und schreiben Tests. Dann **sabotiert ein Skript heimlich den Code** (Mutations-
Orakel) und zählt: Test rot = Fehler gefangen, Test grün = durchgerutscht. Gemessen über
**zwei Modell-Stärken** (Haiku = Boden, Opus = Decke), je 3 Wiederholungen, Coder-Prompt
in beiden Armen identisch, dunkle Zone nie im Spec benannt.

## Was gemessen wurde

| Instrument | sabotiert | Ergebnis |
|---|---|---|
| **bench-core-v1** | Test-PLAN (nur Denken: welche Tests bräuchte man?) | **DNA klar besser: 5× Recall bei gleicher Treffsicherheit** |
| **pipe-core-v1** | lokale Logik im gebauten Code | kein Unterschied (beide Arme fangen es) |
| **pipe-nonlocal-v1** | Verdrahtung / echte Boundary (Realität = einziger Testpfad) | kein Unterschied (beide fangen es) |
| **pipe-providedfake-v1** | echte Boundary, *Fake liegt schon bequem da* (wie GBrain) | **Differential — aber auf Modell-Achse, nicht DNA-Achse** |

Der vierte Aufbau war der entscheidende, weil er den echten GBrain-Fall nachstellt:
fertiger Fake + Starter-Test, das Echte zu testen ist Mehrarbeit. Resultat:

|        | ohne DNA | mit DNA |
|--------|----------|---------|
| Haiku  | 3/3 durchgerutscht | **3/3 durchgerutscht** |
| Opus   | 0/3 (alles gefangen) | 0/3 (alles gefangen) |

## Die eine echte Erkenntnis
**Ob die Realität getestet wird, entscheidet die Modell-Stärke — nicht der Prompt.**
- Opus fasst die echte Boundary von allein an (auch *ohne* DNA) → fängt den Fehler immer.
- Haiku bleibt beim bequemen Fake (auch *mit* DNA) → verschläft den Fehler immer.
- Die DNA schließt diese Lücke beim schwachen Modell **nicht**. Ein stärkerer Prompt
  kann einem schwächeren Modell die Fähigkeit nicht aufzwingen.

**Belegter DNA-Nutzen:** beim **Test-Planen** (das Denken ist dort das Produkt). Beim
tatsächlichen Bauen ist sie **präzisions-sicher, aber ergebnis-neutral** — schadet nie
(0 Regressionen, 0 Fehlalarme über alle Läufe), verändert aber die gefangenen Fehler nicht.

## Konsequenz
1. **DNA bleibt deployed** — gratis Gewinn beim Planen, kein Risiko.
2. **Echter Hebel gegen den GBrain-Fehlertyp: das QA-Modell-Tier hochziehen**
   (Tester auf Opus laufen lassen), *nicht* den Prompt verstärken.
3. **Nicht behaupten**, die DNA schließe die Fake-Boundary-Lücke auf schwachen Modellen —
   gemessen: tut sie nicht.

## Umgesetzte Modell-Belegung der /agileteam-Rollen (2026-05-30)

Direkt aus dem Befund abgeleitet, gesetzt als `model:`-Frontmatter in der jeweiligen
Agent-Datei. Gewählt: **Hybrid** — alle Urteils-/Review-/Adversarial-Gates werden hart
auf Opus gepinnt; die Generierungs-/Kuratierungs-Rollen folgen `/model`
(`model: inherit`) mit dokumentierter Empfehlung.

| Rolle | Datei | Modell | Durchsetzung |
|---|---|---|---|
| tester (QA) | `core/tester.md` | **opus** | **hart gepinnt** |
| code-reviewer | `code-reviewer.md` | **opus** | **hart gepinnt** |
| security-reviewer | `agileteam/security-reviewer.md` | **opus** | **hart gepinnt** |
| spec-auditor | `agileteam/spec-auditor.md` | **opus** | **hart gepinnt** |
| product-owner | `agileteam/product-owner.md` | **opus** | **hart gepinnt** |
| coder | `core/coder.md` | inherit | Empfehlung: Sonnet |
| requirements-analyst | `agileteam/requirements-analyst.md` | inherit | Empfehlung: Sonnet |
| planner | `core/planner.md` | inherit | Empfehlung: Sonnet |
| context-keeper | `agileteam/context-keeper.md` | inherit | Empfehlung: Sonnet |
| production-validator | `testing/validation/production-validator.md` | inherit | Empfehlung: Sonnet |
| retro-analyst | `agileteam/retro-analyst.md` | inherit | Empfehlung: Sonnet |

Begründung: Der GBrain-Fehlertyp wird *nur* von einem starken Modell gefangen, und das
betrifft alle prüfenden Gates (QA, Review, Security, Spec-Audit, Urteil). Würden sie
`inherit` sein, verlöre ein versehentliches `/model haiku` diesen Schutz still. Deshalb
sind die **5 Gates hart auf Opus**; die generierenden Rollen (coder/planner/etc.) dürfen
`/model` folgen.

### Wie `/model` damit zusammenspielt (Override-Mechanik)
Auflösungs-Reihenfolge bei einem Subagenten (laut Tool-Doku, höchste zuerst):
1. **Expliziter `model`-Parameter** beim Spawn (der Orchestrator setzt hier keinen —
   `agileteam.md` hardcodet kein Modell, geprüft).
2. **`model:`-Frontmatter** der Agent-Datei → bei den 5 harten Rollen = `opus`.
3. **Vererbung vom Eltern-/Session-Modell** (das, was `/model` setzt) — greift bei
   allen `inherit`-Rollen.

Konsequenz: `/model haiku` zieht **6 der 11 Rollen** auf Haiku, aber **tester,
code-reviewer, security-reviewer, spec-auditor und product-owner bleiben Opus**. Wer
auch diese fünf umstellen will, muss bewusst ihr Frontmatter ändern.

### Bekommt der User eine Warnung, bevor `/model` greift?
**Nein.** `/model` ist nur ein Session-Schalter — es gibt **keine eingebaute Warnung**,
dass dabei hart gepinnte Rollen unberührt bleiben (oder, bei Variante B, mit umgestellt
würden). Die Frontmatter-Auflösung passiert still beim Spawn jedes Subagenten; es gibt
keinen Bestätigungs-Dialog und kein „model syncing"-Vorab-Hinweis. Bei Variante C ist
das unkritisch (die Schutz-Gates ignorieren `/model` ohnehin), aber transparent machen
lässt sich's nur über Doku oder einen optionalen Orchestrator-Hinweis zu Lauf-Beginn
(„QA/Review laufen fix auf Opus, übrige Rollen auf <Session-Modell>").

> ⚠ Verifikations-Caveat: Die Reihenfolge entspricht der dokumentierten Tool-Semantik;
> dass deine konkrete Claude-Code-Version das `model:`-Frontmatter pro Subagent beim
> `/agileteam`-Lauf tatsächlich anwendet, ist noch nicht im Live-Lauf bestätigt.

## Methoden-Disziplin (Selbstkorrektur, transparent)
Das Instrument fing mehrfach **eigene** Fehler: ein Regex-Bug im Sabotage-Skript (falscher
"durchgerutscht"-Befund), vier "Leaks", bei denen Spec/Code/Docstrings die dunkle Zone
selbst verrieten (de-leaked und neu gefahren), und ein Lauf, bei dem die DNA-Datei
versehentlich fehlte (verworfen, sauber wiederholt). Jeder dieser Fälle ist in den
Einzel-Reports offen dokumentiert statt geglättet.

*Detail-Reports: `metrics/bench-2026-05-29-*.md` · Korpora: `metrics/corpus/{bench-core-v1,pipe-core-v1,pipe-nonlocal-v1,pipe-providedfake-v1}/`*
