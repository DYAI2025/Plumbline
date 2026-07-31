#!/usr/bin/env bash
# Contract: an --update from a MOVED checkout repoints ALL FIVE install layers.
#
# Measured defect this pins (2026-07-31, found by independent review): the
# `safe_to_replace` ownership predicate recognised only `config/claude/{bin,lib}`
# targets. `transfer()` is the write path for FIVE layers -- agents, commands, skills,
# bin, lib -- so every agent/command/skill symlink the installer itself had created was
# classified FOREIGN and refused, while CLIs and libs were repointed. Measured on a real
# two-checkout install: 61 agents + 11 commands + 16 skills refused, 13 bin + 17 lib
# repointed, exit 0. That is a MIXED runtime -- the /agileteam orchestrator prompt and
# every agent prompt served from the OLD tree while the gates came from the new one --
# reported as success.
#
# No pre-existing test caught it because every install-touching test passes
# --no-agents --no-commands --no-skills.
#
# Portability: bash-3.2 safe (NO $()-wrapped heredocs), shellcheck-clean.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"

# shellcheck source=lib.sh
. "$HERE/lib.sh"

echo "test_install_all_layers"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# build_src <root> <marker> -- a minimal but structurally real Plumbline checkout.
build_src() {
  local r="$1" m="$2"
  mkdir -p "$r/config/claude/hooks" "$r/config/claude/bin" "$r/config/claude/lib" \
           "$r/config/claude/commands" "$r/config/claude/skills/demo-skill" \
           "$r/core" "$r/agileteam"
  cp "$REPO_DIR/config/claude/install.sh" "$r/config/claude/install.sh"
  chmod +x "$r/config/claude/install.sh"
  printf '#!/usr/bin/env bash\n# %s hook\nexit 0\n' "$m" >"$r/config/claude/hooks/plumbline-enforce.sh"
  printf '#!/usr/bin/env bash\n# %s hook\nexit 0\n' "$m" >"$r/config/claude/hooks/stop-learning-loop.sh"
  printf '#!/usr/bin/env bash\n# %s hook\nexit 0\n' "$m" >"$r/config/claude/hooks/pretool-vision-gate.sh"
  chmod +x "$r/config/claude/hooks/"*.sh
  printf '#!/usr/bin/env bash\n# %s cli\nexit 0\n' "$m" >"$r/config/claude/bin/plumbline-scope-check"
  chmod +x "$r/config/claude/bin/plumbline-scope-check"
  printf '# %s lib\n' "$m" >"$r/config/claude/lib/plumbline_scope.py"
  printf -- '---\nname: demo-command\ndescription: %s\n---\nbody\n' "$m" \
    >"$r/config/claude/commands/demo-command.md"
  printf '{"name":"demo-skill","description":"%s"}\n' "$m" \
    >"$r/config/claude/skills/demo-skill/SKILL.md"
  printf -- '---\nname: demo-agent\ndescription: %s\n---\nbody\n' "$m" >"$r/core/demo-agent.md"
  printf -- '---\nname: demo-team\ndescription: %s\n---\nbody\n' "$m" >"$r/agileteam/demo-team.md"
}

A="$WORK/checkout-A"
B="$WORK/checkout-B"
HOME_DIR="$WORK/home"
build_src "$A" "OLD"
build_src "$B" "NEW"
mkdir -p "$HOME_DIR"

# 1. Full install from checkout A (all five layers, symlink mode).
env CLAUDE_HOME="$HOME_DIR" HOME="$HOME_DIR" bash "$A/config/claude/install.sh" \
  >"$WORK/install-A.log" 2>&1
rc_a=$?
assert_eq "install from checkout A succeeds" "0" "$rc_a"

