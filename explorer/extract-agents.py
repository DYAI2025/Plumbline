#!/usr/bin/env python3
"""Extract agent frontmatter from a Claude agents directory into JSON (stdout).

Usage: python3 extract-agents.py [AGENTS_DIR]   (default: current directory)
Progress goes to stderr; only the JSON array is written to stdout.
"""
import glob
import json
import os
import re
import sys

try:
    import yaml
except ImportError:
    sys.exit(
        "PyYAML required. Install it for this interpreter:\n"
        "  python3 -m pip install pyyaml\n"
        "  # PEP-668 (externally-managed) python, e.g. system python3 on macOS/Debian:\n"
        "  python3 -m pip install --user --break-system-packages pyyaml\n"
        "  # or run under a venv / uv that has it."
    )

root = sys.argv[1] if len(sys.argv) > 1 else "."
os.chdir(root)

agents = []
for path in sorted(glob.glob("**/*.md", recursive=True)):
    # Skip docs, metrics and the explorer's own sources. `config/` holds vendored
    # skills + slash-commands (not subagents) and `docs/`/`metrics/` are prose, so
    # they must not be counted as agents.
    if (
        path in ("README.md", "SETUP.md", "CLAUDE.md")
        or path.startswith(("explorer/", "config/", "docs/", "metrics/"))
        or "/proposed/" in path          # concilium/proposed = draft, not-active agents
        or "/reports/" in path           # concilium/reports = prose, not agents
        or "/characters/" in path        # concilium/characters = role/preset CHARACTER SKILLS, not agents
    ):
        continue
    cat = path.split("/")[0] if "/" in path else "(root)"
    m = re.match(r"^---\n(.*?)\n---(.*)$", open(path, encoding="utf-8").read(), re.S)
    if not m:
        continue
    try:
        d = yaml.safe_load(m.group(1))
    except Exception as e:  # noqa: BLE001
        print(f"skip (parse error): {path}: {e}", file=sys.stderr)
        continue
    if not isinstance(d, dict):
        continue
    body = m.group(2).strip()
    caps = d.get("capabilities", {}) if isinstance(d.get("capabilities"), dict) else {}
    tools = d.get("tools") or caps.get("allowed_tools") or []
    if isinstance(tools, str):
        tools = [tools]
    trig = d.get("triggers", {}) if isinstance(d.get("triggers"), dict) else {}
    kw = trig.get("keywords") or []
    meta = d.get("metadata", {}) if isinstance(d.get("metadata"), dict) else {}
    schema = (
        "standard"
        if "triggers" in d or "capabilities" in d
        else ("claude-flow" if ("tools" in d or "priority" in d) else "minimal")
    )
    agents.append(
        {
            "name": d.get("name", ""),
            "description": d.get("description", "") or meta.get("description", ""),
            "category": cat,
            "file": path,
            "type": d.get("type", ""),
            "color": str(d.get("color", "")),
            "tools": [str(t) for t in tools][:24],
            "keywords": [str(k) for k in kw][:12],
            "specialization": meta.get("specialization", ""),
            "complexity": str(meta.get("complexity", "")),
            "schema": schema,
            "bodyChars": len(body),
        }
    )

agents.sort(key=lambda a: (a["category"], a["name"]))
json.dump(agents, sys.stdout, ensure_ascii=False, indent=0)
print(f"extracted {len(agents)} agents", file=sys.stderr)
