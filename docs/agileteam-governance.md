# /agileteam — Messung & Governance (Meta-Meta-Ebene)

Begleitdokument zu `agileteam-spec-v3.md` und zum Command `config/claude/commands/agileteam.md`.
Beantwortet: *welche* Metriken, *wo* der Abgleich stattfindet, und wie man von der
Meta-Ebene (Retro, claude-reflect) auf eine **Meta-Meta-Ebene** kommt, die erkennt, ob ein
bestimmtes Gate/Agent/Skill **auf Dauer** eine negative Tendenz entwickelt — und dort
behutsam, aber dauerhaft messend gegensteuert.

---

## 1. Drei Ebenen (Begriffsklärung)

```text
Objekt-Ebene     Produkt bauen (Phasen 0–3). "Ist DIESES Produkt korrekt?"
Meta-Ebene       Retro + claude-reflect. "Wie sollten wir den Prozess ändern?"   (kurzer Horizont, pro Lauf)
Meta-Meta-Ebene  Prozess-Gesundheit über viele Läufe. "Verbessern unsere
                 Verbesserungen wirklich – oder driften sie?"                    (langer Horizont, lauf-übergreifend)
```

Die Meta-Meta-Ebene beobachtet **die Meta-Ebene selbst**. Sie ist die einzige Stelle,
die Komponenten-Änderungen (Gate/Agent/Skill) zurückrollen oder einfrieren darf — immer
human-gated, nie reflexhaft.

---

## 2. Wo der Abgleich physisch stattfindet

```text
Emission (automatisch)   Ende Phase 3 → metrics-emitter schreibt EINEN Run-Record
                         nach  metrics/runs.jsonl   (append-only, Branch agileteam-improved)

Per-Run-Vergleich        /agileteam-bench (auf Anforderung): fixer Korpus,
                         gepinnte Config → main-Prozess vs. agileteam-improved

Meta-Meta-Review         periodischer Job (z.B. wöchentlich, scheduled task):
(Process Health Board)   liest runs.jsonl → SPC + Attribution → metrics/process-health.md
                         + Alerts. Schlägt Gegensteuerung vor (human-gated).
```

**Run-Record-Schema** (eine Zeile JSON pro Lauf — das ist das Rückgrat der Attribution):

```json
{
  "run_id": "2026-05-29T10:14Z-ab12",
  "corpus_id": "bench-core-v1",          // fixierter Aufgaben-Korpus
  "process_branch": "agileteam-improved@<commit>",
  "config_fingerprint": {                // WELCHE Versionen waren aktiv?
    "gate.spec_sanity":   "sha:…",
    "gate.mutation":      "sha:…",
    "agent.coder":        "sha:…",
    "agent.code_reviewer":"sha:…",
    "skill.konfab_audit": "sha:…"
  },
  "metrics": { "first_pass": 0.72, "mutation": 0.81, "unverified_claims": 0.04, … },
  "gate_outcomes": { "A":"pass","B":"pass","C":"pass","D":"pass" },
  "human_overrides": 1
}
```

Ohne `config_fingerprint` ist keine Attribution möglich — sie ist Pflicht.

---

## 3. Metrik-Katalog (ausformuliert)

Drei Gruppen. **Präzision/Qualität** ist das eigentliche Ziel; **Fluss** misst Tempo/
Effizienz; **Selbst-Korrektur** sind Frühwarnsignale. Regel gegen Goodhart: die
Meta-Meta-Ebene gewichtet Qualität über Tempo — sonst wirken „Verbesserungen", die nur
schneller machen, gut, während die Präzision driftet.

### 3a. Präzision & Qualität (Primärziel)

