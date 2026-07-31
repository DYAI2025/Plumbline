#!/usr/bin/env python3
"""Plumbline Runtime Integrity Layer scope guard."""
from __future__ import annotations

import argparse
import fnmatch
import hashlib
import json
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from plumbline_cli import (  # noqa: E402  (path shim above must run first)
    PlumblineArgumentParser,
)

EXIT_PASS = 0
EXIT_MISSING = 2
EXIT_VIOLATION = 3
EXIT_MALFORMED = 4

SECTION_NAMES = ("allowed change scope", "allowed changes", "change scope")

# PLUM-10: the canonical, machine-readable scope manifest.
#
# The markdown canvas is a HUMAN document that a formatter, a wrapped line or an
# inline description can silently rewrite; it must not be the primary security
# configuration. `docs/scope/<feature>.scope.json` is. It is checked FIRST and,
# when present, it is the ONLY source — a canvas can no longer widen or override
# it. Measured pilot failures this replaces: a `- /src/feature/**` bullet and a
# fenced code block were both discarded silently (reported as "missing"), and a
# formatter-wrapped `* …` prose line became a real allowed pattern.
MANIFEST_SCHEMA = 1
# Unknown keys are refused rather than ignored: in a security configuration a
# typo'd key must not read as "not configured".
MANIFEST_KEYS = frozenset(
    {
        "schema",
        "feature",
        "allowed_change_scope",
        "governance_paths",
        "generated_artifacts",
        "notes",
        "provenance",
    }
)
# PLUM-15: `generated_artifacts` declares producer/output relationships. The scope
# guard itself still judges PATHS only -- provenance is a separate, separately visible
# answer in plumbline_provenance.py -- but the declaration lives in the same canonical
# manifest, so the key must be recognised here rather than refused as unknown.
# PLUM-12 (AC-5): product paths and governance paths are modelled separately, so a
# drift report can say WHICH class a path belongs to instead of flattening the
# feature's own canvas/PRD/ledger into its product surface. Both classes authorize
# a change; only their classification differs.
SCOPE_CLASSES = ("product", "governance")
PLACEHOLDER_TOKENS = {"MISSING", "OPEN QUESTION", "BLOCKER"}


def _pattern_problem(pattern: str) -> str | None:
    """Why ``pattern`` cannot be used as an allowed-scope pattern (or None).

    Shared by the manifest (where a problem is a HARD error) and the legacy
    canvas (where it is a loud, named drop). Every rejection NARROWS the allowed
    set, so a bad line can never widen the scope.
    """
    if not pattern:
        return "is empty"
    if pattern.upper() in PLACEHOLDER_TOKENS:
        return f"is the placeholder token {pattern.upper()!r}, not a path"
    if any(ord(ch) < 32 for ch in pattern):
        return "contains a control character"
    if any(ch.isspace() for ch in pattern):
        return "contains whitespace (looks like prose, not a path)"
    if pattern.startswith("/"):
        return "must be repo-relative (no leading '/')"
    if "\\" in pattern:
        return "must use '/' as the path separator"
    if ".." in Path(pattern).parts:
        return "must not contain '..'"
    return None


def _is_broad_pattern(pattern: str) -> bool:
    """A pattern is "broad" if it has no concrete path segment to anchor on.

    A self-authored scope must not legitimize *every* path with a single
    wildcard line: a bare ``*``, ``**``, ``.``, ``/`` or ``**/*`` matches the
    whole repo and silently defeats the scope guard. ``fnmatch`` treats ``*``
    AND ``?`` AND character classes (``[a-z]``, ``[!/]`` …) as wildcards that
    cross ``/``, so ``?*``, ``[!/]*`` and friends also match the whole repo —
    they are just as broad as a bare ``*`` and must be refused too. We treat a
    pattern as broad when, after removing every glob metacharacter (character
    classes, ``*``, ``?``) and ``.``, no literal path segment remains.
    Legitimate patterns keep a concrete anchor: ``src/billing/**`` ->
    ``src``/``billing``; ``config/claude/*.py`` -> ``config``/``claude``/``py``;
    ``file[0-9].txt`` -> ``file``/``txt`` (the class spans away but the literals
    remain).
    """
    candidate = pattern.strip().strip("/")
    if not candidate:
        return True
    # Neutralize ``[...]`` character-class spans FIRST, on the whole pattern,
    # before splitting on ``/`` — a class may legitimately contain ``/`` (e.g.
    # ``[!/]*``), so stripping classes after the split would leave a class's
    # contents (``!``, ``/`` …) misread as a literal anchor.
    declassed = re.sub(r"\[.*?\]", "", candidate)
    for segment in declassed.split("/"):
        # A segment contributes a concrete anchor iff some literal character
        # remains after removing the remaining glob metacharacters (``*``,
        # ``?``) and ``.``. If nothing literal is left, the segment is
        # non-anchoring (so ``*``, ``**``, ``?``, ``?*``, ``[a-z]*``, ``[!/]*``
        # are NOT anchors, but ``*.py`` / ``file[0-9].txt`` are).
        seg = segment.replace("*", "").replace("?", "").replace(".", "")
        if seg.strip():
            return False
    return True


