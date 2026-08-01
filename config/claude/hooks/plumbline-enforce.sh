#!/usr/bin/env bash
#
# Fail-closed PRIL enforcement Stop hook (git ground-truth).
#
# Runs the Plumbline Runtime Integrity Layer (PRIL) gates against the real git
# diff when an /agileteam feature run is active, so "fail-closed" is a runtime
# property and not just prose addressed to a cooperative LLM. On any PRIL gate
# failure it returns a `decision: block` so the agent must fix the gate (or
# escalate to the user) before the session ends.
#
# Activation (C1) is a GROUND-TRUTH MARKER the orchestrator writes:
#   docs/context/.active-feature  (the confirmed feature slug)
# It is NOT gated on PLUMBLINE_FEATURE — the runtime never sets that, so a
# variable-gated hook would be a permanent no-op. A normal (non-feature) session
# has no marker, so this hook is an immediate no-op exit 0.
#
# TRUST BOUNDARY: enforcement is only as trustworthy as write-access to
# docs/context/. The orchestrator owns this marker (same trust model as the
# user-confirmed canvas/vision). Therefore a marker that is PRESENT but
# empty/whitespace-only is treated as suspicious (an armed-then-blanked marker by
# which enforcement could be silently disabled) and BLOCKS — it is not a no-op.
# Only a truly ABSENT marker is a no-op (a normal session that was never armed).
#
# KO-1 AND ITS CEILING (be precise here; the first attempt got this wrong).
# The marker is gitignored, so DELETING it disarms every gate below and leaves no
# git trace. That is a real bypass. But it CANNOT be closed by inferring intent from
# absence, because removing the marker is ALSO the legitimate end of a feature run:
# "no marker" is the correct steady state of every ordinary session.
#
# A first fix blocked when the marker was absent while confirmed canvases existed and
# the tree was dirty. Measured: that is the NORMAL state of any repo that has ever run
# /agileteam and is currently being worked in — it blocked ordinary sessions in this
# repo and in five others, and its remedy text invited committing an unreviewed tree or
# writing a marker that FALSELY arms enforcement. Both are worse than the threat.
#
# So the detection is OPT-IN: PLUMBLINE_GATE_MARKER_ABSENT=1. Default OFF, because a
# gate that cannot distinguish an attack from the normal case is a false-alarm
# generator, and this layer's own value dies to alarm fatigue. With the flag ON the
# absent-marker shape blocks; with it OFF an absent marker is a silent no-op, exactly
# as the paragraph above describes. KO-1 is therefore NAMED and OPTIONALLY detectable,
# NOT closed — do not describe it as closed.
#
# Safety contract (mirrors stop-learning-loop.sh):
#   - NEVER exits non-zero (an accidental error must not crash the session).
#   - Honors stop_hook_active (exit 0, no output) to avoid infinite stop loops.
#   - On a PRIL failure emits exactly ONE JSON object to stdout.
#   - FAILS CLOSED: a PRIL gate returning non-zero -> block. It never fails open.
#
# This is a NEW, distinct filename from the deliberately-inert optional pretool
# guard, so the runtime-integrity test's "optional pretool guard is not
# activated" pin stays valid (that pin asserts the inert guard is unregistered).
#
# `set` is intentionally omitted: with `set -e` a single PRIL sub-command failure
# would abort the hook before it could emit the block decision (fail OPEN). We
# want the opposite — collect every failure, then block.

input="$(cat 2>/dev/null)"

# Honor stop_hook_active first: if we already blocked once this stop cycle, let
# the agent finish (no infinite loop). Short-circuits before any enforcement.
# M-1: do not hard-depend on jq for the loop guard — if jq is unavailable a naive
# jq-only parse silently fails and the hook could re-fire. Fall back to a grep on
# the raw payload so the loop guard still holds without jq.
if command -v jq >/dev/null 2>&1; then
  active="$(printf '%s' "$input" | jq -r '.stop_hook_active // false' 2>/dev/null)"
  [ "$active" = "true" ] && exit 0
elif printf '%s' "$input" | grep -Eq '"stop_hook_active"[[:space:]]*:[[:space:]]*true'; then
  exit 0
fi

# emit_block <reason>: print exactly one block-decision JSON object to stdout.
# Uses jq when available; otherwise a jq-less fallback that strips the only two
# bytes which could break a hand-built JSON string (`"` and `\`). Reasons here are
# controlled literals, so this lossy strip never corrupts a meaningful message.
emit_block() {
  local r="$1"
  if command -v jq >/dev/null 2>&1; then
    jq -cn --arg r "$r" '{decision:"block", reason:$r}' 2>/dev/null && return 0
  fi
  local safe="${r//\\/}"
  safe="${safe//\"/}"
  printf '{"decision":"block","reason":"%s"}\n' "$safe"
}

