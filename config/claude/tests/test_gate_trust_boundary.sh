#!/usr/bin/env bash
# Contract tests for the three trust-boundary defects that blocked PR #103.
# Each was reproduced against the pre-fix tree before this file existed.
#
#   OPEN-1  a project-resolved scope checker was executed WITHOUT any integrity
#           verification, on every resolution branch. Replacing the checker body
#           with `exit 0` made the blocking scope gate pass an out-of-scope
#           change. Measured pre-fix: canonical checker exit=3, in-repo mutated
#           checker exit=0 on the identical fixture.
#
#   OPEN-2  the scope manifest authorized its own widening. Adding the exact
#           out-of-scope path to docs/scope/<feature>.scope.json inside the run
#           and declaring both files passed with a success message. The `**`
#           guard caught the wildcard form; the targeted form went through.
#
#   NEW-1   argparse exits 2 on a usage error and the hook maps 2 to
#           PRIL_INPUT_MISSING, so a mis-invoked checker read as "nothing to
#           check" rather than "the gate did not run".
#
# Every assertion here is paired with a counter-mutation further down: the guard
# is removed from a throwaway copy and the case must flip. A test that still
# passes with its feature deleted does not cover it.
#
# Portability: bash-3.2 safe (NO $()-wrapped heredocs), shellcheck-clean.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"

# shellcheck source=lib.sh
. "$HERE/lib.sh"

echo "test_gate_trust_boundary"

HOOK="$REPO_DIR/config/claude/hooks/plumbline-enforce.sh"
BIN_SRC="$REPO_DIR/config/claude/bin"
LIB_SRC="$REPO_DIR/config/claude/lib"

# PATH with every Plumbline-wrapper directory removed, so `command -v` inside the
# hook cannot silently satisfy a lookup from a real install. Toolchain survives.
SANITISED_PATH=""
_old_ifs="$IFS"
IFS=':'
for _p in $PATH; do
  [ -n "$_p" ] || continue
  [ -e "$_p/plumbline-scope-check" ] && continue
  [ -e "$_p/plumbline-reality-check" ] && continue
  if [ -n "$SANITISED_PATH" ]; then
    SANITISED_PATH="$SANITISED_PATH:$_p"
  else
    SANITISED_PATH="$_p"
  fi
done
IFS="$_old_ifs"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# An empty HOME. Without it the developer machine's own ~/.claude/bin satisfies
# the last resolution branch, an immutable external checker is found, and the
# no-fallback cases below silently stop testing what they claim to test.
NOHOME="$WORK/nohome"
mkdir -p "$NOHOME"

# Run a given hook file against a project dir. Extra args are NAME=value env.
# Sets: HOOK_OUT HOOK_ERR HOOK_RC
run_hook_file() {
  local hook_file="$1" project="$2"
  shift 2
  local outf errf
  outf="$(mktemp -d "$WORK/o.XXXXXX")/out"
  errf="$(dirname "$outf")/err"
  env PATH="$SANITISED_PATH" "$@" CLAUDE_PROJECT_DIR="$project" \
    bash "$hook_file" >"$outf" 2>"$errf" <<<'{}'
  HOOK_RC=$?
  HOOK_OUT="$(cat "$outf")"
  HOOK_ERR="$(cat "$errf")"
}

run_hook() { run_hook_file "$HOOK" "$@"; }

