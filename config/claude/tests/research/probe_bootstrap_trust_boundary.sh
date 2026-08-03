#!/usr/bin/env bash
#
# RESEARCH PROBE -- NOT a product regression test. Deliberately NOT registered in
# config/claude/tests/run_all.sh.
#
#   A SUCCESSFUL RUN OF THIS PROBE CONFIRMS THE WEAKNESS IS STILL REPRODUCIBLE.
#   IT DOES NOT FIX ANYTHING. `PROBE_RESULT=WEAKNESS_CONFIRMED` together with
#   exit 0 means "the probe ran correctly and the bypass is still open", NOT
#   "the tree is healthy".
#
# Baseline under probe: agent/fix-plum-12-scope-drift @ 42320c320e0827d02d777866aab3dcbf7dab91b0
#
# ---------------------------------------------------------------------------
# What is being probed
# ---------------------------------------------------------------------------
# The governed repository must not supply any program the gate runs before
# independent authority is selected. Two layers fail that today.
#
# (1) INTERPRETER. pretool-scope-gate.sh runs PATH-resolved python3 at :77 (Bash
#     arm), :202 (manifest classifier), and :253/:270 (checker provenance).
#     Independent checker resolution only begins at :243. The classifier at :202
#     feeds `[ "$manifest_kind" = "legacy" ] && exit 0`, so a shim printing one
#     word disables the gate.
#
# (2) BOOTSTRAP TOOLS. Earlier still, the hook runs PATH-resolved `cat` (:10),
#     `jq` (:17) or `sed`+`head` (:25-41), and `tr` (:59). Each feeds a fail-OPEN
#     branch:
#         :11  [ -n "$PAYLOAD" ] || exit 0      <- repo-owned cat prints nothing
#         :53  case "$tool_name" in *) exit 0   <- repo-owned jq prints nothing
#         :60  [ -n "$feature" ] || exit 0      <- repo-owned tr prints nothing
#     A repository-owned parser therefore sets the gate fail-open exactly like
#     the Python shim, which is why an interpreter-only resolver cannot close it.
#
# (3) STOP HOOK (classified SEPARATELY -- not PLUM-12). In plumbline-enforce.sh
#     `git` is not a helper, it is the ground truth: the changed-file surface
#     (:533-558) and file_matches_head (:207-212) -- the checker-integrity test
#     itself -- are git calls.
#
# ---------------------------------------------------------------------------
# How a case is judged
# ---------------------------------------------------------------------------
# Every negative case reports three INDEPENDENT observations, because any one of
# them alone can pass for the wrong reason:
#     executed  -- did the repository-owned program actually run?
#     decision  -- allow or deny
#     target    -- unchanged or modified (the harness performs the write when the
#                  gate does not deny, so file bytes are the falsifier; a
#                  text-only assertion would also be satisfied by a Stop-time
#                  block that happens after the write landed)
# Verdicts:
#     FULL_BYPASS     executed AND allowed AND the unplanned write landed
#     EXECUTION_ONLY  executed, but the outcome still failed closed (incidentally)
#     NOT_REPRODUCED  the repository-owned program never ran
#
# Portability: bash-3.2 safe (NO $()-wrapped heredocs), shellcheck-clean.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../../.." && pwd)"

PRETOOL="$REPO_DIR/config/claude/hooks/pretool-scope-gate.sh"
STOP_HOOK="$REPO_DIR/config/claude/hooks/plumbline-enforce.sh"
BIN_SRC="$REPO_DIR/config/claude/bin"
BASELINE="42320c320e0827d02d777866aab3dcbf7dab91b0"

echo "probe_bootstrap_trust_boundary -- RESEARCH PROBE (confirms a weakness; fixes nothing)"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# An isolated CLAUDE_HOME. Without it the fixtures silently resolve the MACHINE's
# installed plumbline-scope-check ($HOME/.claude/bin), which on a developer box
# points at a different checkout: the probe would then measure that install.
ISOLATED_CLAUDE_HOME="$WORK/claude-home"
mkdir -p "$ISOLATED_CLAUDE_HOME/bin"

RESULTS="$WORK/results"
: >"$RESULTS"
PROBE_INVALID=0