: "${CLAUDE_PROJECT_DIR:=$PWD}"
repo="$CLAUDE_PROJECT_DIR"

# --- C1 activation: ground-truth marker the orchestrator writes ---------------
# No marker -> not an active feature run -> no-op. This is what keeps normal
# sessions completely untouched.
marker="$repo/docs/context/.active-feature"
if [ ! -f "$marker" ]; then
  # KO-1 detection -- OPT-IN. See the header for why this cannot be on by default:
  # an absent marker is the normal steady state, so blocking on it blocks ordinary
  # sessions (measured across six repos). Only an operator who wants the stricter
  # reading turns it on.
  if [ "${PLUMBLINE_GATE_MARKER_ABSENT:-0}" != "1" ]; then
    exit 0
  fi
  if [ -d "$repo/docs/canvas" ]; then
    canvas_count=0
    for canvas_candidate in "$repo/docs/canvas/"*.canvas.md; do
      [ -f "$canvas_candidate" ] && canvas_count=$((canvas_count + 1))
    done
    if [ "$canvas_count" -gt 0 ]; then
      dirty="unknown"
      if git -C "$repo" rev-parse --git-dir >/dev/null 2>&1; then
        if git_status_out="$(git -C "$repo" status --porcelain 2>/dev/null)"; then
          if [ -n "$git_status_out" ]; then dirty="yes"; else dirty="no"; fi
        fi
      fi
      if [ "$dirty" != "no" ]; then
        emit_block "PRIL_MARKER_ABSENT: docs/context/.active-feature is missing while $canvas_count confirmed canvas(es) exist and the working tree has uncommitted changes (dirty=$dirty). The marker is gitignored, so its deletion leaves no trace and silently disarms every PRIL gate. Restore the confirmed feature slug, or commit/clean the tree if no feature run is active."
        exit 0
      fi
    fi
  fi
  exit 0
fi

# Read the slug; strip any surrounding whitespace/newlines.
feat="$(tr -d ' \t\r\n' < "$marker" 2>/dev/null)"
# H-1 (marker laundering): the marker is PRESENT (we passed the -f check) but the
# slug is empty/whitespace-only. That is an armed-then-blanked marker by which
# enforcement could be silently disabled — BLOCK, never silently no-op. (A truly
# ABSENT marker already exited above as a normal, un-armed session.)
if [ -z "$feat" ]; then
  emit_block "PRIL enforcement: active-feature marker present but empty — enforcement cannot be silently disabled. Restore the confirmed feature slug in docs/context/.active-feature or remove the marker if no feature is active."
  exit 0
