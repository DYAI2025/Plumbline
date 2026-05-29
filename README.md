# Claude Agents: Advanced Multi-Agent Systems for Claude Code

**82 Claude Code subagents · 16 vendored skills · `/agileteam` v3 · AI agent automation · swarm and hive-mind patterns · controlled self-developing agent loops**

> **An advanced AI agent engineering lab for Claude Code.** This repository packages 82 specialized subagents, portable skills, slash commands, lifecycle hooks, metrics, governance docs, and a defense-in-depth `/agileteam` workflow for builders who want to design, test, automate, and evolve complex multi-agent systems instead of relying on one-shot prompts.

**Discovery tags:**  
`#AIAgents` `#AgenticAI` `#ClaudeCode` `#ClaudeAgents` `#MultiAgentSystems` `#AgentSwarm` `#HiveMind` `#SelfDevelopingAgents` `#SelfImprovingAI` `#AutonomousAgents` `#AutonomousCoding` `#AgentAutomation` `#AIAutomation` `#AgentEngineering` `#PromptEngineering` `#LLMOps` `#TDD` `#DevOpsAutomation` `#SPARC` `#GOAP` `#ConsensusAgents` `#AdvancedAgentSystems`

---

## What is this repository?

This repository is a versioned collection of **Claude Code agent definitions**. Each agent is a Markdown file with YAML frontmatter and a role-specific system prompt. Claude Code discovers these files from `~/.claude/agents/` and can delegate work to the right subagent by name and description.

It is more than a prompt dump:

- **82 agents across 23 agent directories** for coding, planning, research, review, testing, GitHub automation, swarm coordination, hive-mind coordination, distributed consensus, SPARC workflows, optimization, Flow Nexus platform tasks, and domain-specific engineering.
- **16 vendored skills** in `config/claude/skills/` so important agent workflows remain portable even when external skill packs are unavailable.
- **`/agileteam` v3**, a spec-driven multi-agent software delivery workflow that connects requirements, spec auditing, TDD, implementation, independent review, security review, production validation, product judgment, human acceptance, and retrospective learning.
- **Controlled self-improvement loops** through metrics, governance, a sentinel-gated Stop hook, and human-gated persistence rules.
- **A searchable static explorer** in `agent-explorer.html` for browsing the agent catalog.

In short: this is an advanced agentic software engineering toolkit for people building complex AI agent systems, autonomous coding workflows, swarm experiments, and auditable self-improving agent processes.

---

## Why this project matters

### 1. Multi-agent workflows instead of one-shot prompting

The collection separates responsibilities across specialized roles: planners plan, coders implement, testers design acceptance tests, reviewers critique diffs, security agents inspect risk, production validators map evidence to requirements, and product-owner agents judge whether the right thing was built. That separation creates richer, more reliable agentic workflows than a single general-purpose prompt.

### 2. Defense in depth for agentic software delivery

The `/agileteam` workflow distinguishes internal correctness, security posture, requirement coverage, user value, and human approval. The goal is not a false promise of perfect safety; the goal is to stack independent gates so a defect must survive several unrelated checks before it ships.

### 3. Self-developing agents with guardrails

The repository supports process learning from recurring failures, but it does not blindly let agents rewrite their own future. In CORE mode, learnings stay human-gated. FULL mode can unlock autonomous evolution only after metrics baselines, canaries, and auto-revert protections exist.

### 4. Agent engineering as versioned infrastructure

Agents, skills, commands, hooks, metrics scripts, governance docs, and installer behavior all live in git. That means your agent system can be reviewed, tested, benchmarked, forked, reverted, and improved like software.

---

## Repository contents at a glance

