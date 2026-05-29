# SETUP — making claude-agents (and /agileteam) work on a new system

This repo has two layers with very different portability:

- **Agent definitions** (`*.md`) — plain Markdown, zero dependencies. Portable anywhere
  Claude Code can read `~/.claude/agents/`.
- **The `/agileteam` v3 workflow** — portable, but it expects a small toolchain and a
  set of skill plugins. Without them it still runs in **CORE** mode but degrades
  (skill-backed gates lose depth). Nothing breaks; capability narrows.

---

## 1. Install the agents + commands

```bash
# Put this repo where Claude Code looks for agents:
git clone <this-repo> ~/.claude/agents          # or symlink an existing checkout

# Transfer the commands + skill and register the Stop hook:
cd ~/.claude/agents
./config/claude/install.sh                       # add --copy on Windows / if you prefer copies
```

`install.sh` transfers `/agileteam` and `/agileteam-bench` into `~/.claude/commands/`,
copies the `konfabulations-audit` skill into `~/.claude/skills/`, and registers the
learning-loop Stop hook in `~/.claude/settings.json`. Open `/hooks` once (or restart
Claude Code) afterwards.

## 2. Required toolchain

| Tool | Needed for | If missing |
|------|------------|------------|
| Claude Code | everything | hard requirement |
| `jq` | Stop-hook registration in install.sh | hook is skipped (add manually) |
| `python3` | metrics scripts + the README frontmatter validator | metrics/meta-meta unavailable |
| `git` | branch strategy, worktrees, provenance | required for the workflow |

## 3. Expected skills

`/agileteam` references these skills by name. Install the plugin packs that provide
them. **Note:** on some systems they are namespaced (e.g.
`anthropic-skills:ultrathink-craftsmanship`, `superpowers:executing-plans`); if a bare
name does not resolve, adjust the reference or install under the expected name.

| Skill | Phase | Required? | If absent |
|-------|-------|-----------|-----------|
| `ai-native-prd-architect` | 0 | **required** (PRD engine) | Phase 0 falls back to hand-written PRD; lose REQ-ID rigor |
| `brainstorming` | 0 | **required** (gap closing) | gaps must be closed by manual Q&A |
| `ultrathink-craftsmanship` | 0.5, Gate D | **required** (sanity/judgment gates) | those gates degrade to inline reasoning |
| `konfabulations-audit` | 0.5, Gate D | **shipped** (vendored here) | — installed by install.sh |
| `root-cause-tracing` | 2 (≥2× bug) | recommended | use inline 5-Why manually |
| `systematic-debugging` | 3 (on fail) | recommended | inline debugging |
| `test-driven-development` | 2 | recommended | follow the inline TDD steps |
| `executing-plans` | 2 | recommended | inline per-task loop |
| `writing-plans` | 1 | recommended | plan format is described inline |
| `writing-skills` | 4 | required for FULL | needed to author new skills safely |
| `product-management:write-spec` | 0 (optional) | optional | skip; ai-native-prd-architect covers it |
| `using-git-worktrees` | guard | optional | create branches manually |

## 4. Optional integrations

- **kanban-md** (`brew install antopolskiy/tap/kanban-md` or `go install`) — task
  backbone + terminal board. Without it, the orchestrator falls back to `TodoWrite`.
- **claude-reflect** (plugin) — Phase-4 skill discovery (`/reflect`, `/reflect-skills`).
  Without it, do retrospective discovery manually. Keep its human review gate on.

## 5. Per-project gate tooling (resolved at run start)

Gate A/B need project-specific commands; the orchestrator asks for them at the start and
marks unknowns `MISSING` rather than inventing them:

```
TYPECHECK_CMD · LINT_CMD · UNIT_CMD · INTEGRATION_CMD · E2E_CMD
MUTATION_CMD (+ MUTATION_MIN) · COVERAGE_MIN
SAST_CMD · DEP_SCAN_CMD · SECRETS_CMD · HERMETIC_RUNNER
MAX_DEVREVIEW_LOOPS · MAX_QA_RETURNS
```

If a project has none of these set up, run in CORE mode and enable gates as you wire the
tooling in.

## 6. Modes — start CORE, graduate to FULL

- **CORE** (default): runnable, safe baseline. Phase-4 self-modification is **locked**.
- **FULL**: unlocks autonomous evolution (canary + auto-revert). Only permitted once a
  `metrics/runs.jsonl` baseline exists — otherwise the run warns and falls back to CORE.
  Collect a baseline first: `python3 config/claude/metrics/emit_run.py …` over a few runs,
  then `python3 config/claude/metrics/process_health.py`.

## 7. Cross-platform notes

- **macOS / Linux:** works as-is.
- **Windows:** `install.sh` is Bash → run under Git Bash or WSL; prefer `--copy` (symlinks
  are restricted). `python3` must be on PATH.

## 8. Smoke test (verify before relying on it)

```bash
python3 -m py_compile config/claude/metrics/emit_run.py config/claude/metrics/process_health.py && echo PY_OK
python3 config/claude/metrics/emit_run.py --dry-run --metrics '{"first_pass":0.8}'
# run the README "Validate" snippet to check agent frontmatter (parse / dupes / description)
```
