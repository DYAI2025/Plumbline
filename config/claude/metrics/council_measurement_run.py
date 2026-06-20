#!/usr/bin/env python3
"""council_measurement_run.py — the MEASUREMENT-RUN orchestrator (Slice 3b).

The ONLY new code module for Slice 3b. It CONSUMES the read-only 3a substrate +
instrument and ORCHESTRATES the foreign-model-council measurement; it adds NO
scoring logic, NO transport, and NO instrument of its own (REQ-MR-009). The
read-only files it imports stay byte-unchanged after every run.

What it does, per corpus task, for BOTH arms:
  * Arm A (``claude-only``) — build the structured-flag-protocol messages via the
    read-only ``arm_a_review_runner.build_messages``; reach Arm A's REAL boundary by
    calling ``council_inference.run_inference(...)`` DIRECTLY with the gated real
    transport (NOT by editing the frozen 3a runner — resolving the REQ-MR-005 vs
    REQ-MR-009 contradiction). Offline: an injected per-task raw output, parsed by
    the SAME parser.
  * Arm B (``council-A``) — invoke ``deepseek_review.py preset --preset A --subject
    <subject+protocol>`` gated; offline via this orchestrator's OWN per-role
    injection seam (``positions[]``-shaped fixture keyed by task id, since the single
    ``deepseek_review --inject-response`` cannot give distinct per-role outputs).

ARM SYMMETRY (REQ-MR-002): a BYTE-IDENTICAL structured-flag-protocol instruction is
appended to the subject for BOTH arms, and BOTH arms' raw outputs are parsed by the
SAME ``parse_arm_output`` → ``arm_a_review_runner.parse_flag_set``. A non-protocol
output is the SAME classified empty parse for both arms — never silently zeroing one.

Honesty discipline (carried from the PRD/canvas):
  * Paired-exclusion: any Arm-B role with ``code != OK`` excludes the SUBJECT from
    BOTH arms (attrition by difficulty, never a council miss); ``code == OK`` + 0
    flags is a SCORED legitimate empty review (a real miss). Below the
    pre-registered minimum survivors → outcome ``underpowered``.
  * Foreign-only: an Arm-B role carrying an ``anthropic``/``claude`` id fails closed
    for that subject — never emitted as a valid (``foreign_only_ok`` true) council
    result.
  * Budget = a MAX-CALLS ceiling; ``--live`` REFUSES without ``--max-calls``; the
    live gate is OFF by default → 0 transport calls.
  * n=2 rubric: ``demonstrated``/``refuted`` are definitionally out of reach; the
    only reachable outcomes are ``underpowered`` / ``tradeoff-signal-to-investigate``.
  * Emission routes per-arm via the REAL ``emit_run.py --raw`` (review metrics under
    ``record.raw``, ``corpus_id`` top-level); the raw key never enters the
    allowlisted ``--metrics`` block.
  * No key material in any output / runs.jsonl; malformed responses classify (never
    a fabricated flag).
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
from typing import Any

# config/claude/lib/ and config/claude/metrics/ are not packages — add both to the
# import path so the read-only substrate + instrument modules resolve (mirrors how
# deepseek_review.py wires its sibling lib imports).
_HERE = os.path.dirname(os.path.abspath(__file__))
_LIB = os.path.normpath(os.path.join(_HERE, "..", "lib"))
for _p in (_HERE, _LIB):
    if _p not in sys.path:
        sys.path.insert(0, _p)

import arm_a_review_runner  # noqa: E402  (read-only 3a runner — build_messages/parse_flag_set)
import council_inference  # noqa: E402  (read-only instrument — run_inference + gated real boundary)
import council_presets  # noqa: E402  (read-only roster — preset role count for the worst-case ceiling)
import council_review_scorer  # noqa: E402  (read-only 3a scorer — score_flag_set/build_emit_blob)

ARM_A = "claude-only"
ARM_B = "council-A"

# The only OK code on the Arm-B (preset) path; any other role code is non-OK.
COUNCIL_OK = "COUNCIL_INFERENCE_OK"

# n=2 pilot outcome vocabulary — closed (REQ-MR-007). demonstrated/refuted are
# definitionally out of reach at n=2 and are NEVER emitted by this orchestrator.
OUTCOME_UNDERPOWERED = "underpowered"
OUTCOME_TRADEOFF = "tradeoff-signal-to-investigate"

# The default minimum-survivors floor when no pre-registration is supplied. The
# scored / pre-registered run reads the floor from the frozen artifact instead.
DEFAULT_MIN_SURVIVORS = 2

# The structured-flag-protocol instruction appended (byte-identical) to BOTH arms'
# review subject. It demands the {"flags":[...]} envelope arm_a_review_runner.
# parse_flag_set requires, so the SAME parser consumes both arms (ARM SYMMETRY).
STRUCTURED_FLAG_PROTOCOL = (
    "\n\n----- STRUCTURED FLAG PROTOCOL (response format) -----\n"
    "Emit your findings ONLY as a single JSON object {\"flags\": [ ... ]} where each\n"
    "finding is an object with EXACTLY these keys:\n"
    "  - \"file\": the file path the finding is in (string)\n"
    "  - \"line\": the line number the finding is at (integer)\n"
    "  - \"description\": a short description of the defect (string)\n"
    "Flag ONLY real defects; do NOT invent findings. If there are no defects, emit\n"
    "{\"flags\": []}. Do not flag correct, defect-free code.\n"
    "----- END STRUCTURED FLAG PROTOCOL -----\n"
)


# ---------------------------------------------------------------------------
# Shared parser (REQ-MR-002 / C2) — the SINGLE entrypoint used for BOTH arms.
# ---------------------------------------------------------------------------
def parse_arm_output(raw_text: str, *, arm: str) -> tuple[list[dict[str, Any]], str]:
    """Parse one arm's RAW model output into (flags, code), identically for both arms.

    Delegates to the read-only ``arm_a_review_runner.parse_flag_set`` so Arm A and
    Arm B are parsed by the EXACT SAME parser (ARM SYMMETRY). A non-protocol output
    yields an EMPTY flag-set with the SAME classified code for both arms — never a
    fabricated flag, never silently zeroing only one arm. ``arm`` is accepted for the
    symmetric call shape; the parse is independent of it by construction.
    """
    if not isinstance(raw_text, str):
        raw_text = ""
    flags, code = arm_a_review_runner.parse_flag_set(raw_text)
    return list(flags), code


# ---------------------------------------------------------------------------
# Subject + protocol (REQ-MR-002) — symmetric flag protocol for both arms.
# ---------------------------------------------------------------------------
def build_arm_a_messages(diff_text: str, model_scope: str) -> list[dict[str, str]]:
    """Arm-A messages = the read-only runner's structured-flag-protocol prompt."""
    return arm_a_review_runner.build_messages(diff_text, model_scope)


