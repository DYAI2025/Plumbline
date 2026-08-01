#!/usr/bin/env bash
# CLI reachability contract: every shipped wrapper must be reachable by SOMETHING.
#
# Why this exists (council finding, 2026-07-30, verified against the tree): the
# PLUM-9…15 batch shipped four CLIs -- plumbline-plan-check, -runtime-hygiene,
# -remote-watch, -provenance-check -- that were fully implemented, fully tested, and
# invoked by NOTHING. `plumbline-enforce.sh` resolved exactly three CLIs; the four new
# wrappers appeared in zero hooks, and -runtime-hygiene appeared nowhere in the 867-line
# orchestrator either. The suite stayed green the whole time, because a test that
# exercises a CLI directly proves the CLI works -- never that anything calls it.
#
# That is this repo's own signature failure class ("exists in tests, never composed in
# prod") committed inside the batch meant to close that class. This test is the
# regression guard.
#
# SCOPE, stated honestly: C1-C8 are NAME-reachability checks (does the wrapper appear
# where its class requires?). They catch a wrapper nothing references. They do NOT by
# themselves prove the hook calls it -- that is C9, and the behavioural proof lives in
# test_pril_enforce_hook.sh, which reddens when the call sites are deleted.
#
# The contract: every `config/claude/bin/plumbline*` wrapper is declared in exactly one
# reachability class, and that class's requirement is checked:
#
#   enforced    invoked by a hook AND able to block -> the fail-closed core.
#   advisory    invoked by a hook, DEFAULT ON, but reports instead of blocking.
#               Runs without anyone remembering to type it; never halts the session.
#   workflow    invoked from a command file (the /agileteam or /concilium prompt).
#               Reachable only if an agent follows the prose.
#   standalone  a user-invoked tool, reachable because it is DOCUMENTED.
#
# `advisory` is a real class, not a softer `enforced`: for these four, "fail-closed"
# is deliberately NOT claimed. Keeping the distinction in the contract is what stops
# the batch-level overclaim ("all wired into a fail-closed Stop hook") from recurring.
#
# An undeclared wrapper FAILS. That is deliberate: adding a CLI must force a conscious
# decision about how anyone would ever reach it, instead of defaulting to "nothing does".
#
# Portability: bash-3.2 safe (NO $()-wrapped heredocs), shellcheck-clean.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"

# shellcheck source=lib.sh
. "$HERE/lib.sh"

echo "test_cli_wiring"

BIN_DIR="$REPO_DIR/config/claude/bin"
HOOK_DIR="$REPO_DIR/config/claude/hooks"
CMD_DIR="$REPO_DIR/config/claude/commands"

# --- The declared reachability classes ---------------------------------------
# Keep these lists in sync with reality. A wrapper in the wrong class fails loudly.
ENFORCED_CLIS="
plumbline-scope-check
plumbline-context-check
plumbline-reality-check
plumbline-redact
plumbline-start-check
"
ADVISORY_CLIS="
plumbline-plan-check
plumbline-runtime-hygiene
plumbline-remote-watch
plumbline-provenance-check
"
WORKFLOW_CLIS="
plumbline-run-ledger
plumbline-scope-update
"
STANDALONE_CLIS="
plumbline
plumbline-council-gui
plumbline-rule-ledger
"

in_list() { # in_list <needle> <list>
  local needle="$1" item
  for item in $2; do
    [ "$item" = "$needle" ] && return 0
  done
  return 1
}

referenced_in_dir() { # referenced_in_dir <name> <dir>
  [ -d "$2" ] || return 1
  grep -rlq -- "$1" "$2" 2>/dev/null
}

documented() { # documented <name>
  grep -q -- "$1" "$REPO_DIR/CLAUDE.md" 2>/dev/null && return 0
  grep -rlq -- "$1" "$REPO_DIR/docs" 2>/dev/null && return 0
  return 1
}

# --- C1: every wrapper on disk is declared in exactly one class ---------------
for path in "$BIN_DIR"/plumbline*; do
  [ -f "$path" ] || continue
  name="$(basename "$path")"
  hits=0
  in_list "$name" "$ENFORCED_CLIS" && hits=$((hits + 1))
  in_list "$name" "$ADVISORY_CLIS" && hits=$((hits + 1))
  in_list "$name" "$WORKFLOW_CLIS" && hits=$((hits + 1))
  in_list "$name" "$STANDALONE_CLIS" && hits=$((hits + 1))
  assert_eq "C1 $name is declared in exactly one reachability class" "1" "$hits"
done

# --- C2: every declared wrapper still exists ----------------------------------
for name in $ENFORCED_CLIS $ADVISORY_CLIS $WORKFLOW_CLIS $STANDALONE_CLIS; do
  assert_file "C2 declared wrapper $name exists on disk" "$BIN_DIR/$name"
done

# --- C3: an `enforced` or `advisory` CLI is actually invoked by a hook ---------
# This is the assertion the batch needed and did not have. It fails the moment a gate
# is shipped that nothing calls.
for name in $ENFORCED_CLIS $ADVISORY_CLIS; do
  if referenced_in_dir "$name" "$HOOK_DIR"; then
    _pass "C3 enforced $name is invoked by a hook"
  else
    _fail "C3 enforced $name is invoked by a hook (NO hook in config/claude/hooks/ references it; it is a gate nothing runs)"
  fi
  TESTS_RUN=$((TESTS_RUN + 1))
done

# --- C4: a `workflow` CLI is reachable from a command file --------------------
for name in $WORKFLOW_CLIS; do
  if referenced_in_dir "$name" "$CMD_DIR"; then
    _pass "C4 workflow $name is referenced by a command file"
  else
    _fail "C4 workflow $name is referenced by a command file"
  fi
  TESTS_RUN=$((TESTS_RUN + 1))
