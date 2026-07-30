#!/usr/bin/env python3
"""Atomically apply a confirmed decision to a canonical scope manifest."""
from __future__ import annotations

import argparse
import json
import os
import tempfile
from pathlib import Path

from plumbline_scope import (
    EXIT_MALFORMED,
    EXIT_MISSING,
    EXIT_PASS,
    _scope_digest,
    load_scope_manifest,
    validate_manifest_artifacts,
    validate_manifest_data,
)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Atomically update a confirmed, provenance-bound scope decision."
    )
    parser.add_argument("--repo", required=True)
    parser.add_argument("--feature", required=True)
    parser.add_argument("--product-path", action="append", default=[])
    parser.add_argument("--governance-path", action="append", default=[])
    parser.add_argument("--canvas")
    parser.add_argument("--plan")
    parser.add_argument("--origin", required=True)
    parser.add_argument("--decision-maker", required=True)
    parser.add_argument("--decided-at", required=True)
    parser.add_argument("--rationale", required=True)
    parser.add_argument(
        "--confirmed",
        action="store_true",
        help="Required acknowledgement that the recorded decision was explicitly confirmed",
    )
    return parser


def _atomic_json_write(path: Path, data: dict[str, object]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary_name = tempfile.mkstemp(
        dir=str(path.parent), prefix=f".{path.name}.", suffix=".tmp"
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            json.dump(data, handle, indent=2)
            handle.write("\n")
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(temporary, path)
    except BaseException:
        temporary.unlink(missing_ok=True)
        raise


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    if not args.confirmed:
        print("ERROR: --confirmed is required; scope decisions cannot self-confirm")
        return EXIT_MALFORMED

    repo = Path(args.repo).resolve()
    manifest_path = repo / "docs" / "scope" / f"{args.feature}.scope.json"
    status, existing = load_scope_manifest(repo, args.feature)
    if status not in (EXIT_PASS, EXIT_MISSING):
        return status
    if status == EXIT_MISSING and manifest_path.exists():
        print(
            "ERROR: legacy scope JSON exists; migrate it explicitly before using the updater"
        )
        return EXIT_MALFORMED

    if existing is None:
        if not args.canvas or not args.plan:
            print("ERROR: --canvas and --plan are required for the first manifest revision")
            return EXIT_MISSING
        provenance: list[dict[str, object]] = []
        artifacts = {"canvas": args.canvas, "plan": args.plan}
    else:
        provenance = list(existing["provenance"])
        artifacts = dict(existing["artifacts"])
        if args.canvas:
            artifacts["canvas"] = args.canvas
        if args.plan:
            artifacts["plan"] = args.plan

    scope = {
        "product": list(args.product_path),
        "governance": list(args.governance_path),
    }
    if existing is not None and existing["scope"] == scope:
        print("ERROR: proposed scope is unchanged; no provenance revision written")
        return EXIT_MALFORMED

    provenance.append(
        {
            "revision": len(provenance) + 1,
            "origin": args.origin,
            "decision_maker": args.decision_maker,
            "decided_at": args.decided_at,
            "rationale": args.rationale,
            "confirmed": True,
            "scope": scope,
            "scope_digest": _scope_digest(scope),
        }
    )
    manifest: dict[str, object] = {
        "schema_version": 1,
        "feature": args.feature,
        "scope": scope,
        "artifacts": artifacts,
        "provenance": provenance,
    }
    validation_status, normalized = validate_manifest_data(
        manifest_path, manifest, args.feature
    )
    if validation_status != EXIT_PASS or normalized is None:
        return validation_status
    artifact_status = validate_manifest_artifacts(
        repo, args.feature, normalized
    )
    if artifact_status != EXIT_PASS:
        return artifact_status

    _atomic_json_write(manifest_path, manifest)
    print(
        f"PRIL canonical scope updated atomically for feature '{args.feature}' "
        f"(revision {len(provenance)}, digest {_scope_digest(scope)})"
    )
    return EXIT_PASS


if __name__ == "__main__":
    raise SystemExit(main())
