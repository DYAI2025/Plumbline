# Product Canvas: Plumbline Update Reliability

Status: user-confirmed
Owner: requirements-analyst
Confirmed by user: yes
Confirmation date: 2026-06-21
Canvas file: docs/canvas/plumbline-update-reliability.canvas.md
Feature-Slug: plumbline-update-reliability
Plan: docs/plans/2026-06-21-plumbline-update-reliability.md

> The Product Canvas is a mandatory pre-build value-alignment artifact. `/agileteam`
> may not finalize the PRD or enter development until this canvas is filled in well
> enough, saved, linked to PRD/Vision/traceability, and explicitly confirmed by the
> user. No agent may self-confirm it. The user gave the exact confirmation phrase on
> 2026-06-21, so this Canvas is now `user-confirmed` and may serve as the basis for
> AgileTeam planning. This intake is authored only (docs, no production code; not yet
> committed).

---

## 1. Problem

What real problem should be solved?

Status: CONFIRMED

Answer:
`EXPLICIT` (investigation 2026-06-21, code-grounded): `plumbline update` does not reliably
install new content into a user's `~/.claude`. The 2026-06-21 investigation reproduced three
root causes, all currently invisible to CI:

- `EXPLICIT` G1 — **no install identity.** Both the installed VERSION and the repo slug are
  derived from the current working directory (`repo_root()` falls to `Path.cwd()` at
  `plumbline_update.py:48`; `read_version` `:51-58`; `default_repo_slug` `:137-152`). Run from
  a foreign repo with its own `VERSION`/`origin`, the tool reports a phantom/wrong version and
  hits a wrong-slug 404. Reproduced.
- `EXPLICIT` G2 — **unauthenticated fetch.** `fetch_latest_release` (`:181-199`) sends no auth
  header and re-raises on error (`:191`), so GitHub's 60-req/hr/IP unauthenticated limit causes
  intermittent 403/404, and a 403-rate-limit is not distinguished from a 404-not-found.
- `EXPLICIT` G3 — **update never refreshes `~/.claude`.** `install.sh transfer()` (`:71-98`)
  skips an existing target without `--force` (`:77-80`), and `update_apply` (`:414-465`) only
  runs `install.sh --dry-run` (`:440`) against the checkout — so changed agents/commands/skills
  are never written into the user's HOME.
- `EXPLICIT` G4 — **tests mask the gaps.** `test_update_layer.sh` pins `--root "$REPO_DIR"` and
  local `--source` fixtures; the only network test points at a closed port
  (`PLUMBLINE_GITHUB_API=http://127.0.0.1:1`, `:189`) and asserts the failure string — so
  G1–G3 stay green in CI.

---

## 2. Target user / customer

Who has this problem?

Status: CONFIRMED

Answer:
- `EXPLICIT` Every Plumbline user/operator who installs the framework and later runs
  `plumbline update` to pull new agents/commands/skills/libs/bin into `~/.claude`. The
  `--copy`/web-bootstrap installs are most affected (symlink-mode installs already auto-refresh).
- `EXPLICIT` The framework maintainer, who needs a single natural update path that demonstrably
  delivers every new artifact to every user and is provable in CI (no masked gaps).

---

## 3. Current workaround

How is the problem handled today?

Status: CONFIRMED

Answer:
`EXPLICIT`: Today there is no reliable natural path. A symlink-mode install picks up repo
changes for free (the symlink points back at the checkout), but a `--copy`/web-bootstrap user
must manually re-clone and re-run `install.sh --force`, or hand-copy changed files, because
`plumbline update` only dry-runs the installer against the checkout and `transfer()` skips
changed targets. Version/slug are read from cwd, so even checking "am I behind?" is unreliable
from any directory other than the repo root.

---

## 4. Value proposition

What concrete human/customer value will this create?

Status: CONFIRMED

Answer:
`EXPLICIT`: One natural `plumbline update`, run from anywhere, reliably installs ALL new content
into every user's `~/.claude` — fast, precise, and verified-or-reverted. Concretely:

- `EXPLICIT` correct installed version + slug from ANY cwd, in BOTH install modes, each honestly
  sourced (copy installs: the `.plumbline-install.json` anchor; symlink installs: the symlinked
  checkout's current VERSION + git origin) — cwd-independent in both cases (C1 refinement, user/Ben
  2026-06-21);
- `EXPLICIT` token-aware, rate-limit-resilient release check that classifies 403 vs 404;
- `EXPLICIT` an apply that refreshes stale content and adds new content into `$CLAUDE_HOME`
  through the REAL installer, with a snapshot/verify/revert safety floor;
- `EXPLICIT` falsifying tests so reverting any fix reddens CI (the gap can no longer hide).

---

## 5. Success signal

How will we know this is valuable?

Status: CONFIRMED

