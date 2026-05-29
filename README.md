# Claude Agents: Advanced Multi-Agent Systems for Claude Code

**82 Claude-Code-Subagents · 16 vendored Skills · `/agileteam` v3 · Swarm-/Hive-Mind-Patterns · kontrollierte Self-Developing-Agent-Loops**

> **Ein Advanced-Agent-Engineering-Lab für Claude Code:** 82 spezialisierte Subagents, vendored Skills, Slash Commands, Hooks und Metriken für Menschen, die komplexe Multi-Agent-Systeme, autonome Software-Automation, TDD-Agent-Teams, Swarm-Koordination und kontrollierte Self-Improvement-Loops bauen oder erforschen wollen.

**Hashtags / Discovery:**  
`#AIAgents` `#AgenticAI` `#ClaudeCode` `#MultiAgentSystems` `#AgentSwarm` `#HiveMind` `#SelfDevelopingAgents` `#SelfImprovingAI` `#Automation` `#AutonomousCoding` `#TDD` `#DevOpsAutomation` `#AIWorkflow` `#SPARC` `#GOAP` `#ConsensusAgents` `#AdvancedAgentSystems` `#AIAgentBubble` `#AgentEngineering`

---

## Was ist dieses Repo?

Dieses Repository ist die versionierte Quelle für eine umfangreiche Sammlung von **Claude Code Agent Definitions**. Jede Agent-Datei ist eine Markdown-Datei mit YAML-Frontmatter und einem System-Prompt. Claude Code entdeckt diese Dateien über `~/.claude/agents/` und kann Aufgaben an die Agenten delegieren.

Das Repo ist mehr als eine lose Prompt-Sammlung:

- **82 Agenten** in 23 Verzeichnissen: Core-Rollen, GitHub-Automation, Swarm-/Hive-Mind-Koordinatoren, Consensus-Protokolle, SPARC-Phasen, Optimierungsagenten, Flow-Nexus-Agenten und Domänenspezialisten.
- **16 vendored Skills** unter `config/claude/skills/`, damit wichtige Workflows auch ohne externe Skill-Packs portabel bleiben.
- **`/agileteam` v3**: ein spec-getriebener Multi-Agent-Orchestrator, der Requirements, Spec-Audit, TDD, Review, Security, Validation, Product-Judgment und Retrospektive verbindet.
- **Learning Loop**: ein sentinel-gesteuerter Stop-Hook kann nach einem abgeschlossenen `/agileteam`-Run eine Retro erzwingen und human-gated Prozessverbesserungen vorschlagen.
- **Explorer UI**: `agent-explorer.html` ist ein statischer Snapshot, mit dem die Agenten durchsuchbar und filterbar werden.

Kurz: Dieses Repo ist der Maschinenraum für die Advanced-AI-Agent-Bubble: keine lose Prompt-Liste, sondern konkrete, versionierte Bausteine für agentische Workflows, automatisierte Softwareentwicklung, Swarm-Experimente und kontrollierte Agenten-Evolution.

---

## Warum dieses Repo interessant ist

### 1. Multi-Agent statt One-Shot-Prompt

Die Agenten sind bewusst in Rollen getrennt: Planner plant, Coder implementiert, Reviewer prüft unabhängig, Tester formuliert Akzeptanztests, Security sucht Risiken, Product Owner beurteilt Produktfit. Dadurch entstehen Workflows, in denen unterschiedliche Agenten unterschiedliche Perspektiven und Kontexte haben.

### 2. Defense in Depth statt „Tests grün, alles gut“

Der `/agileteam`-Workflow unterscheidet zwischen interner Korrektheit, Sicherheitslage, Requirement-Abdeckung, Produktnutzen und menschlicher Abnahme. Ziel ist nicht die Illusion absoluter Sicherheit, sondern mehrere unabhängige Gates, sodass ein Fehler mehrere Prüfungen überleben müsste.

### 3. Self-Developing Agents — aber mit Guardrails