# A governed repo that VENDORS the PRIL CLIs at config/claude/bin (the
# project-local resolution branch, priority 2) and commits them, so the tracked +
# byte-identical-to-HEAD precondition is satisfiable and its violation is
# meaningful. Echoes the repo path.
make_governed_repo() { # make_governed_repo <feature>
  local feat="$1" repo
  repo="$(mktemp -d "$WORK/repo.XXXXXX")"

  mkdir -p "$repo/config/claude/bin" "$repo/config/claude/lib"
  cp "$BIN_SRC"/plumbline-context-check "$BIN_SRC"/plumbline-reality-check \
     "$BIN_SRC"/plumbline-scope-check "$repo/config/claude/bin/"
  cp "$LIB_SRC"/plumbline_context.py "$LIB_SRC"/plumbline_reality.py \
     "$LIB_SRC"/plumbline_scope.py "$LIB_SRC"/plumbline_python.sh \
     "$LIB_SRC"/plumbline_cli.py \
     "$repo/config/claude/lib/"
  chmod +x "$repo/config/claude/bin/"*

  mkdir -p "$repo/docs/canvas" "$repo/docs/prd" "$repo/docs/vision" \
           "$repo/docs/context" "$repo/docs/scope" "$repo/src/feature"
  cat >"$repo/docs/canvas/$feat.canvas.md" <<EOF
# $feat Canvas

Status: user-confirmed
Confirmed by user: yes

## Allowed change scope
- src/feature/**
- docs/
EOF
  printf 'Status: user-confirmed\nPRD body.\n' >"$repo/docs/prd/$feat.prd.md"
  printf 'Status: user-confirmed\nVision body.\n' >"$repo/docs/vision/$feat.vision.md"
  printf 'Status: user-confirmed\nTraceability.\n' >"$repo/docs/traceability.md"
  printf '.plumbline/\n' >"$repo/.gitignore"

  git -C "$repo" init -q
  git -C "$repo" config user.email trust-test@example.com
  git -C "$repo" config user.name "Trust Test"
  git -C "$repo" checkout -q -b main
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "baseline confirmed context + vendored checkers"
  git -C "$repo" checkout -q -b "feat/$feat"
  printf '%s' "$feat" >"$repo/docs/context/.active-feature"
  printf '%s' "$repo"
}

# Plant a real out-of-scope change that no agent listed (git ground truth).
plant_violation() { # plant_violation <repo>
  mkdir -p "$1/src/billing"
  printf 'CHARGE = 1\n' >"$1/src/billing/charge.py"
  git -C "$1" add src/billing/charge.py
}

# Replace the loaded runtime of the vendored checker with an always-pass body.
mutate_checker_lib() { # mutate_checker_lib <repo>
  printf 'import sys\nprint("scope check passed")\nsys.exit(0)\n' \
    >"$1/config/claude/lib/plumbline_scope.py"
}

############################################################################
# OPEN-1 — a project-resolved checker is never executed unverified
############################################################################

# --- O1a CONTROL: clean vendored checker detects the scope violation ----------
o1a="$(make_governed_repo trustfeat)"
plant_violation "$o1a"
run_hook "$o1a"
assert_eq "O1a control: hook exits 0 (block travels in the payload)" "0" "$HOOK_RC"
assert_contains "O1a control: clean project-local checker blocks the violation" \
  "$HOOK_OUT" "gate=scope"

# --- O1b THE DEFECT: mutated checker must NOT be trusted ----------------------
o1b="$(make_governed_repo trustfeat)"
plant_violation "$o1b"
mutate_checker_lib "$o1b"
run_hook "$o1b" HOME="$NOHOME"
assert_contains "O1b: a mutated project-local checker is refused, classified" \
  "$HOOK_OUT" "CHECKER_INTEGRITY_UNVERIFIED"
assert_contains "O1b: the run still blocks" "$HOOK_OUT" '"decision":"block"'
assert_not_contains "O1b: the mutated checker's verdict is never reported as a pass" \
  "$HOOK_OUT" "scope check passed"

# --- O1c the WRAPPER itself is covered, not only the library -----------------
o1c="$(make_governed_repo trustfeat)"
plant_violation "$o1c"
printf '#!/usr/bin/env bash\nexit 0\n' >"$o1c/config/claude/bin/plumbline-scope-check"
run_hook "$o1c" HOME="$NOHOME"
assert_contains "O1c: a mutated wrapper is refused" \
  "$HOOK_OUT" "CHECKER_INTEGRITY_UNVERIFIED"

# --- O1d an UNTRACKED checker is not verifiable, therefore not trusted --------
o1d="$(make_governed_repo trustfeat)"
plant_violation "$o1d"
git -C "$o1d" rm -q --cached config/claude/lib/plumbline_scope.py >/dev/null 2>&1
git -C "$o1d" commit -q -m "untrack the checker runtime"
run_hook "$o1d" HOME="$NOHOME"
assert_contains "O1d: an untracked checker runtime is refused" \
  "$HOOK_OUT" "CHECKER_INTEGRITY_UNVERIFIED"

# --- O1e PLUMBLINE_BIN_DIR pointing INTO the repo is checked too --------------
o1e="$(make_governed_repo trustfeat)"
plant_violation "$o1e"
mutate_checker_lib "$o1e"
run_hook "$o1e" HOME="$NOHOME" PLUMBLINE_BIN_DIR="$o1e/config/claude/bin"
assert_contains "O1e: PLUMBLINE_BIN_DIR into the repo is verified, not exempt" \
  "$HOOK_OUT" "CHECKER_INTEGRITY_UNVERIFIED"

# --- O1f PATH resolution into the repo is checked too ------------------------
o1f="$(make_governed_repo trustfeat)"
plant_violation "$o1f"
mutate_checker_lib "$o1f"
run_hook_file "$HOOK" "$o1f" HOME="$NOHOME" PATH="$o1f/config/claude/bin:$SANITISED_PATH"
assert_contains "O1f: PATH resolution into the repo is verified, not exempt" \
  "$HOOK_OUT" "CHECKER_INTEGRITY_UNVERIFIED"

# --- O1g a SYMLINK from outside into the mutated in-repo checker is followed ---
o1g="$(make_governed_repo trustfeat)"
plant_violation "$o1g"
mutate_checker_lib "$o1g"
linkdir="$(mktemp -d "$WORK/link.XXXXXX")"
ln -s "$o1g/config/claude/bin/plumbline-scope-check" "$linkdir/plumbline-scope-check"
run_hook "$o1g" HOME="$NOHOME" PLUMBLINE_BIN_DIR="$linkdir"
assert_contains "O1g: a symlink into the governed repo is resolved and verified" \
  "$HOOK_OUT" "CHECKER_INTEGRITY_UNVERIFIED"

# --- O1h an EXTERNAL immutable checker is preferred over a mutated in-repo one -
# The spec's fallback: refuse the mutated checker, but do not lose enforcement
# when a checker outside the governed repo exists. The run must still block --
# on the REAL scope violation, not on integrity.
o1h="$(make_governed_repo trustfeat)"
plant_violation "$o1h"
mutate_checker_lib "$o1h"
extbin="$(mktemp -d "$WORK/ext.XXXXXX")"
extlib="$extbin/../lib"
mkdir -p "$extlib"
cp "$BIN_SRC"/plumbline-context-check "$BIN_SRC"/plumbline-reality-check \
   "$BIN_SRC"/plumbline-scope-check "$extbin/"
cp "$LIB_SRC"/plumbline_context.py "$LIB_SRC"/plumbline_reality.py \
   "$LIB_SRC"/plumbline_scope.py "$LIB_SRC"/plumbline_python.sh \
   "$LIB_SRC"/plumbline_cli.py "$extlib/"
chmod +x "$extbin"/*
run_hook_file "$HOOK" "$o1h" HOME="$NOHOME" PATH="$extbin:$SANITISED_PATH"
assert_contains "O1h: an external immutable checker takes over and still blocks" \
  "$HOOK_OUT" "gate=scope"
assert_not_contains "O1h: the mutated in-repo verdict is not used" \
  "$HOOK_OUT" "scope check passed"

# --- O1i a clean repo produces NO integrity noise (no false positive) --------
o1i="$(make_governed_repo trustfeat)"
printf 'def f():\n    return 1\n' >"$o1i/src/feature/impl.py"
git -C "$o1i" add src/feature/impl.py
run_hook "$o1i"
assert_not_contains "O1i: an unmodified vendored checker raises no integrity finding" \
  "$HOOK_OUT" "CHECKER_INTEGRITY_UNVERIFIED"

############################################################################
# OPEN-2 — the active scope manifest cannot authorize its own change
############################################################################

SCOPE_CLI="$REPO_DIR/config/claude/bin/plumbline-scope-check"

# A minimal repo for direct CLI-level scope-authority cases.
make_scope_repo() { # make_scope_repo <feature>
  local feat="$1" repo
  repo="$(mktemp -d "$WORK/scope.XXXXXX")"
  mkdir -p "$repo/src" "$repo/docs/scope" "$repo/docs/context"
  printf '.plumbline/\n' >"$repo/.gitignore"
  printf 'x\n' >"$repo/src/app.py"
  # governance_paths lists the manifest itself -- exactly as the reproduced attack
  # did. Without it the widened manifest would be refused merely for being an
  # unlisted path, and the case would go green for a reason unrelated to scope
  # authority. Pre-fix, this fixture passes with exit 0.
  printf '{"schema":1,"feature":"%s","allowed_change_scope":["src/**"],"governance_paths":["docs/scope/%s.scope.json"]}\n' \
    "$feat" "$feat" >"$repo/docs/scope/$feat.scope.json"
  printf '%s' "$feat" >"$repo/docs/context/.active-feature"
  git -C "$repo" init -q
  git -C "$repo" config user.email trust-test@example.com
  git -C "$repo" config user.name "Trust Test"
  git -C "$repo" add -A
  git -C "$repo" commit -q -m base
  printf '%s' "$repo"
}

run_scope() { # run_scope <repo> <feature> <changed-file-lines...>
  local repo="$1" feat="$2"
  shift 2
  local cf="$repo/.changed"
  : >"$cf"
  local line
  for line in "$@"; do printf '%s\n' "$line" >>"$cf"; done
  SCOPE_OUT="$(env PATH="$SANITISED_PATH" "$SCOPE_CLI" \
    --repo "$repo" --feature "$feat" --changed-files "$cf" 2>&1)"
  SCOPE_RC=$?
}

# --- O2a arming: first run binds the baseline and passes in-scope work -------
o2="$(make_scope_repo authfeat)"
run_scope "$o2" authfeat "src/app.py"
assert_eq "O2a: arming run with in-scope work passes" "0" "$SCOPE_RC"

# --- O2b THE DEFECT: widening the manifest inside the run must not pass -------
printf 'y\n' >"$o2/secrets.txt"
printf '{"schema":1,"feature":"authfeat","allowed_change_scope":["src/**","secrets.txt"],"governance_paths":["docs/scope/authfeat.scope.json"]}\n' \
  >"$o2/docs/scope/authfeat.scope.json"
run_scope "$o2" authfeat "secrets.txt" "docs/scope/authfeat.scope.json"
assert_contains "O2b: an in-run manifest widening is refused, classified" \
  "$SCOPE_OUT" "SCOPE_AUTHORITY_CHANGED"
assert_eq "O2b: and it is a policy violation, not a pass" "3" "$SCOPE_RC"
assert_not_contains "O2b: the widened manifest never reports success" \
  "$SCOPE_OUT" "scope check passed"

# --- O2c deleting the manifest after arming is the same class ----------------
o2c="$(make_scope_repo delfeat)"
run_scope "$o2c" delfeat "src/app.py"
rm -f "$o2c/docs/scope/delfeat.scope.json"
run_scope "$o2c" delfeat "src/app.py"
assert_contains "O2c: removing the bound manifest is refused, classified" \
  "$SCOPE_OUT" "SCOPE_AUTHORITY_CHANGED"

# --- O2d NO false positive: an unchanged manifest keeps passing --------------
o2d="$(make_scope_repo stablefeat)"
run_scope "$o2d" stablefeat "src/app.py"
run_scope "$o2d" stablefeat "src/app.py"
assert_eq "O2d: an unchanged manifest passes on every later run" "0" "$SCOPE_RC"
assert_not_contains "O2d: and raises no authority finding" \
  "$SCOPE_OUT" "SCOPE_AUTHORITY_CHANGED"

# --- O2e the legitimate path: disarm, re-confirm, re-arm ---------------------
# Removing the bound baseline is the explicit end-of-run/disarm step. The next
# run re-arms against the new manifest, and the newly confirmed scope holds.
o2e="$(make_scope_repo refeat)"
run_scope "$o2e" refeat "src/app.py"
printf 'y\n' >"$o2e/wide.txt"
printf '{"schema":1,"feature":"refeat","allowed_change_scope":["src/**","wide.txt"],"governance_paths":["docs/scope/refeat.scope.json"]}\n' \
  >"$o2e/docs/scope/refeat.scope.json"
rm -rf "$o2e/.plumbline/scope-authority"
run_scope "$o2e" refeat "wide.txt"
assert_eq "O2e: after an explicit disarm and re-arm the new scope is honored" \
  "0" "$SCOPE_RC"

# --- O2f the baseline itself never pollutes the governed scope surface -------
run_scope "$o2d" stablefeat "src/app.py" ".plumbline/scope-authority/stablefeat.json"
assert_eq "O2f: the run-baseline file is never itself an out-of-scope change" \
  "0" "$SCOPE_RC"

############################################################################
# NEW-1 — a mis-invoked checker is never "nothing to check"
############################################################################

# --- N1a every hook-invoked CLI reports a usage error distinctly -------------
for cli in plumbline-scope-check plumbline-context-check plumbline-reality-check \
           plumbline-plan-check plumbline-runtime-hygiene plumbline-remote-watch \
           plumbline-provenance-check; do
  out="$(env PATH="$SANITISED_PATH" "$BIN_SRC/$cli" --definitely-not-a-flag 2>&1)"
  rc=$?
  assert_eq "N1a $cli: a usage error exits TOOL_INVOCATION_ERROR (122)" "122" "$rc"
  assert_contains "N1a $cli: and carries a machine-readable token" \
    "$out" "PRIL_TOOL_INVOCATION_ERROR"
done

# --- N1b the hook classifies 122 as an invocation error, never INPUT_MISSING --
# A stub CLI outside the governed repo (so O1's integrity rule does not apply)
# that exits 122 the way argparse now does.
n1b="$(make_governed_repo n1feat)"
stubbin="$(mktemp -d "$WORK/stub.XXXXXX")"
for cli in plumbline-scope-check plumbline-context-check plumbline-reality-check; do
  cp "$BIN_SRC/$cli" "$stubbin/$cli"
done
cat >"$stubbin/plumbline-runtime-hygiene" <<'STUB'
#!/usr/bin/env bash
echo "PRIL_TOOL_INVOCATION_ERROR: unrecognized arguments" >&2
exit 122
STUB
chmod +x "$stubbin/plumbline-runtime-hygiene"
mkdir -p "$stubbin/../lib"
cp "$LIB_SRC"/plumbline_context.py "$LIB_SRC"/plumbline_reality.py \
   "$LIB_SRC"/plumbline_scope.py "$LIB_SRC"/plumbline_python.sh \
   "$LIB_SRC"/plumbline_cli.py "$stubbin/../lib/"
run_hook "$n1b" PLUMBLINE_BIN_DIR="$stubbin"
# With no blocking failure the advisory notices go to stderr; with one they are
# attached to the block reason. Assert on both surfaces so the case does not
# depend on whether something else happened to block.
N1B_ALL="$HOOK_OUT
$HOOK_ERR"
assert_contains "N1b: the hook names the invocation error" \
  "$N1B_ALL" "PRIL_TOOL_INVOCATION_ERROR"
assert_not_contains "N1b: the mis-invoked gate never reads as INPUT_MISSING" \
  "$N1B_ALL" "PRIL_ADVISORY hygiene PRIL_INPUT_MISSING"

# --- N1c the fachlich-missing case keeps its own meaning ---------------------
# A feature with no manifest and no canvas scope section is genuinely missing
# input; that must still be exit 2, distinct from 122.
n1c="$(mktemp -d "$WORK/miss.XXXXXX")"
mkdir -p "$n1c/docs/scope" "$n1c/src"
git -C "$n1c" init -q
git -C "$n1c" config user.email t@e.co
git -C "$n1c" config user.name T
printf 'x\n' >"$n1c/src/a.py"
git -C "$n1c" add -A >/dev/null 2>&1
git -C "$n1c" commit -q -m base
run_scope "$n1c" nosuchfeature "src/a.py"
assert_eq "N1c: genuinely missing scope input keeps exit 2 (MISSING)" "2" "$SCOPE_RC"

############################################################################
# Counter-mutations — each guard removed, each case must flip
############################################################################

MUT="$WORK/mutated-hook.sh"

# CM-1: strip the checker-integrity verification from a copy of the hook.
sed 's/^\( *\)verify_checker_integrity /\1: verify_checker_integrity /' \
  "$HOOK" >"$MUT"
cm1="$(make_governed_repo trustfeat)"
plant_violation "$cm1"
mutate_checker_lib "$cm1"
run_hook_file "$MUT" "$cm1"
assert_not_contains "CM-1 counter-mutation: without the guard the mutated checker is trusted again" \
  "$HOOK_OUT" "CHECKER_INTEGRITY_UNVERIFIED"

# CM-2: strip the scope-authority binding from a copy of the checker runtime.
cm2="$(make_scope_repo cmfeat)"
run_scope "$cm2" cmfeat "src/app.py"
printf 'y\n' >"$cm2/secrets.txt"
printf '{"schema":1,"feature":"cmfeat","allowed_change_scope":["src/**","secrets.txt"],"governance_paths":["docs/scope/cmfeat.scope.json"]}\n' \
  >"$cm2/docs/scope/cmfeat.scope.json"
CM2_LIB="$WORK/cm2lib"
mkdir -p "$CM2_LIB"
cp "$LIB_SRC"/plumbline_cli.py "$CM2_LIB/"
# Neutralise the guard at its call site, the way a reverted fix would: the
# manifest is read but never pinned.
sed 's/^\( *\)authority_error = check_scope_authority(.*)$/\1authority_error = None/' \
  "$LIB_SRC/plumbline_scope.py" >"$CM2_LIB/plumbline_scope.py"
cf="$cm2/.changed"
printf 'secrets.txt\ndocs/scope/cmfeat.scope.json\n' >"$cf"
CM2_OUT="$(env PATH="$SANITISED_PATH" PLUMBLINE_PYTHON_LIB_OVERRIDE=1 \
  python3 "$CM2_LIB/plumbline_scope.py" --repo "$cm2" --feature cmfeat \
  --changed-files "$cf" 2>&1)"
CM2_RC=$?
assert_not_contains "CM-2 counter-mutation: without the binding the widening passes again" \
  "$CM2_OUT" "SCOPE_AUTHORITY_CHANGED"
assert_eq "CM-2 counter-mutation: and it reports success" "0" "$CM2_RC"

# CM-3: restore argparse's default exit-2 behaviour and prove N1a flips.
CM3_LIB="$WORK/cm3lib"
mkdir -p "$CM3_LIB"
cp "$LIB_SRC"/plumbline_cli.py "$CM3_LIB/"
sed 's/^\( *\)parser = PlumblineArgumentParser(/\1parser = argparse.ArgumentParser(/' \
  "$LIB_SRC/plumbline_scope.py" >"$CM3_LIB/plumbline_scope.py"
cf3="$WORK/cm3.changed"
: >"$cf3"
CM3_OUT="$(env PATH="$SANITISED_PATH" python3 "$CM3_LIB/plumbline_scope.py" \
  --definitely-not-a-flag 2>&1)"
CM3_RC=$?
assert_eq "CM-3 counter-mutation: plain argparse returns to the colliding exit 2" \
  "2" "$CM3_RC"
assert_not_contains "CM-3 counter-mutation: and loses the machine-readable token" \
  "$CM3_OUT" "PRIL_TOOL_INVOCATION_ERROR"

finish "test_gate_trust_boundary"