| Area | Count | Purpose |
|---|---:|---|
| `core/` | 5 | Foundational roles: `coder`, `planner`, `researcher`, `reviewer`, `tester` |
| `agileteam/` | 6 | `/agileteam` v3 workflow roles: requirements, spec audit, product owner, security, retrospective, context |
| `github/` | 13 | Pull request, issue, release, repository, workflow, and multi-repo automation |
| `flow-nexus/` | 9 | Flow Nexus platform agents for sandboxes, swarms, workflows, auth, payments, neural features, and user tooling |
| `templates/` | 9 | Reusable scaffolds and template variants for agent creation |
| `consensus/` | 7 | Distributed-systems patterns: Byzantine, Raft, Gossip, CRDT, Quorum, security, benchmarking |
| `hive-mind/` | 5 | Queen, worker, scout, memory, and collective-intelligence coordination patterns |
| `optimization/` | 5 | Performance monitoring, topology optimization, load balancing, resource allocation, benchmarks |
| `sparc/` | 4 | SPARC phases: specification, pseudocode, architecture, refinement |
| `swarm/` | 3 | Adaptive, hierarchical, and mesh swarm coordinators |
| `goal/` | 2 | Goal-oriented action planning for product and code goals |
| `reasoning/` | 2 | Reasoning and goal-planning variants |
| `testing/` | 2 | London-school TDD swarm and production validation |
| `analysis/`, `architecture/`, `data/`, `development/`, `devops/`, `documentation/`, `neural/`, `specialized/` | 8 | Domain specialists for code analysis, architecture, ML, backend, CI/CD, API docs, neural systems, and mobile |
| Repository root | 2 | `base-template-generator` and `code-reviewer` |
| `config/claude/skills/` | 16 | Vendored skills and fallbacks for portable agent workflows |
| `config/claude/commands/` | 4 | Slash commands: `/agileteam`, `/agileteam-bench`, `/reflect`, `/reflect-skills` |

---

## Core concepts

### Agent definition

An agent file starts with YAML frontmatter and then contains the prompt. Minimal example:

```yaml
---
name: my-agent
# Claude Code uses this description to decide when the agent is relevant.
description: "One line on what it does and when to use it"
---
```

Rules:

- `name` must be unique across the entire collection.
- `description` must exist at the top level and should clearly state when to use the agent.
- If a `description` contains a colon followed by a space, quote the whole value so YAML parses correctly.
- Two frontmatter styles coexist:
  - **Standard template:** richer `triggers`, `capabilities`, `constraints`, `behavior`, and `examples` blocks.
  - **claude-flow style:** leaner `tools`, `priority`, and optional `npx claude-flow@alpha hooks` usage.

### Skill

Skills in `config/claude/skills/` are portable fallbacks for capabilities referenced by `/agileteam`. Examples include TDD, root-cause tracing, skill creation, ultrathink craftsmanship, confabulation auditing, and local Claude Reflect fallbacks.

### Command

Commands in `config/claude/commands/` are installed into `~/.claude/commands/`. The most important command is `/agileteam`, which orchestrates the full multi-agent software delivery pipeline.

### Hook

Hooks in `config/claude/hooks/` automate bootstrap and learning-loop behavior:

- `session-start.sh` can bootstrap Claude Code web sessions automatically.
- `stop-learning-loop.sh` only blocks session end when a retrospective sentinel is present.

---

## `/agileteam` v3: autonomous TDD team with verification gates

`/agileteam` is the most advanced workflow in this repository. It orchestrates a role-separated software delivery pipeline:

1. **Requirements:** PRD, acceptance criteria, requirement IDs, and traceability.
2. **Spec sanity:** spec audit, confabulation checks, bias review, failure-mode review.
3. **Planning:** architecture, milestones, atomic tasks, and context artifacts.
4. **TDD implementation:** coder writes a failing test first, then the smallest implementation needed to pass.
5. **Independent code review:** reviewer inspects the diff without relying on the coder's reasoning.
6. **Security review:** SAST, dependency risk, secrets, threat cases, and supply-chain concerns when tooling exists.
7. **Production validation:** production-validator checks every acceptance criterion against evidence.
8. **Judgment gate:** product-owner checks whether the implementation solves the right problem.
9. **Human acceptance:** machine-pass is not treated as product approval.
10. **Retrospective and learning loop:** recurring failures become controlled improvement proposals.

