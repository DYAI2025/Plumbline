# PRD: Plumbline Update Reliability

Status: user-confirmed
Feature-Slug: plumbline-update-reliability
Canvas: docs/canvas/plumbline-update-reliability.canvas.md (user-confirmed 2026-06-21)
Vision: docs/vision/plumbline-update-reliability.vision.md (user-confirmed 2026-06-21)
Plan: docs/plans/2026-06-21-plumbline-update-reliability.md

> Authored only (docs, no production code; not yet committed). The Product Canvas and Product
> Vision were explicitly confirmed by the user (Ben) on 2026-06-21 via the exact confirmation
> phrase, so this PRD is finalized `user-confirmed` and may serve as the basis for AgileTeam
> planning. REQ IDs are stable and taken verbatim from the plan (REQ-PUR-01..08) — do NOT
> renumber. Every requirement is grounded in the code-grounded investigation 2026-06-21
> (file:line anchors carried below).

## 1. Summary

One natural `plumbline update`, run from anywhere, reliably installs ALL new content into every
user's `~/.claude` — fast, precise, verified-or-reverted. The feature closes three reproduced
root causes (no install identity; unauthenticated fetch; update never refreshes `~/.claude`) and
covers a fourth that lets tests mask them. The binding safety rule: every real test/smoke uses a
SANDBOX `$CLAUDE_HOME`; snapshot+verify+revert is mandatory and itself tested; no test ever runs
the real installer against the operator's real `~/.claude`.

## 2. Problem Statement (root causes, code-grounded 2026-06-21)

- `EXPLICIT` G1 — cwd-derived identity: VERSION and slug both come from cwd, no install anchor
  (`plumbline_update.py:43-48` falls to `Path.cwd()` `:48`; `read_version` `:51-58`;
  `default_repo_slug` `:137-152`) → phantom/missing version + wrong-slug 404 (reproduced).
- `EXPLICIT` G2 — unauthenticated fetch: `fetch_latest_release` (`:181-199`) sends NO auth header,
  re-raises at `:191` → 60-req/hr/IP limit → intermittent 403/404, with no 403-vs-404 distinction.
- `EXPLICIT` G3 — update never refreshes `~/.claude`: `transfer()` (`install.sh:71-98`) skips an
  existing target without `--force` (`:77-80`); `update_apply` (`:414-465`) only runs
  `install.sh --dry-run` (`:440`) against the checkout.
- `EXPLICIT` G4 — tests mask the gaps: `test_update_layer.sh` pins `--root "$REPO_DIR"` + local
  `--source` fixtures; the only network test points at a closed port
  (`PLUMBLINE_GITHUB_API=http://127.0.0.1:1`, `:189`) and asserts the failure string → G1–G3
  stay green.

## 3. Goals