def build_arm_b_subject(diff_text: str) -> str:
    """Arm-B review subject = the diff under review + the IDENTICAL protocol suffix.

    Threaded VERBATIM into each preset role's user message by ``deepseek_review.py
    preset --subject`` (belegt), so Arm B is prompted in the byte-identical protocol
    Arm A embeds — the symmetry contract.
    """
    return (
        "Review the diff under review below and report every genuine defect you find.\n"
        "----- DIFF UNDER REVIEW -----\n"
        f"{diff_text}\n"
        "----- END DIFF -----\n"
        + STRUCTURED_FLAG_PROTOCOL
    )


# ---------------------------------------------------------------------------
# Security N1 — confine @path injects to the work dir.
# ---------------------------------------------------------------------------
class RunError(Exception):
    """A fail-closed orchestration error: surfaced as a non-zero exit, never swallowed."""


def _resolve_inject_arg(raw: str | None, *, flag: str, work_dir: str) -> str | None:
    """Resolve a ``--inject-*`` arg: ``@path`` reads a file CONFINED to the work dir.

    N1: an ``@path`` whose realpath escapes the work dir is REFUSED (no arbitrary-file
    read, no content leak). A literal (non-``@``) value is returned verbatim.
    """
    if raw is None:
        return None
    if not raw.startswith("@"):
        return raw
    candidate = raw[1:]
    base = os.path.realpath(work_dir)
    path = os.path.realpath(os.path.join(base, candidate)) if not os.path.isabs(candidate) \
        else os.path.realpath(candidate)
    if os.path.commonpath([base, path]) != base:
        raise RunError(f"{flag} @path refused: outside the work dir (no arbitrary read)")
    if not os.path.isfile(path):
        raise RunError(f"{flag} @path not found within the work dir")
    with open(path, encoding="utf-8") as handle:
        return handle.read()


