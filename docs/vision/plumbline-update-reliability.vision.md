# Product Vision: Plumbline Update Reliability

Status: user-confirmed
Feature-Slug: plumbline-update-reliability
Canvas: docs/canvas/plumbline-update-reliability.canvas.md (user-confirmed 2026-06-21; Vision and Canvas agree on problem, target user, value, success signal, and status)
Source plan: docs/plans/2026-06-21-plumbline-update-reliability.md

> This is the confirmed-customer-value line the plumbline-watcher checks every phase, gate,
> and retrospective against. It is a SEPARATE artifact from the Canvas and PRD — never merged.
> The user confirmed it at the `/agileteam` user-confirmation gate on 2026-06-21 with the exact
> confirmation phrase, so this Vision is `user-confirmed` and AgileTeam planning may proceed.

## Vision Statement (Customer value / North Star)

Every Plumbline user can run ONE natural update path, from anywhere, and reliably get
ALL new content into their `~/.claude` — fast, precise, verified-or-reverted. The delivered
value is the *reliable, complete, honest delivery of updates* — not a version string, not a
green check, not "it ran". An update either lands every changed agent/command/skill/lib/bin
into the user's install and proves it, or it reverts and says so. Nothing in between.

The natural path is per install mode (CR-1, the C1 two-mode model — see Core Value Promise
invariant 2): COPY installs (web-bootstrap / `--copy`) update via `plumbline update`; SYMLINK
installs update via `git pull` on the tracked checkout. `plumbline update` applies the
`install.sh --update` MECHANISM (content-compare + overwrite changed targets + add new — both
symlink and copy targets) to COPY installs, and REFUSES a symlink install with a classified
"update via `git pull`" message rather than silently copy-converting it (which would destroy the
checkout-tracking the C1 decision preserves).

## Target User

- `EXPLICIT`: Every Plumbline operator who installs the framework into `~/.claude` and later
  wants the newest agents, commands, skills, libs, and bin tooling — including `--copy` and
  web-bootstrap installs, which today do NOT auto-refresh the way a symlink install does.
- `ASSUMPTION`: Operators who run `plumbline`/`plumbline update` from arbitrary working
  directories (inside other repos, from `/`, from `/tmp`), not only from a Plumbline checkout.
- `ASSUMPTION`: Maintainers who need the update path testable, honest about its evidence class,
  and safe enough to ship to every user's machine without risking their real `~/.claude`.

## User Problem

`EXPLICIT` (root causes from the code-grounded investigation 2026-06-21):
- **RC1 / G1 — cwd-derived identity.** Both the VERSION and the repo slug are read from the
  current working directory (no install anchor), so `plumbline version` prints a phantom or
  missing version, and `update --check` can target the wrong slug → a 404. Reproduced.
- **RC2 / G2 — unauthenticated release fetch.** The fetch carries no auth header → 60
  requests/hour/IP → intermittent 403/404, so `update --check` fails from rate-limiting.
- **RC3 / G3 — `update` never refreshes `~/.claude`.** `install.sh transfer()` skips existing
  targets without `--force`, and `update_apply` only runs `install.sh --dry-run` against the
  checkout — so a re-install silently skips changed files and the user is left on a STALE
  install. The "update" updates nothing the user can see.
- **G4 — the gaps are invisible to CI.** The tests pin `--root`/`--source` to local fixtures,
  so G1–G3 pass green; the failure is masked, not absent.

The net experience: a user runs the one command they were told to run, it reports success or a
version, and their install is still stale, mis-identified, or rate-limited — with the test suite
agreeing it is fine.

## Desired Change

