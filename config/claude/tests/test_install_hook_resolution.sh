#!/usr/bin/env bash
# Contract: which COPY of a hook may be registered in settings.json.
#
# Measured defect (2026-07-30, real machine, caused a full rollback): the installer
# preferred `$CLAUDE_HOME/agents/config/claude/hooks/<hook>` whenever a file of that
# name existed there, and "repointed" enforcement into a 7-week-old copy that carried
# none of the current gates -- strictly worse than the stale path it was fixing, and
# reported success while doing it.
#
# Measured configuration (2026-07-31, corrected -- an earlier version of this comment
# was WRONG): ~/.claude/agents has NO .git of its own. `git rev-parse` from inside it
# walks UP and reports $HOME, which IS a working tree (origin DYAI2025/azodiac) whose
# .gitignore excludes .claude/*. The stale 2026-06-08 copy of plumbline-enforce.sh
# there is therefore UNTRACKED, inside a gitignored subtree of an unrelated repo --
# not, as first claimed, a clone of azodiac at that path.
#
# The agents copy is usable ONLY when all hold:
#   1. it lives in a git repository;
#   2. that repository's normalized remote identity equals the install checkout's;
#   3. that repository root is itself a Plumbline checkout;
#   4. the hook file is TRACKED by that repository;
#   5. the hook file there is byte-identical to the install checkout's;
# and the chosen source + REASON are always printed. Anything else, including
# "identity cannot be determined", falls back to the checkout. The foreign repository
# is never modified.
#
# Portability: bash-3.2 safe (NO $()-wrapped heredocs), shellcheck-clean.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"

# shellcheck source=lib.sh
. "$HERE/lib.sh"

echo "test_install_hook_resolution"

if ! command -v jq >/dev/null 2>&1; then
  _skip "jq not installed; hook registration is jq-gated"
  finish "test_install_hook_resolution"
  exit $?
fi

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

HOOK_REL="config/claude/hooks/plumbline-enforce.sh"

# run_install <claude-home> -- hooks only; never touches agents/commands/skills/bin.
run_install() {
  local home="$1" outf="$WORK/install.out"
  env CLAUDE_HOME="$home" HOME="$home" \
    bash "$REPO_DIR/config/claude/install.sh" --no-agents --no-commands \
    --no-skills --no-bin >"$outf" 2>&1
  INSTALL_RC=$?
  INSTALL_OUT="$(cat "$outf")"
}

registered_enforce() {
  jq -r '[.hooks.Stop[]?.hooks[]?.command] | map(select(test("plumbline-enforce"))) | .[0] // ""' \
    "$1/settings.json"
}

# make_agents_repo <home> <origin-url> <hook-content-mode>
#   hook-content-mode: same | different | none
make_agents_repo() {
  local home="$1" origin="$2" mode="$3"
  local a="$home/agents"
  mkdir -p "$a/config/claude/hooks"
  git -C "$a" init -q
  git -C "$a" config user.email res@example.com
  git -C "$a" config user.name "Res"
  git -C "$a" remote add origin "$origin"
  case "$mode" in
    same)      cp "$REPO_DIR/$HOOK_REL" "$a/$HOOK_REL"
               mkdir -p "$a/config/claude"
               cp "$REPO_DIR/config/claude/install.sh" "$a/config/claude/install.sh" ;;
    different) printf "#!/usr/bin/env bash\\n# stale copy\\nexit 0\\n" >"$a/$HOOK_REL"
               cp "$REPO_DIR/config/claude/install.sh" "$a/config/claude/install.sh" ;;
    none)      : ;;
  esac
  printf 'x\n' >"$a/marker.txt"
  git -C "$a" add -A >/dev/null 2>&1
  git -C "$a" commit -q -m base >/dev/null 2>&1
  # A dirty file, so any accidental write to the foreign repo is detectable.
  printf 'dirty\n' >>"$a/marker.txt"
}

agents_fingerprint() { # agents_fingerprint <home>
  { git -C "$1/agents" status --porcelain 2>/dev/null
    git -C "$1/agents" rev-parse HEAD 2>/dev/null
    shasum -a 256 "$1/agents/$HOOK_REL" 2>/dev/null | cut -d' ' -f1
  } | shasum -a 256 | cut -d' ' -f1
}

ORIGIN_SELF="$(git -C "$REPO_DIR" remote get-url origin 2>/dev/null)"
[ -n "$ORIGIN_SELF" ] || ORIGIN_SELF="https://github.com/DYAI2025/Plumbline.git"