def _rel(path: Path, repo: Path) -> str:
    try:
        return str(path.relative_to(repo))
    except ValueError:
        return str(path)


def _valid_feature(feature: str) -> bool:
    return bool(feature) and "/" not in feature and "\\" not in feature and feature not in {".", ".."}


def _candidate_pattern(line: str) -> str | None:
    """Strip list markup/backticks off a markdown line. No validation."""
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        return None
    for prefix in ("- [ ]", "- [x]", "-", "*", "+"):
        if stripped.startswith(prefix):
            stripped = stripped[len(prefix):].strip()
            break
    if "#" in stripped:
        stripped = stripped.split("#", 1)[0].strip()
    return stripped.strip("` ").strip()


def _clean_pattern(line: str) -> tuple[str | None, str | None]:
    """Return ``(pattern, drop_reason)`` for one markdown line.

    Exactly one of the two is non-None. A dropped line is never silent: the
    reason is reported by the caller together with the source line number.
    """
    candidate = _candidate_pattern(line)
    if candidate is None:
        return None, None  # blank line or markdown comment: intentional, silent
    problem = _pattern_problem(candidate)
    if problem is not None:
        return None, problem
    return candidate, None


def _patterns_from_canvas(canvas: Path) -> tuple[int, list[str], list[str]]:
    """Parse the legacy canvas scope section.

    Returns ``(status, patterns, ignored)``. ``ignored`` describes every line
    inside the section that did NOT become a pattern, each with its 1-based file
    line number and the reason. Nothing is discarded silently — a silently
    dropped bullet was the pilot's false RED ("missing Allowed change scope"
    while the author had in fact declared one).
    """
    try:
        lines = canvas.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return EXIT_MISSING, [], []
    except UnicodeDecodeError:
        print(f"ERROR: malformed canvas is not UTF-8 text: {canvas}", file=sys.stderr)
        return EXIT_MALFORMED, [], []

    in_section = False
    in_fence = False
    patterns: list[str] = []
    ignored: list[str] = []

    def note(lineno: int, text: str, reason: str) -> None:
        ignored.append(f"line {lineno} {text.strip()!r}: {reason}")

    for lineno, line in enumerate(lines, start=1):
        stripped = line.strip()
        if stripped.startswith("```") or stripped.startswith("~~~"):
            if in_section:
                in_fence = not in_fence
            continue
        if not in_fence and line.lstrip().startswith("#"):
            if in_section:
                break
            normalized_heading = stripped.lstrip("#").strip().lower()
            if "." in normalized_heading:
                before, after = normalized_heading.split(".", 1)
                if before.strip().isdigit():
                    normalized_heading = after.strip()
            if normalized_heading in SECTION_NAMES:
                in_section = True
            continue
        if not in_section:
            continue
        if in_fence:
            if stripped:
                note(lineno, line, "inside a fenced code block, not a list item")
            continue
        if not stripped:
            continue
        if not stripped.startswith(("-", "*", "+")):
            # A wrapped/indented continuation or a prose paragraph. Only report
            # lines that look like they were MEANT to be a path, so ordinary
            # explanatory prose does not drown the signal.
            if "/" in stripped or "`" in stripped:
                note(lineno, line, "not a list item (wrapped or indented continuation?)")
            continue
        pattern, reason = _clean_pattern(line)
        if pattern:
            patterns.append(pattern)
        elif reason:
            note(lineno, line, reason)
    if not patterns:
        return EXIT_MISSING, [], ignored
    return EXIT_PASS, patterns, ignored


