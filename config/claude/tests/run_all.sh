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
    import yaml  # type: ignore[import-not-found]
except ImportError:
    yaml = None

def parse_frontmatter(raw):
    if yaml is not None:
        return yaml.safe_load(raw)
    # Dependency-free fallback for the flat frontmatter used by agent prompts.
    data = {}
    for lineno, line in enumerate(raw.splitlines(), start=1):
        if not line.strip() or line.lstrip().startswith("#"):
            continue
        if line[:1].isspace():
            # Ignore nested YAML details in the fallback; this validator only needs
            # top-level name/description presence and duplicate names.
            continue
        if ":" not in line:
            raise ValueError(f"unsupported frontmatter line {lineno}: {line}")
        key, value = line.split(":", 1)
        key = key.strip()
        value = value.strip().strip('"').strip("'")
        if not key:
            raise ValueError(f"empty frontmatter key on line {lineno}")
        data[key] = value
    return data

names = collections.Counter(); bad = []; nodesc = []
for p in sorted(glob.glob("**/*.md", recursive=True)):
    if p.startswith("explorer/"):
        continue
    m = re.match(r"^---\n(.*?)\n---", open(p, encoding="utf-8").read(), re.S)
    if not m:
        continue
    try:
        d = parse_frontmatter(m.group(1))
    except Exception as e:  # noqa: BLE001
        bad.append((p, str(e).splitlines()[0])); continue
    if not isinstance(d, dict):
        bad.append((p, "frontmatter not a mapping")); continue
    if "description" not in d:
        nodesc.append(p)
    if d.get("name"):
        names[d["name"]] += 1
dupes = {k: v for k, v in names.items() if v > 1}
colon = sorted(k for k in names if ":" in k)
print("parse failures:", bad or "none")
print("missing description:", nodesc or "none")
print("duplicate names:", dupes or "none")
print("colon in name (plugin-namespace syntax, invalid for a local skill/agent):", colon or "none")
if bad or nodesc or dupes or colon:
    sys.exit(1)
PY

stage "metrics scripts compile"
python3 -m py_compile config/claude/metrics/emit_run.py config/claude/metrics/process_health.py config/claude/metrics/challenge_token_oracle.py config/claude/lib/plumbline_update.py config/claude/lib/gate_contracts.py config/claude/lib/plumbline_start.py config/claude/lib/council_backend.py \
  && echo "py_compile OK" || fail=1

stage "metrics contract round-trip"
bash config/claude/tests/test_metrics_contract.sh || fail=1

stage "settings JSON validity (.claude/settings.json)"
jq -e . .claude/settings.json >/dev/null && echo ".claude/settings.json OK" || fail=1

stage "stop hook tests"
bash config/claude/tests/test_stop_hook.sh || fail=1

stage "web bootstrap tests"
bash config/claude/tests/test_web_bootstrap.sh || fail=1

stage "true-line governance tests"
bash config/claude/tests/test_true_line_governance.sh || fail=1

stage "product canvas gate tests"
bash config/claude/tests/test_product_canvas_gate.sh || fail=1

stage "agileteam start gate tests"
bash config/claude/tests/test_agileteam_start_gate.sh || fail=1

stage "scope shift notice tests"
bash config/claude/tests/test_scope_shift_notice.sh || fail=1

stage "openrouter council backend acceptance contract"
bash config/claude/tests/test_council_backend.sh || fail=1


stage "runtime integrity layer tests"
bash config/claude/tests/test_runtime_integrity_layer.sh || fail=1

stage "PRIL enforce hook tests"
bash config/claude/tests/test_pril_enforce_hook.sh || fail=1

stage "pretool vision-gate hook tests"
bash config/claude/tests/test_pretool_vision_gate_hook.sh || fail=1

stage "runtime start governance gate tests"
bash config/claude/tests/test_runtime_start_governance_gate.sh || fail=1

stage "evidence-class vocab consistency"
bash config/claude/tests/test_evidence_vocab.sh || fail=1

stage "rule-ledger provenance tests"
bash config/claude/tests/test_rule_ledger.sh || fail=1

stage "run-ledger resume tests"
bash config/claude/tests/test_run_ledger.sh || fail=1

stage "release-please tests"
bash config/claude/tests/test_release_please.sh || fail=1

stage "update layer tests"
bash config/claude/tests/test_update_layer.sh || fail=1

stage "gate contract tests (G1/G3/G4)"
bash config/claude/tests/test_gate_contracts.sh || fail=1

stage "challenge token oracle scorer tests"
bash config/claude/tests/test_challenge_token_oracle.sh || fail=1

stage "readme honesty (Wave A: agent count derived from explorer + vendored framing)"
bash config/claude/tests/test_readme_honesty.sh || fail=1

stage "dependencies doc (Wave A: external vs shipped vs referenced MCP families)"
bash config/claude/tests/test_dependencies_doc.sh || fail=1

stage "install path (Wave A: CLI discoverable — doctor PATH check + install.sh hint)"
bash config/claude/tests/test_install_path.sh || fail=1

stage "lean install (default omits MCP-coupled agents; --with-flow-agents includes them)"
bash config/claude/tests/test_install_lean_agents.sh || fail=1

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
