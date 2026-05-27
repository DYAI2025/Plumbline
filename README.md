# Claude Code Agent Definitions

Subagent definitions for [Claude Code](https://claude.com/claude-code), versioned
from `~/.claude/agents/`. Each `.md` file defines one agent via YAML frontmatter
plus a Markdown system prompt; Claude Code discovers them by name and can delegate
tasks to them.

**76 agents** across 20 categories (this is largely a [claude-flow](https://github.com/ruvnet/claude-flow)
agent pack, extended with standalone agents).

## Layout

| Directory | Count | Purpose |
|-----------|------:|---------|
| `core/` | 5 | Foundational roles: coder, planner, researcher, reviewer, tester |
| `github/` | 13 | PR / issue / repo / release / workflow automation |
| `flow-nexus/` | 9 | Flow Nexus platform agents (sandboxes, swarms, neural, payments…) |
| `templates/` | 9 | Reusable scaffold/template variants of other agents |
| `consensus/` | 7 | Distributed consensus protocols (byzantine, raft, gossip, crdt, quorum…) |
| `core/` … | | |
| `hive-mind/` | 5 | Collective intelligence / queen coordinator |
| `optimization/` | 5 | Load balancing, topology, performance, resource allocation, benchmarking |
| `sparc/` | 4 | SPARC phases: specification, pseudocode, architecture, refinement |
| `swarm/` | 3 | Swarm topology coordinators (hierarchical, mesh, adaptive) |
| `goal/` | 2 | GOAP planners: `goal-planner`, `code-goal-planner` |
| `reasoning/` | 2 | `reasoning-goal-planner` (claude-flow/MCP), `sublinear-goal-planner` |
| `testing/` | 2 | TDD (London school), production validation |
| `analysis/` `architecture/` `data/` `development/` `devops/` `documentation/` `neural/` `specialized/` | 1 each | Domain specialists |
| _(root)_ | 2 | `base-template-generator`, `code-reviewer` |

## Frontmatter contract

Every agent file **must** open with YAML frontmatter that includes, at the **top
level** (not nested under `metadata:`):

```yaml
---
name: my-agent              # unique across the whole collection
description: "One line on what it does and when to use it"
---
```

- `name` must be **unique** — duplicate names make delegation ambiguous.
- `description` is required at the top level and is how Claude Code decides relevance.
- If a `description` contains a colon-space (e.g. `Examples: <example>...`), **quote
  the whole value** or the YAML won't parse.

Two schema flavors coexist here and both are valid:

- **Standard template** — rich `triggers:` / `capabilities:` / `constraints:` /
  `behavior:` / `examples:` blocks (used by the domain specialists, 8 files).
- **claude-flow** — leaner frontmatter with `tools:`, `priority:`, and `npx
  claude-flow@alpha hooks` pre/post (14 files use a `tools:` list).

## Validate

Run this before committing to catch the common breakages (parse errors, missing
`description`, duplicate names):

```bash
python3 - <<'PY'
import re, glob, collections, yaml
names = collections.Counter(); bad = []; nodesc = []
for p in sorted(glob.glob("**/*.md", recursive=True)):
    m = re.match(r"^---\n(.*?)\n---", open(p, encoding="utf-8").read(), re.S)
    if not m: continue
    try: d = yaml.safe_load(m.group(1))
    except Exception as e: bad.append((p, str(e).splitlines()[0])); continue
    if not isinstance(d, dict): bad.append((p, "frontmatter not a mapping")); continue
    if "description" not in d: nodesc.append(p)
    if d.get("name"): names[d["name"]] += 1
dupes = {k: v for k, v in names.items() if v > 1}
print("parse failures:", bad or "none ✓")
print("missing description:", nodesc or "none ✓")
print("duplicate names:", dupes or "none ✓")
PY
```

## Notes

- These files are the live source for `~/.claude/agents/`. Edits here take effect
  the next time Claude Code scans agents (reload the session if needed).
- This is a nested git repo inside `~/.claude/`; the parent home repo ignores
  `.claude/`, so this repo is independent.

## License

[MIT](LICENSE) © 2026 DYAI2025. Portions derived from
[claude-flow](https://github.com/ruvnet/claude-flow) (MIT, © ruvnet).
