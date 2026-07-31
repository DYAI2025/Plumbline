#!/usr/bin/env python3
"""Plumbline generated-artifact provenance guard (PLUM-15).

The scope guard models PATHS. That is not enough: an allowed target path can still be
changed the wrong WAY. In the EYT-88 pilot `packages/contracts/openapi/v1.json` was an
allowed change target while its generator under `packages/contracts/src/openapi/**` was
not, and a HAND edit of the generated file would have passed the scope gate although it
is exactly the wrong change.

So the manifest may declare producer/output relationships:

    "generated_artifacts": [
      {"path": "pkg/openapi/v1.json",
       "producer": "pkg/src/openapi/**",
       "command": "./scripts/gen.sh",
       "deterministic": true}
    ]

Four classes are reported SEPARATELY, because they call for different fixes:

    PROVENANCE_VIOLATION   the artifact changed but nothing matching its producer did
                           -- a hand edit of generated output (exit 3)
    ARTIFACT_DRIFT         the producer changed, but re-running the declared command
                           does not reproduce the committed artifact (exit 3)
    NONDETERMINISTIC_OUTPUT  the command does not even agree with itself across two
                           consecutive runs, so drift is unprovable here (exit 3)
    PRODUCER_OUT_OF_SCOPE / MISSING_PRODUCER
                           the declaration contradicts the manifest, or names a
                           producer that matches no file (exit 4 / exit 3)

A byte-level drift test alone cannot distinguish "changed" from "changed legitimately":
that is why provenance (who produced it) and drift (does it reproduce) stay two visible
answers rather than one verdict.

Reproducibility verification EXECUTES the declared command, so it is opt-in
(`--verify-reproducible`). Without the flag no command is ever run, and the report says
plainly that reproducibility was not verified rather than implying it was.
"""
from __future__ import annotations

import argparse
import filecmp
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from plumbline_cli import (  # noqa: E402  (path shim above must run first)
    PlumblineArgumentParser,
)

from plumbline_scope import (  # noqa: E402  (path shim above must run first)
    EXIT_MALFORMED,
    EXIT_MISSING,
    EXIT_PASS,
    EXIT_VIOLATION,
    _matches,
    _pattern_problem,
    load_scope_model,
    manifest_path,
)

CLASS_PROVENANCE = "PROVENANCE_VIOLATION"
CLASS_DRIFT = "ARTIFACT_DRIFT"
CLASS_NONDETERMINISTIC = "NONDETERMINISTIC_OUTPUT"
CLASS_MISSING_PRODUCER = "MISSING_PRODUCER"
CLASS_PRODUCER_UNSCOPED = "PRODUCER_OUT_OF_SCOPE"

ARTIFACT_KEYS = frozenset({"path", "producer", "command", "deterministic", "note"})
ARTIFACT_REQUIRED = ("path", "producer", "command")


