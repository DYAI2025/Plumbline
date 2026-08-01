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
  printf '#!/usr/bin/env bash\n# %s hook\nexit 0\n' "$m" >"$r/config/claude/hooks/pretool-scope-gate.sh"
  chmod +x "$r/config/claude/hooks/"*.sh
  for c in plumbline-scope-check plumbline-context-check; do
    printf '#!/usr/bin/env bash\n# %s cli\nexit 0\n' "$m" >"$r/config/claude/bin/$c"
    chmod +x "$r/config/claude/bin/$c"
  done
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

# Precondition: live content layers are symlinks into checkout A; the scope
# authority is deliberately copied outside the governed checkout.
pre_stale=0
for p in agents/core/demo-agent.md commands/demo-command.md skills/demo-skill; do
  t="$(readlink "$HOME_DIR/$p" 2>/dev/null || echo '')"
  case "$t" in "$A"/*) ;; *) pre_stale=$((pre_stale + 1)); printf '    not linked into A: %s -> %s\n' "$p" "$t" ;; esac
done
assert_eq "precondition: live content layers are symlinks into checkout A" "0" "$pre_stale"
assert "precondition: scope checker is independent copied authority" \
  "test -f '$HOME_DIR/bin/plumbline-scope-check' && test ! -L '$HOME_DIR/bin/plumbline-scope-check'"
assert "precondition: context checker is independent copied authority" \
  "test -f '$HOME_DIR/bin/plumbline-context-check' && test ! -L '$HOME_DIR/bin/plumbline-context-check'"
assert "precondition: scope library is independent copied authority" \
  "test -f '$HOME_DIR/lib/plumbline_scope.py' && test ! -L '$HOME_DIR/lib/plumbline_scope.py'"

# 2. --update from checkout B: the moved-checkout repoint.
env CLAUDE_HOME="$HOME_DIR" HOME="$HOME_DIR" bash "$B/config/claude/install.sh" --update \
  >"$WORK/install-B.log" 2>&1
rc_b=$?
OUT_B="$(cat "$WORK/install-B.log")"

# 3. Every live layer must now resolve to checkout B; copied authority must be
# refreshed to B's content without becoming a symlink back into B.
stale=0
for p in agents/core/demo-agent.md agents/agileteam/demo-team.md \
         commands/demo-command.md skills/demo-skill; do
  t="$(readlink "$HOME_DIR/$p" 2>/dev/null || echo MISSING)"
  case "$t" in
    "$B"/*) ;;
    *) stale=$((stale + 1)); printf '    STALE: %-34s -> %s\n' "$p" "$t" ;;
  esac
done
assert_eq "all live layers repoint to checkout B (no mixed runtime)" "0" "$stale"
assert "scope checker stays copied and refreshes to checkout B content" \
  "test ! -L '$HOME_DIR/bin/plumbline-scope-check' && grep -q NEW '$HOME_DIR/bin/plumbline-scope-check'"
assert "context checker stays copied and refreshes to checkout B content" \
  "test ! -L '$HOME_DIR/bin/plumbline-context-check' && grep -q NEW '$HOME_DIR/bin/plumbline-context-check'"
assert "scope library stays copied and refreshes to checkout B content" \
  "test ! -L '$HOME_DIR/lib/plumbline_scope.py' && grep -q NEW '$HOME_DIR/lib/plumbline_scope.py'"
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

# 8. A layer root that ESCAPES $CLAUDE_HOME must be refused, not written through.
#    This is not hypothetical: during review of this change a reviewer copied a real
#    ~/.claude with `cp -a`, which preserved `skills -> <real home>/skills-unified` as
#    an ABSOLUTE link. Installing into the copy rewrote 16 entries in the REAL shared
#    skills directory. Nothing was lost, but nothing stopped it either.
HOME_E="$WORK/home-escape"
OUTSIDE="$WORK/outside-shared-skills"
mkdir -p "$HOME_E" "$OUTSIDE"
printf 'someone elses content\n' >"$OUTSIDE/demo-skill-marker.txt"
ln -s "$OUTSIDE" "$HOME_E/skills"          # layer root escapes $CLAUDE_HOME
env CLAUDE_HOME="$HOME_E" HOME="$HOME_E" bash "$B/config/claude/install.sh" --update \
  >"$WORK/install-E.log" 2>&1
rc_e=$?
OUT_E="$(cat "$WORK/install-E.log")"
assert_contains "an escaping layer root is REFUSED" "$OUT_E" "OUTSIDE \$CLAUDE_HOME"
assert_eq "the escape makes the run non-zero" "3" "$rc_e"
assert "the outside directory is untouched" "[ -f '$OUTSIDE/demo-skill-marker.txt' ]"
assert "nothing was written into the outside directory" \
  "[ ! -e '$OUTSIDE/demo-skill' ]"
# A layer root symlinked INSIDE $CLAUDE_HOME is legitimate and must still work.
HOME_I="$WORK/home-inside"
mkdir -p "$HOME_I/skills-unified"
ln -s "$HOME_I/skills-unified" "$HOME_I/skills"
env CLAUDE_HOME="$HOME_I" HOME="$HOME_I" bash "$B/config/claude/install.sh" --update \
  >"$WORK/install-I.log" 2>&1
rc_i=$?
assert_eq "a layer root symlinked INSIDE \$CLAUDE_HOME still installs" "0" "$rc_i"
assert "the skill landed via the in-home symlink" \
  "[ -e '$HOME_I/skills-unified/demo-skill' ]"

# 9. Refusal aggregation across layers: the count must be the real total, not 1.
#    A refactor moving the transfer loop into a subshell would zero the counter and a
#    single-refusal assertion would not notice.
HOME_M="$WORK/home-multi"
mkdir -p "$HOME_M/bin" "$HOME_M/lib" "$WORK/foreign"
printf 'x\n' >"$WORK/foreign/thing"
ln -s "$WORK/foreign/thing" "$HOME_M/bin/plumbline-scope-check"
ln -s "$WORK/foreign/thing" "$HOME_M/bin/plumbline-context-check"
ln -s "$WORK/foreign/thing" "$HOME_M/lib/plumbline_scope.py"
env CLAUDE_HOME="$HOME_M" HOME="$HOME_M" bash "$B/config/claude/install.sh" --update \
  >"$WORK/install-M.log" 2>&1
rc_m=$?
OUT_M="$(cat "$WORK/install-M.log")"
assert_eq "multiple refusals still exit 3" "3" "$rc_m"
assert_contains "the refusal COUNT is the real total, not 1" \
  "$OUT_M" "PLUMBLINE_INSTALL_REFUSALS=3"

# 10. A dangling link is adopted, but NAMED -- never a silent takeover.
HOME_G="$WORK/home-dangle2"
mkdir -p "$HOME_G/bin"
ln -s "$WORK/gone-away/plumbline-scope-check" "$HOME_G/bin/plumbline-scope-check"
env CLAUDE_HOME="$HOME_G" HOME="$HOME_G" bash "$B/config/claude/install.sh" --update \
  >"$WORK/install-G.log" 2>&1
OUT_G="$(cat "$WORK/install-G.log")"
assert_contains "adopting a dangling link is announced" "$OUT_G" "adopting dangling link"

# 11. M1-a: a stray `config/claude/install.sh` at a HIGH ancestor must NOT mark every
#     link beneath it as ours. Without the $HOME stop, one marker file disables the
#     foreign-symlink refusal wholesale. (Measured: deleting either stop left all 15
#     install-touching suites green -- an unverified claim in the commit that added it.)
HOME_S="$WORK/home-straymarker"
mkdir -p "$HOME_S/.claude/bin" "$HOME_S/config/claude" "$HOME_S/othertool"
printf '#!/usr/bin/env bash\n# stray marker\n' >"$HOME_S/config/claude/install.sh"
printf 'foreign\n' >"$HOME_S/othertool/plumbline-scope-check"
ln -s "$HOME_S/othertool/plumbline-scope-check" "$HOME_S/.claude/bin/plumbline-scope-check"
env CLAUDE_HOME="$HOME_S/.claude" HOME="$HOME_S" bash "$B/config/claude/install.sh" --update \
  >"$WORK/install-S.log" 2>&1
rc_s=$?
OUT_S="$(cat "$WORK/install-S.log")"
assert_eq "a stray marker at \$HOME does NOT legitimise a foreign link" "3" "$rc_s"
assert_contains "the foreign link is still refused" "$OUT_S" "REFUSING to replace foreign symlink"
st="$(readlink "$HOME_S/.claude/bin/plumbline-scope-check" 2>/dev/null || echo '')"
assert_contains "and it still points at the foreign target" "$st" "$HOME_S/othertool"

# 12. M1-b: the walk must CANONICALIZE. A relative target that traverses through a
#     Plumbline-named directory and back out resolves elsewhere, but a lexical walk
#     matches the name and adopts the link.
HOME_C2="$WORK/home-canon"
mkdir -p "$HOME_C2/.claude/bin" "$HOME_C2/plumbtree/config/claude" "$HOME_C2/elsewhere"
printf '#!/usr/bin/env bash\n' >"$HOME_C2/plumbtree/config/claude/install.sh"
printf 'foreign\n' >"$HOME_C2/elsewhere/plumbline-scope-check"
ln -s "../../plumbtree/../elsewhere/plumbline-scope-check" \
  "$HOME_C2/.claude/bin/plumbline-scope-check"
env CLAUDE_HOME="$HOME_C2/.claude" HOME="$HOME_C2" bash "$B/config/claude/install.sh" --update \
  >"$WORK/install-C2.log" 2>&1
rc_c2=$?
OUT_C2="$(cat "$WORK/install-C2.log")"
assert_eq "a path traversing OUT of a Plumbline tree is refused" "3" "$rc_c2"
assert_contains "the traversal case is reported as foreign" \
  "$OUT_C2" "REFUSING to replace foreign symlink"

# 13. F3: $CLAUDE_HOME living INSIDE a checkout is a documented layout (the CLAUDE_HOME
#     override). Testing the ancestor stops before the marker refused it outright --
#     7 refusals, 0 layers repointed, the exact inversion of a repoint.
A3="$WORK/checkout-A3"
B3="$WORK/checkout-B3"
build_src "$A3" "OLD3"
build_src "$B3" "NEW3"
env CLAUDE_HOME="$A3/.claude" HOME="$WORK/hhome" bash "$A3/config/claude/install.sh" \
  >"$WORK/install-A3.log" 2>&1
env CLAUDE_HOME="$A3/.claude" HOME="$WORK/hhome" bash "$B3/config/claude/install.sh" --update \
  >"$WORK/install-B3.log" 2>&1
rc_b3=$?
OUT_B3="$(cat "$WORK/install-B3.log")"
assert_eq "CLAUDE_HOME inside a checkout still repoints (no refusals)" "0" "$rc_b3"
assert_not_contains "nothing was refused in that layout" "$OUT_B3" "REFUSING"
assert "and the copied scope authority refreshed to the new checkout content" \
  "test ! -L '$A3/.claude/bin/plumbline-scope-check' && grep -q NEW3 '$A3/.claude/bin/plumbline-scope-check'"

# 14. F1: the LEGACY whole-repo agents symlink that this installer used to create must
#     remain installable. The escape guard ran before the back-compat branch, so
#     `agents -> $REPO_DIR` (by definition outside $CLAUDE_HOME) was refused, exit 3 --
#     and plumbline_update.py reverts the WHOLE $CLAUDE_HOME on a non-zero exit, making
#     every legacy machine's update an unrecoverable loop.
HOME_L="$WORK/home-legacy"
mkdir -p "$HOME_L"
ln -s "$B" "$HOME_L/agents"
env CLAUDE_HOME="$HOME_L" HOME="$HOME_L" bash "$B/config/claude/install.sh" --update \
  --no-commands --no-skills --no-hook --no-bin >"$WORK/install-L.log" 2>&1
rc_l=$?
OUT_L="$(cat "$WORK/install-L.log")"
assert_eq "a legacy whole-repo agents symlink still installs cleanly" "0" "$rc_l"
assert_contains "it is recognised, not refused" "$OUT_L" "already points at this repo"
assert_not_contains "no escape refusal for the install source itself" \
  "$OUT_L" "OUTSIDE \$CLAUDE_HOME"

# 15. F5: a refusal in `bin` must not silently swallow the `lib` layer as well.
HOME_BL="$WORK/home-binlib"
mkdir -p "$HOME_BL/bin" "$WORK/foreign2"
printf 'x\n' >"$WORK/foreign2/thing"
ln -s "$WORK/foreign2/thing" "$HOME_BL/bin/plumbline-scope-check"
env CLAUDE_HOME="$HOME_BL" HOME="$HOME_BL" bash "$B/config/claude/install.sh" --update \
  --no-agents --no-commands --no-skills --no-hook >"$WORK/install-BL.log" 2>&1
assert "a bin refusal does not skip the lib layer" \
  "[ -e '$HOME_BL/lib/plumbline_scope.py' ]"

# 16. F4: a DANGLING layer root must not kill the run with an unclassified exit 1.
HOME_DL="$WORK/home-danglingroot"
mkdir -p "$HOME_DL"
ln -s "$HOME_DL/skills-unified" "$HOME_DL/skills"     # target does not exist yet
env CLAUDE_HOME="$HOME_DL" HOME="$HOME_DL" bash "$B/config/claude/install.sh" --update \
  --no-agents --no-commands --no-hook --no-bin >"$WORK/install-DL.log" 2>&1
rc_dl=$?
OUT_DL="$(cat "$WORK/install-DL.log")"
assert_eq "a dangling layer root inside \$CLAUDE_HOME is handled, not fatal" "0" "$rc_dl"
assert_contains "creating it is announced" "$OUT_DL" "creating dangling layer root"
assert "the skill landed through the repaired root" \
  "[ -e '$HOME_DL/skills-unified/demo-skill' ]"

finish "test_install_all_layers"
