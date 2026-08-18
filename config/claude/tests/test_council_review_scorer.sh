#!/usr/bin/env bash
set -u
#
# Phase-1 BLACK-BOX acceptance contract for Slice 3a — the measurement SUBSTRATE:
#   (1) the NEW review-catch corpus      metrics/corpus/council-review-catch-v1/
#   (3) the shared flag-set SCORER       config/claude/metrics/council_review_scorer.py
# (the Arm-A runner has its own file: test_arm_a_review_runner.sh.)
#
# Written BEFORE any implementation/corpus exists (TDD RED). These tests ARE the
# contract: the coder builds the corpus + scorer to satisfy EXACTLY this file.
# RED NOW because the corpus dir and the scorer module are absent.
#
# Spec sources (frozen, user-confirmed Ben 2026-06-19; OQ-DM-7 = structured flag
# protocol + DETERMINISTIC location-overlap matching for the primary, judge-free):
#   docs/prd/council-diversity-measurement.prd.md     (REQ-DM-3a-001..010, §3 data model)
#   docs/canvas/council-diversity-measurement.canvas.md
#   config/claude/metrics/emit_run.py + process_health.py  (the run-record schema)
#
# ===========================================================================
# SEAM / CONTRACT THE CODER MUST IMPLEMENT (derived independently from the spec)
# ===========================================================================
# A deterministic, NETWORK-FREE, KEY-FREE Python module, importable AND with a CLI:
#
#   python3 config/claude/metrics/council_review_scorer.py score \
#       --flag-set <flagset.json>  --corpus <corpus-dir>  --json
#
# It also exposes an import API used by the determinism/round-trip tests below:
#   score_flag_set(flag_set: dict, oracle: dict) -> dict
#   load_corpus(corpus_dir: str) -> dict   (manifest + per-task oracle index)
#
# --- The corpus oracle CONTRACT (REQ-DM-3a-001) -----------------------------
# metrics/corpus/council-review-catch-v1/manifest.json carries:
#   corpus_id, version, hash, primary_metric="review_catch_rate",
#   secondary_metrics=["review_cry_wolf_rate","review_recall_control"],
#   a provenance note (defects seeded BEFORE/independent of any review),
#   a variance note, and a "tasks" list. Each task dir tasks/<id>/ carries:
#     - the diff under review
#     - a SEEDED-DEFECT oracle: list of {id, file, line_start, line_end, type}
#       (defects defined INDEPENDENTLY of any review)
#     - CLEAN-CONTROL regions: list of {file, line_start, line_end} with NO defect
#     - a recall/no-narrowing control
#   The corpus has >=2 tasks with DISTINCT outcomes (real variance; BLOCKER-2).
#
# --- The reviewer FLAG-SET CONTRACT (scorer input; REQ-DM-3a-003) -----------
# Per arm, per task: {"arm": "<label>", "model_scope": <...>, "task": "<id>",
#   "flags": [ {"file": "...", "line": <int>, "description": "..."} , ... ]}
# A flag may also carry line_start/line_end; the deterministic matcher (OQ-DM-7)
# matches a flag to a seeded defect by FILE + LINE-RANGE OVERLAP.
#
# --- The deterministic MATCHING RULE (REQ-DM-3a-004, OQ-DM-7) ---------------
#   catch    = a flag whose {file,line(-range)} OVERLAPS a seeded-defect span.
#   cry-wolf = a flag overlapping NO seeded defect (esp. one in a clean-control region).
#   recall-control = the no-narrowing guard computed per the corpus recall control.
#   The SAME flag-set always yields the SAME numbers (no judge; numeric, not substring).
#
# --- The scorer OUTPUT CONTRACT (REQ-DM-3a-003/005, §3) ---------------------
# score_flag_set / `score --json` emit BOTH metric families together plus scope:
#   review_catch_rate, review_cry_wolf_rate, review_recall_control,
#   n, task_count, model_scope, arm, foreign_only_ok (assertion field), non_claim.
# Counts (catch_count, cry_wolf_count, flag_count) are also exposed for exactness.
# An output MISSING the cry-wolf field is RED (the substrate forces both).
#
# --- emit_run round-trip (REQ-DM-3a-005, the REAL schema) -------------------
# IMPORTANT-1 (verified against emit_run.py): emit_run REJECTS any --metrics key
# not in process_health.DIRECTIONS. review_catch_rate/review_cry_wolf_rate/
# review_recall_control/n/task_count are NOT in DIRECTIONS today. The scorer MUST
# therefore expose an emit-ready blob that routes the numeric review metrics +
# arm/model_scope under `--raw` (free-form, not allowlisted) so the record assembles
# WITHOUT a non-allowlisted-key error and process_health reads it without crashing.
# The test asserts: those fields land under record["raw"], NONE top-level.
# (CONTRACT DECISION below for the planner.)
# ===========================================================================

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"
cd "$REPO_DIR" || exit 1
# shellcheck source=config/claude/tests/lib.sh
source "$HERE/lib.sh"

