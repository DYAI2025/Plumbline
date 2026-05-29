# /agileteam — Hardened Spec (v3)

> Reference design doc for the `/agileteam` orchestrator
> (`config/claude/commands/agileteam.md`). This is documentation, not an agent or
> command definition (no agent frontmatter on purpose). Metrics & meta-meta
> governance live in `agileteam-governance.md`.

> Grundhaltung: Es gibt kein „100 % abgesichert". Oracle-Problem und Rice's Theorem
> setzen harte Grenzen. Ziel ist **Defense in Depth**: viele *diverse, voneinander
> unabhängige* Prüfungen, sodass ein Fehler mehrere unkorrelierte Gates gleichzeitig
> überleben müsste. Jedes Gate hat: einen **Owner-Agenten**, eine **Unabhängigkeits-
> Bedingung**, eine **harte Loop-Grenze** und ein **maschinell prüfbares Pass-Kriterium**.

---

## Konfigurierbare Projekt-Parameter (zu Beginn auflösen)

```text
TYPECHECK_CMD     z.B. npx tsc --noEmit
LINT_CMD          z.B. npx eslint . --quiet
UNIT_CMD          z.B. npm test
INTEGRATION_CMD   z.B. npm run test:integration
E2E_CMD           z.B. npm run test:e2e
MUTATION_CMD      z.B. npx stryker run        (Schwelle: MUTATION_MIN, Default 70 %)
COVERAGE_MIN      Default 80 % Lines / 70 % Branches
SAST_CMD          z.B. semgrep --config auto
DEP_SCAN_CMD      z.B. npm audit --audit-level=high / osv-scanner
SECRETS_CMD       z.B. gitleaks detect
HERMETIC_RUNNER   sauberer Container/CI-Job (NICHT der stateful Agenten-Sandbox)
MAX_DEVREVIEW_LOOPS   Default 4   → danach Eskalation an Mensch
MAX_QA_RETURNS        Default 3   → danach Eskalation an Mensch
```

Fehlt ein Wert: als `MISSING` markieren, konservativen Default als `ASSUMPTION`
vorschlagen, NICHT still erfinden.

---

## Agenten-Rollen (mit Kontext-Isolation)

| Agent | Aufgabe | Sieht NICHT |
|---|---|---|
| **requirements-analyst** | Elicitation, Spec, REQ-Inventar, Traceability-Matrix | — |
| **spec-auditor** (ultrathink) | Bias-/Halluzinations-Gate auf Spec | — |
| **context-keeper** | Kuratiert state.md / decision-log / ADRs / Matrix | — |
| **planner** | Architektur, Phasen, atomare Tasks | — |
| **tester** (QA design + acceptance) | leitet Acceptance-/E2E-Tests aus Spec ab, fährt Suiten | Coder-Reasoning, Coder-Code |
| **coder** | Implementierung (frischer Subagent je Task) | fremde Tasks |
| **code-reviewer** | Review auf Diff gegen Spec | Coder-Reasoning-Kette |
| **security-reviewer** | SAST/Deps/Secrets/Threat auf Diff | — |
| **production-validator** | DoD + jedes Acceptance-Kriterium gegen Matrix | — |
| **product-owner** (ultrathink) | Iterations-Schlussurteil: richtig gebaut? Bias? erfundene Claims? | Coder-Reasoning |
| **retro-analyst** | Prozessregeln + Gesamtsystem-Justierung | — |

**Unabhängigkeits-Invariante:** Wer Code schreibt, prüft ihn nicht. Wer Tests
ableitet, implementiert sie nicht. Reviewer/Validatoren bekommen **Diff + Spec**, nie
die Reasoning-Kette des Coders (sonst korrelieren die Fehler). Wo möglich: anderes
Modell / adversariale Rolle.

---

