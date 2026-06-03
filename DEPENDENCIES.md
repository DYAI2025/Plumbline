# Dependencies & provenance — what is external, what ships, what is only referenced

Plumbline's creed is radical honesty, so the install boundary is stated plainly. There are
three classes. (Guarded by `config/claude/tests/test_dependencies_doc.sh`, which derives
the referenced MCP families dynamically — a new external reference cannot slip in
undocumented.)

---

## 1. EXTERNAL — prerequisites you provide; Plumbline does NOT install these

| Tool | Why | Installed by Plumbline? |
|------|-----|:--:|
| **Claude Code** | the runtime that loads the agents, commands, hooks, and skills | no |
| **python3** (+ **PyYAML**) | frontmatter validators, the Agent-Explorer extractor, the PRIL `lib/*.py`, the metrics harness, the `plumbline` CLI | no |
| **bash** | `install.sh`, the hooks, the test suite | no |
| **git** | self-update + normal version control | no |
| **jq** | hook registration in `~/.claude/settings.json` | no |
| **shellcheck** | CI only (lints the `.sh` tree) | no |

These are checked for, not installed. `install.sh` assumes they exist.

## 2. SHIPPED in this repo — the deliverable Plumbline installs

`config/claude/install.sh` makes these available under `~/.claude` (symlink, or `--copy`):

- **86 Claude Code subagent _prompts_** (markdown). A small Plumbline-engineered core
  (~16 — the `/agileteam` pipeline, the `/concilium` council, the core TDD/governance
  roles) plus ~70 **vendored from the claude-flow agent base** — we ship the **prompts
  only**, as a *tested-workload dependency*, **not** claude-flow's runtime. (See README.)
- **16 vendored skills** (`config/claude/skills/*/SKILL.md`).
- **The commands** (`config/claude/commands/*.md`) — `/agileteam`, `/concilium`,
  `/honest-status`, `/bench-oracle`, `/merge-when-true`, `/reflect`(-skills),
  `/plumbline-update`, `/agileteam-bench`.
- **The hooks** (`config/claude/hooks/*.sh`) — SessionStart + the sentinel-gated learning
  loop.
- **The PRIL runtime-integrity layer** — `config/claude/bin/*` (the `plumbline` CLI +
  `plumbline-reality-check`/`-scope-check`/`-context-check`/`-redact`/`-rule-ledger`/
  `-run-ledger`) and its Python in `config/claude/lib/*.py`.
- **The metrics harness + corpora** (`config/claude/metrics/*`, `metrics/`).

Plumbline ships **no MCP server** and is **not** packaged as a Claude Code plugin
(`/plugin install` does not apply) — installation is `install.sh` only.

## 3. REFERENCED but NOT shipped — external, optional MCP servers

Some agents' frontmatter lists MCP tools. **Plumbline ships and launches none of these
MCP servers.** Each must be installed **separately** by you; without it, those tool
references are simply **inert** — not an error, just unavailable. The agents that mention
them still load and run; they only lose the corresponding tool.

| MCP family (`mcp__<family>__*`) | What it is / who references it | Shipped? |
|---|---|:--:|
| **`mcp__claude-flow__`** | the [claude-flow](https://github.com/ruvnet/claude-flow) MCP — origin of the vendored agent base; most vendored agents reference it | no |
| **`mcp__flow-nexus__`** | Flow Nexus MCP — referenced by the `flow-nexus/*` vendored agents | no |
| **`mcp__github__`** | GitHub MCP — referenced by the `github/*` automation agents | no |
| **`mcp__gemini__`** | foreign-model MCP — `/concilium` may seat a Gemini body for cognitive diversity | no |
| **`mcp__openai__`** | foreign-model MCP — `/concilium` (OpenAI/Codex body) | no |
| **`mcp__qwen__`** | foreign-model MCP — `/concilium` (Qwen body) | no |
| **`mcp__sublinear-time-solver__`** | specialized solver MCP referenced by a few vendored agents | no |

*Naming note: some vendored agents write these with underscores (`mcp__claude_flow__`)
rather than hyphens (`mcp__claude-flow__`) — the same logical server either way; the
disclosure guard matches both forms.*

> **Council note:** the foreign-model families (`gemini`/`openai`/`qwen`) are the path to a
> genuinely diverse `/concilium`. Today they are **not wired**, so the council runs as a
> structured single-model critique (disclosed at runtime — see `concilium.md` Step 0.5).
> Roadmap **Wave C** adds an OpenRouter-backed, **fail-closed** multi-model council so this
> stops being an echo chamber. Until then: single-model, and honest about it.