| Metrik | Definition / Formel | Richtung | Frühwarn-Sentinel für |
|---|---|---|---|
| First-pass-Erfolg | Anteil Tasks ohne Rücksprung in Phase 2 = `tasks_no_return / tasks_total` | ↑ | nachlassende Code-/Spec-Qualität |
| Acceptance-Trefferquote (Gate C, 1. Versuch) | `REQ_pass_first_try / REQ_total` | ↑ | „falsch verstanden" statt „falsch gebaut" |
| Mutation-Score | getötete Mutanten / Mutanten gesamt | ↑ | schwache Tests (Schein-Grün) |
| Coverage (Line/Branch) | überdeckte / gesamt | ↑ (Plateau) | Testlücken; Vorsicht: gameable |
| Escaped-Defect-Rate / Regression | in Folgeläufen wieder geöffnete REQ-IDs `reopened_REQ / closed_REQ` | ↓ | echte entwichene Fehler (wahrster Qualitätswert) |
| Defect Removal Efficiency (DRE) | `vor Acceptance gefundene / (vor + nach) gefunden` | ↑ | Wirksamkeit der Gates insgesamt |
| Ungeprüfte-Claim-Quote | aus Konfabulations-Audit: `ungeprüft+nicht_behaupten / claims_total` | ↓ | **Halluzinations-Drift** (Kern-Sentinel) |

### 3b. Fluss / Kanban (übertragbar — kritisch geprüft)

| Kanban/Scrum-Metrik | Überträgt sich? | Agenten-Äquivalent | Mein Vorbehalt |
|---|---|---|---|
| **Cycle Time** | ✅ stark | Task-Start → merged-green | bestes Tempo-Maß |
| **Lead Time** | ✅ stark | REQ definiert → akzeptiert | inkl. Wartezeit an User-Gates |
| **Flow Efficiency** | ✅ aufschlussreich | Arbeitszeit / (Arbeit+Wartezeit in Loops) | zeigt, ob Review-Loops zum Engpass werden |
| **Throughput** | ⚠️ bedingt | akzeptierte REQ / Lauf | gameable; nie allein bewerten |
| **WIP** | ⚠️ nur Parallel-Phasen | offene Tasks in Batch-Phasen | im seriellen Loop kaum aussagekräftig |
| **Blocked Time / Blocker-Count** | ✅ | Zeit/Anzahl an User-Gates & Eskalationen | hoher Wert = unreife Spec |
| **Cumulative Flow Diagram** | ✅ Visualisierung | Tasks je Phase über Zeit | macht die Engpass-Phase sichtbar (von kanban-md ableitbar) |
| **Rework Ratio** | ✅ | `dev_review_loops / tasks` + Phase-2-Returns | direkter Qualitäts-/Reibungsindikator |
| **Velocity / Story Points** | ❌ ablehnen | — | Effort-Proxy, gameable, Agenten ermüden nicht → irreführend, höchstens informativ |
| **Sprint Burndown** | ❌ n/a | — | nur falls echte Sprints auferlegt werden |

> Hinweis: Die Fluss-Metriken (Cycle/Lead/Throughput/Flow-Efficiency) liefert
> **kanban-md** via `kanban-md metrics` out of the box — von dort lesen, nicht neu bauen.

### 3c. Selbst-Korrektur & Kosten (Frühwarnung)

| Metrik | Definition | Richtung | Sentinel für |
|---|---|---|---|
| Root-cause-Trigger-Rate | `≥2×-Bug-Auslösungen / Lauf` | ↓ | steigend = „um Fehler herumgebaut" |
| Mittlere Dev/Review-Loops bis grün | Ø Loops/Task | ↓ | Review-Effektivität sinkt |
| Human-Override-Quote | `Overrides an Gates / Gates` | ↓ (stabil) | Vertrauensverlust / Fehljustierung |
| Eskalationsrate | `Eskalationen / Lauf` (Loop-Grenzen erreicht) | ↓ | strukturelle Sackgassen |
| Kosten pro akzeptierter REQ | `tokens_total / REQ_accepted` | ↓ (stabil) | ineffiziente Selbst-Modifikation |
| Spec-Sanity-Findings | BLOCKER-Funde in Phase 0.5 / Lauf | ↓ über Zeit | Reifegrad der Anforderungsarbeit |

