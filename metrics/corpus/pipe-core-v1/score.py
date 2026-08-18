#!/usr/bin/env python3
"""Aggregate pipe-core-v1 results into the report metrics.

Input: a results JSON (hand-assembled from the runs), shape:
{
  "arm": {
    "gap":   [{"task":"T08","run":1,"oracle":"CAUGHT|ESCAPED","built":true,"verdict":"BLOCK|SHIP"}, ...],
    "control":[{"task":"CTRL","run":1,"result":"CLEAN|FALSE_POSITIVE","built":true}, ...],
    "rdiff": [{"diff":"A","run":1,"defects_caught":2,"verdict":"BLOCK|SHIP"}, ...]
  }, ...
}
Usage: score.py results.json
"""
import json, sys


def pct(n, d):
    return f"{(100.0*n/d):.1f}%" if d else "n/a"


def main(path):
    data = json.load(open(path))
    for arm, d in data.items():
        gap = d.get("gap", [])
        ctrl = d.get("control", [])
        rd = d.get("rdiff", [])
        escaped = sum(1 for g in gap if g["oracle"] == "ESCAPED")
        fp = sum(1 for c in ctrl if c["result"] == "FALSE_POSITIVE")
        rec_caught = sum(r["defects_caught"] for r in rd)
        rec_total = 3 * len(rd)
        builds = sum(1 for g in gap if g.get("built")) + sum(1 for c in ctrl if c.get("built"))
        build_total = len(gap) + len(ctrl)
        print(f"=== {arm} ===")
        print(f"  escaped_defect_rate   = {escaped}/{len(gap)} = {pct(escaped,len(gap))}  (lower better)")
        print(f"  pipeline_FP_rate      = {fp}/{len(ctrl)} = {pct(fp,len(ctrl))}  (lower better)")
        print(f"  reviewer_recall       = {rec_caught}/{rec_total} = {pct(rec_caught,rec_total)}  (higher better)")
        print(f"  build_success         = {builds}/{build_total} = {pct(builds,build_total)}")
    print("\nReport all three families together (anti-Goodhart). A '0 escaped' with missing")
    print("control/rdiff data is NOT a pass.")


if __name__ == "__main__":
    main(sys.argv[1] if len(sys.argv) > 1 else "results.json")