```text
/agileteam <goal>
    │
    ├─ Guard clause
    │   ├─ $ARGUMENTS leer/Platzhalter → fragen + stop
    │   ├─ Zielrepo identifizieren
    │   ├─ Branch-Check (main/master) → Feature-Branch / Worktree
    │   ├─ Projekt-Parameter auflösen (s.o.; MISSING markieren)
    │   └─ Task-Backbone in kanban-md (oder TodoWrite) anlegen
    │
    ├─ Phase 0 — Requirements & Validation Design
    │   │  Owner: requirements-analyst
    │   ├─ (optional, bei vagem <goal>) Skill /product-management:write-spec
    │   ├─ Skill /ai-native-prd-architect   [PFLICHT — Engine dieser Phase]
    │   │     → REQ-IDs, Datenmodell, Architektur-Constraints,
    │   │       Given/When/Then-Acceptance, NFRs, Security-Matrix,
    │   │       atomare Tasks, MISSING/ASSUMPTION/OPEN QUESTION/BLOCKER
    │   ├─ Definition of Ready (DoR) erfüllt? sonst stop
    │   ├─ Jede Anforderung: testbar, atomar, widerspruchsfrei → sonst Rückfrage
    │   ├─ LÜCKEN-REGEL (hart): MISSING/OPEN QUESTION/BLOCKER NIEMALS selbst
    │   │     "logisch" schließen. Jede Lücke einzeln via Skill /brainstorming
    │   │     gezielt am User abfragen. Kein ASSUMPTION ohne User-Bestätigung.
    │   ├─ TRACEABILITY-MATRIX bauen (context-keeper):
    │   │     REQ-ID ↔ Acceptance-Test ↔ Impl-Task ↔ Pass-Evidenz
    │   ├─ Speichern → docs/prd/<feature>.prd.md  +  docs/plans/YYYY-MM-DD-<feature>.md
    │   └─ Bei BLOCKER → USER GATE, kein Weiterlauf
    │
    ├─ Phase 0.5 — Spec-Sanity-Gate  (ultrathink, EINMAL)
    │   │  Owner: spec-auditor  |  Modus: voll (irreversibel/kritisch)
    │   ├─ Skill /ultrathink-craftsmanship  (genau EINE Runde, KEIN Re-Run — teuer)
    │   │     ├─ Bias-Hooks: Confirmation / Overengineering / Sunk-Cost / Tool
    │   │     ├─ Failure-Mode-Kette auf die geplante Architektur
    │   │     └─ Konfabulations-Audit via Skill /konfabulations-audit (Companion):
    │   │           jeder externe Claim → belegt | ableitbar | ungeprüft | nicht behaupten
    │   │           ungeprüft/nicht-behaupten DARF nicht als Prämisse weiterwandern
    │   ├─ Findings → wenn BLOCKER: GENAU EIN Remediation-Pass (requirements-analyst)
    │   │            + USER GATE → danach Spec einfrieren (frozen baseline)
    │   └─ ultrathink wird hier NICHT erneut aufgerufen
    │   ⚠ Grenze: prüft Reasoning-Qualität & Claim-Herkunft, NICHT Funktionskorrektheit
    │
    ├─ USER GATE: DoD + Matrix + Spec-Findings zeigen, bevor implementiert wird
    │
    ├─ Phase 1 — TDD- & QA-Setup
    │   │  Owner: planner ∥ tester (parallel)
    │   ├─ tester leitet Acceptance-/E2E-Tests UNABHÄNGIG aus Spec ab
    │   │     (Black-Box, vor Coder-Start; Coder sieht sie als Vertrag)
    │   ├─ planner: Phasen-/Task-Sequenz aus PRD (atomar, dependency-aware)
    │   │     → als kanban-md-Tickets
    │   └─ Test-Fixtures/Test-Daten definieren
    │
    ├─ Phase 2 — Dev/Review-Loop (pro Task)
    │   │  Loop-Grenze: MAX_DEVREVIEW_LOOPS → sonst Eskalation an Mensch
    │   ├─ Frischer coder-Subagent (kanban-md pick --claim … --move in-progress)
    │   │   ├─ Failing Test schreiben (falls nicht schon vom tester)
    │   │   ├─ Laufen lassen + Fehlschlag bestätigen (RED)
    │   │   ├─ Minimale Impl
    │   │   └─ Bis grün laufen (GREEN)
    │   ├─ Unabhängiger code-reviewer auf Diff (gegen Spec, ohne Coder-Reasoning)
    │   ├─ security-reviewer auf Diff: SAST_CMD, DEP_SCAN_CMD, SECRETS_CMD, Threat,
    │   │     Untrusted-Input-/Injection-Surface
    │   ├─ WIEDERHOLUNGS-WÄCHTER (≥2× dieselbe Bug-Signatur in Review/QA):
    │   │     → erzwinge Skill /root-cause-tracing mit 5-Why-Analyse BEVOR ein
    │   │       weiterer Fix versucht wird. Root Cause ist ein Claim → an
    │   │       /konfabulations-audit koppeln (evidenzbelegt, nicht geraten).
    │   ├─ LOOP coder↔reviewer bis bedingungslos grün  (≤ MAX_DEVREVIEW_LOOPS)
    │   ├─ Matrix updaten: REQ-ID → Impl-Task verknüpft
    │   └─ Atomarer, signierter Commit pro Task (Agent-Provenance im Trailer)
    │
    ├─ Phase 3 — Verifikations-, Security-, Validierungs- & Urteils-Gates  (HERMETISCH)
    │   │  Ausführung in HERMETIC_RUNNER, nicht im Agenten-Sandbox
    │   ├─ Gate A — Verifikation: TYPECHECK · LINT · UNIT · INTEGRATION · E2E pass;
    │   │     Coverage ≥ COVERAGE_MIN; MUTATION ≥ MUTATION_MIN; NFR (Perf/A11y/Obs)
    │   ├─ Gate B — Security: keine High/Critical (SAST/Deps/Secrets); Threat abgedeckt
    │   ├─ Gate C — Validierung: production-validator prüft JEDES Acceptance-Kriterium
    │   │     gegen die Matrix; pro REQ-ID pass/fail + Evidenz-Link (keine Prosa)
    │   ├─ Gate D — Iterations-Urteil (ultrathink, EINMAL/Iteration; product-owner)
    │   │     ├─ Modus kurz/kurz+ (Triage skaliert → Kostenkontrolle), KEIN Re-Run
    │   │     ├─ „Richtiges gebaut?" + Bias + Failure-Mode + Konfabulations-Audit
    │   │     └─ BLOCKER → GENAU EIN gezielter Fix zurück Phase 2 (zählt MAX_QA_RETURNS)
    │   │        ⚠ ergänzt, ersetzt NICHT Gate A–C
    │   ├─ Alle pass → Phase 4; fail → Phase 2 (systematic-debugging; ≥2× → 5-Why)
    │   │     Rücksprung ≤ MAX_QA_RETURNS, sonst Eskalation
    │   ├─ METRICS-EMITTER: Run-Record → metrics/runs.jsonl (governance §2)
    │   └─ ARM sentinel: touch ~/.claude/.agileteam-reflection-pending
    │
    ├─ USER ACCEPTANCE GATE  (Mensch, am Ende)
    │   ├─ Stakeholder-Sign-off gegen die Traceability-Matrix
    │   └─ Audit-Artefakte: PRD, Matrix, Gate-Evidenz, Commit-Provenance
    │
    ├─ Phase 4 — Retrospektive  (zwei Ebenen; retro-analyst)
    │   ├─ EBENE 1 — Einzel-Learnings
    │   ├─ EBENE 2 — Gesamtsystem-Justierung (Gate-Reihenfolge, Loop-Grenzen, Modi;
    │   │     Hypothese je Vorschlag: Drift vs. Präzision)
    │   ├─ Discovery via claude-reflect (/reflect, /reflect-skills) — human-gated
    │   ├─ Skill-Authoring NUR via /writing-skills
    │   ├─ Validierung (Dedup, Konflikt, Nutzen) → PER-ITEM y/n-Gate
    │   ├─ CANARY vor voller Übernahme (governance §5)
    │   ├─ ROUTING: Prozess→agileteam-improved · Agent→~/.claude/agents · Projekt→CLAUDE.md
    │   ├─ AUTO-REVERT-Wächter (governance §4c)
    │   └─ DISARM sentinel: rm -f ~/.claude/.agileteam-reflection-pending
    │
    └─ Stop hook  (parallel, feuert bei Session-Ende)
        ├─ stop_hook_active=true → exit 0 (Loop-Guard)
        ├─ Sentinel fehlt → exit 0 (still)
        ├─ sonst {decision:"block", reason:"Retro ausstehend"}
        └─ immer exit 0 (blockiert nie durch Fehler)
```

