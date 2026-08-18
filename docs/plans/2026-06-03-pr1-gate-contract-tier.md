# PR-1 — Gate Contract Tier (G1 + G3 + G4) Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Work strictly TDD-first. Show every diff before applying. Commit atomically. `bash config/claude/tests/run_all.sh` MUST end with `ALL CHECKS PASSED` after every task, and `shellcheck` (run inside that suite) must stay clean for every new/edited `.sh`.

**Goal:** Add a deterministic, offline **contract** test tier that guards three `/agileteam` gates against silent drift — G1 (challenge gate), G3 (vision-GO → autonomous run, *final human gate preserved*), G4 (team-composition roster) — each backed by a negative fixture that proves the check is not vacuously green.

**Architecture:** One new bash module `test_gate_contracts.sh` (built on the existing `lib.sh` assertion helpers + a local `has` grep helper), one small read-only Python helper `gate_contracts.py` for the checks that need real parsing (token number, roster YAML, name-resolution), and one new source-of-truth file `agileteam-roster.yml`. No model calls; runs in per-commit CI in <1s. All three gates are **green today** (verified 2026-06-03) — the value is drift-protection, with G3's final-gate guard as the centerpiece.

**Tech Stack:** Python 3 (stdlib + PyYAML, already a repo dependency), Bash (`set -uo pipefail`), `shellcheck`. No new third-party deps.