SCORER="config/claude/metrics/council_review_scorer.py"
CORPUS="metrics/corpus/council-review-catch-v1"
EMIT="config/claude/metrics/emit_run.py"
PH="config/claude/metrics/process_health.py"

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Run the scorer hermetically (no real key in env; offline).
scorer() { env -i PATH="$PATH" python3 "$SCORER" "$@" 2>&1; }

printf 'Council review SUBSTRATE — corpus + scorer Phase-1 contract (RED until built)\n'

# ===========================================================================
# 0. ARTIFACT PRESENCE — drives the RED state before implementation.
# ===========================================================================
assert_file "REQ-DM-3a-003 scorer module exists" "$SCORER"
assert_file "REQ-DM-3a-001 corpus manifest exists" "$CORPUS/manifest.json"

# ===========================================================================
# 1. CORPUS SCHEMA + VARIANCE  (REQ-DM-3a-001; BLOCKER-2; NGOAL-DM-003/004)
#    These: "a corpus exists." Gegenthese: a single saturated task is GREEN-shaped
#    but has no across-task variance → 3b cannot pin a noise threshold/MDE, and a
#    corpus with no clean control physically cannot produce cry-wolf → the whole
#    anti-Goodhart guarantee is void. Schärfung: assert >=2 DISTINCT-outcome tasks,
#    >=1 clean control, >=1 recall control, and seeded-defect oracles — by reading
#    the corpus through the scorer's own load_corpus (the consumer's view).
# ===========================================================================
CORPUS_CHECK="$(env -i PATH="$PATH" python3 - "$REPO_DIR" "$CORPUS" <<'PY' 2>&1
import importlib.util, json, sys, pathlib
repo, corpus = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location(
    "council_review_scorer",
    pathlib.Path(repo) / "config/claude/metrics/council_review_scorer.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
c = m.load_corpus(str(pathlib.Path(repo) / corpus))
man = c["manifest"]
tasks = c["tasks"]            # list of {id, oracle:[...], clean_controls:[...], recall_control:{...}}
out = {
  "corpus_id": man.get("corpus_id"),
  "has_hash": bool(man.get("hash")),
  "primary": man.get("primary_metric"),
  "secondary": man.get("secondary_metrics"),
  "task_count": len(tasks),
  "tasks_with_seeded_defect": sum(1 for t in tasks if t.get("oracle")),
  "tasks_with_clean_control": sum(1 for t in tasks if t.get("clean_controls")),
  "tasks_with_recall_control": sum(1 for t in tasks if t.get("recall_control")),
  # an oracle entry must carry the machine-checkable matcher fields:
  "oracle_fields_ok": all(
     all(k in d for k in ("id","file","line_start","line_end","type"))
     for t in tasks for d in t.get("oracle", [])),
}
print(json.dumps(out, sort_keys=True))
PY
)"
assert_contains "REQ-DM-3a-001 corpus_id is council-review-catch-v1" "$CORPUS_CHECK" '"corpus_id": "council-review-catch-v1"'
assert_contains "NFR-DM-3a-005 manifest carries a content hash" "$CORPUS_CHECK" '"has_hash": true'
assert_contains "REQ-DM-3a-003 primary metric is review_catch_rate" "$CORPUS_CHECK" '"primary": "review_catch_rate"'
assert_contains "REQ-DM-3a-003 secondary carries review_cry_wolf_rate" "$CORPUS_CHECK" "review_cry_wolf_rate"
assert_contains "REQ-DM-3a-003 secondary carries review_recall_control" "$CORPUS_CHECK" "review_recall_control"
assert_contains "BLOCKER-2 corpus has >=2 tasks (not single-task)" "$CORPUS_CHECK" '"task_count": 2'  # >=2; 2 is the floor the contract requires
assert_json_eq "REQ-DM-3a-001 >=1 task carries a seeded-defect oracle" "$CORPUS_CHECK" 'd["tasks_with_seeded_defect"]>=1' True
assert_json_eq "NGOAL-DM-004 >=1 clean control region exists (cry-wolf oracle)" "$CORPUS_CHECK" 'd["tasks_with_clean_control"]>=1' True
assert_json_eq "REQ-DM-3a-001 >=1 recall/no-narrowing control exists" "$CORPUS_CHECK" 'd["tasks_with_recall_control"]>=1' True
assert_contains "REQ-DM-3a-004 seeded-defect oracle carries matcher fields (file/line_start/line_end/type)" "$CORPUS_CHECK" '"oracle_fields_ok": true'