record() { # record <id> <class> <tool> <executed> <decision> <target> <verdict> <note>
  printf 'CASE %s class=%s tool=%s repo_program_executed=%s decision=%s target=%s verdict=%s note=%s\n' \
    "$1" "$2" "$3" "$4" "$5" "$6" "$7" "$8" >>"$RESULTS"
  printf '  %-5s %-22s executed=%-3s decision=%-5s target=%-9s -> %s\n' \
    "$1" "$3" "$4" "$5" "$6" "$7"
}

# --------------------------------------------------------------- toolchain ---
# An interpreter that cannot execute a trivial program is not an interpreter, and
# a wrapper that re-execs another resolver (e.g. `exec uv run python3 "$@"`) is
# not stable here: it re-resolves against the caller's HOME, which these fixtures
# deliberately move. Either would break every fixture and the wreckage would read
# like "no weakness found".
python_ok() {
  [ -x "$1" ] || return 1
  if head -c 400 "$1" 2>/dev/null | grep -q 'uv run'; then
    return 1
  fi
  po_out="$("$1" -c 'print("PYOK")' 2>/dev/null || true)"
  [ "$po_out" = "PYOK" ]
}

CLEAN_PATH=""
REAL_PYTHON=""
_old_ifs="$IFS"
IFS=':'
for _p in $PATH; do
  [ -n "$_p" ] || continue
  [ -e "$_p/plumbline-scope-check" ] && continue
  [ -e "$_p/plumbline-plan-check" ] && continue
  if [ -e "$_p/python3" ] && ! python_ok "$_p/python3"; then
    continue
  fi
  if [ -z "$REAL_PYTHON" ] && [ -x "$_p/python3" ]; then
    REAL_PYTHON="$_p/python3"
  fi
  if [ -n "$CLEAN_PATH" ]; then CLEAN_PATH="$CLEAN_PATH:$_p"; else CLEAN_PATH="$_p"; fi
done
IFS="$_old_ifs"

# A PATH with no jq, so the hook's SECOND parser (sed + head, :25-41) is really
# reached. With real jq present the jq branch wins at :17 and sed never runs.
NOJQ_PATH=""
_old_ifs="$IFS"
IFS=':'
for _p in $CLEAN_PATH; do
  [ -n "$_p" ] || continue
  [ -e "$_p/jq" ] && continue
  if [ -n "$NOJQ_PATH" ]; then NOJQ_PATH="$NOJQ_PATH:$_p"; else NOJQ_PATH="$_p"; fi
done
IFS="$_old_ifs"

# A PATH that still has a working shell and coreutils but NO external python3 and
# NO external uv, so "the only interpreter available is repository-owned" can be
# probed for real. Pinning PATH to the repo directory alone does NOT do that: env
# then cannot even find `bash`, the hook never runs, and rc=127 reads as
# "not reproduced" while nothing was measured.
NOPY_PATH=""
_old_ifs="$IFS"
IFS=':'
for _p in $CLEAN_PATH; do
  [ -n "$_p" ] || continue
  [ -e "$_p/python3" ] && continue
  [ -e "$_p/uv" ] && continue
  if [ -n "$NOPY_PATH" ]; then NOPY_PATH="$NOPY_PATH:$_p"; else NOPY_PATH="$_p"; fi
done
IFS="$_old_ifs"

if [ -z "$REAL_PYTHON" ]; then
  echo "PROBE INVALID: no working external python3 on PATH" >&2
  printf 'PROBE_RESULT=PROBE_INVALID reason=no-external-python3\n'
  exit 2
fi
printf '   baseline: %s\n' "$BASELINE"
printf '   external interpreter: %s\n' "$REAL_PYTHON"

