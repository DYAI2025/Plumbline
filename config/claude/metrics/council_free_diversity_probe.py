#!/usr/bin/env python3
"""Best-effort FREE-ONLY diversity probe (no-budget reframe of the powered run).

This is NOT the frozen 3b instrument (council_measurement_run.py, which pins
council_presets.py byte-unchanged via REQ-MR-009 and therefore cannot be repointed at
chosen models). It is a SEPARATE, honestly-labelled probe harness that REUSES the vetted
primitives READ-ONLY and adds only a per-model dispatch + council-union loop:

  - council_measurement_run.run_arm_a   (structured protocol -> council_inference real
                                          boundary -> the SAME parse_flag_set; ARM SYMMETRY)
  - council_review_scorer.score_flag_set / load_corpus / compute_corpus_hash  (the vetted
                                          deterministic 3a scorer; no judge)
  - council_measurement_run.classify_outcome  (the frozen MDE/survivors rubric)

The key is header-only via the reused council_inference real transport; never logged.
ONE run, NO re-roll (re-running until survivors appear would be p-hacking).

HONEST REFRAME: with no paid budget the baseline (Arm A) is a single FREE model, NOT
Claude. So this measures "does a multi-model FREE council catch more than a single free
model, without more cry-wolf?" — NOT "council vs Claude". At n=2 only `underpowered` /
`tradeoff-signal-to-investigate` are reachable (`demonstrated`/`refuted` are out of reach).

Usage (gated, live, real free calls):
  COUNCIL_INFERENCE_LIVE=1 OPENROUTER_API_KEY=... python3 council_free_diversity_probe.py
The model set is the one that was reachable at run time (free-tier reachability is
intermittent — see the benchmark write-up for the captured run's reachability context).
"""
import os
import sys
import json

_HERE = os.path.dirname(os.path.abspath(__file__))            # config/claude/metrics
ROOT = os.path.dirname(os.path.dirname(os.path.dirname(_HERE)))  # repo root
sys.path.insert(0, os.path.join(ROOT, "config", "claude", "lib"))
sys.path.insert(0, _HERE)
import council_review_scorer as scorer  # noqa: E402
import council_measurement_run as mr  # noqa: E402

BASELINE = os.environ.get("FREE_PROBE_BASELINE", "google/gemma-4-31b-it:free")
COUNCIL = os.environ.get(
    "FREE_PROBE_COUNCIL",
    "openai/gpt-oss-120b:free,nvidia/nemotron-3-super-120b-a12b:free",
).split(",")
CORPUS = os.path.join(ROOT, "metrics", "corpus", "council-review-catch-v1")
MIN_SURVIVORS = int(os.environ.get("FREE_PROBE_MIN_SURVIVORS", "2"))
MDE = float(os.environ.get("FREE_PROBE_MDE", "0.5"))


def main() -> int:
    prereg = {
        "experiment": "council-free-diversity-probe",
        "reframe": "free-only diversity probe; baseline is a single FREE model, NOT Claude",
        "baseline": BASELINE, "council": COUNCIL, "corpus": "council-review-catch-v1",
        "corpus_hash": scorer.compute_corpus_hash(CORPUS),
        "n": 2, "min_survivors": MIN_SURVIVORS, "mde": MDE, "noise_model": "cross-task-variance",
        "reachable_outcomes": ["underpowered", "tradeoff-signal-to-investigate"],
        "note": "at n=2 demonstrated/refuted are definitionally unreachable; free-tier rate-limits expected",
    }
    print("=== FROZEN PRE-REGISTRATION (before the run) ===")
    print(json.dumps(prereg, indent=2))

    env = dict(os.environ)
    calls = {"n": 0}

    def bump():
        calls["n"] += 1

    corpus = scorer.load_corpus(CORPUS)
    oracle_by_id = {t["id"]: t for t in corpus["tasks"]}
    survivors = 0
    records, attrition = [], []
    a_catch, b_catch, a_cw, b_cw = [], [], [], []

    print("\n=== RUN (one pass, no re-roll) ===")
    for task in corpus["tasks"]:
        tid = task["id"]
        oracle = oracle_by_id[tid]
        diff = mr._load_task_diff(CORPUS, tid)
        a = mr.run_arm_a(diff, model_scope=BASELINE, task_id=tid, env=env, live=True,
                         injected_raw=None, on_call=bump)
        council_results = [mr.run_arm_a(diff, model_scope=m, task_id=tid, env=env, live=True,
                                        injected_raw=None, on_call=bump) for m in COUNCIL]
        codes = [a["code"]] + [c["code"] for c in council_results]
        non_ok = [c for c in codes if c != mr.COUNCIL_OK]
        if non_ok:
            attrition.append({"task": tid, "reason": non_ok[0], "all_codes": codes})
            print(f"  {tid}: EXCLUDED (paired) codes={codes}")
            continue
        union = []
        for c in council_results:
            for f in c["flags"]:
                if f not in union:
                    union.append(f)
        sa = scorer.score_flag_set(
            {"arm": mr.ARM_A, "task": tid, "model_scope": BASELINE, "flags": a["flags"]}, oracle)
        sb = scorer.score_flag_set(
            {"arm": mr.ARM_B, "task": tid, "model_scope": "+".join(COUNCIL), "flags": union}, oracle)
        survivors += 1
        a_catch.append(sa["review_catch_rate"]); b_catch.append(sb["review_catch_rate"])
        a_cw.append(sa["review_cry_wolf_rate"]); b_cw.append(sb["review_cry_wolf_rate"])
        records.append({"task": tid,
                        "baseline": {"catch": sa["review_catch_rate"], "cry_wolf": sa["review_cry_wolf_rate"],
                                     "flags": len(a["flags"]), "foreign_only_ok": sa.get("foreign_only_ok")},
                        "council": {"catch": sb["review_catch_rate"], "cry_wolf": sb["review_cry_wolf_rate"],
                                    "flags": len(union), "foreign_only_ok": sb.get("foreign_only_ok")}})
        print(f"  {tid}: baseline catch={sa['review_catch_rate']} cw={sa['review_cry_wolf_rate']} | "
              f"council catch={sb['review_catch_rate']} cw={sb['review_cry_wolf_rate']} (union {len(union)} flags)")

    def mean(xs):
        return sum(xs) / len(xs) if xs else 0.0

    catch_delta = mean(b_catch) - mean(a_catch)
    cw_delta = mean(b_cw) - mean(a_cw)
    outcome = mr.classify_outcome(survivors, MIN_SURVIVORS, catch_delta=catch_delta,
                                  cry_wolf_delta=cw_delta, mde=MDE)
    print("\n=== RESULT ===")
    print(json.dumps({"outcome": outcome, "survivors": survivors, "min_survivors": MIN_SURVIVORS,
                      "calls_attempted": calls["n"], "catch_delta": catch_delta, "cry_wolf_delta": cw_delta,
                      "attrition": attrition, "records": records}, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