---

## Kontext-Eigentum & agile Architekturänderungen

**Wer hält den Gesamtkontext?** Nicht ein einzelner Agent (Kontextfenster driften,
Subagenten sind bewusst isoliert). Der Gesamtkontext lebt in **persistenten
Artefakten**, die jeder Agent zu Beginn liest und am Ende aktualisiert. Der
**context-keeper** ist *verantwortlich* dafür, dass diese Artefakte aktuell und
widerspruchsfrei sind — Kurator, nicht Gedächtnis.

```text
docs/prd/<feature>.prd.md        Anforderungen (REQ-IDs)        — Phase 0
docs/traceability.md             REQ ↔ Test ↔ Task ↔ Evidenz    — alle Phasen
docs/architecture/adr-*.md       Architecture Decision Records  — bei jeder Änderung
docs/context/state.md            lebender Gesamtkontext-Snapshot — jede Phase
docs/context/decision-log.md     chronolog. Änderungen + Grund   — agil, append-only
```

**Agile Architekturanpassung** (Lösung weicht von Plan ab): nicht still im Code.
1. ADR anlegen (Kontext, Entscheidung, Alternativen, Konsequenz, betroffene REQ-IDs).
2. decision-log.md Append (was/warum/wann/welcher Agent).
3. Traceability-Matrix nachziehen.
4. Berührt Acceptance-Kriterien → zurück zum USER GATE.
5. Ändert den Prozess selbst → Branch-Strategie.

---

## Task-Backbone & Board — kanban-md

