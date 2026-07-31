#!/usr/bin/env python3
"""Plumbline Runtime Integrity Layer reality-evidence gate."""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from plumbline_cli import (  # noqa: E402  (path shim above must run first)
    PlumblineArgumentParser,
)
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

# --- PLUM-13: evidence targets -----------------------------------------------
#
# Ranking the CLAIMED evidence class says nothing about WHAT the evidence touched.
# Measured 2026-07-30 against the pre-fix gate: a record claiming
# `real-boundary-smoke` for a requirement about dataset W32 on the product
# read-through route PASSED while its linked test drove W40 harness fixtures on a
# different route; and a record whose `evidence_ref` pointed at a file that does not
# exist was credited as `production-verified`.
#
# A critical acceptance criterion therefore declares its target in
# `docs/evidence/<feature>.targets.json`, and a ledger record only satisfies that
# requirement when the binding is PROVABLE in the referenced artifact.
TARGET_SCHEMA = 1
TARGET_KEYS = frozenset(
    {
        "requirement_id",
        "dataset",
        "boundary",
        "expected_result",
        "preconditions",
        "min_evidence",
        "proof_tokens",
        "note",
    }
)
TARGET_FILE_KEYS = frozenset({"schema", "feature", "targets", "notes"})
TARGET_REQUIRED = ("requirement_id", "dataset", "boundary", "expected_result")
PRECONDITION_STATES = ("present", "absent")

# Stable classifications the workflow (and the watcher) can key off.
CLASS_MISSING_BOUNDARY = "MISSING_BOUNDARY"
CLASS_EVIDENCE_MISMATCH = "EVIDENCE_MISMATCH"


def targets_path(repo: Path, feature: str) -> Path:
    return repo / "docs" / "evidence" / f"{feature}.targets.json"


def _targets_error(path: Path, repo: Path, detail: str) -> int:
    print(f"ERROR: invalid evidence targets {_rel(path, repo)}: {detail}", file=sys.stderr)
    return EXIT_MALFORMED


def _normalize_preconditions(
    raw: object, where: str, path: Path, repo: Path
) -> tuple[int | None, list[tuple[str, str]]]:
    """Normalize a precondition list to sorted ``(fixture, state)`` pairs."""
    if raw is None:
        return None, []
    if not isinstance(raw, list):
        return _targets_error(path, repo, f"{where}: 'preconditions' must be a list"), []
    out: list[tuple[str, str]] = []
    for index, item in enumerate(raw, start=1):
        if not isinstance(item, dict):
            return _targets_error(
                path, repo, f"{where}: precondition #{index} must be an object"
            ), []
        fixture = str(item.get("fixture", "")).strip()
        state = str(item.get("state", "")).strip()
        if not fixture:
            return _targets_error(
                path, repo, f"{where}: precondition #{index} is missing 'fixture'"
            ), []
        if state not in PRECONDITION_STATES:
            return _targets_error(
                path,
                repo,
                f"{where}: precondition #{index} has state {state!r}; "
                f"expected one of {', '.join(PRECONDITION_STATES)}",
            ), []
        out.append((fixture, state))
    return None, sorted(out)


