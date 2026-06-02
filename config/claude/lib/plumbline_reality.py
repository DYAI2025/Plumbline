#!/usr/bin/env python3
"""Plumbline Runtime Integrity Layer reality-evidence gate."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

RANKS = {
    "fake-only": 0,
    # Workflow-documented Reality Ledger classes. Keep *-fake evidence
    # below the legacy integration gate used by /agileteam Gate C/D.
    "unit-fake": 0,
    "integration-fake": 1,
    "real-boundary-smoke": 3,
    "production-verified": 4,
    # Backward-compatible class names accepted by earlier PRIL fixtures/docs.
    "unit-only": 1,
    "integration": 2,
    "browser-live": 3,
    "production-observed": 4,
    "user-confirmed": 5,
}
REQUIRED_FIELDS = ("feature", "requirement_id", "evidence_class", "evidence_ref", "verified_by")
FORBIDDEN_TOKENS = ("fake-only", "mock-only", "placeholder", "unverified")

EXIT_PASS = 0
EXIT_MISSING = 2
EXIT_INSUFFICIENT = 3
EXIT_MALFORMED = 4


def _rel(path: Path, repo: Path) -> str:
    try:
        return str(path.relative_to(repo))
    except ValueError:
        return str(path)


def _load_jsonl(path: Path, repo: Path) -> tuple[int, list[dict[str, Any]]]:
    records: list[dict[str, Any]] = []
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except UnicodeDecodeError:
        print(f"ERROR: malformed evidence ledger is not UTF-8 text: {_rel(path, repo)}", file=sys.stderr)
        return EXIT_MALFORMED, records

    if not lines:
        print(f"ERROR: missing evidence entries in {_rel(path, repo)}", file=sys.stderr)
        return EXIT_MISSING, records

    for idx, line in enumerate(lines, start=1):
        if not line.strip():
            continue
        lowered = line.lower()
        for token in FORBIDDEN_TOKENS:
            if token in lowered:
                print(
                    f"ERROR: forbidden non-reality evidence token '{token}' in "
                    f"{_rel(path, repo)} line {idx}",
                    file=sys.stderr,
                )
                return EXIT_INSUFFICIENT, records
        try:
            data = json.loads(line)
        except json.JSONDecodeError as exc:
            print(f"ERROR: invalid JSONL in {_rel(path, repo)} line {idx}: {exc.msg}", file=sys.stderr)
            return EXIT_MALFORMED, records
        if not isinstance(data, dict):
            print(f"ERROR: malformed evidence line {idx}: expected JSON object", file=sys.stderr)
            return EXIT_MALFORMED, records
        missing = [field for field in REQUIRED_FIELDS if not str(data.get(field, "")).strip()]
        if missing:
            print(f"ERROR: evidence line {idx} missing required fields: {', '.join(missing)}", file=sys.stderr)
            return EXIT_MALFORMED, records
        evidence_class = data["evidence_class"]
        if evidence_class not in RANKS:
            print(f"ERROR: evidence line {idx} has unknown evidence_class: {evidence_class}", file=sys.stderr)
            return EXIT_MALFORMED, records
        records.append(data)
    if not records:
        print(f"ERROR: missing evidence entries in {_rel(path, repo)}", file=sys.stderr)
        return EXIT_MISSING, records
    return EXIT_PASS, records


def validate_reality(repo: Path, feature: str, min_evidence: str) -> int:
    if min_evidence not in RANKS:
        print(f"ERROR: unknown --min-evidence '{min_evidence}'", file=sys.stderr)
        return EXIT_MALFORMED
    if not feature or "/" in feature or "\\" in feature or feature in {".", ".."}:
        print(f"ERROR: malformed feature slug: {feature!r}", file=sys.stderr)
        return EXIT_MALFORMED

    ledger = repo / "docs" / "reality" / f"{feature}.evidence.jsonl"
    if not ledger.exists():
        print(f"ERROR: missing reality evidence ledger: {_rel(ledger, repo)}", file=sys.stderr)
        return EXIT_MISSING
    if not ledger.is_file():
        print(f"ERROR: malformed reality evidence ledger is not a file: {_rel(ledger, repo)}", file=sys.stderr)
        return EXIT_MALFORMED

    status, records = _load_jsonl(ledger, repo)
    if status != EXIT_PASS:
        return status

    relevant = [record for record in records if record.get("feature") == feature]
    if not relevant:
        print(f"ERROR: no evidence records found for feature '{feature}' in {_rel(ledger, repo)}", file=sys.stderr)
        return EXIT_MISSING

    floor = RANKS[min_evidence]
    passing = [record for record in relevant if RANKS[str(record["evidence_class"])] >= floor]
    if not passing:
        classes = ", ".join(str(record["evidence_class"]) for record in relevant)
        print(
            f"ERROR: evidence for feature '{feature}' is below minimum '{min_evidence}'; "
            f"found: {classes}",
            file=sys.stderr,
        )
        return EXIT_INSUFFICIENT

    print(
        f"PRIL reality check passed for feature '{feature}' "
        f"with minimum evidence '{min_evidence}'"
    )
    return EXIT_PASS


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Validate reality evidence for a feature.")
    parser.add_argument("--repo", required=True, help="Repository root to inspect")
    parser.add_argument("--feature", required=True, help="Feature slug")
    parser.add_argument("--min-evidence", default="integration", choices=tuple(RANKS), help="Minimum evidence class")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return validate_reality(Path(args.repo).resolve(), args.feature, args.min_evidence)


if __name__ == "__main__":
    raise SystemExit(main())