**kanban-md** als Task-Quelle der Wahrheit und Board (statt claude-task-viewer):
agents-first Control-Plane mit atomarem `pick --claim` (multi-agenten-sicher),
Terminal-Tab-TUI, dateibasiert/git-mergebar, `metrics` liefert Fluss-Metriken,
`context --write-to` bindet an den context-keeper. Nur EIN Store nutzen (kanban-md),
nicht zusätzlich den nativen TaskCreate-Store. Arbeitsteilung: kanban-md = Fluss-
Metriken; Metrics-Emitter = Qualitäts-/Drift-Metriken + config_fingerprint.

---

## Branch-Strategie: Produkt vs. Prozess-Evolution

```text
main                 v3 als eingefrorene Baseline. Bekommt KEINE autonomen
                     Workflow-/Skill-Updates mehr. Stabiler Referenzpunkt.
agileteam-improved   iterativ wachsender Prozess-/Architektur-Branch. Alle
                     autonomen Phase-4-Änderungen. 1 Hypothese pro Commit.
~/.claude/agents/    reine Agenten-Feinjustierung direkt (kein Branch);
                     für Bench-Läufe per Snapshot-Tag pinnen (Konfounder-Fix).
```

Drift-vs-Präzision-Vergleich: fixer Korpus + vorab definierte Metriken, main
(eingefroren) vs. agileteam-improved. Details + Meta-Meta-Attribution:
`agileteam-governance.md`.

---

## Skill-Einbindung — Zusammenfassung

| Stelle | Skill | Modus | Wiederholung |
|---|---|---|---|
| Phase 0 (optional) | `/product-management:write-spec` | dialogisch | n.a. |
| Phase 0 (Pflicht) | `/ai-native-prd-architect` | voll | bis DoR erfüllt |
| Phase 0 (je Lücke) | `/brainstorming` | dialogisch | bis Lücke geschlossen |
| Phase 0.5 | `/ultrathink-craftsmanship` (+ `/konfabulations-audit`) | voll | **EINMAL**, kein Re-Run |
| Phase 2 (≥2× Bug) | `/root-cause-tracing` (5-Why) | — | vor jedem weiteren Fix |
| Phase 2 (bei Fail) | `systematic-debugging` | — | ≤ MAX_QA_RETURNS |
| Phase 3 / Gate D | `/ultrathink-craftsmanship` (+ `/konfabulations-audit`) | kurz/kurz+ | **EINMAL/Iteration**, kein Re-Run |
| Phase 4 (Discovery) | `claude-reflect` (`/reflect`, `/reflect-skills`) | — | je Lauf |
| Phase 4 (Authoring) | `/writing-skills` | — | je neuem Skill |

Weitere Anker-Skills: `defense-in-depth`, `test-driven-development`,
`testing-anti-patterns`, `writing-plans`, `executing-plans`.

## Kritische Ergänzungen (v3)

1. **„Selber Bug" braucht eine Bug-Signatur** (Fehlerklasse + Ort + Assertion),
   sonst feuert der ≥2×-Wächter nie. Recurrence-Count pro Signatur in der Matrix.
2. **5-Why kann selbst konfabulieren** → an `/konfabulations-audit` koppeln
   (Root Cause evidenzbelegt, nicht geraten).
3. **Lücken-Differenzierung.** Anforderungs-Lücke → immer an Menschen. Reversibles
   Implementierungs-Detail (keine Acceptance-Kriterien berührt) → ADR-dokumentierte
   technische Entscheidung. Im Zweifel: fragen.
4. **Selbstmodifikation ist das höchste Risiko.** Schutz: Isolation in
   agileteam-improved, Human y/n-Gate, Canary, Auto-Revert unter Baseline.
5. **Vergleichs-Konfounder:** Agenten-Verbesserungen werden von beiden Prozessen
   geteilt → für Vergleichsläufe Agenten-Version pinnen oder re-baselinen.
6. **Stochastik:** mehrere Läufe; Δ unter Rausch-Schwelle = kein Signal.
7. **Flaky Tests = falsche Sicherheit:** Quarantäne + Rerun; flaky zählt nicht als grün.
8. **Untrusted Input** (Docs/Deps) als nicht vertrauenswürdig behandeln.
9. **Maschinell prüfbares Validator-Verdikt** pro REQ-ID (pass/fail + Evidenz).
10. **Globales Budget + Circuit Breaker** zusätzlich zu Loop-Grenzen.

## Wichtige Grenzen (ehrlich)

1. **ultrathink ist ein Reasoning-/Konfabulations-Gate, kein Korrektheits-Gate.**
   Funktionskorrektheit kommt aus Gate A–C.
2. **Companion `konfabulations-audit` wird mitgeliefert** (vendored unter
   `config/claude/skills/`). Prüft Claim-*Herkunft*, nicht Funktionskorrektheit.
3. **„EINE Runde, kein Re-Run"** ist bewusst gewählt (Kosten + Anti-Perfektionismus).
4. **100 % gibt es nicht** — maximiert Zahl unabhängiger Hürden, nicht Beweisbarkeit.