def _patterns_from_traceability(traceability: Path, feature: str) -> list[str]:
    if not traceability.exists() or not traceability.is_file():
        return []
    try:
        text = traceability.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return []
    patterns: list[str] = []
    for line in text.splitlines():
        if feature not in line or "scope" not in line.lower():
            continue
        if ":" in line:
            _, rhs = line.split(":", 1)
        else:
            rhs = line
        for item in rhs.replace(",", "\n").splitlines():
            pattern, _reason = _clean_pattern(item)
            if pattern and pattern != feature:
                patterns.append(pattern)
    return patterns


def _manifest_error(manifest: Path, detail: str) -> int:
    print(f"ERROR: invalid scope manifest {manifest}: {detail}", file=sys.stderr)
    return EXIT_MALFORMED


def _patterns_from_manifest(manifest: Path, feature: str) -> tuple[int, dict]:
    """Load the canonical scope manifest. STRICT: every problem is classified.

    A manifest is machine configuration, so intent is never guessed: an entry
    that is not a clean repo-relative path/glob fails the check and names the
    offending entry index, instead of being dropped (which would silently narrow)
    or coerced (which would silently widen).
    """
    if not manifest.exists():
        return EXIT_MISSING, {}
    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
    except UnicodeDecodeError:
        return _manifest_error(manifest, "file is not UTF-8 text"), {}
    except json.JSONDecodeError as exc:
        return _manifest_error(manifest, f"invalid JSON ({exc.msg} at line {exc.lineno})"), {}

    if not isinstance(data, dict):
        return _manifest_error(manifest, "top level must be a JSON object"), {}

    unknown = sorted(set(data) - MANIFEST_KEYS)
    if unknown:
        return _manifest_error(
            manifest,
            f"unknown key(s) {', '.join(repr(k) for k in unknown)}; "
            f"supported: {', '.join(sorted(MANIFEST_KEYS))}",
        ), {}

    # An absent `schema` means the original v1 shape (the pre-PLUM-10 fixtures).
    schema = data.get("schema", MANIFEST_SCHEMA)
    if schema != MANIFEST_SCHEMA:
        return _manifest_error(
            manifest,
            f"unsupported schema version {schema!r} (supported: {MANIFEST_SCHEMA})",
        ), {}

    declared = data.get("feature")
    if declared is not None and declared != feature:
        return _manifest_error(
            manifest,
            f"declares feature {declared!r} but the check requested {feature!r}",
        ), {}

    raw = data.get("allowed_change_scope")
    if not isinstance(raw, list):
        return _manifest_error(
            manifest, "'allowed_change_scope' must be a list of repo-relative paths/globs"
        ), {}

    def read_list(key: str, entries: object) -> tuple[int | None, list[str]]:
        if not isinstance(entries, list):
            return _manifest_error(
                manifest, f"{key!r} must be a list of repo-relative paths/globs"
            ), []
        out: list[str] = []
        for index, item in enumerate(entries, start=1):
            label = f"entry #{index}" if key == "allowed_change_scope" else f"{key} entry #{index}"
            if not isinstance(item, str):
                return _manifest_error(
                    manifest, f"{label} is not a string (got {type(item).__name__})"
                ), []
            candidate = item.strip()
            problem = _pattern_problem(candidate)
            if problem is not None:
                return _manifest_error(manifest, f"{label} {item!r} {problem}"), []
            if _is_broad_pattern(candidate):
                return _manifest_error(
                    manifest,
                    f"{label} {candidate!r} is too broad and would legitimize "
                    "every path; use a pattern with a concrete path segment "
                    "(e.g. 'src/feature/**')",
                ), []
            out.append(candidate)
        return None, out

    status, product = read_list("allowed_change_scope", raw)
    if status is not None:
        return status, {}
    governance: list[str] = []
    if "governance_paths" in data:
        status, governance = read_list("governance_paths", data["governance_paths"])
        if status is not None:
            return status, {}

    if not product and not governance:
        print(
            f"ERROR: scope manifest {manifest} declares an EMPTY allowed_change_scope; "
            "an empty allow-list authorizes nothing (it is not a wildcard). "
            "List the confirmed paths/globs.",
            file=sys.stderr,
        )
        return EXIT_MISSING, {}

    provenance = data.get("provenance")
    if provenance is not None and not isinstance(provenance, list):
        return _manifest_error(manifest, "'provenance' must be a list of records"), {}

    return EXIT_PASS, {
        "product": product,
        "governance": governance,
        "provenance": provenance,
        "manifest": manifest,
    }