# BLOCKER-2 variance, asserted ON THE SCORER: the corpus must admit >=2 DISTINCT
# outcomes. Score a "perfect" flag-set (one exact flag per seeded defect, none
# elsewhere) across all tasks and assert NOT every task is saturated — i.e. the
# per-task catch rate is not identical across tasks under a fixed reviewer policy.
VARIANCE="$(env -i PATH="$PATH" python3 - "$REPO_DIR" "$CORPUS" <<'PY' 2>&1
import importlib.util, json, sys, pathlib
repo, corpus = sys.argv[1], sys.argv[2]
spec = importlib.util.spec_from_file_location(
    "council_review_scorer",
    pathlib.Path(repo) / "config/claude/metrics/council_review_scorer.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
c = m.load_corpus(str(pathlib.Path(repo) / corpus))
# A reviewer that flags EXACTLY the FIRST seeded defect of each task (a fixed,
# corpus-independent policy). On a saturated single-defect corpus this catches 100%
# everywhere; with real variance (tasks differ in #defects) the per-task catch rate
# differs -> >=2 distinct outcomes. This is the BLOCKER-2 not-saturated assertion.
rates = []
for t in c["tasks"]:
    oracle = t.get("oracle", [])
    flags = ([{"file": oracle[0]["file"], "line": oracle[0]["line_start"],
               "description": "first-only policy"}] if oracle else [])
    fs = {"arm": "probe", "model_scope": "probe", "task": t["id"], "flags": flags}
    res = m.score_flag_set(fs, t)
    rates.append(round(res["review_catch_rate"], 6))
print(json.dumps({"distinct_outcomes": len(set(rates)), "rates": rates}, sort_keys=True))
PY
)"
assert_json_eq "BLOCKER-2 corpus is NOT saturated: >=2 DISTINCT task outcomes under a fixed policy" "$VARIANCE" 'd["distinct_outcomes"]>=2' True