> Praktische Mindestauswahl, falls ihr klein anfangt: **First-pass-Erfolg,
> Escaped-Defect-Rate, Mutation-Score, Ungeprüfte-Claim-Quote, Cycle Time,
> Human-Override-Quote.** Diese sechs decken Qualität, Fluss und Drift ab.

---

## 4. Meta-Meta: negative Tendenz erkennen & attribuieren

Ziel: erkennen, dass ein *bestimmtes* Gate/Agent/Skill auf Dauer schadet — nicht nur,
dass „irgendwas schlechter wird".

### 4a. Zwei sich ergänzende Sichten

```text
(1) Run-Zeitreihe je Metrik (alle Läufe)   → ist der Prozess "in control"?
    Methode: Statistical Process Control (SPC). Kontrollgrenzen aus der
    eingefrorenen main-Baseline. Signale: Punkt außerhalb der Grenzen ODER
    Run-Regel (z.B. 7 Punkte monoton fallend). CUSUM für schleichende Drift.

(2) Komponenten-Versions-Panel je Metrik    → WER ist schuld?
    Da jede Prozessänderung = genau EIN Commit (eine Hypothese), ist jeder
    Commit ein Quasi-Experiment. Segmentiere die Metrik nach config_fingerprint:
    Läufe mit gate.X=v1 vs. v2 (Korpus fix). Effektgröße + (bei kleinem N)
    robust/nichtparametrisch. Über mehrere Versionen derselben Komponente:
    fällt Metrik M mit jeder neuen Version von gate.X? → negative Tendenz
    von gate.X attribuiert.
```

Sicht (1) sagt *dass* etwas driftet, Sicht (2) sagt *welche Komponente*. Erst beide
zusammen rechtfertigen eine Gegensteuerung.

### 4b. Behutsam gegensteuern (Hysterese statt Reflex)

Einzelne Ausreißer = Rauschen (LLM-Stochastik). Nie auf einen Lauf reagieren.

```text
Auslöser: nachhaltiges Signal = Metrik unter Baseline für ≥ W Läufe
          ODER monoton fallend über ≥ 3 aufeinanderfolgende Versionen einer Komponente.

Eskalationsleiter (kleinster Eingriff zuerst):
  1) FLAG + ein weiteres Beobachtungsfenster (nichts ändern, weiter messen)
  2) FREEZE: keine neuen Versionen dieser Komponente, bis erholt
  3) REVERT: genau die Versions-Hypothese (1 Commit) zurückrollen, die die
     Regression einführte  → saubere Historie macht das risikoarm
  4) ESKALATION an Mensch: Redesign der Komponente

Jeder Schritt human-gated. Nach jeder Maßnahme: Bestätigungsfenster, bevor
"erholt" erklärt wird. → "immer langfristig messend".
```

### 4c. Auto-Revert-Schwelle (harte Untergrenze)

Unabhängig von der sanften Leiter: fällt eine **Primär-Qualitätsmetrik** (3a) unter die
eingefrorene main-Baseline und bleibt dort über das Bestätigungsfenster → automatischer
Vorschlag zum Revert der zuletzt eingeführten Komponenten-Version, mit Alert. Ausführung
human-gated. Das schützt vor dem größten Risiko: dass die Selbst-Modifikation den ganzen
Prozess schleichend verschlechtert.

---

## 5. Canary für neue Prozessregeln (vor voller Übernahme)

Bevor eine in Phase 4 beschlossene Regel/Skill-Änderung in `agileteam-improved` voll
aktiv wird:

```text
1. Regel als "canary" markieren (aktiv, aber als experimentell geflaggt).
2. Auf kleinem, fixem Canary-Task-Set laufen lassen (Teilmenge des Bench-Korpus).
3. Metriken gegen die Vor-Regel-Baseline vergleichen.
4. Keine Verschlechterung der Primärmetriken → Promotion zu "stable".
   Verschlechterung → Commit verwerfen, Learning dokumentieren (kein stiller Drop).
```

