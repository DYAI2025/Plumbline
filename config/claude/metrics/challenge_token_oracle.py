#!/usr/bin/env python3
"""challenge_token_oracle.py — deterministic scorer for the challenge-gate token oracle.

Reads a run-data JSON (per-role token counts + output text from a real
concilium --mode=challenge slice) and computes two v1 verdicts:

  O1  total tokens <= bound              (the decisive one — is "<=15k" real?)
  O3  the three role outputs are DISTINCT (friction, not consensus theater)

O2 ("<=1-page summary") is intentionally NOT scored in v1: the one-pager is the
gate's *distilled* output, not the sum of the three raw role contributions, so
scoring it faithfully requires capturing the orchestrator's distillation step.
Deferred to keep the pilot lean and the measurement valid (no wrong-thing proxy).

No model calls; pure scoring. Exit codes:
  0  all verdicts pass
  1  scored, but one or more verdicts FAIL (a valid, publishable negative result)
  2  MISSING/malformed — a per-role token figure or text is absent; NOT a pass.

Usage:
  challenge_token_oracle.py score <run-data.json> [--bound 15000] [--similarity-cap 0.6]
"""
from __future__ import annotations
import argparse
import json
import re
import sys

ROLES = ("challenger", "advisor", "critic")


def _words(text):
    return [w for w in re.findall(r"[A-Za-z0-9']+", (text or "").lower()) if w]


def _jaccard(a, b):
    sa, sb = set(a), set(b)
    if not sa and not sb:
        return 1.0
    return len(sa & sb) / len(sa | sb)


def score(data, bound, sim_cap):
    """Return (verdict_dict, exit_code). Fail closed to MISSING (2) on any gap."""
    roles = data.get("roles") or {}
    # MISSING: any role absent, or token figure not a number, or text empty.
    for r in ROLES:
        rd = roles.get(r)
        if not isinstance(rd, dict):
            return {"status": "MISSING", "reason": f"role '{r}' absent"}, 2
        if not isinstance(rd.get("tokens"), (int, float)):
            return {"status": "MISSING", "reason": f"role '{r}' token figure absent/non-numeric"}, 2
        if not (rd.get("text") or "").strip():
            return {"status": "MISSING", "reason": f"role '{r}' output text empty"}, 2

    total_tokens = sum(roles[r]["tokens"] for r in ROLES)
    role_words = {r: _words(roles[r]["text"]) for r in ROLES}
    pairs = (("challenger", "advisor"), ("challenger", "critic"), ("advisor", "critic"))
    max_sim = max(_jaccard(role_words[a], role_words[b]) for a, b in pairs)

    o1 = total_tokens <= bound
    o3 = max_sim <= sim_cap
    verdict = {
        "status": "SCORED",
        "model": data.get("model"),
        "bound": bound,
        "total_tokens": total_tokens,
        "O1_token_bound_hold": o1,
        "max_pairwise_similarity": round(max_sim, 4),
        "similarity_cap": sim_cap,
        "O3_roles_distinct": o3,
        "pass": bool(o1 and o3),
    }
    return verdict, (0 if verdict["pass"] else 1)


def main(argv):
    p = argparse.ArgumentParser(prog="challenge_token_oracle.py")
    sub = p.add_subparsers(dest="cmd", required=True)
    s = sub.add_parser("score")
    s.add_argument("run_data")
    s.add_argument("--bound", type=int, default=15000)
    s.add_argument("--similarity-cap", type=float, default=0.6)
    args = p.parse_args(argv[1:])
    try:
        with open(args.run_data, encoding="utf-8") as fh:
            data = json.load(fh)
    except (OSError, ValueError) as e:
        print(json.dumps({"status": "MISSING", "reason": f"cannot read run-data: {e}"}))
        return 2
    verdict, code = score(data, args.bound, args.similarity_cap)
    print(json.dumps(verdict, indent=2, sort_keys=True))
    return code


if __name__ == "__main__":
    sys.exit(main(sys.argv))
