#!/usr/bin/env python3
"""arm_a_review_runner.py — the Arm-A (Claude-only) review RUNNER (Slice 3a).

A SEPARATE entrypoint (NOT an edit to the read-only council instrument
config/claude/lib/deepseek_review.py). It builds a Claude-only review prompt over a
corpus task's diff in the STRUCTURED FLAG PROTOCOL and parses a model RESPONSE into the
exact flag-set schema council_review_scorer.py consumes — all OFFLINE (0 credits, 0
network) via an injected response, mirroring the deepseek live-gate seam WITHOUT
importing-and-mutating the instrument.

Reality Ledger / house rules:
  * The live transport is GATED OFF by default: armed ONLY when --live AND
    COUNCIL_INFERENCE_LIVE=1 (mirrors deepseek_review._make_transport). Offline (no
    gate) makes ZERO network calls — the call counter reads 0. (REQ-DM-3a-006)
  * The injected-response path makes ZERO transport calls (counter == 0). The runner
    replicates the seam pattern; it does NOT import-and-mutate the instrument.
  * A malformed / no-flags response classifies to an EMPTY flag-set — NEVER a
    fabricated flag (the looks-measured-but-isn't guard).
  * The disclosed Arm-A model scope is present in the flag-set output (scope visible).
  * No secret in output: this runner holds no key on the offline path; a real key (3b)
    would live header-only inside a real transport, never in this module's output.

The structured flag protocol: the reviewer is instructed to emit each finding as a
machine-parseable {file, line, description}, so the scorer's deterministic
location-overlap matcher (OQ-DM-7) can consume it.
"""
from __future__ import annotations

import argparse
import json
import os
import re
from typing import Any

ARM = "claude-only"

# Classified statuses (never a fabricated flag).
CODE_OK = "ARM_A_OK"
CODE_LIVE_DISABLED = "ARM_A_LIVE_DISABLED"
CODE_NEEDS_INJECTION = "ARM_A_NEEDS_INJECTION"
CODE_FLAG_PROTOCOL_MALFORMED = "ARM_A_FLAG_PROTOCOL_MALFORMED"

# Fenced-JSON extractor: a model may wrap the protocol JSON in a ```json fence.
_FENCE_RE = re.compile(r"```(?:json)?\s*(\{.*?\})\s*```", re.DOTALL)


# ---------------------------------------------------------------------------
# Diff loading.
# ---------------------------------------------------------------------------
def load_diff(task_dir: str) -> str:
    """Read the diff under review from a corpus task dir.

    Accepts either a plain ``diff.patch`` (the test fixture) or a ``diffs/<id>.md``
    style; for a task dir the load-bearing file is the diff text. Reads the first
    matching candidate; missing → empty string (classified, never fabricated).
    """
    candidates = ["diff.patch", "diff.md", "diff.txt"]
    for name in candidates:
        path = os.path.join(task_dir, name)
        if os.path.isfile(path):
            with open(path, encoding="utf-8") as handle:
                return handle.read()
    # Fall back: a single *.patch / *.md file in the dir.
    if os.path.isdir(task_dir):
        for name in sorted(os.listdir(task_dir)):
            if name.endswith((".patch", ".md", ".txt")):
                with open(os.path.join(task_dir, name), encoding="utf-8") as handle:
                    return handle.read()
    return ""


# ---------------------------------------------------------------------------
# Structured-flag-protocol prompt (REQ-DM-3a-002, OQ-DM-7).
# ---------------------------------------------------------------------------
def build_review_prompt(diff_text: str, model_scope: str) -> str:
    """Build the Claude-only review prompt in the STRUCTURED FLAG PROTOCOL.

    The prompt instructs the reviewer to emit each finding as a machine-parseable
    {file, line, description} (so the scorer's deterministic matcher can consume it),
    embeds the diff under review, and discloses the Arm-A model scope.
    """
    return (
        "You are an independent code reviewer (Arm A, Claude-only review arm).\n"
        f"Model scope (disclosed): {model_scope}\n\n"
        "Review the diff under review below and report every genuine defect you find.\n"
        "Emit your findings ONLY in the STRUCTURED FLAG PROTOCOL: a single JSON object\n"
        '{\"flags\": [ ... ]} where each finding is an object with EXACTLY these keys:\n'
        '  - \"file\": the file path the finding is in (string)\n'
        '  - \"line\": the line number the finding is at (integer)\n'
        '  - \"description\": a short description of the defect (string)\n'
        "Flag ONLY real defects; do NOT invent findings. If there are no defects, emit\n"
        '{\"flags\": []}. Do not flag correct, defect-free code.\n\n'
        "----- DIFF UNDER REVIEW -----\n"
        f"{diff_text}\n"
        "----- END DIFF -----\n"
    )


def build_messages(diff_text: str, model_scope: str) -> list[dict[str, str]]:
    """Build [system, user] messages for the review (the real call shape, 3b)."""
    return [
        {"role": "system", "content": build_review_prompt(diff_text, model_scope)},
        {"role": "user", "content": "Review the diff and emit the structured flag set."},
    ]


