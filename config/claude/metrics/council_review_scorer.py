#!/usr/bin/env python3
"""council_review_scorer.py — the shared, JUDGE-FREE flag-set SCORER (Slice 3a).

The single scorer BOTH measurement arms feed (Arm A = Claude-only, via
arm_a_review_runner.py; Arm B = the foreign council, via the read-only instrument
deepseek_review.py). It consumes a reviewer FLAG-SET + a corpus task's seeded-defect
oracle and computes, DETERMINISTICALLY (no LLM judge), the catch / cry-wolf / recall
numbers — both metric families together, with scope visible.

Reality Ledger / house rules:
  * IMPORT-PURE & NETWORK-FREE: no urllib/requests/http/socket/ssl import; no
    run_inference/transport seam. A flag-set + an oracle in, numbers out. (REQ-DM-3a-006)
  * The PRIMARY matching rule (OQ-DM-7) is a deterministic FILE + LINE-RANGE OVERLAP:
    a flag matches a defect iff SAME file AND the flag's [line_start..line_end] (or a
    single `line`) intersects the defect's [line_start..line_end] INCLUSIVE on the
    endpoints (a touch counts); adjacent-non-touch is a miss; a wrong file is a miss.
    One flag matches AT MOST one defect (no double-counting). (REQ-DM-3a-004)
  * Every result carries BOTH metric families — review_catch_rate AND
    review_cry_wolf_rate AND review_recall_control — so a catch-only headline is
    structurally impossible (RISK-DM-001 / NGOAL-DM-004).
  * foreign_only_ok flags an Arm-B (council) result whose model_scope secretly carries
    an anthropic/claude-* id, so 3b can reject silent-Claude contamination (RISK-DM-011).
  * emit-blob routes the numeric review metrics + arm/model_scope under emit_run's
    `--raw` (free-form), NEVER `--metrics` — those keys are NOT in the closed
    process_health.DIRECTIONS allowlist; emit_run rejects a non-allowlisted --metrics
    key. corpus_id goes top-level via --corpus-id. (REQ-DM-3a-005 / IMPORTANT-1)

3a produces NO measurement number — this is the instrument 3b will run.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from typing import Any

# A council result whose model scope carries any of these substrings is contaminated
# with a Claude-family id (foreign-only violation). Matched case-insensitively.
_CLAUDE_MARKERS = ("anthropic", "claude")

# The default non-claim string the substrate stamps on every result: 3a is the
# instrument, not the answer.
NON_CLAIM = ("Slice-3a substrate: this is a deterministic score of a single flag-set; "
             "it is NOT a measurement result. The foreign-vs-Claude comparison is Slice 3b.")


# ---------------------------------------------------------------------------
# Corpus loading (REQ-DM-3a-001) — the consumer's view used by the contract.
# ---------------------------------------------------------------------------
def load_corpus(corpus_dir: str) -> dict[str, Any]:
    """Load a review-catch corpus into {"manifest": ..., "tasks": [...]}.

    Each task is normalized to the shape the scorer + the contract tests consume:
      {"id", "oracle": [ {id,file,line_start,line_end,type}, ... ],
       "clean_controls": [ {file,line_start,line_end}, ... ],
       "recall_control": {file,line_start,line_end}}

    The manifest's `tasks` index points at per-task oracle files; the seeded defects
    live in the corpus oracle (declarative, no Python logic in the corpus).
    """
    manifest_path = os.path.join(corpus_dir, "manifest.json")
    with open(manifest_path, encoding="utf-8") as handle:
        manifest = json.load(handle)

    oracle_path = os.path.join(corpus_dir, "oracle.json")
    with open(oracle_path, encoding="utf-8") as handle:
        oracle_doc = json.load(handle)

    by_id = {entry["id"]: entry for entry in oracle_doc.get("tasks", [])}

    tasks: list[dict[str, Any]] = []
    for task_index in manifest.get("tasks", []):
        task_id = task_index["id"]
        entry = by_id.get(task_id, {})
        tasks.append({
            "id": task_id,
            "oracle": list(entry.get("oracle", [])),
            "clean_controls": list(entry.get("clean_controls", [])),
            "recall_control": entry.get("recall_control"),
        })

    return {"manifest": manifest, "tasks": tasks}


# ---------------------------------------------------------------------------
# Deterministic location-overlap matcher (REQ-DM-3a-004, OQ-DM-7).
# ---------------------------------------------------------------------------
def _flag_span(flag: dict[str, Any]) -> tuple[int, int] | None:
    """Return the (start, end) inclusive line span of a flag, or None if unusable.

    A flag carries either an explicit line_start/line_end range OR a single `line`.
    A flag with neither (or a non-int value) cannot be located → None (counts as a
    cry-wolf when scored, never silently dropped from the flag total).
    """
    start = flag.get("line_start")
    end = flag.get("line_end")
    if start is None and end is None:
        single = flag.get("line")
        if single is None:
            return None
        start = end = single
    elif start is None:
        start = end
    elif end is None:
        end = start
    try:
        lo, hi = int(start), int(end)
    except (TypeError, ValueError):
        return None
    if lo > hi:
        lo, hi = hi, lo
    return (lo, hi)


def _spans_overlap(a: tuple[int, int], b: tuple[int, int]) -> bool:
    """Inclusive-endpoint intersection: a touch (shared endpoint) counts as overlap."""
    return a[0] <= b[1] and b[0] <= a[1]


def _flag_matches_defect(flag: dict[str, Any], defect: dict[str, Any]) -> bool:
    """A flag matches a defect iff SAME file AND line spans overlap (inclusive)."""
    if str(flag.get("file")) != str(defect.get("file")):
        return False
    fspan = _flag_span(flag)
    if fspan is None:
        return False
    try:
        dspan = (int(defect["line_start"]), int(defect["line_end"]))
    except (KeyError, TypeError, ValueError):
        return False
    if dspan[0] > dspan[1]:
        dspan = (dspan[1], dspan[0])
    return _spans_overlap(fspan, dspan)


def _flag_in_clean_control(flag: dict[str, Any], clean_controls: list[dict[str, Any]]) -> bool:
    """True if the flag overlaps any declared clean-control region (a seeded cry-wolf)."""
    fspan = _flag_span(flag)
    if fspan is None:
        return False
    for region in clean_controls:
        if str(flag.get("file")) != str(region.get("file")):
            continue
        try:
            rspan = (int(region["line_start"]), int(region["line_end"]))
        except (KeyError, TypeError, ValueError):
            continue
        if rspan[0] > rspan[1]:
            rspan = (rspan[1], rspan[0])
        if _spans_overlap(fspan, rspan):
            return True
    return False


# ---------------------------------------------------------------------------
# Scoring (REQ-DM-3a-003) — both metric families together, scope visible.
# ---------------------------------------------------------------------------
def _model_scope_carries_claude(model_scope: Any) -> bool:
    """True if any model id in the scope is a Claude/anthropic id (str or list)."""
    if model_scope is None:
        return False
    if isinstance(model_scope, str):
        ids = [model_scope]
    elif isinstance(model_scope, (list, tuple)):
        ids = [str(x) for x in model_scope]
    else:
        ids = [str(model_scope)]
    lowered = " ".join(ids).lower()
    return any(marker in lowered for marker in _CLAUDE_MARKERS)


def score_flag_set(flag_set: dict[str, Any], oracle: dict[str, Any]) -> dict[str, Any]:
    """Score ONE arm's flag-set for ONE task against its seeded-defect oracle.

    Returns BOTH metric families together plus scope, deterministically. The same
    flag-set always yields the same numbers (no judge; numeric).

    catch_count    = # seeded defects matched by >=1 flag (one flag matches <=1 defect).
    cry_wolf_count = # flags overlapping NO seeded defect.
    review_catch_rate     = catch_count / max(#defects, 1).
    review_cry_wolf_rate  = cry_wolf_count / max(#flags, 1).
    review_recall_control = 1.0 if no recall-control region was wrongly narrowed away
                            (i.e. the reviewer did not flag INSIDE the recall control as
                            a defect, which would falsely narrow the no-narrowing guard);
                            else 0.0. With no flag inside it, the guard holds (1.0).
    """
    flags = list(flag_set.get("flags", []))
    defects = list(oracle.get("oracle", []))
    clean_controls = list(oracle.get("clean_controls", []))
    recall_control = oracle.get("recall_control")

    # Greedy one-to-one assignment: a flag matches AT MOST one defect; a defect is
    # caught by AT MOST one flag. Order is deterministic (corpus/flag order is fixed).
    matched_defects: set[int] = set()
    catching_flags: set[int] = set()
    for fi, flag in enumerate(flags):
        for di, defect in enumerate(defects):
            if di in matched_defects:
                continue
            if _flag_matches_defect(flag, defect):
                matched_defects.add(di)
                catching_flags.add(fi)
                break

    catch_count = len(matched_defects)
    # A cry-wolf flag is one that caught no defect (regardless of clean-control overlap;
    # a clean-control flag is the canonical cry-wolf, but ANY non-catching flag counts).
    cry_wolf_count = sum(1 for fi in range(len(flags)) if fi not in catching_flags)

    n_defects = len(defects)
    n_flags = len(flags)
    review_catch_rate = catch_count / n_defects if n_defects else 0.0
    review_cry_wolf_rate = cry_wolf_count / n_flags if n_flags else 0.0

    # Recall control: the no-narrowing guard holds (1.0) unless a flag falsely lands
    # inside the recall-control region (which would mean the reviewer narrowed scope
    # onto a region the corpus declares should not be flagged as a defect).
    review_recall_control = 1.0
    if recall_control is not None:
        for flag in flags:
            if str(flag.get("file")) != str(recall_control.get("file")):
                continue
            fspan = _flag_span(flag)
            if fspan is None:
                continue
            try:
                rspan = (int(recall_control["line_start"]), int(recall_control["line_end"]))
            except (KeyError, TypeError, ValueError):
                continue
            if rspan[0] > rspan[1]:
                rspan = (rspan[1], rspan[0])
            if _spans_overlap(fspan, rspan):
                review_recall_control = 0.0
                break

    arm = flag_set.get("arm")
    model_scope = flag_set.get("model_scope")

    # foreign_only_ok: a council (arm != claude-only) result must carry NO Claude id.
    # An Arm-A (claude-only) result is expected to be Claude → not a violation.
    if arm == "claude-only":
        foreign_only_ok = True
    else:
        foreign_only_ok = not _model_scope_carries_claude(model_scope)

    return {
        "arm": arm,
        "model_scope": model_scope,
        "task": flag_set.get("task"),
        "n": n_defects,
        "task_count": 1,
        "flag_count": n_flags,
        "catch_count": catch_count,
        "cry_wolf_count": cry_wolf_count,
        "review_catch_rate": review_catch_rate,
        "review_cry_wolf_rate": review_cry_wolf_rate,
        "review_recall_control": review_recall_control,
        "foreign_only_ok": foreign_only_ok,
        "non_claim": NON_CLAIM,
    }


# ---------------------------------------------------------------------------
# emit-blob (REQ-DM-3a-005) — route review metrics under emit_run's --raw.
# ---------------------------------------------------------------------------
def build_emit_blob(*, catch: float, cry_wolf: float, recall: float, n: int,
                    task_count: int, arm: str, model_scope: Any) -> dict[str, Any]:
    """Build the {metrics, raw, corpus_id-hint} pair to feed the REAL emit_run.py.

    The numeric review metrics + arm + model_scope ALL go under `raw`, because none of
    review_catch_rate/review_cry_wolf_rate/review_recall_control/n/task_count are in the
    closed process_health.DIRECTIONS allowlist — emit_run rejects a non-allowlisted
    --metrics key. `metrics` is left empty here (3b may add an allowlisted cost metric).
    The caller passes raw to `emit_run.py --raw <json>` and corpus via --corpus-id.
    """
    raw = {
        "review_catch_rate": catch,
        "review_cry_wolf_rate": cry_wolf,
        "review_recall_control": recall,
        "n": n,
        "task_count": task_count,
        "arm": arm,
        "model_scope": model_scope,
        "non_claim": NON_CLAIM,
    }
    return {"metrics": {}, "raw": raw}


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def _cmd_score(args: argparse.Namespace) -> int:
    with open(args.flag_set, encoding="utf-8") as handle:
        flag_set = json.load(handle)
    corpus = load_corpus(args.corpus)
    by_id = {t["id"]: t for t in corpus["tasks"]}
    task_id = flag_set.get("task")
    oracle = by_id.get(task_id)
    if oracle is None:
        print(f"ERROR: task {task_id!r} not in corpus {args.corpus}", file=sys.stderr)
        return 2
    result = score_flag_set(flag_set, oracle)
    print(json.dumps(result, sort_keys=True, indent=2 if args.json else None))
    return 0


def _cmd_emit_blob(args: argparse.Namespace) -> int:
    blob = build_emit_blob(
        catch=args.catch, cry_wolf=args.cry_wolf, recall=args.recall,
        n=args.n, task_count=args.task_count, arm=args.arm, model_scope=args.model_scope,
    )
    print(json.dumps(blob, sort_keys=True))
    return 0


def _cmd_freeze_hash(args: argparse.Namespace) -> int:
    """Recompute the corpus content hash (NFR-DM-3a-005) over manifest+oracle."""
    print(compute_corpus_hash(args.corpus))
    return 0


def compute_corpus_hash(corpus_dir: str) -> str:
    """Deterministic content hash over the corpus's declarative artifacts.

    Hashes oracle.json + the diffs (the load-bearing content), independent of the
    manifest's own `hash` field, so a manifest hash can be verified against it.
    """
    hasher = hashlib.sha256()
    oracle_path = os.path.join(corpus_dir, "oracle.json")
    with open(oracle_path, "rb") as handle:
        hasher.update(handle.read())
    diffs_dir = os.path.join(corpus_dir, "diffs")
    if os.path.isdir(diffs_dir):
        for name in sorted(os.listdir(diffs_dir)):
            with open(os.path.join(diffs_dir, name), "rb") as handle:
                hasher.update(name.encode("utf-8"))
                hasher.update(handle.read())
    return "sha256:" + hasher.hexdigest()


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Shared judge-free flag-set scorer.")
    parser.add_argument("--json", action="store_true", help="Pretty JSON output.")
    sub = parser.add_subparsers(dest="command", required=True)

    p_score = sub.add_parser("score", help="Score a flag-set against the corpus oracle.")
    p_score.add_argument("--flag-set", required=True)
    p_score.add_argument("--corpus", required=True)
    p_score.add_argument("--json", action="store_true")

    p_blob = sub.add_parser("emit-blob", help="Emit the {metrics,raw} pair for emit_run.py --raw.")
    p_blob.add_argument("--catch", type=float, required=True)
    p_blob.add_argument("--cry-wolf", type=float, required=True)
    p_blob.add_argument("--recall", type=float, required=True)
    p_blob.add_argument("--n", type=int, required=True)
    p_blob.add_argument("--task-count", type=int, required=True)
    p_blob.add_argument("--arm", required=True)
    p_blob.add_argument("--model-scope", required=True)

    p_hash = sub.add_parser("freeze-hash", help="Recompute the corpus content hash.")
    p_hash.add_argument("--corpus", required=True)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    if args.command == "score":
        return _cmd_score(args)
    if args.command == "emit-blob":
        return _cmd_emit_blob(args)
    if args.command == "freeze-hash":
        return _cmd_freeze_hash(args)
    return 2  # pragma: no cover - argparse enforces a valid subcommand


if __name__ == "__main__":
    raise SystemExit(main())
