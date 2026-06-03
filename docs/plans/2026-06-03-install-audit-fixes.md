# Install-Audit Fixes Implementation Plan

> **For Claude:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task. Work TDD-first; show every diff (governed config!) before applying; commit atomically; `bash config/claude/tests/run_all.sh` MUST end `ALL CHECKS PASSED` after every task; shellcheck clean.

**Goal:** Fix the verified, *ours* defects an external install audit surfaced — the `plumbline` CLI not being on `$PATH` (the user's `command not found`), the macOS-false-RED verification, an invalid skill name, doc/expectation gaps (MCP/plugin + fork-update override), count drift, and the whole-repo agent mount — each cleanly building on the last.

**Architecture:** Six sequenced phases, foundation-first. P1 makes the verification itself trustworthy + observable cross-platform (everything downstream relies on an honest `run_all`). P2–P5 are small, isolated, low-risk fixes that progressively introduce/extend a `plumbline doctor` self-check and guard tests. P6 (the invasive agent-mount restructure) is **last and gated on verifying its premise**.

**Tech Stack:** Bash (`install.sh`, `*.sh` tests, `set -uo pipefail`, shellcheck), Python 3 stdlib (`plumbline_update.py`, `tarfile`), GitHub Actions (CI matrix), Markdown (README/SETUP).

**Verified facts this plan builds on (checked 2026-06-03, this repo):**
- `install.sh:12` `CLAUDE_HOME="${CLAUDE_HOME:-$HOME/.claude}"`; `install_bin` → `$CLAUDE_HOME/bin/` (`:133-137`); `install_agent_repo` → `transfer "$REPO_DIR" "$CLAUDE_HOME/agents"` (`:96-102`, **whole repo**); commands/skills/lib installed **separately** (`:108-129`); Stop-hook source referenced at `$CLAUDE_HOME/agents/config/claude/hooks/plumbline-enforce.sh` (`:194`); done-message `:246` has **no PATH hint**.
- `plumbline_update.py`: production extract uses portable `tarfile.extractall(into, filter="data")` + `_member_escapes` guard (`:215,240,253`) — **product code is fine**; `update` subcommand exists (`:491`); slug resolution: `git remote origin` → `PLUMBLINE_REPO` env → `DEFAULT_REPO_SLUG="DYAI2025/Plumbline"`, plus `--repo` flag (`:25,137-152,494`) — **upstream override already exists**.
- `config/claude/tests/test_update_layer.sh:114-115` uses GNU-only `tar --transform` / `-P --absolute-names` (the macOS-RED, **test-only**).
- `config/claude/skills/product-management-write-spec/SKILL.md:2` `name: product-management:write-spec` (colon).
- `README.md:9,94` "87 subagents · 16 vendored skills"; `config/claude/commands/` has 9 commands.

**Honesty gates carried from the konfabulations-audit (binding):**
- **P6 premise is UNVERIFIED.** "Whole-repo mount → phantom/broken agents in the runtime loader" was *asserted* by the foreign audit, not observed by us. **P6 Task 0 verifies it first; if the runtime ignores non-agent `.md`, P6 downgrades to cosmetic or is dropped — do not invest in the restructure on an unverified premise.**
- **macOS not reproducible here (Linux dev box).** P1's fix is correct regardless (removing BSD-incompatible flags is strictly better), but its macOS effect is verified only by the **new macOS CI runner** P1 adds — not by local claims.
- **F6 is discoverability, not capability.** The upstream override exists today (`--repo` / `PLUMBLINE_REPO`). P4 only makes it *visible*; it must not claim to "add" upstream updates.

---

## Standing constraints

- **Never commit to `main`.** One isolated branch for this plan: `fix/install-audit`. Multi-agent workspace — no stash/branch-dance.
- **Governed config = show the diff first.** `install.sh`, `README.md`, `SETUP.md`, `commands/`, `skills/`, agent files: every edit shown before applying; no silent writes.
- **Green gate before each commit;** shellcheck clean for new/edited `.sh`.
- **No fabrication / MISSING discipline.** If a premise can't be verified (P6), STOP and say so — don't build on it.
- Final integration uses **`/merge-when-true`** (CI green is necessary, not sufficient).

---

## Phase 1 — Trustworthy, cross-platform verification (F4)

*Rationale: every later task gates on `run_all` being green. If it falsely REDs on macOS, the whole TDD loop is compromised there. Fix the verification first, and make macOS observable so we never again claim a macOS result we can't see.*

### Task 1.1 — Read the failing fixture
**Files:** read `config/claude/tests/test_update_layer.sh:90-160` (the "evil tarball" construction + the `unsafe tarball reports unsafe member` assertion).
Understand: the test builds a malicious tarball with a `../evil` traversal member and asserts the **production** extractor rejects it. The bug is only in *how the fixture is built* (GNU `tar` flags), not in what it tests.

### Task 1.2 — Make the evil-tarball build portable (TDD)
**Files:** Modify `config/claude/tests/test_update_layer.sh:114-115`.
**Step 1 — Confirm the current line is GNU-only** (already verified): `--transform` / `-P --absolute-names` are unsupported by macOS BSD `tar`.
**Step 2 — Replace with a portable Python `tarfile` builder** that crafts a `../evil` member without any tar CLI flags:
```bash
# was: tar -C "$EVIL_DIR" -czf "$EVIL_TARBALL" --transform 's,^evil,../evil,' evil ...
python3 - "$EVIL_TARBALL" <<'PY'
import sys, tarfile, io
with tarfile.open(sys.argv[1], "w:gz") as t:
    data = b"pwned\n"
    ti = tarfile.TarInfo("../evil"); ti.size = len(data)
    t.addfile(ti, io.BytesIO(data))
PY
```
**Step 3 — Run the module:** `bash config/claude/tests/test_update_layer.sh` → expect `50 run, 0 failed`; specifically `unsafe tarball reports unsafe member` PASSES (the production `_member_escapes` / `filter="data"` still rejects `../evil`).
**Step 4 — Full suite:** `bash config/claude/tests/run_all.sh` → `ALL CHECKS PASSED`; shellcheck clean.
**Step 5 — Commit:** `fix: portable update-layer evil-tarball fixture (macOS run_all no longer falsely RED)`

### Task 1.3 — Make macOS observable in CI
**Files:** Modify `.github/workflows/ci.yml`.
**Step 1 — Read** the current workflow (single ubuntu job).
**Step 2 — Add a macOS leg** to the job matrix (`runs-on: ${{ matrix.os }}`, `os: [ubuntu-latest, macos-latest]`), ensuring `shellcheck`/`jq`/`python3+PyYAML` install on macOS (`brew install shellcheck jq`).
**Step 3 — Push the branch; confirm the macOS leg runs `run_all.sh` green** (this is the only honest verification of the F4 fix on macOS — we cannot reproduce it on the Linux dev box).
**Step 4 — Commit:** `ci: run run_all on macOS too (catch GNU/BSD portability regressions)`

> **Honesty note in the plan:** Task 1.2's correctness on macOS is *claimed* until Task 1.3's macOS leg is green. Do not mark F4 "fixed on macOS" before that leg passes.

---

## Phase 2 — Skill-name correctness + guard (F5)

### Task 2.1 — Add a validator guard that REDs on a colon in a local skill/agent `name:` (TDD)
**Files:** Modify the frontmatter validator inside `config/claude/tests/run_all.sh` (the `agent frontmatter validation` Python stage).
**Step 1 — Add the check:** after the duplicate-name scan, also fail if any `name:` value contains `:` (plugin-namespace syntax is invalid for a local skill/agent):
```python
colon = sorted(n for n in names if ":" in n)
print("colon in name (plugin-namespace syntax):", colon or "none")
if bad or nodesc or dupes or colon:
    sys.exit(1)
```
**Step 2 — Run `run_all.sh` → expect RED** at this stage, listing `product-management:write-spec` (proves the guard bites — TDD red first).

### Task 2.2 — Find + update references to the colon name
**Files:** repo-wide.
**Step 1:** `grep -rn 'product-management:write-spec' . | grep -v '/.git/'` — find every reference (frontmatter, any agent/command that invokes it, docs, the explorer source).
**Step 2:** Note each; they all migrate to the hyphen form in 2.3.

### Task 2.3 — Rename to the hyphen form
**Files:** Modify `config/claude/skills/product-management-write-spec/SKILL.md:2` → `name: product-management-write-spec`; apply the same rename to every reference found in 2.2.
**Step 1 — Edit.** **Step 2 — `run_all.sh` → now GREEN** (the colon guard passes; name now matches the folder).
**Step 3 — If the skill is surfaced in the Agent Explorer**, rebuild: `./build-explorer.sh` and confirm `agent-explorer.html` + `docs/index.html` updated (only if it's an *agent*; a pure skill is not in the explorer — check 2.2's grep).
**Step 4 — Commit:** `fix: rename product-management skill to hyphen form (colon is plugin-namespace syntax) + guard it`

---

## Phase 3 — The PATH fix (the user's `command not found`)

### Task 3.1 — Teach `plumbline doctor` to report PATH status (TDD)
**Files:** Modify `config/claude/lib/plumbline_update.py` (the `doctor` subcommand handler); Test: `config/claude/tests/test_update_layer.sh` (or a new `test_plumbline_doctor.sh`).
**Step 1 — Failing test:** assert `python3 config/claude/lib/plumbline_update.py doctor` output contains a PATH line, e.g. `PATH:`:
```bash
out="$(python3 "$REPO/config/claude/lib/plumbline_update.py" doctor 2>&1 || true)"
assert "doctor reports PATH status" "printf '%s' \"$out\" | grep -q 'PATH'"
```
Run → FAIL (doctor doesn't mention PATH yet).
**Step 2 — Implement:** in the `doctor` handler, compute the CLI's own dir (`Path(sys.argv[0]).resolve().parent` or the install bin dir) and print whether it is on `os.environ["PATH"]`:
```python
bindir = Path(__file__).resolve().parent.parent / "bin"   # the installed plumbline lives here
on_path = str(bindir) in os.environ.get("PATH", "").split(os.pathsep)
print(f"PATH: plumbline CLI dir {'on' if on_path else 'NOT on'} $PATH ({bindir})")
if not on_path:
    print(f"  fix: add to your shell rc →  export PATH=\"{bindir}:$PATH\"")
```
**Step 3 — Run test → PASS.** **Step 4 — `run_all.sh` green.**

### Task 3.2 — install.sh prints a PATH hint at the end
**Files:** Modify `config/claude/install.sh` (the done-message block near `:246`).
**Step 1 — After install_bin**, detect whether `$CLAUDE_HOME/bin` is on `$PATH`; if not, append a clear instruction to the final output:
```bash
case ":$PATH:" in
  *":$CLAUDE_HOME/bin:"*) : ;;
  *) printf 'NOTE: %s/bin is not on your $PATH — the `plumbline` CLI will be "command not found".\n      Add it:  export PATH="%s/bin:$PATH"   (then restart your shell)\n' "$CLAUDE_HOME" "$CLAUDE_HOME" ;;
esac
```
**Step 2 — Test (TDD):** add to a test that runs `install.sh --dry-run` (or real, isolated `CLAUDE_HOME=/tmp/...`) with a PATH lacking the bin dir and asserts the hint appears. Run → FAIL first, then PASS.
**Step 3 — `run_all.sh` green; shellcheck clean.**

### Task 3.3 — Document PATH in SETUP.md
**Files:** Modify `SETUP.md` — add a short "Put the CLI on your PATH" note (`export PATH="$HOME/.claude/bin:$PATH"`), and that `/plumbline-update` (slash command in Claude Code) is distinct from the `plumbline` terminal CLI.
**Step — Commit (all of Phase 3):** `fix(install): put plumbline CLI discoverable on PATH (hint + doctor check + SETUP)`

---

## Phase 4 — Doc/expectation clarity (F1/F2) + fork-update discoverability (F6)

### Task 4.1 — README/SETUP: state the install model honestly (TDD)
**Files:** Modify `README.md` + `SETUP.md`; Test: `config/claude/tests/run_all.sh` (or a small doc test).
**Step 1 — Failing test:** assert `README.md` contains an explicit install-model statement, e.g. grep for `not a Claude Code plugin` and `no MCP server`. Run → FAIL.
**Step 2 — Add the section** (README "Installation model"): *"Plumbline installs via `config/claude/install.sh` into `~/.claude` (symlinks, or `--copy`). It is **not a Claude Code plugin** (`/plugin install` does not apply) and ships **no MCP server**. Some vendored agents reference `mcp__claude-flow__*` tools; those work only if the claude-flow MCP is installed **separately** — without it those tool refs are inert (not an error)."*
**Step 3 — Run test → PASS; `run_all.sh` green.**

### Task 4.2 — `plumbline doctor` + docs surface the update slug + override (F6, discoverability only)
**Files:** Modify `plumbline_update.py` (`doctor`); `README.md`/`SETUP.md`; Test: doctor test.
**Step 1 — Failing test:** assert `plumbline doctor` output prints the resolved update slug (so a fork user *sees* it points at their fork):
```bash
assert "doctor reports the resolved update slug" "printf '%s' \"$out\" | grep -qE 'update (repo|slug):'"
```
**Step 2 — Implement:** in `doctor`, print `update slug: {default_repo_slug(root)}` and, when it differs from `DEFAULT_REPO_SLUG`, a hint: `  (fork detected — for upstream: plumbline update --repo DYAI2025/Plumbline  or  PLUMBLINE_REPO=DYAI2025/Plumbline)`.
**Step 3 — Doc:** add the same override note to README/SETUP. **Framing: the override already exists; this only makes it discoverable.**
**Step 4 — Run test → PASS; `run_all.sh` green.**
**Step — Commit (Phase 4):** `docs+feat(doctor): clarify no-MCP/no-plugin install model and surface the fork-update override`

> **Out of scope here (separate, noted):** sanitizing the dangling `mcp__claude-flow__*` tool refs out of the vendored agents (the bigger cleanup). Phase 4 *documents* the dependency; the sanitize is a follow-up so this plan stays bounded.

---

## Phase 5 — Count drift, guarded (F8)

### Task 5.1 — Establish the TRUE counts deterministically
**Files:** add a tiny counter to `build-explorer.sh`'s extraction (or a standalone `config/claude/metrics/count_assets.py` — reuse the explorer's frontmatter extractor; do NOT hand-count).
**Step 1 — Compute** agent count (the explorer's own list — single source of truth), skill count (`config/claude/skills/*/SKILL.md`), command count (`config/claude/commands/*.md`). Record the numbers.
> Note: the konfabulations-audit found three conflicting figures (README 87, audit 86, naive grep 102) — so the count is **derived from the explorer extractor**, never asserted by hand.

### Task 5.2 — Update README to the derived numbers + add a drift-guard (TDD)
**Files:** Modify `README.md:9,94`; add a check to `run_all.sh`.
**Step 1 — Failing guard:** a `run_all` check that re-derives the counts and asserts they equal the numbers printed in `README.md`. Run → FAIL (README says 87/16 vs derived).
**Step 2 — Update README** to the derived counts; **Step 3 — guard PASSES; `run_all.sh` green.**
**Step — Commit:** `fix(docs): derive README asset counts from the explorer + drift-guard test`

---

## Phase 6 — Agent-dir mount (F3) — LAST, and GATED on verifying its premise

> **Premise check first. Do not restructure on an unverified claim.**

### Task 6.0 — VERIFY the "phantom agents" premise (BLOCKER gate)
**Step 1 — Determine, with evidence, whether Claude Code's agent loader actually parses non-agent `.md` under `~/.claude/agents` as agents** (the audit asserted it; we have not observed it). Check: Claude Code docs on agent discovery (via the claude-code-guide agent or official docs), and/or observe a real `~/.claude/agents` that contains README/docs whether the agent list shows phantom entries.
**Step 2 — Decision:**
- If the loader **does** create phantom/broken agents → proceed with 6.1+ (real fix).
- If the loader **ignores** non-frontmatter / non-agent `.md` → **F3 is cosmetic**: STOP the restructure, record the finding, and instead (optional) just exclude obvious noise. Do not do the risky mount change for nothing.
**Step 3 — Record the verdict in the plan/PR. This gate is mandatory; report the evidence either way.**

### Task 6.1 — (only if 6.0 confirms) Mount only agent categories
**Files:** Modify `config/claude/install.sh` `install_agent_repo()` (`:96-102`).
**Step 1 — Enumerate** the agent category dirs + top-level agent files (e.g. `code-reviewer.md`) vs non-agent (`README.md`, `CHANGELOG.md`, `SETUP.md`, `CLAUDE.md`, `docs/`, `metrics/`, `config/`, `explorer/`, `dev-plan.md`, …).
**Step 2 — Change** the mount to transfer only agent dirs/files into `$CLAUDE_HOME/agents/`, not `$REPO_DIR` root.

### Task 6.2 — Handle the ripple (this is why F3 is risky)
**Files:** `config/claude/install.sh:194` (hook source `$CLAUDE_HOME/agents/config/claude/hooks/plumbline-enforce.sh` no longer exists if the repo isn't mounted there) → repoint to `$REPO_DIR/config/claude/hooks/plumbline-enforce.sh`. Check `plumbline_update.py` does not assume `~/.claude/agents == repo root` for self-update. Check `SETUP.md`'s "install.sh makes the repository available as ~/.claude/agents" claim — update it.
**Step — TDD:** a test asserting that, after an isolated install, `$CLAUDE_HOME/agents` contains **only** `.md` whose frontmatter has `name:` (no README/docs/metrics), AND the registered hook path resolves to an existing file.

### Task 6.3 — Verify + commit
**Step:** isolated install into `CLAUDE_HOME=/tmp/...`; assert clean agent dir + resolving hook + `run_all.sh` green; update `SETUP.md`. Commit: `fix(install): mount only agent categories, not the repo root (no non-agent files in the agent scan)`

---

## Sequencing rationale (why this order builds cleanly)

1. **P1** makes `run_all` honest + macOS-observable → every later "green" gate is trustworthy.
2. **P2** adds the colon guard (a validator pattern reused conceptually later) — tiny, isolated.
3. **P3** introduces/extends `plumbline doctor` (PATH) — the user's symptom.
4. **P4** extends the *same* `doctor` (slug) + docs — natural continuation of P3.
5. **P5** makes README accurate + adds a count guard **before** P6 (so the guard catches any count change P6 causes).
6. **P6** — the invasive restructure — last, **and only if its premise verifies**, with the now-trustworthy suite + count guard to catch regressions.

## Definition of Done

- `run_all.sh` green on **both** ubuntu and macos CI legs.
- `plumbline` discoverable on `$PATH` (hint + `doctor` check + SETUP); the `command not found` is resolved for a user who follows the docs.
- No colon in any local skill/agent `name:`; guarded.
- README/SETUP state the install model (no MCP/no plugin) and the fork-update override; guarded where testable.
- README counts derived, not hand-asserted; drift-guarded.
- F3: either the mount is restructured (premise confirmed) **or** the premise is documented as unverified/cosmetic and the risky change is *not* made — never built on an unverified claim.
- No agent frontmatter semantics changed without an explorer rebuild; governed-config diffs all shown.

## Open decisions (human)

- **OD-1:** P1 Task 1.3 needs CI to actually have macOS runners available (cost). Confirm that's acceptable.
- **OD-2:** P3 — print-only PATH hint (safe) vs. also offering to symlink `plumbline` into `/usr/local/bin`/`~/.local/bin` (writes outside `~/.claude`, needs consent). Default: print-only.
- **OD-3:** P6 scope depends entirely on Task 6.0's verdict — may shrink to "documented non-issue."