def _parse_inject_json(raw: str | None, *, flag: str) -> dict[str, Any]:
    """Parse an injection JSON object (keyed by task id), fail-closed on bad shape."""
    if raw is None:
        return {}
    try:
        value = json.loads(raw)
    except (ValueError, TypeError) as exc:
        raise RunError(f"invalid JSON for {flag}: {exc}") from exc
    if not isinstance(value, dict):
        raise RunError(f"{flag} must be a JSON object keyed by task id")
    return value


# ---------------------------------------------------------------------------
# Arm runners.
# ---------------------------------------------------------------------------
def run_arm_a(
    diff_text: str,
    *,
    model_scope: str,
    task_id: str,
    env: dict[str, str],
    live: bool,
    injected_raw: str | None,
    on_call,
) -> dict[str, Any]:
    """Run Arm A: offline via an injected raw output, live via DIRECT run_inference.

    The real boundary is reached by calling ``council_inference.run_inference(...)``
    with Arm-A's structured-protocol messages and the gated real transport — NEVER by
    editing the read-only runner. Offline (no live gate / injected output) fires 0
    transport calls. Returns {arm, task, model_scope, code, flags}.
    """
    messages = build_arm_a_messages(diff_text, model_scope)

    if injected_raw is not None:
        # Offline path: parse the injected raw output with the shared parser; the
        # injected seam goes through run_inference's no-network inject branch so the
        # call counter stays 0 and the path is identical to the live classification.
        result = council_inference.run_inference(
            env,
            model=model_scope,
            messages=messages,
            max_tokens=256,
            input_estimate=council_inference.estimate_input_tokens(messages),
            dry_run=False,
            build_only=False,
            inject_response=injected_raw,
            inject_error=None,
            inject_retry_after=None,
            transport=None,
            on_transport_call=on_call,
        )
        raw_completion = result.get("completion")
        flags, code = parse_arm_output(raw_completion if raw_completion is not None else injected_raw,
                                       arm=ARM_A)
        return {"arm": ARM_A, "task": task_id, "model_scope": model_scope,
                "code": COUNCIL_OK, "flags": flags, "parse_code": code}

    # Live path: gated by --live AND COUNCIL_INFERENCE_LIVE=1. The transport callable
    # is supplied ONLY when armed; otherwise the no-network branch fires 0 calls.
    transport = _live_transport(env) if live else None
    result = council_inference.run_inference(
        env,
        model=model_scope,
        messages=messages,
        max_tokens=256,
        input_estimate=council_inference.estimate_input_tokens(messages),
        dry_run=False,
        build_only=False,
        inject_response=None,
        inject_error=None,
        inject_retry_after=None,
        transport=transport,
        on_transport_call=on_call,
    )
    code = result.get("code")
    if code != COUNCIL_OK:
        return {"arm": ARM_A, "task": task_id, "model_scope": model_scope,
                "code": code, "flags": [], "parse_code": None}
    flags, parse_code = parse_arm_output(result.get("completion") or "", arm=ARM_A)
    return {"arm": ARM_A, "task": task_id, "model_scope": model_scope,
            "code": COUNCIL_OK, "flags": flags, "parse_code": parse_code,
            "usage": result.get("usage")}


