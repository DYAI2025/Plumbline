#!/usr/bin/env bash
# Lean default install (Option 1). The ~35 agents whose distinctive function is calling an
# external heavy MCP server (claude-flow / flow-nexus / sublinear-time-solver) are OMITTED by
# default, so a plain Plumbline install never pulls the user toward that MCP stack (the token
# cost) and never carries those agents in the loader's registry. The MCP-free governance core
# (/agileteam pipeline, /concilium, PRIL roles, base agents) is ALWAYS installed. The coupled
# set installs only with --with-flow-agents. Nothing is deleted from the repo — this is purely
# an install-time selection. See README "Quickstart" and DEPENDENCIES.md.
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config/claude/tests/lib.sh
. "$DIR/lib.sh"
REPO="$(cd "$DIR/../../.." && pwd)"
INSTALL="$REPO/config/claude/install.sh"

# Stable fixtures: two MCP-coupled agents, one core agent (in a subdir), one ROOT-level agent.
COUPLED1="flow-nexus/sandbox.md"
COUPLED2="swarm/adaptive-coordinator.md"
CORE1="core/coder.md"
ROOTAGENT="code-reviewer.md"

# Fixture sanity — if these drift, the test below is meaningless, so assert the premise.
assert "fixture: coupled agent references a heavy MCP family" \
  "grep -qE 'mcp__(claude[-_]flow|flow[-_]nexus|sublinear)' '$REPO/$COUPLED1'"
assert "fixture: core agent is MCP-free" \
  "! grep -qE 'mcp__' '$REPO/$CORE1'"

# 1. DEFAULT install (agents only, copy into an isolated CLAUDE_HOME) OMITS the coupled agents,
#    KEEPS the MCP-free core + root agent, and does NOT mount the non-agent repo tree (config/).
TMP1="$(mktemp -d)"; TMP2=""
trap 'rm -rf "$TMP1" "$TMP2"' EXIT
CLAUDE_HOME="$TMP1" bash "$INSTALL" --copy --no-hook --no-commands --no-skills --no-bin >/dev/null 2>&1

assert "default install OMITS coupled agent ($COUPLED1)"   "[ ! -e '$TMP1/agents/$COUPLED1' ]"
assert "default install OMITS coupled agent ($COUPLED2)"   "[ ! -e '$TMP1/agents/$COUPLED2' ]"
assert "default install KEEPS core agent ($CORE1)"         "[ -e '$TMP1/agents/$CORE1' ]"
assert "default install KEEPS root agent ($ROOTAGENT)"     "[ -e '$TMP1/agents/$ROOTAGENT' ]"
assert "default install does NOT mount non-agent config/"  "[ ! -e '$TMP1/agents/config' ]"

# 2. --with-flow-agents INCLUDES the coupled agents (and still the MCP-free core).
TMP2="$(mktemp -d)"
CLAUDE_HOME="$TMP2" bash "$INSTALL" --copy --with-flow-agents --no-hook --no-commands --no-skills --no-bin >/dev/null 2>&1

assert "--with-flow-agents INCLUDES coupled agent ($COUPLED1)" "[ -e '$TMP2/agents/$COUPLED1' ]"
assert "--with-flow-agents still KEEPS core agent ($CORE1)"    "[ -e '$TMP2/agents/$CORE1' ]"

finish "lean default install tests"