fi
# A present slug that could escape into a path/git argument, or be read as a CLI
# flag, is a tampered/suspicious marker (not a blank one) — also BLOCK rather than
# risk it or silently ignore an armed marker.
case "$feat" in
  */*|*\\*|.|..|-*)
    emit_block "PRIL enforcement: active-feature marker present but malformed (slug '$feat' is not a safe feature name). Restore the confirmed feature slug in docs/context/.active-feature or remove the marker."
    exit 0
    ;;
esac

# The feature must have a confirmed canvas to be a real active feature; without
# it there is nothing to enforce against -> no-op.
[ -f "$repo/docs/canvas/$feat.canvas.md" ] || exit 0

# --- PLUM-7: resolve every required CLI independently -------------------------
# Installation identity and the governed product repository are different
# things. Resolve each executable in this documented order:
#   1. PLUMBLINE_BIN_DIR (explicit installation/pilot override)
#   2. project-local config/claude/bin (legacy/vendored layout)
#   3. PATH
#   4. CLAUDE_HOME/bin, then HOME/.claude/bin (normal user install)
#
# Do not use `readlink -f`: macOS does not provide the GNU option. Python is
# already a required runtime dependency, so use Path.resolve to follow both
# directory and executable symlinks before evaluating the trust boundary.
canonical_executable() {
  local candidate="$1"
  [ -f "$candidate" ] && [ -x "$candidate" ] || return 1
  python3 - "$candidate" <<'PY' 2>/dev/null
import sys
from pathlib import Path
try:
    print(Path(sys.argv[1]).resolve(strict=True))
except OSError:
    raise SystemExit(1)
PY
}

repo_physical="$(cd "$repo" 2>/dev/null && pwd -P)" || repo_physical="$repo"

# --- OPEN-1: never execute a checker the governed repo could have rewritten ---
#
# The resolution order above deliberately prefers a project-local checker, and
# nothing verified it. Replacing the body of the resolved runtime with `exit 0`
# made the BLOCKING scope gate pass a real out-of-scope change; measured on a
# fixture, canonical checker exit=3 versus in-repo mutated checker exit=0.
#
# A checker that lives inside the repository it is judging is only trustworthy if
# it is tracked AND byte-identical to HEAD -- i.e. it is the reviewed artifact,
# not something written during this run. That test is applied to the wrapper and
# to every runtime file the wrapper loads, on EVERY resolution branch: an
# override (PLUMBLINE_BIN_DIR), a PATH entry and a symlink from outside all land
# on the same physical file, so exempting any of them would leave the hole open
# under a different name.
#
# A checker resolved OUTSIDE the governed repo is out of the agent's reach in
# this threat model and is not subject to the check.
repo_physical=""
if [ -n "$repo" ]; then
  repo_physical="$(cd "$repo" 2>/dev/null && pwd -P)" || repo_physical=""
fi

path_inside_repo() { # path_inside_repo <canonical-path>
  [ -n "$repo_physical" ] || return 1
  case "$1" in
    "$repo_physical"/*) return 0 ;;
    *) return 1 ;;
  esac
}

# One file is verifiable iff git tracks it AND it matches HEAD exactly.
file_matches_head() { # file_matches_head <canonical-path>
  local rel=""
  rel="${1#"$repo_physical"/}"
  git -C "$repo_physical" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1 || return 1
  git -C "$repo_physical" diff --quiet HEAD -- "$rel" >/dev/null 2>&1 || return 1
  return 0
}

# Follow a symlink chain to the physical file. `canonical_executable` canonicalizes
# the containing DIRECTORY only, so a link in an outside directory pointing at an
# in-repo wrapper reads as "outside the repo" and would skip the whole check --
# the very bypass the requirement names explicitly. macOS has no `readlink -f`,
# so walk the chain by hand, resolving relative targets against the link's dir.
resolve_link_chain() { # resolve_link_chain <path>
  local current="$1" target="" dir="" hops=0
  while [ -L "$current" ] && [ "$hops" -lt 40 ]; do
    target="$(readlink "$current" 2>/dev/null)" || return 1
    [ -n "$target" ] || return 1
    case "$target" in
      /*) current="$target" ;;
      *)  dir="$(dirname "$current")"; current="$dir/$target" ;;
    esac
    hops=$((hops + 1))
  done
  dir="$(cd "$(dirname "$current")" 2>/dev/null && pwd -P)" || return 1
  printf '%s/%s\n' "$dir" "$(basename "$current")"
}

checker_integrity_reason=""
verify_checker_integrity() { # verify_checker_integrity <canonical-wrapper-path>
  local wrapper="$1" physical="" dir="" libref="" libpath="" canon=""
  checker_integrity_reason=""

  # Judge the file that will actually be executed, not the name used to reach it.
  physical="$(resolve_link_chain "$wrapper" 2>/dev/null)" || physical=""
  [ -n "$physical" ] || physical="$wrapper"

  path_inside_repo "$physical" || return 0  # outside the governed repo: not our threat

  if ! file_matches_head "$physical"; then
    checker_integrity_reason="wrapper ${physical#"$repo_physical"/} is untracked or differs from HEAD"
    return 1
  fi
  wrapper="$physical"

  # The wrapper is proven to be the reviewed artifact, so its own text is now a
  # trustworthy source for WHICH runtime files it loads. Verify each of them.
  dir="$(dirname "$wrapper")"
  # Process substitution, not a pipeline: the loop must run in THIS shell so a
  # refusal can set the reason and return from the function.
  while IFS= read -r libref; do
    [ -n "$libref" ] || continue
    libpath="$dir/$libref"
    [ -e "$libpath" ] || continue
    canon="$(cd "$(dirname "$libpath")" 2>/dev/null && pwd -P)/$(basename "$libpath")" \
      || canon=""
    [ -n "$canon" ] || continue
    path_inside_repo "$canon" || continue
    if ! file_matches_head "$canon"; then
      checker_integrity_reason="runtime ${canon#"$repo_physical"/} is untracked or differs from HEAD"
      return 1
    fi
  done < <(grep -oE '\.\./lib/[A-Za-z0-9_.-]+' "$wrapper" 2>/dev/null | sort -u)
  return 0
}

resolved_cli_path=""
resolved_cli_source=""
# Set when at least one candidate was refused for integrity, so a CLI that ends
# up unresolvable can say WHY instead of reporting a plain "missing executable".
refused_cli_reason=""

# Accept a candidate only after it survives the integrity test. A refused
# candidate does not end resolution: the search continues, so an immutable
# checker installed outside the repo still takes over and enforcement is kept.
accept_candidate() { # accept_candidate <canonical-path> <source-label>
  if verify_checker_integrity "$1"; then
    resolved_cli_path="$1"
    resolved_cli_source="$2"
    return 0
  fi
  refused_cli_reason="$checker_integrity_reason (candidate $1, source=$2)"
  printf 'PRIL CHECKER_INTEGRITY_UNVERIFIED: refusing %s -- %s\n' \
    "$1" "$checker_integrity_reason" >&2
  return 1
}

resolve_cli() {
  local name="$1" candidate="" found="" user_bin=""
  resolved_cli_path=""
  resolved_cli_source=""
  refused_cli_reason=""

  if [ -n "${PLUMBLINE_BIN_DIR:-}" ]; then
    candidate="$PLUMBLINE_BIN_DIR/$name"
    found="$(canonical_executable "$candidate" 2>/dev/null)" || found=""
    if [ -n "$found" ]; then
      accept_candidate "$found" "PLUMBLINE_BIN_DIR" || :
    fi
  fi

  if [ -z "$resolved_cli_path" ]; then
    candidate="$repo/config/claude/bin/$name"
    found="$(canonical_executable "$candidate" 2>/dev/null)" || found=""
    if [ -n "$found" ]; then
      accept_candidate "$found" "project-local" || :
    fi
  fi

  if [ -z "$resolved_cli_path" ]; then
    candidate="$(command -v "$name" 2>/dev/null)" || candidate=""
    found=""
    if [ -n "$candidate" ]; then
      found="$(canonical_executable "$candidate" 2>/dev/null)" || found=""
    fi
    if [ -n "$found" ]; then
      accept_candidate "$found" "PATH" || :
    fi
  fi

  if [ -z "$resolved_cli_path" ] && [ -n "${CLAUDE_HOME:-}" ]; then
    user_bin="$CLAUDE_HOME/bin"
    found="$(canonical_executable "$user_bin/$name" 2>/dev/null)" || found=""
    if [ -n "$found" ]; then
      accept_candidate "$found" "CLAUDE_HOME/bin" || :
    fi
  fi

  if [ -z "$resolved_cli_path" ] && [ -n "${HOME:-}" ]; then
    user_bin="$HOME/.claude/bin"
    found="$(canonical_executable "$user_bin/$name" 2>/dev/null)" || found=""
    if [ -n "$found" ]; then
      accept_candidate "$found" "HOME/.claude/bin" || :
    fi
  fi

  [ -n "$resolved_cli_path" ] || return 1
  printf 'PRIL CLI resolved: %s source=%s path=%s\n' \
    "$name" "$resolved_cli_source" "$resolved_cli_path" >&2
  return 0
}

missing_clis=""
unverified_clis=""
scope_bin=""
context_bin=""
reality_bin=""
for required_cli in \
  plumbline-scope-check plumbline-context-check plumbline-reality-check
do
  if resolve_cli "$required_cli"; then
    case "$required_cli" in
      plumbline-scope-check) scope_bin="$resolved_cli_path" ;;
      plumbline-context-check) context_bin="$resolved_cli_path" ;;
      plumbline-reality-check) reality_bin="$resolved_cli_path" ;;
    esac
  elif [ -n "$refused_cli_reason" ]; then
    # A candidate existed but could not be proven to be the reviewed artifact,
    # and no immutable checker was found further down the chain. This is NOT the
    # same condition as "not installed" and must never be reported as one.
    unverified_clis="$unverified_clis $required_cli: $refused_cli_reason;"
  else
    missing_clis="$missing_clis $required_cli"
  fi
done

# Integrity is decided BEFORE any checker result is interpreted: a checker that
# cannot be proven unmodified never runs, so there is no verdict to weigh.
if [ -n "$unverified_clis" ]; then
  emit_block "PRIL_CHECKER_INTEGRITY_UNVERIFIED: a scope/context/reality checker resolved INSIDE the governed repository but is not the reviewed artifact --$unverified_clis A checker the repository under judgement could have rewritten is never executed, and no immutable checker was found elsewhere on the resolution chain. Commit the checker change (so it is tracked and identical to HEAD), or install Plumbline outside this repository, then re-run."
  exit 0
fi

# --- Advisory gates (PLUM-11/12/14/15): DEFAULT ON, NOTICE-ONLY ---------------
# These four checkers shipped fully implemented and fully tested while NOTHING
# invoked them: the hook resolved three CLIs, and they were reachable only through
# prose in the orchestrator prompt. A capability reachable only through prose is not
# wired-in-prod -- this repo's own signature failure class, committed inside the
# batch meant to close it (council finding, 2026-07-30, verified against the tree).
#
# They run by DEFAULT and they NEVER block. That combination is deliberate and was
# argued for explicitly:
#
#   * Default-ON, because for a governance check "off by default" is not safety, it
#     is ABSENCE. The measured evidence is unambiguous: in this repo the ONE artifact
#     a hook demanded (the reality ledger) sits at 9/9 features, while every
#     prompt-suggested artifact sits at 0/9. A gate nobody runs governs nothing.
#     (The `*_LIVE=1` default-off pattern elsewhere in this repo exists for LIVE
#     boundaries, where ON costs money or hits a remote. Importing it here would
#     borrow the shape of that invariant while inverting its meaning.)
#   * Notice-only, because these four legitimately need artifacts a feature may not
#     have (a declared plan, a manifest with generated_artifacts, a recorded remote
#     snapshot). Blocking on their absence would block honest work -- this repo has
#     already recorded the fail-closed gate halting its own build twice mid-build.
#     A notice informs the human without training them to ignore reds.
#
# Consequence, stated plainly so no reader has to infer it: these four are ADVISORY.
# "Fail-closed" is NOT claimed for them. The blocking gates remain scope, context and
# reality. Set PLUMBLINE_GATE_<NAME>=0 to silence one.
plan_bin=""
hygiene_bin=""
remote_bin=""
provenance_bin=""
notices=""

gate_enabled() { # gate_enabled <env-var-name>  -- default ON; only "0" disables
  # Indirect expansion, not eval: `eval "value=\"\${$1:-1}\""` executes its argument, so
  # a caller-controlled name could inject shell. Every call site passes a literal today,
  # so the live risk was nil -- but an eval in the security-relevant hook is a
  # capability nothing here needs. `${!name}` is byte-equivalent and bash-3.2 safe.
  local value="${!1:-1}"
  [ "$value" != "0" ]
}

append_notice() { # append_notice <text>
  if [ -n "$notices" ]; then
    notices="$notices
$1"
  else
    notices="$1"
  fi
}

# An advisory gate whose CLI cannot be resolved is reported, never blocked, and never
# silently skipped: a missing checker must not read as a clean check.
resolve_advisory_cli() { # resolve_advisory_cli <flag-var> <cli-name>
  gate_enabled "$1" || return 1
  if resolve_cli "$2"; then
    return 0
  fi
  append_notice "PRIL_ADVISORY_UNAVAILABLE: $2 could not be resolved, so its check did NOT run (set $1=0 to silence)."
  return 1
}

resolve_advisory_cli PLUMBLINE_GATE_PLAN plumbline-plan-check &&
  plan_bin="$resolved_cli_path"
resolve_advisory_cli PLUMBLINE_GATE_HYGIENE plumbline-runtime-hygiene &&
  hygiene_bin="$resolved_cli_path"
resolve_advisory_cli PLUMBLINE_GATE_REMOTE plumbline-remote-watch &&
  remote_bin="$resolved_cli_path"
resolve_advisory_cli PLUMBLINE_GATE_PROVENANCE plumbline-provenance-check &&
  provenance_bin="$resolved_cli_path"

if [ -n "$missing_clis" ]; then
  emit_block "PRIL_CLI_UNAVAILABLE: missing executable(s):$missing_clis. Search order: PLUMBLINE_BIN_DIR, project-local config/claude/bin, PATH, CLAUDE_HOME/bin, HOME/.claude/bin. Cannot prove gates; fix the install or escalate to the user."
  exit 0
fi

# --- I1: route all sub-command stderr to a temp dir, never the repo CWD -------
# M-2: a failed mktemp must never leave errd empty — an empty errd would write
# "/changed", "/scope", ... to the filesystem ROOT. Block instead of proceeding.
errd="$(mktemp -d)" || { emit_block "PRIL enforcement failed: scratch dir unavailable (mktemp -d). Cannot run gates safely; fix the environment or escalate to the user."; exit 0; }
if [ -z "$errd" ] || [ ! -d "$errd" ]; then
  emit_block "PRIL enforcement failed: scratch dir unavailable (mktemp -d). Cannot run gates safely; fix the environment or escalate to the user."
  exit 0
fi
trap 'rm -rf "$errd"' EXIT

fails=""

# Append one stable, machine-readable failure record. Updated PRIL wrappers emit
# a `PRIL_RUNTIME` diagnostic carrying the selected interpreter; older/external
# CLIs may not, so retain a fail-closed `unknown` value rather than inventing an
# interpreter. Exit 120 is the wrapper's tool-unavailable code, 121 is
# tool-broken. A shell-level 126/127 means the resolved CLI itself could not be
# executed and is therefore also unavailable.
append_gate_failure() {
  local gate="$1" cli="$2" rc="$3" err_file="$4"
  local runtime_line="" interpreter="unknown"
  local error_code="" error_class="" detail=""

  runtime_line="$(grep '^PRIL_RUNTIME ' "$err_file" 2>/dev/null | tail -n 1)" \
    || runtime_line=""
  if [ -n "$runtime_line" ]; then
    interpreter="$(printf '%s\n' "$runtime_line" | \
      sed -n 's/.* interpreter=\([^ ]*\).*/\1/p')"
    [ -n "$interpreter" ] || interpreter="unknown"
  fi

  case "$rc" in
    120|126|127)
      error_code="PRIL_TOOL_UNAVAILABLE"
      error_class="tool_unavailable"
      ;;
    121)
      error_code="PRIL_TOOL_BROKEN"
      error_class="tool_broken"
      ;;
    122)
      # NEW-1: the checker could not be invoked, so it produced no verdict at
      # all. Kept out of the 2|3|4 policy arm deliberately -- reading a usage
      # error as a policy result is what made a mis-invoked checker look like a
      # clean "nothing to check".
      error_code="PRIL_TOOL_INVOCATION_ERROR"
      error_class="tool_invocation_error"
      ;;
    2|3|4)
      error_code="PRIL_POLICY_VIOLATION"
      error_class="policy_violation"
      ;;
    *)
      error_code="PRIL_TOOL_BROKEN"
      error_class="tool_broken"
      ;;
  esac

  detail="$error_code: gate=$gate cli=$cli interpreter=$interpreter error_class=$error_class exit_code=$rc"
  if [ -n "$fails" ]; then
    fails="$fails; $detail"
  else
    fails="$detail"
  fi
}

