# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

**Plumbline** — a defense-in-depth Claude Code agent framework whose one obsession is
proving work is *actually* done, not that it merely *looks* done. It is three things in
one repo, and editing one usually means touching another:

1. **An agent collection** — ~87 subagent prompt files (`*.md` with YAML frontmatter)
   organized into category directories (`core/`, `agileteam/`, `github/`, `consensus/`,
   `sparc/`, `swarm/`, `hive-mind/`, `concilium/`, …). These are the deliverable.
2. **A vendored workflow + tooling tree** under `config/claude/` — the `/agileteam`
   orchestrator, `/concilium` council, vendored skills, hooks, the runtime-integrity
   layer (PRIL), and the metrics harness. This is what makes the agents *portable* and
   *governed*.
3. **An empirical instrument** — `metrics/` holds deterministic mutation-oracle corpora
   and the honest write-ups. The framework's central claims (e.g. "reaching the real
   test boundary is governed by model capability, not prompt cleverness") are *measured*
   here, not asserted. Preserve that intellectual honesty: never downgrade a RED result
   or fabricate a passing one — mark missing tooling `MISSING`.

Read `README.md` for the philosophy and `SETUP.md` for portability/web-bootstrap.

## Common commands

```bash
# Full CI check suite (frontmatter, metrics scripts, settings JSON, hooks,
# governance + PRIL tests, shellcheck). This is exactly what .github/workflows/ci.yml runs.
bash config/claude/tests/run_all.sh

# Run a single test module (each is a standalone bash script):
bash config/claude/tests/test_stop_hook.sh
bash config/claude/tests/test_true_line_governance.sh
bash config/claude/tests/test_product_canvas_gate.sh
bash config/claude/tests/test_runtime_integrity_layer.sh
bash config/claude/tests/test_web_bootstrap.sh

# Rebuild the Agent Explorer after ANY agent frontmatter change.
# Re-extracts frontmatter → bundles a single self-contained agent-explorer.html
# AND syncs docs/index.html (the GitHub Pages live demo) — they must never drift.
./build-explorer.sh            # needs python3+PyYAML, pnpm/node, artifacts-builder skill

# Install onto a machine: symlink repo → ~/.claude/agents, install commands/skills,
# and idempotently register the learning-loop Stop hook in ~/.claude/settings.json.
./config/claude/install.sh           # or: --copy  (Windows / prefer copies over symlinks)

# Benchmark harness (metrics/):
python3 config/claude/metrics/emit_run.py --corpus-id <id> --mode <core|full> \
  --metrics '{...}' --gate-outcomes '{...}' --human-overrides 0   # append a run to runs.jsonl
python3 config/claude/metrics/process_health.py                   # SPC + drift attribution

# PRIL runtime-integrity checks (bash wrappers over config/claude/lib/*.py):
config/claude/bin/plumbline-reality-check   # evidence-class / wired-in-prod gate
config/claude/bin/plumbline-scope-check
config/claude/bin/plumbline-context-check
config/claude/bin/plumbline-redact          # strip secrets/private data from output
```

Requirements: `git`, `bash`, `python3` (+ `PyYAML` for the explorer/validators), and
`jq` (for hook registration). CI also installs `shellcheck`.

## Agent frontmatter contract

Every agent is a markdown file beginning with a `---` YAML frontmatter block. The CI
validator (inside `run_all.sh`) enforces, across all `**/*.md` except `explorer/`:
- frontmatter parses as a YAML mapping,
- a `description:` key is present,
- `name:` values are **globally unique** (no duplicates across the whole tree).

Typical keys: `name`, `description`, `model` (usually `inherit`), `type`, `color`,
`capabilities`, `priority`, `hooks`. **Note:** per-agent `model:` frontmatter is *not*
applied by the current Claude Code runtime — only an explicit dispatch parameter takes
effect, so model control lives in the orchestrator, transparently. After editing any
agent, run `build-explorer.sh` and the frontmatter validator before committing.

## Core invariants (don't violate these)

- **True-Line governance** — Plumbline optimizes for staying true to confirmed human
  customer value, not for *finishing*. Green tests, completed tasks, and agent consensus
  are never sufficient on their own.
