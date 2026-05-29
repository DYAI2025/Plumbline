#!/usr/bin/env python3
"""
emit_run.py — append ONE run record to metrics/runs.jsonl for /agileteam.

The run record is the spine of the meta-meta layer (see docs/agileteam-governance.md
§2). It carries the metrics AND a config_fingerprint — a per-component content hash of
the command, the agents, and the konfabulations-audit skill — so that later analysis
(process_health.py) can attribute a drift to a specific gate/agent/skill.

Pure standard library. No third-party dependencies.

Usage
-----
  emit_run.py --metrics-file run-metrics.json [options]
  emit_run.py --metrics '{"first_pass":0.72,"mutation":0.81}' [options]

Options
-------
  --metrics JSON          inline metrics object
  --metrics-file PATH     metrics object as a JSON file (overrides --metrics)
  --corpus-id ID          fixed task-corpus id (default: "adhoc")
  --mode core|full        operating mode the run used (default: "core")
  --gate-outcomes JSON    e.g. '{"A":"pass","B":"skip","C":"pass","D":"skip"}'
  --human-overrides N     count of human overrides at gates (default: 0)
  --baseline              tag this run as part of the baseline window
  --repo PATH             repo root to fingerprint (default: auto-detect)
  --out PATH              output jsonl (default: <repo>/metrics/runs.jsonl)
  --dry-run               print the record, do not append
"""
import argparse
import datetime as dt
import hashlib
import json
import os
import subprocess
import sys
import uuid

# Logical component -> path relative to repo root. Keep in sync with the workflow.
COMPONENTS = {
    "command.agileteam":      "config/claude/commands/agileteam.md",
    "command.agileteam_bench":"config/claude/commands/agileteam-bench.md",
    "skill.konfab_audit":     "config/claude/skills/konfabulations-audit/SKILL.md",
    "hook.stop_learning":     "config/claude/hooks/stop-learning-loop.sh",
    "agent.requirements_analyst": "agileteam/requirements-analyst.md",
    "agent.spec_auditor":         "agileteam/spec-auditor.md",
    "agent.product_owner":        "agileteam/product-owner.md",
    "agent.security_reviewer":    "agileteam/security-reviewer.md",
    "agent.retro_analyst":        "agileteam/retro-analyst.md",
    "agent.context_keeper":       "agileteam/context-keeper.md",
    "agent.coder":            "core/coder.md",
    "agent.planner":          "core/planner.md",
    "agent.tester":           "core/tester.md",
    "agent.code_reviewer":    "code-reviewer.md",
    "agent.production_validator": "testing/validation/production-validator.md",
}


def sha256_file(path):
    try:
        with open(path, "rb") as fh:
            return "sha256:" + hashlib.sha256(fh.read()).hexdigest()[:16]
    except FileNotFoundError:
        return "missing"


def find_repo_root(start):
    cur = os.path.abspath(start)
    while True:
        if os.path.isdir(os.path.join(cur, ".git")):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            return os.path.abspath(start)  # fall back to start
        cur = parent


def git(repo, *args):
    try:
        out = subprocess.run(["git", "-C", repo, *args],
                             capture_output=True, text=True, timeout=10)
        return out.stdout.strip() if out.returncode == 0 else ""
    except Exception:
        return ""


def fingerprint(repo):
    return {name: sha256_file(os.path.join(repo, rel))
            for name, rel in COMPONENTS.items()}


def load_metrics(args):
    if args.metrics_file:
        with open(args.metrics_file, encoding="utf-8") as fh:
            return json.load(fh)
    if args.metrics:
        return json.loads(args.metrics)
    return {}


def parse_args(argv):
    p = argparse.ArgumentParser(description="Append one /agileteam run record.")
    p.add_argument("--metrics")
    p.add_argument("--metrics-file")
    p.add_argument("--corpus-id", default="adhoc")
    p.add_argument("--mode", default="core", choices=["core", "full"])
    p.add_argument("--gate-outcomes", default="{}")
    p.add_argument("--human-overrides", type=int, default=0)
    p.add_argument("--baseline", action="store_true")
    p.add_argument("--repo", default=None)
    p.add_argument("--out", default=None)
    p.add_argument("--dry-run", action="store_true")
    return p.parse_args(argv)


def main(argv=None):
    args = parse_args(argv if argv is not None else sys.argv[1:])
    repo = args.repo or find_repo_root(".")
    out = args.out or os.path.join(repo, "metrics", "runs.jsonl")

    branch = git(repo, "rev-parse", "--abbrev-ref", "HEAD") or "unknown"
    short = git(repo, "rev-parse", "--short", "HEAD") or "nogit"

    record = {
        "run_id": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
                  + "-" + uuid.uuid4().hex[:6],
        "corpus_id": args.corpus_id,
        "mode": args.mode,
        "baseline": bool(args.baseline),
        "process_branch": f"{branch}@{short}",
        "config_fingerprint": fingerprint(repo),
        "metrics": load_metrics(args),
        "gate_outcomes": json.loads(args.gate_outcomes),
        "human_overrides": args.human_overrides,
    }

    line = json.dumps(record, ensure_ascii=False)
    if args.dry_run:
        print(line)
        return 0
    out_dir = os.path.dirname(out)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    with open(out, "a", encoding="utf-8") as fh:
        fh.write(line + "\n")
    print(f"appended run {record['run_id']} -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
