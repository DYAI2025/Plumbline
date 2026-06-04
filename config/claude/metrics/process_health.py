#!/usr/bin/env python3
"""
process_health.py — the meta-meta layer for /agileteam.

Reads metrics/runs.jsonl and answers two questions (docs/agileteam-governance.md §4):
  (1) Is the process "in control"?   -> SPC on each metric's run time-series.
  (2) WHICH component is drifting?    -> attribution by config_fingerprint version.

It then prints alerts and writes metrics/process-health.md. It only ever *proposes*
counter-steering (flag -> freeze -> revert -> escalate); every action stays human-gated.

Pure standard library.

Usage
-----
  process_health.py [--runs metrics/runs.jsonl] [--out metrics/process-health.md]
                    [--baseline-window 10] [--sustained-window 5] [--sigma 3.0]
"""
import argparse
import json
import os
import statistics as st
import sys
from collections import OrderedDict, defaultdict

# +1 = higher is better, -1 = lower is better. Unknown metrics default to +1.
DIRECTIONS = {
    "first_pass": +1, "acceptance_first_try": +1, "mutation": +1, "coverage": +1,
    "dre": +1,
    "escaped_defect_rate": -1, "regression": -1, "unverified_claims": -1,
    "cycle_time": -1, "lead_time": -1, "dev_review_loops": -1,
    "human_override_rate": -1, "escalation_rate": -1, "cost_per_req": -1,
    "challenge_gate_tokens": -1,
    "root_cause_trigger_rate": -1,
}


def direction(metric):
    return DIRECTIONS.get(metric, +1)


def load_runs(path):
    runs = []
    with open(path, encoding="utf-8") as fh:
        for ln in fh:
            ln = ln.strip()
            if ln:
                runs.append(json.loads(ln))
    return runs


def baseline_values(runs, metric, window):
    tagged = [r["metrics"][metric] for r in runs
              if r.get("baseline") and metric in r.get("metrics", {})]
    if len(tagged) >= 2:
        return tagged
    vals = [r["metrics"][metric] for r in runs if metric in r.get("metrics", {})]
    return vals[:window]


def worse_side(metric, value, ref):
    """True if `value` is on the bad side of `ref` for this metric's direction."""
    return value < ref if direction(metric) > 0 else value > ref


def monotonic_worse_run(series, metric, length=7):
    """Longest run of consecutive steps moving in the worse direction."""
    if len(series) < length:
        return False
    d = direction(metric)
    best = run = 1
    for i in range(1, len(series)):
        step = series[i] - series[i - 1]
        worse = step < 0 if d > 0 else step > 0
        run = run + 1 if worse else 1
        best = max(best, run)
    return best >= length


def spc_for_metric(runs, metric, window, sustained_window, sigma):
    series = [r["metrics"][metric] for r in runs if metric in r.get("metrics", {})]
    if len(series) < 2:
        return None
    base = baseline_values(runs, metric, window)
    if len(base) < 2:
        return None
    mu = st.mean(base)
    sd = st.pstdev(base)
    ucl, lcl = mu + sigma * sd, mu - sigma * sd

    signals = []
    last = series[-1]
    # 1) point beyond control limits on the worse side
    if direction(metric) > 0 and last < lcl:
        signals.append(f"last point {last:.3f} < LCL {lcl:.3f}")
    if direction(metric) < 0 and last > ucl:
        signals.append(f"last point {last:.3f} > UCL {ucl:.3f}")
    # 2) Western-Electric-style run rule
    if monotonic_worse_run(series, metric, length=7):
        signals.append("7+ consecutive steps worsening")
    # 3) sustained below/above baseline mean
    tail = series[-sustained_window:]
    if len(tail) >= sustained_window and all(worse_side(metric, v, mu) for v in tail):
        signals.append(f"{sustained_window} consecutive on the worse side of baseline mean")

    return {
        "metric": metric, "n": len(series), "mu": mu, "sd": sd,
        "ucl": ucl, "lcl": lcl, "last": last,
        "status": "SIGNAL" if signals else "in-control", "signals": signals,
    }


def attribute(runs, metric):
    """Mean of `metric` per version of each component, in first-seen order."""
    suspects = []
    comps = OrderedDict()
    for r in runs:
        for c, v in r.get("config_fingerprint", {}).items():
            comps.setdefault(c, None)
    for comp in comps:
        by_ver = OrderedDict()
        for r in runs:
            v = r.get("config_fingerprint", {}).get(comp)
            m = r.get("metrics", {}).get(metric)
            if v is None or m is None:
                continue
            by_ver.setdefault(v, []).append(m)
        if len(by_ver) < 2:
            continue
        means = [(v, st.mean(xs)) for v, xs in by_ver.items()]
        # worsening across successive versions?
        d = direction(metric)
        deltas = [means[i + 1][1] - means[i][1] for i in range(len(means) - 1)]
        worsening = all((dl < 0 if d > 0 else dl > 0) for dl in deltas)
        if worsening and len(means) >= 2:
            seq = " -> ".join(f"{m:.3f}" for _, m in means)
            suspects.append((comp, seq))
    return suspects