# ===========================================================================
# 2. SCORER DETERMINISM + LOCATION-OVERLAP (THE HEART — REQ-DM-3a-004, OQ-DM-7)
#    These: "the scorer counts catches." Gegenthese: a fuzzy/judge matcher makes
#    catch judge-dependent (RISK-DM-012) and a substring-y check silently passes
#    wrong signs/magnitudes (Slice-1 retro). Schärfung: drive a FIXED synthetic
#    oracle + flag-sets entirely in-process and assert EXACT integer counts and
#    EXACT rates for: exact-on-span=catch; in-clean-control=cry-wolf; no-overlap=
#    cry-wolf; partial-overlap boundary; multi-flag mix; ZERO flags; and identical
#    re-run (determinism). No corpus files needed — this isolates the matcher.
# ===========================================================================
MATCH="$(env -i PATH="$PATH" python3 - "$REPO_DIR" <<'PY' 2>&1
import importlib.util, json, sys, pathlib
repo = sys.argv[1]
spec = importlib.util.spec_from_file_location(
    "council_review_scorer",
    pathlib.Path(repo) / "config/claude/metrics/council_review_scorer.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)

# A synthetic single-task oracle: ONE seeded defect over a/b.py lines 10..14,
# and ONE clean-control region over a/b.py lines 50..60. recall_control present.
oracle = {
  "id": "T-syn",
  "oracle": [{"id": "D1", "file": "a/b.py", "line_start": 10, "line_end": 14, "type": "logic"}],
  "clean_controls": [{"file": "a/b.py", "line_start": 50, "line_end": 60}],
  "recall_control": {"file": "a/b.py", "line_start": 1, "line_end": 5},
}
def fs(flags): return {"arm": "claude-only", "model_scope": "tier-x", "task": "T-syn", "flags": flags}

cases = {}
# (a) a flag EXACTLY on the seeded-defect span -> 1 catch, 0 cry-wolf.
cases["exact_on_defect"] = m.score_flag_set(
    fs([{"file": "a/b.py", "line": 12, "description": "x"}]), oracle)
# (b) a flag inside the CLEAN-CONTROL region -> 0 catch, 1 cry-wolf.
cases["in_clean_control"] = m.score_flag_set(
    fs([{"file": "a/b.py", "line": 55, "description": "x"}]), oracle)
# (c) a flag overlapping NO oracle span (and not a clean control) -> 0 catch, 1 cry-wolf.
cases["no_overlap"] = m.score_flag_set(
    fs([{"file": "a/b.py", "line": 200, "description": "x"}]), oracle)
# (d) PARTIAL overlap boundary: a flag range 14..20 touches the defect end (14) -> catch.
cases["partial_overlap_touch"] = m.score_flag_set(
    fs([{"file": "a/b.py", "line_start": 14, "line_end": 20, "description": "x"}]), oracle)
# (e) ADJACENT-but-not-overlapping: range 15..20 does NOT touch 10..14 -> NOT a catch.
cases["adjacent_no_touch"] = m.score_flag_set(
    fs([{"file": "a/b.py", "line_start": 15, "line_end": 20, "description": "x"}]), oracle)
# (f) WRONG FILE same line -> NOT a catch (overlap is file-scoped).
cases["wrong_file"] = m.score_flag_set(
    fs([{"file": "other/z.py", "line": 12, "description": "x"}]), oracle)
# (g) multi-flag mix: one catch + one clean-control cry-wolf + one no-overlap cry-wolf.
cases["multi_mix"] = m.score_flag_set(
    fs([{"file": "a/b.py", "line": 11, "description": "catch"},
        {"file": "a/b.py", "line": 55, "description": "cw1"},
        {"file": "a/b.py", "line": 300, "description": "cw2"}]), oracle)
# (h) ZERO flags -> 0 catch, 0 cry-wolf.
cases["zero_flags"] = m.score_flag_set(fs([]), oracle)
# (i) DETERMINISM: identical input twice -> identical numbers.
r1 = m.score_flag_set(fs([{"file": "a/b.py", "line": 12, "description": "x"}]), oracle)
r2 = m.score_flag_set(fs([{"file": "a/b.py", "line": 12, "description": "x"}]), oracle)
cases["determinism_equal"] = (r1 == r2)

def pick(r):
    return {"catch": r.get("catch_count"), "cw": r.get("cry_wolf_count"),
            "rate": round(r.get("review_catch_rate", -1), 6),
            "cw_rate": round(r.get("review_cry_wolf_rate", -1), 6),
            "has_cw_field": "review_cry_wolf_rate" in r,
            "has_recall_field": "review_recall_control" in r}
print(json.dumps({k: (pick(v) if isinstance(v, dict) else v)
                  for k, v in cases.items()}, sort_keys=True))
PY
)"
# Exact integer counts (NOT substrings) per the matcher contract.
assert_json_eq "OQ-DM-7 exact-on-defect span => exactly 1 catch" "$MATCH" 'd["exact_on_defect"]["catch"]==1' True
assert_json_eq "OQ-DM-7 exact-on-defect => exactly 0 cry-wolf" "$MATCH" 'd["exact_on_defect"]["cw"]==0' True
assert_json_eq "OQ-DM-7 flag in clean-control => 0 catch, 1 cry-wolf" "$MATCH" 'd["in_clean_control"]["catch"]==0 and d["in_clean_control"]["cw"]==1' True
assert_json_eq "OQ-DM-7 flag overlapping no oracle span => 0 catch, 1 cry-wolf" "$MATCH" 'd["no_overlap"]["catch"]==0 and d["no_overlap"]["cw"]==1' True
assert_json_eq "OQ-DM-7 partial-overlap touching defect end (14) => catch" "$MATCH" 'd["partial_overlap_touch"]["catch"]==1' True
assert_json_eq "OQ-DM-7 adjacent range (15..20) NOT overlapping 10..14 => NOT a catch" "$MATCH" 'd["adjacent_no_touch"]["catch"]==0' True
assert_json_eq "OQ-DM-7 overlap is FILE-scoped: same line wrong file => NOT a catch" "$MATCH" 'd["wrong_file"]["catch"]==0' True
assert_json_eq "OQ-DM-7 multi-flag mix => exactly 1 catch and 2 cry-wolf" "$MATCH" 'd["multi_mix"]["catch"]==1 and d["multi_mix"]["cw"]==2' True
assert_json_eq "OQ-DM-7 ZERO flags => 0 catch AND 0 cry-wolf" "$MATCH" 'd["zero_flags"]["catch"]==0 and d["zero_flags"]["cw"]==0' True
assert_json_eq "NFR-DM-3a-002 determinism: identical flag-set => identical numbers" "$MATCH" 'd["determinism_equal"] is True' True