| ID | Goal | Status |
|---|---|---|
| GOAL-PUR-01 | Installed identity is fixed at install (version+slug+source_commit+installed_at). | EXPLICIT |
| GOAL-PUR-02 | `version`/`update --check` are cwd-independent for the installed copy in BOTH modes (anchor for copy installs; the symlinked checkout's current VERSION/origin for symlink installs). | EXPLICIT |
| GOAL-PUR-03 | Release fetch is token-aware, rate-limit-resilient, 403-vs-404-distinct. | EXPLICIT |
| GOAL-PUR-04 | `plumbline update` applies ALL changed content into `$CLAUDE_HOME` via the real installer. | EXPLICIT |
| GOAL-PUR-05 | Install update-mode refreshes changed targets (no stale skip). | EXPLICIT |
| GOAL-PUR-06 | Verify-or-revert (snapshot of `$CLAUDE_HOME`) on apply. | EXPLICIT |
| GOAL-PUR-07 | Falsifying tests for G1–G3 (never mock the gap; red if the fix is reverted). | EXPLICIT |
| GOAL-PUR-08 | On-by-default / opt-out, non-blocking, notify-only session-start update-check. | EXPLICIT |

## 4. Non-Goals

| ID | Non-Goal |
|---|---|
| NGOAL-PUR-01 | No change to the release-please release-cutting flow (`.github/workflows/release-please.yml`). |
| NGOAL-PUR-02 | No curated release ZIP assets (GitHub `tarball_url` suffices) unless a sprint needs it. |
| NGOAL-PUR-03 | No auto-APPLY without consent; auto-CHECK + notify is on-by-default / opt-out (env to disable; per OQ-PUR-02) and notify-only; apply stays explicit (a CHECK is not an apply). |
| NGOAL-PUR-04 | No touching the unrelated PRIL `bin/plumbline-*` wrappers. |

## 5. Functional Requirements (REQ IDs are STABLE — verbatim from the plan)

### REQ-PUR-01 — Install-identity anchor

`EXPLICIT`: `install.sh` writes `$CLAUDE_HOME/.plumbline-install.json`
`{version, repo_slug, source_commit, installed_at}` during `install_bin*` (read source `VERSION`
+ git origin; fallback `DYAI2025/Plumbline`). Files: `config/claude/install.sh`
(`install_bin`/`install_bin_libs` `:167-182`).

Acceptance criteria (Given/When/Then):
- AC-PUR-01.1 — **Given** a fresh install into a sandbox `$CLAUDE_HOME`, **when** `install.sh`
  runs `install_bin`/`install_bin_libs`, **then** `$CLAUDE_HOME/.plumbline-install.json` exists
  and contains `version`, `repo_slug`, `source_commit`, `installed_at`.
- AC-PUR-01.2 — **Given** the source `VERSION` and git origin are readable, **when** the anchor
  is written, **then** `version` equals the source `VERSION` and `repo_slug` equals the origin
  slug; **and given** no readable origin, **then** `repo_slug` falls back to `DYAI2025/Plumbline`.

### REQ-PUR-02 — cwd-independent installed identity (two-mode, honestly sourced)

> **Refinement (C1, user/Ben, 2026-06-21):** installed identity is **cwd-INDEPENDENT in BOTH
> install modes**, but sourced honestly per mode rather than from a single "anchor authoritative
> regardless of mode/cwd" rule (which would report a stale install-time version for a symlink
> install after a `git pull`). This refines the earlier "anchor-preferred / anchor-authoritative"
> wording; the True-Line invariant "correct INSTALLED identity from any cwd" is unchanged — it now
> explicitly covers both modes via their honest source. User's own refinement; status stays
> `user-confirmed`.

`EXPLICIT`: `plumbline_update.py` adds `resolve_install_identity()` that, when running as the
installed copy (`__file__` under `$CLAUDE_HOME` / no source `install.sh` above it), is
cwd-INDEPENDENT in BOTH modes, sourcing identity by install mode:
- **copy installs** (web-bootstrap / Windows / frozen): identity comes from the
  `.plumbline-install.json` ANCHOR (the install-time `version`+`repo_slug`); natural update path =
  `plumbline update` (Sprint 3 re-stamps the anchor on apply).
- **symlink installs** (the dev default): the install IS the live checkout — identity is the
  (symlinked) checkout's CURRENT `VERSION` + git origin, which is cwd-INDEPENDENT because the
  symlink is a fixed anchor to the checkout (NOT cwd); natural update path = `git pull` (forcing
  the install-time anchor here would report a STALE version after a pull — wrong; so
  symlink-tracks-checkout is intended).

In both modes cwd is never the identity source; cwd/root fall-through applies only when an explicit
`--root` is given (dev use). Files: `plumbline_update.py`
(`repo_root`/`read_version`/`default_repo_slug` `:43-58,:137-152` + new fn). Closes G1.

Acceptance criteria (Given/When/Then):
- AC-PUR-02.1 — **Given** an installed `~/.claude/bin/plumbline` and cwd `/tmp`, **when**
  `plumbline version` runs (no `--root`), **then** it prints the INSTALLED version, never an error.
