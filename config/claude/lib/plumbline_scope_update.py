#!/usr/bin/env python3
"""Atomically apply a confirmed decision to a canonical scope manifest."""
from __future__ import annotations

import argparse
import json
import os
import re
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
    parser.add_argument("--planned-create", action="append", default=[])
    parser.add_argument("--planned-modify", action="append", default=[])
    parser.add_argument("--planned-delete", action="append", default=[])
    parser.add_argument("--planned-test", action="append", default=[])
    parser.add_argument(
        "--replace-plan-declarations",
        action="store_true",
        help="Remove existing Create/Modify/Delete declarations before adding the supplied ones",
    )
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


def _atomic_text_write(path: Path, text: str) -> None:
    fd, temporary_name = tempfile.mkstemp(
        dir=str(path.parent), prefix=f".{path.name}.", suffix=".tmp"
    )
    temporary = Path(temporary_name)
    try:
        with os.fdopen(fd, "w", encoding="utf-8") as handle:
            handle.write(text)
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
    plan_additions = [
        (action, path)
        for action, paths in (
            ("Create", args.planned_create),
            ("Modify", args.planned_modify),
            ("Delete", args.planned_delete),
            ("Test", args.planned_test),
        )
        for path in paths
    ]
    if existing is not None and existing["scope"] == scope and not plan_additions:
        print("ERROR: proposed scope is unchanged; no provenance revision written")
        return EXIT_MALFORMED

    try:
        plan_path = (repo / str(artifacts["plan"])).resolve()
        plan_path.relative_to(repo)
    except (OSError, ValueError):
        print("ERROR: implementation plan resolves outside repository")
        return EXIT_MALFORMED
    original_plan_text: str | None = None
    proposed_plan_text: str | None = None
    if plan_additions:
        try:
            original_plan_text = plan_path.read_text(encoding="utf-8")
        except (OSError, UnicodeError) as exc:
            print(f"ERROR: cannot read implementation plan {plan_path}: {exc}")
            return EXIT_MALFORMED
        base_plan_text = original_plan_text
        if args.replace_plan_declarations:
            base_plan_text = "\n".join(
                line
                for line in original_plan_text.splitlines()
                if not re.search(r"\b(?:Create|Modify|Delete|Test):\s*", line)
            )
            if original_plan_text.endswith("\n"):
                base_plan_text += "\n"
        separator = "" if base_plan_text.endswith("\n") else "\n"
        declarations = "\n".join(
            f"- {action}: `{path}`" for action, path in plan_additions
        )
        proposed_plan_text = (
            base_plan_text
            + separator
            + "\n## Confirmed plan revision\n\n"
            + declarations
            + "\n"
        )

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
        repo,
        args.feature,
        normalized,
        plan_text_override=proposed_plan_text,
    )
    if artifact_status != EXIT_PASS:
        return artifact_status

    if proposed_plan_text is not None and original_plan_text is not None:
        _atomic_text_write(plan_path, proposed_plan_text)
        try:
            _atomic_json_write(manifest_path, manifest)
        except BaseException:
            # Restore the old plan if the manifest replacement fails. If this
            # rollback itself fails, the normal preflight sees plan/manifest
            # drift and blocks all implementation writes.
            _atomic_text_write(plan_path, original_plan_text)
            raise
    else:
        _atomic_json_write(manifest_path, manifest)
    print(
        f"PRIL canonical scope updated atomically for feature '{args.feature}' "
        f"(revision {len(provenance)}, digest {_scope_digest(scope)})"
    )
    return EXIT_PASS


if __name__ == "__main__":
    raise SystemExit(main())
