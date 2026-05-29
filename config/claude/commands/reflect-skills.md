---
description: Run the local claude-reflect skill-discovery fallback and propose skill/rule changes without applying them.
argument-hint: [focus]
allowed-tools: Read, Bash, Glob, Grep, TodoWrite, Skill
---

Use Skill `claude-reflect`, then Skill `writing-skills`, to inspect whether the current
session reveals a reusable skill improvement or a new skill need for:

> $ARGUMENTS

Output evidence-backed proposals with expected benefit, overlap check, and rollback note.
Do not create or edit skills until the user explicitly approves each item.