# --- C1: no agents copy at all -> the checkout path ---------------------------
home="$WORK/h1"; mkdir -p "$home"
run_install "$home"
assert_eq "C1 the installer succeeds" "0" "$INSTALL_RC"
assert_contains "C1 no agents copy: registers the checkout path" \
  "$(registered_enforce "$home")" "$REPO_DIR/$HOOK_REL"
assert_contains "C1 reason is reported" "$INSTALL_OUT" "no copy under"

# --- C2: agents is a DIFFERENT repo carrying a same-named stale hook ----------
# This is the exact real-world shape that forced the rollback.
home="$WORK/h2"; mkdir -p "$home"
make_agents_repo "$home" "https://github.com/DYAI2025/azodiac.git" different
before="$(agents_fingerprint "$home")"
run_install "$home"
assert_contains "C2 different repo: registers the CHECKOUT path, not the agents copy" \
  "$(registered_enforce "$home")" "$REPO_DIR/$HOOK_REL"
assert_not_contains "C2 the foreign copy is NOT registered" \
  "$(registered_enforce "$home")" "$home/agents"
assert_contains "C2 the reason names it as a different repository" \
  "$INSTALL_OUT" "DIFFERENT repository"
assert_eq "C2 the foreign repository is untouched" "$before" "$(agents_fingerprint "$home")"

# --- C3: same origin, but the hook file DIFFERS -> the checkout path ----------
home="$WORK/h3"; mkdir -p "$home"
make_agents_repo "$home" "$ORIGIN_SELF" different
before="$(agents_fingerprint "$home")"
run_install "$home"
assert_contains "C3 same repo but differing hook: registers the checkout path" \
  "$(registered_enforce "$home")" "$REPO_DIR/$HOOK_REL"
assert_contains "C3 the reason names the content difference" \
  "$INSTALL_OUT" "differs from this checkout"
assert_eq "C3 the agents repository is untouched" "$before" "$(agents_fingerprint "$home")"

# --- C4: same origin AND byte-identical -> the agents path is allowed ---------
home="$WORK/h4"; mkdir -p "$home"
make_agents_repo "$home" "$ORIGIN_SELF" same
run_install "$home"
assert_contains "C4 same repo + byte-identical: the agents path IS used" \
  "$(registered_enforce "$home")" "$home/agents/$HOOK_REL"
assert_contains "C4 the reason states why it was allowed" \
  "$INSTALL_OUT" "byte-identical"

# Same-repo reached by a DIFFERENT URL FORM must still compare equal.
home="$WORK/h4b"; mkdir -p "$home"
scp_form="$(printf '%s' "$ORIGIN_SELF" | sed -e 's#^https://#git@#' -e 's#/#:#3')"
make_agents_repo "$home" "$scp_form" same
run_install "$home"
assert_contains "C4b ssh-form remote of the same repo still matches" \
  "$(registered_enforce "$home")" "$home/agents/$HOOK_REL"

# --- C4c: a FORK or a MIRROR is a different repository -----------------------
# Without these, `normalize_remote` could be reduced to comparing only the repo NAME
# and both suites would stay green -- measured: that mutation survived. A fork
# (different owner) and a mirror (different host) are the realistic shapes.
for other in "https://github.com/SomeoneElse/Plumbline.git" \
             "https://gitlab.com/DYAI2025/Plumbline.git"; do
  home="$WORK/h4c-$(printf '%s' "$other" | shasum | cut -c1-6)"; mkdir -p "$home"
  make_agents_repo "$home" "$other" same     # byte-identical hook, different repo
  before="$(agents_fingerprint "$home")"
  run_install "$home"
  assert_contains "C4c $other: registers the checkout path, not the look-alike" \
    "$(registered_enforce "$home")" "$REPO_DIR/$HOOK_REL"
  assert_contains "C4c $other: the reason names it as a different repository" \
    "$INSTALL_OUT" "DIFFERENT repository"
  assert_eq "C4c $other: that repository is untouched" "$before" "$(agents_fingerprint "$home")"
done