# ---------------------------------------------------------------- fixtures ---
# An armed canonical repo whose plan declares exactly one product file.
# src/demo/unplanned.py is inside the manifest scope but NOT in the plan.
make_repo() {
  mr_repo="$1"
  mkdir -p "$mr_repo/docs/scope" "$mr_repo/docs/canvas" "$mr_repo/docs/plans" \
           "$mr_repo/docs/context" "$mr_repo/src/demo" "$mr_repo/config/claude/tests"
  printf 'demo\n' >"$mr_repo/docs/context/.active-feature"
  cat >"$mr_repo/docs/canvas/demo.canvas.md" <<'EOF'
# Product Canvas: demo

Status: user-confirmed

## Allowed change scope

Status: CONFIRMED

Scope manifest: `docs/scope/demo.scope.json`
EOF
  cat >"$mr_repo/docs/plans/2026-07-29-demo.md" <<'EOF'
# Demo implementation plan

- Create: `src/demo/app.py`
- Modify: `config/claude/tests/test_demo.sh`
- Modify: `docs/scope/demo.scope.json`
- Delete: `src/demo/old.py`
- Test: `bash config/claude/tests/test_demo.sh`
EOF
  printf 'print("app")\n' >"$mr_repo/src/demo/app.py"
  printf '.plumbline/\ndocs/context/.active-feature\n' >"$mr_repo/.gitignore"
  "$REAL_PYTHON" - "$mr_repo/docs/scope/demo.scope.json" <<'PY'
import hashlib
import json
import sys

scope = {
    "product": ["src/demo/**"],
    "governance": [
        "config/claude/tests/test_demo.sh",
        "docs/canvas/demo.canvas.md",
        "docs/plans/2026-07-29-demo.md",
        "docs/scope/demo.scope.json",
    ],
}
payload = json.dumps(scope, sort_keys=True, separators=(",", ":")).encode()
manifest = {
    "schema_version": 1,
    "feature": "demo",
    "scope": scope,
    "artifacts": {
        "canvas": "docs/canvas/demo.canvas.md",
        "plan": "docs/plans/2026-07-29-demo.md",
    },
    "provenance": [{
        "revision": 1,
        "origin": "jira:PLUM-12",
        "decision_maker": "test-user",
        "decided_at": "2026-07-29T20:00:00+00:00",
        "rationale": "Confirmed pilot scope",
        "confirmed": True,
        "scope": scope,
        "scope_digest": "sha256:" + hashlib.sha256(payload).hexdigest(),
    }],
}
with open(sys.argv[1], "w", encoding="utf-8") as handle:
    json.dump(manifest, handle, indent=2)
    handle.write("\n")
PY
  git -C "$mr_repo" init -q
  git -C "$mr_repo" config user.email plum12@example.com
  git -C "$mr_repo" config user.name "PLUM-12 Probe"
  git -C "$mr_repo" checkout -q -b main
  git -C "$mr_repo" add -A
  git -C "$mr_repo" commit -q -m "baseline: confirmed manifest, plan, context"
  git -C "$mr_repo" checkout -q -b feat/demo
}

MARK="PROJECT_OWNED_PROGRAM_EXECUTED"

# A repository-owned program that records that it ran, drains stdin, prints
# nothing and exits 0 -- the shape every fail-open branch rewards. For python3
# the empty stdout is exactly the classifier answer that drives the no-op path,
# so one body covers both layers; `legacy` is printed only for python3.
plant_shim() { # plant_shim <repo> <dir> <tool> <marker>
  ps_repo="$1"; ps_dir="$2"; ps_tool="$3"; ps_marker="$4"
  mkdir -p "$ps_repo/$ps_dir"
  {
    printf '#!/bin/sh\n'
    printf 'printf "%s %s\\n" >>"%s"\n' "$MARK" "$ps_tool" "$ps_marker"
    printf 'cat >/dev/null 2>&1 || true\n'
    if [ "$ps_tool" = "python3" ]; then
      printf 'printf "legacy\\n"\n'
    fi
    printf 'exit 0\n'
  } >"$ps_repo/$ps_dir/$ps_tool"
  chmod +x "$ps_repo/$ps_dir/$ps_tool"
}