# --- C2 scope surface: the WHOLE feature surface, not bare `git diff` ----------
# resolved merge-base..HEAD (committed feature work) UNION working-tree UNION
# staged UNION untracked-non-ignored, sorted-unique. Bare `git diff --name-only`
# is vacuous on a committed tree (would fail open); this reads the real ground
# truth. A missing/unrelated base is NOT replaced by HEAD: HEAD...HEAD is a
# false-green empty surface.
#
# Explicit stack pins are authoritative. `PLUMBLINE_STACK_BASE` is canonical;
# `PLUMBLINE_BASE_REF` is accepted as a compatibility alias. Auto-resolution:
# remote default -> origin/main -> origin/master -> local main -> local master.
base_ref=""
base_commit=""
base_merge=""
base_source=""
base_error_code=""
base_error_ref=""

try_git_base() {
  local candidate="$1" source="$2" commit="" common=""
  case "$candidate" in
    ""|-*) return 1 ;;
  esac
  commit="$(git -C "$repo" rev-parse --verify "${candidate}^{commit}" \
    2>/dev/null)" || return 1
  [ -n "$commit" ] || return 1
  common="$(git -C "$repo" merge-base HEAD "$commit" 2>/dev/null)" || return 2
  [ -n "$common" ] || return 2
  base_ref="$candidate"
  base_commit="$commit"
  base_merge="$common"
  base_source="$source"
  return 0
}