def load_generated_artifacts(repo: Path, feature: str) -> tuple[int, list[dict]]:
    """Read and validate the `generated_artifacts` declarations."""
    manifest = manifest_path(repo, feature)
    if not manifest.exists():
        print(
            f"ERROR: no scope manifest at {manifest}; provenance is declared there",
            file=sys.stderr,
        )
        return EXIT_MISSING, []
    import json

    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        detail = getattr(exc, "msg", str(exc))
        print(f"ERROR: invalid scope manifest {manifest}: {detail}", file=sys.stderr)
        return EXIT_MALFORMED, []
    if not isinstance(data, dict):
        print(
            f"ERROR: invalid scope manifest {manifest}: top level must be an object",
            file=sys.stderr,
        )
        return EXIT_MALFORMED, []

    raw = data.get("generated_artifacts")
    if raw is None:
        return EXIT_PASS, []
    if not isinstance(raw, list):
        print(
            f"ERROR: invalid scope manifest {manifest}: 'generated_artifacts' must be "
            "a list of declaration objects",
            file=sys.stderr,
        )
        return EXIT_MALFORMED, []

    out: list[dict] = []
    for index, item in enumerate(raw, start=1):
        where = f"generated_artifacts #{index}"
        if not isinstance(item, dict):
            print(
                f"ERROR: invalid scope manifest {manifest}: {where} must be an object",
                file=sys.stderr,
            )
            return EXIT_MALFORMED, []
        unknown = sorted(set(item) - ARTIFACT_KEYS)
        if unknown:
            print(
                f"ERROR: invalid scope manifest {manifest}: {where} has unknown "
                f"key(s) {', '.join(repr(k) for k in unknown)}",
                file=sys.stderr,
            )
            return EXIT_MALFORMED, []
        missing = [f for f in ARTIFACT_REQUIRED if not str(item.get(f, "")).strip()]
        if missing:
            print(
                f"ERROR: invalid scope manifest {manifest}: {where} is missing "
                f"required field(s): {', '.join(missing)}. A generated artifact needs "
                "its 'path', its 'producer' and the allowed generation 'command', or "
                "provenance cannot be judged.",
                file=sys.stderr,
            )
            return EXIT_MALFORMED, []
        for field in ("path", "producer"):
            problem = _pattern_problem(str(item[field]).strip())
            if problem is not None:
                print(
                    f"ERROR: invalid scope manifest {manifest}: {where} {field} "
                    f"{item[field]!r} {problem}",
                    file=sys.stderr,
                )
                return EXIT_MALFORMED, []
        deterministic = item.get("deterministic", True)
        if not isinstance(deterministic, bool):
            print(
                f"ERROR: invalid scope manifest {manifest}: {where} 'deterministic' "
                "must be true or false",
                file=sys.stderr,
            )
            return EXIT_MALFORMED, []
        out.append(
            {
                "path": str(item["path"]).strip(),
                "producer": str(item["producer"]).strip(),
                "command": str(item["command"]).strip(),
                "deterministic": deterministic,
            }
        )
    return EXIT_PASS, out


def _load_changed(path: Path) -> tuple[int, list[str]]:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        print(f"ERROR: missing changed-files list: {path}", file=sys.stderr)
        return EXIT_MISSING, []
    except UnicodeDecodeError:
        print(f"ERROR: changed-files list is not UTF-8 text: {path}", file=sys.stderr)
        return EXIT_MALFORMED, []
    return EXIT_PASS, [line.strip() for line in lines if line.strip()]


def _producer_matches_in_repo(repo: Path, producer: str) -> list[str]:
    """Files in the repository that the producer pattern matches."""
    hits: list[str] = []
    base = repo
    for candidate in base.rglob("*"):
        if not candidate.is_file():
            continue
        try:
            rel = str(candidate.relative_to(repo))
        except ValueError:
            continue
        if rel.startswith(".git/"):
            continue
        if _matches(rel, producer):
            hits.append(rel)
    return sorted(hits)


def _run_generator(repo: Path, command: str) -> tuple[int, str]:
    """Execute the DECLARED generation command. Returns (returncode, output).

    TRUST BOUNDARY, stated rather than implied: the command string comes from
    ``docs/scope/<feature>.scope.json``, i.e. from the repository. Running
    ``--verify-reproducible`` on a branch you do not trust executes repo-supplied
    commands (twice per deterministic artifact). That is why the flag is opt-in and why
    the Stop hook never passes it. Bounded so a hanging generator cannot wedge a caller.
    """
    try:
        result = subprocess.run(
            command,
            shell=True,
            cwd=str(repo),
            capture_output=True,
            text=True,
            check=False,
            timeout=60,
        )
    except subprocess.TimeoutExpired:
        return 124, f"the generation command exceeded 60s: {command!r}"
    return result.returncode, (result.stderr or result.stdout).strip()


