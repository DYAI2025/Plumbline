#!/usr/bin/env python3
"""Plumbline plan-vs-scope drift guard (PLUM-12).

The pilot's failure mode: a change was authorized in conversation and named in the
implementation plan, but never reached the machine-readable Allowed change scope.
Every pre-coding gate passed; the contradiction only surfaced when the fail-closed
Stop hook blocked mid-build, after the work was already done.

This module closes that gap BEFORE coding by comparing three artifacts against the
one canonical source:

    docs/scope/<feature>.scope.json   canonical (product + governance classes)
        ^                       ^
        |                       |
    the plan's touched files    the canvas' documented scope

Exit codes match the rest of PRIL: 0 pass, 2 missing input, 3 drift/violation,
4 malformed input.
"""
from __future__ import annotations

import argparse
import re
import sys
from datetime import datetime
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from plumbline_scope import (  # noqa: E402  (path shim above must run first)
    EXIT_MALFORMED,
    EXIT_MISSING,
    EXIT_PASS,
    EXIT_VIOLATION,
    _matches,
    _patterns_from_canvas,
    _rel,
    load_scope_model,
    manifest_path,
)

# A fenced block that states, machine-readably, which files the plan will touch.
# Declared beats inferred: prose is a heuristic, this is a contract.
TOUCHES_FENCE = "plumbline-touches"

# Governance artifacts. Used only to REPORT a likely misclassification -- never to
# block -- because a repo is free to organise its own governance surface.
GOVERNANCE_HINTS = (
    "docs/canvas/",
    "docs/prd/",
    "docs/vision/",
    "docs/plans/",
    "docs/reality/",
    "docs/trace/",
    "docs/scope/",
    "CLAUDE.md",
)

PROVENANCE_FIELDS = ("origin", "decided_by", "decided_at", "reason")

# A backticked span is treated as a path candidate only when it looks like one:
# no whitespace, and either a directory separator or a file extension.
_PATHISH = re.compile(r"^[A-Za-z0-9._\-*?\[\]{}/@+]+$")


def _valid_declared_path(token: str) -> bool:
    """Validation for a DECLARED touches entry: permissive but unambiguous.

    A declared block is a contract, so it may legitimately name `Makefile`,
    `.gitignore` or a glob. Only genuinely unusable tokens are refused: absolute
    paths, traversal, flags, URLs and anything with whitespace or shell syntax.
    """
    if not token or not _PATHISH.match(token):
        return False
    if token.startswith(("-", "/")):
        return False
    if "://" in token:
        return False
    return ".." not in Path(token).parts


def _looks_like_path(token: str) -> bool:
    """Stricter filter for HEURISTIC extraction from prose.

    Prose backticks also carry commands, flags and identifiers, so an inferred
    candidate must actually look like a file: a directory separator, a plausible
    extension, or a leading-dot config name.
    """
    if not _valid_declared_path(token):
        return False
    if "/" in token:
        return True
    if token.startswith(".") and len(token) > 1:
        return True  # .gitignore, .env.example
    stem, _, ext = token.rpartition(".")
    return bool(stem) and 1 <= len(ext) <= 6 and ext.isalnum()


def extract_touches(plan_text: str) -> tuple[list[str], str, str | None]:
    """Return ``(paths, mode, error)`` for one plan document.

    ``mode`` is ``declared`` when the plan carries a ``plumbline-touches`` fenced
    block (authoritative, exact) and ``heuristic`` when the paths were inferred
    from backticked spans in prose. The mode is always reported, so an operator can
    tell an inferred read-only mention from a declared write target.
    """
    lines = plan_text.splitlines()
    declared: list[str] = []
    in_block = False
    saw_block = False
    for line in lines:
        stripped = line.strip()
        if stripped.startswith("```") or stripped.startswith("~~~"):
            info = stripped.lstrip("`~").strip().lower()
            if in_block:
                in_block = False
            elif info == TOUCHES_FENCE:
                in_block = True
                saw_block = True
            continue
        if in_block and stripped and not stripped.startswith("#"):
            declared.append(stripped.strip("` "))
    if saw_block:
        if not declared:
            return [], "declared", (
                f"the plan declares a '{TOUCHES_FENCE}' block but it is EMPTY; "
                "an empty declaration is not 'touches nothing' -- list the files "
                "the plan will change, or remove the block to fall back to "
                "heuristic extraction"
            )
        bad = [p for p in declared if not _valid_declared_path(p)]
        if bad:
            return [], "declared", (
                f"the '{TOUCHES_FENCE}' block entry {bad[0]!r} is not a "
                "repo-relative path or glob"
            )
        return sorted(set(declared)), "declared", None

    found: list[str] = []
    for span in re.findall(r"`([^`\n]+)`", plan_text):
        token = span.strip()
        if _looks_like_path(token):
            found.append(token)
    return sorted(set(found)), "heuristic", None