# --- C4d: same repo, byte-identical, but the hook is UNTRACKED ---------------
# `rev-parse --show-toplevel` walks UP, so it validates whichever repository CONTAINS
# the directory -- never that the file belongs to it. This is the real machine's shape:
# ~/.claude/agents has no .git at all, and rev-parse from inside it reports $HOME, an
# unrelated working tree whose .gitignore excludes .claude/*. The hook there is
# untracked. Identity of an ancestor must not launder an untracked file.
home="$WORK/h4d"; mkdir -p "$home"
a="$home/agents"; mkdir -p "$a/config/claude/hooks"
git -C "$home" init -q
git -C "$home" config user.email res@example.com
git -C "$home" config user.name "Res"
git -C "$home" remote add origin "$ORIGIN_SELF"
mkdir -p "$home/config/claude"
cp "$REPO_DIR/config/claude/install.sh" "$home/config/claude/install.sh"
cp "$REPO_DIR/$HOOK_REL" "$a/$HOOK_REL"          # byte-identical, but never committed
printf 'x\n' >"$home/tracked.txt"
git -C "$home" add tracked.txt >/dev/null 2>&1
git -C "$home" commit -q -m base >/dev/null 2>&1
run_install "$home"
assert_contains "C4d untracked agents copy: registers the checkout path" \
  "$(registered_enforce "$home")" "$REPO_DIR/$HOOK_REL"
assert_contains "C4d the reason names the untracked provenance" \
  "$INSTALL_OUT" "UNTRACKED"
assert_not_contains "C4d it must NOT claim 'same repository and byte-identical'" \
  "$INSTALL_OUT" "same repository and byte-identical"

# --- C4e: same repo, tracked, byte-identical -- but the root is NOT a Plumbline
# checkout. Measured: deleting this branch left all four install suites green (92/92),
# so it was an unverified claim. A test that still passes with its branch removed does
# not cover it.
home="$WORK/h4e"; mkdir -p "$home"
a="$home/agents"; mkdir -p "$a/config/claude/hooks"
git -C "$a" init -q
git -C "$a" config user.email res@example.com
git -C "$a" config user.name "Res"
git -C "$a" remote add origin "$ORIGIN_SELF"
cp "$REPO_DIR/$HOOK_REL" "$a/$HOOK_REL"          # byte-identical AND committed...
git -C "$a" add -A >/dev/null 2>&1
git -C "$a" commit -q -m base >/dev/null 2>&1
# ...but NO config/claude/install.sh at the root, so it is not a Plumbline checkout.
run_install "$home"
assert_contains "C4e non-Plumbline root: registers the checkout path" \
  "$(registered_enforce "$home")" "$REPO_DIR/$HOOK_REL"
assert_contains "C4e the reason names the missing checkout marker" \
  "$INSTALL_OUT" "not a Plumbline checkout"

# --- C5: identity undeterminable -> fail-safe to the checkout, never foreign --
# An agents directory that is NOT a git repository at all.
home="$WORK/h5"; mkdir -p "$home/agents/config/claude/hooks"
cp "$REPO_DIR/$HOOK_REL" "$home/agents/$HOOK_REL"
run_install "$home"
assert_contains "C5 non-git agents dir: fail-safe to the checkout path" \
  "$(registered_enforce "$home")" "$REPO_DIR/$HOOK_REL"
assert_contains "C5 the reason names it as unverifiable" \
  "$INSTALL_OUT" "not inside a git repository"

# A git repo with NO origin remote: identity cannot be determined.
home="$WORK/h5b"; mkdir -p "$home"
a="$home/agents"; mkdir -p "$a/config/claude/hooks"
git -C "$a" init -q
git -C "$a" config user.email res@example.com
git -C "$a" config user.name "Res"
cp "$REPO_DIR/$HOOK_REL" "$a/$HOOK_REL"
git -C "$a" add -A >/dev/null 2>&1
git -C "$a" commit -q -m base >/dev/null 2>&1
run_install "$home"
assert_contains "C5b no origin remote: fail-safe to the checkout path" \
  "$(registered_enforce "$home")" "$REPO_DIR/$HOOK_REL"
assert_contains "C5b the reason names the undeterminable identity" \
  "$INSTALL_OUT" "undeterminable"

# --- C6: the selection is always logged with source AND reason ----------------
assert_contains "C6 the chosen source is printed" "$INSTALL_OUT" "hook source (plumbline-enforce.sh):"
assert_contains "C6 a reason accompanies it" "$INSTALL_OUT" "reason:"
# Every registered hook family reports its resolution, not just the enforce one.
assert_contains "C6 the vision hook also reports its source" \
  "$INSTALL_OUT" "hook source (pretool-vision-gate.sh):"
assert_contains "C6 the learning-loop hook also reports its source" \
  "$INSTALL_OUT" "hook source (stop-learning-loop.sh):"

finish "test_install_hook_resolution"