def _verify_reproducible(
    repo: Path, artifact: dict
) -> tuple[str | None, str]:
    """Re-run the generator and compare bytes.

    Returns ``(problem_class, detail)`` with ``problem_class`` None on success. The
    committed artifact is always restored, so the check never leaves the tree dirty.
    """
    target = repo / artifact["path"]
    if not target.is_file():
        return CLASS_DRIFT, (
            f"the declared artifact {artifact['path']} does not exist, so it cannot "
            "be compared against a regeneration"
        )

    with tempfile.TemporaryDirectory() as tmp:
        backup = Path(tmp) / "committed"
        shutil.copy2(target, backup)
        try:
            rc, output = _run_generator(repo, artifact["command"])
            if rc != 0:
                return "TOOL", (
                    f"the declared generation command {artifact['command']!r} failed "
                    f"with exit code {rc}: {output.splitlines()[0] if output else '(no output)'}"
                )
            first = Path(tmp) / "run1"
            if not target.is_file():
                return CLASS_DRIFT, (
                    f"the declared command {artifact['command']!r} did not produce "
                    f"{artifact['path']}"
                )
            shutil.copy2(target, first)

            if not artifact["deterministic"]:
                # A declared non-deterministic generator cannot be byte-compared at
                # all: a difference would prove nothing, and an accidental match would
                # prove even less. Withhold the reproducibility claim explicitly rather
                # than manufacturing a verdict from an invalid comparison.
                #
                # This is a distinct outcome from "verified", not a flavour of it: the
                # flag is a potential bypass (declare non-determinism, never be
                # drift-checked again), so it must never be reported in the same words
                # as a real reproducibility pass.
                return "WITHHELD", (
                    f"{artifact['path']} was regenerated from "
                    f"{artifact['command']!r}; deterministic=false, so no byte "
                    "comparison was made and reproducibility is NOT claimed"
                )

            # Self-agreement first: without it, a byte difference against the committed
            # file cannot be attributed to drift at all.
            rc, output = _run_generator(repo, artifact["command"])
            if rc != 0:
                return "TOOL", (
                    f"the declared generation command {artifact['command']!r} "
                    f"failed on its second run with exit code {rc}"
                )
            second = Path(tmp) / "run2"
            shutil.copy2(target, second)
            if not filecmp.cmp(first, second, shallow=False):
                return CLASS_NONDETERMINISTIC, (
                    f"the generator for {artifact['path']} is declared "
                    "deterministic, but two consecutive runs produced different "
                    "bytes; drift cannot be attributed while this holds. Make the "
                    "generator reproducible, or declare deterministic=false."
                )

            if not filecmp.cmp(backup, first, shallow=False):
                return CLASS_DRIFT, (
                    f"re-running {artifact['command']!r} does not reproduce the "
                    f"committed {artifact['path']}: the file in the tree is not the "
                    "output of its declared producer"
                )
            return None, (
                f"{artifact['path']} reproduces byte-identically from "
                f"{artifact['command']!r}"
            )
        finally:
            shutil.copy2(backup, target)


