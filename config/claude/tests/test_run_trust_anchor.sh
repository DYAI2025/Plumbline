#!/usr/bin/env bash
# Counter-examples for the immutable run-trust anchor.
#
# The previous slice bound trust to two things the judged party still controls:
#
#   T1  checker integrity was measured against the CURRENT HEAD. Modify the
#       checker, COMMIT it, and it is tracked and byte-identical to HEAD -- so
#       the guard trusts it. "Change the checker, commit, then be trusted" was an
#       unintended maintenance path and is explicitly not supported.
#
#   T2  the scope baseline lived INSIDE the controlled repository and was created
#       by the gate itself. An artifact the judged party can rewrite, and that
#       the judge will happily re-create, is not an anchor.
#
#   T3  the first Stop run WAS the arming moment, so a widening performed before
#       it was simply adopted as the baseline and never seen.
#
# The anchor closes all three: it is written OUTSIDE the repository by an
# externally installed, verified Plumbline CLI, before implementation writes
# begin, and every gate reads it and only reads it.
#
# Portability: bash-3.2 safe (NO $()-wrapped heredocs), shellcheck-clean.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"

# shellcheck source=lib.sh
. "$HERE/lib.sh"

echo "test_run_trust_anchor"

HOOK="$REPO_DIR/config/claude/hooks/plumbline-enforce.sh"
BIN_SRC="$REPO_DIR/config/claude/bin"
LIB_SRC="$REPO_DIR/config/claude/lib"

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

NOHOME="$WORK/nohome"
STATE="$WORK/state"
mkdir -p "$NOHOME" "$STATE"