- AC-PUR-02.2 — **Given** cwd is a foreign repo `/tmp/fakerepo` with its own `VERSION=9.9.9` and
  its own git origin, **when** `plumbline version` runs, **then** it prints the installed version
  (never `9.9.9`); **and when** `plumbline update --check` runs, **then** it queries
  `DYAI2025/Plumbline` (the installed slug), never the foreign origin.
- AC-PUR-02.3 — **Given** an explicit `--root <dev-checkout>`, **when** `version` runs, **then**
  cwd/root fall-through applies (dev use preserved).
- AC-PUR-02.4 — **Given** a COPY install with an old anchor-less or anchor-bearing state but NO
  resolvable identity (e.g. anchor missing on a copy install), **when** identity resolves, **then**
  it falls back to the DEFAULT slug + emits a clear "re-run install.sh to write the identity
  anchor" notice (never a wrong cwd pick).
- AC-PUR-02.5 — **Given** a SYMLINK install whose checkout has been advanced by `git pull` from vN
  to vN+1, **when** `plumbline version` runs from a foreign cwd, **then** it prints vN+1 (the
  checkout's CURRENT `VERSION`, cwd-independent) — NOT a stale install-time vN and NOT the foreign
  cwd's version. (Proves symlink-mode identity tracks the checkout, not a frozen anchor, while
  staying cwd-independent.)

Per-mode update path: copy installs update via `plumbline update` (Sprint 3); symlink installs
update via `git pull` on the checkout the symlink points at.

### REQ-PUR-03 — token-aware, resilient release fetch

`EXPLICIT`: `fetch_latest_release` reads a token (`GITHUB_TOKEN` → `GH_TOKEN` → `gh auth token`
if `gh` present) and sets the `Authorization` header; classifies 403-rate-limit vs 404-not-found
distinctly; keeps the injectable `PLUMBLINE_GITHUB_API` seam; never logs the token/header. Files:
`plumbline_update.py` (`fetch_latest_release` `:181-199`, error path `:191`). Closes G2.

Acceptance criteria (Given/When/Then):
- AC-PUR-03.1 — **Given** `GITHUB_TOKEN` is set and a fake endpoint via `PLUMBLINE_GITHUB_API`,
  **when** `update --check` runs, **then** the request carries `Authorization: Bearer <token>`.
- AC-PUR-03.2 — **Given** no token, **when** `update --check` runs, **then** it still succeeds
  unauthenticated (no crash).
- AC-PUR-03.3 — **Given** the endpoint returns 403 with rate-limit headers, **when** the fetch
  runs, **then** the message is classified "rate-limited"; **and given** a 404, **then** the
  message is "release/repo not found" — the two are distinct.
- AC-PUR-03.4 — **Given** any of the above, **when** output/logs are produced, **then** the token
  is NEVER printed.

### REQ-PUR-04 — natural update applies into `$CLAUDE_HOME` via the REAL installer

`EXPLICIT`: `update_apply` (no `--target`) applies into `$CLAUDE_HOME`: stage payload → snapshot
`$CLAUDE_HOME` → run the REAL `install.sh --update` (NOT `--dry-run`) into `$CLAUDE_HOME` →
verify → revert-on-fail. Checkout-patching stays the explicit `--target <checkout>` path. Files:
`plumbline_update.py` (`update_apply`/`_apply_from_source` `:414-465`, `resolve_payload_source`
`:282`). Closes G3 (apply half).

Acceptance criteria (Given/When/Then):
- AC-PUR-04.1 — **Given** a sandbox `$CLAUDE_HOME` installed at vN and a staged vN+1 payload,
  **when** `plumbline update` runs (no `--target`), **then** the real `install.sh --update` is
  invoked into `$CLAUDE_HOME` (NOT `--dry-run`).
- AC-PUR-04.2 — **Given** the apply completes and verification passes, **when** it finishes,
  **then** the anchor reads vN+1.
- AC-PUR-04.3 — **Given** an explicit `--target <checkout>`, **when** `update` runs, **then** the
  checkout-patching path is used (the prior behaviour is preserved as an explicit mode).
- AC-PUR-04.4 — **Given** any test/smoke, **when** apply runs, **then** the real `~/.claude` is
  NEVER written (asserted via the sandbox env).

