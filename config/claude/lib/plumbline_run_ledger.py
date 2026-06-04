#!/usr/bin/env python3
"""
plumbline_run_ledger.py — an executable, resumable, per-feature run-ledger.

A /agileteam run is a sequence of gates (Phase 0 → ... → release). When a run is
interrupted (Watcher pause, a human gate, a crash) and later re-invoked for the
same feature, the orchestrator must resume at the FIRST gate that is not yet
cleared — and must NOT trust a human gate whose underlying artifact has changed
since it was cleared. This ledger makes that resumable state a real, replayable
artifact instead of something held in a context window.

Storage
-------
A per-feature, append-only JSONL file at:

    <repo>/docs/context/<feature>.run-ledger.jsonl

one row per gate event:

    {repo, feature, gate, status, artifact_hash, at}

  status        CLEARED | PENDING | PAUSED
  artifact_hash hash of the artifact the gate was decided against (for human-gate
                re-validation: a changed artifact invalidates a prior CLEAR)
  at            ISO-8601 instant of the event, supplied as an ARGUMENT — never read
                from the wall clock, so the ledger is deterministic and replayable.

Subcommands
-----------
  record      append one gate event (fail-closed on a bad --status)
  resume-point  print the first mandatory canonical gate whose LATEST row is
                missing or not CLEARED. Fail-closed sentinels:
                  * ledger missing / empty / corrupt -> START sentinel (begin at
                    Phase 0; NEVER "all cleared")
                  * every expected gate latest-CLEARED -> COMPLETE sentinel
  revalidate  exit 0 iff gate G's LATEST row is CLEARED AND its recorded
                artifact_hash == --current-hash; otherwise non-zero (the human gate
                must be re-asked because its artifact changed, or it was never
                cleared). Fail-closed: an unknown gate is non-zero.

Design invariants
-----------------
  * `at` is caller-supplied; there is no wall-clock call anywhere in this module.
  * resume-point fails CLOSED: any doubt about the ledger resolves to "start from
    the beginning", never to "everything is done". A laundered "complete" on a
    corrupt ledger would skip every gate — the exact failure this framework exists
    to prevent.
  * Pure standard library. No third-party dependencies.

Usage
-----
  plumbline_run_ledger.py record --repo R --feature F --gate G \\
      --status CLEARED|PENDING|PAUSED --artifact-hash H --at 2026-06-02T10:00:00Z
  plumbline_run_ledger.py resume-point --repo R --feature F
  plumbline_run_ledger.py revalidate --repo R --feature F --gate G --current-hash H
"""
import argparse
import json
import os
import sys

STATUSES = ("CLEARED", "PENDING", "PAUSED")

# Canonical mandatory CORE gate IDs used across Plumbline tooling (see
# config/claude/metrics/emit_run.py for canonical gate outcome keys; these map to the
# Phase/Gate names documented in config/claude/commands/agileteam.md).
# Optional/full-mode gates (Gate B security, Gate D judgment, mutation, etc.) may be
# recorded and revalidated, but they are not required for the CORE completion sentinel.
# only early CLEARED rows could incorrectly look complete.
CANONICAL_GATES = (
    "phase0",
    "phase0_5_spec_sanity",
    "phase1_tdd_qa",
    "phase2_implementation",
    "gateA_verification",
    "gateC_validation",
    "user_acceptance",
)

# Fail-closed sentinels (kept in sync with config/claude/tests/test_run_ledger.sh).
# START_SENTINEL means "resume from the very beginning (Phase 0)"; it is the answer
# whenever the ledger cannot be trusted. COMPLETE_SENTINEL means every expected gate
# is latest-CLEARED. Neither is a real gate name, so they can never collide with one.
START_SENTINEL = "__START__"
COMPLETE_SENTINEL = "__COMPLETE__"


def ledger_path(repo, feature):
    return os.path.join(repo, "docs", "context", f"{feature}.run-ledger.jsonl")


def read_rows(path):
    """Return (rows, ok). ok is False if the file is missing, empty, or any line
    fails to parse as a JSON object — i.e. the ledger cannot be trusted and the
    caller must fail closed. We deliberately do NOT silently skip bad lines: a
    partially-corrupt ledger is untrustworthy as a whole."""
    if not os.path.isfile(path):
        return [], False
    rows = []
    try:
        with open(path, encoding="utf-8") as fh:
            for line in fh:
                line = line.strip()
                if not line:
                    continue
                obj = json.loads(line)
                if not isinstance(obj, dict):
                    return [], False
                rows.append(obj)
    except (OSError, ValueError):
        return [], False
    if not rows:
        return [], False
    return rows, True