# A repository-owned program that BEHAVES CORRECTLY (delegates) but records that
# it ran. Needed where a misbehaving shim would make the case fail for the wrong
# reason: containment must reject a repository-owned program even when honest.
plant_delegating_shim() { # plant_delegating_shim <repo> <dir> <tool> <marker> <real>
  pd_repo="$1"; pd_dir="$2"; pd_tool="$3"; pd_marker="$4"; pd_real="$5"
  mkdir -p "$pd_repo/$pd_dir"
  {
    printf '#!/bin/sh\n'
    printf 'printf "%s %s\\n" >>"%s"\n' "$MARK" "$pd_tool" "$pd_marker"
    printf 'exec "%s" "$@"\n' "$pd_real"
  } >"$pd_repo/$pd_dir/$pd_tool"
  chmod +x "$pd_repo/$pd_dir/$pd_tool"
}

# ------------------------------------------------------------------ driver ---
GATE_OUT=""; GATE_RC=""; GATE_DECISION=""
run_pretool() { # run_pretool <repo> <payload> <path> [NAME=value ...]
  rp_repo="$1"; rp_payload="$2"; rp_path="$3"
  shift 3
  rp_out="$(mktemp -p "$WORK")"
  env -i PATH="$rp_path" HOME="$ISOLATED_CLAUDE_HOME" \
    CLAUDE_HOME="$ISOLATED_CLAUDE_HOME" CLAUDE_PROJECT_DIR="$rp_repo" "$@" \
    bash "$PRETOOL" >"$rp_out" 2>/dev/null <<EOF
$rp_payload
EOF
  GATE_RC=$?
  GATE_OUT="$(cat "$rp_out")"
  rm -f "$rp_out"
  GATE_DECISION="allow"
  case "$GATE_OUT" in *'"decision"'*'"deny"'*) GATE_DECISION="deny" ;; esac
  return 0
}

run_stop() { # run_stop <repo> <path> [NAME=value ...]
  rs_repo="$1"; rs_path="$2"
  shift 2
  rs_out="$(mktemp -p "$WORK")"
  env -i PATH="$rs_path" HOME="$ISOLATED_CLAUDE_HOME" \
    CLAUDE_HOME="$ISOLATED_CLAUDE_HOME" CLAUDE_PROJECT_DIR="$rs_repo" "$@" \
    bash "$STOP_HOOK" >"$rs_out" 2>/dev/null <<'EOF'
{}
EOF
  GATE_RC=$?
  GATE_OUT="$(cat "$rs_out")"
  rm -f "$rs_out"
  GATE_DECISION="allow"
  case "$GATE_OUT" in *'"decision"'*'"block"'*) GATE_DECISION="deny" ;; esac
  return 0
}

digest() { if [ -f "$1" ]; then shasum -a 256 "$1" | cut -d' ' -f1; else printf 'ABSENT'; fi; }

UNPLANNED='{"tool_name":"Write","tool_input":{"file_path":"src/demo/unplanned.py","content":"x"}}'
TARGET="src/demo/unplanned.py"

slug() { printf '%s' "$1" | tr -cd 'A-Za-z0-9'; }

# negative_case <id> <tool> <shim-kind: hostile|delegating> <where: path|env|symlink-*>
#               <path-suffix> [NAME=value ...]
negative_case() {
  nc_id="$1"; nc_tool="$2"; nc_kind="$3"; nc_dir="$4"; nc_suffix="$5"
  shift 5
  nc_repo="$WORK/$(slug "$nc_id")"
  rm -rf "$nc_repo"; mkdir -p "$nc_repo"
  make_repo "$nc_repo"
  nc_marker="$WORK/marker-$(slug "$nc_id")"
  : >"$nc_marker"
  if [ "$nc_kind" = "delegating" ]; then
    plant_delegating_shim "$nc_repo" "$nc_dir" "$nc_tool" "$nc_marker" "$REAL_PYTHON"
  else
    plant_shim "$nc_repo" "$nc_dir" "$nc_tool" "$nc_marker"
  fi

  nc_before="$(digest "$nc_repo/$TARGET")"
  run_pretool "$nc_repo" "$UNPLANNED" "$nc_repo/$nc_dir:$nc_suffix" "$@"
  if [ "$GATE_DECISION" != "deny" ]; then
    printf '# the permitted action executed\n' >>"$nc_repo/$TARGET"
  fi
  nc_after="$(digest "$nc_repo/$TARGET")"

  finish_case "$nc_id" "$nc_tool" "$nc_marker" "$nc_before" "$nc_after"
}

