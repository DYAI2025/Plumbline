#!/usr/bin/env python3
"""Plumbline Runtime Integrity Layer context gate."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

CONFIRMATION_MARKERS = (
    "Status: user-confirmed",
    "Confirmed by user: yes",
    "Status: confirmed",
)

EXIT_PASS = 0
EXIT_MISSING = 2
EXIT_UNCONFIRMED = 3
EXIT_MALFORMED = 4


def required_artifacts(repo: Path, feature: str) -> list[Path]:
    return [
        repo / "docs" / "canvas" / f"{feature}.canvas.md",
        repo / "docs" / "prd" / f"{feature}.prd.md",
        repo / "docs" / "vision" / f"{feature}.vision.md",
        repo / "docs" / "traceability.md",
    ]


def validate_context(repo: Path, feature: str) -> int:
    if not feature or "/" in feature or "\\" in feature or feature in {".", ".."}:
        print(f"ERROR: malformed feature slug: {feature!r}", file=sys.stderr)
        return EXIT_MALFORMED

    for artifact in required_artifacts(repo, feature):
        rel = artifact.relative_to(repo) if artifact.is_relative_to(repo) else artifact
        if not artifact.exists():
            print(f"ERROR: missing required product-context artifact: {rel}", file=sys.stderr)
            return EXIT_MISSING
        if not artifact.is_file():
            print(f"ERROR: malformed artifact is not a file: {rel}", file=sys.stderr)
            return EXIT_MALFORMED
        try:
            text = artifact.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            print(f"ERROR: malformed artifact is not UTF-8 text: {rel}", file=sys.stderr)
            return EXIT_MALFORMED
        if not text.strip():
            print(f"ERROR: malformed artifact is empty: {rel}", file=sys.stderr)
            return EXIT_MALFORMED
        if not any(marker in text for marker in CONFIRMATION_MARKERS):
            markers = ", ".join(CONFIRMATION_MARKERS)
            print(
                f"ERROR: unconfirmed product-context artifact: {rel}; "
                f"expected one of: {markers}",
                file=sys.stderr,
            )
            return EXIT_UNCONFIRMED

    print(f"PRIL context check passed for feature '{feature}'")
    return EXIT_PASS


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Validate confirmed product context for a feature.")
    parser.add_argument("--repo", required=True, help="Repository root to inspect")
    parser.add_argument("--feature", required=True, help="Feature slug")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return validate_context(Path(args.repo).resolve(), args.feature)


if __name__ == "__main__":
    raise SystemExit(main())