`EXPLICIT`: After this feature, from ANY cwd (including inside a foreign repo with its own
`VERSION` and `origin`):
- installed `plumbline version` → the INSTALLED version (never cwd's, never "VERSION not found");
- `plumbline update --check` → queries the INSTALLED slug (`DYAI2025/Plumbline`), authenticated
  when a token exists, resilient to rate limits, with 403-rate-limit reported distinctly from
  404-not-found;
- `plumbline update` (on a COPY install) → delivers ALL changed content into `$CLAUDE_HOME` via
  the REAL `install.sh --update` MECHANISM (content-compares + overwrites stale
  agents/commands/skills/libs/bin AND adds new — skills INCLUDED, CR-2), rewrites the install
  anchor, and on a verify-failure REVERTS the whole `$CLAUDE_HOME` to its prior state; on a SYMLINK
  install it is REFUSED with a classified "update via `git pull`" message (the C1 two-mode model —
  the symlink install updates via `git pull` and is never copy-converted);
- reverting ANY of these fixes reddens a falsifying test in `run_all` (the masked gaps become
  visible, not mocked green);
- a throttled, non-blocking, notify-only session-start check (on by default, env opt-out; resolved
  OQ-PUR-02) notifies the user only when they are behind.

## Core Value Promise (the True-Line)

The promise that must not be broken, in five invariants the plumbline-watcher checks against:

1. **The natural update path delivers ALL changed content (two-mode, CR-1 / C1).** No silent
   partial update, no stale skip. The `install.sh --update` MECHANISM content-compares + overwrites
   every changed target and adds new (both symlink and copy targets). The applicability is per mode:
   on a COPY install `plumbline update` applies that mechanism into `$CLAUDE_HOME`; on a SYMLINK
   install the natural path is `git pull`, and `plumbline update` REFUSES the symlink install with a
   classified "update via `git pull`" message rather than copy-converting it (which would freeze the
   install and destroy the checkout-tracking). So: if a file changed upstream and the user runs
   their mode's natural update path, it lands in their install — completely, not partially.
2. **Correct INSTALLED identity from any cwd (both install modes, honestly sourced).** Version and
   slug are cwd-INDEPENDENT in BOTH install modes, never from whatever directory the user happens
   to stand in — sourced per mode: copy installs from the `.plumbline-install.json` anchor; symlink
   installs from the symlinked checkout's current VERSION + git origin (cwd-independent because the
   symlink is a fixed anchor to the checkout, not cwd). (C1 refinement, user/Ben 2026-06-21: not
   "anchor regardless of mode" — forcing the install-time anchor on a symlink install would report
   a stale version after a `git pull`; symlink-tracks-checkout is intended.)
3. **Verify-or-revert.** A failed update NEVER leaves a broken install. The apply snapshots
   `$CLAUDE_HOME`, verifies, and restores the prior state on failure.
4. **SANDBOX-`$CLAUDE_HOME` only in tests.** Every real test/smoke uses
   `export CLAUDE_HOME="$(mktemp -d)"` — never the operator's real `~/.claude`. Snapshot +
   verify + revert is non-negotiable and is itself tested.
5. **Honest evidence.** The live `update --check` and the sandbox-HOME apply are
   `real-boundary-smoke`; the offline mechanics are `integration-fake`. The previously-masked
   gaps (G1–G3) are falsifying-tested — red if the fix is reverted — never mocked green. The
   Reality Ledger class is never raised to launder a real boundary as integration-fake.

## Why Now

`EXPLICIT`: This is the user-facing install tooling for EVERY Plumbline user, and it is broken
in three reproduced ways at once (phantom version, 404 checks, stale installs), with the test
suite masking all three. A defense-in-depth framework whose own update path silently delivers
stale content while reporting success contradicts the repo's central claim — proving work is
*actually* done, not that it merely *looks* done. The gap is shipping today.

## Non-Goals

