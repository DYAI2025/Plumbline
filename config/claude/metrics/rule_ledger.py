#!/usr/bin/env python3
"""
rule_ledger.py — append ONE provenance record per APPROVED Kaizen rule.

The rule ledger (metrics/rule-ledger.jsonl) is the audit spine for the agent
learning loop: each line records a rule the human approved (the y/n gate in
config/claude/skills/agent-learning-loop.json), with enough provenance for
process_health.py / canary_gate.py to later attribute a metric movement to a
specific rule.

Design invariants (mirror the human-gate contract):
  * approved_at is supplied as an ARGUMENT, never read from the wall clock. The
    approval timestamp belongs to the moment the human said "y" — scripts must not
    invent it from a clock call. This keeps the ledger replayable and free of
    nondeterministic emit-time skew.
  * a write happens ONLY on an explicit, complete CLI invocation. A missing
    required field fails closed (non-zero, nothing written) — there is no silent
    default-and-write path, exactly as the y/n gate has no silent "yes".

Record fields (all required):
  rule_id        stable id of the approved rule
  approved_at    ISO-8601 instant the human approved it (caller-supplied)
  level          A | B | C  (local CLAUDE.md / global agent prompt / new skill)
  target_file    the file the rule was written into
  named_metric   the metric this rule is expected to move
  direction      higher_is_better | lower_is_better

Pure standard library. No third-party dependencies.

Usage
-----
  rule_ledger.py --rule-id R-2026-001 --approved-at 2026-06-02T10:00:00Z \\
      --level A --target-file CLAUDE.md \\
      --named-metric escaped_defect_rate --direction lower_is_better \\
      [--out PATH]
"""
import argparse
import json
import os
import sys

LEVELS = ("A", "B", "C")
DIRECTIONS = ("higher_is_better", "lower_is_better")


def find_repo_root(start):
    cur = os.path.abspath(start)
    while True:
        if os.path.isdir(os.path.join(cur, ".git")):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            return os.path.abspath(start)  # fall back to start
        cur = parent


def parse_args(argv):
    p = argparse.ArgumentParser(description="Append one approved-rule provenance record.")
    p.add_argument("--rule-id", required=True)
    p.add_argument("--approved-at", required=True,
                   help="ISO-8601 instant the human approved (caller-supplied, NOT wall-clock)")
    p.add_argument("--level", required=True, choices=LEVELS,
                   help="A=local CLAUDE.md, B=global agent prompt, C=new skill")
    p.add_argument("--target-file", required=True,
                   help="the file the rule was persisted into")
    p.add_argument("--named-metric", required=True,
                   help="the metric this rule is expected to move")
    p.add_argument("--direction", required=True, choices=DIRECTIONS)
    p.add_argument("--repo", default=None)
    p.add_argument("--out", default=None,
                   help="output jsonl (default: <repo>/metrics/rule-ledger.jsonl)")
    return p.parse_args(argv)


def main(argv=None):
    args = parse_args(argv if argv is not None else sys.argv[1:])

    record = {
        "rule_id": args.rule_id,
        "approved_at": args.approved_at,
        "level": args.level,
        "target_file": args.target_file,
        "named_metric": args.named_metric,
        "direction": args.direction,
    }

    repo = args.repo or find_repo_root(".")
    out = args.out or os.path.join(repo, "metrics", "rule-ledger.jsonl")

    out_dir = os.path.dirname(out)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    line = json.dumps(record, ensure_ascii=False)
    with open(out, "a", encoding="utf-8") as fh:
        fh.write(line + "\n")
    print(f"appended rule {record['rule_id']} -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