### CORE vs FULL mode

| Mode | Purpose | Self-modification behavior |
|---|---|---|
| `core` | Safe, runnable baseline for normal use | No autonomous skill writes; learnings remain human-gated |
| `full` | Full evolution with metrics, canary, and auto-revert | Allowed only after a `metrics/runs.jsonl` baseline exists |

Recommended path: start in CORE, gather metrics, then graduate to FULL only when you can measure drift, regression, and improvement.

---

## Quickstart

### Requirements

Minimum:

- `git`
- `bash`
- `python3`
- `jq` for hook registration and JSON checks

Recommended for full local checks:

- `PyYAML`
- `shellcheck`
- optional `node`/`pnpm` plus the `artifacts-builder` skill for rebuilding the explorer

### Install into Claude Code

```bash
./config/claude/install.sh
```

The installer:

- symlinks this repository as `~/.claude/agents`, or copies it when `--copy` is used;
- installs vendored commands into `~/.claude/commands/`;
- installs vendored skills into `~/.claude/skills/`;
- registers the sentinel-gated Stop hook when `jq` is available.

Useful variants:

```bash
./config/claude/install.sh --dry-run
./config/claude/install.sh --copy
./config/claude/install.sh --force
./config/claude/install.sh --no-hook
```

For new machines, optional integrations, and Windows notes, see `SETUP.md`.

---

## SEO-focused use cases

### Advanced AI agent engineering

Use this repository as a pattern library for Claude Code subagents, multi-agent orchestration, agent roles, agent prompts, and production-oriented agent workflows.

### Agentic software development

Run `/agileteam <feature>` in a target project to turn requirements, TDD, review, validation, and retrospectives into a coordinated AI software engineering pipeline.

### Autonomous coding and automation lab

Combine GitHub agents, DevOps agents, Flow Nexus agents, optimization agents, and swarm coordinators to prototype end-to-end AI automation for issues, pull requests, releases, workflows, and benchmarks.

### Self-improving agent process research

Use the metrics emitter, Stop hook, governance docs, and retrospective agents to study how agent workflows can improve safely over time. The design favors auditable, human-gated improvement over uncontrolled self-modification.

### Prompt engineering and LLMOps research

Compare standard-template agents, claude-flow-style agents, coordinators, workers, validators, critics, security roles, and specialized domain experts.

---

## Explorer UI

The repository includes `agent-explorer.html`, a static searchable snapshot of the agent collection. Rebuild it after changing agents:

```bash
./build-explorer.sh
```

The explorer build requires Python with PyYAML, Node/pnpm, and the `artifacts-builder` skill. If you only edit agent Markdown files, rebuilding the explorer is useful but not required for frontmatter validation.

---

## Validation and quality checks

### Validate agent frontmatter

Before committing, check for YAML parse errors, missing descriptions, and duplicate names:

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

### Run the full check suite

```bash
bash config/claude/tests/run_all.sh
```

The suite validates agent frontmatter, metrics scripts, `.claude/settings.json`, Stop-hook behavior, web-session bootstrap behavior, and shell scripts when `shellcheck` is installed.

---

## Repository structure

```text
.
├── agileteam/                 # /agileteam workflow roles
├── core/                      # Coder, Planner, Researcher, Reviewer, Tester
├── github/                    # GitHub, PR, issue, release, and workflow automation
├── swarm/                     # Swarm coordinators
├── hive-mind/                 # Queen, worker, scout, and memory roles
├── consensus/                 # Raft, Gossip, CRDT, Byzantine, and Quorum agents
├── sparc/                     # SPARC phases
├── optimization/              # Performance, resource, and topology agents
├── flow-nexus/                # Platform and workflow agents
├── templates/                 # Agent templates
├── config/claude/commands/    # Slash commands
├── config/claude/skills/      # Vendored skills and fallbacks
├── config/claude/hooks/       # SessionStart and Stop hooks
├── config/claude/metrics/     # Run metrics and process-health reporting
├── docs/                      # Agile-team spec and governance docs
├── explorer/                  # Source for agent-explorer.html
├── tests/                     # Python setup tests
├── README.md
├── SETUP.md
└── CLAUDE.md
```