def load_evidence_targets(repo: Path, feature: str) -> tuple[int, dict[str, dict]]:
    """Load the declared evidence targets keyed by requirement id.

    A feature with no targets file returns an empty mapping and PASS: existing
    ledgers keep working unchanged (the targets file is the opt-in mechanism). A
    PRESENT but broken targets file is a hard `malformed` error -- it must never
    degrade to "no targets declared", which would silently restore the false green.
    """
    path = targets_path(repo, feature)
    if not path.exists():
        return EXIT_PASS, {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except UnicodeDecodeError:
        return _targets_error(path, repo, "file is not UTF-8 text"), {}
    except json.JSONDecodeError as exc:
        return _targets_error(
            path, repo, f"invalid JSON ({exc.msg} at line {exc.lineno})"
        ), {}
    if not isinstance(data, dict):
        return _targets_error(path, repo, "top level must be a JSON object"), {}

    unknown = sorted(set(data) - TARGET_FILE_KEYS)
    if unknown:
        return _targets_error(
            path,
            repo,
            f"unknown key(s) {', '.join(repr(k) for k in unknown)}; "
            f"supported: {', '.join(sorted(TARGET_FILE_KEYS))}",
        ), {}

    schema = data.get("schema", TARGET_SCHEMA)
    if schema != TARGET_SCHEMA:
        return _targets_error(
            path, repo, f"unsupported schema version {schema!r} (supported: {TARGET_SCHEMA})"
        ), {}

    declared_feature = data.get("feature")
    if declared_feature is not None and declared_feature != feature:
        return _targets_error(
            path,
            repo,
            f"declares feature {declared_feature!r} but the check requested {feature!r}",
        ), {}

    raw_targets = data.get("targets")
    if not isinstance(raw_targets, list) or not raw_targets:
        return _targets_error(
            path, repo, "'targets' must be a non-empty list of target objects"
        ), {}

    targets: dict[str, dict] = {}
    for index, item in enumerate(raw_targets, start=1):
        where = f"target #{index}"
        if not isinstance(item, dict):
            return _targets_error(path, repo, f"{where} must be an object"), {}
        unknown = sorted(set(item) - TARGET_KEYS)
        if unknown:
            return _targets_error(
                path, repo, f"{where} has unknown key(s) {', '.join(repr(k) for k in unknown)}"
            ), {}
        missing = [f for f in TARGET_REQUIRED if not str(item.get(f, "")).strip()]
        if missing:
            return _targets_error(
                path,
                repo,
                f"{where} is missing required field(s): {', '.join(missing)}. A "
                "critical acceptance criterion must name its dataset, boundary and "
                "expected result, or the evidence cannot be bound to it.",
            ), {}
        req = str(item["requirement_id"]).strip()
        if req in targets:
            return _targets_error(
                path, repo, f"{where} duplicates requirement_id {req!r}"
            ), {}
        floor = item.get("min_evidence")
        if floor is not None and floor not in RANKS:
            return _targets_error(
                path, repo, f"{where} has unknown min_evidence {floor!r}"
            ), {}
        tokens = item.get("proof_tokens")
        if tokens is not None:
            if not isinstance(tokens, list) or not tokens:
                return _targets_error(
                    path, repo, f"{where}: 'proof_tokens' must be a non-empty list"
                ), {}
            if any(not isinstance(t, str) or not t.strip() for t in tokens):
                return _targets_error(
                    path, repo, f"{where}: every proof token must be a non-empty string"
                ), {}
            tokens = [t.strip() for t in tokens]
        err, preconditions = _normalize_preconditions(
            item.get("preconditions"), where, path, repo
        )
        if err is not None:
            return err, {}
        targets[req] = {
            "requirement_id": req,
            "dataset": str(item["dataset"]).strip(),
            "boundary": str(item["boundary"]).strip(),
            "expected_result": str(item["expected_result"]).strip(),
            "preconditions": preconditions,
            "min_evidence": floor,
            "proof_tokens": tokens,
        }
    return EXIT_PASS, targets


def _resolve_evidence_artifact(repo: Path, evidence_ref: str) -> Path | None:
    """Resolve the artifact path out of an ``evidence_ref``.

    The ledger convention is ``<repo-relative-path>::<selector> (free prose)``. Only
    the path part is resolvable; anything else (a bare prose reference) yields None,
    which the caller reports rather than treating as proof.
    """
    candidate = evidence_ref.strip().split("::", 1)[0].strip()
    candidate = candidate.split()[0].strip() if candidate.split() else ""
    if not candidate or candidate.startswith("/") or ".." in Path(candidate).parts:
        return None
    resolved = repo / candidate
    return resolved if resolved.is_file() else None


def _mismatch(record_index: int, requirement: str, detail: str) -> None:
    print(
        f"{CLASS_EVIDENCE_MISMATCH}: requirement={requirement} "
        f"ledger_line={record_index} {detail}",
        file=sys.stderr,
    )


def validate_evidence_targets(
    repo: Path, feature: str, records: list[dict[str, Any]], targets: dict[str, dict]
) -> int:
    """Check every declared target against the ledger. Returns an exit code."""
    if not targets:
        return EXIT_PASS

    by_requirement: dict[str, list[tuple[int, dict[str, Any]]]] = {}
    for index, record in enumerate(records, start=1):
        req = str(record.get("requirement_id", "")).strip()
        by_requirement.setdefault(req, []).append((index, record))

    missing_boundary = False
    mismatch = False

    for req, target in sorted(targets.items()):
        candidates = by_requirement.get(req, [])
        if not candidates:
            print(
                f"{CLASS_MISSING_BOUNDARY}: requirement={req} has a declared evidence "
                f"target (dataset={target['dataset']!r} boundary={target['boundary']!r}) "
                f"but NO record in the ledger for feature '{feature}'.",
                file=sys.stderr,
            )
            missing_boundary = True
            continue

        unbound: list[int] = []
        satisfied = False
        for index, record in candidates:
            binding_missing = [
                field
                for field in ("dataset", "boundary", "expected_result")
                if not str(record.get(field, "")).strip()
            ]
            if binding_missing:
                unbound.append(index)
                continue

            reasons: list[str] = []
            for field in ("dataset", "boundary", "expected_result"):
                declared = target[field]
                evidenced = str(record[field]).strip()
                if declared != evidenced:
                    reasons.append(
                        f"{field}: target demands {declared!r} but the evidence "
                        f"records {evidenced!r}"
                    )

            err, record_preconditions = _normalize_preconditions(
                record.get("preconditions"), f"ledger line {index}",
                repo / "docs" / "reality" / f"{feature}.evidence.jsonl", repo,
            )
            if err is not None:
                return err
            if target["preconditions"] and record_preconditions != target["preconditions"]:
                reasons.append(
                    "preconditions: target demands "
                    + ", ".join(f"{f}={s}" for f, s in target["preconditions"])
                    + " but the evidence records "
                    + (
                        ", ".join(f"{f}={s}" for f, s in record_preconditions)
                        or "none"
                    )
                )

            floor_name = target["min_evidence"]
            if floor_name is not None:
                actual = str(record["evidence_class"])
                if RANKS[actual] < RANKS[floor_name]:
                    reasons.append(
                        f"evidence_class: target demands at least {floor_name!r} "
                        f"but the evidence is {actual!r}"
                    )

            artifact = _resolve_evidence_artifact(repo, str(record["evidence_ref"]))
            if artifact is None:
                reasons.append(
                    f"evidence_ref {str(record['evidence_ref']).strip()!r} is "
                    "unresolvable: no such file in the repository, so nothing was "
                    "verified"
                )
            else:
                tokens = target["proof_tokens"] or [target["dataset"]]
                try:
                    haystack = artifact.read_text(encoding="utf-8", errors="replace")
                except OSError as exc:
                    reasons.append(
                        f"evidence artifact {_rel(artifact, repo)} could not be read "
                        f"({exc.strerror})"
                    )
                    haystack = ""
                absent = [token for token in tokens if token not in haystack]
                if absent:
                    reasons.append(
                        "the referenced artifact "
                        f"{_rel(artifact, repo)} does not contain the proof token(s) "
                        + ", ".join(repr(t) for t in absent)
                        + ", so the binding is self-declared, not proven"
                    )

            # An `absent`-state precondition passes trivially while the counter-set
            # does not exist yet (a vacuous absence test). It needs a paired
            # present-state control, and that control must resolve.
            if any(state == "absent" for _f, state in target["preconditions"]):
                control = str(record.get("control_ref", "")).strip()
                if not control:
                    reasons.append(
                        "an 'absent'-state target proves a negative, so the record "
                        "must name a paired present-state 'control_ref'; without it "
                        "the absence evidence is vacuous"
                    )
                elif _resolve_evidence_artifact(repo, control) is None:
                    reasons.append(
                        f"control_ref {control!r} is unresolvable: no such file in "
                        "the repository, so there is no present-state control"
                    )

            if reasons:
                for reason in reasons:
                    _mismatch(index, req, reason)
                mismatch = True
            else:
                satisfied = True
                print(
                    f"bound: requirement={req} dataset={target['dataset']} "
                    f"boundary={target['boundary']} class={record['evidence_class']} "
                    f"artifact={_rel(artifact, repo) if artifact else '?'}"
                )

        if not satisfied and unbound and not mismatch:
            for index in unbound:
                print(
                    f"{CLASS_MISSING_BOUNDARY}: requirement={req} ledger_line={index} "
                    "declares no dataset / boundary / expected_result, so it cannot "
                    f"evidence the declared target (dataset={target['dataset']!r} "
                    f"boundary={target['boundary']!r}).",
                    file=sys.stderr,
                )
            missing_boundary = True
        elif not satisfied and unbound:
            for index in unbound:
                print(
                    f"{CLASS_MISSING_BOUNDARY}: requirement={req} ledger_line={index} "
                    "declares no dataset / boundary / expected_result.",
                    file=sys.stderr,
                )
            missing_boundary = True

    if mismatch:
        return EXIT_INSUFFICIENT
    if missing_boundary:
        return EXIT_MISSING
    return EXIT_PASS


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

    # PLUM-13: before ranking claimed classes, bind each declared target to evidence
    # that provably touched it. A broken targets file is malformed, never "no
    # targets" -- degrading would restore exactly the false green this closes.
    target_status, targets = load_evidence_targets(repo, feature)
    if target_status != EXIT_PASS:
        return target_status
    if targets:
        bound_status = validate_evidence_targets(repo, feature, relevant, targets)
        if bound_status != EXIT_PASS:
            return bound_status

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
    parser = PlumblineArgumentParser(description="Validate reality evidence for a feature.")
    parser.add_argument("--repo", required=True, help="Repository root to inspect")
    parser.add_argument("--feature", required=True, help="Feature slug")
    parser.add_argument("--min-evidence", default="integration", choices=tuple(RANKS), help="Minimum evidence class")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return validate_reality(Path(args.repo).resolve(), args.feature, args.min_evidence)


if __name__ == "__main__":
    raise SystemExit(main())
