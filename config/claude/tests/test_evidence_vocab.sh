#!/usr/bin/env bash
# Vocab-consistency guard for the evidence-class vocabulary (M5).
#
# Two load-bearing vocabularies must stay reconciled:
#   1. the 4-rung prose ladder in config/claude/commands/agileteam.md
#      (unit-fake -> integration-fake -> real-boundary-smoke -> production-verified)
#   2. the 10-value schema enum in
#      docs/templates/reality-ledger-evidence.schema.json, ranked 0-5 in
#      plumbline_reality.RANKS.
#
# This test FAILS CLOSED if any future edit desyncs the enum, RANKS, the prose
# ladder, or the crosswalk doc. It is a characterization+guard test (it should
# pass today); a red here means a real desync that must be investigated, never
# forced green. stdlib-only (json/re), invoked from run_all.sh.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"

echo "test_evidence_vocab"

# All assertions live in one Python process: it parses the schema JSON, imports
# RANKS from the library, scans the prose ladder and the crosswalk doc, and exits
# non-zero with a clear message on the first inconsistency.
REPO_DIR="$REPO_DIR" python3 - <<'PY'
import json
import os
import re
import sys

repo = os.environ["REPO_DIR"]
sys.path.insert(0, os.path.join(repo, "config", "claude", "lib"))

errors = []


def fail(msg):
    errors.append(msg)


# --- Load the three sources of truth -------------------------------------------------
try:
    from plumbline_reality import RANKS
except Exception as exc:  # noqa: BLE001
    print(f"FAIL could not import RANKS from plumbline_reality: {exc}", file=sys.stderr)
    sys.exit(1)

schema_path = os.path.join(repo, "docs", "templates", "reality-ledger-evidence.schema.json")
try:
    with open(schema_path, encoding="utf-8") as fh:
        schema = json.load(fh)
    enum = schema["properties"]["evidence_class"]["enum"]
except Exception as exc:  # noqa: BLE001
    print(f"FAIL could not load evidence_class enum from {schema_path}: {exc}", file=sys.stderr)
    sys.exit(1)

enum_set = set(enum)
ranks_set = set(RANKS)

# --- Assertion 1: enum set and RANKS set are identical (neither may drift) -----------
if enum_set != ranks_set:
    only_enum = sorted(enum_set - ranks_set)
    only_ranks = sorted(ranks_set - enum_set)
    fail(
        "schema enum and plumbline_reality.RANKS are NOT identical sets "
        f"(only in enum: {only_enum or 'none'}; only in RANKS: {only_ranks or 'none'}). "
        "Every evidence class must be defined in both."
    )
if len(enum) != len(set(enum)):
    dupes = sorted({v for v in enum if enum.count(v) > 1})
    fail(f"schema evidence_class enum has duplicate values: {dupes}")

# --- Assertion 2: the 4-rung prose ladder is a strict, monotonic coarsening ----------
LADDER = ["unit-fake", "integration-fake", "real-boundary-smoke", "production-verified"]

missing_rungs = [rung for rung in LADDER if rung not in RANKS]
if missing_rungs:
    fail(f"prose-ladder rungs missing from RANKS (no schema home): {missing_rungs}")
else:
    rung_ranks = [RANKS[rung] for rung in LADDER]
    if not all(a < b for a, b in zip(rung_ranks, rung_ranks[1:])):
        fail(
            "prose-ladder ranks are not strictly increasing: "
            f"{list(zip(LADDER, rung_ranks))}. The ladder must be a monotonic coarsening "
            "of the schema enum."
        )
    # The ladder must literally appear, in order, in the command's prose so the doc
    # and the code can never silently disagree about the ladder.
    cmd_path = os.path.join(repo, "config", "claude", "commands", "agileteam.md")
    try:
        cmd_text = open(cmd_path, encoding="utf-8").read()
    except OSError as exc:
        fail(f"could not read prose ladder source {cmd_path}: {exc}")
    else:
        # Tolerate the line-wrap between rungs (whitespace / leading comment markers).
        ladder_pattern = re.compile(
            r"\bunit-fake\b.*?\bintegration-fake\b.*?\breal-boundary-smoke\b.*?\bproduction-verified\b",
            re.S,
        )
        if not ladder_pattern.search(cmd_text):
            fail(
                "the 4-rung prose ladder "
                "(unit-fake -> integration-fake -> real-boundary-smoke -> production-verified) "
                f"was not found in order in {cmd_path}"
            )

# --- Assertion 3: the crosswalk doc mentions all 10 enum values ----------------------
crosswalk_path = os.path.join(repo, "docs", "reality-evidence-crosswalk.md")
try:
    crosswalk = open(crosswalk_path, encoding="utf-8").read()
except OSError as exc:
    fail(f"crosswalk doc missing or unreadable ({crosswalk_path}): {exc}")
    crosswalk = ""

for value in enum:
    # Word-boundary match so 'integration' does not accidentally satisfy
    # 'integration-fake' and vice-versa.
    if not re.search(rf"(?<![\w-]){re.escape(value)}(?![\w-])", crosswalk):
        fail(
            f"crosswalk doc {crosswalk_path} does not mention enum value '{value}' "
            "(the doc must not silently drift from the schema enum)."
        )

# --- Report --------------------------------------------------------------------------
if errors:
    for err in errors:
        print(f"FAIL {err}", file=sys.stderr)
    sys.exit(1)

print(f"  ok   schema enum and RANKS are identical sets ({len(enum)} values)")
print("  ok   4-rung prose ladder is a strict coarsening (ranks 1<2<3<4)")
print("  ok   crosswalk doc mentions all 10 schema enum values")
PY
status=$?

if [ "$status" -eq 0 ]; then
  echo "test_evidence_vocab: PASSED"
else
  echo "test_evidence_vocab: FAILED"
fi
exit "$status"
