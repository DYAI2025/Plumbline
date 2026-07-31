#!/usr/bin/env bash
# PLUM-11 contract tests: generated agent runtime state must not contaminate a
# product repository or its scope gates.
#
# Measured starting state (2026-07-30, this very repository): `.claude-flow/`
# (604K of neural/policy/session state) was present, UNTRACKED and NOT IGNORED.
# The enforce hook's change surface includes `git ls-files --others
# --exclude-standard`, and the 2026-07-08 C4 exemption only covers paths that are
# gitignored AND untracked -- so an unignored dropping lands in the surface and
# blocks every scope check without a single line of feature work. The pilot had the
# worse variant: 11 such files (~7.1 MB) actually TRACKED.
#
# Contract:
#   * ephemeral runtime state is reliably ignored (AC-1);
#   * curated insight lives only under an explicit export path (AC-2);
#   * the ignore rules are added non-destructively -- foreign .gitignore content is
#     never rewritten or deleted (AC-3);
#   * already-tracked runtime files are detected and get a NON-destructive fix
#     (printed `git rm -r --cached`, never executed for you) (AC-4);
#   * repeated session activity leaves the product work tree unchanged (AC-5);
#   * the scope guard stays green with droppings present (AC-6).
#
# Portability: bash-3.2 safe (NO $()-wrapped heredocs), shellcheck-clean.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"

# shellcheck source=lib.sh
. "$HERE/lib.sh"

echo "test_runtime_hygiene"

HYG_BIN="$REPO_DIR/config/claude/bin/plumbline-runtime-hygiene"
SCOPE_BIN="$REPO_DIR/config/claude/bin/plumbline-scope-check"
# Manifest-governed fixtures below are ARMED immediately before each scope-check
# invocation: this module's subject is not run-trust binding (that is
# test_run_trust_anchor.sh), and an unarmed manifest run now blocks by design.
TRUST_BIN="$REPO_DIR/config/claude/bin/plumbline-run-trust"
export PLUMBLINE_STATE_DIR="${PLUMBLINE_STATE_DIR:-$(mktemp -d)}"
arm_fixture() { # arm_fixture <repo> <feature>
  "$TRUST_BIN" disarm --repo "$1" --feature "$2" >/dev/null 2>&1
  "$TRUST_BIN" arm --repo "$1" --feature "$2" >/dev/null 2>&1
}


WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

assert_file "runtime-hygiene CLI exists" "$HYG_BIN"

new_repo() {
  local name="$1" repo
  repo="$WORK/$name"
  mkdir -p "$repo"
  git -C "$repo" init -q
  git -C "$repo" config user.email hygiene-test@example.com
  git -C "$repo" config user.name "Hygiene Test"
  printf 'src\n' >"$repo/README.md"
  git -C "$repo" add README.md
  git -C "$repo" commit -q -m "product baseline"
  printf '%s' "$repo"
}

run_hyg() {
  local repo="$1"
  shift
  local outf="$WORK/hyg.out"
  "$HYG_BIN" --repo "$repo" "$@" >"$outf" 2>&1
  HYG_RC=$?
  HYG_OUT="$(cat "$outf")"
}

# Simulate one agent session writing its runtime droppings.
write_droppings() {
  local repo="$1" run="$2"
  mkdir -p "$repo/.claude-flow/neural" "$repo/.claude/homunculus" "$repo/.swarm"
  printf '{"run": %s}\n' "$run" >"$repo/.claude-flow/neural/stats.json"
  printf '{"run": %s}\n' "$run" >"$repo/.claude-flow/policy.json"
  printf '{"run": %s}\n' "$run" >"$repo/.claude/homunculus/observations.json"
  printf 'db-%s\n' "$run" >"$repo/.swarm/memory.db"
}

# ---------------------------------------------------------------------------
# D. Detection.
# ---------------------------------------------------------------------------

repo="$(new_repo unignored)"
write_droppings "$repo" 1
run_hyg "$repo"
assert_eq "unignored runtime state is a violation (exit 3)" "3" "$HYG_RC"
assert_contains "unignored: names the claude-flow directory" \
  "$HYG_OUT" ".claude-flow/"
assert_contains "unignored: names the homunculus directory" \
  "$HYG_OUT" ".claude/homunculus/"
