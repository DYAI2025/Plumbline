#!/usr/bin/env bash
# A3.2 / Wave A: the plumbline CLI must be discoverable. `plumbline doctor` reports a PATH
# status line, and install.sh prints an unmistakable export hint when its bin dir is NOT on
# $PATH — so a user who follows the docs never hits a bare "command not found" (the exact
# symptom the install audit surfaced). See docs/plans/2026-06-03-install-audit-fixes.md (P3).
set -uo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config/claude/tests/lib.sh
. "$DIR/lib.sh"
REPO="$(cd "$DIR/../../.." && pwd)"
PLUMBLINE="$REPO/config/claude/bin/plumbline"
INSTALL="$REPO/config/claude/install.sh"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# 1. `plumbline doctor` surfaces PATH status (so the user can self-diagnose command-not-found).
#    `|| true` neutralises doctor's exit code (it may be non-zero on a check) so grep decides.
assert "doctor reports PATH status" \
  "{ '$PLUMBLINE' --root '$REPO' doctor 2>&1 || true; } | grep -q PATH"

# 2. install.sh prints an export hint when its bin dir is NOT on \$PATH. Isolated CLAUDE_HOME
#    (a fresh temp dir whose /bin is by construction absent from the real \$PATH) + --dry-run.
assert "install.sh prints a PATH export hint when bin not on PATH" \
  "{ CLAUDE_HOME='$TMP/clh' bash '$INSTALL' --dry-run 2>&1 || true; } | grep -q 'export PATH'"

# F6: doctor surfaces the resolved update slug, so a fork user sees their update targets
# the fork (and the existing --repo/PLUMBLINE_REPO override is discoverable).
assert "doctor reports the resolved update slug" \
  "{ '$PLUMBLINE' --root '$REPO' doctor 2>&1 || true; } | grep -qiE 'update slug|update repo'"

finish "install path tests"
