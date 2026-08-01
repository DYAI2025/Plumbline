#!/usr/bin/env bash
#
# Shared Python runtime contract for the PRIL command wrappers.
#
# Resolution is authoritative and deterministic:
#   1. PLUMBLINE_PYTHON (one executable name or path)
#   2. uv run --no-project --no-config python3
#   3. python3
#
# Exit codes 120/121 are reserved for runtime failures so callers can
# distinguish a checker that could not run from a checker that ran and rejected
# policy. Checker-specific policy exits are supplied by each wrapper.

PLUMBLINE_EXIT_TOOL_UNAVAILABLE=120
PLUMBLINE_EXIT_TOOL_BROKEN=121
# NEW-1: a usage/argument error is a TOOL fault, not a policy result. argparse's
# default exit 2 collided with the contract's MISSING, so a mis-invoked checker
# read as "nothing to check". 122 keeps it in the reserved tool family.
PLUMBLINE_EXIT_TOOL_INVOCATION=122

plumbline_runtime_emit() {
  local code="$1"
  local error_class="$2"
  local cli="$3"
  local interpreter="$4"
  local exit_code="$5"
  local always="${6:-0}"

  if [ "$always" = "1" ] || [ "${PLUMBLINE_RUNTIME_DIAGNOSTICS:-0}" = "1" ]; then
    printf 'PRIL_RUNTIME code=%s error_class=%s cli=%s interpreter=%s exit_code=%s\n' \
      "$code" "$error_class" "$cli" "$interpreter" "$exit_code" >&2
  fi
}

plumbline_resolve_python() {
  local candidate=""

  PLUMBLINE_PYTHON_MODE=""
  PLUMBLINE_PYTHON_EXECUTABLE=""
  PLUMBLINE_PYTHON_INTERPRETER=""
  PLUMBLINE_PYTHON_EXPLICIT=0

  if [ -n "${PLUMBLINE_PYTHON:-}" ]; then
    candidate="$(command -v "$PLUMBLINE_PYTHON" 2>/dev/null)" || candidate=""
    if [ -z "$candidate" ] || [ ! -f "$candidate" ] || [ ! -x "$candidate" ]; then
      PLUMBLINE_PYTHON_INTERPRETER="PLUMBLINE_PYTHON"
      return "$PLUMBLINE_EXIT_TOOL_UNAVAILABLE"
    fi
    PLUMBLINE_PYTHON_MODE="direct"
    PLUMBLINE_PYTHON_EXECUTABLE="$candidate"
    PLUMBLINE_PYTHON_INTERPRETER="PLUMBLINE_PYTHON"
    PLUMBLINE_PYTHON_EXPLICIT=1
    return 0
  fi

  candidate="$(command -v uv 2>/dev/null)" || candidate=""
  if [ -n "$candidate" ] && [ -f "$candidate" ] && [ -x "$candidate" ]; then
    PLUMBLINE_PYTHON_MODE="uv"
    PLUMBLINE_PYTHON_EXECUTABLE="$candidate"
    PLUMBLINE_PYTHON_INTERPRETER="uv-run-python3"
    return 0
  fi

  candidate="$(command -v python3 2>/dev/null)" || candidate=""
  if [ -n "$candidate" ] && [ -f "$candidate" ] && [ -x "$candidate" ]; then
    PLUMBLINE_PYTHON_MODE="direct"
    PLUMBLINE_PYTHON_EXECUTABLE="$candidate"
    PLUMBLINE_PYTHON_INTERPRETER="python3"
    return 0
  fi

  PLUMBLINE_PYTHON_INTERPRETER="none"
  return "$PLUMBLINE_EXIT_TOOL_UNAVAILABLE"
}

plumbline_python_probe() {
  if [ "$PLUMBLINE_PYTHON_MODE" = "uv" ]; then
    "$PLUMBLINE_PYTHON_EXECUTABLE" run --no-project --no-config python3 -c \
      'import sys; raise SystemExit(0 if sys.version_info.major == 3 else 1)' \
      >/dev/null 2>&1
    return $?
  fi

  "$PLUMBLINE_PYTHON_EXECUTABLE" -c \
    'import sys; raise SystemExit(0 if sys.version_info.major == 3 else 1)' \
    >/dev/null 2>&1
}

plumbline_python_run() {
  local script="$1"
  local runtime_dir=""
  local started_file=""
  local checker_rc=0
  local bootstrap='import os,sys; marker=os.environ.pop("PLUMBLINE_RUNTIME_STARTED_FILE"); open(marker,"x").close(); os.execv(sys.executable,[sys.executable]+sys.argv[1:])'
  shift

  PLUMBLINE_PYTHON_STARTED=0
  runtime_dir="$(mktemp -d "${TMPDIR:-/tmp}/plumbline-python.XXXXXX" 2>/dev/null)" \
    || return "$PLUMBLINE_EXIT_TOOL_BROKEN"
  if [ -z "$runtime_dir" ] || [ ! -d "$runtime_dir" ]; then
    return "$PLUMBLINE_EXIT_TOOL_BROKEN"
  fi
  started_file="$runtime_dir/started"

  if [ "$PLUMBLINE_PYTHON_MODE" = "uv" ]; then
    if PLUMBLINE_RUNTIME_STARTED_FILE="$started_file" \
      "$PLUMBLINE_PYTHON_EXECUTABLE" run --no-project --no-config python3 -c "$bootstrap" \
      "$script" "$@"
    then
      checker_rc=0
    else
      checker_rc=$?
    fi
  elif PLUMBLINE_RUNTIME_STARTED_FILE="$started_file" \
    "$PLUMBLINE_PYTHON_EXECUTABLE" -c "$bootstrap" "$script" "$@"
  then
    checker_rc=0
  else
    checker_rc=$?
  fi

  [ -f "$started_file" ] && PLUMBLINE_PYTHON_STARTED=1
  rm -f "$started_file" 2>/dev/null || true
  rmdir "$runtime_dir" 2>/dev/null || true
  return "$checker_rc"
}