def _covered_by(path: str, patterns: list[str]) -> bool:
    return any(_matches(path, pattern) for pattern in patterns)


def _check_provenance(model: dict, manifest: Path) -> int:
    """Every scope entry must carry origin, decider, timestamp and reason."""
    records = model.get("provenance")
    entries = list(model.get("product", [])) + list(model.get("governance", []))
    if records is None:
        print(
            f"ERROR: {manifest} declares no 'provenance', so no scope entry can be "
            "attributed. Unattributed entr(ies): " + ", ".join(entries),
            file=sys.stderr,
        )
        return EXIT_MALFORMED

    attributed: set[str] = set()
    for index, record in enumerate(records, start=1):
        if not isinstance(record, dict):
            print(
                f"ERROR: {manifest} provenance record #{index} is not an object",
                file=sys.stderr,
            )
            return EXIT_MALFORMED
        unknown = sorted(set(record) - set(PROVENANCE_FIELDS) - {"paths"})
        if unknown:
            print(
                f"ERROR: {manifest} provenance record #{index} has unknown "
                f"field(s) {', '.join(repr(k) for k in unknown)}",
                file=sys.stderr,
            )
            return EXIT_MALFORMED
        for field in PROVENANCE_FIELDS:
            value = record.get(field)
            if not isinstance(value, str) or not value.strip():
                print(
                    f"ERROR: {manifest} provenance record #{index} is missing a "
                    f"non-empty {field!r}; a scope decision without its "
                    "origin, decider, timestamp and reason is not auditable",
                    file=sys.stderr,
                )
                return EXIT_MALFORMED
        stamp = record["decided_at"].strip()
        try:
            datetime.fromisoformat(stamp.replace("Z", "+00:00"))
        except ValueError:
            print(
                f"ERROR: {manifest} provenance record #{index} has an unparseable "
                f"'decided_at' {stamp!r}; use an ISO-8601 date or timestamp",
                file=sys.stderr,
            )
            return EXIT_MALFORMED
        paths = record.get("paths")
        if not isinstance(paths, list) or not paths:
            print(
                f"ERROR: {manifest} provenance record #{index} must list the "
                "'paths' it decided",
                file=sys.stderr,
            )
            return EXIT_MALFORMED
        for path in paths:
            if isinstance(path, str):
                attributed.add(path.strip())

    orphans = [entry for entry in entries if entry not in attributed]
    if orphans:
        print(
            f"ERROR: {manifest} scope entr(ies) without a provenance record: "
            + ", ".join(orphans)
            + ". Record who authorized each path, when, from where and why.",
            file=sys.stderr,
        )
        return EXIT_MALFORMED
    print(f"provenance: {len(records)} record(s) cover {len(entries)} scope entr(ies)")
    return EXIT_PASS