def _reject_broad(patterns: list[str]) -> int | None:
    """Return EXIT_MALFORMED (fail closed) if any pattern is overly broad."""
    broad = [p for p in patterns if _is_broad_pattern(p)]
    if broad:
        print(
            "ERROR: allowed-scope pattern is too broad and would legitimize every "
            f"path: {broad[0]!r}; use a pattern with a concrete path segment "
            "(e.g. 'src/feature/**')",
            file=sys.stderr,
        )
        return EXIT_MALFORMED
    return None


def manifest_path(repo: Path, feature: str) -> Path:
    return repo / "docs" / "scope" / f"{feature}.scope.json"


def load_scope_model(repo: Path, feature: str) -> tuple[int, dict, str]:
    """Class-aware view of the effective scope, for the PLUM-12 drift checks.

    Returns ``(status, model, source)``. ``model`` carries ``product`` and
    ``governance`` pattern lists separately (plus the raw ``provenance`` records
    when the manifest declares them), so a drift report can name the CLASS of a
    path instead of flattening a feature's own governance artifacts into its
    product surface.

    A legacy canvas/traceability source has no class information: everything it
    declares is reported as ``product`` and ``classified`` is False, so a caller
    can say so rather than implying a distinction the source cannot express.
    """
    manifest = manifest_path(repo, feature)
    if manifest.exists():
        status, model = _patterns_from_manifest(manifest, feature)
        if status != EXIT_PASS:
            return status, {}, f"manifest={_rel(manifest, repo)}"
        model["classified"] = True
        return status, model, f"manifest={_rel(manifest, repo)}"

    status, patterns, source = load_allowed_scope(repo, feature)
    if status != EXIT_PASS:
        return status, {}, source
    return (
        status,
        {
            "product": patterns,
            "governance": [],
            "provenance": None,
            "manifest": None,
            "classified": False,
        },
        source,
    )


def load_allowed_scope(repo: Path, feature: str) -> tuple[int, list[str], str]:
    """Resolve the effective allowed scope.

    Returns ``(status, patterns, source)`` where ``source`` is a stable label
    (``manifest=<path>``, ``canvas=<path>``, ``traceability=<path>``) so a run can
    never leave "which configuration governs me?" a guess.

    Precedence — the canonical manifest is FIRST and FINAL. When it exists, a
    canvas can neither widen nor override it (the pilot's manifest lost to the
    canvas, which made the fragile markdown the effective security config).
    """
    manifest = manifest_path(repo, feature)
    if manifest.exists():
        status, model = _patterns_from_manifest(manifest, feature)
        patterns = list(model.get("product", [])) + list(model.get("governance", []))
        return status, patterns, f"manifest={_rel(manifest, repo)}"

    canvas = repo / "docs" / "canvas" / f"{feature}.canvas.md"
    status, patterns, ignored = _patterns_from_canvas(canvas)
    canvas_source = f"canvas={_rel(canvas, repo)}"
    if status == EXIT_PASS:
        for entry in ignored:
            # No silent drops: name every line the parser did not use.
            print(
                f"NOTE: {_rel(canvas, repo)} {entry} — not used as an allowed-scope "
                f"pattern; the canonical source is {_rel(manifest, repo)}"
            )
        broad = _reject_broad(patterns)
        if broad is not None:
            return broad, [], canvas_source
        return status, patterns, canvas_source
    if status == EXIT_MALFORMED:
        return status, [], canvas_source
    if ignored:
        # The author DID declare a scope; the parser could not use any of it.
        # Reporting this as "missing" was the pilot's misleading false RED.
        print(
            f"ERROR: {_rel(canvas, repo)} declares an 'Allowed change scope' section "
            "but no line in it is a usable pattern: "
            + "; ".join(ignored)
            + f". Put the confirmed scope in {_rel(manifest, repo)} "
            "(one repo-relative path/glob per array entry).",
            file=sys.stderr,
        )
        return EXIT_MALFORMED, [], canvas_source

    trace = repo / "docs" / "traceability.md"
    trace_patterns = _patterns_from_traceability(trace, feature)
    if trace_patterns:
        broad = _reject_broad(trace_patterns)
        trace_source = f"traceability={_rel(trace, repo)}"
        if broad is not None:
            return broad, [], trace_source
        return EXIT_PASS, trace_patterns, trace_source

    print(
        "ERROR: missing Allowed change scope for feature "
        f"'{feature}'; add {_rel(manifest, repo)} (canonical) "
        f"or the legacy docs/canvas/{feature}.canvas.md section 'Allowed change scope'",
        file=sys.stderr,
    )
    return EXIT_MISSING, [], f"none={_rel(manifest, repo)}"


