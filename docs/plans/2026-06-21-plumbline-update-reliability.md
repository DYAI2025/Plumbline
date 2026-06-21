# Plan: Plumbline Update Reliability — one natural `plumbline update` that installs all new content for every user

Iterative plan, 4 sprints, each with a verifiable sprint goal and RED-contract-first (TDD). Built on
the code-grounded investigation of 2026-06-21 (every claim below carries a file:line anchor).

## Goal
A single natural `plumbline update`, run from anywhere, reliably installs ALL new content into every
user's `~/.claude` — fast, precise, verified-or-reverted. Close the three root causes and cover the
gaps the current tests mask.

## Non-goals
- Not changing the release-please release-cutting flow (`.github/workflows/release-please.yml`).
- Not adding curated release ZIP assets (GitHub's `tarball_url` is sufficient) unless a sprint needs it.
- Not auto-APPLYING updates without consent — auto-CHECK + notify is opt-in; apply stays explicit.
- Not touching the unrelated PRIL `bin/plumbline-*` wrappers.

## Preconditions / baseline (investigation 2026-06-21, code-grounded)
- Entry: `config/claude/bin/plumbline:4` execs `config/claude/lib/plumbline_update.py` (all of
  version/doctor/update/rollback/install live there).
- `repo_root()` (`plumbline_update.py:43-48`) walks up for `config/claude/install.sh`, else falls to
  `Path.cwd()` (`:48`). `read_version` (`:51-58`). `default_repo_slug` (`:137-152`, git origin →
  `$PLUMBLINE_REPO` → literal `DYAI2025/Plumbline` `:25`). `fetch_latest_release` (`:181-199`, **NO
  auth header**; errors re-raised at `:191`). `update_check` (`:318-348`). `update_apply` (`:414-465`,
  target = `--target` or root; only `install.sh --dry-run` at `:440`; `DEFAULT_VERIFY=run_all.sh` `:36`).
- `install.sh`: `transfer()` (`:71-98`) symlink default / `--copy`, **skips existing without `--force`**
  (`:77-80`); `install_bin`/`install_bin_libs` (`:167-182`) copy `bin/*`+`lib/*.py`, write **no anchor**.
- Tests: `test_update_layer.sh` runs everything with `--root "$REPO_DIR"` + local `--source` fixtures;
  the only network test points at a closed port (`PLUMBLINE_GITHUB_API=http://127.0.0.1:1 :189`) and
  asserts the failure string.

## Known gaps (must be closed; currently invisible to CI)
- **G1** cwd-derived identity: VERSION *and* slug come from cwd (no install anchor) → phantom/missing
  version + wrong-slug 404 (reproduced).
- **G2** unauthenticated fetch → 60/hr/IP → intermittent 403/404.
- **G3** `update` never refreshes `~/.claude`: `transfer()` skips changed targets; `update_apply` only
  `install.sh --dry-run` against the checkout.
- **G4** tests pin `--root`/`--source` so G1–G3 pass green.

## Requirements
- REQ-PUR-01 install-identity anchor (version+slug+source_commit+installed_at) written at install.
- REQ-PUR-02 `version`/`update --check` are cwd-INDEPENDENT (anchor-preferred) for the installed copy.
- REQ-PUR-03 token-aware release fetch (auth when a token exists; graceful unauth fallback; 403-rate-limit
  classified distinctly from 404-not-found).
- REQ-PUR-04 `plumbline update` applies into `$CLAUDE_HOME` via the REAL installer (all changed content).
- REQ-PUR-05 install update-mode REFRESHES changed targets (no stale skip).
- REQ-PUR-06 verify-or-revert on apply (snapshot of `$CLAUDE_HOME`).
- REQ-PUR-07 falsifying tests for G1–G3 (never mock the gap; reddens if the fix is reverted).
- REQ-PUR-08 (opt-in) non-intrusive session-start update-check notify.

## Hard safety rule (binding for every task)
Every real test/smoke uses a SANDBOX home — `export CLAUDE_HOME="$(mktemp -d)"` — NEVER the operator's
real `~/.claude`. Snapshot+verify+revert is non-negotiable and itself tested. New bash tests are
bash-3.2-safe (no `$()`-wrapped heredocs; the shell-portability guard covers it), ASCII-only, eval-free.

---

## Sprint 1 — Fixed install identity
**Verifiable sprint goal:** the INSTALLED `plumbline version` and `plumbline update --check` return the
CORRECT installed result from ANY cwd — including inside a foreign repo that has its own `VERSION` and
`origin` — never cwd's value, never "VERSION not found". (REQ-PUR-01/02; closes G1 + the wrong-slug 404.)

- **PUR-1.1 (tester, RED)** — falsifying test in `config/claude/tests/test_update_layer.sh`: install into
  a sandbox `$CLAUDE_HOME`; run the INSTALLED `~/.claude/bin/plumbline version` from `/tmp` and from a
  `/tmp/fakerepo` (own `VERSION=9.9.9`, own git origin) → MUST print the installed version, never `9.9.9`,
  never an error; `update --check` from `/tmp/fakerepo` MUST query `DYAI2025/Plumbline` (the installed
  slug), not the foreign origin. No `--root`. RED now.
  - Acceptance: the assertions fail today (prints `9.9.9` / foreign slug), pass after PUR-1.2/1.3.
- **PUR-1.2 (coder)** — `install.sh` writes `$CLAUDE_HOME/.plumbline-install.json`
  `{version, repo_slug, source_commit, installed_at}` during `install_bin*` (read source `VERSION` + git
  origin, fallback `DYAI2025/Plumbline`). Files: `config/claude/install.sh` (`install_bin`/`install_bin_libs`).
- **PUR-1.3 (coder)** — `plumbline_update.py`: add `resolve_install_identity()` that, when running as the
  installed copy (`__file__` under `$CLAUDE_HOME` / no source `install.sh` above it), reads the anchor and
  is PREFERRED by `read_version` and `default_repo_slug`; cwd fall-through only when an explicit `--root`
  is given (dev use). Files: `plumbline_update.py` (`repo_root`/`read_version`/`default_repo_slug` + new fn).
- **Acceptance evidence:** PUR-1.1 green; manual `plumbline version` from `/` and `/tmp/fakerepo` both
  print the installed version; `--check` from a foreign repo hits `DYAI2025/Plumbline`.
- **Risk/rollback:** old installs lack the anchor → fallback to DEFAULT slug + a clear "re-run install.sh
  to write the identity anchor" notice (never a wrong cwd pick). Rollback: revert the 2 files; the anchor
  file is additive/ignorable.

## Sprint 2 — Authenticated, resilient release fetch
**Verifiable sprint goal:** `update --check` no longer fails from rate-limiting — it sends a token when
one exists (offline-proven), still works unauthenticated, and reports a 403 rate-limit distinctly from a
404. (REQ-PUR-03; closes G2.)

- **PUR-2.1 (tester, RED)** — test (offline, via the injectable `PLUMBLINE_GITHUB_API` seam / a fake
  endpoint): with `GITHUB_TOKEN` set the request carries `Authorization: Bearer <token>`; with none it
  still succeeds unauth (no crash); a 403-with-rate-limit-headers yields a classified "rate-limited"
  message, a 404 yields "release/repo not found" — distinct. Assert the token is NEVER printed. Files:
  `test_update_layer.sh`. RED.
- **PUR-2.2 (coder)** — `fetch_latest_release` reads a token (`GITHUB_TOKEN` → `GH_TOKEN` → `gh auth token`
  if `gh` present) and sets the header; classify 403-rate-limit vs 404; keep the `PLUMBLINE_GITHUB_API`
  seam. Never log the token/header. Files: `plumbline_update.py` (`fetch_latest_release`, error path `:191`).
- **Acceptance evidence:** PUR-2.1 green; a gated, opt-in real `update --check` against `DYAI2025/Plumbline`
  returns up-to-date authenticated → `real-boundary-smoke` (run once, NOT in CI).
- **Risk/rollback:** token leakage → asserted-absent in PUR-2.1. Rollback: revert the function.

## Sprint 3 — The natural update that actually installs (the core)
**Verifiable sprint goal:** `plumbline update` delivers ALL changed content into a SANDBOX `$CLAUDE_HOME`
(refreshes stale agents/commands/skills/libs/bin + adds new), updates the anchor, and on a verify-failure
REVERTS the whole `$CLAUDE_HOME` to the prior state — never touching the real `~/.claude`.
(REQ-PUR-04/05/06; closes G3.)

- **PUR-3.1 (tester, RED)** — headline falsifier in `test_update_layer.sh`: sandbox `$CLAUDE_HOME`
  installed at vN with a deliberately STALE agent + command + lib; stage a newer payload (vN+1); run
  `plumbline update`; assert (a) stale files REFRESHED to vN+1, (b) NEW files added, (c) anchor now vN+1,
  (d) on an injected verify-failure the entire `$CLAUDE_HOME` is REVERTED to vN (snapshot), (e) the real
  `~/.claude` is never written (assert via the sandbox env). RED.
- **PUR-3.2 (coder)** — `install.sh` update-mode: `transfer()` OVERWRITES a changed existing target
  (content-compare, or a `--update`/`--force-refresh` flag) instead of skipping; expose `install.sh
  --update` that refreshes agents/commands/skills/libs/bin and rewrites the anchor. Files: `install.sh`
  (`transfer` `:71-98`, arg parsing).
- **PUR-3.3 (coder)** — `update_apply` (no `--target`) applies into `$CLAUDE_HOME`: stage payload →
  snapshot `$CLAUDE_HOME` → run the REAL `install.sh --update` (NOT `--dry-run`) into `$CLAUDE_HOME` →
  verify (`DEFAULT_VERIFY` or the payload's `compatibility.verifyCommand`) from the staged checkout →
  revert-on-fail. Keep checkout-patching as the explicit `--target <checkout>` path. Files:
  `plumbline_update.py` (`update_apply`/`_apply_from_source` `:414-465`, `resolve_payload_source` `:282`).
- **Acceptance evidence:** PUR-3.1 green; a real sandbox-`$CLAUDE_HOME` `update` vN→vN+1 refreshes a
  known-changed file and reverts on a forced verify-fail → `real-boundary-smoke` (sandbox HOME only).
- **Risk/rollback (HIGH — touches every user's install):** a broken update could brick `~/.claude`.
  Mitigations: snapshot+verify+revert mandatory and tested (PUR-3.1d); smokes run against a SANDBOX
  `$CLAUDE_HOME` ONLY; no test ever runs the real installer against the real HOME; symlink-mode installs
  already auto-refresh (this fix matters most for `--copy`/web installs). Rollback: revert
  `plumbline_update.py` + `install.sh`; anchor + snapshot are additive.

## Sprint 4 — Cover the masked gaps + opt-in auto-check
**Verifiable sprint goal:** reverting ANY Sprint-1/2/3 fix reddens a falsifying test in `run_all`; and an
opt-in session-start check notifies only when behind, never blocks. (REQ-PUR-07/08; closes G4.)

- **PUR-4.1 (tester)** — confirm the Sprint-1/2/3 falsifiers are wired into `run_all.sh` and are
  behaviour/counter falsifiers (red if the fix is reverted), not outcome-only; add the missing
  "re-run refreshes a changed file" assertion if not already covered by PUR-3.1. Files:
  `test_update_layer.sh`, `run_all.sh`.
- **PUR-4.2 (coder, opt-in)** — `config/claude/hooks/session-start.sh` (or a new hook): a non-blocking,
  throttled (≤1/day, cached) `plumbline update --check`; on "behind" print `update available: vN→vM, run
  \`plumbline update\``; silent when current; env-gated/off-by-default; never blocks the session. Files:
  `config/claude/hooks/session-start.sh`.
- **Acceptance evidence:** reverting each fix reddens its falsifier; the auto-check notifies on a behind
  sandbox, is silent when current, and adds no blocking latency.
- **Risk/rollback:** auto-check noise/rate-limit → throttle + Sprint-2 auth; opt-in. Rollback: revert hook.

---

## Cross-cutting end state (the plan's verifiable definition of done)
From any cwd (incl. a foreign repo): installed `plumbline version` → the installed version; `plumbline
update --check` → queries `DYAI2025/Plumbline` authenticated, resilient to rate limits; `plumbline update`
→ refreshes a sandbox `$CLAUDE_HOME` with ALL changed content, verified-or-reverted; reverting any fix
reddens a falsifying test. Reality ledger: `integration-fake` for the offline mechanics +
`real-boundary-smoke` for the gated live `update --check` and the sandbox-HOME apply.

## Global risks & rollback
- Highest risk is user-facing install tooling for everyone → the SANDBOX-`$CLAUDE_HOME` rule + mandatory,
  tested snapshot/verify/revert are the safety floor; the headline smokes never run against a real HOME.
- Each sprint is independently shippable and revertible (git revert the touched files; the anchor file is
  additive). Run the sprints in order (Sprint 3 depends on Sprint 1's anchor + Sprint 2's fetch).
- Execute via `/agileteam` per sprint (Canvas confirming the scope = the listed files; RED contract first;
  independent review; the sandbox-HOME real-boundary-smoke before each sprint's acceptance).
