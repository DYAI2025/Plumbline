---
description: Run the local claude-reflect retrospective discovery fallback over the current session/workspace evidence.
argument-hint: [focus]
allowed-tools: Read, Bash, Glob, Grep, TodoWrite, Skill
---

Use Skill `claude-reflect` to discover recurring improvement candidates for:

> $ARGUMENTS

Collect evidence from the plan, git diff, tests, reviewer findings, and user corrections.
Return candidate improvements only; do not persist any change without the explicit
Agent Learning Loop approval gate.
