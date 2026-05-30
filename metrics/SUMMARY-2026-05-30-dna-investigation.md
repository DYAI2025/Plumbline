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

Direkt aus dem Befund abgeleitet — Urteils-/Review-/Adversarial-Rollen auf Opus 4.8
(dort entscheidet Fähigkeit, nicht Prompt), Generierungs-/Kuratierungs-Rollen auf
Sonnet 4.6. Gesetzt als `model:`-Frontmatter in der jeweiligen Agent-Datei.

| Rolle | Datei | Modell |
|---|---|---|
| tester (QA) | `core/tester.md` | **opus** |
| code-reviewer | `code-reviewer.md` | **opus** |
| spec-auditor | `agileteam/spec-auditor.md` | **opus** |
| security-reviewer | `agileteam/security-reviewer.md` | **opus** |
| product-owner | `agileteam/product-owner.md` | **opus** |
| coder | `core/coder.md` | sonnet |
| requirements-analyst | `agileteam/requirements-analyst.md` | sonnet |
| planner | `core/planner.md` | sonnet |
| context-keeper | `agileteam/context-keeper.md` | sonnet |
| production-validator | `testing/validation/production-validator.md` | sonnet |
| retro-analyst | `agileteam/retro-analyst.md` | sonnet |

### Wie `/model` damit zusammenspielt (Override-Mechanik)
Auflösungs-Reihenfolge bei einem Subagenten (laut Tool-Doku, höchste zuerst):
1. **Expliziter `model`-Parameter** beim Spawn (der Orchestrator setzt hier keinen —
   `agileteam.md` hardcodet kein Modell, geprüft).
2. **`model:`-Frontmatter** der Agent-Datei → das sind diese Pins.
3. **Vererbung vom Eltern-/Session-Modell** (das, was `/model` setzt) — greift nur,
   wenn 1 und 2 fehlen bzw. `model: inherit` steht.

Konsequenz: **Ein explizites `model:` (wie hier) gewinnt gegen `/model`.** Setzt der
User `/model haiku`, laufen die gepinnten Rollen weiter auf opus/sonnet — `/model`
steuert nur die Haupt-Session und alle `inherit`-Rollen. Das ist die **harte** Variante:
QA/Review bekommen immer Opus, auch in einer billigen Session. Wer einen ganzen Lauf
auf ein Tier zwingen will, muss die Frontmatter ändern (oder der Orchestrator müsste
einen expliziten Override durchreichen).

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