finish_case() { # finish_case <id> <tool> <marker> <before> <after>
  fc_exec=no
  grep -Fq "$MARK" "$3" 2>/dev/null && fc_exec=yes
  if [ "$4" = "$5" ]; then fc_target=unchanged; else fc_target=modified; fi
  if [ "$fc_exec" = "yes" ] && [ "$GATE_DECISION" = "allow" ] && [ "$fc_target" = "modified" ]; then
    fc_verdict=FULL_BYPASS
  elif [ "$fc_exec" = "yes" ]; then
    fc_verdict=EXECUTION_ONLY
  elif [ "$GATE_DECISION" = "allow" ] && [ "$fc_target" = "modified" ]; then
    # The gate let the unplanned write through WITHOUT running anything the
    # repository owns. That is a distinct finding, not an absence of one: it is
    # the same fail-open branch reached by the ABSENCE of an external parser
    # rather than by a hostile one. Recording it as NOT_REPRODUCED would hide it.
    fc_verdict=FAIL_OPEN_NO_REPO_PROGRAM
  else
    fc_verdict=NOT_REPRODUCED
  fi
  record "$1" negative "$2" "$fc_exec" "$GATE_DECISION" "$fc_target" "$fc_verdict" "rc=$GATE_RC"
}

echo "-- negative cases: interpreter layer"

negative_case N1  python3 hostile ".venv/bin" "$CLEAN_PATH"
negative_case N4  python3 hostile "tools/bin" "$CLEAN_PATH"

# N2 -- entry OUTSIDE the repo, real symlink target INSIDE it.
n2_repo="$WORK/n2"; mkdir -p "$n2_repo"; make_repo "$n2_repo"
n2_marker="$WORK/marker-n2"; : >"$n2_marker"
plant_shim "$n2_repo" "internal/bin" python3 "$n2_marker"
n2_outside="$WORK/n2-outside"; mkdir -p "$n2_outside"
ln -s "$n2_repo/internal/bin/python3" "$n2_outside/python3"
n2_before="$(digest "$n2_repo/$TARGET")"
run_pretool "$n2_repo" "$UNPLANNED" "$n2_outside:$CLEAN_PATH"
if [ "$GATE_DECISION" != "deny" ]; then printf 'x\n' >>"$n2_repo/$TARGET"; fi
finish_case N2 "python3(symlink-in)" "$n2_marker" "$n2_before" "$(digest "$n2_repo/$TARGET")"

# N3 -- entry INSIDE the repo, real target OUTSIDE it. The shim DELEGATES, so the
# gate behaves normally: only the execution marker can decide this case.
negative_case N3 python3 delegating "internal/bin" "$CLEAN_PATH"

# N5 -- PLUMBLINE_PYTHON pointing inside the governed repo.
n5_repo="$WORK/n5"; mkdir -p "$n5_repo"; make_repo "$n5_repo"
n5_marker="$WORK/marker-n5"; : >"$n5_marker"
plant_shim "$n5_repo" "tools/bin" python3 "$n5_marker"
n5_before="$(digest "$n5_repo/$TARGET")"
run_pretool "$n5_repo" "$UNPLANNED" "$CLEAN_PATH" "PLUMBLINE_PYTHON=$n5_repo/tools/bin/python3"
if [ "$GATE_DECISION" != "deny" ]; then printf 'x\n' >>"$n5_repo/$TARGET"; fi
finish_case N5 "python3(PLUMBLINE_PYTHON)" "$n5_marker" "$n5_before" "$(digest "$n5_repo/$TARGET")"

# N6 -- the ONLY interpreter reachable is repository-owned: must fail CLOSED.
# The shell and coreutils stay external (NOPY_PATH), otherwise the hook cannot
# start at all and the case measures nothing.
if [ -n "$NOPY_PATH" ]; then
  n6_repo="$WORK/n6"; mkdir -p "$n6_repo"; make_repo "$n6_repo"
  n6_marker="$WORK/marker-n6"; : >"$n6_marker"
  plant_shim "$n6_repo" "only/bin" python3 "$n6_marker"
  n6_before="$(digest "$n6_repo/$TARGET")"
  run_pretool "$n6_repo" "$UNPLANNED" "$n6_repo/only/bin:$NOPY_PATH"
  if [ "$GATE_DECISION" != "deny" ]; then printf 'x\n' >>"$n6_repo/$TARGET"; fi
  finish_case N6 "python3(only-candidate)" "$n6_marker" "$n6_before" "$(digest "$n6_repo/$TARGET")"