`EXPLICIT` (from the plan):
- NOT changing the release-please release-cutting flow (`.github/workflows/release-please.yml`).
- NOT adding curated release ZIP assets (GitHub's `tarball_url` is sufficient) unless a sprint
  genuinely needs it.
- NOT auto-APPLYING updates without consent — auto-CHECK + notify is on-by-default / opt-out (env
  to disable; resolved OQ-PUR-02) and notify-only; apply stays explicit and user-initiated (a
  CHECK is not an apply).
- NOT touching the unrelated PRIL `bin/plumbline-*` wrappers.

## Success Signal

`EXPLICIT`: The cross-cutting end state from the plan is reached and proven:
- `SS-PUR-01`: installed `plumbline version` from `/`, `/tmp`, and `/tmp/fakerepo` (own
  `VERSION=9.9.9`, own git origin) all print the INSTALLED version — never `9.9.9`, never an
  error. (REQ-PUR-01/02, closes G1.)
- `SS-PUR-02`: `update --check` from a foreign repo queries `DYAI2025/Plumbline`, sends a token
  when one exists (asserted-present, never printed/logged), still works unauthenticated, and
  classifies 403-rate-limit distinctly from 404-not-found. (REQ-PUR-03, closes G2.)
- `SS-PUR-03`: `plumbline update` into a sandbox COPY-install `$CLAUDE_HOME` refreshes a
  deliberately STALE agent + command + lib (skills INCLUDED, CR-2), adds new files, rewrites the
  anchor, and on an injected verify-failure REVERTS the whole `$CLAUDE_HOME` to the prior state —
  and never writes the real `~/.claude`. (REQ-PUR-04/05/06, closes G3.) The `install.sh --update`
  MECHANISM content-compares + overwrites changed targets for both symlink and copy targets; the
  CLI applies it to copy installs (the sandbox apply runs `install.sh --copy --update --no-hook`).
- `SS-PUR-03b`: `plumbline update` run against a SYMLINK install is REFUSED before any fetch with a
  classified "update via `git pull` in `<checkout>`" message and never copy-converts the install
  (the C1 two-mode model; CR-1). (REQ-PUR-02/REQ-PUR-05.)
- `SS-PUR-04`: reverting ANY Sprint-1/2/3 fix reddens a behaviour/counter falsifier wired into
  `run_all.sh` (not outcome-only). (REQ-PUR-07, closes G4.)
- `SS-PUR-05`: the session-start check notifies on a behind sandbox, is silent when
  current, adds no blocking latency, is notify-only, and is on by default with an env opt-out
  (resolved OQ-PUR-02; APPLY stays explicit). (REQ-PUR-08.)
- `SS-PUR-06`: a gated, opt-in real `update --check` against `DYAI2025/Plumbline` and a real
  sandbox-`$CLAUDE_HOME` `update` vN→vN+1 (refresh + forced-fail revert) run as
  `real-boundary-smoke` before each sprint's acceptance — never against a real HOME, never in CI.

## Risks if Misbuilt (Gegenthese — green-but-untrue shapes for the watcher)

These are the classic "fully green yet zero/negative user value" shapes the watcher must screen
for. Each is a BLOCKER if present, and per the escalation-asymmetry rule only the user may
downgrade one:

- **Bricked / half-updated install.** An update that bricks or half-updates `~/.claude` (writes
  some changed files, skips others, or leaves a partial state) — the stale-skip bug surviving
  under a green suite. The verify-or-revert invariant exists precisely to forbid this.
- **cwd-leaking identity.** A version or `--check` that silently reads cwd's `VERSION`/slug
  instead of the install anchor — green tests that pin `--root` would hide it (this is G4).
- **Mocked-away real boundary.** A "passing" suite that mocks the real fetch or the real
  identity resolution so the actual gap stays invisible — looks-measured-but-isn't.
- **Checkout-only apply.** An apply that patches only the Plumbline checkout (the old
  `--dry-run`-against-the-checkout behaviour) and never touches the user's install — the update
  "succeeds" while the user's `~/.claude` is unchanged.
- **Ledger laundering.** A real boundary crossed (real fetch, real install into a HOME) while
  the Reality Ledger claims `integration-fake` — the ceiling laundered down to clear a floor.
- **Consent bypass.** Auto-apply without explicit user consent — turning the notify-only check
  into an unrequested mutation of the user's machine.

## QA Value Checks (VCHK-*)

What QA must later verify as customer value, not just function:

- `VCHK-01`: From a foreign repo, the INSTALLED `plumbline version` prints the installed version
  and `--check` hits the installed slug — proving identity is value-real, not cwd-real.
- `VCHK-02`: A real sandbox-`$CLAUDE_HOME` update demonstrably refreshes a known-changed file the
  user would otherwise be stale on — proving "ALL changed content" is delivered, not skipped.
- `VCHK-03`: A forced verify-failure leaves the sandbox `$CLAUDE_HOME` byte-identical to its
  pre-update snapshot — proving verify-or-revert protects the user's install.
- `VCHK-04`: No test or smoke ever writes the operator's real `~/.claude` (asserted via the
  sandbox env) — proving the safety floor holds.
- `VCHK-05`: The token is never present in any logged/printed output while still being sent —
  proving auth resilience without leakage.
- `VCHK-06`: The Reality Ledger class matches the boundary actually crossed for every load-bearing
  REQ-PUR-* — proving honest evidence over green-by-mock.

## User Confirmation

Status: user-confirmed
Confirmed by: Ben
Confirmed at: 2026-06-21
Open contradictions: none recorded (Canvas is user-confirmed; Canvas and Vision statuses match)

Confirmation event (real): the user (Ben, 2026-06-21) gave the exact confirmation phrase at the
`/agileteam` user-confirmation gate, jointly confirming the Product Canvas and this Product Vision
as the basis for AgileTeam planning:

```text
Ich bestätige, dass Product Canvas und Product Vision meine Absicht korrekt wiedergeben und als Grundlage für AgileTeam Planning verwendet werden dürfen.
```

Refinement C1 (user/Ben, 2026-06-21): installed identity is cwd-INDEPENDENT in BOTH install modes,
sourced honestly per mode — copy installs from the `.plumbline-install.json` anchor (update path =
`plumbline update`), symlink installs from the symlinked checkout's current VERSION + git origin
(update path = `git pull`). This refines Core-Value-Promise invariant 2 from "anchor regardless of
mode" to "honest per-mode source"; the True-Line invariant "correct INSTALLED identity from any
cwd" is unchanged. The user's own refinement of an already-`user-confirmed` Vision — status stays
`user-confirmed`, no contradiction recorded.