# Exact RATE (not substring): 1 catch / 1 seeded defect => 1.0; cry-wolf rate exact.
assert_json_eq "OQ-DM-7 exact catch RATE == 1.0 for 1/1 (numeric, not substring)" "$MATCH" 'd["exact_on_defect"]["rate"]==1.0' True
assert_json_eq "OQ-DM-7 zero-flags catch RATE == 0.0 (numeric)" "$MATCH" 'd["zero_flags"]["rate"]==0.0' True

# ===========================================================================
# 3. BOTH METRIC FAMILIES TOGETHER + SCOPE (RISK-DM-001; REQ-DM-3a-003)
#    These: a scorer "reports catch." Gegenthese: a catch-only headline is the exact
#    anti-Goodhart failure the substrate must forbid. Schärfung: EVERY scorer result
#    MUST carry cry-wolf AND recall fields together, plus n / task_count / model_scope
#    / arm — a result missing the cry-wolf field is RED.
# ===========================================================================
assert_json_eq "RISK-DM-001 every result carries the cry-wolf field (both families together)" "$MATCH" 'all(v.get("has_cw_field") for v in d.values() if isinstance(v,dict))' True
assert_json_eq "REQ-DM-3a-003 every result carries the recall-control field" "$MATCH" 'all(v.get("has_recall_field") for v in d.values() if isinstance(v,dict))' True

SCOPECHECK="$(env -i PATH="$PATH" python3 - "$REPO_DIR" <<'PY' 2>&1
import importlib.util, json, sys, pathlib
repo = sys.argv[1]
spec = importlib.util.spec_from_file_location(
    "council_review_scorer",
    pathlib.Path(repo) / "config/claude/metrics/council_review_scorer.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
oracle = {"id":"T","oracle":[{"id":"D1","file":"a.py","line_start":1,"line_end":3,"type":"x"}],
          "clean_controls":[{"file":"a.py","line_start":9,"line_end":9}],"recall_control":{"file":"a.py","line_start":1,"line_end":1}}
r = m.score_flag_set({"arm":"claude-only","model_scope":"opus-tier","task":"T",
                      "flags":[{"file":"a.py","line":2,"description":"x"}]}, oracle)
print(json.dumps({k: r.get(k) for k in
   ("n","task_count","model_scope","arm","review_catch_rate","review_cry_wolf_rate",
    "review_recall_control","foreign_only_ok")}, sort_keys=True))
PY
)"
assert_contains "REQ-DM-3a-003 result carries model_scope" "$SCOPECHECK" '"model_scope": "opus-tier"'
assert_contains "REQ-DM-3a-003 result carries arm label" "$SCOPECHECK" '"arm": "claude-only"'
assert_json_eq "REQ-DM-3a-003 result carries n (>=1)" "$SCOPECHECK" 'd["n"]>=1' True
assert_json_eq "REQ-DM-3a-003 result carries task_count (>=1)" "$SCOPECHECK" 'd["task_count"]>=1' True

