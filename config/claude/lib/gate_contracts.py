#!/usr/bin/env python3
"""Deterministic, read-only helpers for the /agileteam gate contract tests (G1/G3/G4).

No model calls. Exits non-zero on parse failure so the bash harness can assert.

Subcommands:
  roster-roles <manifest> [minimum|specialists|all]
      Print roster roles (default all), one per line, sorted. Exit 1 if malformed.
  prose-specialists <agileteam.md>
      Print the backtick-quoted specialist names on the orchestrator's dynamic-add
      line(s) (those mentioning "domain role"), one per line, sorted.
  resolve-roster <manifest> <repo-root>
      Print roster roles that do NOT resolve to an in-repo agent `name:` (quote-aware).
      Exit 1 if any unresolved, else 0.
"""
from __future__ import annotations
import glob
import importlib.util
import os
import re
import sys

yaml = None
if importlib.util.find_spec("yaml") is not None:  # pragma: no cover - CI installs PyYAML
    import yaml  # type: ignore[import-not-found]


def _read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def _load_simple_roster_manifest(raw):
    """Parse the small roster YAML subset used by the G4 contract fixtures.

    CI installs PyYAML, but this fallback keeps `run_all.sh` deterministic in local
    or stripped-down environments. It intentionally supports only top-level keys
    whose values are dash lists, which is the complete roster contract shape.
    """
    data = {}
    current = None
    for lineno, original in enumerate(raw.splitlines(), start=1):
        line = original.split("#", 1)[0].rstrip()
        if not line.strip():
            continue
        if not line[:1].isspace() and line.endswith(":"):
            current = line[:-1].strip()
            if not current:
                raise ValueError(f"empty roster key on line {lineno}")
            data[current] = []
            continue
        stripped = line.strip()
        if stripped.startswith("- ") and current is not None:
            role = stripped[2:].strip().strip('"').strip("'")
            if not role:
                raise ValueError(f"empty roster role on line {lineno}")
            data[current].append(role)
            continue
        raise ValueError(
            f"unsupported roster YAML on line {lineno}: {original} "
            "(the built-in simple parser only supports a limited subset of roster YAML; "
            "install PyYAML to use full YAML syntax)"
        )
    return data


def _load_manifest(path):
    raw = _read(path)
    if yaml is not None:
        data = yaml.safe_load(raw)
    else:
        data = _load_simple_roster_manifest(raw)
    if not isinstance(data, dict):
        raise ValueError("roster manifest is not a mapping")
    return data


def roster_roles(path, section="all"):
    try:
        data = _load_manifest(path)
    except Exception as e:  # noqa: BLE001
        print(f"malformed manifest: {e}", file=sys.stderr)
        return 1
    keys = ("minimum", "specialists") if section == "all" else (section,)
    roles = []
    for key in keys:
        roles.extend(data.get(key) or [])
    for r in sorted(set(roles)):
        print(r)
    return 0


def prose_specialists(path):
    names = set()
    for line in _read(path).splitlines():
        if "domain role" in line.lower():
            names.update(re.findall(r"`([a-z][a-z0-9-]+)`", line))
    for n in sorted(names):
        print(n)
    return 0


def _name_exists(root, role):
    # Accept single OR double quotes around the value, mirroring the repo's own
    # frontmatter validator (run_all.sh strips both " and ' before comparing).
    pat = re.compile(r"""^name:\s*["']?""" + re.escape(role) + r"""["']?\s*$""")
    for path in glob.glob(os.path.join(root, "**", "*.md"), recursive=True):
        if f"{os.sep}explorer{os.sep}" in path:
            continue
        try:
            text = _read(path)
        except (OSError, UnicodeDecodeError):
            continue
        m = re.match(r"^---\n(.*?)\n---", text, re.S)
        if not m:
            continue
        if any(pat.match(line.strip()) for line in m.group(1).splitlines()):
            return True
    return False


def resolve_roster(manifest, root):
    try:
        data = _load_manifest(manifest)
    except Exception as e:  # noqa: BLE001
        print(f"malformed manifest: {e}", file=sys.stderr)
        return 1
    roles = sorted(set((data.get("minimum") or []) + (data.get("specialists") or [])))
    unresolved = [r for r in roles if not _name_exists(root, r)]
    for r in unresolved:
        print(r)
    return 1 if unresolved else 0


def main(argv):
    if len(argv) < 3:
        print(__doc__, file=sys.stderr)
        return 2
    cmd, rest = argv[1], argv[2:]
    try:
        if cmd == "roster-roles" and len(rest) in (1, 2):
            return roster_roles(rest[0], rest[1] if len(rest) == 2 else "all")
        if cmd == "prose-specialists" and len(rest) == 1:
            return prose_specialists(rest[0])
        if cmd == "resolve-roster" and len(rest) == 2:
            return resolve_roster(rest[0], rest[1])
    except OSError as e:
        # Uniform clean error surface (no traceback); keep exit non-zero so the
        # harness's `! ...` assertions still hold.
        print(f"{cmd}: {e}", file=sys.stderr)
        return 1
    print(f"unknown/invalid subcommand: {argv[1:]}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
