#!/usr/bin/env bash
# Integration test reproducing the REAL failure shape that forced a rollback on
# 2026-07-30, end to end, in one fixture:
#
#   ~/.claude/agents      = a directory carrying a stale same-named copy of
#                           plumbline-enforce.sh, inside an UNRELATED repository
#                           (on the real machine it has no .git of its own: rev-parse
#                           walks up to $HOME, a working tree with origin azodiac whose
#                           .gitignore excludes .claude/*, so the copy is UNTRACKED.
#                           An earlier version of this header wrongly called the agents
#                           directory itself a clone. The committed-repo shape below is
#                           the STRICTER fixture; the untracked shape is covered by
#                           test_install_hook_resolution.sh C4d.)
#   ~/.claude/bin/*       = symlinks into an OLDER Plumbline checkout
#   ~/.claude/lib/*       = symlinks into that same older checkout
#   installer source      = the current checkout
#
# On the real machine this produced a MIXED runtime: the Stop hook was registered into
# the foreign repository's 7-week-old copy, while the three BLOCKING CLIs still pointed
# at the older checkout -- and the installer reported success.
#
# Required end state:
#   * the foreign repository is byte-for-byte untouched;
#   * hooks resolve to an ALLOWED source (never the foreign copy);
#   * every managed CLI and library points at ONE checkout -- no mixed runtime;
#   * a foreign symlink and a real file are never overwritten;
#   * a second identical run is idempotent.
#
# Portability: bash-3.2 safe (NO $()-wrapped heredocs), shellcheck-clean.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"

# shellcheck source=lib.sh
. "$HERE/lib.sh"

echo "test_install_mixed_runtime"

if ! command -v jq >/dev/null 2>&1; then
  _skip "jq not installed; hook registration is jq-gated"
  finish "test_install_mixed_runtime"
  exit $?
fi

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

HOME_DIR="$WORK/home"
OLD="$WORK/old-plumbline"
mkdir -p "$HOME_DIR/bin" "$HOME_DIR/lib"

# --- the OLDER Plumbline checkout the existing symlinks point at ---------------
# It must carry config/claude/install.sh: that is what makes a tree recognisably a
# Plumbline checkout, and therefore what makes links into it OURS to repoint. A
# fixture without it is not a plausible old install.
mkdir -p "$OLD/config/claude/bin" "$OLD/config/claude/lib"
cp "$REPO_DIR/config/claude/install.sh" "$OLD/config/claude/install.sh"
for c in plumbline-scope-check plumbline-context-check plumbline-reality-check; do
  printf '#!/usr/bin/env bash\n# OLD checkout copy\nexit 0\n' >"$OLD/config/claude/bin/$c"
  chmod +x "$OLD/config/claude/bin/$c"
  ln -s "$OLD/config/claude/bin/$c" "$HOME_DIR/bin/$c"
done
printf '# OLD lib\n' >"$OLD/config/claude/lib/plumbline_scope.py"
ln -s "$OLD/config/claude/lib/plumbline_scope.py" "$HOME_DIR/lib/plumbline_scope.py"

# --- ~/.claude/agents = an UNRELATED repository with a stale hook copy ----------
A="$HOME_DIR/agents"
mkdir -p "$A/config/claude/hooks"
git -C "$A" init -q
git -C "$A" config user.email foreign@example.com
git -C "$A" config user.name "Foreign"
git -C "$A" remote add origin "https://github.com/DYAI2025/azodiac.git"
printf '#!/usr/bin/env bash\n# 7-week-old copy, none of the current gates\nexit 0\n' \
  >"$A/config/claude/hooks/plumbline-enforce.sh"
printf 'project file\n' >"$A/README.md"
git -C "$A" add -A >/dev/null 2>&1
git -C "$A" commit -q -m base >/dev/null 2>&1
printf 'uncommitted work\n' >>"$A/README.md"       # the foreign repo's dirty state

# --- things the installer must NEVER touch -------------------------------------
printf '#!/usr/bin/env bash\necho other tool\n' >"$HOME_DIR/bin/some-other-tool"
chmod +x "$HOME_DIR/bin/some-other-tool"
mkdir -p "$WORK/othertool"
printf 'other\n' >"$WORK/othertool/plumbline-redact"
ln -s "$WORK/othertool/plumbline-redact" "$HOME_DIR/bin/plumbline-redact"   # FOREIGN link
# A stale REAL file at a MANAGED destination: under --update this is a previous
# copy-mode install of ours and MUST be refreshed. (Refusing it would make a --copy
# install permanently un-updatable -- the update-layer suite pins that contract.)
printf '#!/usr/bin/env bash\n# a stale REAL file from an older copy install\n' \
  >"$HOME_DIR/bin/plumbline-run-ledger"
chmod +x "$HOME_DIR/bin/plumbline-run-ledger"

foreign_fp() {
  { git -C "$A" status --porcelain; git -C "$A" rev-parse HEAD
    shasum -a 256 "$A/config/claude/hooks/plumbline-enforce.sh" | cut -d' ' -f1
    shasum -a 256 "$A/README.md" | cut -d' ' -f1
  } 2>/dev/null | shasum -a 256 | cut -d' ' -f1
}
before_foreign="$(foreign_fp)"
before_other="$(shasum -a 256 "$HOME_DIR/bin/some-other-tool" | cut -d' ' -f1)"