# ===========================================================================
# 4. FOREIGN-ONLY ASSERTION FIELD  (REQ-DM-3a-003; RISK-DM-011)
#    These: "a council result is scored." Gegenthese: an Arm-B result whose model
#    scope secretly contains a Claude/anthropic id is silent-Claude contamination —
#    scoring it as a valid council result launders the comparison. Schärfung: the
#    scorer FLAGS any arm!=claude-only result whose model_scope holds anthropic/claude-*
#    (foreign_only_ok=false) so 3b can reject it; a genuinely-foreign council passes.
# ===========================================================================
FOREIGN="$(env -i PATH="$PATH" python3 - "$REPO_DIR" <<'PY' 2>&1
import importlib.util, json, sys, pathlib
repo = sys.argv[1]
spec = importlib.util.spec_from_file_location(
    "council_review_scorer",
    pathlib.Path(repo) / "config/claude/metrics/council_review_scorer.py")
m = importlib.util.module_from_spec(spec); spec.loader.exec_module(m)
oracle = {"id":"T","oracle":[{"id":"D1","file":"a.py","line_start":1,"line_end":3,"type":"x"}],
          "clean_controls":[],"recall_control":{"file":"a.py","line_start":1,"line_end":1}}
def f(arm, scope): return m.score_flag_set({"arm":arm,"model_scope":scope,"task":"T","flags":[]}, oracle)
print(json.dumps({
  "council_foreign": f("council-A", ["openai/gpt-4","mistral/large"]).get("foreign_only_ok"),
  "council_contaminated": f("council-A", ["openai/gpt-4","anthropic/claude-3"]).get("foreign_only_ok"),
  "council_contaminated_str": f("council-A", "anthropic/claude-3-opus").get("foreign_only_ok"),
}, sort_keys=True))
PY
)"
assert_contains "RISK-DM-011 genuinely-foreign council scope => foreign_only_ok true" "$FOREIGN" '"council_foreign": true'
assert_contains "RISK-DM-011 anthropic/claude id in council scope => foreign_only_ok false (flagged)" "$FOREIGN" '"council_contaminated": false'
assert_contains "RISK-DM-011 claude id (string scope) in council => foreign_only_ok false" "$FOREIGN" '"council_contaminated_str": false'

# ===========================================================================
# 5. SCORER -> emit_run ROUND-TRIP against the REAL schema (REQ-DM-3a-005, IMPORTANT-1)
#    These: "metrics get emitted." Gegenthese: the previous PRD put catch_rate/arm/
#    model_scope at the TOP LEVEL — emit_run rejects unknown top-level metric keys and
#    process_health reads ONLY metrics.<name>, so a wrong shape is a silently-broken
#    pipeline. Schärfung: the scorer's emit-ready blob, fed to the REAL emit_run.py,
#    must (i) assemble WITHOUT a non-allowlisted-key error, (ii) land the review
#    metrics + arm/model_scope under record["raw"], (iii) put NONE of them top-level,
#    and (iv) process_health.py must load the record without crashing.
# ===========================================================================
# The scorer exposes `emit-blob` which prints the {--metrics, --raw} pair the caller
# passes to emit_run (the contract: review metrics route via --raw, see header).
EMITBLOB="$(scorer emit-blob --catch 0.5 --cry-wolf 0.25 --recall 1.0 --n 4 --task-count 2 --arm claude-only --model-scope opus-tier 2>&1)"
# Extract the --raw object the scorer recommends and feed emit_run for real.
RAWOBJ="$(printf '%s' "$EMITBLOB" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)["raw"]))' 2>/dev/null)"
RECORD="$(env -i PATH="$PATH" python3 "$EMIT" --dry-run --corpus-id council-review-catch-v1 --metrics '{}' --raw "$RAWOBJ" 2>&1)"
RC=$?
assert "REQ-DM-3a-005 emit_run assembles the scorer raw-blob WITHOUT a non-allowlist error (rc 0)" "[ $RC -eq 0 ]"
assert_json_eq "REQ-DM-3a-005 review_catch_rate lands under record.raw, NOT top-level" "$RECORD" '"review_catch_rate" in d["raw"] and "review_catch_rate" not in d' True
assert_json_eq "REQ-DM-3a-005 review_cry_wolf_rate lands under record.raw" "$RECORD" '"review_cry_wolf_rate" in d["raw"]' True
assert_json_eq "REQ-DM-3a-005 arm + model_scope land under record.raw, NOT top-level" "$RECORD" '"arm" in d["raw"] and "model_scope" in d["raw"] and "arm" not in d and "model_scope" not in d' True
assert_json_eq "REQ-DM-3a-005 corpus_id is the new corpus (top-level, per emit_run)" "$RECORD" 'd["corpus_id"]' council-review-catch-v1
# process_health must read the assembled record without crashing (it reads metrics.<name>).
printf '%s\n' "$RECORD" | python3 -c 'import json,sys; print(json.dumps(json.load(sys.stdin)))' > "$WORK/runs.jsonl" 2>/dev/null
assert "REQ-DM-3a-005 process_health reads the record without crashing" "env -i PATH=\"$PATH\" python3 \"$PH\" --runs \"$WORK/runs.jsonl\" --out \"$WORK/ph.md\" >/dev/null 2>&1"

