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
                  * every recorded gate latest-CLEARED but no explicit
                    __RUN_COMPLETE__ marker -> START sentinel (the ledger has no
                    authoritative full gate list, so all-observed-cleared is not
                    proof that later gates ran)
                  * explicit __RUN_COMPLETE__ marker latest-CLEARED -> COMPLETE
                    sentinel
  revalidate  exit 0 iff gate G's LATEST row is CLEARED AND its recorded
                artifact_hash == --current-hash; otherwise non-zero (the human gate
                must be re-asked because its artifact changed, or it was never
                cleared). Fail-closed: an unknown gate is non-zero.

Design invariants
-----------------
  * `at` is caller-supplied; there is no wall-clock call anywhere in this module.
  * resume-point fails CLOSED: any doubt about the ledger resolves to "start from
    the beginning", never to "everything is done". A laundered "complete" on a
    corrupt or partial ledger would skip gates — the exact failure this framework
    exists to prevent.
  * The ledger stores observed events, not an authoritative /agileteam gate list,
    so "all observed gates are CLEARED" is NOT completion. Completion requires an
    explicit __RUN_COMPLETE__ marker recorded after the final gate clears.
  * Pure standard library. No third-party dependencies.

Usage
-----
  plumbline_run_ledger.py record --repo R --feature F --gate G \\
      --status CLEARED|PENDING|PAUSED --artifact-hash H --at 2026-06-02T10:00:00Z
  plumbline_run_ledger.py resume-point --repo R --feature F
  plumbline_run_ledger.py revalidate --repo R --feature F --gate G --current-hash H
  plumbline_run_ledger.py constants --format shell|json
"""
import argparse
import json
import os
import sys

STATUSES = ("CLEARED", "PENDING", "PAUSED")

# Fail-closed sentinels. Tests and shell callers can read these from the
# `constants --format shell` subcommand instead of duplicating literal values.
# START_SENTINEL means "resume from the very beginning (Phase 0)"; it is the answer
# whenever the ledger cannot be trusted or is only partial. COMPLETE_SENTINEL means
# the caller explicitly recorded RUN_COMPLETE_GATE as CLEARED after the final gate.
# The sentinel values are not real gate names, so they can never collide with one.
START_SENTINEL = "__START__"
COMPLETE_SENTINEL = "__COMPLETE__"

# Synthetic terminal marker. Because the ledger only stores observed events and has
# no authoritative full /agileteam gate list, resume-point must not infer completion
# from "every recorded gate is CLEARED"; a crash between gates would otherwise skip
# gates that were never recorded. Record this marker only after the final gate clears.
RUN_COMPLETE_GATE = "__RUN_COMPLETE__"


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
    """Map gate -> its LATEST recorded row.

    The ledger is append-only and chronological, so the last row for a gate is its
    current state. Ordering is a resume-point concern and is derived directly from
    the rows there instead of being returned by this helper."""
    latest = {}
    for row in rows:
        gate = row.get("gate")
        if gate is None:
            continue
        latest[gate] = row
    return latest


def iter_first_seen_gates(rows):
    """Yield gates in the order they first appear in the ledger."""
    seen = set()
    for row in rows:
        gate = row.get("gate")
        if gate is None or gate in seen:
            continue
        seen.add(gate)
        yield gate


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
    latest = latest_status_by_gate(rows)
    for gate in iter_first_seen_gates(rows):
        if gate == RUN_COMPLETE_GATE:
            continue
        if latest[gate].get("status") != "CLEARED":
            print(gate)
            return 0

    # Only treat the run as complete if the completion marker is the last recorded row,
    # matching the invariant that it is recorded after the final gate clears.
    last_row = rows[-1]
    if last_row.get("gate") == RUN_COMPLETE_GATE and last_row.get("status") == "CLEARED":
        print(COMPLETE_SENTINEL)
        return 0

    # Fail closed: the ledger has no authoritative list of gates, so a ledger whose
    # observed gates are all latest-CLEARED may simply be partial (for example, a
    # crash after one gate cleared but before the next gate's PENDING row was
    # recorded). Do not let resume skip unobserved later gates.
    print(START_SENTINEL)
    return 0


def cmd_constants(args):
    constants = {
        "START_SENTINEL": START_SENTINEL,
        "COMPLETE_SENTINEL": COMPLETE_SENTINEL,
        "RUN_COMPLETE_GATE": RUN_COMPLETE_GATE,
    }
    if args.format == "json":
        print(json.dumps(constants, sort_keys=True))
        return 0
    for name, value in constants.items():
        print(f"{name}={json.dumps(value)}")
    return 0


def cmd_revalidate(args):
    rows, ok = read_rows(ledger_path(args.repo, args.feature))
    if not ok:
        print(f"STALE: ledger untrusted for gate {args.gate}", file=sys.stderr)
        return 1
    latest = latest_status_by_gate(rows)
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

    pc = sub.add_parser("constants",
                        help="emit run-ledger constants for shell/json consumers")
    pc.add_argument("--format", choices=("shell", "json"), default="shell")
    pc.set_defaults(func=cmd_constants)

    return p.parse_args(argv)


def main(argv=None):
    args = parse_args(argv if argv is not None else sys.argv[1:])
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