def _live_transport(env: dict[str, str]):
    """Return the instrument's gated real transport ONLY when the env gate is armed.

    The transport object is owned by the read-only instrument; this orchestrator does
    NOT define one of its own. Gate: COUNCIL_INFERENCE_LIVE=1 (the caller also requires
    the --live flag AND a --max-calls ceiling before reaching here).
    """
    if env.get("COUNCIL_INFERENCE_LIVE") == "1":
        # CONSUME the read-only instrument's gated real-transport callable by a plain
        # reference. This orchestrator DEFINES no transport of its own and imports no
        # http — the read-only instrument owns the real boundary; we only reach it
        # (REQ-MR-005). A plain reference is permitted by the contract's AST real-
        # invariant check (no `def _real_transport`, no http import, no urlopen call).
        return council_inference._real_transport
    return None


def run_arm_b(
    diff_text: str,
    *,
    task_id: str,
    preset: str,
    env: dict[str, str],
    live: bool,
    injected_positions: list[dict[str, Any]] | None,
    on_call,
) -> dict[str, Any]:
    """Run Arm B (the foreign council) for one task.

    Offline: the orchestrator's OWN per-role injection seam supplies a
    ``positions[]``-shaped fixture (mirroring ``deepseek_review preset``), so distinct
    per-role council outputs are exercised (the single ``deepseek_review
    --inject-response`` cannot). Live: shell out to ``deepseek_review.py preset
    --preset <p> --subject <subject+protocol>`` with the live gate armed.

    For each role with ``code == OK`` the raw position is parsed by the SAME parser and
    the per-role flags are UNIONed into one council flag-set; ``model_scope`` = the OK
    roles' foreign model ids. Returns {arm, task, model_scope, positions, flags,
    role_codes}.
    """
    if injected_positions is not None:
        positions = injected_positions
    else:
        positions = _live_preset_positions(diff_text, preset=preset, env=env, live=live,
                                            on_call=on_call)

    role_codes: list[str] = []
    model_scope: list[str] = []
    union_flags: list[dict[str, Any]] = []
    for role in positions:
        code = role.get("code")
        role_codes.append(code)
        model = role.get("model")
        if code == COUNCIL_OK:
            if model is not None:
                model_scope.append(str(model))
            position = role.get("position")
            flags, _ = parse_arm_output(position if position is not None else "", arm=ARM_B)
            for flag in flags:
                if flag not in union_flags:
                    union_flags.append(flag)
    return {"arm": ARM_B, "task": task_id, "model_scope": model_scope,
            "positions": positions, "flags": union_flags, "role_codes": role_codes}


def _live_preset_positions(diff_text: str, *, preset: str, env: dict[str, str], live: bool,
                           on_call) -> list[dict[str, Any]]:
    """Reach Arm B's real boundary via the read-only deepseek_review preset CLI.

    Shells out (live gate armed in the child env) and returns its ``positions[]``.
    Each real role invocation counts one transport call. Offline (no live gate) the
    child fires 0 calls; offline tests use the injected per-role seam instead.
    """
    cmd = [sys.executable, os.path.join(_LIB, "deepseek_review.py"), "preset",
           "--preset", preset, "--subject", build_arm_b_subject(diff_text)]
    if live:
        cmd.append("--live")
    proc = subprocess.run(cmd, capture_output=True, text=True, env=env, check=False)
    if proc.returncode != 0:
        raise RunError(f"deepseek_review preset failed: {proc.stderr.strip()[:200]}")
    try:
        payload = json.loads(proc.stdout)
    except (ValueError, TypeError) as exc:
        raise RunError(f"deepseek_review preset returned non-JSON: {exc}") from exc
    positions = payload.get("positions", [])
    # Count each OK role as one real transport invocation (the preset path fired them).
    for role in positions:
        if role.get("code") == COUNCIL_OK:
            on_call()
    return positions


# ---------------------------------------------------------------------------
# Scoring (REQ-MR-003) — read-only scorer, no local math.
# ---------------------------------------------------------------------------
def score_arm(arm_result: dict[str, Any], oracle: dict[str, Any]) -> dict[str, Any]:
    """Score one arm's flag-set through the read-only scorer (deterministic)."""
    flag_set = {
        "arm": arm_result["arm"],
        "model_scope": arm_result["model_scope"],
        "task": arm_result["task"],
        "flags": arm_result["flags"],
    }
    return council_review_scorer.score_flag_set(flag_set, oracle)