# Precondition: every layer really is a symlink INTO checkout A.
pre_stale=0
for p in agents/core/demo-agent.md commands/demo-command.md skills/demo-skill \
         bin/plumbline-scope-check lib/plumbline_scope.py; do
  t="$(readlink "$HOME_DIR/$p" 2>/dev/null || echo '')"
  case "$t" in "$A"/*) ;; *) pre_stale=$((pre_stale + 1)); printf '    not linked into A: %s -> %s\n' "$p" "$t" ;; esac
done
assert_eq "precondition: all five layers are symlinks into checkout A" "0" "$pre_stale"

# 2. --update from checkout B: the moved-checkout repoint.
env CLAUDE_HOME="$HOME_DIR" HOME="$HOME_DIR" bash "$B/config/claude/install.sh" --update \
  >"$WORK/install-B.log" 2>&1
rc_b=$?
OUT_B="$(cat "$WORK/install-B.log")"

# 3. EVERY layer must now resolve to checkout B. This is the assertion that was missing.
stale=0
for p in agents/core/demo-agent.md agents/agileteam/demo-team.md \
         commands/demo-command.md skills/demo-skill \
         bin/plumbline-scope-check lib/plumbline_scope.py; do
  t="$(readlink "$HOME_DIR/$p" 2>/dev/null || echo MISSING)"
  case "$t" in
    "$B"/*) ;;
    *) stale=$((stale + 1)); printf '    STALE: %-34s -> %s\n' "$p" "$t" ;;
  esac
done
assert_eq "ALL FIVE layers repoint to checkout B (no mixed runtime)" "0" "$stale"
assert_eq "the update reports success" "0" "$rc_b"
assert_not_contains "no target was refused" "$OUT_B" "REFUSING"
assert_not_contains "no partial-failure signal" "$OUT_B" "PLUMBLINE_INSTALL_REFUSALS"

# Content must actually change, not just the link path.
assert_contains "the installed agent now serves NEW content" \
  "$(cat "$HOME_DIR/agents/core/demo-agent.md")" "NEW"
assert_contains "the installed command now serves NEW content" \
  "$(cat "$HOME_DIR/commands/demo-command.md")" "NEW"

# 4. The same shape in COPY mode -- what `plumbline update` actually runs.
HOME_C="$WORK/home-copy"
mkdir -p "$HOME_C"
env CLAUDE_HOME="$HOME_C" HOME="$HOME_C" bash "$A/config/claude/install.sh" --copy \
  >"$WORK/install-CA.log" 2>&1
env CLAUDE_HOME="$HOME_C" HOME="$HOME_C" bash "$B/config/claude/install.sh" --copy --update --no-hook \
  >"$WORK/install-CB.log" 2>&1
rc_c=$?
assert_eq "copy --update --no-hook succeeds" "0" "$rc_c"
assert_not_contains "copy --update refuses nothing" "$(cat "$WORK/install-CB.log")" "REFUSING"
copy_stale=0
for p in agents/core/demo-agent.md commands/demo-command.md; do
  grep -q NEW "$HOME_C/$p" 2>/dev/null || { copy_stale=$((copy_stale + 1)); printf '    STALE copy: %s\n' "$p"; }
done
assert_eq "copy-mode update refreshes agents and commands too" "0" "$copy_stale"

# 5. A DANGLING link (the old checkout was deleted) must still be repairable.
HOME_D="$WORK/home-dangling"
mkdir -p "$HOME_D"
A2="$WORK/checkout-A2"
build_src "$A2" "OLD2"
env CLAUDE_HOME="$HOME_D" HOME="$HOME_D" bash "$A2/config/claude/install.sh" \
  >"$WORK/install-D.log" 2>&1
rm -rf "$A2"
assert "precondition: the agent link is now dangling" \
  "[ -L '$HOME_D/agents/core/demo-agent.md' ] && [ ! -e '$HOME_D/agents/core/demo-agent.md' ]"
env CLAUDE_HOME="$HOME_D" HOME="$HOME_D" bash "$B/config/claude/install.sh" --update \
  >"$WORK/install-D2.log" 2>&1
rc_d=$?
assert_eq "a deleted-checkout install is repairable" "0" "$rc_d"
dt="$(readlink "$HOME_D/agents/core/demo-agent.md" 2>/dev/null || echo MISSING)"
assert_contains "the dangling link is repointed to checkout B" "$dt" "$B/"

# 6. Partial failure is DETECTABLE: a foreign symlink makes the run non-zero and
#    emits a machine-readable count, so an orchestrator can roll back.
HOME_F="$WORK/home-foreign"
mkdir -p "$HOME_F/bin" "$WORK/othertool"
printf 'other\n' >"$WORK/othertool/plumbline-scope-check"
ln -s "$WORK/othertool/plumbline-scope-check" "$HOME_F/bin/plumbline-scope-check"
env CLAUDE_HOME="$HOME_F" HOME="$HOME_F" bash "$B/config/claude/install.sh" --update \
  >"$WORK/install-F.log" 2>&1
rc_f=$?
OUT_F="$(cat "$WORK/install-F.log")"
assert_eq "a refusal makes the installer exit NON-zero" "3" "$rc_f"
assert_contains "a machine-readable refusal count is emitted" \
  "$OUT_F" "PLUMBLINE_INSTALL_REFUSALS=1"
assert_contains "the incoherence is stated plainly" "$OUT_F" "NOT coherent"
ft="$(readlink "$HOME_F/bin/plumbline-scope-check" 2>/dev/null || echo '')"
assert_contains "the foreign symlink still survives" "$ft" "$WORK/othertool"

# 7. --dry-run models refusals instead of promising a clean install.
env CLAUDE_HOME="$HOME_F" HOME="$HOME_F" bash "$B/config/claude/install.sh" --update --dry-run \
  >"$WORK/install-DR.log" 2>&1
OUT_DR="$(cat "$WORK/install-DR.log")"
assert_contains "dry-run predicts the refusal" "$OUT_DR" "would REFUSE"
assert_not_contains "dry-run does not promise to symlink the refused target" \
  "$OUT_DR" "would symlink:  $HOME_F/bin/plumbline-scope-check"

finish "test_install_all_layers"