assert_contains "unignored: classifies the finding" "$HYG_OUT" "unignored"
assert_contains "unignored: names the fix" "$HYG_OUT" "--fix-ignore"

# A clean repo is clean: the check must not invent findings.
repo="$(new_repo clean)"
run_hyg "$repo"
assert_eq "no runtime state present: exit 0" "0" "$HYG_RC"

# ---------------------------------------------------------------------------
# F. --fix-ignore is additive and non-destructive.
# ---------------------------------------------------------------------------

repo="$(new_repo fixignore)"
printf '# project rules\nnode_modules/\n*.tmp\n' >"$repo/.gitignore"
git -C "$repo" add .gitignore
git -C "$repo" commit -q -m "project gitignore"
write_droppings "$repo" 1
run_hyg "$repo" --fix-ignore
assert_eq "--fix-ignore resolves the findings (exit 0)" "0" "$HYG_RC"
assert_contains "--fix-ignore writes a marked block" \
  "$(cat "$repo/.gitignore")" "plumbline"
assert_contains "--fix-ignore keeps the project's own rules" \
  "$(cat "$repo/.gitignore")" "node_modules/"
assert_contains "--fix-ignore keeps the project's comment" \
  "$(cat "$repo/.gitignore")" "# project rules"
assert "runtime files still exist on disk (nothing deleted)" \
  "[ -f '$repo/.claude-flow/neural/stats.json' ]"
assert_eq "work tree is clean again after the fix" \
  "" "$(git -C "$repo" status --porcelain -- .claude-flow .claude .swarm)"

# Idempotent: a second run adds nothing and stays green.
before="$(cat "$repo/.gitignore")"
run_hyg "$repo" --fix-ignore
assert_eq "second --fix-ignore stays green" "0" "$HYG_RC"
assert_eq "second --fix-ignore does not duplicate the block" \
  "$before" "$(cat "$repo/.gitignore")"

# A repo with no .gitignore at all gets one created (still additive).
repo="$(new_repo nogitignore)"
write_droppings "$repo" 1
run_hyg "$repo" --fix-ignore
assert_eq "--fix-ignore creates a missing .gitignore" "0" "$HYG_RC"
assert_file "created .gitignore exists" "$repo/.gitignore"

# ---------------------------------------------------------------------------
# T. Already-tracked runtime files: detected, fix is printed, never executed.
# ---------------------------------------------------------------------------

repo="$(new_repo tracked)"
write_droppings "$repo" 1
git -C "$repo" add -A -f
git -C "$repo" commit -q -m "accidentally tracked runtime state"
run_hyg "$repo"
assert_eq "tracked runtime state is a violation (exit 3)" "3" "$HYG_RC"
assert_contains "tracked: classified distinctly from unignored" \
  "$HYG_OUT" "tracked"
assert_contains "tracked: offers the non-destructive untrack command" \
  "$HYG_OUT" "rm -r --cached"
assert_contains "tracked: says the working copy is kept" "$HYG_OUT" "keeps the file"

# --fix-ignore must NOT untrack anything by itself, and must not go green while a
# tracked runtime file is still in the index.
run_hyg "$repo" --fix-ignore
assert_eq "--fix-ignore does not silently resolve a tracked file" "3" "$HYG_RC"
assert_eq "--fix-ignore did not untrack the file" \
  ".claude-flow/neural/stats.json" \
  "$(git -C "$repo" ls-files -- .claude-flow/neural/stats.json)"
assert "tracked runtime file still on disk after --fix-ignore" \
  "[ -f '$repo/.claude-flow/neural/stats.json' ]"

# After the operator applies the printed fix, the check goes green.
git -C "$repo" rm -r --cached -q .claude-flow .claude .swarm
git -C "$repo" commit -q -m "untrack runtime state (non-destructive)"
run_hyg "$repo"
assert_eq "after the printed fix the repo is clean" "0" "$HYG_RC"
assert "untracked-but-kept file still on disk" \
  "[ -f '$repo/.claude-flow/neural/stats.json' ]"

# ---------------------------------------------------------------------------
# C. Curated export path vs ephemeral state (AC-2).
# ---------------------------------------------------------------------------

