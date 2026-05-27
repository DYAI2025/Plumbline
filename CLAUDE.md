# CLAUDE.md — claude-agents

Guidance for Claude Code when working in this repository (`~/.claude/agents`, the
versioned home of the Claude Code subagent collection). See `README.md` for the
agent layout and frontmatter contract.

This repo also vendors an agile multi-agent workflow and an evolutionary learning
loop under `config/claude/`. The rules below are a **protocol you follow when
working in this workspace** — they are documentation, not a harness-enforced hook.

## Agile Team Command

The `/agileteam` command orchestrates an autonomous TDD team (planner → coder/
reviewer loop → QA + production-validator gate → retrospective). Its canonical,
versioned source lives at **`config/claude/commands/agileteam.md`**.

**Bootstrap (first use on a machine):** the command must exist at
`~/.claude/commands/agileteam.md` to be invokable. If it is missing, transfer it:

```bash
./config/claude/install.sh          # symlink (repo edits stay live)
# or: ./config/claude/install.sh --copy
```

`install.sh` also idempotently registers the learning-loop **Stop hook** in
`~/.claude/settings.json` (needs `jq`), preserving any existing hooks — so the real
trigger is reproducible on a fresh machine.

When working in this repo, if `~/.claude/commands/agileteam.md` is absent, offer to
run `install.sh`. Keep the global copy and the vendored copy in sync — after editing
one, mirror to the other (or use the symlink so there is a single source of truth).

## Agent Learning Loop

Spec: **`config/claude/skills/agent-learning-loop.json`**. Run this loop at the end
of an `/agileteam` session (after the DoD gate) or before ending any session with
substantial implementation/review work.

**Trigger (real):** a **Stop hook** (`config/claude/hooks/stop-learning-loop.sh`,
registered in `~/.claude/settings.json`) fires when the session tries to end. It is
**sentinel-gated**: it only acts when `~/.claude/.agileteam-reflection-pending` exists
(created by `/agileteam` Phase 3 after the DoD clear), so normal sessions are never
interrupted. When armed it returns `decision: block` so the agent runs the loop below,
then removes the sentinel. The hook honours `stop_hook_active` (no infinite loops).

1. **Analyse** the session: the git diff, test/QA failures, recurring `code-reviewer`
   findings, error patterns in logs, and tasks that needed multiple coder↔reviewer
   iterations.
2. **Derive** concrete, recurring failure patterns → one proposed process rule each.
3. **Interactive gate — never write blindly.** For each proposed rule, show:
   ```
   Gefundenes Fehlermuster: <…>
   Vorgeschlagene permanente Optimierung in <CLAUDE.md | Agent-Prompt | neuer Skill>: <…>
   Möchtest du diese Verbesserung permanent für zukünftige Sessions implementieren? (y/n)
   ```
   Only on explicit **`y`** is anything written; `n` discards that item.
4. **Persist** approved rules with `skill-creator` (+ `writing-skills`) at the
   narrowest fitting level:
   - **A · Local** → the project's `CLAUDE.md` (project-specific coding guidelines).
   - **B · Global agents** → the relevant `~/.claude/agents/<agent>.md` system prompt,
     so the dev/QA subagents improve across sessions. Show the exact diff first;
     re-run `./build-explorer.sh` afterwards to refresh `agent-explorer.html`.
   - **C · New skill** → `~/.claude/skills/<name>/SKILL.md`, only for a genuinely new
     reusable capability.

## System Integration

While working in this workspace I adhere to this protocol:
- Use `/agileteam` (or its phased workflow) for feature/bugfix work; TDD first, no
  production code before a failing test; frequent atomic commits; no placeholder code.
- Run the Agent Learning Loop at session end / after a DoD clear, with the interactive
  gate — **no silent writes** to `CLAUDE.md`, `~/.claude/agents/`, or `~/.claude/skills/`.
- Prefer level A over B over C; always preview diffs before writing shared/global config.
- This is a nested git repo; the parent home repo ignores `.claude/`. After agent edits,
  rebuild the explorer and validate frontmatter (see `README.md`) before committing.