def _load_task_diff(corpus_dir: str, task_id: str) -> str:
    """Read a corpus task's diff text (diffs/<task-id>.md), or empty if absent."""
    path = os.path.join(corpus_dir, "diffs", f"{task_id}.md")
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as handle:
            return handle.read()
    return ""


def difficulty_of(oracle: dict[str, Any]) -> int:
    """A subject's difficulty = its seeded-defect count (cross-task variance source)."""
    return len(oracle.get("oracle", []))


# ---------------------------------------------------------------------------
# Pre-registration (REQ-MR-007).
# ---------------------------------------------------------------------------
def load_preregistration(path: str | None) -> dict[str, Any] | None:
    """STRICT-load the frozen pre-registration artifact, or None when absent."""
    if path is None:
        return None
    try:
        with open(path, encoding="utf-8") as handle:
            value = json.load(handle)
    except OSError as exc:
        raise RunError(f"cannot read --pre-registration: {exc}") from exc
    except (ValueError, TypeError) as exc:
        raise RunError(f"invalid pre-registration JSON: {exc}") from exc
    if not isinstance(value, dict):
        raise RunError("pre-registration must be a JSON object")
    return value


def _mean(values: list[float]) -> float:
    """Arithmetic mean over the surviving-subject values (0.0 over an empty list)."""
    return sum(values) / len(values) if values else 0.0


def classify_outcome(
    survivors: int,
    min_survivors: int,
    *,
    catch_delta: float,
    cry_wolf_delta: float,
    mde: float,
) -> str:
    """n=2 pilot classifier — closed vocabulary (REQ-MR-007).

    Implements BOTH halves of the frozen pre-registration's ``underpowered`` rubric:
    ``survivors below min_survivors OR the observed catch delta below the MDE``
    (noise_model: cross-task-variance). The ``mde`` is READ from the artifact by the
    caller (never hardcoded) and threaded in here.

    Ordering:
      * ``survivors < min_survivors``                → ``underpowered``.
      * ELSE ``abs(catch_delta) < mde``             → ``underpowered`` (a below-MDE
        delta is NEVER laundered as a tradeoff signal — pure noise stays underpowered).
      * ELSE (above-MDE catch delta) catch up AND cry-wolf up
                                                     → ``tradeoff-signal-to-investigate``.
      * ELSE                                         → ``tradeoff-signal-to-investigate``.

    ``demonstrated`` and ``refuted`` are definitionally out of reach at n=2 (cross-task
    variance is unestimable) and are NEVER emitted by this orchestrator. The closed
    reachable pilot vocabulary is exactly {underpowered, tradeoff-signal-to-investigate}.
    """
    if survivors < min_survivors:
        return OUTCOME_UNDERPOWERED
    if abs(catch_delta) < mde:
        return OUTCOME_UNDERPOWERED
    # Above the MDE: an interpretable signal at n=2 is, at most, a catch-vs-cry-wolf
    # trade to investigate — never a demonstrated/refuted claim.
    return OUTCOME_TRADEOFF


def worst_case_call_count(preset: str, task_count: int) -> int:
    """A-priori UPPER BOUND on real transport calls for a --live run (REQ-MR-005).

    Computed UP FRONT, before any dispatch: per task, Arm A fires 1 real call and Arm B
    (the ``deepseek_review`` preset) fires one call per role in the preset roster (all
    roles fire in one subprocess with no mid-call cap), so the worst case is
    ``task_count × (1 + roles_in_preset)``. An unknown preset has no bounded roster →
    its role count is treated as 0 here (the live path classifies the unknown preset
    itself when it runs); the ceiling check still applies to the Arm-A calls.
    """
    roster = council_presets.get_preset(preset) or []
    roles = len(roster)
    return task_count * (1 + roles)


