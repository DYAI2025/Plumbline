# Plan: Unblock v0.18.0 Test Suite — All Blockers & Contradictions

**Created:** 2026-06-20  
**Branch context:** detached HEAD @ v0.18.0 tag  
**Goal:** `bash config/claude/tests/run_all.sh` exits 0 on this machine. Status changes from "changed, not yet verified" to "verified".

**Non-goals:**
- Do NOT modify upstream test contracts (`.sh` files are the spec, not the subject)
- Do NOT implement real OpenRouter network calls — seam stays offline
- Do NOT skip RED-phase suites; implement them to GREEN instead

---

## Preconditions & Known Gaps

| # | Gap | Evidence |
|---|-----|----------|
| G-1 | `python3` not in PATH on this machine | `python3 --version` → exit 1; `uv run python3` → OK |
| G-2 | 86 bare `python3` calls across 26 test scripts | `grep -rn "python3" tests/*.sh \| grep -v "uv run" \| wc -l` → 86 |
| G-3 | `council_inference.py` CLI seam untestable until G-1 fixed | All 75 OpenRouter tests fail |
| G-4 | `deepseek_review.py` pre-implementation (TDD RED) | Test header: "RED until implemented" |
| G-5 | Metrics contract: 8/19 fail | Likely G-1 cascade; verify after G-1 fix |
| G-6 | `plumbline update` CLI not in PATH | `~/.claude/bin` not exported; add to `~/.zshrc` |

---

## Task List

### TASK-01 — Fix `python3` PATH (Root blocker, unblocks everything)
**REQ:** G-1, G-2  
**Approach:** Create a `python3` shim at `~/.local/bin/python3` that delegates to `uv run python3`. Do NOT modify the 26 upstream test scripts.

**Files affected:**
- `~/.local/bin/python3` (new shim, must be on PATH before `/usr/bin`)
- `~/.zshrc` — ensure `~/.local/bin` is prepended

**Implementation:**
```bash
mkdir -p ~/.local/bin
cat > ~/.local/bin/python3 << 'EOF'
#!/usr/bin/env bash
exec uv run python3 "$@"
EOF
chmod +x ~/.local/bin/python3
# Prepend to PATH in ~/.zshrc (idempotent)
grep -q 'HOME/.local/bin' ~/.zshrc || \
  echo 'export PATH="$HOME/.local/bin:$PATH"' >> ~/.zshrc
export PATH="$HOME/.local/bin:$PATH"
```

**Acceptance evidence:**
```bash
python3 --version         # must print Python 3.x.x, exit 0
python3 -c "print('ok')" # must print ok
```

**Rollback:** `rm ~/.local/bin/python3`

---

### TASK-02 — Add `plumbline` CLI to PATH (TASK-01 independent, G-6)
**REQ:** G-6  
**Files affected:** `~/.zshrc`

**Implementation:**
```bash
grep -q '\.claude/bin' ~/.zshrc || \
  echo 'export PATH="$HOME/.claude/bin:$PATH"' >> ~/.zshrc
export PATH="$HOME/.claude/bin:$PATH"
```

**Acceptance evidence:**
```bash
plumbline --version   # must not return "command not found"
```

**Rollback:** Remove the added line from `~/.zshrc`.

---

### TASK-03 — Verify metrics contract after python3 fix (depends: TASK-01)
**REQ:** G-5  
**Scope:** Run `test_metrics_contract.sh` in isolation; triage surviving failures.

**Run:**
```bash
cd ~/Projects/_TOOLZ/plumbline_v1/Plumbline
bash config/claude/tests/test_metrics_contract.sh 2>&1
```

**Expected:** All 19 pass once python3 works. If failures remain, each failing assertion maps 1:1 to `config/claude/metrics/emit_run.py`. Fix in that file only.

**Files potentially affected:**
- `config/claude/metrics/emit_run.py` (implementation, if logic gaps exist)

**Acceptance evidence:** `test_metrics_contract.sh` → `19 run, 0 failed`

---

### TASK-04 — Verify council_inference CLI seam (depends: TASK-01)
**REQ:** G-3  
**Scope:** Run `test_council_inference.sh` in isolation after TASK-01.

**Run:**
```bash
cd ~/Projects/_TOOLZ/plumbline_v1/Plumbline
bash config/claude/tests/test_council_inference.sh 2>&1 | tail -3
```

**If still failing:** `council_inference.py` (471 lines, already exists) is missing the `infer` argparse subcommand or the injected-transport seam. Fix inside `config/claude/lib/council_inference.py` only.

**CLI contract (from test header):**
```
python3 config/claude/lib/council_inference.py infer \
  --model <id> --messages '<json>' --max-tokens <int> \
  --input-estimate <int> [--dry-run | --build-only] \
  [--inject-response '<json>' | --inject-error <class>] \
  --inject-call-counter <path> --json
```

**JSON output contract:**
```json
{
  "decision": "proceed|abort|dry-run",
  "code": "COUNCIL_*",
  "estimate": { "input_token_estimate": int, "max_tokens": int, "total_estimate": int, "approximate": true, "cap": int },
  "completion": "str|null",
  "usage": {}|null,
  "retry_after": "str|null"
}
```

**Files affected:** `config/claude/lib/council_inference.py`

**Acceptance evidence:** `test_council_inference.sh` → `75 run, 0 failed`

---

### TASK-05 — Implement DeepSeek review Phase-1 contract (depends: TASK-01)
**REQ:** G-4  
**Scope:** `test_deepseek_review.sh` — TDD RED phase. Implement `deepseek_review.py` to satisfy the contract.

**Run to see all failing assertions:**
```bash
cd ~/Projects/_TOOLZ/plumbline_v1/Plumbline
bash config/claude/tests/test_deepseek_review.sh 2>&1
```

**Key contracts from test:**
- `REQ-DS-001`: builds system + user message with subject verbatim
- `prompt_source` discloses body file path (e.g. `concilium/market-realist.md`)
- Uses `council_presets.py` for preset lookup

**Files affected:** `config/claude/lib/deepseek_review.py`

**Acceptance evidence:** `test_deepseek_review.sh` → `N run, 0 failed`

---

### TASK-06 — Full suite green gate (depends: TASK-01..05)
**REQ:** All  

```bash
cd ~/Projects/_TOOLZ/plumbline_v1/Plumbline
bash config/claude/tests/run_all.sh 2>&1 | tail -20
```

**Acceptance evidence:** Exit code 0, no `FAIL` lines in output.  
**Status change:** "changed, not yet verified" → **verified**.

---

## Risks & Rollback

| Risk | Mitigation |
|------|-----------|
| `uv run python3` shim is slower (subprocess overhead) | Acceptable for test suite; not a production path |
| Modifying `council_inference.py` breaks v0.18.0 tag | Work on `main` branch after tag checkout, not on the tag itself |
| DeepSeek implementation introduces real network calls | Tests enforce `--inject-*` seam; any real urlopen in offline suite = test failure |
| `~/.zshrc` PATH change breaks other tools | Prepend only; existing PATH entries preserved. `rm ~/.local/bin/python3` reverts fully |

**Rollback v0.18.0 → v0.15.0 (if needed):**
```bash
git -C ~/Projects/_TOOLZ/plumbline_v1/Plumbline checkout v0.15.0
bash config/claude/install.sh --force
```