# ===========================================================================
# 6. ISOLATION GUARD (REQ-DM-3a-006 / NFR-DM-3a-004) — scorer is offline, judge-free.
#    The scorer must contain NO network import and NO live/transport seam: it is a
#    pure flag-set + oracle -> numbers function. (A judge or network call here would
#    re-introduce RISK-DM-008/012.)
# ===========================================================================
assert "REQ-DM-3a-006 scorer imports no network module (urllib/requests/http/socket)" "! grep -nE '^(import|from)[[:space:]]+(urllib|requests|http|socket|ssl)' \"$SCORER\""
assert_no_code_token "RISK-DM-008 scorer has no judge/LLM call seam (no run_inference/transport)" "$SCORER" 'run_inference|_real_transport|openrouter|OPENROUTER'

# ===========================================================================
# 7. CORPUS ORACLE <-> DIFF FIDELITY  (BLOCKER-1 — the falsifier that was MISSING)
#    These: "oracle.json declares the seeded defects." Gegenthese: oracle.json is
#    self-consistent and the whole scorer suite is GREEN, yet the oracle line numbers
#    point at the WRONG new-file lines of the diff (e.g. a comment, or the defensive
#    guard) — so every measured "catch" rewards a reviewer for flagging a line that
#    carries NO defect, and a real defect line is never the catch target. The numbers
#    are real, deterministic, and meaningless. (This is exactly the gap that let
#    BLOCKER-1 through: NO test tied oracle.json lines to the real diff content.)
#    Schärfung: independently re-parse each diff hunk (@@ ... +<start> @@), map every
#    ADDED (+) line to its real new-file line number, and assert FOR EACH TASK:
#      - each seeded-defect [line_start..line_end] lands on actual added(+) lines AND
#        the line text carries the defect-type's anti-pattern token (closed vocab:
#        timing-side-channel => '=='; resource-exhaustion/unhandled-exception => 'int(')
#      - each CLEAN-CONTROL region maps to real added(+) lines that overlap NO seeded
#        defect (a control that secretly sits on a defect is not a cry-wolf control).
#    Eval-free: the corpus dir is passed as argv (NEVER eval'd); the helper hunk-parses
#    + asserts and prints a JSON verdict, checked via the non-eval assert_json_eq path.
#    PROVEN falsifier: with the pre-fix oracle this reports ok:false (3 mismatches:
#    T1/D1 lands on 'if header is None:' not the '==' compare; T2/D1,D2 land on comment
#    lines, not the int() calls); with the coder's corrected oracle it reports ok:true.
# ===========================================================================
FIDELITY="$(env -i PATH="$PATH" python3 - "$CORPUS" <<'PY' 2>&1
import json, pathlib, re, sys