def render(report, out):
    lines = ["# /agileteam — Process Health Board", ""]
    lines.append(f"Runs analysed: **{report['n_runs']}**  ·  baseline window: "
                 f"{report['baseline_window']}  ·  sigma: {report['sigma']}")
    lines.append("")
    signals = [m for m in report["metrics"] if m["status"] == "SIGNAL"]
    verdict = "⚠ SIGNAL — investigate" if signals else "✓ in control"
    lines += [f"## Verdict: {verdict}", ""]

    lines += ["## SPC per metric", "",
              "| Metric | n | baseline μ | σ | last | status | signals |",
              "|---|---|---|---|---|---|---|"]
    for m in report["metrics"]:
        lines.append(f"| {m['metric']} | {m['n']} | {m['mu']:.3f} | {m['sd']:.3f} "
                     f"| {m['last']:.3f} | {m['status']} | "
                     f"{'; '.join(m['signals']) or '—'} |")
    lines.append("")

    lines += ["## Attribution (worsening across component versions)", ""]
    if report["attribution"]:
        lines.append("| Metric | Component | mean per version (first→latest) |")
        lines.append("|---|---|---|")
        for metric, comp, seq in report["attribution"]:
            lines.append(f"| {metric} | {comp} | {seq} |")
    else:
        lines.append("No component shows monotonic worsening. —")
    lines.append("")

    lines += [
        "## Counter-steering (human-gated; hysteresis, never reflexive)",
        "",
        "A single out-of-control point is noise (LLM stochasticity). Act only on a "
        "sustained signal. Smallest intervention first:",
        "",
        "1. **FLAG** + one more observation window (change nothing, keep measuring).",
        "2. **FREEZE** the implicated component (no new versions until recovered).",
        "3. **REVERT** the single version-hypothesis (one commit) that introduced it.",
        "4. **ESCALATE** to a human for redesign.",
        "",
        "Auto-revert threshold: a primary quality metric below the frozen baseline over "
        "the confirmation window proposes reverting the last component version (alert; "
        "execution human-gated). See docs/agileteam-governance.md §4c.",
    ]
    out_dir = os.path.dirname(out)
    if out_dir:
        os.makedirs(out_dir, exist_ok=True)
    with open(out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(lines) + "\n")


def parse_args(argv):
    p = argparse.ArgumentParser(description="Meta-meta process-health analysis.")
    p.add_argument("--runs", default="metrics/runs.jsonl")
    p.add_argument("--out", default="metrics/process-health.md")
    p.add_argument("--baseline-window", type=int, default=10)
    p.add_argument("--sustained-window", type=int, default=5)
    p.add_argument("--sigma", type=float, default=3.0)
    return p.parse_args(argv)


def main(argv=None):
    args = parse_args(argv if argv is not None else sys.argv[1:])
    if not os.path.exists(args.runs):
        print(f"no runs file at {args.runs} — nothing to analyse "
              f"(emit some runs first).", file=sys.stderr)
        return 1
    runs = load_runs(args.runs)
    if not runs:
        print("runs file is empty.", file=sys.stderr)
        return 1

    all_metrics = []
    for r in runs:
        for k in r.get("metrics", {}):
            if k not in all_metrics:
                all_metrics.append(k)

    metric_reports, attribution = [], []
    for metric in all_metrics:
        spc = spc_for_metric(runs, metric, args.baseline_window,
                             args.sustained_window, args.sigma)
        if spc:
            metric_reports.append(spc)
        for comp, seq in attribute(runs, metric):
            attribution.append((metric, comp, seq))

    report = {
        "n_runs": len(runs), "baseline_window": args.baseline_window,
        "sigma": args.sigma, "metrics": metric_reports, "attribution": attribution,
    }
    render(report, args.out)

    signals = [m for m in metric_reports if m["status"] == "SIGNAL"]
    if signals:
        print(f"⚠ {len(signals)} metric(s) signalling drift -> {args.out}")
        for m in signals:
            print(f"  - {m['metric']}: {'; '.join(m['signals'])}")
    else:
        print(f"✓ process in control across {len(metric_reports)} metric(s) "
              f"-> {args.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