**Out of scope (separate plans):** the behavioral **Oracle** tier (PR-2 — the token-bound proof for Finding #2, bench/FULL, model-dependent) and sanitizing the four vendored claude-flow specialist agents. See `docs/plans/2026-06-03-gate-verification-hardening-design.md`.

---

## Standing constraints (read before Task 0)

- **Never commit to `main`.** This is a multi-agent workspace; isolate on a branch (Task 0). Do not stash, switch, or touch other worktrees.
- **No silent writes to shared config.** Every edit to `config/claude/commands/*.md` is shown as a diff first. This plan does **not** modify any agent or command file — only adds tests + the roster manifest. If a check reveals a real inconsistency, STOP and surface it; do not "fix" a command file to make a test pass without sign-off.
- **Green gate before every commit:** `bash config/claude/tests/run_all.sh` ends with `ALL CHECKS PASSED`.
- **Test-the-test:** no contract check lands without a negative fixture that has been *observed* to make it fail.
- **Ground truth (verified 2026-06-03, quote-aware):** all roster roles resolve in-repo — `coder→core/coder.md`, `code-reviewer→code-reviewer.md`, `tester→core/tester.md`, `product-owner→agileteam/product-owner.md`, `backend-dev→development/backend/dev-backend-api.md`, `security-reviewer→agileteam/security-reviewer.md`, `ml-developer→data/ml/data-ml-model.md`, `mobile-dev→specialized/mobile/spec-mobile-react-native.md`, `system-architect→architecture/system-design/arch-system-design.md`.

---

## Task 0: Isolate the work

**Files:** none (git only).

**Step 1 — Confirm clean tree on `main`.**
Run: `git -C "$REPO" status --short && git -C "$REPO" rev-parse --abbrev-ref HEAD`
Expected: empty status, branch `main`.

**Step 2 — Create the feature branch (ask the user before switching).**
Run: `git -C "$REPO" switch -c feat/gate-contract-tier`

---

## Task 1: Roster manifest (single source of truth)

**Files:**
- Create: `config/claude/agileteam-roster.yml`

**Step 1 — Write the manifest** (roles verified to resolve in-repo):
```yaml
# config/claude/agileteam-roster.yml
# Single source of truth for the roles /agileteam may staff. The G4 team-composition
# contract (config/claude/tests/test_gate_contracts.sh) asserts every role here resolves
# to an in-repo agent `name:` (quote-aware). Keep in sync with the "Team composition"
# section of config/claude/commands/agileteam.md. All roles ship in-repo (verified 2026-06-03).
minimum:          # always staffed — the fixed judgment/review gates
  - coder
  - code-reviewer
  - tester
  - product-owner
specialists:      # architecture-driven; added per confirmed Canvas / PRD
  - backend-dev
  - security-reviewer
  - ml-developer
  - mobile-dev
  - system-architect
```

**Step 2 — Commit.**
```bash
git add config/claude/agileteam-roster.yml
git commit -m "test: add /agileteam roster manifest (G4 contract source of truth)"
```

---

## Task 2: `gate_contracts.py` — the parsing helper (TDD)

**Files:**
- Create: `config/claude/lib/gate_contracts.py`
- Test: assertions live in `test_gate_contracts.sh` (Tasks 5–7); this task is proven via the CLI checks below.

**Step 1 — Write the failing check first.** From repo root run (expected: FAIL — file does not exist):
```bash
python3 config/claude/lib/gate_contracts.py token-bound config/claude/commands/concilium.md
```
Expected now: `No such file`. After Step 2: prints `15000`.

**Step 2 — Implement the helper:**
```python
#!/usr/bin/env python3
"""Deterministic, read-only helpers for the /agileteam gate contract tests (G1/G3/G4).

No model calls. Exits non-zero on parse failure so the bash harness can assert.

Subcommands:
  token-bound <file>
      Print the challenge-gate token cap as an int (e.g. 15000) parsed from text
      like "<= ~15k tokens total". Exit 1 if no parseable cap is found.
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
import os
import re
import sys

try:
    import yaml  # type: ignore[import-not-found]
except ImportError:  # pragma: no cover - PyYAML is a repo dependency
    yaml = None


def _read(path):
    with open(path, encoding="utf-8") as fh:
        return fh.read()


def token_bound(path):
    m = re.search(r"(\d+)\s*([kK])?\s+tokens", _read(path))
    if not m:
        print(f"no parseable token cap in {path}", file=sys.stderr)
        return 1
    value = int(m.group(1)) * (1000 if m.group(2) else 1)
    print(value)
    return 0


def _load_manifest(path):
    if yaml is None:
        raise RuntimeError("PyYAML required for roster parsing")
    data = yaml.safe_load(_read(path))
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
    pat = re.compile(r'^name:\s*"?' + re.escape(role) + r'"?\s*$')
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
    if cmd == "token-bound" and len(rest) == 1:
        return token_bound(rest[0])
    if cmd == "roster-roles" and len(rest) in (1, 2):
        return roster_roles(rest[0], rest[1] if len(rest) == 2 else "all")
    if cmd == "prose-specialists" and len(rest) == 1:
        return prose_specialists(rest[0])
    if cmd == "resolve-roster" and len(rest) == 2:
        return resolve_roster(rest[0], rest[1])
    print(f"unknown/invalid subcommand: {argv[1:]}", file=sys.stderr)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv))
```

**Step 3 — Verify each subcommand by hand** (from repo root):
```bash
python3 config/claude/lib/gate_contracts.py token-bound config/claude/commands/concilium.md      # -> 15000
python3 config/claude/lib/gate_contracts.py token-bound config/claude/commands/agileteam.md       # -> 15000
python3 config/claude/lib/gate_contracts.py roster-roles config/claude/agileteam-roster.yml minimum # -> code-reviewer / coder / product-owner / tester
python3 config/claude/lib/gate_contracts.py resolve-roster config/claude/agileteam-roster.yml .     # -> (no output) ; echo $? -> 0
```

**Step 4 — Add to the `py_compile` gate.** Edit `config/claude/tests/run_all.sh`: append `config/claude/lib/gate_contracts.py` to the existing `python3 -m py_compile ...` line (the "metrics scripts compile" stage).

**Step 5 — Commit.**
```bash
git add config/claude/lib/gate_contracts.py config/claude/tests/run_all.sh
git commit -m "test: add gate_contracts.py parsing helper for G1/G4 contracts"
```

---

## Task 3: Negative fixtures (so the checks can go red)

**Files:**
- Create: `config/claude/tests/fixtures/gate_contracts/g1_no_cap.md` — a few lines describing the gate but with **no** "N tokens" phrase.
- Create: `config/claude/tests/fixtures/gate_contracts/g3_missing_acceptance_gate.md` — a copy of the agileteam Phase/gate prose with the `USER ACCEPTANCE GATE` heading **removed**.
- Create: `config/claude/tests/fixtures/gate_contracts/g4_unresolved_roster.yml` — a manifest listing one bogus role:
  ```yaml
  minimum:
    - coder
  specialists:
    - this-agent-does-not-exist
  ```

**Step 1 — Prove each fixture breaks the corresponding check** (from repo root):
```bash
python3 config/claude/lib/gate_contracts.py token-bound config/claude/tests/fixtures/gate_contracts/g1_no_cap.md; echo "exit=$?"   # exit=1
grep -qF 'USER ACCEPTANCE GATE' config/claude/tests/fixtures/gate_contracts/g3_missing_acceptance_gate.md; echo "exit=$?"          # exit=1
python3 config/claude/lib/gate_contracts.py resolve-roster config/claude/tests/fixtures/gate_contracts/g4_unresolved_roster.yml .; echo "exit=$?"  # prints this-agent-does-not-exist ; exit=1
```

**Step 2 — Commit.**
```bash
git add config/claude/tests/fixtures/gate_contracts/
git commit -m "test: add negative fixtures for gate contract checks"
```

---

## Task 4: Test module skeleton + helpers

**Files:**
- Create: `config/claude/tests/test_gate_contracts.sh`

**Step 1 — Write the header and helpers:**
```bash
#!/usr/bin/env bash
# Gate contract tests: G1 (challenge gate), G3 (vision-GO autonomy, final human gate
# preserved), G4 (team-composition roster). Deterministic, offline. Each gate's negative
# fixture proves its checks are not vacuously green.
# Design: docs/plans/2026-06-03-gate-verification-hardening-design.md
set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=config/claude/tests/lib.sh
. "$DIR/lib.sh"
REPO="$(cd "$DIR/../../.." && pwd)"
CMD="$REPO/config/claude/commands/agileteam.md"
CONC="$REPO/config/claude/commands/concilium.md"
WATCHER="$REPO/agileteam/plumbline-watcher.md"
ROSTER="$REPO/config/claude/agileteam-roster.yml"
GC="$REPO/config/claude/lib/gate_contracts.py"
FIX="$DIR/fixtures/gate_contracts"

has()  { TESTS_RUN=$((TESTS_RUN+1)); if grep -qF -- "$3" "$2" 2>/dev/null; then _pass "$1"; else _fail "$1 (missing '$3' in $2)"; fi; }

# ===== gates wired below in Tasks 5-7 =====

finish "gate contract tests"
```

**Step 2 — Make executable and run** (expected: 0 run, 0 failed):
```bash
chmod +x config/claude/tests/test_gate_contracts.sh
bash config/claude/tests/test_gate_contracts.sh
```

**Step 3 — Commit.**
```bash
git add config/claude/tests/test_gate_contracts.sh
git commit -m "test: scaffold gate contract test module"
```

---

## Task 5: G4 checks (roster) — implement before the long prose gates

Insert above the `finish` line. Each check has its positive assertion; the negative-fixture assertions prove non-vacuity.

```bash
# ---- G4: team composition roster ----
assert_file "G4 roster manifest exists" "$ROSTER"

# G4-C1: fixed minimum is EXACTLY coder/code-reviewer/tester/product-owner
g4_min="$(python3 "$GC" roster-roles "$ROSTER" minimum | tr '\n' ' ')"
assert_eq "G4-C1 fixed minimum exact" "code-reviewer coder product-owner tester " "$g4_min"

# G4-C2: every roster role resolves to an in-repo agent name (quote-aware)
assert "G4-C2 every roster role resolves in-repo" "python3 '$GC' resolve-roster '$ROSTER' '$REPO'"

# G4-C3: prose examples in agileteam.md are a SUBSET of the manifest (prose uses 'e.g.')
g4_manifest="$(python3 "$GC" roster-roles "$ROSTER")"
while read -r role; do
  [ -z "$role" ] && continue
  TESTS_RUN=$((TESTS_RUN+1))
  if printf '%s\n' "$g4_manifest" | grep -qx "$role"; then _pass "G4-C3 prose specialist '$role' is in the manifest"
  else _fail "G4-C3 prose specialist '$role' missing from manifest"; fi
done < <(python3 "$GC" prose-specialists "$CMD")

# G4-C5 (negative fixture): resolve-roster reddens on a bogus role
assert "G4-C5 resolve-roster reddens on unresolved role" "! python3 '$GC' resolve-roster '$FIX/g4_unresolved_roster.yml' '$REPO'"
```

**Run + commit:**
```bash
bash config/claude/tests/test_gate_contracts.sh     # all ok
git add config/claude/tests/test_gate_contracts.sh
git commit -m "test: G4 team-composition roster contract checks"
```

---

## Task 6: G1 checks (challenge gate)

```bash
# ---- G1: council challenge gate ----
# G1-C1: token bound present, parseable, and EQUAL across both files
g1_conc="$(python3 "$GC" token-bound "$CONC" 2>/dev/null)"
g1_cmd="$(python3 "$GC" token-bound "$CMD" 2>/dev/null)"
assert_eq "G1-C1 token bound equal across concilium.md and agileteam.md" "$g1_conc" "$g1_cmd"
assert "G1-C1 token bound is a positive integer" "[ \"\${g1_conc:-0}\" -gt 0 ]"

# G1-C2: per-round word cap present in both
has "G1-C2 word cap in concilium.md"  "$CONC" "180 words per role"
has "G1-C2 word cap in agileteam.md"  "$CMD"  "180 words per role"

# G1-C3: the three roles present in BOTH files
for role in Challenger Advisor Critic; do
  has "G1-C3 role '$role' in agileteam.md" "$CMD"  "$role"
  has "G1-C3 role '$role' in concilium.md" "$CONC" "$role"
done

# G1-C4: each role alias maps to a body subagent that resolves in-repo
for body in concilium-skeptic concilium-market-realist concilium-tech-arbiter; do
  TESTS_RUN=$((TESTS_RUN+1))
  if grep -rlE "^name: *\"?$body\"?\\s*\$" --include='*.md' "$REPO" 2>/dev/null | grep -qv '/explorer/'; then
    _pass "G1-C4 body '$body' resolves in-repo"
  else _fail "G1-C4 body '$body' does not resolve in-repo"; fi
done

# G1-C5: Phase 0.16 wired in agileteam.md (table + detail) and the invocation in both
has "G1-C5 Phase 0.16 named"            "$CMD"  "Phase 0.16"
has "G1-C5 challenge invocation (cmd)"  "$CMD"  "concilium --mode=challenge"
has "G1-C5 challenge mode (concilium)"  "$CONC" "--mode=challenge"

# G1-C6: intent invariant — friction not approval, one-page summary
has "G1-C6 friction-not-approval" "$CMD" "friction, not approval"

# G1-C7 (negative fixture): token-bound fails closed when no cap is present
assert "G1-C7 token-bound fails closed on capless fixture" "! python3 '$GC' token-bound '$FIX/g1_no_cap.md'"
```

> **If G1-C4 fails:** confirm the exact body `name:` values in `concilium/*.md` and adjust the loop list to match — do NOT edit `concilium.md` to satisfy the test. Surface any real mismatch.

**Run + commit:**
```bash
bash config/claude/tests/test_gate_contracts.sh
git add config/claude/tests/test_gate_contracts.sh
git commit -m "test: G1 challenge-gate contract checks"
```

---

## Task 7: G3 checks (vision-GO autonomy — the centerpiece)

```bash
# ---- G3: vision-GO -> autonomous run, final human gate preserved ----
# G3-C1: BOTH bookends exist — initial GO and the final acceptance gate
has "G3-C1 Vision GO gate present"        "$CMD" "Vision GO gate"
has "G3-C1 USER ACCEPTANCE GATE present"  "$CMD" "USER ACCEPTANCE GATE"

# G3-C2 (negative fixture = the core invariant): a copy with the acceptance gate deleted
# must make the C1 check fail. Prove the check reddens on the broken fixture.
assert "G3-C2 acceptance-gate check reddens when the gate is removed" \
  "! grep -qF 'USER ACCEPTANCE GATE' '$FIX/g3_missing_acceptance_gate.md'"

# G3-C3: bounded autonomy — Watcher may pause; user is final authority
has "G3-C3 user is final authority" "$CMD" "user is the final authority"

# G3-C4/C6: escalation asymmetry + Watcher ownership (uncertainty resolves to the user)
has "G3-C4 Watcher escalates on uncertainty" "$CMD" "escalates to the user"

# G3-C5: vision goal immutable inside re-alignment
has "G3-C5 vision change needs user re-confirmation" "$CMD" "Vision change requiring explicit user re-confirmation"

# G3-C7: /goal ruleset wiring + vision doc path
has "G3-C7 goal-planner ruleset referenced" "$CMD" "goal-planner"
has "G3-C7 vision doc path"                  "$CMD" "docs/vision/"
```

> **If any G3 `has` fails:** the exact phrase may have been reworded in `agileteam.md`. Read the current wording and update the *test string* to the real phrase (the contract tracks intent, not a stale quote) — never edit the command to match. If the *concept* is genuinely gone (e.g. the acceptance gate removed), that is a real regression — STOP and surface it.

**Run + commit:**
```bash
bash config/claude/tests/test_gate_contracts.sh
git add config/claude/tests/test_gate_contracts.sh
git commit -m "test: G3 vision-GO autonomy contract checks (final-gate guard)"
```

---

## Task 8: Wire into `run_all.sh` and prove the whole suite green

**Files:**
- Modify: `config/claude/tests/run_all.sh`

**Step 1 — Add the module** next to the other `bash config/claude/tests/test_*.sh || fail=1` lines:
```bash
stage "gate contract tests (G1/G3/G4)"
bash config/claude/tests/test_gate_contracts.sh || fail=1
```
(`shellcheck` already globs `config/claude/tests/*.sh`, so the new module is linted automatically.)

**Step 2 — Run the full suite:**
```bash
bash config/claude/tests/run_all.sh
```
Expected: ends with `ALL CHECKS PASSED` (and the new `gate contract tests` stage shows all `ok`).

**Step 3 — Commit.**
```bash
git add config/claude/tests/run_all.sh
git commit -m "test: wire gate contract tier into run_all.sh"
```

---

## Task 9: Finalize

**Step 1 — Confirm tree clean + suite green:** `git status --short` (empty) and re-run `run_all.sh` (`ALL CHECKS PASSED`).

**Step 2 — Open the PR** (use `finishing-a-development-branch` to decide merge/PR). Body: list the gates covered (G1/G3/G4), note all are green today (drift-protection), link this plan and the design doc, and state the Oracle tier (token-bound proof) is deferred to PR-2.

**Step 3 — Before merge:** verify the actual `ci` workflow conclusion is `success` (not just `mergeable`), per the repo's merge-safety rule.

---

## Definition of Done

- New: `agileteam-roster.yml`, `gate_contracts.py`, `test_gate_contracts.sh`, three negative fixtures.
- `run_all.sh` ends `ALL CHECKS PASSED`; `gate_contracts.py` is in the `py_compile` gate; module is shellcheck-clean.
- Each gate has a negative fixture observed to make its check fail (G1-C7, G3-C2, G4-C5).
- No agent/command file was modified; any real inconsistency surfaced, not silently patched.
- Commit type `test:` throughout (adds guards, no behavior change, intentionally kept out of release notes).