Das Repo enthält einen Learning Loop, der aus wiederkehrenden Fehlern Prozessverbesserungen ableitet. In CORE-Mode bleiben diese Vorschläge human-gated. FULL-Mode ist für autonomere Evolution vorgesehen, setzt aber Metrik-Baselines, Canary und Auto-Revert voraus. Das ist bewusst konservativer als „Agent schreibt einfach seine eigene Zukunft um“.

### 4. Agent Engineering als Repo, nicht als Bauchgefühl

Agenten, Skills, Commands, Hook-Skripte, Metriken und Governance-Dokumente liegen versioniert vor. Dadurch können Änderungen reviewed, getestet, gebenchmarkt und zurückgerollt werden.

---

## Inhalt auf einen Blick

| Bereich | Anzahl | Zweck |
|---|---:|---|
| `core/` | 5 | Basisrollen: `coder`, `planner`, `researcher`, `reviewer`, `tester` |
| `agileteam/` | 6 | Workflow-Rollen für `/agileteam` v3: Requirements, Spec Audit, PO, Security, Retro, Context |
| `github/` | 13 | PR-, Issue-, Release-, Repo-, Workflow- und Multi-Repo-Automation |
| `flow-nexus/` | 9 | Flow-Nexus-Plattformagenten: Sandbox, Swarm, Workflow, Auth, Payments, Neural usw. |
| `templates/` | 9 | Wiederverwendbare Agenten-Templates und Scaffold-Varianten |
| `consensus/` | 7 | Distributed-Systems-Patterns: Byzantine, Raft, Gossip, CRDT, Quorum, Security, Benchmarking |
| `hive-mind/` | 5 | Queen-/Worker-/Scout-/Memory-Patterns für kollektive Intelligenz |
| `optimization/` | 5 | Performance, Topology, Ressourcen, Load Balancing, Benchmarking |
| `sparc/` | 4 | SPARC-Phasen: Specification, Pseudocode, Architecture, Refinement |
| `swarm/` | 3 | Swarm-Topologien: adaptive, hierarchical, mesh |
| `goal/` | 2 | Goal-Oriented Action Planning für Aufgaben- und Code-Ziele |
| `reasoning/` | 2 | Reasoning-/Goal-Planning-Varianten |
| `testing/` | 2 | TDD-London-Swarm und Production Validation |
| `analysis/`, `architecture/`, `data/`, `development/`, `devops/`, `documentation/`, `neural/`, `specialized/` | 8 | Domänenspezialisten für Analyse, Architektur, ML, Backend, CI/CD, API-Doku, Neural, Mobile |
| Repo-Root | 2 | `base-template-generator` und `code-reviewer` |
| `config/claude/skills/` | 16 | Vendored Skills/Fallbacks für portables Arbeiten |
| `config/claude/commands/` | 4 | Slash Commands: `/agileteam`, `/agileteam-bench`, `/reflect`, `/reflect-skills` |

---

## Wichtige Konzepte

### Agent Definition

Eine Agent-Datei beginnt mit YAML-Frontmatter und enthält anschließend den eigentlichen Prompt. Minimal erforderlich:

```yaml
---
name: my-agent
# Claude Code nutzt diese Beschreibung zur Auswahl des passenden Agenten.
description: "One line on what it does and when to use it"
---
```

Regeln:

- `name` muss über die gesamte Sammlung eindeutig sein.
- `description` muss auf Top-Level stehen und aussagekräftig sein.
- Enthält eine Beschreibung `: `, sollte sie komplett gequotet werden, damit YAML korrekt parsebar bleibt.
- Zwei Frontmatter-Stile koexistieren:
  - **Standard Template** mit `triggers`, `capabilities`, `constraints`, `behavior`, `examples`.
  - **claude-flow Style** mit `tools`, `priority` und optionalen `npx claude-flow@alpha hooks`.

### Skill

Skills unter `config/claude/skills/` sind portable Fallbacks für Fähigkeiten, die der `/agileteam`-Workflow referenziert. Beispiele: TDD, Root-Cause-Tracing, Skill-Erstellung, Ultra-Think-Craftsmanship, Konfabulations-Audit und Claude-Reflect-Fallbacks.

### Command

Commands unter `config/claude/commands/` werden nach `~/.claude/commands/` installiert. Besonders wichtig ist `/agileteam`, der eine vollständige agentische Delivery-Pipeline orchestriert.