else
  record N6 negative "python3(only-candidate)" skipped n/a n/a NOT_REPRODUCED no-python-free-PATH-available
fi

echo "-- negative cases: bootstrap-tool layer"

negative_case N7  jq  hostile "tools/bin" "$CLEAN_PATH"
negative_case N8  cat hostile "tools/bin" "$CLEAN_PATH"
if [ -n "$NOJQ_PATH" ]; then
  negative_case N8b sed hostile "tools/bin" "$NOJQ_PATH"
else
  record N8b negative sed skipped n/a n/a NOT_REPRODUCED no-jq-free-PATH-available
fi
negative_case N10 tr  hostile "tools/bin" "$CLEAN_PATH"
negative_case N9  uv  hostile "tools/bin" "$CLEAN_PATH"

echo "-- negative cases: Stop hook (S2 is a SEPARATE finding, not PLUM-12)"

# S1 -- repository-owned python3 against the Stop hook.
s1_repo="$WORK/s1"; mkdir -p "$s1_repo"; make_repo "$s1_repo"
s1_marker="$WORK/marker-s1"; : >"$s1_marker"
plant_shim "$s1_repo" ".venv/bin" python3 "$s1_marker"
mkdir -p "$s1_repo/tools"; printf 'pwned\n' >"$s1_repo/tools/hack.sh"
git -C "$s1_repo" add -A >/dev/null 2>&1
git -C "$s1_repo" commit -q -m "out-of-scope change" >/dev/null 2>&1
run_stop "$s1_repo" "$s1_repo/.venv/bin:$CLEAN_PATH" "PLUMBLINE_BIN_DIR=$BIN_SRC"
s1_exec=no; grep -Fq "$MARK" "$s1_marker" 2>/dev/null && s1_exec=yes
if [ "$s1_exec" = yes ]; then s1_v=EXECUTION_ONLY; else s1_v=NOT_REPRODUCED; fi
record S1 negative "python3(stop)" "$s1_exec" "$GATE_DECISION" n/a "$s1_v" stop-hook

# S2 -- repository-owned git against the Stop hook, where git IS the ground truth.
s2_repo="$WORK/s2"; mkdir -p "$s2_repo"; make_repo "$s2_repo"
mkdir -p "$s2_repo/tools"; printf 'pwned\n' >"$s2_repo/tools/hack.sh"
git -C "$s2_repo" add -A >/dev/null 2>&1
git -C "$s2_repo" commit -q -m "out-of-scope change" >/dev/null 2>&1
s2_marker="$WORK/marker-s2"; : >"$s2_marker"
plant_shim "$s2_repo" "tools/bin" git "$s2_marker"
run_stop "$s2_repo" "$s2_repo/tools/bin:$CLEAN_PATH" "PLUMBLINE_BIN_DIR=$BIN_SRC"
s2_exec=no; grep -Fq "$MARK" "$s2_marker" 2>/dev/null && s2_exec=yes
if [ "$s2_exec" = yes ]; then s2_v=EXECUTION_ONLY; else s2_v=NOT_REPRODUCED; fi
record S2 negative "git(stop)" "$s2_exec" "$GATE_DECISION" n/a "$s2_v" separate-finding-not-plum-12

echo "-- positive controls (a fix must keep these)"