def check_provenance(
    repo: Path, feature: str, changed_files: Path, verify_reproducible: bool = False
) -> int:
    status, model, source = load_scope_model(repo, feature)
    if status != EXIT_PASS:
        return status
    allowed = list(model.get("product", [])) + list(model.get("governance", []))

    art_status, artifacts = load_generated_artifacts(repo, feature)
    if art_status != EXIT_PASS:
        return art_status

    changed_status, changed = _load_changed(changed_files)
    if changed_status != EXIT_PASS:
        return changed_status

    if not artifacts:
        print(
            f"provenance: no generated artifacts declared for feature '{feature}' "
            f"(scope source={source}); nothing to judge"
        )
        return EXIT_PASS

    provenance_problems: list[str] = []
    drift_problems: list[str] = []
    nondeterministic: list[str] = []
    tool_problems: list[str] = []
    contradictions: list[str] = []
    verified: list[str] = []

    for artifact in artifacts:
        path = artifact["path"]
        producer = artifact["producer"]

        # A declaration that contradicts the manifest is an authoring error, not a
        # runtime violation: the producer can never legally change.
        if not any(_matches_pattern_pair(producer, pattern) for pattern in allowed):
            contradictions.append(
                f"{CLASS_PRODUCER_UNSCOPED}: artifact={path} producer={producer} is "
                "not inside the Allowed change scope, so the artifact could only ever "
                "be changed by an unauthorized route. Add the producer to the manifest "
                "or drop the declaration."
            )
            continue

        producer_files = _producer_matches_in_repo(repo, producer)
        if not producer_files:
            provenance_problems.append(
                f"{CLASS_MISSING_PRODUCER}: artifact={path} producer={producer} "
                "matches no file in the repository, so the declared production route "
                "does not exist and no change to the artifact can be attributed to it."
            )
            continue

        artifact_changed = any(_matches(entry, path) for entry in changed)
        producer_changed = any(_matches(entry, producer) for entry in changed)

        if artifact_changed and not producer_changed:
            provenance_problems.append(
                f"{CLASS_PROVENANCE}: artifact={path} changed but nothing matching its "
                f"producer {producer} did. A generated artifact must change only "
                f"through its producer; regenerate it with the declared command "
                f"{artifact['command']!r} instead of editing it by hand. (The path is "
                "allowed by the scope; the production route is not.)"
            )
            continue

        if not artifact_changed:
            continue

        if not verify_reproducible:
            verified.append(
                f"provenance ok: artifact={path} changed together with its producer "
                f"{producer}; reproducibility not verified (pass --verify-reproducible "
                f"to run {artifact['command']!r})"
            )
            continue

        problem, detail = _verify_reproducible(repo, artifact)
        if problem is None:
            verified.append(f"provenance+drift ok: {detail}")
        elif problem == "WITHHELD":
            # Passes, but under its own wording: no drift verdict was reached.
            verified.append(f"provenance ok, drift NOT checked: {detail}")
        elif problem == CLASS_NONDETERMINISTIC:
            nondeterministic.append(f"{CLASS_NONDETERMINISTIC}: {detail}")
        elif problem == "TOOL":
            tool_problems.append(f"PROVENANCE_TOOL_FAILURE: artifact={path} {detail}")
        else:
            drift_problems.append(f"{CLASS_DRIFT}: artifact={path} {detail}")

    for line in verified:
        print(line)
    for artifact in artifacts:
        if verify_reproducible and not artifact["deterministic"]:
            print(
                f"note: artifact={artifact['path']} deterministic=false — the "
                "reproducibility claim is withheld by declaration, not assumed"
            )

    # AC-4: drift and provenance stay SEPARATE answers, printed under their own class.
    for line in contradictions:
        print(line, file=sys.stderr)
    for line in provenance_problems:
        print(line, file=sys.stderr)
    for line in nondeterministic:
        print(line, file=sys.stderr)
    for line in drift_problems:
        print(line, file=sys.stderr)
    for line in tool_problems:
        print(line, file=sys.stderr)

    if contradictions:
        return EXIT_MALFORMED
    if tool_problems and not (provenance_problems or drift_problems or nondeterministic):
        # A checker that could not run is not a policy violation.
        return EXIT_MISSING
    if provenance_problems or drift_problems or nondeterministic:
        return EXIT_VIOLATION
    if tool_problems:
        return EXIT_VIOLATION
    print(
        f"PRIL provenance check passed for feature '{feature}' "
        f"({len(artifacts)} declared artifact(s), scope source={source})"
    )
    return EXIT_PASS


def _matches_pattern_pair(producer: str, allowed_pattern: str) -> bool:
    """Is the producer pattern covered by an allowed-scope pattern?

    Compares patterns, not paths: `pkg/src/openapi/**` is covered by
    `pkg/src/openapi/**` and by a broader `pkg/**`. A concrete probe path derived from
    the producer keeps this simple and conservative.
    """
    if producer == allowed_pattern:
        return True
    probe = producer.replace("**", "x").replace("*", "x")
    probe = probe.rstrip("/") or producer
    return _matches(probe, allowed_pattern)


def build_parser() -> argparse.ArgumentParser:
    parser = PlumblineArgumentParser(
        description="Check that generated artifacts changed only through their "
        "declared producer, and (opt-in) that they reproduce.",
    )
    parser.add_argument("--repo", required=True, help="Repository root to inspect")
    parser.add_argument("--feature", required=True, help="Feature slug")
    parser.add_argument(
        "--changed-files", required=True, help="File containing repo-relative changed paths"
    )
    parser.add_argument(
        "--verify-reproducible",
        action="store_true",
        help="EXECUTE each declared generation command and compare bytes "
        "(off by default: this runs commands from the manifest)",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return check_provenance(
        Path(args.repo).resolve(),
        args.feature,
        Path(args.changed_files),
        verify_reproducible=args.verify_reproducible,
    )


if __name__ == "__main__":
    raise SystemExit(main())