# Closed defect-type vocabulary -> the anti-pattern token that MUST appear on the
# real seeded-defect line(s). Keeps the assertion tied to diff CONTENT, not a number.
DEFECT_TOKENS = {
    "timing-side-channel": "==",       # non-constant-time secret compare
    "resource-exhaustion": "int(",     # unbounded int() conversion (no clamp)
    "unhandled-exception": "int(",     # unguarded int() parse (no try/except)
}

def parse_added_lines(diff_text):
    # Map each ADDED (+) new-file line number -> its text, per the @@ +<start> @@ header.
    block = re.search(r"```diff\n(.*?)```", diff_text, re.S)
    if not block:
        return None
    added, new_ln = {}, None
    for line in block.group(1).splitlines():
        if line.startswith("@@"):
            mm = re.search(r"\+(\d+)", line)
            new_ln = int(mm.group(1)) if mm else None
            continue
        if new_ln is None:
            continue
        if line.startswith("+"):
            added[new_ln] = line[1:]
            new_ln += 1
        elif line.startswith("-"):
            pass          # old-file-only line: does NOT advance the new-file counter
        else:
            new_ln += 1   # context line: present on both sides
    return added

corpus = pathlib.Path(sys.argv[1])
oracle = json.loads((corpus / "oracle.json").read_text())
failures, checked_defects, checked_controls = [], 0, 0

for task in oracle["tasks"]:
    tid = task["id"]
    diff_path = corpus / "diffs" / f"{tid}.md"
    if not diff_path.is_file():
        failures.append(f"{tid}: diff file missing"); continue
    added = parse_added_lines(diff_path.read_text())
    if added is None:
        failures.append(f"{tid}: no diff fenced block parsed"); continue
    defect_spans = [range(d["line_start"], d["line_end"] + 1) for d in task.get("oracle", [])]
    # (2) each seeded defect must land on real added lines AND carry its anti-pattern token.
    for d in task.get("oracle", []):
        checked_defects += 1
        did, dtype = d.get("id", "?"), d.get("type")
        if dtype not in DEFECT_TOKENS:
            failures.append(f"{tid}/{did}: type {dtype!r} not in closed vocabulary"); continue
        token = DEFECT_TOKENS[dtype]
        span_lines = [n for n in range(d["line_start"], d["line_end"] + 1) if n in added]
        if not span_lines:
            failures.append(f"{tid}/{did}: oracle span {d['line_start']}..{d['line_end']} hits NO added(+) line"); continue
        if not any(token in added[n] for n in span_lines):
            failures.append(f"{tid}/{did}: token {token!r} ({dtype}) absent from oracle span {d['line_start']}..{d['line_end']}")
    # (3) each clean-control region must map to real added lines that overlap NO defect.
    for cc in task.get("clean_controls", []):
        checked_controls += 1
        span_lines = [n for n in range(cc["line_start"], cc["line_end"] + 1) if n in added]
        if not span_lines:
            failures.append(f"{tid}: clean-control {cc['line_start']}..{cc['line_end']} hits NO added(+) line"); continue
        overlapped = [n for n in span_lines if any(n in ds for ds in defect_spans)]
        if overlapped:
            failures.append(f"{tid}: clean-control {cc['line_start']}..{cc['line_end']} overlaps a seeded defect at {overlapped}")

print(json.dumps({"ok": not failures, "checked_defects": checked_defects,
                  "checked_controls": checked_controls, "failures": failures}, sort_keys=True))
PY
)"
assert_json_eq "BLOCKER-1 every seeded-defect oracle range lands on real added(+) lines carrying its anti-pattern token, and every clean-control is defect-free (oracle<->diff fidelity)" "$FIDELITY" 'd["ok"] is True' True
assert_json_eq "BLOCKER-1 fidelity test actually exercised the seeded defects (>=3 checked, not a no-op)" "$FIDELITY" 'd["checked_defects"]>=3' True
assert_json_eq "BLOCKER-1 fidelity test actually exercised the clean-control regions (>=2 checked, not a no-op)" "$FIDELITY" 'd["checked_controls"]>=2' True

finish "Council review substrate (corpus + scorer)"