def _matches(path: str, pattern: str) -> bool:
    pattern = pattern.strip()
    if pattern.endswith("/"):
        return path.startswith(pattern)
    if pattern.endswith("/**"):
        return path == pattern[:-3] or path.startswith(pattern[:-2])
    return fnmatch.fnmatchcase(path, pattern) or path == pattern


def _load_changed_files(path: Path) -> tuple[int, list[str]]:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        print(f"ERROR: missing changed-files list: {path}", file=sys.stderr)
        return EXIT_MISSING, []
    except UnicodeDecodeError:
        print(f"ERROR: changed-files list is not UTF-8 text: {path}", file=sys.stderr)
        return EXIT_MALFORMED, []
    changed = [line.strip() for line in lines if line.strip()]
    bad = [p for p in changed if p.startswith("/") or ".." in Path(p).parts]
    if bad:
        print(f"ERROR: malformed changed file path: {bad[0]}", file=sys.stderr)
        return EXIT_MALFORMED, []
    return EXIT_PASS, changed


def _gitignored_untracked(repo: Path, paths: list[str]) -> set[str]:
    """Subset of ``paths`` that are BOTH gitignored AND untracked.

    These are session-tooling droppings (e.g. ``.claude-flow/`` daemon state),
    not feature edits, and repeatedly false-positived the scope gate
    (2026-07-08 retro, C4). Tracked files are never exempted — a
    tracked-but-ignore-matching file still counts as a real edit. Any git
    failure (no repo, git missing) exempts nothing: fail-closed.
    """
    if not paths:
        return set()
    try:
        tracked = subprocess.run(
            ["git", "-C", str(repo), "ls-files", "--", *paths],
            capture_output=True, text=True, check=False,
        )
        if tracked.returncode != 0:
            return set()
        tracked_set = {line.strip() for line in tracked.stdout.splitlines() if line.strip()}
        candidates = [p for p in paths if p.rstrip("/") not in tracked_set]
        if not candidates:
            return set()
        ignored = subprocess.run(
            ["git", "-C", str(repo), "check-ignore", "--", *candidates],
            capture_output=True, text=True, check=False,
        )
        # check-ignore exits 1 when no path matches — not an error here.
        if ignored.returncode not in (0, 1):
            return set()
        return {line.strip() for line in ignored.stdout.splitlines() if line.strip()}
    except OSError:
        return set()


def verify_run_trust_for_scope(repo: Path, feature: str) -> str | None:
    """Check the manifest against the run-trust anchor bound before the run.

    Supersedes the in-repo `.plumbline/scope-authority/` baseline this module used
    to write itself. Two things were wrong with that: the baseline lived inside
    the repository the run could write, and the gate CREATED it on first use --
    so the first gate run was also the arming moment, and any widening performed
    before it was silently adopted as the baseline rather than detected.

    The anchor lives outside the repository, is written by an externally
    installed Plumbline before implementation writes begin, and is only ever READ
    here. A missing, altered or unreadable anchor blocks; it is never re-created.

    Transition, stated rather than hidden: this applies to features governed by a
    scope MANIFEST. A legacy canvas-only feature that was never armed keeps the
    pre-existing (weaker) posture -- see docs/run-trust-anchor.md. That residual
    is named there, not silently carried.
    """
    manifest = manifest_path(repo, feature)
    if not manifest.exists():
        anchor = _run_trust_anchor_path(repo, feature)
        # Legacy canvas-only feature that was never armed. An unresolvable anchor
        # path (no trust module on this deployment) counts as "not armed" here --
        # otherwise every pre-anchor installation would block on upgrade.
        if anchor is None or not anchor.exists():
            return None

    try:
        from plumbline_run_trust import verify_run_trust
    except ImportError:
        # The trust module is part of the runtime; its absence means the gate
        # cannot prove anything. Fail closed rather than skip the check.
        return (
            "RUN_TRUST_BASELINE_UNREADABLE: the run-trust module is not available, "
            "so this run's authority cannot be verified."
        )
    return verify_run_trust(repo, feature)