resolve_git_base() {
  local explicit="" remote_default="" candidate="" source="" rc=0

  if [ -n "${PLUMBLINE_STACK_BASE:-}" ] && \
     [ -n "${PLUMBLINE_BASE_REF:-}" ] && \
     [ "$PLUMBLINE_STACK_BASE" != "$PLUMBLINE_BASE_REF" ]; then
    base_error_code="PRIL_GIT_BASE_CONFLICT"
    base_error_ref="$PLUMBLINE_STACK_BASE != $PLUMBLINE_BASE_REF"
    return 1
  fi

  if [ -n "${PLUMBLINE_STACK_BASE:-}" ]; then
    explicit="$PLUMBLINE_STACK_BASE"
    source="PLUMBLINE_STACK_BASE"
  elif [ -n "${PLUMBLINE_BASE_REF:-}" ]; then
    explicit="$PLUMBLINE_BASE_REF"
    source="PLUMBLINE_BASE_REF"
  fi

  if [ -n "$explicit" ]; then
    try_git_base "$explicit" "$source"
    rc=$?
    if [ "$rc" -eq 0 ]; then
      return 0
    elif [ "$rc" -eq 2 ]; then
      base_error_code="PRIL_GIT_BASE_UNRELATED"
    else
      base_error_code="PRIL_GIT_BASE_UNRESOLVED"
    fi
    base_error_ref="$explicit"
    return 1
  fi

  remote_default="$(git -C "$repo" symbolic-ref --quiet --short \
    refs/remotes/origin/HEAD 2>/dev/null)" || remote_default=""
  if [ -n "$remote_default" ]; then
    try_git_base "$remote_default" "remote-default"
    rc=$?
    if [ "$rc" -eq 0 ]; then
      return 0
    elif [ "$rc" -eq 2 ]; then
      base_error_code="PRIL_GIT_BASE_UNRELATED"
      base_error_ref="$remote_default"
      return 1
    fi
  fi

  for candidate in origin/main origin/master main master
  do
    case "$candidate" in
      origin/main) source="origin-main" ;;
      origin/master) source="origin-master" ;;
      main) source="local-main" ;;
      master) source="local-master" ;;
    esac
    try_git_base "$candidate" "$source"
    rc=$?
    if [ "$rc" -eq 0 ]; then
      return 0
    elif [ "$rc" -eq 2 ]; then
      base_error_code="PRIL_GIT_BASE_UNRELATED"
      base_error_ref="$candidate"
      return 1
    fi
  done

  base_error_code="PRIL_GIT_BASE_UNRESOLVED"
  base_error_ref="remote default, origin/main, origin/master, main, master"
  return 1
}