run_install() {
  local outf="$WORK/install.out"
  env CLAUDE_HOME="$HOME_DIR" HOME="$HOME_DIR" \
    bash "$REPO_DIR/config/claude/install.sh" --update --no-agents --no-commands \
    --no-skills >"$outf" 2>&1
  INSTALL_RC=$?
  INSTALL_OUT="$(cat "$outf")"
}
run_install
# The fixture deliberately contains ONE foreign symlink, so the run must end
# NON-zero with a machine-readable count: partial failure has to be detectable by an
# orchestrator, not merely visible in stderr prose.
assert_eq "a refused target makes the installer exit non-zero" "3" "$INSTALL_RC"
assert_contains "the refusal count is machine-readable" \
  "$INSTALL_OUT" "PLUMBLINE_INSTALL_REFUSALS=1"
assert_contains "the incoherence is stated plainly" "$INSTALL_OUT" "NOT coherent"

# --- 1. the foreign repository is untouched ------------------------------------
assert_eq "the foreign (azodiac) repository is byte-for-byte untouched" \
  "$before_foreign" "$(foreign_fp)"

# --- 2. hooks resolve to an allowed source, never the foreign copy --------------
reg="$(jq -r '[.hooks.Stop[]?.hooks[]?.command] | map(select(test("plumbline-enforce"))) | .[0] // ""' "$HOME_DIR/settings.json")"
assert_contains "the enforce hook resolves to THIS checkout" "$reg" "$REPO_DIR/config/claude/hooks/plumbline-enforce.sh"
assert_not_contains "the enforce hook does NOT resolve into the foreign repo" "$reg" "$HOME_DIR/agents"
assert_contains "the resolution reason is reported" "$INSTALL_OUT" "DIFFERENT repository"

# --- 3. NO MIXED RUNTIME: every managed CLI/lib points at one checkout -----------
mixed=0
for c in plumbline-scope-check plumbline-context-check plumbline-reality-check \
         plumbline-plan-check plumbline-runtime-hygiene plumbline-remote-watch \
         plumbline-provenance-check; do
  t="$(readlink "$HOME_DIR/bin/$c" 2>/dev/null || echo MISSING)"
  case "$t" in
    "$REPO_DIR"/*) ;;
    *) mixed=$((mixed + 1)); printf '    stale/missing: %s -> %s\n' "$c" "$t" ;;
  esac
done
assert_eq "no managed CLI still points at the OLD checkout" "0" "$mixed"
lib_t="$(readlink "$HOME_DIR/lib/plumbline_scope.py" 2>/dev/null || echo MISSING)"
assert_contains "the managed library is repointed too" "$lib_t" "$REPO_DIR/config/claude/lib/"

# --- 4. foreign files and real files survive ------------------------------------
assert_eq "an unrelated tool in ~/.claude/bin is untouched" \
  "$before_other" "$(shasum -a 256 "$HOME_DIR/bin/some-other-tool" | cut -d' ' -f1)"
ft="$(readlink "$HOME_DIR/bin/plumbline-redact" 2>/dev/null || echo '')"
assert_contains "a FOREIGN symlink is refused, not overwritten" "$ft" "$WORK/othertool"
assert_contains "the refusal is reported" "$INSTALL_OUT" "REFUSING to replace foreign symlink"
# A stale REAL file at a managed destination is a previous copy-install of ours, and
# --update must refresh it. Refusing it would make a --copy install permanently
# un-updatable; the update-layer suite plants exactly this shape and requires the
# overwrite. What must NEVER be touched is a FOREIGN symlink (asserted above).
assert "a stale REAL file at a managed destination IS refreshed by --update" \
  "[ -L '$HOME_DIR/bin/plumbline-run-ledger' ]"
rl="$(readlink "$HOME_DIR/bin/plumbline-run-ledger" 2>/dev/null || echo '')"
assert_contains "and it now points at this checkout" "$rl" "$REPO_DIR/config/claude/bin/"
assert_not_contains "no regular-file refusal is emitted any more" \
  "$INSTALL_OUT" "REFUSING to replace a regular file"

# --- 5. a second identical run is idempotent ------------------------------------
snap_before="$(ls -l "$HOME_DIR/bin" "$HOME_DIR/lib"; cat "$HOME_DIR/settings.json")"
run_install
snap_after="$(ls -l "$HOME_DIR/bin" "$HOME_DIR/lib"; cat "$HOME_DIR/settings.json")"
assert_eq "second identical run changes nothing" "$snap_before" "$snap_after"
# Still non-zero, and that is correct: the foreign symlink is STILL there, so the
# runtime is still incoherent. A refusal that stopped being reported on the second run
# would let an operator "fix" the exit code by running the installer twice.
assert_eq "second run still reports the unresolved refusal" "3" "$INSTALL_RC"
assert_contains "second run still names the count" \
  "$INSTALL_OUT" "PLUMBLINE_INSTALL_REFUSALS=1"
assert_eq "the foreign repo is STILL untouched after the second run" \
  "$before_foreign" "$(foreign_fp)"

finish "test_install_mixed_runtime"