# ---------------------------------------------------------------------------
# Response -> flag-set parsing (REQ-DM-3a-002) — never fabricate.
# ---------------------------------------------------------------------------
def parse_flag_set(response_text: str) -> tuple[list[dict[str, Any]], str]:
    """Parse a model response into a list of {file, line, description} flags.

    Tolerant of a ```json fenced block. A malformed or non-protocol response yields an
    EMPTY flag-set with a classified status — NEVER a fabricated flag. Returns
    (flags, status).
    """
    text = response_text.strip()
    if not text:
        return [], CODE_NEEDS_INJECTION

    obj = _try_load_object(text)
    if obj is None:
        match = _FENCE_RE.search(text)
        if match:
            obj = _try_load_object(match.group(1))
    if obj is None or not isinstance(obj, dict):
        return [], CODE_FLAG_PROTOCOL_MALFORMED

    raw_flags = obj.get("flags")
    if not isinstance(raw_flags, list):
        return [], CODE_FLAG_PROTOCOL_MALFORMED

    flags: list[dict[str, Any]] = []
    for item in raw_flags:
        if not isinstance(item, dict):
            continue
        file_val = item.get("file")
        line_val = item.get("line")
        desc_val = item.get("description", "")
        if file_val is None or line_val is None:
            # A flag without a locatable file+line cannot be scored — drop it (never
            # fabricate a location).
            continue
        try:
            line_int = int(line_val)
        except (TypeError, ValueError):
            continue
        flags.append({
            "file": str(file_val),
            "line": line_int,
            "description": str(desc_val),
        })
    return flags, CODE_OK


def _try_load_object(text: str) -> Any:
    try:
        return json.loads(text)
    except (json.JSONDecodeError, TypeError):
        return None


# ---------------------------------------------------------------------------
# Injected-response resolution (offline seam, mirrors deepseek --inject-response).
# ---------------------------------------------------------------------------
def _resolve_injected(inject_response: str | None) -> str | None:
    """Resolve --inject-response: ``@path`` reads the file, else the literal text."""
    if inject_response is None:
        return None
    if inject_response.startswith("@"):
        path = inject_response[1:]
        try:
            with open(path, encoding="utf-8") as handle:
                return handle.read()
        except OSError:
            return ""
    return inject_response


def _write_counter(path: str | None, count: int) -> None:
    """Mirror deepseek_review._write_counter: write the transport call count."""
    if not path:
        return
    try:
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(str(count))
    except OSError:
        pass


def _live_armed(args: argparse.Namespace, env: dict[str, str]) -> bool:
    """Arm the real transport ONLY when --live AND COUNCIL_INFERENCE_LIVE=1.

    Replicates the deepseek_review._make_transport gate WITHOUT importing-and-mutating
    the instrument. Offline (no gate) => not armed => 0 calls.
    """
    return bool(getattr(args, "live", False)) and env.get("COUNCIL_INFERENCE_LIVE") == "1"


# ---------------------------------------------------------------------------
# CLI commands.
# ---------------------------------------------------------------------------
def _cmd_build_prompt(args: argparse.Namespace) -> dict[str, Any]:
    diff_text = load_diff(args.task)
    prompt = build_review_prompt(diff_text, args.model_scope)
    return {
        "arm": ARM,
        "model_scope": args.model_scope,
        "task": os.path.basename(os.path.normpath(args.task)),
        "prompt": prompt,
    }


def _cmd_review(args: argparse.Namespace, env: dict[str, str]) -> dict[str, Any]:
    diff_text = load_diff(args.task)
    task_id = os.path.basename(os.path.normpath(args.task))
    call_count = {"n": 0}

    injected = _resolve_injected(args.inject_response)

    if injected is not None:
        # Offline injected path: 0 transport calls.
        flags, status = parse_flag_set(injected)
        _write_counter(args.inject_call_counter, call_count["n"])
        return {
            "code": status,
            "status": status,
            "arm": ARM,
            "model_scope": args.model_scope,
            "task": task_id,
            "flags": flags,
        }

    # No injected response. The live path is gated; without the gate it fires ZERO
    # calls and classifies (never fabricates a live result).
    if _live_armed(args, env):
        # A real transport WOULD be invoked here in 3b (key header-only, fixed
        # OpenRouter host → no SSRF). 3a never crosses the boundary; the real call is
        # deferred. Classify and keep the counter at 0 (no transport fired in 3a).
        status = CODE_NEEDS_INJECTION
    else:
        status = CODE_LIVE_DISABLED

    _write_counter(args.inject_call_counter, call_count["n"])
    return {
        "code": status,
        "status": status,
        "arm": ARM,
        "model_scope": args.model_scope,
        "task": task_id,
        "flags": [],
    }


def _emit(state: dict[str, Any]) -> None:
    print(json.dumps(state, sort_keys=True, indent=2))


def _parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--json", action="store_true", help="Emit machine-readable JSON.")
    parser = argparse.ArgumentParser(
        description="Arm-A (Claude-only) review runner.", parents=[common])
    sub = parser.add_subparsers(dest="command", required=True)

    p_bp = sub.add_parser("build-prompt", help="Disclose the review prompt that WOULD be sent.",
                          parents=[common])
    p_bp.add_argument("--task", required=True)
    p_bp.add_argument("--model-scope", required=True)

    p_rv = sub.add_parser("review", help="Produce the reviewer flag-set (offline injected).",
                          parents=[common])
    p_rv.add_argument("--task", required=True)
    p_rv.add_argument("--model-scope", required=True)
    p_rv.add_argument("--inject-response", default=None)
    p_rv.add_argument("--inject-call-counter", default=None)
    p_rv.add_argument("--live", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    env = dict(os.environ)
    if args.command == "build-prompt":
        state = _cmd_build_prompt(args)
    elif args.command == "review":
        state = _cmd_review(args, env)
    else:  # pragma: no cover - argparse enforces a valid subcommand
        return 2
    _emit(state)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