### Hook

Hooks unter `config/claude/hooks/` automatisieren Bootstrap und Learning Loop:

- `session-start.sh`: kann in Claude Code Web Sessions automatisch Setup durchführen.
- `stop-learning-loop.sh`: blockiert Session-Ende nur dann, wenn eine Agile-Team-Retro per Sentinel ansteht.

---

## `/agileteam` v3: autonomes TDD-Team mit Gates

`/agileteam` ist der anspruchsvollste Teil des Repos. Der Command orchestriert eine Softwareentwicklungskette mit klaren Rollen:

1. **Requirements**: Anforderungen, PRD, Akzeptanzkriterien, Traceability.
2. **Spec sanity**: Spec-Audit, Konfabulationsprüfung, Bias-/Failure-Mode-Check.
3. **Planning**: Architektur, Tasks, Sequenz, Kontextartefakte.
4. **TDD/Implementation**: Coder schreibt erst Tests, dann minimale Implementierung.
5. **Independent Review**: Reviewer bewertet Diff ohne Coder-Gedankengang.
6. **Security Review**: SAST/Dependencies/Secrets/Threat-Surface, sofern Tooling vorhanden ist.
7. **Validation**: Production Validator prüft jedes Requirement gegen Evidenz.
8. **Judgment Gate**: Product Owner prüft, ob wirklich das richtige Produkt gebaut wurde.
9. **Human Acceptance**: Menschliche Abnahme bleibt explizit Teil des Prozesses.
10. **Retrospective / Learning Loop**: Prozessverbesserungen werden gesammelt und nur kontrolliert persistiert.

### CORE vs. FULL

| Mode | Ziel | Self-Modification |
|---|---|---|
| `core` | Sicherer, lauffähiger Standardmodus | Keine autonomen Skill-Writes; Learnings bleiben human-gated |
| `full` | Vollständige Evolution mit Metriken, Canary und Auto-Revert | Nur erlaubt, wenn eine Baseline in `metrics/runs.jsonl` existiert |

Empfehlung: Starte mit CORE, sammle Metriken, aktiviere FULL erst, wenn du Drift und Regressionen messen kannst.

---

## Schnellstart

### Voraussetzungen

Minimal:

- `git`
- `bash`
- `python3`
- `jq` für Hook-Registrierung und JSON-Checks

Für vollständige lokale Checks zusätzlich empfohlen:

- `PyYAML`
- `shellcheck`
- optional `pnpm`/`node` plus `artifacts-builder` für den Explorer-Build

### Installation in Claude Code

```bash
./config/claude/install.sh
```

Der Installer:

- verlinkt dieses Repo als `~/.claude/agents` oder kopiert es mit `--copy`,
- installiert vendored Commands nach `~/.claude/commands/`,
- installiert vendored Skills nach `~/.claude/skills/`,
- registriert den sentinel-gesteuerten Stop-Hook, sofern `jq` verfügbar ist.

Nützliche Varianten:

```bash
./config/claude/install.sh --dry-run
./config/claude/install.sh --copy
./config/claude/install.sh --force
./config/claude/install.sh --no-hook
```

Für neue Maschinen, externe Integrationen und Windows-Hinweise siehe `SETUP.md`.

---

## Typische Use Cases

### Advanced Agent Playground

Nutze die Agentendefinitionen als Pattern-Bibliothek für eigene Subagents: Core-Team, Swarm-Koordination, Consensus, SPARC, GitHub-Automation oder Domänenspezialisten.

### Agentic Software Delivery

Starte `/agileteam <feature>` in einem Zielprojekt, um Requirements, TDD, Reviews und Gates als Agentenpipeline abzubilden.

### AI Automation Lab

Kombiniere GitHub-Agenten, DevOps-Agenten, Flow-Nexus-Agenten und Optimierungsrollen, um End-to-End-Automation rund um Issues, PRs, Releases, Workflows und Benchmarks zu entwerfen.

### Self-Improving Process Experiments

