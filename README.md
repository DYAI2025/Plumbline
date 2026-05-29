# Claude Code Agent Definitions

Subagent definitions for [Claude Code](https://claude.com/claude-code), versioned
from `~/.claude/agents/`. Each `.md` file defines one agent via YAML frontmatter
plus a Markdown system prompt; Claude Code discovers them by name and can delegate
tasks to them.

**82 agents** across 21 categories (largely a [claude-flow](https://github.com/ruvnet/claude-flow)
agent pack, extended with standalone agents and the 6 `/agileteam` workflow roles).

## Layout

| Directory | Count | Purpose |
|-----------|------:|---------|
| `core/` | 5 | Foundational roles: coder, planner, researcher, reviewer, tester |
| `agileteam/` | 6 | `/agileteam` v3 roles: requirements-analyst, spec-auditor, product-owner, security-reviewer, retro-analyst, context-keeper |
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

## Agile team & learning loop

`config/claude/` vendors the **`/agileteam` v3** orchestrator (a defense-in-depth,
spec-driven multi-agent build workflow) and an evolutionary learning loop (see
`CLAUDE.md`). The full design is in `docs/agileteam-spec-v3.md`; metrics & meta-meta
governance in `docs/agileteam-governance.md`. Activate on a machine with:

```bash
./config/claude/install.sh    # transfers /agileteam + /agileteam-bench commands,
                              # the konfabulations-audit skill, and registers the Stop hook (needs jq)
```

> **New machine?** See **`SETUP.md`** for the full portability checklist: required
> toolchain (`jq`, `python3`, `git`), the expected skill plugins (and namespace caveat),
> optional integrations (kanban-md, claude-reflect), per-project gate tooling, and
> Windows notes.

> **Claude Code on the web ("co-work")?** No manual install needed. A SessionStart
> hook (`config/claude/hooks/session-start.sh`, registered in `.claude/settings.json`)
> runs `install.sh` automatically on session start so `/agileteam` + the vendored skill
> are ready. It is remote-only by default and never fatal — see `SETUP.md` §8.

What ships with v3:

- **6 workflow agents** in `agileteam/` (above) + the existing core/testing agents.
- **`config/claude/skills/konfabulations-audit/`** — claim-provenance gate, companion to
  the `ultrathink-craftsmanship` skill.
- **`config/claude/commands/agileteam-bench.md`** — the drift-vs-precision comparison.
- **`config/claude/metrics/`** — `emit_run.py` (run records → `metrics/runs.jsonl`) and
  `process_health.py` (SPC + component attribution → `metrics/process-health.md`). Pure
  stdlib, no dependencies.
- **Operating modes:** `/agileteam` defaults to **CORE** (runnable, safe baseline;
  Phase-4 self-modification locked). **FULL** unlocks autonomous evolution and is only
  permitted once a `metrics/runs.jsonl` baseline exists.

The learning loop is driven by a **sentinel-gated Stop hook**
(`config/claude/hooks/stop-learning-loop.sh`): `/agileteam` creates
`~/.claude/.agileteam-reflection-pending` after its DoD gate, and the hook then blocks
session-end so the retrospective runs. Normal sessions (no sentinel) are never touched.

### Testing the Stop hook

**Deterministic** (no session needed) — invoke the script the way the harness does:

```bash
H=config/claude/hooks/stop-learning-loop.sh
echo '{"stop_hook_active":false}' | bash "$H"                                   # → nothing (no sentinel)
touch ~/.claude/.agileteam-reflection-pending
echo '{"stop_hook_active":false}' | bash "$H"                                   # → {"decision":"block",...}
echo '{"stop_hook_active":true}'  | bash "$H"                                   # → nothing (loop guard)
rm -f ~/.claude/.agileteam-reflection-pending
```

**Live-fire** — `touch ~/.claude/.agileteam-reflection-pending`, then end your turn:
if the hook is active, Claude is auto-continued into the retrospective. Remember to
`rm -f` the sentinel afterwards (the retrospective does this automatically).

### Disabling

- Remove the sentinel: `rm -f ~/.claude/.agileteam-reflection-pending` (disarms the next stop).
- Permanently: delete the learning-loop entry from `hooks.Stop` in `~/.claude/settings.json`
  (review/edit hooks via the `/hooks` menu), or set `"disableAllHooks": true` to turn off
  all hooks.

## License

[MIT](LICENSE) © 2026 DYAI2025. Portions derived from
[claude-flow](https://github.com/ruvnet/claude-flow) (MIT, © ruvnet).