def latest_status_by_gate(rows):
    """Map gate -> its LATEST recorded row, preserving first-seen gate order.

    The ledger is append-only and chronological, so the last row for a gate is its
    current state. We keep an ordered list of gates as first encountered so
    resume-point returns the first non-cleared gate in *recorded* order."""
    order = []
    latest = {}
    for row in rows:
        gate = row.get("gate")
        if gate is None:
            continue
        if gate not in latest:
            order.append(gate)
        latest[gate] = row
    return order, latest


def cmd_record(args):
    if args.status not in STATUSES:
        # argparse choices already enforces this; belt-and-suspenders, fail closed.
        print(f"ERROR: invalid --status {args.status!r}", file=sys.stderr)
        return 2
    record = {
        "repo": args.repo,
        "feature": args.feature,
        "gate": args.gate,
        "status": args.status,
        "artifact_hash": args.artifact_hash,
        "at": args.at,
    }
    path = ledger_path(args.repo, args.feature)
    out_dir = os.path.dirname(path)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    line = json.dumps(record, ensure_ascii=False)
    with open(path, "a", encoding="utf-8") as fh:
        fh.write(line + "\n")
    print(f"recorded {args.gate}={args.status} -> {path}")
    return 0


def cmd_resume_point(args):
    rows, ok = read_rows(ledger_path(args.repo, args.feature))
    if not ok:
        # Fail closed: missing / empty / corrupt -> start from the beginning.
        print(START_SENTINEL)
        return 0
    _, latest = latest_status_by_gate(rows)
    for gate in CANONICAL_GATES:
        row = latest.get(gate)
        if row is None or row.get("status") != "CLEARED":
            print(gate)
            return 0
    # Every expected gate is latest-CLEARED; extra recorded optional gates do not
    # make a partial mandatory ledger complete, and do not block CORE completion.
    print(COMPLETE_SENTINEL)
    return 0


def cmd_revalidate(args):
    rows, ok = read_rows(ledger_path(args.repo, args.feature))
    if not ok:
        print(f"STALE: ledger untrusted for gate {args.gate}", file=sys.stderr)
        return 1
    _, latest = latest_status_by_gate(rows)
    row = latest.get(args.gate)
    if row is None:
        print(f"STALE: gate {args.gate} not in ledger", file=sys.stderr)
        return 1
    if row.get("status") != "CLEARED":
        print(f"STALE: gate {args.gate} latest status is {row.get('status')!r}",
              file=sys.stderr)
        return 1
    if row.get("artifact_hash") != args.current_hash:
        print(f"STALE: gate {args.gate} artifact changed "
              f"(was {row.get('artifact_hash')!r}, now {args.current_hash!r}) — re-ask",
              file=sys.stderr)
        return 1
    print(f"VALID: gate {args.gate} cleared and artifact unchanged")
    return 0


def parse_args(argv):
    p = argparse.ArgumentParser(description="Executable resumable per-feature run-ledger.")
    sub = p.add_subparsers(dest="command", required=True)

    pr = sub.add_parser("record", help="append one gate event")
    pr.add_argument("--repo", required=True)
    pr.add_argument("--feature", required=True)
    pr.add_argument("--gate", required=True)
    pr.add_argument("--status", required=True, choices=STATUSES)
    pr.add_argument("--artifact-hash", required=True, dest="artifact_hash")
    pr.add_argument("--at", required=True,
                    help="ISO-8601 instant of the event (caller-supplied, NOT wall-clock)")
    pr.set_defaults(func=cmd_record)

    prp = sub.add_parser("resume-point",
                         help="print the first non-CLEARED gate (fail-closed sentinels otherwise)")
    prp.add_argument("--repo", required=True)
    prp.add_argument("--feature", required=True)
    prp.set_defaults(func=cmd_resume_point)

    prv = sub.add_parser("revalidate",
                         help="exit 0 iff gate is latest-CLEARED and artifact unchanged")
    prv.add_argument("--repo", required=True)
    prv.add_argument("--feature", required=True)
    prv.add_argument("--gate", required=True)
    prv.add_argument("--current-hash", required=True, dest="current_hash")
    prv.set_defaults(func=cmd_revalidate)

    return p.parse_args(argv)


def main(argv=None):
    args = parse_args(argv if argv is not None else sys.argv[1:])
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