Answer:
`EXPLICIT` (plan's verifiable definition of done):
- From any cwd (incl. a foreign repo with its own `VERSION=9.9.9`/origin): installed
  `plumbline version` prints the installed version (never `9.9.9`, never an error); `update
  --check` queries `DYAI2025/Plumbline`, authenticated and rate-limit-resilient.
- `plumbline update` into a SANDBOX `$CLAUDE_HOME` refreshes a known-stale agent/command/lib,
  adds new files, rewrites the anchor, and on an injected verify-failure REVERTS the whole
  `$CLAUDE_HOME` to the prior snapshot — never touching the real `~/.claude`.
- Reverting ANY Sprint-1/2/3 fix reddens a falsifying test in `run_all.sh`.
- Reality ledger: `integration-fake` for offline mechanics; `real-boundary-smoke` for the gated
  live `update --check` and the sandbox-HOME apply.

---

## 6. Core use case

What is the smallest meaningful use case?

Status: CONFIRMED

Answer:
`EXPLICIT`: A `--copy`/web-bootstrap user upgrades. They run `plumbline update` from their
working directory (not the repo root). The tool reads its install-identity anchor to learn its
version + slug, queries `DYAI2025/Plumbline` (authenticated when a token exists), sees it is
behind, stages the new payload, snapshots `$CLAUDE_HOME`, runs the real `install.sh --update`
into `$CLAUDE_HOME` (refreshing changed agents/commands/skills/libs/bin and adding new ones),
verifies, and rewrites the anchor — reverting to the snapshot if verification fails.

---

## 7. Non-goals

What should explicitly not be built?

Status: CONFIRMED

Answer (from the plan's non-goals):
- `EXPLICIT` NGOAL — Not changing the release-please release-cutting flow
  (`.github/workflows/release-please.yml`).
- `EXPLICIT` NGOAL — Not adding curated release ZIP assets (GitHub's `tarball_url` is
  sufficient) unless a sprint needs it.
- `EXPLICIT` NGOAL — Not auto-APPLYING updates without consent. Auto-CHECK + notify is
  on-by-default / opt-out (env to disable; per OQ-PUR-02); apply stays explicit. A CHECK is not
  an apply.
- `EXPLICIT` NGOAL — Not touching the unrelated PRIL `bin/plumbline-*` wrappers.

---

## 8. Risks / contradictions

What could make this wrong, useless, unsafe, misleading, too broad, or misaligned?

Status: CONFIRMED

Answer:

| ID | Risk | Likelihood | Impact | Mitigation | Status |
|---|---|---:|---:|---|---|
| RISK-PUR-001 | **A broken update bricks every user's `~/.claude`** (touches everyone's install tooling). | low | HIGH | SANDBOX-`$CLAUDE_HOME` rule for every test/smoke; mandatory, itself-tested snapshot+verify+revert (PUR-3.1d); headline smokes NEVER run against the real HOME. | CONFIRMED (residual: snapshot scope must capture all of `$CLAUDE_HOME` that the installer writes). |
| RISK-PUR-002 | GitHub token leaked into logs. | medium | high | Token/header never logged; PUR-2.1 asserts the token is never printed. | CONFIRMED |
| RISK-PUR-003 | Old installs predate the identity anchor → no anchor to read. | medium | medium | Fall back to the DEFAULT slug + a clear "re-run install.sh to write the identity anchor" notice — never a wrong cwd pick. | CONFIRMED |
| RISK-PUR-004 | Rate-limiting still blocks `update --check`. | medium | medium | Token-aware fetch (Sprint 2) + on-by-default auto-check throttle (≤1/day, cached); env opt-out (per OQ-PUR-02). | CONFIRMED |
| RISK-PUR-005 | Auto-check noise / blocking the session. | medium | low | On-by-default / opt-out (env to disable), non-blocking, throttled, notify-only; silent when current. | CONFIRMED |
| RISK-PUR-006 | Falsifiers are outcome-only (still pass when the fix is reverted). | medium | high | PUR-4.1: behaviour/counter falsifiers, ≥1 per gap, red when the fix is reverted; wired into `run_all.sh`. | CONFIRMED |
| RISK-PUR-007 | New bash tests break on macOS bash-3.2 CI. | medium | medium | bash-3.2-safe (no `$()`-wrapped heredocs; the shell-portability guard covers it), ASCII-only, eval-free. | CONFIRMED |

Contradiction check: none found between requirements. The "natural update installs everything"
goal and the "never auto-apply without consent" non-goal are consistent — apply is explicit; the
on-by-default piece is CHECK + notify only (a CHECK is not an apply; per OQ-PUR-02).

---

## 9. Evidence needed

What must be verified before implementation can be considered real?

Status: CONFIRMED

Answer:
- `EXPLICIT` Offline (`integration-fake`): cwd-independent identity from `/tmp` + a foreign repo;
  token-on-header + unauth-fallback + 403-vs-404 classification + token-never-printed; headline
  apply into a sandbox `$CLAUDE_HOME` refreshing stale + adding new + anchor rewrite + revert on
  injected verify-fail + real-HOME-never-written; falsifiers red when each fix is reverted.
- `EXPLICIT` Real boundary (`real-boundary-smoke`, gated, NOT in CI): an opt-in real `update
  --check` against `DYAI2025/Plumbline` authenticated; and a real sandbox-`$CLAUDE_HOME`
  `update` vN→vN+1 that refreshes a known-changed file and reverts on a forced verify-fail.
- `EXPLICIT` SANDBOX safety: no test or smoke ever runs the real installer against the real
  `~/.claude`; the snapshot/verify/revert mechanism is itself tested.

---

## Allowed change scope

List the only repo-relative files, directories, or glob patterns that implementation agents may
edit for this feature. Machine-parseable (PRIL `plumbline-scope-check`): one path/glob per line.

Status: CONFIRMED (user-confirmed 2026-06-21 at the pre-build gate)

Allowed change scope:

- `config/claude/lib/plumbline_update.py`
- `config/claude/install.sh`
- `config/claude/tests/test_update_layer.sh`
- `config/claude/tests/run_all.sh`
- `config/claude/hooks/session-start.sh`
- `docs/canvas/plumbline-update-reliability.canvas.md`
- `docs/prd/plumbline-update-reliability.prd.md`
- `docs/vision/plumbline-update-reliability.vision.md`
- `docs/reality/plumbline-update-reliability.evidence.jsonl`
- `docs/trace/plumbline-update-reliability.trace.md`
- `docs/traceability.md`
- `docs/plans/2026-06-21-plumbline-update-reliability.md`
- `docs/benchmarks/2026-06-21-plumbline-update-reliability-smoke.md`
- `CLAUDE.md`

---

## 10. Traceability links

PRD: docs/prd/plumbline-update-reliability.prd.md
Product Vision: docs/vision/plumbline-update-reliability.vision.md (user-confirmed 2026-06-21)
Traceability Matrix: docs/traceability.md (slice block: plumbline-update-reliability)
Related REQ IDs: REQ-PUR-01 … REQ-PUR-08
True-Line status: aligned

---

## Open Questions

| ID | Question | Status |
|---|---|---|
| OQ-PUR-01 | symlink-mode auto-refresh vs `--copy` force-refresh default: should `install.sh --update` content-compare and overwrite for BOTH modes, or only re-link symlinks and force-refresh copies? | RESOLVED (user, 2026-06-21) — content-compare + overwrite in BOTH modes: `install.sh --update` content-compares and overwrites every CHANGED target regardless of symlink/copy mode (most reliable "all changed content lands for every user"). Affects PUR-3.2 / REQ-PUR-05. |
| OQ-PUR-02 | auto-check opt-in default: should the session-start update-check be off-by-default (env-gated opt-in) as the plan states, or opt-out? Plan says opt-in/off-by-default; confirm this is the desired default. | RESOLVED (user, 2026-06-21) — auto-check ON by default / opt-out: the session-start `update --check` runs by default (throttled ≤1/day, authenticated per Sprint 2, non-blocking) and only NOTIFIES; disabled via an env opt-out. APPLY stays explicit (a CHECK is not an apply). Affects PUR-4.2 / REQ-PUR-08. |

---

## User confirmation

Confirmed by user: yes
Confirmation date: 2026-06-21
Confirmation note: The user (Ben, 2026-06-21) gave the exact confirmation phrase —
"Ich bestätige, dass Product Canvas und Product Vision meine Absicht korrekt wiedergeben und als
Grundlage für AgileTeam Planning verwendet werden dürfen." — so this Canvas is `user-confirmed`
and may serve as the basis for AgileTeam planning (no agent self-confirmation). Both OPEN QUESTIONs
were RESOLVED (user, 2026-06-21): OQ-PUR-01 → content-compare + overwrite in BOTH modes; OQ-PUR-02
→ auto-check on-by-default / opt-out. Intake remains authored only (docs, no production code; not
yet committed).

Refinement C1 (user/Ben, 2026-06-21): the user clarified that installed identity is
cwd-INDEPENDENT in BOTH install modes, sourced honestly per mode — copy installs from the
`.plumbline-install.json` anchor (natural update path = `plumbline update`); symlink installs from
the symlinked checkout's CURRENT VERSION + git origin (natural update path = `git pull`; forcing
the install-time anchor here would report a stale version after a pull). This refines the earlier
"anchor-preferred / anchor-authoritative" wording in REQ-PUR-02 and the value proposition. It is
the user's OWN refinement of an already-`user-confirmed` intake, not a re-open: status stays
`user-confirmed`; the True-Line invariant "correct INSTALLED identity from any cwd" is unchanged
and now explicitly covers both modes via their honest source.