### REQ-PUR-05 — install update-mode refreshes changed targets (no stale skip)

`EXPLICIT`: `install.sh` update-mode: `transfer()` content-compares and OVERWRITES every CHANGED
existing target in BOTH modes (symlink AND `--copy`) instead of skipping — not a two-path
symlink-vs-copy variant (resolved OQ-PUR-01, user 2026-06-21: content-compare + overwrite in both
modes is the most reliable "all changed content lands for every user"). Expose `install.sh
--update` that refreshes agents/commands/skills/libs/bin and rewrites the anchor. Files:
`install.sh` (`transfer` `:71-98`, arg parsing). Closes G3 (refresh half).

Acceptance criteria (Given/When/Then):
- AC-PUR-05.1 — **Given** a sandbox `$CLAUDE_HOME` with a deliberately STALE agent + command +
  lib at vN, **when** `install.sh --update` runs with a vN+1 source, **then** the stale files are
  content-compared and REFRESHED to vN+1 (no skip) — in BOTH symlink and `--copy` modes.
- AC-PUR-05.2 — **Given** the vN+1 source contains NEW files absent from `$CLAUDE_HOME`, **when**
  `install.sh --update` runs, **then** the new files are added.
- AC-PUR-05.3 — **Given** `install.sh --update` completes, **when** it finishes, **then** the
  anchor is rewritten to vN+1.

### REQ-PUR-06 — verify-or-revert on apply (snapshot of `$CLAUDE_HOME`)

`EXPLICIT`: `update_apply` snapshots `$CLAUDE_HOME` before the real install, verifies via
`DEFAULT_VERIFY` (`run_all.sh`, `:36`) or the payload's `compatibility.verifyCommand` from the
staged checkout, and reverts the whole `$CLAUDE_HOME` to the prior snapshot on a verify-failure.
Files: `plumbline_update.py` (`update_apply` `:414-465`).

Acceptance criteria (Given/When/Then):
- AC-PUR-06.1 — **Given** a sandbox `$CLAUDE_HOME` at vN and an injected verify-FAILURE during a
  vN→vN+1 apply, **when** `plumbline update` runs, **then** the entire `$CLAUDE_HOME` is REVERTED
  to the vN snapshot (state byte-identical to pre-apply).
- AC-PUR-06.2 — **Given** verification passes, **when** apply finishes, **then** the snapshot is
  released and the vN+1 state is kept.
- AC-PUR-06.3 — **Given** the snapshot/verify/revert mechanism, **when** the test suite runs,
  **then** the mechanism itself is exercised by a test (not assumed).

### REQ-PUR-07 — falsifying tests for G1–G3 (never mock the gap)

`EXPLICIT`: confirm the Sprint-1/2/3 falsifiers are wired into `run_all.sh` and are
behaviour/counter falsifiers (red if the fix is reverted), not outcome-only; add the missing
"re-run refreshes a changed file" assertion if not covered by PUR-3.1. Files:
`test_update_layer.sh`, `run_all.sh`. Closes G4.

Acceptance criteria (Given/When/Then):
- AC-PUR-07.1 — **Given** the Sprint-1 identity fix is reverted, **when** `run_all.sh` runs,
  **then** the identity falsifier turns RED (prints `9.9.9`/foreign slug).
- AC-PUR-07.2 — **Given** the Sprint-2 token/classification fix is reverted, **when** `run_all.sh`
  runs, **then** the fetch falsifier turns RED.
- AC-PUR-07.3 — **Given** the Sprint-3 refresh/apply/revert fix is reverted, **when** `run_all.sh`
  runs, **then** the apply falsifier turns RED (stale not refreshed / not reverted).
- AC-PUR-07.4 — **Given** the test suite, **when** `run_all.sh` runs in CI, **then** all update
  falsifiers are wired in and pass with the fixes in place.

### REQ-PUR-08 — on-by-default / opt-out, non-blocking session-start update-check notify