# ---------------------------------------------------------------------------
# Emission (REQ-MR-006) — route per-arm records through the REAL emit_run.py --raw.
# ---------------------------------------------------------------------------
def emit_arm_record(scored: dict[str, Any], *, corpus_id: str, out_path: str | None) -> None:
    """Build the scorer's emit-blob and append via the REAL emit_run.py --raw.

    Review metrics + arm + model_scope land under ``record.raw``; ``corpus_id`` is
    top-level via ``--corpus-id``. The allowlisted ``--metrics`` block stays empty (a
    review key there would make emit_run exit 2). OSError on the write surfaces (N2).
    """
    blob = council_review_scorer.build_emit_blob(
        catch=scored["review_catch_rate"],
        cry_wolf=scored["review_cry_wolf_rate"],
        recall=scored["review_recall_control"],
        n=scored["n"],
        task_count=scored["task_count"],
        arm=scored["arm"],
        model_scope=scored["model_scope"],
    )
    raw = dict(blob["raw"])
    raw["task"] = scored["task"]
    raw["foreign_only_ok"] = scored["foreign_only_ok"]
    argv = ["--raw", json.dumps(raw), "--corpus-id", corpus_id]
    if out_path is not None:
        argv += ["--out", out_path]
    rc = _emit_run_main(argv)
    if rc != 0:
        raise RunError(f"emit_run.py refused the record (exit {rc})")


def _emit_run_main(argv: list[str]) -> int:
    """Invoke the REAL emit_run.py main(), surfacing an OSError write failure (N2).

    emit_run.py swallows nothing on a JSON/allowlist error (returns non-zero) but does
    NOT guard the final append's OSError; we run it as a subprocess so an unwritable
    --out (e.g. /proc/...) surfaces as a non-zero child exit rather than a swallowed
    traceback in-process.
    """
    cmd = [sys.executable, os.path.join(_HERE, "emit_run.py"), *argv]
    proc = subprocess.run(cmd, capture_output=True, text=True, check=False)
    return proc.returncode


# ---------------------------------------------------------------------------
# The run flow.
# ---------------------------------------------------------------------------
def _record_for_output(scored: dict[str, Any]) -> dict[str, Any]:
    """Project a scored arm result into the run --json records[] entry shape (C5)."""
    return {
        "arm": scored["arm"],
        "task": scored["task"],
        "review_catch_rate": scored["review_catch_rate"],
        "review_cry_wolf_rate": scored["review_cry_wolf_rate"],
        "review_recall_control": scored["review_recall_control"],
        "n": scored["n"],
        "task_count": scored["task_count"],
        "foreign_only_ok": scored["foreign_only_ok"],
        "model_scope": scored["model_scope"],
    }


