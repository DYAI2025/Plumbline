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

**Nachtrag 2026-05-30 — Sonnet 4.6 nachgemessen (die fehlende Mitte):** 3 Läufe auf
derselben P1-Falle, Tester-DNA via explizitem `model`-Parameter erzwungen → **3/3
durchgerutscht, wie Haiku.** Die Grenze ist also **Opus vs. der Rest**, nicht "Haiku vs.
Rest". Sonnet ist ein vernünftiges Coding-Modell, greift hier aber still daneben.

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

## Modell-Policy der /agileteam-Rollen (2026-05-30, verifiziert)

### Verifizierter Mechanismus (Subagent-Logs, nicht Selbstauskunft)
Quelle: `…/<session>/subagents/agent-<id>.jsonl` — jeder Subagent loggt sein
tatsächlich genutztes Modell. Drei kontrollierte Probes:

| Test | erwartet (wenn Frontmatter wirkt) | tatsächlich geloggt | Schluss |
|---|---|---|---|
| 11 Rollen, Session=Opus | alle Opus | alle `claude-opus-4-8` | nicht unterscheidend |
| `retro-analyst` **Frontmatter** `model: haiku` | haiku | `claude-opus-4-8` | ❌ Frontmatter ignoriert |
| `general-purpose` **expliziter** `model: haiku` | haiku | `claude-haiku-4-5` | ✅ greift |

**Befund: Das `model:`-Frontmatter wird von dieser Claude-Code-Version NICHT angewandt.**
Subagenten laufen auf dem **Session-Modell** (`/model`). Der einzige wirksame Hebel ist
der **explizite `model`-Parameter beim Dispatch** — den setzt nur der Orchestrator.
Konsequenz: Frontmatter-Pins sind wirkungslos → **alle 11 Rollen auf `model: inherit`**
zurückgesetzt; die Steuerung liegt im `/agileteam`-Command (Orchestrator), nicht in den
Agent-Dateien.

### Gewählte Policy: User entscheidet, mit Pflicht-Hinweis
Gemessen (siehe Nachtrag oben): die GBrain-Klasse (Real-Boundary statt Fake) fangen
**nur Opus** — **Haiku UND Sonnet** rutschen 3/3 durch. Da Frontmatter ohnehin nicht
greift und der User die Modellwahl behalten soll, gilt:

1. **Default:** alle Rollen auf dem **Session-Modell** (kein per-Dispatch-`model`).
2. **Pflicht-Disclosure zu Lauf-Beginn (einmal):** der Orchestrator nennt das effektive
   Modell und den GBrain-Vorbehalt — auf Sonnet/Haiku ist das Sicherheitsnetz der
   prüfenden Gates (tester, code-reviewer, security-reviewer, spec-auditor,
   product-owner) **nicht** garantiert.
3. **Opt-in:** sagt der User „gates on opus", dispatcht der Orchestrator genau diese
   fünf Gates mit explizitem `model: "opus"` (der verifiziert wirksame Hebel); sonst
   wird nichts erzwungen.

Kein stilles Hoch-/Runterstufen. Der Hinweis ist verpflichtend, weil das Risiko
unsichtbar ist: Sonnet ist ein vernünftiges Coder-Modell und verfehlt diese Klasse
trotzdem. Umgesetzt in `config/claude/commands/agileteam.md` → Abschnitt
„Model selection (orchestrator-controlled)".

## Methoden-Disziplin (Selbstkorrektur, transparent)
Das Instrument fing mehrfach **eigene** Fehler: ein Regex-Bug im Sabotage-Skript (falscher
"durchgerutscht"-Befund), vier "Leaks", bei denen Spec/Code/Docstrings die dunkle Zone
selbst verrieten (de-leaked und neu gefahren), und ein Lauf, bei dem die DNA-Datei
versehentlich fehlte (verworfen, sauber wiederholt). Jeder dieser Fälle ist in den
Einzel-Reports offen dokumentiert statt geglättet.

*Detail-Reports: `metrics/bench-2026-05-29-*.md` · Korpora: `metrics/corpus/{bench-core-v1,pipe-core-v1,pipe-nonlocal-v1,pipe-providedfake-v1}/`*