`EXPLICIT`: `config/claude/hooks/session-start.sh` (or a new hook) performs a non-blocking,
throttled (≤1/day, cached) `plumbline update --check`; on "behind" prints `update available:
vN→vM, run \`plumbline update\``; silent when current; ON by default with an env opt-out (resolved
OQ-PUR-02, user 2026-06-21); authenticated per Sprint 2; never blocks the session; NOTIFY-only (a
CHECK is not an apply — APPLY stays explicit, NFR-PUR-06 unchanged). Files:
`config/claude/hooks/session-start.sh`.

Acceptance criteria (Given/When/Then):
- AC-PUR-08.1 — **Given** the auto-check env opt-out is SET (disabled), **when** a session starts,
  **then** no update-check runs and nothing is printed.
- AC-PUR-08.2 — **Given** the default (opt-out NOT set → check ON) and the sandbox install is
  BEHIND, **when** a session starts, **then** it prints `update available: vN→vM, run \`plumbline
  update\`` and does NOT block the session (notify-only, no apply).
- AC-PUR-08.3 — **Given** the default (check ON) and the install is CURRENT, **when** a session
  starts, **then** the check is silent.
- AC-PUR-08.4 — **Given** the default (check ON), **when** sessions start within the throttle
  window, **then** the check runs at most once per day (cached).

## 6. Non-Functional Requirements

| ID | NFR | Status |
|---|---|---|
| NFR-PUR-01 | **SANDBOX-`$CLAUDE_HOME` safety:** every real test/smoke uses `export CLAUDE_HOME="$(mktemp -d)"`; NO test touches the operator's real `~/.claude`. | EXPLICIT (binding) |
| NFR-PUR-02 | **Verify-or-revert:** apply snapshots `$CLAUDE_HOME` and reverts on a verify-failure; the mechanism is itself tested. | EXPLICIT |
| NFR-PUR-03 | **No-mock-the-gap:** falsifiers are behaviour/counter-based; reverting a fix reddens CI. | EXPLICIT |
| NFR-PUR-04 | **bash-3.2-safe tests:** no `$()`-wrapped heredocs (macOS bash-3.2 CI is the strict OS); ASCII-only; eval-free. | EXPLICIT |
| NFR-PUR-05 | **Token never logged:** the GitHub token/header is never printed or written to any log/output. | EXPLICIT |
| NFR-PUR-06 | **Never auto-apply without consent:** apply stays explicit (never auto-applied). The auto-CHECK is on-by-default / opt-out (env to disable; per OQ-PUR-02), non-blocking, and notify-only — a CHECK is not an apply, so this is consistent with the never-auto-apply invariant. | EXPLICIT |
| NFR-PUR-07 | **Additive/revertible:** the anchor and the snapshot are additive; each sprint is independently revertible (git revert the touched files). | EXPLICIT |

## 7. Implementation phases (the plan's 4 sprints)

| Phase | Sprint | REQs | Verifiable sprint goal | Files |
|---|---|---|---|---|
| P1 | Sprint 1 — Fixed install identity | REQ-PUR-01, REQ-PUR-02 | Installed `version`/`--check` correct from ANY cwd incl. a foreign repo, in BOTH install modes (anchor for copy; symlinked checkout for symlink — both cwd-independent); closes G1 + wrong-slug 404. | `install.sh`, `plumbline_update.py`, `test_update_layer.sh` |
| P2 | Sprint 2 — Authenticated, resilient fetch | REQ-PUR-03 | `--check` token-aware, unauth-fallback, 403-vs-404 distinct; closes G2. | `plumbline_update.py`, `test_update_layer.sh` |
| P3 | Sprint 3 — The natural update that actually installs | REQ-PUR-04, REQ-PUR-05, REQ-PUR-06 | `update` delivers ALL changed content into a sandbox `$CLAUDE_HOME`, anchor updated, verify-or-revert; closes G3. **HIGH-risk** (touches every install). | `install.sh`, `plumbline_update.py`, `test_update_layer.sh` |
| P4 | Sprint 4 — Cover masked gaps + on-by-default/opt-out auto-check | REQ-PUR-07, REQ-PUR-08 | Reverting any Sprint-1/2/3 fix reddens a falsifier; on-by-default (env opt-out) notify-only session-start check notifies when behind, never blocks; closes G4. | `test_update_layer.sh`, `run_all.sh`, `session-start.sh` |

