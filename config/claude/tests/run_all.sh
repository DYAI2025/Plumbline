#!/usr/bin/env bash
#
# CI entrypoint: run the whole claude-agents check suite. Exits non-zero if any
# stage fails. Used by .github/workflows/ci.yml and runnable locally:
#
#   bash config/claude/tests/run_all.sh
#
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"
cd "$REPO_DIR" || exit 1

fail=0
stage() { printf '\n=== %s ===\n' "$1"; }

stage "agent frontmatter validation (parse / description / duplicate names)"
python3 - <<'PY' || fail=1
import re, glob, collections, sys
try:
    import yaml
except ImportError:
    sys.exit("PyYAML required (pip install pyyaml)")
names = collections.Counter(); bad = []; nodesc = []
for p in sorted(glob.glob("**/*.md", recursive=True)):
    if p.startswith("explorer/"):
        continue
    m = re.match(r"^---\n(.*?)\n---", open(p, encoding="utf-8").read(), re.S)
    if not m:
        continue
    try:
        d = yaml.safe_load(m.group(1))
    except Exception as e:  # noqa: BLE001
        bad.append((p, str(e).splitlines()[0])); continue
    if not isinstance(d, dict):
        bad.append((p, "frontmatter not a mapping")); continue
    if "description" not in d:
        nodesc.append(p)
    if d.get("name"):
        names[d["name"]] += 1
dupes = {k: v for k, v in names.items() if v > 1}
print("parse failures:", bad or "none")
print("missing description:", nodesc or "none")
print("duplicate names:", dupes or "none")
if bad or nodesc or dupes:
    sys.exit(1)
PY

stage "metrics scripts compile"
python3 -m py_compile config/claude/metrics/emit_run.py config/claude/metrics/process_health.py \
  && echo "py_compile OK" || fail=1

stage "settings JSON validity (.claude/settings.json)"
jq -e . .claude/settings.json >/dev/null && echo ".claude/settings.json OK" || fail=1

stage "stop hook tests"
bash config/claude/tests/test_stop_hook.sh || fail=1

stage "web bootstrap tests"
bash config/claude/tests/test_web_bootstrap.sh || fail=1

if command -v shellcheck >/dev/null 2>&1; then
  stage "shellcheck (hooks + install + tests)"
  shellcheck -x -P SCRIPTDIR \
    config/claude/hooks/*.sh \
    config/claude/install.sh \
    config/claude/tests/*.sh && echo "shellcheck OK" || fail=1
else
  printf '\n=== shellcheck skipped (not installed) ===\n'
fi

printf '\n========================================\n'
if [ "$fail" -eq 0 ]; then
  echo "ALL CHECKS PASSED"
else
  echo "CHECKS FAILED"
fi
exit "$fail"