def check_plan(
    repo: Path,
    feature: str,
    plan: Path,
    canvas: Path | None = None,
    require_provenance: bool = False,
) -> int:
    status, model, source = load_scope_model(repo, feature)
    if status != EXIT_PASS:
        return status

    product = list(model.get("product", []))
    governance = list(model.get("governance", []))
    effective = product + governance
    manifest = model.get("manifest") or manifest_path(repo, feature)

    if not plan.exists():
        print(
            f"ERROR: missing implementation plan: {_rel(plan, repo)}; "
            "plan-vs-scope cannot be proven without it",
            file=sys.stderr,
        )
        return EXIT_MISSING
    try:
        plan_text = plan.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        print(f"ERROR: plan is not UTF-8 text: {_rel(plan, repo)}", file=sys.stderr)
        return EXIT_MALFORMED

    touches, mode, error = extract_touches(plan_text)
    if error:
        print(f"ERROR: {_rel(plan, repo)}: {error}", file=sys.stderr)
        return EXIT_MALFORMED

    print(f"plan={_rel(plan, repo)} mode={mode} scope-source={source}")
    if mode == "heuristic":
        print(
            "NOTE: mode=heuristic — the plan declares no "
            f"'{TOUCHES_FENCE}' block, so touched files were inferred from "
            "backticked paths and may include read-only references. Declare the "
            "block to make this check exact."
        )
    if not model.get("classified", False):
        print(
            "NOTE: the effective scope comes from a legacy source that cannot "
            "distinguish product from governance paths; every pattern is reported "
            f"as 'product'. The canonical source is {_rel(manifest, repo)}."
        )

    exit_code = EXIT_PASS

    unauthorized = [path for path in touches if not _covered_by(path, effective)]
    if unauthorized:
        print(
            "ERROR: the plan touches path(s) the confirmed scope does not "
            "authorize: " + ", ".join(f"unauthorized: {p}" for p in unauthorized)
            + f". Add them to {_rel(manifest, repo)} (with provenance) or remove "
            "them from the plan — do not discover this at the Stop gate.",
            file=sys.stderr,
        )
        exit_code = EXIT_VIOLATION
    else:
        for path in touches:
            klass = "product" if _covered_by(path, product) else "governance"
            print(f"covered: {path} class={klass}")
        if not touches:
            print("covered: (the plan declares no touched files)")

    # The canvas is validated AGAINST the manifest, never the reverse: a canvas
    # claiming more than the manifest is a contradiction, because the canvas is
    # documentation and the manifest is the executable decision.
    if canvas is None:
        canvas = repo / "docs" / "canvas" / f"{feature}.canvas.md"
    if canvas.exists() and model.get("classified", False):
        canvas_status, canvas_patterns, _ignored = _patterns_from_canvas(canvas)
        if canvas_status == EXIT_PASS:
            extra = [p for p in canvas_patterns if p not in effective]
            if extra:
                print(
                    f"ERROR: {_rel(canvas, repo)} declares scope pattern(s) the "
                    "canonical manifest does not authorize: " + ", ".join(extra)
                    + f". Reconcile the canvas with {_rel(manifest, repo)} "
                    "(the manifest decides).",
                    file=sys.stderr,
                )
                exit_code = EXIT_VIOLATION
            documented_only = [p for p in effective if p not in canvas_patterns]
            if documented_only:
                print(
                    f"NOTE: {_rel(manifest, repo)} authorizes pattern(s) the canvas "
                    "does not mention (the canvas is documentation, so this is not "
                    "a contradiction): " + ", ".join(documented_only)
                )

    # Visible, non-blocking classification report: a governance-looking path sitting
    # in the product list is almost always an authoring slip.
    misclassified = [
        p for p in product if any(p.startswith(hint) or p == hint for hint in GOVERNANCE_HINTS)
    ]
    if misclassified and model.get("classified", False):
        print(
            "NOTE: governance-looking path(s) declared in 'allowed_change_scope' "
            "rather than 'governance_paths': " + ", ".join(misclassified)
        )

    if require_provenance:
        prov = _check_provenance(model, manifest)
        if prov != EXIT_PASS:
            return prov

    if exit_code == EXIT_PASS:
        print(
            f"PRIL plan/scope check passed for feature '{feature}' "
            f"({len(touches)} planned path(s), {len(product)} product + "
            f"{len(governance)} governance pattern(s))"
        )
    return exit_code


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Validate an implementation plan (and the canvas) against the "
        "canonical scope manifest before coding starts.",
    )
    parser.add_argument("--repo", required=True, help="Repository root to inspect")
    parser.add_argument("--feature", required=True, help="Feature slug")
    parser.add_argument("--plan", required=True, help="Implementation plan markdown")
    parser.add_argument(
        "--canvas",
        help="Canvas to validate against the manifest "
        "(default: docs/canvas/<feature>.canvas.md when present)",
    )
    parser.add_argument(
        "--require-provenance",
        action="store_true",
        help="Also require that every scope entry carries origin, decided_by, "
        "decided_at and reason",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return check_plan(
        Path(args.repo).resolve(),
        args.feature,
        Path(args.plan),
        Path(args.canvas) if args.canvas else None,
        require_provenance=args.require_provenance,
    )


if __name__ == "__main__":
    raise SystemExit(main())
