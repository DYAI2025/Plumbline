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

All JSON-bearing arguments (--metrics, --metrics-file, --raw, --gate-outcomes) are
validated fail-closed: invalid JSON or a non-object value is rejected with an ERROR on
stderr and a non-zero exit, never a raw traceback or a silently-written bad record.

Options
-------
  --metrics JSON          inline metrics object (must be a JSON object)
  --metrics-file PATH     metrics object as a JSON file (overrides --metrics)
  --raw JSON              free-form diagnostic counts; recorded under record["raw"],
                          NOT scored/allowlisted (must be a JSON object)
  --tokens-total N        total output tokens for the run; numerator of cost_per_req
                          (must be >= 0). Conflicts with cost_per_req in --metrics.
  --reqs-accepted N       count of VALIDATED REQs (evidence_class >= min-evidence) —
                          the cost_per_req denominator (must be >= 0)
  --corpus-id ID          fixed task-corpus id (default: "adhoc")
  --mode core|full        operating mode the run used (default: "core")
  --gate-outcomes JSON    per-gate outcome map (must be a JSON object). The
                          canonical keys actually emitted by the /agileteam pipeline
                          (use these so process_health analysis does not drift) are:
                            phase0_5_spec_sanity  spec-sanity audit (Phase 0.7, run
                                                  inside Phase 0.5 confirmation)
                            gateA_verification    Gate A — typecheck/lint/unit/
                                                  integration/e2e + coverage
                            gateB_security        Gate B — SAST/deps/secrets/threat
                            gateC_validation      Gate C — production-validator vs the
                                                  acceptance matrix
                            gateD_judgment        Gate D — ultrathink product-owner
                                                  judgment
                          each value is a short outcome token, e.g. "pass"/"skip"/
                          "fail". The keys are documentary: process_health.py does not
                          consume gate_outcomes, so unknown keys are recorded as-is.
                          e.g. '{"gateA_verification":"pass","gateB_security":"skip"}'
  --human-overrides N     count of human overrides at gates (default: 0)
  --active-rules JSON     JSON array of approved-rule ids active during this run;
                          stored verbatim under record["active_rules"] (default []).
                          Lets later analysis segment a metric by the rules in force.
  --baseline              tag this run as part of the baseline window
  --repo PATH             target repo (default: auto-detect). NB: config_fingerprint
                          resolves COMPONENT paths against the Plumbline install (this
                          script's own repo root) FIRST, then --repo, then
                          $CLAUDE_HOME/agents — emitting the first hit, or
                          "missing:<relpath>" on a true miss. So a run inside a target
                          project still fingerprints Plumbline's own components.
  --fail-on-missing-fingerprint
                          exit non-zero (3) if EVERY config_fingerprint component is
                          missing (default off; intended ON for agileteam-bench)
  --out PATH              output jsonl (default: <repo>/metrics/runs.jsonl)
  --dry-run               print the record, do not append

Record fields (selected)
------------------------
  metrics_schema_version  version of the scored-metrics allowlist contract (int)
  raw                     the validated --raw object (diagnostic, never scored)
"""
import argparse
import datetime as dt
import hashlib
import json
import os
import subprocess
import sys
import uuid

# Single source of truth for which metrics are SCORED. Importing DIRECTIONS from
# process_health (same directory) makes the emit-side allowlist incapable of
# drifting from the analyse-side scorer — the exact drift this contract closes.
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from process_health import DIRECTIONS  # noqa: E402

ALLOWED_METRICS = frozenset(DIRECTIONS)
METRICS_SCHEMA_VERSION = 1

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
    with open(path, "rb") as fh:
        return "sha256:" + hashlib.sha256(fh.read()).hexdigest()[:16]


def find_repo_root(start):
    cur = os.path.abspath(start)
    while True:
        if os.path.isdir(os.path.join(cur, ".git")):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            return os.path.abspath(start)  # fall back to start
        cur = parent


def plumbline_install_root():
    """Repo root of the Plumbline install that owns THIS script.

    config_fingerprint resolves COMPONENT paths against the install, NOT against
    --repo: the COMPONENT relpaths (config/claude/commands/agileteam.md, core/coder.md,
    …) describe Plumbline's own tree, which does not exist under a target project. The
    historical all-`missing` fingerprint (amendment M-1) was exactly this: the run was
    emitted inside a target repo. Derive the install root from __file__ — walk up to the
    nearest .git-bearing dir (the install repo), falling back to the structural parent of
    config/claude/metrics/ when there is no .git (e.g. a copied/installed tree).
    """
    here = os.path.abspath(__file__)
    cur = os.path.dirname(here)
    while True:
        if os.path.isdir(os.path.join(cur, ".git")):
            return cur
        parent = os.path.dirname(cur)
        if parent == cur:
            break
        cur = parent
    # No .git above the script (copied/installed): metrics/ -> claude/ -> config/ -> root
    return os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(here))))


def search_path(repo):
    """Ordered roots to resolve each COMPONENT relpath against; first hit wins.

    (1) the Plumbline install (the script's own repo root) — the canonical location of
        the COMPONENTs even when emitting from inside a target project;
    (2) --repo / auto-detected repo — covers a run executed from within the install;
    (3) $CLAUDE_HOME/agents — the global agents home for agent-rooted relpaths.
    """
    roots = [plumbline_install_root()]
    if repo:
        roots.append(os.path.abspath(repo))
    claude_home = os.environ.get("CLAUDE_HOME")
    if claude_home:
        roots.append(os.path.join(os.path.abspath(claude_home), "agents"))
    # De-duplicate while preserving order (install root may equal repo).
    seen = set()
    ordered = []
    for r in roots:
        if r not in seen:
            seen.add(r)
            ordered.append(r)
    return ordered


def fingerprint_component(rel, roots):
    """Hash the first existing `rel` across `roots`; else 'missing:<rel>'.

    On a true miss the unresolved relpath is embedded ('missing:<rel>', never a bare
    'missing') so the gap is diagnosable from the record alone.
    """
    for root in roots:
        candidate = os.path.join(root, rel)
        if os.path.isfile(candidate):
            try:
                return sha256_file(candidate)
            except OSError:
                continue
    return "missing:" + rel


def git(repo, *args):
    try:
        out = subprocess.run(["git", "-C", repo, *args],
                             capture_output=True, text=True, timeout=10)
        return out.stdout.strip() if out.returncode == 0 else ""
    except Exception:
        return ""


def fingerprint(repo):
    roots = search_path(repo)
    return {name: fingerprint_component(rel, roots)
            for name, rel in COMPONENTS.items()}


def all_components_missing(fp):
    """True iff every component resolved to a 'missing:<relpath>' marker."""
    return bool(fp) and all(str(v).startswith("missing:") for v in fp.values())


class InputError(Exception):
    """A user-input problem that must fail closed with a clean ERROR (no traceback)."""


def parse_json_object(text, flag):
    """Parse `text` as JSON and require a JSON object.

    Fail closed: raise InputError (caught in main -> stderr ERROR + exit 2) on either
    a JSONDecodeError or a non-object (list/scalar/null) value. Centralising this means
    every JSON-bearing flag gets the same rigor the metric-key allowlist already has.
    """
    try:
        value = json.loads(text)
    except json.JSONDecodeError as exc:
        raise InputError(f"invalid JSON for {flag}: {exc}") from exc
    if not isinstance(value, dict):
        raise InputError(f"{flag} must be a JSON object")
    return value


def parse_json_array(text, flag):
    """Parse `text` as JSON and require a JSON array (fail closed otherwise)."""
    try:
        value = json.loads(text)
    except json.JSONDecodeError as exc:
        raise InputError(f"invalid JSON for {flag}: {exc}") from exc
    if not isinstance(value, list):
        raise InputError(f"{flag} must be a JSON array")
    return value


def load_metrics(args):
    if args.metrics_file:
        try:
            with open(args.metrics_file, encoding="utf-8") as fh:
                text = fh.read()
        except OSError as exc:
            raise InputError(f"cannot read --metrics-file: {exc}") from exc
        return parse_json_object(text, "--metrics-file")
    if args.metrics:
        return parse_json_object(args.metrics, "--metrics")
    return {}


def validate_metrics(metrics):
    """Fail closed on any metric key not in the scored allowlist (DIRECTIONS)."""
    unknown = sorted(k for k in metrics if k not in ALLOWED_METRICS)
    if unknown:
        raise ValueError(
            "non-allowlisted metric key(s): " + ", ".join(unknown)
            + "\nallowed (process_health.DIRECTIONS): "
            + ", ".join(sorted(ALLOWED_METRICS))
            + "\nput operational counts under --raw instead."
        )


def apply_cost(metrics, raw, tokens_total, reqs_accepted):
    """Emit cost-per-VALIDATED-req, not per green req.

    The caller passes reqs_accepted = the count of REQs whose evidence_class is
    at/above the run's min-evidence (the Reality-Ledger validated count) — NOT
    the count of green tests. tokens_total is the run's output-token total.
    Denominator floored at 1 so a zero-validated run cannot divide by zero.

    Fails closed (InputError) on:
      * negative --tokens-total or --reqs-accepted — a negative numerator slips past
        the max(reqs, 1) floor and yields a negative cost_per_req that corrupts the
        SPC baseline/attribution math in process_health.py.
      * cost_per_req already present in --metrics — refuse to silently overwrite a
        user-supplied value with the computed one (conflicting input).
    """
    if tokens_total is None:
        return
    if tokens_total < 0:
        raise InputError("--tokens-total must be >= 0")
    if reqs_accepted is not None and reqs_accepted < 0:
        raise InputError("--reqs-accepted must be >= 0")
    if "cost_per_req" in metrics:
        raise InputError(
            "cost_per_req supplied both via --metrics and computed from --tokens-total"
        )
    reqs = reqs_accepted if reqs_accepted is not None else 0
    metrics["cost_per_req"] = tokens_total / max(reqs, 1)
    raw["tokens_total"] = tokens_total
    raw["reqs_accepted"] = reqs


def parse_args(argv):
    p = argparse.ArgumentParser(description="Append one /agileteam run record.")
    p.add_argument("--metrics")
    p.add_argument("--metrics-file")
    p.add_argument("--raw", default="{}",
                   help="free-form diagnostic counts (recorded, NOT scored/allowlisted)")
    p.add_argument("--tokens-total", type=int, default=None,
                   help="total output tokens for the run (numerator of cost_per_req)")
    p.add_argument("--reqs-accepted", type=int, default=None,
                   help="count of VALIDATED REQs (evidence_class >= min-evidence) — the denominator")
    p.add_argument("--corpus-id", default="adhoc")
    p.add_argument("--mode", default="core", choices=["core", "full"])
    p.add_argument("--gate-outcomes", default="{}",
                   help="per-gate outcome map (JSON object). Canonical keys: "
                        "phase0_5_spec_sanity, gateA_verification, gateB_security, "
                        "gateC_validation, gateD_judgment (documentary; "
                        "process_health.py does not consume gate_outcomes)")
    p.add_argument("--active-rules", default="[]",
                   help="JSON array of rule_ids active during this run "
                        "(recorded under record['active_rules']; default [])")
    p.add_argument("--human-overrides", type=int, default=0)
    p.add_argument("--baseline", action="store_true")
    p.add_argument("--repo", default=None)
    p.add_argument("--out", default=None)
    p.add_argument("--dry-run", action="store_true")
    p.add_argument("--fail-on-missing-fingerprint", action="store_true",
                   help="exit non-zero if EVERY config_fingerprint component is "
                        "missing (intended ON for agileteam-bench)")
    return p.parse_args(argv)


def main(argv=None):
    args = parse_args(argv if argv is not None else sys.argv[1:])
    repo = args.repo or find_repo_root(".")
    out = args.out or os.path.join(repo, "metrics", "runs.jsonl")

    branch = git(repo, "rev-parse", "--abbrev-ref", "HEAD") or "unknown"
    short = git(repo, "rev-parse", "--short", "HEAD") or "nogit"

    try:
        metrics = load_metrics(args)
        raw = parse_json_object(args.raw, "--raw")
        gate_outcomes = parse_json_object(args.gate_outcomes, "--gate-outcomes")
        active_rules = parse_json_array(args.active_rules, "--active-rules")
        apply_cost(metrics, raw, args.tokens_total, args.reqs_accepted)
        validate_metrics(metrics)
    except (InputError, ValueError) as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        return 2

    record = {
        "run_id": dt.datetime.now(dt.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
                  + "-" + uuid.uuid4().hex[:6],
        "metrics_schema_version": METRICS_SCHEMA_VERSION,
        "corpus_id": args.corpus_id,
        "mode": args.mode,
        "baseline": bool(args.baseline),
        "process_branch": f"{branch}@{short}",
        "config_fingerprint": fingerprint(repo),
        "metrics": metrics,
        "raw": raw,
        "gate_outcomes": gate_outcomes,
        "active_rules": active_rules,
        "human_overrides": args.human_overrides,
    }

    if args.fail_on_missing_fingerprint and all_components_missing(record["config_fingerprint"]):
        print("ERROR: config_fingerprint has no resolved component "
              "(all missing) — Plumbline install not found on the search path",
              file=sys.stderr)
        return 3

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