repo="$(new_repo curated)"
mkdir -p "$repo/docs/.claude-flow"
printf '{"session": 1}\n' >"$repo/docs/.claude-flow/state.json"
run_hyg "$repo"
assert_eq "runtime state inside a curated dir is a violation" "3" "$HYG_RC"
assert_contains "curated violation is classified" "$HYG_OUT" "curated"
assert_contains "curated violation names the path" \
  "$HYG_OUT" "docs/.claude-flow"

# ---------------------------------------------------------------------------
# S. Session operation leaves the product work tree unchanged (AC-5, AC-6).
# ---------------------------------------------------------------------------

repo="$(new_repo sessions)"
mkdir -p "$repo/docs/scope" "$repo/src/feature"
cat >"$repo/docs/scope/feat.scope.json" <<'EOF'
{"schema": 1, "feature": "feat", "allowed_change_scope": ["src/feature/**"]}
EOF
git -C "$repo" add -A
git -C "$repo" commit -q -m "feature scope"
# Install the ignore rules BEFORE the first session runs -- that is the real
# ordering, and it proves --fix-ignore is prophylactic rather than reactive.
run_hyg "$repo" --fix-ignore
assert_eq "prophylactic --fix-ignore on a still-clean repo succeeds" "0" "$HYG_RC"
assert_file "prophylactic --fix-ignore created .gitignore" "$repo/.gitignore"
git -C "$repo" add .gitignore
git -C "$repo" commit -q -m "ignore runtime state"

# Three consecutive "sessions" write and rewrite their state.
write_droppings "$repo" 1
status_after_1="$(git -C "$repo" status --porcelain)"
write_droppings "$repo" 2
write_droppings "$repo" 3
status_after_3="$(git -C "$repo" status --porcelain)"
assert_eq "session 1 leaves the work tree unchanged" "" "$status_after_1"
assert_eq "sessions 1-3 leave the work tree unchanged" "" "$status_after_3"
run_hyg "$repo"
assert_eq "hygiene stays green across repeated sessions" "0" "$HYG_RC"

# AC-6: the scope guard stays green with droppings present. The real feature edit
# is in scope; the droppings are gitignored+untracked, so C4 exempts them visibly.
printf 'x = 1\n' >"$repo/src/feature/app.py"
changed="$WORK/changed.txt"
git -C "$repo" ls-files --others --exclude-standard >"$changed"
printf 'src/feature/app.py\n' >>"$changed"
scope_out="$WORK/scope.out"
arm_fixture "$repo" feat
"$SCOPE_BIN" --repo "$repo" --feature feat --changed-files "$changed" \
  >"$scope_out" 2>&1
scope_rc=$?
assert_eq "scope guard passes with runtime droppings present" "0" "$scope_rc"
assert_not_contains "droppings are not reported as out-of-scope" \
  "$(cat "$scope_out")" "outside Allowed change scope"

# ---------------------------------------------------------------------------
# X. Extra patterns and classified input failures.
# ---------------------------------------------------------------------------

repo="$(new_repo extrapattern)"
mkdir -p "$repo/.myagent"
printf 'state\n' >"$repo/.myagent/state.json"
run_hyg "$repo"
assert_eq "an unknown tool's directory is not invented as a finding" "0" "$HYG_RC"
run_hyg "$repo" --pattern '.myagent/'
assert_eq "--pattern extends the known runtime patterns" "3" "$HYG_RC"
assert_contains "--pattern finding names the directory" "$HYG_OUT" ".myagent/"

run_hyg "$WORK/does-not-exist"
assert_eq "missing repo: exit 2" "2" "$HYG_RC"

notrepo="$WORK/notarepo"
mkdir -p "$notrepo"
run_hyg "$notrepo"
assert_eq "not a git repo: exit 2" "2" "$HYG_RC"

# ---------------------------------------------------------------------------
# R. This repository must stay clean (the live 2026-07-30 finding).
# ---------------------------------------------------------------------------

assert "Plumbline's own .gitignore ignores .claude-flow/" \
  "git -C '$REPO_DIR' check-ignore -q .claude-flow/probe.json"
assert "Plumbline's own .gitignore ignores .swarm/" \
  "git -C '$REPO_DIR' check-ignore -q .swarm/probe.db"

finish "test_runtime_hygiene"