So degradiert eine schlechte Regel nicht sofort alle Folgeläufe.

---

## 6. Vergleichsprotokoll /agileteam-bench (mit Konfounder-Fix)

Zweck: zeigen, ob `agileteam-improved` über Zeit Präzision oder Drift erzeugt — gegen den
eingefrorenen `main`-Prozess als Kontrolle.

```text
Voraussetzungen (VOR Beginn fixieren, sonst misst man den Maßstab mit):
  - corpus_id: fixer Aufgaben-Korpus (repräsentativ, eingefroren)
  - Metrik-Set + Rausch-Schwellen + Baseline aus N main-Läufen

Konfounder-Fix (wichtigster Punkt):
  Agenten-Verbesserungen fließen direkt in claude-agents und werden von BEIDEN
  Prozessen geteilt. Damit der Vergleich nur den PROZESS misst:
  → pro Vergleichslauf die Agenten-Version PINNEN (Snapshot-Tag im
    config_fingerprint). Beide Arme (main vs. improved) nutzen denselben
    gepinnten Agenten-Stand.
  → Alternative, wenn Pinning unpraktisch: Ergebnis explizit lesen als
    "Prozess GEGEBEN Agenten-Stand X" und bei jedem neuen Agenten-Stand
    re-baselinen.

Ausführung:
  - Mehrere Läufe je Arm (Stochastik!), nicht einer.
  - Δ unter Rausch-Schwelle = kein Signal.
  - Ergebnis → metrics/bench-<datum>.md + Eintrag ins Process Health Board.
```

---

## 6a. Retro True-Line Challenge

Plumbline does not optimize for finishing. Plumbline optimizes for staying true to confirmed human customer value; finishing is valid only when the line remains true.
Retrospective improvements are **subordinate** to this Plumbline vision: a process
improvement is valid only if it improves Plumbline's ability to build real products that
people can use. Every proposed workflow improvement must answer:

1. Does this help us understand how customers think?
2. Does this help us understand how customers work?
3. Does this help us understand how customers feel friction or value?
4. Does this make customer value easier to validate?
5. Does this detect green-but-useless output earlier?
6. Does this detect fantasy-direction drift earlier?
7. Does this reduce unverified assumptions?
8. Does this make user-value contradictions harder to miss?
9. Does this make quality gates more truthful?

Reject or block changes that primarily optimize: faster completion without stronger
truth; agent convenience; lower friction by weakening gates; more generated artifacts
without stronger evidence; green tests without real-world usefulness; or claimed
improvement without customer-value evidence. Required retro fields: improvement proposal ·
claimed benefit · customer-value link · human-realism link · evidence needed · Watcher
challenge result · decision (`accept | revise | reject | blocked`). Route every proposal
through `plumbline-watcher` before persisting it.

---

## 7. Anschluss an die bestehenden Tools

- **claude-reflect** liefert Roh-Signal (Korrekturen, Muster) auf der Meta-Ebene —
  bleibt **zwingend human-gated**, weil in einem Agenten-Team „Korrekturen" oft
  Agent-gegen-Agent-Meinungen sind und eine falsche Korrektur sonst zu permanentem
  Bias würde.
- **Meta-Meta** ist NICHT claude-reflect, sondern die darüberliegende Zeitreihen-/
  Attributionsschicht (`runs.jsonl` + Process Health Board). claude-reflect schlägt
  Änderungen vor; Meta-Meta entscheidet, ob diese Änderungen sich über Zeit bewähren.
- Das Process Health Board kann als wöchentlicher **scheduled task** laufen, der
  `runs.jsonl` auswertet und bei nachhaltigem Signal einen human-gated
  Gegensteuerungs-Vorschlag erzeugt.