---

## Add a new agent

1. Choose an existing directory or create a new domain directory.
2. Create a `.md` file with valid YAML frontmatter.
3. Pick a globally unique `name`.
4. Write a concrete `description` that tells Claude Code when to use the agent.
5. Define tools, behavior, limits, and examples as explicitly as possible.
6. Run the frontmatter validator.
7. Optionally run `./build-explorer.sh` to refresh `agent-explorer.html`.

Example:

```markdown
---
name: reliability-sentinel
description: "Use this agent to inspect reliability risks, failure modes, and operational readiness before release."
tools: Read, Grep, Bash
---

You are a reliability sentinel...
```

---

## Design principles

- **Separate roles clearly:** a strong agent has a sharp responsibility, not a vague "do everything" identity.
- **Preserve independence:** review, testing, security, and product judgment should not simply repeat the coder's perspective.
- **Prefer evidence over vibes:** claims should be backed by code, tests, logs, documentation, or explicit assumptions.
- **Keep human gates where they matter:** especially for requirements, product decisions, and persistent self-improvement.
- **Version prompts like code:** agent changes should be diffed, reviewed, validated, and reversible.
- **Do not automate false confidence:** missing tooling is marked `MISSING`, not silently treated as passing.

---

## Important files

- `SETUP.md` — detailed installation, portability, optional integrations, and Windows notes.
- `CLAUDE.md` — repository working protocol and learning-loop rules.
- `docs/agileteam-spec-v3.md` — canonical specification for `/agileteam` v3.
- `docs/agileteam-governance.md` — metrics, governance, and meta-governance layer.
- `config/claude/commands/agileteam.md` — the actual `/agileteam` slash command.
- `config/claude/install.sh` — bootstrapper for agents, commands, skills, and hooks.
- `explorer/README.md` — explorer build notes.

---

## Who is this for?

This repository is useful if you care about:

- advanced AI agents and agent engineering;
- Claude Code subagents and slash commands;
- multi-agent software development;
- autonomous coding workflows;
- self-improving and self-developing agents;
- agent swarms, hive minds, coordinators, and worker architectures;
- TDD with LLM agents;
- DevOps, GitHub, and release automation;
- spec-driven development and defense-in-depth QA;
- research into agentic systems, prompt engineering, LLMOps, and process governance.

If you only need a tiny prompt, this repository may be overkill. If you want to build, inspect, and evolve complex auditable agent systems, welcome to the machine room.

---

## License and attribution

This repository is licensed under [MIT](LICENSE) © 2026 DYAI2025.

The agent base is derived in part from **Claude Flow** by [`ruvnet`](https://github.com/ruvnet/). The original repository path [`ruvnet/claude-flow`](https://github.com/ruvnet/claude-flow) currently points to [`ruvnet/ruflo`](https://github.com/ruvnet/ruflo). Claude Flow / Ruflo is MIT-licensed; portions of this collection derived from it remain attributed to Copyright © ruvnet, also under MIT. Keep this attribution and the MIT license notice when redistributing forks or major rewrites.

---

**More discovery keywords:**  
`AI agents` · `Claude Code agents` · `Claude subagents` · `agentic AI` · `multi-agent systems` · `autonomous coding agents` · `AI software engineering` · `self-improving agents` · `self-developing agents` · `agent swarm` · `hive mind AI` · `AI workflow automation` · `LLMOps` · `prompt engineering` · `TDD agents` · `SPARC agents` · `GOAP agents` · `consensus agents`