if ! resolve_git_base; then
  emit_block "$base_error_code: cannot establish a related Git baseline ($base_error_ref). Set PLUMBLINE_STACK_BASE to the intended parent for a stacked branch; refusing a false-green HEAD...HEAD fallback."
  exit 0
fi

printf 'PRIL Git base resolved: ref=%s source=%s commit=%s merge-base=%s\n' \
  "$base_ref" "$base_source" "$base_commit" "$base_merge" >&2

# Collect each surface independently and check every Git command. A failed diff
# command must not disappear behind the final `sort` process in a pipeline.
if ! git -C "$repo" diff --name-only "$base_merge"...HEAD \
  >"$errd/committed" 2>"$errd/git-committed" ||
   ! git -C "$repo" diff --name-only \
  >"$errd/working" 2>"$errd/git-working" ||
   ! git -C "$repo" diff --name-only --cached \
  >"$errd/staged" 2>"$errd/git-staged" ||
   ! git -C "$repo" ls-files --others --exclude-standard \
  >"$errd/untracked" 2>"$errd/git-untracked"
then
  emit_block "PRIL_GIT_DIFF_UNAVAILABLE: Git could not enumerate the complete committed, working, staged, and untracked change surface. Refusing an incomplete scope proof."
  exit 0
fi
if ! sort -u "$errd/committed" "$errd/working" "$errd/staged" \
  "$errd/untracked" >"$errd/changed"