Nutze Metrics, Stop-Hook und Retro-Agenten, um Prozessregeln kontrolliert weiterzuentwickeln. Wichtig: Das Repo priorisiert auditierbare, human-gated Verbesserung gegenüber unkontrollierter Selbstmodifikation.

### Prompt-/Agent-Engineering Research

Vergleiche verschiedene Agentenstile: Standard-Template, claude-flow-nahe Agents, Rollen mit enger Tool-Auswahl, Koordinatoren, Worker, Validatoren, Kritiker und Security-Rollen.

---

## Explorer UI

Das Repo enthält `agent-explorer.html`, einen statischen Snapshot der Agentensammlung. Nach Änderungen an Agenten kannst du ihn neu generieren:

```bash
./build-explorer.sh
```

Hinweis: Der Build benötigt Python mit PyYAML, Node/pnpm und den `artifacts-builder` Skill. Wenn du nur Agenten editierst, ist der Explorer-Build hilfreich, aber nicht zwingend für die Frontmatter-Validierung.

---

## Qualitätssicherung

### Frontmatter validieren

Vor jedem Commit solltest du mindestens Frontmatter, fehlende Beschreibungen und doppelte Agentennamen prüfen:

```bash
python3 - <<'PY'
import re, glob, collections, sys
try:
    import yaml
except ImportError:
    sys.exit("PyYAML required: python3 -m pip install pyyaml")

names = collections.Counter()
bad = []
nodesc = []
for p in sorted(glob.glob("**/*.md", recursive=True)):
    if p.startswith("explorer/"):
        continue
    text = open(p, encoding="utf-8").read()
    m = re.match(r"^---\n(.*?)\n---", text, re.S)
    if not m:
        continue
    try:
        d = yaml.safe_load(m.group(1))
    except Exception as e:
        bad.append((p, str(e).splitlines()[0]))
        continue
    if not isinstance(d, dict):
        bad.append((p, "frontmatter not a mapping"))
        continue
    if "description" not in d:
        nodesc.append(p)
    if d.get("name"):
        names[d["name"]] += 1

dupes = {k: v for k, v in names.items() if v > 1}
print("parse failures:", bad or "none ✓")
print("missing description:", nodesc or "none ✓")
print("duplicate names:", dupes or "none ✓")
if bad or nodesc or dupes:
    sys.exit(1)
PY
```

### Vollständige Checks

```bash
bash config/claude/tests/run_all.sh
```

Der Check-Suite-Entry-Point prüft Frontmatter, Metrics-Skripte, Settings-JSON, Stop-Hook, Web-Bootstrap und — falls installiert — Shell-Skripte via `shellcheck`.

---

## Repository-Struktur

```text
.
├── agileteam/                 # Rollen für den /agileteam Workflow
├── core/                      # Coder, Planner, Researcher, Reviewer, Tester
├── github/                    # GitHub-/PR-/Issue-/Release-Automation
├── swarm/                     # Swarm-Koordinatoren
├── hive-mind/                 # Queen/Worker/Scout/Memory Rollen
├── consensus/                 # Raft/Gossip/CRDT/Byzantine/Quorum Agenten
├── sparc/                     # SPARC Phasen
├── optimization/              # Performance, Ressourcen, Topologie
├── flow-nexus/                # Plattform- und Workflow-Agenten
├── templates/                 # Agenten-Templates
├── config/claude/commands/    # Slash Commands
├── config/claude/skills/      # Vendored Skills/Fallbacks
├── config/claude/hooks/       # SessionStart und Stop-Hook
├── config/claude/metrics/     # Run-Metriken und Health-Auswertung
├── docs/                      # Agile-Team-Spec und Governance
├── explorer/                  # Source für agent-explorer.html
├── tests/                     # Python-Setup-Tests
├── README.md
├── SETUP.md
└── CLAUDE.md
```

---

## Wie du neue Agenten hinzufügst

1. Wähle ein passendes Verzeichnis oder lege ein neues Domänenverzeichnis an.
2. Erstelle eine `.md`-Datei mit gültigem YAML-Frontmatter.
3. Vergib einen eindeutigen `name`.
4. Schreibe eine konkrete `description`, die sagt, wann Claude Code den Agenten einsetzen soll.
5. Definiere Tools, Verhalten, Grenzen und Beispiele so konkret wie möglich.
6. Führe die Frontmatter-Validierung aus.
7. Optional: `./build-explorer.sh`, um `agent-explorer.html` zu aktualisieren.