done

# --- C5: a `standalone` CLI is documented ------------------------------------
for name in $STANDALONE_CLIS; do
  if documented "$name"; then
    _pass "C5 standalone $name is documented (CLAUDE.md or docs/)"
  else
    _fail "C5 standalone $name is documented (CLAUDE.md or docs/): a user-invoked tool nobody can discover is unreachable"
  fi
  TESTS_RUN=$((TESTS_RUN + 1))
done

# --- C6: every enforced gate is ALSO described in the orchestrator ------------
# Being invoked by a hook makes a gate run; being named in the orchestrator makes it
# governable by a human reading the workflow. PLUM-11 was invoked by install.sh and
# named nowhere in agileteam.md -- reachable by accident, not by design.
for name in $ENFORCED_CLIS $ADVISORY_CLIS; do
  if referenced_in_dir "$name" "$CMD_DIR"; then
    _pass "C6 $name is described in a command file"
  else
    _fail "C6 $name is described in a command file (a gate that fires but is documented nowhere in the workflow is unauditable)"
  fi
  TESTS_RUN=$((TESTS_RUN + 1))
done

# --- C7: the enforce hook resolves every gate it is supposed to ---------------
# The hook resolves hard-coded names. If a gate is declared here but never reaches
# that list, C3 could still pass via an unrelated mention in another hook.
ENFORCE_HOOK="$HOOK_DIR/plumbline-enforce.sh"
assert_file "C7 enforce hook exists" "$ENFORCE_HOOK"
for name in $ENFORCED_CLIS $ADVISORY_CLIS; do
  case "$name" in
    plumbline-redact|plumbline-start-check) continue ;;  # other hooks own these
  esac
  if grep -q -- "$name" "$ENFORCE_HOOK" 2>/dev/null; then
    _pass "C7 $name is resolved by plumbline-enforce.sh"
  else
    _fail "C7 $name is resolved by plumbline-enforce.sh (declared as a gate but the Stop hook never resolves it)"
  fi
  TESTS_RUN=$((TESTS_RUN + 1))
done

# --- C8: advisory gates are DEFAULT ON and never block ------------------------
# The council's argument for default-ON was empirical: in this repo the one artifact
# a hook demanded sits at 9/9 features, while every prompt-suggested artifact sits at
# 0/9. These assertions pin that decision in code so it cannot be quietly reverted to
# opt-in, and pin that an advisory gate never emits a block.
for name in $ADVISORY_CLIS; do
  flag=""
  case "$name" in
    plumbline-plan-check) flag="PLUMBLINE_GATE_PLAN" ;;
    plumbline-runtime-hygiene) flag="PLUMBLINE_GATE_HYGIENE" ;;
    plumbline-remote-watch) flag="PLUMBLINE_GATE_REMOTE" ;;
    plumbline-provenance-check) flag="PLUMBLINE_GATE_PROVENANCE" ;;
  esac
  if grep -q -- "$flag" "$ENFORCE_HOOK" 2>/dev/null; then
    _pass "C8 $name has its opt-out flag $flag"
  else
    _fail "C8 $name has its opt-out flag $flag"
  fi
  TESTS_RUN=$((TESTS_RUN + 1))
done
# The default must be ON: the gate_enabled helper expands `:-1` (opt-out), never
# `:-0` (opt-in). Flipping that one character is exactly how default-ON would erode.
if grep -q ':-1}' "$ENFORCE_HOOK" 2>/dev/null; then
  _pass "C8 advisory gates default to ON (opt-out, not opt-in)"
else
  _fail "C8 advisory gates default to ON (opt-out, not opt-in): a governance check that is off by default is absent, not safe"
fi
TESTS_RUN=$((TESTS_RUN + 1))
# C9: INVOCATION, not mention. Measured 2026-07-30: deleting all four `run_advisory`
# call sites left this file 62/62 GREEN, because C3/C6/C7 only grep for the CLI NAME
# (still present in the resolve_* lines) and the old C8 grepped for `run_advisory`
# (still present as the function DEFINITION). A test that survives deletion of the
# behaviour it names does not cover it -- the exact class this suite exists to catch.
# The genuine guard is test_pril_enforce_hook.sh, which did redden.
for name in $ADVISORY_CLIS; do
  var=""
  case "$name" in
    plumbline-plan-check) var="plan_bin" ;;
    plumbline-runtime-hygiene) var="hygiene_bin" ;;
    plumbline-remote-watch) var="remote_bin" ;;
    plumbline-provenance-check) var="provenance_bin" ;;
  esac
  if grep -qE "run_advisory +\"\\\$$var\"" "$ENFORCE_HOOK" 2>/dev/null; then
    _pass "C9 $name is INVOKED via run_advisory \"\$$var\""
  else
    _fail "C9 $name is INVOKED via run_advisory \"\$$var\" (it is resolved but never called -- a gate that is looked up and never run)"
  fi
  TESTS_RUN=$((TESTS_RUN + 1))
done

# The call sites must outnumber the definition: >=4 invocations, definition excluded.
adv_calls="$(grep -cE '^[[:space:]]*run_advisory +"' "$ENFORCE_HOOK" 2>/dev/null || true)"
if [ "${adv_calls:-0}" -ge 4 ]; then
  _pass "C9 at least 4 run_advisory INVOCATIONS exist (found $adv_calls)"
else
  _fail "C9 at least 4 run_advisory INVOCATIONS exist (found ${adv_calls:-0}; the function definition alone does not count)"
fi
TESTS_RUN=$((TESTS_RUN + 1))

finish "test_cli_wiring"