plumbline_python_main() {
  local cli="$1"
  local script="$2"
  local policy_exit_codes="$3"
  local resolution_rc=0
  local checker_rc=0
  local expected=""
  local fallback=""
  shift 3

  if plumbline_resolve_python; then
    :
  else
    resolution_rc=$?
    plumbline_runtime_emit \
      "PRIL_TOOL_UNAVAILABLE" "tool_unavailable" "$cli" \
      "${PLUMBLINE_PYTHON_INTERPRETER:-none}" "$resolution_rc" 1
    return "$PLUMBLINE_EXIT_TOOL_UNAVAILABLE"
  fi

  if [ ! -f "$script" ] || [ ! -r "$script" ]; then
    plumbline_runtime_emit \
      "PRIL_TOOL_BROKEN" "tool_broken" "$cli" \
      "$PLUMBLINE_PYTHON_INTERPRETER" "$PLUMBLINE_EXIT_TOOL_BROKEN" 1
    return "$PLUMBLINE_EXIT_TOOL_BROKEN"
  fi

  if ! plumbline_python_probe; then
    # PLUMBLINE_PYTHON is an explicit operator choice and therefore
    # authoritative. An auto-discovered uv, however, is only a candidate: if
    # its Python probe fails, continue to the documented python3 fallback.
    if [ "$PLUMBLINE_PYTHON_EXPLICIT" -eq 0 ] && \
       [ "$PLUMBLINE_PYTHON_MODE" = "uv" ]; then
      fallback="$(command -v python3 2>/dev/null)" || fallback=""
      if [ -n "$fallback" ] && [ -f "$fallback" ] && [ -x "$fallback" ]; then
        PLUMBLINE_PYTHON_MODE="direct"
        PLUMBLINE_PYTHON_EXECUTABLE="$fallback"
        PLUMBLINE_PYTHON_INTERPRETER="python3"
        if plumbline_python_probe; then
          :
        else
          plumbline_runtime_emit \
            "PRIL_TOOL_BROKEN" "tool_broken" "$cli" \
            "$PLUMBLINE_PYTHON_INTERPRETER" "$PLUMBLINE_EXIT_TOOL_BROKEN" 1
          return "$PLUMBLINE_EXIT_TOOL_BROKEN"
        fi
      else
        plumbline_runtime_emit \
          "PRIL_TOOL_BROKEN" "tool_broken" "$cli" \
          "uv-run-python3" "$PLUMBLINE_EXIT_TOOL_BROKEN" 1
        return "$PLUMBLINE_EXIT_TOOL_BROKEN"
      fi
    else
      plumbline_runtime_emit \
        "PRIL_TOOL_BROKEN" "tool_broken" "$cli" \
        "$PLUMBLINE_PYTHON_INTERPRETER" "$PLUMBLINE_EXIT_TOOL_BROKEN" 1
      return "$PLUMBLINE_EXIT_TOOL_BROKEN"
    fi
  fi

  if plumbline_python_run "$script" "$@"; then
    checker_rc=0
  else
    checker_rc=$?
  fi

  # A policy exit is credible only after the selected Python process crossed
  # the bootstrap boundary and started the real checker. uv/launcher failures
  # can reuse the same small integers as checker policy exits; without this
  # marker, numeric coincidence would recreate the original misdiagnosis.
  if [ "${PLUMBLINE_PYTHON_STARTED:-0}" -ne 1 ]; then
    plumbline_runtime_emit \
      "PRIL_TOOL_BROKEN" "tool_broken" "$cli" \
      "$PLUMBLINE_PYTHON_INTERPRETER" "$PLUMBLINE_EXIT_TOOL_BROKEN" 1
    return "$PLUMBLINE_EXIT_TOOL_BROKEN"
  fi

  if [ "$checker_rc" -eq 0 ]; then
    plumbline_runtime_emit \
      "PRIL_OK" "none" "$cli" "$PLUMBLINE_PYTHON_INTERPRETER" 0 0
    return 0
  fi

  # A tool-invocation error is reported before the policy table is consulted, so
  # it can never be mistaken for one of the checker's own policy codes.
  if [ "$checker_rc" -eq "$PLUMBLINE_EXIT_TOOL_INVOCATION" ]; then
    plumbline_runtime_emit \
      "PRIL_TOOL_INVOCATION_ERROR" "tool_invocation_error" "$cli" \
      "$PLUMBLINE_PYTHON_INTERPRETER" "$checker_rc" 1
    return "$PLUMBLINE_EXIT_TOOL_INVOCATION"
  fi

  for expected in $policy_exit_codes; do
    if [ "$checker_rc" -eq "$expected" ]; then
      plumbline_runtime_emit \
        "PRIL_POLICY_VIOLATION" "policy_violation" "$cli" \
        "$PLUMBLINE_PYTHON_INTERPRETER" "$checker_rc" 1
      return "$checker_rc"
    fi
  done

  plumbline_runtime_emit \
    "PRIL_TOOL_BROKEN" "tool_broken" "$cli" \
    "$PLUMBLINE_PYTHON_INTERPRETER" "$PLUMBLINE_EXIT_TOOL_BROKEN" 1
  return "$PLUMBLINE_EXIT_TOOL_BROKEN"
}