Beispiel:

```markdown
---
name: reliability-sentinel
description: "Use this agent to inspect reliability risks, failure modes, and operational readiness before release."
tools: Read, Grep, Bash
---

You are a reliability sentinel...
```

---

## Design-Prinzipien

- **Rollen klar trennen:** Ein guter Agent hat eine scharfe Aufgabe, keine generische „mach alles“-Identität.
- **Independence matters:** Review, Test, Security und Product Judgment sollen nicht einfach dieselbe Coder-Perspektive wiederholen.
- **Evidence over vibes:** Claims sollen durch Code, Tests, Logs, Dokumente oder explizite Annahmen belegbar sein.
- **Human gates bleiben wichtig:** Besonders bei Anforderungen, Produktentscheidungen und persistenter Selbstverbesserung.
- **Versioniere Prompts wie Code:** Agentenänderungen brauchen Diff, Review und Validierung.
- **Automatisiere ohne falsche Sicherheit:** Fehlendes Tooling wird als `MISSING` markiert, nicht als bestanden fantasiert.

---

## Weiterführende Dateien

- `SETUP.md` — ausführliche Installations- und Portabilitätsnotizen.
- `CLAUDE.md` — Arbeitsprotokoll für dieses Repo und Learning-Loop-Regeln.
- `docs/agileteam-spec-v3.md` — kanonische Spezifikation des `/agileteam` v3 Workflows.
- `docs/agileteam-governance.md` — Metriken, Governance und Meta-Meta-Layer.
- `config/claude/commands/agileteam.md` — der eigentliche Slash-Command.
- `config/claude/install.sh` — Bootstrapper für Agents, Commands, Skills und Hook.
- `explorer/README.md` — Hinweise zum Explorer-Build.

---

## Für wen ist das?

Dieses Repo passt besonders gut, wenn du dich für Folgendes interessierst:

- Advanced AI Agents und Agent Engineering
- Claude Code Subagents und Slash Commands
- Multi-Agent Software Development
- Autonomous Coding Workflows
- Self-Improving / Self-Developing Agents
- Agent Swarms, Hive Minds und Koordinator/Worker-Architekturen
- TDD mit LLM-Agenten
- DevOps-, GitHub- und Release-Automation
- Spec-driven Development und Defense-in-Depth QA
- Research rund um agentische Systeme und Prozess-Governance

Wenn du einfach nur einen kleinen Prompt suchst, ist dieses Repo wahrscheinlich Overkill. Wenn du aber mit komplexen, auditierbaren Agentensystemen spielen, bauen und lernen willst: willkommen im Maschinenraum.

---

## Lizenz & Attribution

Ja: Weil die Agentenbasis auf **Claude Flow** aus dem GitHub-Account [`ruvnet`](https://github.com/ruvnet/) aufgebaut wurde, wird die Herkunft hier und in `LICENSE` ausdrücklich genannt. Claude Flow ist bzw. war unter MIT-Lizenz veröffentlicht; der ursprüngliche Projektpfad [`ruvnet/claude-flow`](https://github.com/ruvnet/claude-flow) verweist inzwischen auf [`ruvnet/ruflo`](https://github.com/ruvnet/ruflo).

Dieses Repository steht unter [MIT](LICENSE) © 2026 DYAI2025. Teile dieser Agentensammlung sind von **Claude Flow / Ruflo** abgeleitet: Copyright © ruvnet, ebenfalls MIT. Bei Weitergabe, Forks oder größeren Rewrites bitte diese Attribution und den MIT-Lizenzhinweis beibehalten.

---

**More discovery tags:**  
`#AIEngineering` `#AgentOrchestration` `#PromptEngineering` `#LLMOps` `#AutonomousAgents` `#CodingAgents` `#SoftwareAgents` `#CollectiveIntelligence` `#WorkflowAutomation` `#AgenticWorkflow` `#ClaudeAgents` `#FutureOfSoftwareDevelopment`