def _run_trust_anchor_path(repo: Path, feature: str):
    try:
        from plumbline_run_trust import anchor_path
    except ImportError:
        return None
    try:
        return anchor_path(repo, feature)
    except OSError:
        return None


def validate_scope(repo: Path, feature: str, changed_files: Path, strict_gitignored: bool = False) -> int:
    if not _valid_feature(feature):
        print(f"ERROR: malformed feature slug: {feature!r}", file=sys.stderr)
        return EXIT_MALFORMED
    # Order matters, and the two orders answer different questions.
    #
    # ARMED: trust is checked FIRST. Deleting the bound manifest is structurally
    # indistinguishable from "no scope declared", but it is really an armed run
    # losing the artifact that defines its authority -- reporting that as MISSING
    # would let a deletion read as a benign absence.
    #
    # UNARMED: structure is checked first, because whether a file parses is a
    # property of the file and a malformed manifest authorizes nothing either
    # way. Ordering trust ahead of it would collapse every unparseable manifest
    # into a trust violation and lose the malformed/missing distinction the exit
    # contract depends on.
    anchor = _run_trust_anchor_path(repo, feature)
    armed = anchor is not None and anchor.exists()

    if armed:
        trust_error = verify_run_trust_for_scope(repo, feature)
        if trust_error is not None:
            print(f"ERROR: {trust_error}", file=sys.stderr)
            return EXIT_VIOLATION

    status, patterns, source = load_allowed_scope(repo, feature)
    if status != EXIT_PASS:
        return status

    if not armed:
        trust_error = verify_run_trust_for_scope(repo, feature)
        if trust_error is not None:
            print(f"ERROR: {trust_error}", file=sys.stderr)
            return EXIT_VIOLATION
    changed_status, changed = _load_changed_files(changed_files)
    if changed_status != EXIT_PASS:
        return changed_status
    out = [path for path in changed if not any(_matches(path, pattern) for pattern in patterns)]
    # Plumbline's own runtime directory is never feature work. It holds the scope
    # baseline this checker just bound, so leaving it in the surface would make the
    # guard report itself as an out-of-scope change -- a false red manufactured by
    # the fix. Exempted unconditionally, not merely when the repo happens to
    # gitignore it, because a governed foreign repo has no reason to know the name.
    out = [path for path in out if not path.startswith(".plumbline/")]
    if out and not strict_gitignored:
        exempt = _gitignored_untracked(repo, out)
        if exempt:
            # Visible, never silent (no-silent-caps rule): name what was skipped.
            print(
                "NOTE: ignoring gitignored+untracked tool artifacts (not feature edits): "
                + ", ".join(sorted(exempt))
            )
            out = [p for p in out if p not in exempt]
    if out:
        print(
            "ERROR: changed files outside Allowed change scope: "
            + ", ".join(out)
            + "; allowed: "
            + ", ".join(patterns)
            + f"; source={source}",
            file=sys.stderr,
        )
        return EXIT_VIOLATION
    print(
        f"PRIL scope check passed for feature '{feature}' "
        f"({len(changed)} changed files, source={source})"
    )
    return EXIT_PASS


def build_parser() -> argparse.ArgumentParser:
    parser = PlumblineArgumentParser(description="Validate changed files against a feature's allowed scope.")
    parser.add_argument("--repo", required=True, help="Repository root to inspect")
    parser.add_argument("--feature", required=True, help="Feature slug")
    parser.add_argument("--changed-files", required=True, help="File containing repo-relative changed paths")
    parser.add_argument(
        "--strict-gitignored",
        action="store_true",
        help="Also flag gitignored+untracked paths (default: exempted as tool artifacts, visibly logged)",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return validate_scope(
        Path(args.repo).resolve(),
        args.feature,
        Path(args.changed_files),
        strict_gitignored=args.strict_gitignored,
    )


if __name__ == "__main__":
    raise SystemExit(main())
