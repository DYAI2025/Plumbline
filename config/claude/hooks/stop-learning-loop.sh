#!/usr/bin/env bash
#
# Stop hook for the agent learning loop.
#
# Sentinel-gated: does nothing on normal responses. When an /agileteam run has
# cleared its DoD it creates ~/.claude/.agileteam-reflection-pending; this hook
# then returns a `decision: block` so the agent continues into the Agent
# Learning Loop retrospective (interactive y/n gate) instead of stopping.
#
# Safe by design: never exits non-zero (an accidental error must not block the
# agent), and honours `stop_hook_active` to avoid infinite stop loops.
#
input="$(cat 2>/dev/null)"

# If we already blocked once this stop cycle, let the agent finish.
active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)"
[ "$active" = "true" ] && exit 0

sentinel="$HOME/.claude/.agileteam-reflection-pending"
[ -f "$sentinel" ] || exit 0

reason="A /agileteam implementation passed its DoD gate but the Agent Learning Loop retrospective has not run yet. Run it NOW (see ~/.claude/agents/config/claude/skills/agent-learning-loop.json and the '## Agent Learning Loop' section of ~/.claude/agents/CLAUDE.md): analyse the session diff, test/QA failures and code-reviewer findings; present each proposed rule to the user via the interactive y/n gate; persist only approved rules (level A CLAUDE.md / B agent prompt / C new skill). When the retrospective is complete, remove the sentinel with: rm -f \"$sentinel\""

jq -cn --arg r "$reason" '{decision:"block", reason:$r}' 2>/dev/null \
  || printf '{"decision":"block","reason":"Run the Agent Learning Loop retrospective now, then: rm -f %s"}' "$sentinel"
exit 0