then
  emit_block "PRIL_GIT_DIFF_UNAVAILABLE: could not assemble the complete Git change surface. Refusing an incomplete scope proof."
  exit 0
fi

# Scope guard: changed files must stay inside the feature's allowed scope.
if PLUMBLINE_RUNTIME_DIAGNOSTICS=1 \
  "$scope_bin" --repo "$repo" --feature "$feat" \
  --changed-files "$errd/changed" >/dev/null 2>"$errd/scope"
then
  :
else
  gate_rc=$?
  append_gate_failure \
    "scope" "plumbline-scope-check" "$gate_rc" "$errd/scope"
fi

# Context gate: confirmed product context must exist for the feature.
if PLUMBLINE_RUNTIME_DIAGNOSTICS=1 \
  "$context_bin" --repo "$repo" --feature "$feat" \
  >/dev/null 2>"$errd/ctx"
then
  :
else
  gate_rc=$?
  append_gate_failure \
    "context" "plumbline-context-check" "$gate_rc" "$errd/ctx"
fi

# --- I2: reality gate mirrors the feature's boundary class --------------------
# Only a feature that declares an integration boundary (docs/context/.feature-
# boundary marker) is held to integration-class evidence. A pure-logic feature
# has no integration boundary to evidence, so we SKIP the reality gate entirely
# rather than block it for lacking a ledger it never needed. We cannot express
# "presence-only" via --min-evidence (plumbline_reality.FORBIDDEN_TOKENS rejects
# the "fake-only" token), so the correct behavior is to skip, not invent a floor.
if [ -f "$repo/docs/context/.feature-boundary" ]; then
  if PLUMBLINE_RUNTIME_DIAGNOSTICS=1 \
    "$reality_bin" --repo "$repo" --feature "$feat" \
    --min-evidence integration >/dev/null 2>"$errd/real"
  then
    :
  else
    gate_rc=$?
    append_gate_failure \
      "reality" "plumbline-reality-check" "$gate_rc" "$errd/real"
  fi
fi

