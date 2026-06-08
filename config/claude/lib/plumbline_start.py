#!/usr/bin/env python3
"""Deterministic Plumbline AgileTeam start-state classifier.

This module is intentionally local and API-free. It proves contract behavior for
start governance; it does not claim live Claude session enforcement.
"""
from __future__ import annotations

import argparse
import json
from typing import Any


def classify_start_state(
    has_prd: bool,
    has_confirmed_vision: bool,
    has_confirmed_canvas: bool = False,
    has_traceability: bool = False,
) -> dict[str, Any]:
    """Classify whether AgileTeam may proceed past intake.

    The critical Sprint 2 invariant is fail-closed behavior for PRD-present plus
    missing confirmed Product Vision.
    """
    if has_prd and not has_confirmed_vision:
        return {
            "phase": "VISION_INTAKE",
            "gate": "VISION_MISSING",
            "planning_allowed": False,
            "coding_allowed": False,
            "missing": ["confirmed Product Vision Canvas"],
            "next_allowed_step": "Run Vision Extraction and request explicit user confirmation.",
        }

    missing: list[str] = []
    if not has_prd:
        missing.append("PRD")
    if not has_confirmed_canvas:
        missing.append("confirmed Product Canvas")
    if not has_confirmed_vision:
        missing.append("confirmed Product Vision Canvas")
    if not has_traceability:
        missing.append("traceability matrix")

    if missing:
        return {
            "phase": "INTAKE",
            "gate": "START_ARTIFACTS_MISSING",
            "planning_allowed": False,
            "coding_allowed": False,
            "missing": missing,
            "next_allowed_step": "Complete missing confirmed intake artifacts before planning or coding.",
        }

    return {
        "phase": "PLANNING_READY",
        "gate": "READY_FOR_PLANNING",
        "planning_allowed": True,
        "coding_allowed": False,
        "missing": [],
        "next_allowed_step": "Start planning; coding remains blocked until planning gates pass.",
    }


def _yes_no(value: bool) -> str:
    return "YES" if value else "NO"


def render_status_panel(state: dict[str, Any]) -> str:
    """Render a deterministic terminal panel for shell contract tests."""
    missing = state.get("missing") or []
    lines = [
        "PLUMBLINE START STATUS",
        f"Phase: {state['phase']}",
        f"Gate: {state['gate']}",
        f"Planning allowed: {_yes_no(bool(state['planning_allowed']))}",
        f"Coding allowed: {_yes_no(bool(state['coding_allowed']))}",
        "Missing:",
    ]
    if missing:
        lines.extend(f"- {item}" for item in missing)
    else:
        lines.append("- none")
    lines.extend([
        "Next allowed step:",
        f"- {state['next_allowed_step']}",
    ])
    return "\n".join(lines)


def _parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Classify Plumbline AgileTeam start governance state.")
    parser.add_argument("--prd-present", action="store_true", help="PRD artifact or PRD-equivalent user input is present.")
    vision = parser.add_mutually_exclusive_group()
    vision.add_argument("--vision-confirmed", action="store_true", help="Product Vision is explicitly user-confirmed.")
    vision.add_argument("--vision-missing", action="store_true", help="Product Vision is missing or unconfirmed.")
    parser.add_argument("--canvas-confirmed", action="store_true", help="Product Canvas is explicitly user-confirmed.")
    parser.add_argument("--traceability-present", action="store_true", help="Traceability matrix exists.")
    parser.add_argument("--json", action="store_true", help="Emit machine-readable JSON instead of the status panel.")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    has_confirmed_vision = bool(args.vision_confirmed and not args.vision_missing)
    state = classify_start_state(
        has_prd=args.prd_present,
        has_confirmed_vision=has_confirmed_vision,
        has_confirmed_canvas=args.canvas_confirmed,
        has_traceability=args.traceability_present,
    )
    if args.json:
        print(json.dumps(state, sort_keys=True))
    else:
        print(render_status_panel(state))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