def run(args: argparse.Namespace, env: dict[str, str]) -> dict[str, Any]:
    """Execute the full per-task arm→score→classify→emit loop. Fail-closed."""
    work_dir = os.getcwd()

    # Budget gate (REQ-MR-005): --live REFUSES without --max-calls (0 calls).
    if args.live and args.max_calls is None:
        raise RunError("--live requires --max-calls (a MAX-CALLS ceiling); refusing to start")

    # Pre-registration: --score (or any pre-registration path) requires a frozen
    # artifact. --score with none present REFUSES (REQ-MR-007).
    prereg = load_preregistration(args.pre_registration)
    if args.score and prereg is None:
        raise RunError("--score requires a frozen pre-registration artifact; refusing to score")
    min_survivors = (int(prereg["min_survivors"]) if prereg and "min_survivors" in prereg
                     else DEFAULT_MIN_SURVIVORS)
    # The MDE is READ from the frozen artifact (never hardcoded). With no pre-registration
    # the MDE half of the rubric is inert (0.0) so the survivors floor governs alone.
    mde = float(prereg["mde"]) if prereg and "mde" in prereg else 0.0

    inject_arm_a = _parse_inject_json(
        _resolve_inject_arg(args.inject_arm_a, flag="--inject-arm-a", work_dir=work_dir),
        flag="--inject-arm-a")
    inject_arm_b = _parse_inject_json(
        _resolve_inject_arg(args.inject_arm_b, flag="--inject-arm-b", work_dir=work_dir),
        flag="--inject-arm-b")

    corpus = council_review_scorer.load_corpus(args.corpus)
    corpus_id = corpus["manifest"].get("corpus_id", "adhoc")
    oracle_by_id = {t["id"]: t for t in corpus["tasks"]}

    # Corpus-freeze guarantee (security review Note 1): when a pre-registration carries
    # a `corpus_hash`, the loaded corpus MUST be the exact one the artifact was frozen
    # against. Recompute the freeze-hash the SAME way the corpus/tests do — by reusing
    # the read-only scorer's compute_corpus_hash (NEVER reimplementing the hash) — and
    # FAIL CLOSED on mismatch BEFORE any scoring/dispatch (no transport, 0 calls). A
    # pre-registration with no `corpus_hash` keeps today's behavior (no new requirement).
    if prereg is not None and "corpus_hash" in prereg:
        expected_hash = prereg["corpus_hash"]
        actual_hash = council_review_scorer.compute_corpus_hash(args.corpus)
        if actual_hash != expected_hash:
            raise RunError(
                "corpus_hash mismatch: the loaded corpus does not match the frozen "
                f"pre-registration ({expected_hash} expected, {actual_hash} loaded); "
                "refusing to score against a different corpus (no dispatch, 0 calls)")

    # MAX-CALLS CEILING (REQ-MR-005 / NFR-MR-003): on a --live run, compute the WORST-CASE
    # real-call count UP FRONT and FAIL CLOSED before ANY dispatch if it exceeds the cap.
    # (deepseek_review preset fires all roles in one subprocess with no mid-call cap, so an
    # a-priori upper bound is the only honest ceiling.) A roomy cap does NOT trip this.
    if args.live and args.max_calls is not None:
        worst_case = worst_case_call_count(args.preset, len(corpus["tasks"]))
        if worst_case > args.max_calls:
            raise RunError(
                f"worst-case real-call count {worst_case} exceeds --max-calls {args.max_calls}; "
                "refusing to start (no dispatch, 0 calls)")

    offline = not args.live

    calls = {"n": 0}

    def _bump() -> None:
        calls["n"] += 1

    records: list[dict[str, Any]] = []
    attrition: list[dict[str, Any]] = []
    survivors = 0
    # Per-arm catch / cry-wolf values over SURVIVING subjects only — the basis for the
    # MDE catch-delta and cry-wolf-delta halves of the rubric (REQ-MR-007).
    arm_a_catch: list[float] = []
    arm_b_catch: list[float] = []
    arm_a_crywolf: list[float] = []
    arm_b_crywolf: list[float] = []

    for task in corpus["tasks"]:
        task_id = task["id"]
        oracle = oracle_by_id[task_id]
        diff_text = _load_task_diff(args.corpus, task_id)

        # Arm A.
        a_injected = inject_arm_a.get(task_id) if offline else None
        if offline and a_injected is None:
            # No offline injection supplied for this task → an empty (NEEDS_INJECTION)
            # output, parsed identically (classified empty, never fabricated).
            a_injected = ""
        arm_a_result = run_arm_a(
            diff_text, model_scope=args.claude_model, task_id=task_id, env=env,
            live=args.live, injected_raw=a_injected, on_call=_bump)

        # Arm B.
        b_injected = inject_arm_b.get(task_id) if offline else None
        arm_b_result = run_arm_b(
            diff_text, task_id=task_id, preset=args.preset, env=env, live=args.live,
            injected_positions=b_injected, on_call=_bump)

        # Paired-exclusion (REQ-MR-004): any Arm-B role code != OK → exclude the
        # subject from BOTH arms (attrition by difficulty), never a council miss.
        non_ok = [c for c in arm_b_result["role_codes"] if c != COUNCIL_OK]
        if arm_a_result["code"] != COUNCIL_OK:
            non_ok.append(arm_a_result["code"])
        if non_ok:
            attrition.append({"task": task_id, "reason": non_ok[0],
                              "difficulty": difficulty_of(oracle)})
            continue

        # Score both arms through the read-only scorer.
        scored_a = score_arm(arm_a_result, oracle)
        scored_b = score_arm(arm_b_result, oracle)

        # Foreign-only (REQ-MR-004): a contaminated council record fails closed for
        # this subject — never emitted as a valid (foreign_only_ok true) result.
        if not scored_b["foreign_only_ok"]:
            raise RunError(
                f"Arm-B for {task_id} carries a Claude/anthropic id (foreign-only violated); "
                "failing closed for that subject")

        survivors += 1
        records.append(_record_for_output(scored_a))
        records.append(_record_for_output(scored_b))
        arm_a_catch.append(scored_a["review_catch_rate"])
        arm_b_catch.append(scored_b["review_catch_rate"])
        arm_a_crywolf.append(scored_a["review_cry_wolf_rate"])
        arm_b_crywolf.append(scored_b["review_cry_wolf_rate"])

        # Emit ONLY when an explicit --out is given (bench isolation: never append to
        # the in-tree metrics/runs.jsonl from the offline suite or a no-out run).
        if args.out is not None:
            emit_arm_record(scored_a, corpus_id=corpus_id, out_path=args.out)
            emit_arm_record(scored_b, corpus_id=corpus_id, out_path=args.out)

    # Catch delta = Arm-B mean catch − Arm-A mean catch (cry-wolf delta similarly), over
    # the surviving subjects. Feeds the MDE half of the n=2 rubric.
    catch_delta = _mean(arm_b_catch) - _mean(arm_a_catch)
    cry_wolf_delta = _mean(arm_b_crywolf) - _mean(arm_a_crywolf)
    outcome = classify_outcome(
        survivors, min_survivors,
        catch_delta=catch_delta, cry_wolf_delta=cry_wolf_delta, mde=mde)

    # The call counter proves 0 transport calls on every offline path.
    _write_counter(args.inject_call_counter, calls["n"])

    return {
        "outcome": outcome,
        "records": records,
        "attrition": attrition,
        "survivors": survivors,
        "min_survivors": min_survivors,
        "calls_attempted": calls["n"],
        "arm_a_subject_protocol": STRUCTURED_FLAG_PROTOCOL,
        "arm_b_subject_protocol": STRUCTURED_FLAG_PROTOCOL,
    }