# The EXTERNALLY INSTALLED Plumbline. It lives outside every governed repo, so a
# candidate checkout can never nominate itself as the trusted runtime.
EXT="$WORK/ext"
mkdir -p "$EXT/bin" "$EXT/lib"
cp "$BIN_SRC"/* "$EXT/bin/" 2>/dev/null
cp "$LIB_SRC"/* "$EXT/lib/" 2>/dev/null
chmod +x "$EXT/bin/"*

run_hook_file() {
  local hook_file="$1" project="$2"
  shift 2
  local outf errf
  outf="$(mktemp -d "$WORK/o.XXXXXX")/out"
  errf="$(dirname "$outf")/err"
  # $EXT/bin is on PATH so the EXTERNAL plumbline-run-trust is resolvable -- the
  # realistic posture. Project-local still wins for the scope/context/reality
  # checkers (resolution priority 2), so the in-repo checker is still the one
  # under test.
  env PATH="$EXT/bin:$SANITISED_PATH" HOME="$NOHOME" PLUMBLINE_STATE_DIR="$STATE" "$@" \
    CLAUDE_PROJECT_DIR="$project" bash "$hook_file" >"$outf" 2>"$errf" <<<'{}'
  # RC and stderr are captured for symmetry with the other hook drivers; this
  # module asserts on the decision payload. Exported so an interactive debug run
  # can read them without editing the driver.
  HOOK_RC=$?
  HOOK_OUT="$(cat "$outf")"
  HOOK_ERR="$(cat "$errf")"
  export HOOK_RC HOOK_ERR
}
run_hook() { run_hook_file "$HOOK" "$@"; }

# Arm a run through the EXTERNAL CLI. This is the only supported way to create an
# anchor; no gate may do it.
arm_anchor() { # arm_anchor <repo> <feature> [extra env...]
  local repo="$1" feat="$2"
  shift 2
  ARM_OUT="$(env PATH="$SANITISED_PATH" HOME="$NOHOME" PLUMBLINE_STATE_DIR="$STATE" "$@" \
    "$EXT/bin/plumbline-run-trust" arm --repo "$repo" --feature "$feat" 2>&1)"
  ARM_RC=$?
}

anchor_file() { # anchor_file <repo> <feature>
  env PATH="$SANITISED_PATH" HOME="$NOHOME" PLUMBLINE_STATE_DIR="$STATE" \
    "$EXT/bin/plumbline-run-trust" path --repo "$1" --feature "$2" 2>/dev/null
}

# A governed repo that vendors the CLIs (the project-local resolution branch) and
# carries a confirmed manifest.
make_repo() { # make_repo <feature>
  local feat="$1" repo
  repo="$(mktemp -d "$WORK/repo.XXXXXX")"
  mkdir -p "$repo/config/claude/bin" "$repo/config/claude/lib" \
           "$repo/docs/canvas" "$repo/docs/prd" "$repo/docs/vision" \
           "$repo/docs/context" "$repo/docs/scope" "$repo/src/feature"
  cp "$BIN_SRC"/plumbline-context-check "$BIN_SRC"/plumbline-reality-check \
     "$BIN_SRC"/plumbline-scope-check "$BIN_SRC"/plumbline-run-trust \
     "$repo/config/claude/bin/"
  cp "$LIB_SRC"/plumbline_context.py "$LIB_SRC"/plumbline_reality.py \
     "$LIB_SRC"/plumbline_scope.py "$LIB_SRC"/plumbline_python.sh \
     "$LIB_SRC"/plumbline_cli.py "$LIB_SRC"/plumbline_run_trust.py \
     "$repo/config/claude/lib/" 2>/dev/null
  chmod +x "$repo/config/claude/bin/"*
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
  printf '{"schema":1,"feature":"%s","allowed_change_scope":["src/feature/**","docs/**"],"governance_paths":["docs/scope/%s.scope.json"]}\n' \
    "$feat" "$feat" >"$repo/docs/scope/$feat.scope.json"
  git -C "$repo" init -q
  git -C "$repo" config user.email trust@example.com
  git -C "$repo" config user.name "Trust"
  git -C "$repo" checkout -q -b main
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "confirmed intake + vendored checkers"
  git -C "$repo" checkout -q -b "feat/$feat"
  printf '%s' "$feat" >"$repo/docs/context/.active-feature"
  printf '%s' "$repo"
}

plant_violation() { # plant_violation <repo>
  mkdir -p "$1/src/billing"
  printf 'CHARGE = 1\n' >"$1/src/billing/charge.py"
  git -C "$1" add src/billing/charge.py
}

run_scope() { # run_scope <repo> <feature> <changed lines...>
  local repo="$1" feat="$2"
  shift 2
  local cf="$repo/.changed"
  : >"$cf"
  local line
  for line in "$@"; do printf '%s\n' "$line" >>"$cf"; done
  SCOPE_OUT="$(env PATH="$SANITISED_PATH" HOME="$NOHOME" PLUMBLINE_STATE_DIR="$STATE" \
    "$EXT/bin/plumbline-scope-check" --repo "$repo" --feature "$feat" \
    --changed-files "$cf" 2>&1)"
  SCOPE_RC=$?
}

############################################################################
# T1 — the commit-based checker bypass
############################################################################

t1="$(make_repo t1feat)"
arm_anchor "$t1" t1feat
assert_eq "T1 arming: the external CLI arms the run" "0" "$ARM_RC"
assert_file "T1 arming: the anchor exists OUTSIDE the repo" "$(anchor_file "$t1" t1feat)"
assert "T1 arming: the anchor is not inside the governed repo" \
  "case '$(anchor_file "$t1" t1feat)' in '$t1'/*) false ;; *) true ;; esac"

# Control: with the armed, unmodified checker a real violation blocks.
plant_violation "$t1"
run_hook "$t1"
assert_contains "T1 control: an armed run blocks a real scope violation" \
  "$HOOK_OUT" "gate=scope"

# THE BYPASS: rewrite the checker to trivially succeed, then COMMIT it so it is
# tracked and byte-identical to the CURRENT HEAD.
t1b="$(make_repo t1feat)"
arm_anchor "$t1b" t1feat
printf 'import sys\nprint("scope check passed")\nsys.exit(0)\n' \
  >"$t1b/config/claude/lib/plumbline_scope.py"
git -C "$t1b" add config/claude/lib/plumbline_scope.py
git -C "$t1b" commit -q -m "checker now trivially succeeds"
assert "T1 precondition: the mutated checker IS byte-identical to current HEAD" \
  "git -C '$t1b' diff --quiet HEAD -- config/claude/lib/plumbline_scope.py"
plant_violation "$t1b"
run_hook "$t1b"
assert_contains "T1: a committed checker mutation is still refused" \
  "$HOOK_OUT" "CHECKER_INTEGRITY_UNVERIFIED"
assert_contains "T1: the run blocks" "$HOOK_OUT" '"decision":"block"'
assert_not_contains "T1: the trivially-succeeding checker never reports a pass" \
  "$HOOK_OUT" "scope check passed"

############################################################################
# T2 — the baseline is not rewritable, and never self-healing
############################################################################

t2="$(make_repo t2feat)"
arm_anchor "$t2" t2feat
assert_eq "T2 arming: legitimate baseline bound" "0" "$ARM_RC"
run_scope "$t2" t2feat "src/feature/impl.py"
assert_eq "T2 control: in-scope work under the bound baseline passes" "0" "$SCOPE_RC"

# Widen the manifest with an unconfirmed path.
printf 'y\n' >"$t2/secrets.txt"
printf '{"schema":1,"feature":"t2feat","allowed_change_scope":["src/feature/**","docs/**","secrets.txt"],"governance_paths":["docs/scope/t2feat.scope.json"]}\n' \
  >"$t2/docs/scope/t2feat.scope.json"
# ...and forge the in-repo remnant the previous slice used as its authority.
mkdir -p "$t2/.plumbline/scope-authority"
printf '{"schema":1,"feature":"t2feat","path":"docs/scope/t2feat.scope.json","digest":"forged"}\n' \
  >"$t2/.plumbline/scope-authority/t2feat.json"
run_scope "$t2" t2feat "secrets.txt" "docs/scope/t2feat.scope.json"
assert_contains "T2: a widened manifest is refused against the bound baseline" \
  "$SCOPE_OUT" "RUN_TRUST_BASELINE_CHANGED"
assert_not_contains "T2: forging the in-repo remnant does not authorize anything" \
  "$SCOPE_OUT" "scope check passed"

# Deleting the anchor must block, and must NOT be silently re-created.
t2b="$(make_repo t2bfeat)"
arm_anchor "$t2b" t2bfeat
a2="$(anchor_file "$t2b" t2bfeat)"
rm -f "$a2"
run_scope "$t2b" t2bfeat "src/feature/impl.py"
assert_contains "T2: a deleted baseline blocks, classified" \
  "$SCOPE_OUT" "RUN_TRUST_BASELINE_MISSING"
assert "T2: the gate NEVER re-creates the baseline it just missed" \
  "[ ! -f '$a2' ]"

# A corrupt anchor is refused, not repaired.
t2c="$(make_repo t2cfeat)"
arm_anchor "$t2c" t2cfeat
a3="$(anchor_file "$t2c" t2cfeat)"
printf 'not json at all {{{\n' >"$a3"
run_scope "$t2c" t2cfeat "src/feature/impl.py"
assert_contains "T2: an unreadable baseline blocks, classified" \
  "$SCOPE_OUT" "RUN_TRUST_BASELINE_UNREADABLE"
assert_contains "T2: the corrupt anchor is left exactly as found" \
  "$(cat "$a3")" "not json at all"

############################################################################
# T3 — widening BEFORE the first Stop gate is still caught
############################################################################

t3="$(make_repo t3feat)"
arm_anchor "$t3" t3feat
assert_eq "T3 arming: run armed with the confirmed manifest" "0" "$ARM_RC"
# Widen BEFORE any gate has ever run for this feature.
printf 'y\n' >"$t3/wide.txt"
printf '{"schema":1,"feature":"t3feat","allowed_change_scope":["src/feature/**","docs/**","wide.txt"],"governance_paths":["docs/scope/t3feat.scope.json"]}\n' \
  >"$t3/docs/scope/t3feat.scope.json"
run_scope "$t3" t3feat "wide.txt"
assert_contains "T3: a widening performed before the first gate run is caught" \
  "$SCOPE_OUT" "RUN_TRUST_BASELINE_CHANGED"
assert_eq "T3: and it is a policy violation, not a pass" "3" "$SCOPE_RC"

############################################################################
# Anchor discipline — self-arming, absence, read-only
############################################################################

# A candidate checkout may not nominate itself as the trusted runtime.
t4="$(make_repo t4feat)"
ARM_OUT="$(env PATH="$SANITISED_PATH" HOME="$NOHOME" PLUMBLINE_STATE_DIR="$STATE" \
  "$t4/config/claude/bin/plumbline-run-trust" arm --repo "$t4" --feature t4feat 2>&1)"
ARM_RC=$?
assert_contains "A1: a candidate checkout cannot arm itself" \
  "$ARM_OUT" "TRUST_ANCHOR_SELF_HOSTED"
assert_not_contains "A1: and no anchor is produced" "$ARM_OUT" "armed"

# No anchor at all -> classified block, never a silent pass and never an autoarm.
t5="$(make_repo t5feat)"
plant_violation "$t5"
run_hook "$t5"
assert_contains "A2: an unarmed run blocks with TRUST_ANCHOR_MISSING" \
  "$HOOK_OUT" "TRUST_ANCHOR_MISSING"
assert "A2: the gate does not arm the run itself" \
  "[ ! -f '$(anchor_file "$t5" t5feat)' ]"

# Re-arming an already-armed run is refused: an anchor is bound once.
t6="$(make_repo t6feat)"
arm_anchor "$t6" t6feat
first="$(cat "$(anchor_file "$t6" t6feat)")"
printf '{"schema":1,"feature":"t6feat","allowed_change_scope":["src/feature/**","docs/**","late.txt"],"governance_paths":["docs/scope/t6feat.scope.json"]}\n' \
  >"$t6/docs/scope/t6feat.scope.json"
arm_anchor "$t6" t6feat
assert "A3: re-arming an armed run is refused" "[ '$ARM_RC' -ne 0 ]"
assert_eq "A3: and the bound baseline is untouched" \
  "$first" "$(cat "$(anchor_file "$t6" t6feat)")"
assert_contains "A3: the refusal is classified" "$ARM_OUT" "TRUST_ANCHOR_ALREADY_ARMED"

# Explicit disarm is the supported way to end a run.
env PATH="$SANITISED_PATH" HOME="$NOHOME" PLUMBLINE_STATE_DIR="$STATE" \
  "$EXT/bin/plumbline-run-trust" disarm --repo "$t6" --feature t6feat >/dev/null 2>&1
assert "A4: disarm removes the anchor" "[ ! -f '$(anchor_file "$t6" t6feat)' ]"
arm_anchor "$t6" t6feat
assert_eq "A4: and the run can then be re-armed against the new manifest" "0" "$ARM_RC"

############################################################################
# Counter-mutations — each with a precondition that it actually applied
############################################################################

MUT_HOOK="$WORK/mutated-hook.sh"
sed 's|^verify_run_trust_anchor() {.*|verify_run_trust_anchor() { return 0; }\
_orig_verify_run_trust_anchor() {|' "$HOOK" >"$MUT_HOOK"
bash -n "$MUT_HOOK" || _fail "CM-T1: the mutated hook must still parse"
assert "CM-T1 precondition: the mutation actually changed the hook" \
  "! cmp -s '$HOOK' '$MUT_HOOK'"
cmt1="$(make_repo cmt1feat)"
arm_anchor "$cmt1" cmt1feat
printf 'import sys\nprint("scope check passed")\nsys.exit(0)\n' \
  >"$cmt1/config/claude/lib/plumbline_scope.py"
git -C "$cmt1" add config/claude/lib/plumbline_scope.py
git -C "$cmt1" commit -q -m "committed mutation"
plant_violation "$cmt1"
run_hook_file "$MUT_HOOK" "$cmt1"
assert_not_contains "CM-T1: without the anchor check the committed mutation is trusted again" \
  "$HOOK_OUT" "CHECKER_INTEGRITY_UNVERIFIED"

CM_LIB="$WORK/cmlib"
mkdir -p "$CM_LIB"
cp "$LIB_SRC"/plumbline_cli.py "$LIB_SRC"/plumbline_run_trust.py "$CM_LIB/" 2>/dev/null
sed 's/^\( *\)trust_error = verify_run_trust_for_scope(.*)$/\1trust_error = None/' \
  "$LIB_SRC/plumbline_scope.py" >"$CM_LIB/plumbline_scope.py"
assert "CM-T2 precondition: the mutation actually changed the checker" \
  "! cmp -s '$LIB_SRC/plumbline_scope.py' '$CM_LIB/plumbline_scope.py'"
cmt2="$(make_repo cmt2feat)"
arm_anchor "$cmt2" cmt2feat
printf 'y\n' >"$cmt2/secrets.txt"
printf '{"schema":1,"feature":"cmt2feat","allowed_change_scope":["src/feature/**","docs/**","secrets.txt"],"governance_paths":["docs/scope/cmt2feat.scope.json"]}\n' \
  >"$cmt2/docs/scope/cmt2feat.scope.json"
printf 'secrets.txt\ndocs/scope/cmt2feat.scope.json\n' >"$cmt2/.changed"
CM2_OUT="$(env PATH="$SANITISED_PATH" HOME="$NOHOME" PLUMBLINE_STATE_DIR="$STATE" \
  python3 "$CM_LIB/plumbline_scope.py" --repo "$cmt2" --feature cmt2feat \
  --changed-files "$cmt2/.changed" 2>&1)"
CM2_RC=$?
assert_not_contains "CM-T2: without the baseline check the widening passes again" \
  "$CM2_OUT" "RUN_TRUST_BASELINE_CHANGED"
assert_eq "CM-T2: and it reports success" "0" "$CM2_RC"

finish "test_run_trust_anchor"
