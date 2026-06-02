#!/usr/bin/env python3
"""Plumbline Runtime Integrity Layer scope guard."""
from __future__ import annotations

import argparse
import fnmatch
import json
import sys
from pathlib import Path

EXIT_PASS = 0
EXIT_MISSING = 2
EXIT_VIOLATION = 3
EXIT_MALFORMED = 4

SECTION_NAMES = ("allowed change scope", "allowed changes", "change scope")


def _is_broad_pattern(pattern: str) -> bool:
    """A pattern is "broad" if it has no concrete path segment to anchor on.

    A self-authored scope must not legitimize *every* path with a single
    wildcard line: a bare ``*``, ``**``, ``.``, ``/`` or ``**/*`` matches the
    whole repo and silently defeats the scope guard. We treat a pattern as broad
    when, after stripping glob tokens (``*``, ``**``), separators and ``.``, no
    literal path segment remains. Legitimate patterns keep a concrete anchor:
    ``src/billing/**`` -> ``src``/``billing``; ``config/claude/*.py`` ->
    ``config``/``claude``/``.py``.
    """
    candidate = pattern.strip().strip("/")
    if not candidate:
        return True
    for segment in candidate.split("/"):
        # A segment contributes a concrete anchor iff it has any non-glob,
        # non-dot character (so ``*``, ``**`` and ``.`` are NOT anchors, but
        # ``*.py`` is, via its ``py`` literal).
        if segment.replace("*", "").replace(".", "").strip():
            return False
    return True


def _rel(path: Path, repo: Path) -> str:
    try:
        return str(path.relative_to(repo))
    except ValueError:
        return str(path)


def _valid_feature(feature: str) -> bool:
    return bool(feature) and "/" not in feature and "\\" not in feature and feature not in {".", ".."}


def _clean_pattern(line: str) -> str | None:
    stripped = line.strip()
    if not stripped or stripped.startswith("#"):
        return None
    for prefix in ("- [ ]", "- [x]", "-", "*", "+"):
        if stripped.startswith(prefix):
            stripped = stripped[len(prefix):].strip()
            break
    if "#" in stripped:
        stripped = stripped.split("#", 1)[0].strip()
    stripped = stripped.strip("` ").strip()
    if not stripped or stripped.upper() in {"MISSING", "OPEN QUESTION", "BLOCKER"}:
        return None
    if stripped.startswith("/") or ".." in Path(stripped).parts:
        return None
    return stripped


def _patterns_from_canvas(canvas: Path) -> tuple[int, list[str]]:
    try:
        lines = canvas.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        return EXIT_MISSING, []
    except UnicodeDecodeError:
        print(f"ERROR: malformed canvas is not UTF-8 text: {canvas}", file=sys.stderr)
        return EXIT_MALFORMED, []

    in_section = False
    patterns: list[str] = []
    for line in lines:
        heading = line.strip().lstrip("#").strip().lower()
        if line.lstrip().startswith("#"):
            if in_section:
                break
            normalized_heading = heading
            if "." in normalized_heading:
                before, after = normalized_heading.split(".", 1)
                if before.strip().isdigit():
                    normalized_heading = after.strip()
            if normalized_heading in SECTION_NAMES:
                in_section = True
            continue
        if in_section:
            stripped = line.strip()
            if not stripped.startswith(("-", "*", "+")):
                continue
            pattern = _clean_pattern(line)
            if pattern:
                patterns.append(pattern)
    if not patterns:
        return EXIT_MISSING, []
    return EXIT_PASS, patterns


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
            pattern = _clean_pattern(item)
            if pattern and pattern != feature:
                patterns.append(pattern)
    return patterns


def _patterns_from_json(scope_json: Path) -> tuple[int, list[str]]:
    if not scope_json.exists():
        return EXIT_MISSING, []
    try:
        data = json.loads(scope_json.read_text(encoding="utf-8"))
    except UnicodeDecodeError:
        print(f"ERROR: malformed scope JSON is not UTF-8 text: {scope_json}", file=sys.stderr)
        return EXIT_MALFORMED, []
    except json.JSONDecodeError as exc:
        print(f"ERROR: invalid scope JSON in {scope_json}: {exc.msg}", file=sys.stderr)
        return EXIT_MALFORMED, []
    raw = data.get("allowed_change_scope") if isinstance(data, dict) else None
    if not isinstance(raw, list):
        print(f"ERROR: scope JSON missing allowed_change_scope list: {scope_json}", file=sys.stderr)
        return EXIT_MALFORMED, []
    patterns = [p for p in (_clean_pattern(str(item)) for item in raw) if p]
    return (EXIT_PASS if patterns else EXIT_MISSING), patterns


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


def load_allowed_scope(repo: Path, feature: str) -> tuple[int, list[str]]:
    canvas = repo / "docs" / "canvas" / f"{feature}.canvas.md"
    status, patterns = _patterns_from_canvas(canvas)
    if status == EXIT_PASS:
        broad = _reject_broad(patterns)
        return (broad, []) if broad is not None else (status, patterns)
    if status == EXIT_MALFORMED:
        return status, []

    trace_patterns = _patterns_from_traceability(repo / "docs" / "traceability.md", feature)
    if trace_patterns:
        broad = _reject_broad(trace_patterns)
        return (broad, []) if broad is not None else (EXIT_PASS, trace_patterns)

    json_status, json_patterns = _patterns_from_json(repo / "docs" / "scope" / f"{feature}.scope.json")
    if json_status == EXIT_PASS:
        broad = _reject_broad(json_patterns)
        return (broad, []) if broad is not None else (json_status, json_patterns)
    if json_status == EXIT_MALFORMED:
        return json_status, []

    print(
        "ERROR: missing Allowed change scope for feature "
        f"'{feature}'; add docs/canvas/{feature}.canvas.md section 'Allowed change scope' "
        f"or docs/scope/{feature}.scope.json",
        file=sys.stderr,
    )
    return EXIT_MISSING, []


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


def validate_scope(repo: Path, feature: str, changed_files: Path) -> int:
    if not _valid_feature(feature):
        print(f"ERROR: malformed feature slug: {feature!r}", file=sys.stderr)
        return EXIT_MALFORMED
    status, patterns = load_allowed_scope(repo, feature)
    if status != EXIT_PASS:
        return status
    changed_status, changed = _load_changed_files(changed_files)
    if changed_status != EXIT_PASS:
        return changed_status
    out = [path for path in changed if not any(_matches(path, pattern) for pattern in patterns)]
    if out:
        print(
            "ERROR: changed files outside Allowed change scope: "
            + ", ".join(out)
            + "; allowed: "
            + ", ".join(patterns),
            file=sys.stderr,
        )
        return EXIT_VIOLATION
    print(f"PRIL scope check passed for feature '{feature}' ({len(changed)} changed files)")
    return EXIT_PASS


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Validate changed files against a feature's allowed scope.")
    parser.add_argument("--repo", required=True, help="Repository root to inspect")
    parser.add_argument("--feature", required=True, help="Feature slug")
    parser.add_argument("--changed-files", required=True, help="File containing repo-relative changed paths")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    return validate_scope(Path(args.repo).resolve(), args.feature, Path(args.changed_files))


if __name__ == "__main__":
    raise SystemExit(main())