def _write_counter(path: str | None, count: int) -> None:
    """Write the transport-invocation count (proves 0 calls offline)."""
    if not path:
        return
    try:
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(str(count))
    except OSError:
        pass


# ---------------------------------------------------------------------------
# CLI.
# ---------------------------------------------------------------------------
def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Council measurement-run orchestrator (Slice 3b).")
    sub = parser.add_subparsers(dest="command", required=True)

    p_run = sub.add_parser("run", help="Run the measurement over the corpus (both arms).")
    p_run.add_argument("--corpus", required=True)
    p_run.add_argument("--preset", default="A")
    p_run.add_argument("--claude-model", required=True)
    p_run.add_argument("--pre-registration", default=None)
    p_run.add_argument("--max-calls", type=int, default=None)
    p_run.add_argument("--live", action="store_true")
    p_run.add_argument("--score", action="store_true")
    p_run.add_argument("--json", action="store_true")
    p_run.add_argument("--out", default=None)
    p_run.add_argument("--inject-arm-a", default=None)
    p_run.add_argument("--inject-arm-b", default=None)
    p_run.add_argument("--inject-call-counter", default=None)

    p_proto = sub.add_parser("protocol-instruction",
                             help="Emit the structured-flag-protocol string (both arms).")
    p_proto.add_argument("--json", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    env = dict(os.environ)
    if args.command == "protocol-instruction":
        print(json.dumps({"protocol": STRUCTURED_FLAG_PROTOCOL}, sort_keys=True))
        return 0
    if args.command == "run":
        try:
            state = run(args, env)
        except RunError as exc:
            # Still write the counter (0) so the gate-off / refuse paths prove 0 calls.
            _write_counter(getattr(args, "inject_call_counter", None), 0)
            print(json.dumps({"error": str(exc)}, sort_keys=True), file=sys.stderr)
            return 1
        print(json.dumps(state, sort_keys=True, indent=2))
        return 0
    return 2  # pragma: no cover - argparse enforces a valid subcommand


if __name__ == "__main__":
    raise SystemExit(main())
