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
from datetime import datetime
from pathlib import Path
from typing import Any

sys.path.insert(0, str(Path(__file__).resolve().parent))

from plumbline_cli import (  # noqa: E402  (path shim above must run first)
    PlumblineArgumentParser,
)

EXIT_PASS = 0
EXIT_MISSING = 2
EXIT_VIOLATION = 3
EXIT_MALFORMED = 4

SECTION_NAMES = ("allowed change scope", "allowed changes", "change scope")
MANIFEST_SCHEMA_VERSION = 1
PROVENANCE_FIELDS = (
    "revision",
    "origin",
    "decision_maker",
    "decided_at",
    "rationale",
    "confirmed",
    "scope",
    "scope_digest",
)

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


def _standard_manifest_error(manifest: Path, detail: str) -> int:
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
        return _standard_manifest_error(manifest, "file is not UTF-8 text"), {}
    except json.JSONDecodeError as exc:
        return _standard_manifest_error(manifest, f"invalid JSON ({exc.msg} at line {exc.lineno})"), {}

    if not isinstance(data, dict):
        return _standard_manifest_error(manifest, "top level must be a JSON object"), {}

    unknown = sorted(set(data) - MANIFEST_KEYS)
    if unknown:
        return _standard_manifest_error(
            manifest,
            f"unknown key(s) {', '.join(repr(k) for k in unknown)}; "
            f"supported: {', '.join(sorted(MANIFEST_KEYS))}",
        ), {}

    # An absent `schema` means the original v1 shape (the pre-PLUM-10 fixtures).
    schema = data.get("schema", MANIFEST_SCHEMA)
    if schema != MANIFEST_SCHEMA:
        return _standard_manifest_error(
            manifest,
            f"unsupported schema version {schema!r} (supported: {MANIFEST_SCHEMA})",
        ), {}

    declared = data.get("feature")
    if declared is not None and declared != feature:
        return _standard_manifest_error(
            manifest,
            f"declares feature {declared!r} but the check requested {feature!r}",
        ), {}

    raw = data.get("allowed_change_scope")
    if not isinstance(raw, list):
        return _standard_manifest_error(
            manifest, "'allowed_change_scope' must be a list of repo-relative paths/globs"
        ), {}

    def read_list(key: str, entries: object) -> tuple[int | None, list[str]]:
        if not isinstance(entries, list):
            return _standard_manifest_error(
                manifest, f"{key!r} must be a list of repo-relative paths/globs"
            ), []
        out: list[str] = []
        for index, item in enumerate(entries, start=1):
            label = f"entry #{index}" if key == "allowed_change_scope" else f"{key} entry #{index}"
            if not isinstance(item, str):
                return _standard_manifest_error(
                    manifest, f"{label} is not a string (got {type(item).__name__})"
                ), []
            candidate = item.strip()
            problem = _pattern_problem(candidate)
            if problem is not None:
                return _standard_manifest_error(manifest, f"{label} {item!r} {problem}"), []
            if _is_broad_pattern(candidate):
                return _standard_manifest_error(
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
        return _standard_manifest_error(manifest, "'provenance' must be a list of records"), {}

    return EXIT_PASS, {
        "product": product,
        "governance": governance,
        "provenance": provenance,
        "manifest": manifest,
    }


def _scope_digest(scope: dict[str, list[str]]) -> str:
    payload = json.dumps(scope, sort_keys=True, separators=(",", ":")).encode("utf-8")
    return "sha256:" + hashlib.sha256(payload).hexdigest()


def _glob_tokens(pattern: str) -> list[str]:
    """Tokenize the shell-style subset accepted by :mod:`fnmatch`."""

    tokens: list[str] = []
    index = 0
    while index < len(pattern):
        char = pattern[index]
        if char == "*":
            while index + 1 < len(pattern) and pattern[index + 1] == "*":
                index += 1
            tokens.append("*")
        elif char == "?":
            tokens.append("?")
        elif char == "[":
            closing_start = index + 1
            if closing_start < len(pattern) and pattern[closing_start] == "!":
                closing_start += 1
            if closing_start < len(pattern) and pattern[closing_start] == "]":
                closing_start += 1
            closing = pattern.find("]", closing_start)
            if closing >= 0:
                tokens.append(pattern[index : closing + 1])
                index = closing
            else:
                tokens.append("[")
        else:
            tokens.append(char)
        index += 1
    return tokens


def _token_characters(token: str, alphabet: set[str]) -> set[str]:
    if token in {"*", "?"}:
        return alphabet
    if token.startswith("[") and token.endswith("]"):
        return {char for char in alphabet if fnmatch.fnmatchcase(char, token)}
    return {token}


def _fnmatch_patterns_overlap(left: str, right: str) -> bool:
    """Decide whether two shell globs share a concrete path.

    ``*`` is modeled as the same zero-or-more-character NFA used by
    :mod:`fnmatch`. Product construction searches for an accepting state, so
    intersections such as ``src/*/foo`` versus ``src/bar/*`` are detected
    without relying on a guessed witness.
    """

    left_tokens = _glob_tokens(left)
    right_tokens = _glob_tokens(right)
    alphabet = {chr(code) for code in range(32, 127)}
    alphabet.update({"\x00", "\x1f", "\x7f", "\x80", "é", "Ā", "\u1000", "\U0010ffff"})
    for char in left + right:
        alphabet.add(char)
        codepoint = ord(char)
        if codepoint > 0:
            alphabet.add(chr(codepoint - 1))
        if codepoint < 0x10FFFF:
            alphabet.add(chr(codepoint + 1))
    left_chars = [_token_characters(token, alphabet) for token in left_tokens]
    right_chars = [_token_characters(token, alphabet) for token in right_tokens]

    pending = [(0, 0)]
    visited: set[tuple[int, int]] = set()
    while pending:
        left_index, right_index = pending.pop()
        state = (left_index, right_index)
        if state in visited:
            continue
        visited.add(state)
        if left_index == len(left_tokens) and right_index == len(right_tokens):
            return True
        if left_index < len(left_tokens) and left_tokens[left_index] == "*":
            pending.append((left_index + 1, right_index))
        if right_index < len(right_tokens) and right_tokens[right_index] == "*":
            pending.append((left_index, right_index + 1))
        if left_index == len(left_tokens) or right_index == len(right_tokens):
            continue
        if left_chars[left_index] & right_chars[right_index]:
            next_left = (
                left_index if left_tokens[left_index] == "*" else left_index + 1
            )
            next_right = (
                right_index if right_tokens[right_index] == "*" else right_index + 1
            )
            pending.append((next_left, next_right))
    return False


def _runtime_pattern_languages(pattern: str) -> list[str]:
    """Expand the prefix shortcuts implemented by :func:`_matches`."""

    stripped = pattern.strip()
    if stripped.endswith("/**"):
        base = stripped[:-3]
        return [base, f"{base}/*"]
    if stripped.endswith("/"):
        return [f"{stripped}*"]
    return [stripped]


def _patterns_overlap(left: str, right: str) -> bool:
    """Decide overlap using the exact runtime matching language."""

    return any(
        _fnmatch_patterns_overlap(left_language, right_language)
        for left_language in _runtime_pattern_languages(left)
        for right_language in _runtime_pattern_languages(right)
    )


def _rich_manifest_error(scope_json: Path, message: str) -> tuple[int, None]:
    print(f"ERROR: invalid canonical scope manifest {scope_json}: {message}", file=sys.stderr)
    return EXIT_MALFORMED, None


def _valid_manifest_path(value: object) -> bool:
    if not isinstance(value, str) or not value or value.startswith("/"):
        return False
    return (
        value == value.strip()
        and not any(char in value for char in ("\n", "\r", "\x00", "`"))
        and ".." not in Path(value).parts
    )


def _validate_scope_mapping(
    scope_json: Path, scope: object, *, label: str = "scope"
) -> tuple[int, dict[str, list[str]] | None]:
    if not isinstance(scope, dict):
        return _rich_manifest_error(scope_json, f"{label} must be an object")
    product = scope.get("product")
    governance = scope.get("governance")
    if not isinstance(product, list) or not isinstance(governance, list):
        return _rich_manifest_error(
            scope_json, f"{label}.product and {label}.governance must be arrays"
        )
    for category, patterns in (("product", product), ("governance", governance)):
        for index, pattern in enumerate(patterns):
            if not _valid_manifest_path(pattern):
                return _rich_manifest_error(
                    scope_json,
                    f"{label}.{category}[{index}] must be one clean repo-relative path or glob",
                )
        if len(patterns) != len(set(patterns)):
            return _rich_manifest_error(scope_json, f"{label}.{category} contains duplicate paths")
        broad = _reject_broad(patterns)
        if broad is not None:
            return broad, None
    for product_pattern in product:
        for governance_pattern in governance:
            if _patterns_overlap(product_pattern, governance_pattern):
                return _rich_manifest_error(
                    scope_json,
                    "paths overlap across product and governance: "
                    f"{product_pattern} <> {governance_pattern}",
                )
    return EXIT_PASS, {"product": list(product), "governance": list(governance)}


def validate_manifest_data(
    scope_json: Path, data: object, feature: str
) -> tuple[int, dict[str, Any] | None]:
    if not isinstance(data, dict):
        return _rich_manifest_error(scope_json, "top level must be an object")
    if data.get("schema_version") != MANIFEST_SCHEMA_VERSION:
        return _rich_manifest_error(
            scope_json, f"schema_version must be {MANIFEST_SCHEMA_VERSION}"
        )
    if data.get("feature") != feature:
        return _rich_manifest_error(
            scope_json, f"feature must equal requested feature {feature!r}"
        )

    scope_status, scope = _validate_scope_mapping(scope_json, data.get("scope"))
    if scope_status != EXIT_PASS or scope is None:
        return scope_status, None

    artifacts = data.get("artifacts")
    if not isinstance(artifacts, dict):
        return _rich_manifest_error(scope_json, "artifacts must be an object")
    for name in ("canvas", "plan"):
        if not _valid_manifest_path(artifacts.get(name)):
            return _rich_manifest_error(
                scope_json, f"artifacts.{name} must be a clean repo-relative file path"
            )
    expected_canvas = f"docs/canvas/{feature}.canvas.md"
    if artifacts["canvas"] != expected_canvas:
        return _rich_manifest_error(
            scope_json, f"artifacts.canvas must be {expected_canvas!r}"
        )

    provenance = data.get("provenance")
    if not isinstance(provenance, list) or not provenance:
        return _rich_manifest_error(scope_json, "provenance must contain at least one revision")
    for index, entry in enumerate(provenance, start=1):
        if not isinstance(entry, dict):
            return _rich_manifest_error(scope_json, f"provenance[{index - 1}] must be an object")
        missing = [field for field in PROVENANCE_FIELDS if field not in entry]
        if missing:
            return _rich_manifest_error(
                scope_json, f"provenance[{index - 1}] missing {missing[0]}"
            )
        if entry["revision"] != index:
            return _rich_manifest_error(
                scope_json, f"provenance revision must be contiguous; expected {index}"
            )
        for field in ("origin", "decision_maker", "decided_at", "rationale"):
            if not isinstance(entry[field], str) or not entry[field].strip():
                return _rich_manifest_error(
                    scope_json, f"provenance[{index - 1}].{field} must be non-empty"
                )
        if entry["confirmed"] is not True:
            return _rich_manifest_error(
                scope_json, f"provenance[{index - 1}].confirmed must be true"
            )
        try:
            decided_at = datetime.fromisoformat(entry["decided_at"].replace("Z", "+00:00"))
        except ValueError:
            return _rich_manifest_error(
                scope_json, f"provenance[{index - 1}].decided_at must be ISO-8601"
            )
        if decided_at.tzinfo is None:
            return _rich_manifest_error(
                scope_json, f"provenance[{index - 1}].decided_at must include a timezone"
            )
        historical_status, historical_scope = _validate_scope_mapping(
            scope_json,
            entry["scope"],
            label=f"provenance[{index - 1}].scope",
        )
        if historical_status != EXIT_PASS or historical_scope is None:
            return historical_status, None
        if entry["scope_digest"] != _scope_digest(historical_scope):
            return _rich_manifest_error(
                scope_json, f"provenance[{index - 1}].scope_digest does not match scope"
            )
    if provenance[-1]["scope"] != scope:
        return _rich_manifest_error(
            scope_json, "current scope must exactly match the last provenance revision"
        )

    manifest_path = f"docs/scope/{feature}.scope.json"
    governed_paths = {
        manifest_path,
        str(artifacts["canvas"]),
        str(artifacts["plan"]),
    }
    for path in sorted(governed_paths):
        product_match = any(_matches(path, pattern) for pattern in scope["product"])
        governance_match = any(_matches(path, pattern) for pattern in scope["governance"])
        if product_match or not governance_match:
            return _rich_manifest_error(
                scope_json,
                f"governance artifact must match governance scope only: {path}",
            )

    return EXIT_PASS, {
        "schema_version": MANIFEST_SCHEMA_VERSION,
        "feature": feature,
        "scope": scope,
        "artifacts": {
            "canvas": str(artifacts["canvas"]),
            "plan": str(artifacts["plan"]),
        },
        "provenance": provenance,
    }


def load_scope_manifest(
    repo: Path, feature: str
) -> tuple[int, dict[str, Any] | None]:
    scope_json = repo / "docs" / "scope" / f"{feature}.scope.json"
    if not scope_json.exists():
        return EXIT_MISSING, None
    try:
        data = json.loads(scope_json.read_text(encoding="utf-8"))
    except OSError as exc:
        return _rich_manifest_error(scope_json, f"cannot read file: {exc.strerror or exc}")
    except UnicodeDecodeError:
        return _rich_manifest_error(scope_json, "file is not UTF-8 text")
    except json.JSONDecodeError as exc:
        return _rich_manifest_error(scope_json, f"invalid JSON at line {exc.lineno}: {exc.msg}")
    # Backward-compatible legacy input. PLUM-10 owns its eventual migration;
    # PLUM-12 only makes versioned manifests canonical when one is present.
    if (
        isinstance(data, dict)
        and "allowed_change_scope" in data
        and "schema_version" not in data
    ):
        return EXIT_MISSING, None
    return validate_manifest_data(scope_json, data, feature)


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
        rich_status, rich = load_scope_manifest(repo, feature)
        if rich_status == EXIT_PASS and rich is not None:
            model = {
                "product": list(rich["scope"]["product"]),
                "governance": list(rich["scope"]["governance"]),
                "provenance": rich["provenance"],
                "manifest": manifest,
            }
            status = EXIT_PASS
        elif rich_status == EXIT_MALFORMED:
            return rich_status, {}, f"manifest={_rel(manifest, repo)}"
        else:
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
        rich_status, rich = load_scope_manifest(repo, feature)
        if rich_status == EXIT_PASS and rich is not None:
            status = EXIT_PASS
            model = rich["scope"]
        elif rich_status == EXIT_MALFORMED:
            return rich_status, [], f"manifest={_rel(manifest, repo)}"
        else:
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


def _safe_artifact(repo: Path, relative_path: str) -> Path | None:
    candidate = (repo / relative_path).resolve()
    try:
        candidate.relative_to(repo)
    except ValueError:
        return None
    return candidate


def _canvas_scope_lines(canvas: Path) -> tuple[int, list[str]]:
    try:
        lines = canvas.read_text(encoding="utf-8").splitlines()
    except FileNotFoundError:
        print(f"ERROR: missing Canvas artifact: {canvas}", file=sys.stderr)
        return EXIT_MISSING, []
    except OSError as exc:
        print(f"ERROR: cannot read Canvas artifact {canvas}: {exc}", file=sys.stderr)
        return EXIT_MALFORMED, []
    except UnicodeDecodeError:
        print(f"ERROR: Canvas is not UTF-8 text: {canvas}", file=sys.stderr)
        return EXIT_MALFORMED, []
    in_section = False
    body: list[str] = []
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
            body.append(line)
    return EXIT_PASS, body


def _planned_paths(
    plan: Path, *, text_override: str | None = None
) -> tuple[int, list[str]]:
    if text_override is None:
        try:
            lines = plan.read_text(encoding="utf-8").splitlines()
        except FileNotFoundError:
            print(f"ERROR: missing implementation plan: {plan}", file=sys.stderr)
            return EXIT_MISSING, []
        except OSError as exc:
            print(f"ERROR: cannot read implementation plan {plan}: {exc}", file=sys.stderr)
            return EXIT_MALFORMED, []
        except UnicodeDecodeError:
            print(f"ERROR: implementation plan is not UTF-8 text: {plan}", file=sys.stderr)
            return EXIT_MALFORMED, []
    else:
        lines = text_override.splitlines()
    planned: list[str] = []
    for lineno, line in enumerate(lines, start=1):
        match = re.search(r"\b(?:Create|Modify|Delete):\s*(.*)$", line)
        if not match:
            continue
        declaration = match.group(1)
        paths = re.findall(r"`([^`]+)`", declaration)
        if not paths:
            print(
                f"ERROR: planned-file declaration at {plan}:{lineno} must use backticks",
                file=sys.stderr,
            )
            return EXIT_MALFORMED, []
        remainder = re.sub(r"`[^`]+`", "", declaration)
        if remainder.strip(" \t,;"):
            print(
                f"ERROR: planned-file declaration at {plan}:{lineno} contains "
                "content outside backtick-wrapped paths",
                file=sys.stderr,
            )
            return EXIT_MALFORMED, []
        for path in paths:
            if not _valid_manifest_path(path):
                print(
                    f"ERROR: invalid planned file at {plan}:{lineno}: {path!r}",
                    file=sys.stderr,
                )
                return EXIT_MALFORMED, []
            planned.append(path)
    if not planned:
        print(
            f"ERROR: implementation plan has no `Create:`, `Modify:` or `Delete:` file declarations: {plan}",
            file=sys.stderr,
        )
        return EXIT_MISSING, []
    return EXIT_PASS, planned


def _declared_values(
    plan: Path, label: str, *, text_override: str | None = None
) -> tuple[int, list[str]]:
    try:
        lines = (
            text_override.splitlines()
            if text_override is not None
            else plan.read_text(encoding="utf-8").splitlines()
        )
    except (OSError, UnicodeError) as exc:
        print(f"ERROR: cannot read implementation plan {plan}: {exc}", file=sys.stderr)
        return EXIT_MALFORMED, []
    values: list[str] = []
    for lineno, line in enumerate(lines, start=1):
        match = re.search(rf"\b{re.escape(label)}:\s*(.*)$", line)
        if not match:
            continue
        declaration = match.group(1)
        wrapped = re.findall(r"`([^`]+)`", declaration)
        remainder = re.sub(r"`[^`]+`", "", declaration)
        if not wrapped or remainder.strip(" \t,;"):
            print(
                f"ERROR: {label} declaration at {plan}:{lineno} must contain only backtick-wrapped values",
                file=sys.stderr,
            )
            return EXIT_MALFORMED, []
        values.extend(wrapped)
    return EXIT_PASS, values


def validate_manifest_artifacts(
    repo: Path,
    feature: str,
    manifest: dict[str, Any],
    *,
    canvas_override: str | None = None,
    plan_override: str | None = None,
    write_target: str | None = None,
    plan_text_override: str | None = None,
    test_command: str | None = None,
    delete_target: str | None = None,
    allow_runtime_maintenance: bool = False,
) -> int:
    artifacts = manifest["artifacts"]
    canvas_rel = canvas_override or artifacts["canvas"]
    plan_rel = plan_override or artifacts["plan"]
    for label, path in (("Canvas", canvas_rel), ("plan", plan_rel)):
        if not _valid_manifest_path(path):
            print(f"ERROR: {label} path is not repo-relative: {path!r}", file=sys.stderr)
            return EXIT_MALFORMED
    if canvas_rel != artifacts["canvas"]:
        print(
            f"ERROR: Canvas path contradicts manifest: {canvas_rel}; expected {artifacts['canvas']}",
            file=sys.stderr,
        )
        return EXIT_VIOLATION
    if plan_rel != artifacts["plan"]:
        print(
            f"ERROR: plan path contradicts manifest: {plan_rel}; expected {artifacts['plan']}",
            file=sys.stderr,
        )
        return EXIT_VIOLATION

    canvas = _safe_artifact(repo, canvas_rel)
    plan = _safe_artifact(repo, plan_rel)
    if canvas is None or plan is None:
        print("ERROR: scope artifact resolves outside repository", file=sys.stderr)
        return EXIT_MALFORMED

    canvas_status, canvas_lines = _canvas_scope_lines(canvas)
    if canvas_status != EXIT_PASS:
        return canvas_status
    manifest_rel = f"docs/scope/{feature}.scope.json"
    manifest_path = _safe_artifact(repo, manifest_rel)
    if manifest_path is None:
        print("ERROR: canonical scope manifest resolves outside repository", file=sys.stderr)
        return EXIT_MALFORMED
    manifest_control_rel = manifest_path.relative_to(repo).as_posix()
    expected_reference = f"Scope manifest: `{manifest_rel}`"
    if not any(line.strip() == expected_reference for line in canvas_lines):
        print(
            f"ERROR: Canvas must reference canonical manifest exactly as: {expected_reference}",
            file=sys.stderr,
        )
        return EXIT_VIOLATION
    duplicated = [
        pattern
        for pattern in (
            _candidate_pattern(line)
            for line in canvas_lines
            if line.strip().startswith(("-", "*", "+"))
        )
        if pattern and not pattern.startswith("Scope manifest:")
    ]
    if duplicated:
        print(
            "ERROR: Canvas contains duplicated scope path outside canonical manifest: "
            + duplicated[0],
            file=sys.stderr,
        )
        return EXIT_VIOLATION

    plan_status, planned = _planned_paths(plan, text_override=plan_text_override)
    if plan_status != EXIT_PASS:
        return plan_status
    declared_actions: dict[str, set[str]] = {}
    for action in ("Create", "Modify", "Delete"):
        action_status, action_paths = _declared_values(
            plan, action, text_override=plan_text_override
        )
        if action_status != EXIT_PASS:
            return action_status
        try:
            declared_actions[action] = {
                (repo / path).resolve().relative_to(repo).as_posix()
                for path in action_paths
            }
        except (OSError, ValueError):
            print(
                f"ERROR: planned {action} target resolves outside repository",
                file=sys.stderr,
            )
            return EXIT_MALFORMED
    action_names = tuple(declared_actions)
    for index, left in enumerate(action_names):
        for right in action_names[index + 1 :]:
            conflicts = declared_actions[left] & declared_actions[right]
            if conflicts:
                conflict = sorted(conflicts)[0]
                print(
                    f"ERROR: planned path has conflicting actions {left} and {right}: {conflict}",
                    file=sys.stderr,
                )
                return EXIT_MALFORMED
    test_status, test_commands = _declared_values(
        plan, "Test", text_override=plan_text_override
    )
    if test_status != EXIT_PASS:
        return test_status
    if test_command is not None and test_command not in test_commands:
        print(
            f"ERROR: Bash command is not declared as a confirmed Test in the implementation plan: {test_command}",
            file=sys.stderr,
        )
        return EXIT_VIOLATION
    if delete_target is not None:
        delete_paths = declared_actions["Delete"]
        delete_path = Path(delete_target)
        if not delete_path.is_absolute():
            delete_path = repo / delete_path
        try:
            delete_rel = delete_path.resolve().relative_to(repo).as_posix()
            normalized_deletes = delete_paths
        except (OSError, ValueError):
            print(
                f"ERROR: deletion target resolves outside repository: {delete_target}",
                file=sys.stderr,
            )
            return EXIT_VIOLATION
        if delete_rel not in normalized_deletes:
            print(
                f"ERROR: deletion target is not declared with Delete in the implementation plan: {delete_target}",
                file=sys.stderr,
            )
            return EXIT_VIOLATION
        reserved = {
            manifest_control_rel,
            plan.relative_to(repo).as_posix(),
            "docs/context/.active-feature",
            "config/claude/bin/plumbline-scope-check",
            "config/claude/bin/plumbline-scope-update",
            "config/claude/lib/plumbline_python.sh",
            "config/claude/lib/plumbline_scope.py",
            "config/claude/lib/plumbline_scope_update.py",
        }
        if delete_rel in reserved:
            print(
                f"ERROR: deletion of canonical scope control artifact is forbidden: {delete_rel}",
                file=sys.stderr,
            )
            return EXIT_VIOLATION
    if write_target is not None:
        target = Path(write_target)
        if not target.is_absolute():
            target = repo / target
        try:
            target_rel = target.resolve().relative_to(repo).as_posix()
        except (OSError, ValueError):
            print(
                f"ERROR: write target resolves outside repository: {write_target}",
                file=sys.stderr,
            )
            return EXIT_VIOLATION
        reserved = {
            manifest_control_rel,
            plan.relative_to(repo).as_posix(),
            "docs/context/.active-feature",
            "config/claude/bin/plumbline-scope-check",
            "config/claude/bin/plumbline-scope-update",
            "config/claude/lib/plumbline_python.sh",
            "config/claude/lib/plumbline_scope.py",
            "config/claude/lib/plumbline_scope_update.py",
        }
        runtime = {
            "config/claude/bin/plumbline-scope-check",
            "config/claude/bin/plumbline-scope-update",
            "config/claude/lib/plumbline_python.sh",
            "config/claude/lib/plumbline_scope.py",
            "config/claude/lib/plumbline_scope_update.py",
        }
        if target_rel in reserved and not (
            allow_runtime_maintenance and target_rel in runtime
        ):
            print(
                "ERROR: direct writes to canonical scope control artifacts are reserved for plumbline-scope-update",
                file=sys.stderr,
            )
            return EXIT_VIOLATION
        writable_paths = declared_actions["Create"] | declared_actions["Modify"]
        if target_rel not in writable_paths:
            print(
                f"ERROR: write target is not declared with Create or Modify in implementation plan: {target_rel}",
                file=sys.stderr,
            )
            return EXIT_VIOLATION
    product = manifest["scope"]["product"]
    governance = manifest["scope"]["governance"]
    for path in planned:
        product_match = any(_matches(path, pattern) for pattern in product)
        governance_match = any(_matches(path, pattern) for pattern in governance)
        if product_match and governance_match:
            print(
                f"ERROR: planned path matches both product and governance scope: {path}",
                file=sys.stderr,
            )
            return EXIT_MALFORMED
        if not product_match and not governance_match:
            print(
                f"ERROR: planned file outside canonical scope: {path}",
                file=sys.stderr,
            )
            return EXIT_VIOLATION
    print(
        f"PRIL scope preflight passed for feature '{feature}' "
        f"({len(planned)} planned files)"
    )
    return EXIT_PASS


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


AUTHORITY_DIRNAME = ".plumbline/scope-authority"
AUTHORITY_TOKEN = "SCOPE_AUTHORITY_CHANGED"


def authority_path(repo: Path, feature: str) -> Path:
    """Where the run baseline for a feature's scope authority is bound."""
    return repo / ".plumbline" / "scope-authority" / f"{feature}.json"


def _digest(path: Path) -> str | None:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError:
        return None


def check_scope_authority(repo: Path, feature: str) -> str | None:
    """Bind the active scope manifest on arming; refuse any later change.

    OPEN-2. The manifest is the artifact that decides what may change, and it was
    itself writable by the agent being judged. Adding the exact out-of-scope path
    to it inside the run and declaring both files passed with a success message:
    the authority ratified its own widening. The `**` guard caught only the
    wildcard form; the targeted form -- the realistic one -- went straight
    through.

    So the manifest is pinned for the life of an armed run. The first run binds
    its path and digest; every later run compares. A change, a replacement or a
    deletion is refused and classified, and the changed manifest never gets to
    authorize its own change.

    A legitimate scope change is therefore not a file edit. It is: end/disarm the
    run (remove the bound baseline), confirm the new scope with the human, re-arm.
    Provenance recorded *inside* the same mutable file cannot carry that -- an
    attacker who can edit the scope can edit its audit trail in the same write.

    Returns an error message on violation, or None when the run may proceed.
    """
    manifest = manifest_path(repo, feature)
    current = _digest(manifest)
    baseline = authority_path(repo, feature)

    if baseline.exists():
        try:
            data = json.loads(baseline.read_text(encoding="utf-8"))
            bound_digest = data["digest"]
            bound_path = data["path"]
        except (OSError, ValueError, KeyError, TypeError):
            return (
                f"{AUTHORITY_TOKEN}: the bound scope baseline {baseline} is unreadable, "
                "so the active scope authority cannot be proven unchanged. Disarm the "
                "run (remove the baseline), re-confirm the scope, and re-arm."
            )
        if current is None:
            return (
                f"{AUTHORITY_TOKEN}: the bound scope manifest {bound_path} is gone. "
                "An armed run cannot lose the artifact that defines its authority. "
                "Disarm the run, re-confirm the scope, and re-arm."
            )
        if current != bound_digest:
            return (
                f"{AUTHORITY_TOKEN}: {bound_path} changed during an armed run "
                f"(bound {bound_digest[:12]}, now {current[:12]}). A manifest never "
                "authorizes its own change. Disarm the run, have the new scope "
                "confirmed, then re-arm."
            )
        return None

    # Arming. Nothing to bind when the feature has no manifest at all: that
    # feature is governed by the legacy canvas source and this check must not
    # invent a red for it.
    if current is None:
        return None

    try:
        baseline.parent.mkdir(parents=True, exist_ok=True)
        payload = {
            "schema": 1,
            "feature": feature,
            "path": _rel(manifest, repo),
            "digest": current,
        }
        baseline.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
    except OSError as exc:
        # Visible, never silent. Refusing to run here would invent a new false
        # red for read-only checkouts; pretending the run is pinned would be a
        # false green. Say which one the operator has.
        print(
            f"NOTE: could not bind the scope authority baseline ({exc}); this run is "
            "NOT pinned against an in-run manifest change.",
            file=sys.stderr,
        )
    return None


def validate_scope(repo: Path, feature: str, changed_files: Path, strict_gitignored: bool = False) -> int:
    if not _valid_feature(feature):
        print(f"ERROR: malformed feature slug: {feature!r}", file=sys.stderr)
        return EXIT_MALFORMED
    authority_error = check_scope_authority(repo, feature)
    if authority_error is not None:
        print(f"ERROR: {authority_error}", file=sys.stderr)
        return EXIT_VIOLATION
    status, patterns, source = load_allowed_scope(repo, feature)
    if status != EXIT_PASS:
        return status
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
    parser.add_argument("--changed-files", help="File containing repo-relative changed paths")
    parser.add_argument(
        "--preflight",
        action="store_true",
        help="Validate canonical manifest, Canvas reference and planned files before coding",
    )
    parser.add_argument("--plan", help="Explicit plan path to validate against the manifest")
    parser.add_argument("--canvas", help="Explicit Canvas path to validate against the manifest")
    parser.add_argument(
        "--write-target",
        help="Concrete Write/Edit target, which must be declared exactly in the implementation plan",
    )
    parser.add_argument("--test-command", help="Bash test command, requiring an exact `Test:` plan declaration")
    parser.add_argument("--delete-target", help="Deletion target, requiring an exact `Delete:` plan declaration")
    parser.add_argument(
        "--allow-runtime-maintenance",
        action="store_true",
        help=argparse.SUPPRESS,
    )
    parser.add_argument(
        "--strict-gitignored",
        action="store_true",
        help="Also flag gitignored+untracked paths (default: exempted as tool artifacts, visibly logged)",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    repo = Path(args.repo).resolve()
    if (
        not args.changed_files
        and not args.preflight
        and not args.plan
        and not args.canvas
        and not args.write_target
        and not args.test_command
        and not args.delete_target
    ):
        print(
            "ERROR: provide --changed-files and/or --preflight/--plan/--canvas",
            file=sys.stderr,
        )
        return EXIT_MISSING
    if (
        args.preflight
        or args.plan
        or args.canvas
        or args.write_target
        or args.test_command
        or args.delete_target
    ):
        manifest_status, manifest = load_scope_manifest(repo, args.feature)
        if manifest_status == EXIT_MISSING:
            print(
                f"ERROR: missing canonical scope manifest for preflight: "
                f"docs/scope/{args.feature}.scope.json",
                file=sys.stderr,
            )
            return EXIT_MISSING
        if manifest_status != EXIT_PASS or manifest is None:
            return manifest_status
        preflight_status = validate_manifest_artifacts(
            repo,
            args.feature,
            manifest,
            canvas_override=args.canvas,
            plan_override=args.plan,
            write_target=args.write_target,
            test_command=args.test_command,
            delete_target=args.delete_target,
            allow_runtime_maintenance=args.allow_runtime_maintenance,
        )
        if preflight_status != EXIT_PASS:
            return preflight_status
    if args.changed_files:
        return validate_scope(
            repo,
            args.feature,
            Path(args.changed_files),
            strict_gitignored=args.strict_gitignored,
        )
    return EXIT_PASS


if __name__ == "__main__":
    raise SystemExit(main())
