#!/usr/bin/env bash
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"
# shellcheck source=lib.sh
. "$HERE/lib.sh"

assert_file "release-please workflow exists" "$REPO_DIR/.github/workflows/release-please.yml"
assert_file "release-please config exists" "$REPO_DIR/release-please-config.json"
assert_file "release-please manifest exists" "$REPO_DIR/.release-please-manifest.json"
assert_file "changelog exists" "$REPO_DIR/CHANGELOG.md"
assert "workflow uses release-please v4" "grep -q 'googleapis/release-please-action@v4' '$REPO_DIR/.github/workflows/release-please.yml'"
assert "workflow grants contents write" "grep -q 'contents: write' '$REPO_DIR/.github/workflows/release-please.yml'"
assert "workflow grants pull request write" "grep -q 'pull-requests: write' '$REPO_DIR/.github/workflows/release-please.yml'"
assert "VERSION has release-please marker" "grep -q 'x-release-please-start-version' '$REPO_DIR/VERSION'"
assert "Conventional Commits are documented" "grep -q 'Conventional Commits' '$REPO_DIR/CONTRIBUTING.md'"

python3 - <<'PY' >/tmp/plumbline_release_please_check.txt
import json
from pathlib import Path
root=Path.cwd()
config=json.loads((root/'release-please-config.json').read_text())
manifest=json.loads((root/'.release-please-manifest.json').read_text())
compat=json.loads((root/'compatibility.json').read_text())
pkg=config['packages']['.']
extra=pkg['extra-files']
assert pkg['release-type']=='simple'
assert any(item.get('type')=='generic' and item.get('path')=='VERSION' for item in extra)
assert any(item.get('type')=='json' and item.get('path')=='compatibility.json' and item.get('jsonpath')=='$.version' for item in extra)
version=[l.strip() for l in (root/'VERSION').read_text().splitlines() if l.strip() and not l.startswith('#')][0]
assert manifest['.']==version, (manifest['.'], version)
assert compat['version']==version, (compat['version'], version)
print('release-please JSON OK')
PY
assert "release-please JSON wires VERSION and compatibility.json" "grep -q 'release-please JSON OK' /tmp/plumbline_release_please_check.txt"
rm -f /tmp/plumbline_release_please_check.txt

finish "release-please tests"
