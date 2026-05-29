# SETUP — making claude-agents (and /agileteam) work on a new system

This repo has two layers with very different portability:

- **Agent definitions** (`*.md`) — plain Markdown, zero dependencies. Portable anywhere
  Claude Code can read `~/.claude/agents/`.
- **The `/agileteam` v3 workflow** — portable, with a small required toolchain and
  vendored fallback skills/commands so a fresh co-worker install can run the complete
  setup without hunting for external skill packs.

---

## 1. Install the agents + commands

```bash
# From any checkout (recommended for co-workers):
git clone <this-repo> claude-agents
cd claude-agents
./config/claude/install.sh                       # symlinks repo -> ~/.claude/agents
                                                # add --copy on Windows / if you prefer copies

# If you already cloned directly to ~/.claude/agents, run the same command there:
# cd ~/.claude/agents && ./config/claude/install.sh
```

`install.sh` makes the repository available as `~/.claude/agents`, transfers every
vendored command (`/agileteam`, `/agileteam-bench`, `/reflect`, `/reflect-skills`) into
`~/.claude/commands/`, installs every vendored skill from `config/claude/skills/` into
`~/.claude/skills/`, and registers the learning-loop Stop hook in
`~/.claude/settings.json`. Open `/hooks` once (or restart Claude Code) afterwards.

## 2. Required toolchain

| Tool | Needed for | If missing |
|------|------------|------------|
| Claude Code | everything | hard requirement |
| `jq` | Stop-hook registration in install.sh | hook is skipped (add manually) |
| `python3` | metrics scripts + the README frontmatter validator | metrics/meta-meta unavailable |
| `git` | branch strategy, worktrees, provenance | required for the workflow |

## 3. Expected skills

`/agileteam` references these skills by name. This repo now vendors portable fallback
implementations for every referenced skill, and `install.sh` installs them automatically.
If you prefer richer external plugin packs, install them over the fallback names. **Note:**
on some systems external packs are namespaced (e.g.
`anthropic-skills:ultrathink-craftsmanship`, `superpowers:executing-plans`); the vendored
fallbacks keep the bare names resolvable for co-workers.

| Skill | Phase | Required? | If absent |
|-------|-------|-----------|-----------|
| `ai-native-prd-architect` | 0 | **vendored required** (PRD engine) | fallback installed automatically |
| `brainstorming` | 0 | **vendored required** (gap closing) | fallback installed automatically |
| `ultrathink-craftsmanship` | 0.5, Gate D | **vendored required** (sanity/judgment gates) | fallback installed automatically |
| `konfabulations-audit` | 0.5, Gate D | **shipped** (vendored here) | — installed by install.sh |
| `root-cause-tracing` | 2 (≥2× bug) | vendored recommended | fallback installed automatically |
| `systematic-debugging` | 3 (on fail) | vendored recommended | fallback installed automatically |
| `test-driven-development` | 2 | vendored recommended | fallback installed automatically |
| `executing-plans` | 2 | vendored recommended | fallback installed automatically |
| `writing-plans` | 1 | vendored recommended | fallback installed automatically |
| `writing-skills` | 4 | vendored required for FULL | fallback installed automatically |
| `skill-creator` | learning loop persistence | vendored required for approved skill writes | fallback installed automatically |
| `product-management:write-spec` | 0 (optional) | vendored optional | fallback installed automatically |
| `using-git-worktrees` | guard | vendored optional | fallback installed automatically |
| `defense-in-depth` | verification design | vendored anchor | fallback installed automatically |
| `testing-anti-patterns` | test review | vendored anchor | fallback installed automatically |
| `claude-reflect` | 4 discovery | vendored fallback | `/reflect` and `/reflect-skills` commands installed automatically |

## 4. Optional integrations

- **kanban-md** (`brew install antopolskiy/tap/kanban-md` or `go install`) — task
  backbone + terminal board. Without it, the orchestrator falls back to `TodoWrite`.
- **claude-reflect** — Phase-4 skill discovery. This repo ships local fallback
  `/reflect` and `/reflect-skills` commands plus a `claude-reflect` skill; richer
  external plugins can still replace them. Keep the human review gate on.

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

## 8. Claude Code on the web ("co-work") — zero-touch bootstrap

On the web, Claude Code clones this repo into a fresh, ephemeral container each
session with an **empty `~/.claude`**, and nobody runs `install.sh` by hand — so
`/agileteam` would otherwise be missing. A **SessionStart hook** closes that gap:

- `.claude/settings.json` (repo root) registers
  `config/claude/hooks/session-start.sh` as a SessionStart hook. Claude Code on
  the web auto-discovers project-level `.claude/settings.json`, so **no manual
  step is needed** — once this is on your default branch, every web session runs it.
- `session-start.sh` runs `install.sh --copy` so `/agileteam`, `/agileteam-bench`,
  the `konfabulations-audit` skill and the learning-loop Stop hook are present
  **before the agent loop starts** (it runs synchronously to avoid a race). On
  success it emits the SessionStart `reloadSkills` output so the freshly-copied
  skill and commands are usable in the **same** session (skill/command discovery
  otherwise runs before the hook finishes, deferring them to the next session).

Behaviour & safety:

- **Remote-only by default** — it acts only when `CLAUDE_CODE_REMOTE=true` (the web
  env). In a local session it is a no-op so your global `~/.claude` is untouched;
  run `install.sh` yourself there. Force it anywhere with `AGILETEAM_FORCE_BOOTSTRAP=1`.
- **Idempotent and never fatal** — always exits 0 and keeps stdout clean, so a setup
  hiccup can never abort your session.

> Note: this delivers the *vendored* pieces (commands + `konfabulations-audit`). The
> external skill packs in §3 are still installed separately; without them `/agileteam`
> runs in CORE mode (see §6).

## 9. Smoke test (verify before relying on it)

```bash
# the whole CI check suite (frontmatter, metrics, settings, stop hook, web bootstrap, shellcheck):
bash config/claude/tests/run_all.sh

# or individual pieces:
python3 -m py_compile config/claude/metrics/emit_run.py config/claude/metrics/process_health.py && echo PY_OK
python3 config/claude/metrics/emit_run.py --dry-run --metrics '{"first_pass":0.8}'
python3 -m unittest tests/test_claude_setup.py
./config/claude/install.sh --dry-run
# run the README "Validate" snippet to check agent frontmatter (parse / dupes / description)
```