Ordering: run sprints in order — Sprint 3 depends on Sprint 1's anchor + Sprint 2's fetch. Each
sprint is independently shippable and revertible.

## 8. Reality Ledger (honest ceiling)

`integration-fake` for the offline mechanics (cwd-independent identity, token-on-header +
unauth-fallback + 403/404 classification via the injectable seam, headline apply/refresh/revert
into a sandbox `$CLAUDE_HOME`, falsifiers). `real-boundary-smoke` for the gated, opt-in real
`update --check` against `DYAI2025/Plumbline` (run once, NOT in CI) AND the real sandbox-HOME
apply vN→vN+1 (sandbox HOME only). No claim of "every user's real HOME upgraded" is made by tests
— that is the user-facing capability the smoke evidences against a sandbox, not the real HOME.

## 9. Traceability stub

Full matrix in `docs/traceability.md` (slice block: plumbline-update-reliability).

| REQ | AC | Test | Evidence class |
|---|---|---|---|
| REQ-PUR-01 | AC-PUR-01.1/.2 | test_update_layer.sh | integration-fake |
| REQ-PUR-02 | AC-PUR-02.1..5 | test_update_layer.sh | integration-fake |
| REQ-PUR-03 | AC-PUR-03.1..4 | test_update_layer.sh | integration-fake (+ gated real-boundary-smoke for live `--check`) |
| REQ-PUR-04 | AC-PUR-04.1..4 | test_update_layer.sh | integration-fake (+ real-boundary-smoke: sandbox-HOME apply) |
| REQ-PUR-05 | AC-PUR-05.1..3 | test_update_layer.sh | integration-fake |
| REQ-PUR-06 | AC-PUR-06.1..3 | test_update_layer.sh | integration-fake (+ real-boundary-smoke: sandbox-HOME revert) |
| REQ-PUR-07 | AC-PUR-07.1..4 | test_update_layer.sh + run_all.sh | integration-fake |
| REQ-PUR-08 | AC-PUR-08.1..4 | test_update_layer.sh (+ session-start.sh) | integration-fake |

## 10. Open Questions

- OQ-PUR-01 — symlink-mode auto-refresh vs `--copy` force-refresh default (affects REQ-PUR-05 /
  PUR-3.2): content-compare+overwrite for both modes, or re-link symlinks + force-refresh copies?
  RESOLVED (user, 2026-06-21) — content-compare + overwrite in BOTH modes: `install.sh --update`
  content-compares and overwrites every CHANGED target regardless of symlink/copy mode (most
  reliable "all changed content lands for every user").
- OQ-PUR-02 — auto-check opt-in default on/off (affects REQ-PUR-08 / PUR-4.2): plan says
  opt-in/off-by-default; confirm. RESOLVED (user, 2026-06-21) — auto-check ON by default /
  opt-out: the session-start `update --check` runs by default (throttled ≤1/day, authenticated
  per Sprint 2, non-blocking) and only NOTIFIES; disabled via an env opt-out. APPLY stays
  explicit (a CHECK is not an apply; NFR-PUR-06 unchanged).

## 11. Definition of Ready (Phase 0)

- [x] Product Canvas confirmed by user (user-confirmed 2026-06-21).
- [x] This PRD confirmed by user (user-confirmed 2026-06-21).
- [x] Product Vision authored and confirmed by user (user-confirmed 2026-06-21).
- [x] OQ-PUR-01, OQ-PUR-02 resolved with the user (2026-06-21).
- [x] REQ IDs stable + grounded in the plan/investigation.
- [x] Acceptance criteria in Given/When/Then with observable results.
- [x] Allowed change scope machine-parseable + `plumbline-scope-check` validated.
- [x] Traceability slice authored (REQ → AC → test → evidence class → wired-in-prod → True-Line).