- **Reality Ledger** — every requirement carries an evidence class
  (`unit-fake → integration-fake → real-boundary-smoke → production-verified`). Anything
  touching I/O, a remote, an external API, or UI that stays `*-fake` is **RED regardless
  of green tests**, and that RED cannot be silently downgraded.
- **Wired-in-prod** — a real implementation with no test through the production
  composition root is *not satisfiable*. (This is the original incident the whole repo
  exists to prevent: "exists in tests, never composed in prod.")
- **Independence** — whoever writes code does not review it; whoever derives tests does
  not implement them. Review/security/validation must not echo the coder's reasoning.
- **Human gates stay** — requirements confirmation, the Product Canvas, product
  judgment, and persistent self-improvement always require explicit human sign-off.

## `/agileteam` command

`/agileteam <feature>` orchestrates an autonomous TDD team: Product Canvas gate →
requirements → spec-sanity audit → planning → coder/reviewer TDD loop → security →
validation → product-judgment → human acceptance → retrospective. Canonical source:
**`config/claude/commands/agileteam.md`** (other commands in that dir:
`agileteam-bench`, `concilium`, `honest-status`, `bench-oracle`, `reflect`,
`reflect-skills`).

**Bootstrap:** the command must exist at `~/.claude/commands/agileteam.md` to be
invokable. If it is missing, offer to run `./config/claude/install.sh`. Keep the global
copy and the vendored copy in sync (or use the symlink so there is a single source).

`metrics/runs.jsonl` is meant to accumulate on the `agileteam-improved` branch; `main`
stays the frozen baseline. A valid `/agileteam-bench` comparison must pin the agent
snapshot (a commit/tag) across both arms, since agent files keep evolving on `main`.

## Agent Learning Loop

Spec: **`config/claude/skills/agent-learning-loop.json`**. Run at the end of an
`/agileteam` session (after the DoD gate) or before ending any session with substantial
implementation/review work.

**Trigger (real):** a sentinel-gated **Stop hook**
(`config/claude/hooks/stop-learning-loop.sh`, registered in `~/.claude/settings.json` by
`install.sh`). It only fires when `~/.claude/.agileteam-reflection-pending` exists
(created by `/agileteam` Phase 3 after the DoD clear), so normal sessions are never
interrupted. It returns `decision: block`, runs the loop, then removes the sentinel, and
honours `stop_hook_active` (no infinite loops). Note: this repo's own
`.claude/settings.json` registers only a **SessionStart** hook
(`config/claude/hooks/session-start.sh`); the Stop hook lives in the *global* settings.

The loop: (1) analyse the session (git diff, test/QA failures, recurring `code-reviewer`
findings, repeated coder↔reviewer iterations); (2) derive concrete recurring failure
patterns → one proposed process rule each; (3) **interactive gate — never write
blindly**, show each proposed rule and its target level and only write on explicit `y`;
(4) persist approved rules with `skill-creator` (+ `writing-skills`) at the **narrowest
fitting level**:
- **A · Local** → this project's `CLAUDE.md`.
- **B · Global agents** → the relevant `~/.claude/agents/<agent>.md`. Show the exact diff
  first; re-run `./build-explorer.sh` afterwards.
- **C · New skill** → `~/.claude/skills/<name>/SKILL.md`, only for a genuinely new
  reusable capability.

Prefer A over B over C; always preview diffs before writing shared/global config.

## Working-in-this-repo protocol

- Use `/agileteam` (or its phased workflow) for feature/bugfix work; TDD first, **no
  production code before a failing test**; frequent atomic commits; no placeholder code.
- This is a **nested git repo** (the parent home repo ignores `.claude/`). Don't stash,
  switch branches, or touch worktrees unless asked — this workspace is multi-agent.
- After editing agents: rebuild the explorer, run the frontmatter validator, and run
  `bash config/claude/tests/run_all.sh` before committing.
- Evidence over vibes: back claims with code/tests/logs or an explicit assumption; mark
  absent tooling `MISSING` rather than pretending it passes.