positive_case() { # positive_case <id> <label> <payload> <want-decision> [mode]
  pc_id="$1"; pc_label="$2"; pc_payload="$3"; pc_want="$4"; pc_mode="${5:-armed}"
  pc_repo="$WORK/$(slug "$pc_id")"
  rm -rf "$pc_repo"; mkdir -p "$pc_repo"
  make_repo "$pc_repo"
  [ "$pc_mode" = "unarmed" ] && rm -f "$pc_repo/docs/context/.active-feature"
  if [ "$pc_mode" = "repo-checker" ]; then
    mkdir -p "$pc_repo/config/claude/bin"
    printf '#!/bin/sh\nexit 0\n' >"$pc_repo/config/claude/bin/plumbline-scope-check"
    chmod +x "$pc_repo/config/claude/bin/plumbline-scope-check"
  fi
  pc_before="$(digest "$pc_repo/$TARGET")"
  run_pretool "$pc_repo" "$pc_payload" "$CLEAN_PATH"
  if [ "$GATE_DECISION" != "deny" ] && [ "$pc_want" = "deny" ]; then
    printf 'x\n' >>"$pc_repo/$TARGET"
  fi
  pc_after="$(digest "$pc_repo/$TARGET")"
  if [ "$GATE_DECISION" = "$pc_want" ]; then
    pc_v=CONTROL_OK
  else
    pc_v=CONTROL_BROKEN
    PROBE_INVALID=1
  fi
  if [ "$pc_before" = "$pc_after" ]; then pc_t=unchanged; else pc_t=modified; fi
  record "$pc_id" positive "$pc_label" no "$GATE_DECISION" "$pc_t" "$pc_v" "want=$pc_want"
}

positive_case P1 external-interpreter "$UNPLANNED" deny
positive_case P2 planned-edit \
  '{"tool_name":"Edit","tool_input":{"file_path":"src/demo/app.py","old_string":"a","new_string":"b"}}' allow
positive_case P3 unarmed-session "$UNPLANNED" allow unarmed
positive_case P4 repo-owned-checker "$UNPLANNED" deny repo-checker

# ------------------------------------------------------------------ summary --
neg_total=0; full_bypass=0; exec_only=0; not_repro=0; absent_open=0
pos_total=0; ctrl_ok=0; ctrl_broken=0
while read -r line; do
  case "$line" in
    *class=negative*) neg_total=$((neg_total + 1)) ;;
    *class=positive*) pos_total=$((pos_total + 1)) ;;
  esac
  case "$line" in
    *verdict=FULL_BYPASS*)    full_bypass=$((full_bypass + 1)) ;;
    *verdict=EXECUTION_ONLY*) exec_only=$((exec_only + 1)) ;;
    *verdict=NOT_REPRODUCED*) not_repro=$((not_repro + 1)) ;;
    *verdict=FAIL_OPEN_NO_REPO_PROGRAM*) absent_open=$((absent_open + 1)) ;;
    *verdict=CONTROL_OK*)     ctrl_ok=$((ctrl_ok + 1)) ;;
    *verdict=CONTROL_BROKEN*) ctrl_broken=$((ctrl_broken + 1)) ;;
  esac
done <"$RESULTS"

if [ "$ctrl_broken" -gt 0 ] || [ "$PROBE_INVALID" -eq 1 ]; then
  probe_result=PROBE_INVALID
elif [ "$full_bypass" -gt 0 ] || [ "$exec_only" -gt 0 ] || [ "$absent_open" -gt 0 ]; then
  probe_result=WEAKNESS_CONFIRMED
else
  probe_result=WEAKNESS_NOT_REPRODUCED
fi

printf '\n=== PROBE SUMMARY (machine-readable) ===\n'
printf 'PROBE=bootstrap-trust-boundary\n'
printf 'BASELINE=%s\n' "$BASELINE"
cat "$RESULTS"
printf 'NEGATIVE_TOTAL=%s FULL_BYPASS=%s EXECUTION_ONLY=%s FAIL_OPEN_NO_REPO_PROGRAM=%s NOT_REPRODUCED=%s\n' \
  "$neg_total" "$full_bypass" "$exec_only" "$absent_open" "$not_repro"
printf 'POSITIVE_TOTAL=%s CONTROL_OK=%s CONTROL_BROKEN=%s\n' \
  "$pos_total" "$ctrl_ok" "$ctrl_broken"
printf 'PROBE_RESULT=%s\n' "$probe_result"
printf 'MEANING=a confirmed weakness is NOT a fix; this probe changes no product behaviour\n'
printf '=== END PROBE SUMMARY ===\n'

[ "$probe_result" = "PROBE_INVALID" ] && exit 2
exit 0