# --- Advisory gates: run, report, never block ---------------------------------
# Each runs against the SAME ground-truth surface the blocking gates use.
run_advisory() { # run_advisory <bin> <label> <args...>
  local bin="$1" label="$2"
  shift 2
  [ -n "$bin" ] || return 0
  local out="$errd/adv-$label"
  local rc=0
  # Capture the status explicitly rather than reading $? after an `if`: the compound
  # resets it, which silently reported every advisory finding as exit=0.
  PLUMBLINE_RUNTIME_DIAGNOSTICS=1 "$bin" "$@" >"$out" 2>&1
  rc=$?
  [ "$rc" -eq 0 ] && return 0
  local first=""
  # PRODUCER_ was missing, so PRODUCER_OUT_OF_SCOPE fell through to `head -n 1` and
  # reported an unrelated line. Take the LAST match: the classified verdict follows any
  # progress output rather than preceding it.
  first="$(grep -E '^(ERROR|VIOLATION|PROVENANCE_|PRODUCER_|ARTIFACT_|NONDETERMINISTIC_|MISSING_|REMOTE_STATE_|EVIDENCE_)' "$out" 2>/dev/null | tail -n 1)"
  [ -n "$first" ] || first="$(head -n 1 "$out" 2>/dev/null)"
  # Reuse the blocking path's vocabulary so "could not run" never reads like "ran and
  # found something" -- the whole point of reserving 120/121.
  local klass=""
  case "$rc" in
    120|126|127) klass="PRIL_TOOL_UNAVAILABLE" ;;
    121)         klass="PRIL_TOOL_BROKEN" ;;
    122)         klass="PRIL_TOOL_INVOCATION_ERROR" ;;
    2)           klass="PRIL_INPUT_MISSING" ;;
    3|4)         klass="PRIL_POLICY_FINDING" ;;
    *)           klass="PRIL_TOOL_BROKEN" ;;
  esac
  append_notice "PRIL_ADVISORY $label $klass exit=$rc: ${first:-(no output)}"
}

if [ -n "$plan_bin" ]; then
  # Last plan naming this feature in glob (lexicographic) order -- correct for the
  # date-prefixed convention docs/plans/YYYY-MM-DD-<feature>.md, and NOT an mtime sort.
  # Absent is normal, not a finding.
  plan_file=""
  for candidate in "$repo/docs/plans/"*"$feat"*.md; do
    [ -f "$candidate" ] && plan_file="$candidate"
  done
  if [ -n "$plan_file" ]; then
    run_advisory "$plan_bin" plan \
      --repo "$repo" --feature "$feat" --plan "$plan_file"
  fi
fi

run_advisory "$hygiene_bin" hygiene --repo "$repo"

if [ -n "$remote_bin" ] &&
   [ -f "$repo/docs/context/$feat.remote-state.json" ] &&
   [ "${PLUMBLINE_REMOTE_LIVE:-0}" = "1" ]; then
  # Three conditions, and the live gate is not optional here.
  #
  # `verify` needs the forge half of the state. From the hook there is no
  # --pr-state-file to inject, so without PLUMBLINE_REMOTE_LIVE it ALWAYS returns
  # EXIT_MISSING ("the forge half is unavailable") -- a guaranteed notice on every
  # single Stop, forever, for any feature that ever snapshotted. That is precisely the
  # alarm fatigue this file argues against twenty lines above; a gate whose output is
  # constant carries no information.
  #
  # The live path also crosses a network boundary inside a hook with a 15s registered
  # timeout. If it overruns, the harness kills the hook and the BLOCKING scope/context/
  # reality decision is lost with it -- an advisory gate turning a would-be block into
  # a pass, which is strictly worse than not running it. plumbline_remote.py caps the
  # forge call well inside that budget.
  run_advisory "$remote_bin" remote verify --repo "$repo" --feature "$feat"
fi

run_advisory "$provenance_bin" provenance \
  --repo "$repo" --feature "$feat" --changed-files "$errd/changed"

# --- Decision: fail CLOSED on any BLOCKING gate failure ------------------------
# Advisory notices are attached to the block reason when one is emitted, and printed
# to stderr otherwise. They never turn a pass into a block: that is what "advisory"
# means, and saying so here keeps the distinction unmissable for the next reader.
if [ -n "$notices" ]; then
  printf 'PRIL advisory notices (do NOT block; these gates are ADVISORY):\n%s\n' \
    "$notices" >&2
fi

if [ -n "$fails" ]; then
  block_reason="PRIL enforcement failed: $fails. Fix the failing gate(s) or escalate to the user; do not finish with a failing gate."
  if [ -n "$notices" ]; then
    block_reason="$block_reason ADVISORY (non-blocking) notices this run: $notices"
  fi
  emit_block "$block_reason"
fi

exit 0
