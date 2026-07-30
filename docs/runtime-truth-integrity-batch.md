# Runtime Truth Integrity batch (PLUM-9 … PLUM-15)

Verification record for the control batch "Plumbline Control Truth Integrity". One
section per ticket. Each section states what was **measured**, not what was intended:
the reproduction attempt (or the proof of non-reproducibility), the root cause, the
focused regression test, the counter-check that the test actually bites, and the
evidence ceiling that remains.

Ground rule for this batch: a ticket whose defect is **not reproducible** on the
canonical tree does not get a speculative code change. It gets a documented
non-reproduction plus, where the existing suite only proves the fix indirectly, a
falsifying test that reddens when the fix is reverted.

## Test environment (three local false-REDs)

`run_all.sh` is green on CI but the ambient dev environment reddens most stages
without any code defect. Every measurement below was taken with:

```bash
CLEAN_PATH="$(printf '%s' "$PATH" | tr ':' '\n' \
  | grep -v 'modern-python' | grep -v "^$HOME/.claude/bin$" | paste -sd: -)"
env -u SSL_CERT_FILE PATH="$CLEAN_PATH" bash config/claude/tests/run_all.sh
```

See `CLAUDE.md` → "Run `run_all.sh` in a clean environment" for why each of the
three is needed.

## PLUM-9 — scope guard fell back to an empty `HEAD...HEAD` diff

**Status: not reproducible on the canonical tree; coverage gap closed.**

### Reproduction attempt

The ticket describes `git merge-base HEAD main` with a fallback to `HEAD`, which
turns an unresolvable baseline into a vacuous `HEAD...HEAD` range. The canonical
hook (`config/claude/hooks/plumbline-enforce.sh`) does not contain that code path:
`resolve_git_base()` tries an explicit stack pin
(`PLUMBLINE_STACK_BASE`, alias `PLUMBLINE_BASE_REF`), then the remote default
(`refs/remotes/origin/HEAD`), then `origin/main`, `origin/master`, `main`, `master`,
and on failure emits a classified block (`PRIL_GIT_BASE_UNRESOLVED`,
`PRIL_GIT_BASE_UNRELATED`, `PRIL_GIT_BASE_CONFLICT`) instead of substituting `HEAD`.
All 18 pre-existing PLUM-9 assertions pass on a pristine `git archive HEAD` copy.

### Counter-check (the defect, reintroduced)

To prove the assertions are falsifiable rather than vacuous, the pilot defect was
reintroduced in a throwaway copy — candidate list narrowed to `main` only, and the
classified block replaced by `base_merge="HEAD"`. Result: 6 of the pre-existing
PLUM-9 assertions turn RED, so the fix is genuinely load-bearing.

### Gap found by the counter-check

Under the reintroduced defect, the three **outcome** assertions stayed green; only
the audit-string assertions (`source=local-master`, `source=origin-main`, …) bit.
A direct probe of the ticket's actual harm — a repo whose only default branch is
`master`, carrying a **committed** foreign file and a clean work tree — showed:

| checkout | audited base | verdict |
|---|---|---|
| defect reintroduced | `source=head-fallback merge-base=HEAD` | **FALSE GREEN**, no block |
| canonical `HEAD` | `source=local-master merge-base=<sha>` | blocked, `PRIL_POLICY_VIOLATION gate=scope exit_code=3` |

So AC-5 ("committed and uncommitted foreign files are detected") held in the
implementation but was only *indirectly* covered by the suite.

### Regression test added

`config/claude/tests/test_pril_enforce_hook.sh` — `PLUM-9 master default: …`
(3 assertions): the violation is provably committed-only (absent from the
working/staged/untracked surface), the hook blocks on the scope gate, and the
audited merge-base is the real `master` SHA rather than `HEAD`.

Measured: green on canonical (109 run, 0 failed), and the outcome assertion turns
RED against the reintroduced defect ("missing 'scope'"). The test therefore fails
if the baseline resolution regresses, which the previous assertions did not.

### Evidence ceiling (PLUM-9)

`integration-real` for the git-baseline surface: real throwaway git repositories
with `main`, `master`, custom remote default, stacked branches with and without a
pin, unrelated and unresolvable pins, committed and uncommitted violations, and the
real PRIL CLIs. Not covered: a genuine network remote (all remote refs are created
locally with `update-ref`/`symbolic-ref`), and no claim is made about baselines in
repositories using worktrees or shallow clones.

## PLUM-10 — machine-critical Allowed Scope hung on fragile markdown

**Status: reproduced (4 of 4 claimed failures); fixed.**

### Reproduction (measured 2026-07-30, pre-fix `plumbline_scope.py`)

| # | input | observed | harm |
|---|---|---|---|
| A | `- ``/src/feature/**``` | exit 2 "missing Allowed change scope" | scope silently discarded, then misdiagnosed as *never declared* |
| B | paths only inside a fenced code block | exit 2, same message | same |
| C | `- src/feature/**` + a formatter-wrapped `* and every generated artifact under pkg/openapi/**` | prose became an allowed pattern; the intended path was blocked (exit 3) **and** the prose-shaped path `and every generated artifact under pkg/openapi/v1.json` PASSED (exit 0) | false RED and false GREEN from one line |
| D | manifest restricted to `src/api/**`, canvas allowed `src/feature/**` | `src/feature/app.py` **passed** | the fragile markdown was the effective security config; the machine-readable manifest was dead weight |

### Root cause

One document served two incompatible roles: a free-form human artifact *and* a
security configuration. The manifest existed but sat **last** in the precedence
chain, and every unusable line was dropped without a word — so the guard could not
distinguish "no scope declared" from "scope declared, parsed to nothing".

### Implementation

`config/claude/lib/plumbline_scope.py`:

- `docs/scope/<feature>.scope.json` is canonical, checked **first**, and final —
  a broken manifest does **not** fall back to the canvas, otherwise corrupting the
  canonical file would re-enable the fragile one.
- Schema validation (`schema`, `feature`, `allowed_change_scope`, `notes`,
  `provenance`; unknown keys refused). Every rejected entry names its **index** and
  cause: non-string, empty, leading `/`, `..`, `\`, embedded whitespace, control
  character, or no concrete path segment.
- An empty allow-list is *missing*, never a wildcard.
- Legacy canvas keeps working, but every ignored line is reported with its **line
  number and cause** (fenced block, wrapped continuation, prose, absolute path…).
  A section that yields no usable pattern is now `malformed` naming each line,
  instead of the misleading "missing".
- Prose-shaped candidates are **dropped** (narrowing, fail-safe) — never accepted,
  which closes defect C's false green.
- Every result names its source (`source=manifest=…` / `source=canvas=…`).

Documentation: `docs/scope-manifest.md` (shape, rules, precedence, migration).

### Regression test + counter-check

`config/claude/tests/test_scope_manifest.sh` — 42 assertions, registered in
`run_all.sh` as "canonical scope manifest tests (PLUM-10)". Counter-check is
recorded by construction: against the **pre-fix** module the same file scored
**28 of 37 failed** (including `legacy prose line: prose-shaped path is NOT
authorized — expected '3', got '0'`, i.e. the false green); after the fix 42/42
pass. Negative controls included: a broken manifest must not fall back to a
permissive canvas, and legitimate globs / non-ASCII paths must still pass.

Backward compatibility is proven by the pre-existing fixtures: `scope-json-source`
(a manifest with **no** `schema` key) and all canvas fixtures still pass unchanged.

### Evidence ceiling (PLUM-10)

`integration-real` for the parser/loader boundary: the real CLI over real files in
real throwaway git repositories, exercising leading slashes, code blocks, wrapped
lines, prose, special characters and schema violations. **Not** covered: an actual
formatter (Prettier) run over a canvas — the wrapped output is reproduced by hand,
not generated by the tool; and no claim is made about canvases in other encodings
beyond the UTF-8/non-UTF-8 split already handled.

## PLUM-12 — confirmed scope drifted between conversation, plan, canvas and hook

**Status: reproduced (absence of any validator, verified by inspection + demonstration); fixed.**

### Reproduction

The defect is a *missing* gate, so it was verified two ways. By inspection: nothing
under `config/claude/{lib,bin,hooks}` parsed an implementation plan, and nothing
compared planned files against the allowed scope (`grep` for plan parsing and for
`provenance`/`decided_by` returned no production hit). By demonstration: the
pilot's own list — `.gitignore`, `CLAUDE.md`, `scripts/read-through-harness.sh`,
`packages/contracts/src/openapi/**` — is now the `drift` fixture in
`test_plan_scope_drift.sh`; before the fix there was no command that could reject
it, so the contradiction could only surface when the fail-closed Stop hook blocked
mid-build, after the work was already done.

### Root cause

Scope was maintained redundantly in the conversation, the plan, the canvas and the
runtime gate, with **no atomic transfer** of a confirmed decision into canonical
executable state — and no gate that compared the copies before coding.

### Implementation

- `config/claude/lib/plumbline_scope.py` — the manifest model gains
  `governance_paths` (AC-5: product and governance paths modelled separately) and
  `provenance`; `load_scope_model()` exposes the class-aware view. A legacy source
  cannot express classes, so it reports everything as `product` **and says so**
  rather than implying a distinction it cannot make.
- `config/claude/lib/plumbline_plan.py` + `config/claude/bin/plumbline-plan-check` —
  the pre-coding gate: plan-vs-scope (exit 3), canvas-vs-manifest contradiction
  (exit 3), and opt-in provenance completeness (exit 4). Touched files come from a
  declared `plumbline-touches` block (exact) or inferred from prose with
  `mode=heuristic` announced.
- Wiring (the repo's own "unwired means not satisfiable" rule):
  `config/claude/commands/agileteam.md` Phase 1 now requires the `plumbline-touches`
  block and runs `plumbline-plan-check` as a hard gate **before** Phase 2 coding;
  Phase 0.6 documents the manifest as canonical.
- `run_all.sh` registers the new suite and adds the new wrapper to the shellcheck
  list (an unregistered test or unlinted script is invisible to CI).

### Regression test + counter-check

`config/claude/tests/test_plan_scope_drift.sh` — 38 assertions. Against the
pre-implementation tree: **34 of 38 failed** (exit 127, no such command); after:
38/38 green. Negative controls, so the gate is not a rubber stamp: an authorized
path is not reported as drift; a canvas documenting a subset passes; provenance is
opt-in and a default run still passes; heuristic extraction ignores shell commands,
code identifiers and URLs; a declared-but-empty touches block is `malformed`, never
"all clear".

### Evidence ceiling (PLUM-12)

`integration-real` for the plan/canvas/manifest comparison: the real CLI over real
files. **Not** covered — and deliberately named rather than implied:

- the gate proves *the plan* agrees with the manifest; it cannot prove a human
  actually confirmed a `provenance` record (the record is self-reported, same trust
  model as the confirmed canvas — see the enforce hook's trust boundary);
- `mode=heuristic` is a heuristic: it can flag a read-only mention as unauthorized.
  The remedy is a declared block, not a weaker gate;
- the wiring into Phase 1 is documentation-level (the orchestrator is a prompt);
  the executable proof is the CLI's exit code, not the agent's compliance.

## PLUM-11 — generated agent runtime state contaminated the repo and its gates

**Status: reproduced LIVE in this repository; fixed.**

### Reproduction (measured 2026-07-30, in this working copy)

`git status` reported `?? .claude-flow/` — 604K of `neural/stats.json`,
`neural/patterns.json`, `policy/state.json` — **untracked and not ignored**
(`git check-ignore` said NOT IGNORED). That is not harmless: the enforce hook builds
its change surface from `git ls-files --others --exclude-standard`, and the
2026-07-08 C4 exemption only covers paths that are gitignored **AND** untracked. An
unignored dropping therefore enters the surface and blocks **every** scope check
without a single line of feature work. The pilot hit the worse variant: 11 such
files (~7.1 MB) actually tracked, changing on every session.

The 2026-07-08 commit had ignored `.plumbline/`, `.claude/homunculus/` and
`.devin/` — but not `.claude-flow/`, `.swarm/` or `.hive-mind/`. A per-incident
ignore list is exactly the pattern that keeps regressing.

### Root cause

No binding policy (and no executable check) separating three different kinds of
content: **volatile runtime state**, **curated insight** and **versionable
evidence**. Ignore rules were added reactively, one incident at a time.

### Implementation

- `config/claude/lib/plumbline_hygiene.py` + `config/claude/bin/plumbline-runtime-hygiene`
  classify three distinct violations — `tracked` (in the index), `unignored`
  (present, neither tracked nor ignored → blocks scope gates) and
  `curated-location` (volatile state under `docs/`/`metrics/`, which destroys the
  curated-vs-ephemeral distinction) — and report each with its own fix.
- `--fix-ignore` is **prophylactic and additive**: it appends a marked block for
  every known pattern (rules must exist *before* the first session writes), never
  rewrites a foreign rule, never deletes a file, and **never untracks anything** —
  an already-tracked file keeps failing the check until the operator runs the printed
  `git rm -r --cached` (which keeps the working copy). Untracking is a history
  decision, so the tool refuses to make it silently.
- `config/claude/install.sh` gains `--ignore-runtime-state` (opt-in write) and
  otherwise *reports* the findings plus the hint. Writing into someone else's
  repository is never implicit; `--dry-run` and `--help` write nothing (verified).
- This repo's `.gitignore` now ignores `.claude-flow/`, `.swarm/`, `.hive-mind/` —
  applied by running the new tool on this checkout, which also proved the additive
  behaviour: the pre-existing rules and comments survived and
  `.claude/homunculus/` was recognised as already-ignored rather than duplicated.

### Regression test + counter-check

`config/claude/tests/test_runtime_hygiene.sh` — 43 assertions, registered in
`run_all.sh`; the new wrapper is added to the shellcheck list. Coverage includes the
ACs that are easy to fake: repeated session activity (three runs writing and
rewriting state) must leave `git status --porcelain` **empty** (AC-5); the scope
guard must stay green with droppings present (AC-6); `--fix-ignore` must be
idempotent and must not resolve a *tracked* finding (AC-3/AC-4); a repo with no
`.gitignore` gets one created; and two assertions pin **this** repository so the
live finding cannot silently return.

Negative controls: a clean repo produces no findings; an unknown tool's directory
(`.myagent/`) is **not** invented as a finding unless passed via `--pattern`;
a non-git directory and a missing path are classified `missing` (exit 2), not
"clean".

A defect found by the suite itself, worth recording: `install.sh`'s `usage()` uses an
**unquoted** heredoc, so the backticks in a first draft of the new help text would
have *executed* `git rm -r --cached` when a user ran `--help`. Shellcheck's SC2006
caught it as "style"; in an unquoted heredoc it is a destructive command-substitution
bug. Fixed before commit, and `--help` is now verified to leave the index untouched.

### Evidence ceiling (PLUM-11)

`integration-real` for the tracked/ignored/curated classification and the additive
fix: real git repositories, real index state, real `.gitignore` content, the real
CLI. **Not** covered, and deliberately not claimed:

- AC-1's stronger reading — "volatile state lives *outside* the product repository
  by default" — is **not** achieved. Plumbline cannot relocate a third-party tool's
  write path; what is enforced is the weaker, verifiable half ("reliably ignored").
  Making `.claude-flow/` write elsewhere is a claude-flow configuration question.
- the session simulation writes the droppings the way the tools do (same paths,
  changing content); it does not run claude-flow or homunculus themselves.
- the secret-scan half of AC-6 is covered only insofar as the state stays out of the
  index; no scanner is executed here.

## PLUM-13 — green tests were not bound to the changed defect path

**Status: reproduced (2 false greens, one worse than the ticket claims); fixed.**

### Reproduction (measured 2026-07-30, pre-fix gate)

Both of these exited **0** — credited as satisfied evidence:

| ledger record | reality | verdict |
|---|---|---|
| `real-boundary-smoke` for a requirement about dataset `W32-default-seed` on `GET /api/v1/tree/read-through` | linked test drove `W40-harness-seed` fixtures on a different route | FALSE GREEN |
| `production-verified`, `evidence_ref: tests/does_not_exist_at_all.sh` | the referenced file does not exist | FALSE GREEN |

The second is worse than the ticket describes: the gate credited the **highest**
evidence class to a reference that resolved to nothing at all.

Structural confirmation: across this repo's 9 ledgers, all **84** records use exactly
six fields — `feature`, `requirement_id`, `evidence_class`, `evidence_ref`,
`verified_by`, `note`. There was no field in which a dataset, route, boundary or
precondition could even be expressed, so no gate could have checked one.

### Root cause

Plumbline classified the *strength* of a proof but never modelled its *subject*.
`evidence_ref` was free text, ranked by the claimed class alone.

### Implementation

`config/claude/lib/plumbline_reality.py`:

- `docs/evidence/<feature>.targets.json` (schema 1) declares, per critical REQ:
  `dataset`, `boundary`, `expected_result`, optional `preconditions`
  (`present`/`absent`), an optional per-target `min_evidence` floor that **outranks** a
  lower CLI floor, and optional `proof_tokens`.
- The matching ledger record must repeat the binding, and the artifact its
  `evidence_ref` names must exist **and contain the proof token** — the step that turns
  a self-declared binding into a checked one.
- Stable classifications: `MISSING_BOUNDARY` (exit 2) for a target with no record or a
  record with no binding; `EVIDENCE_MISMATCH` (exit 3) for evidence that proves the
  wrong thing (contradicting field, unresolvable `evidence_ref`, absent proof token,
  differing preconditions, unmet target floor, vacuous absence).
- **Vacuous absence tests** (AC-3): an `absent`-state target must name a resolvable
  present-state `control_ref`, otherwise the absence is unfalsifiable.
- Opt-in per feature: no targets file ⇒ unchanged behaviour, so all 84 existing
  records keep passing. A **present but broken** targets file is `malformed` (exit 4)
  and never degrades to "no targets declared" — degrading would restore the false green.

Wiring: `config/claude/commands/agileteam.md` documents the target contract inside the
Phase-3 PRIL Reality Evidence gate, where the check already runs.
Docs: `docs/evidence-targets.md`.

### Regression test + counter-check

`config/claude/tests/test_evidence_target.sh` — 41 assertions, registered in
`run_all.sh`. Pre-implementation: **35 of 41 failed**; after: 41/41.

The discriminating controls matter more than the count here:

- the **same repository** contains both tests; the correctly-bound record passes
  (exit 0) while the W40-bound record fails (exit 3), so the gate distinguishes them
  rather than rejecting everything;
- a record whose binding *claims* the right target while the referenced test drives
  W40 is caught by the proof token — this is the pilot's precise mechanism;
- removing a proof token from an otherwise-passing test flips it to exit 3, so the
  check is falsifiable;
- a feature with no targets file still passes, and this repo's own
  `openrouter-gui` ledger is asserted to keep passing.

### Evidence ceiling (PLUM-13)

`integration-real` for the target/record/artifact binding: real files, real ledgers,
the real CLI, both the pilot's mismatch and its correctly-bound twin.

**Not** covered, and deliberately not claimed:

- the proof-token check shows the referenced artifact *mentions* the dataset/route; it
  does **not** execute the test or observe which fixture the run loaded. An author can
  still satisfy it by adding the token to an unrelated test. What it removes is the
  *accidental* mismatch (the pilot's actual failure) and every unresolvable reference.
  Runtime instrumentation — a test that emits its dataset identity into a machine-read
  result — would be the next class up, and is not built here;
- adoption is opt-in per feature, so an undeclared critical AC is still unbound. The
  gate cannot know which criteria are critical; that judgement stays human.

## PLUM-14 — a documented draft / no-merge state was not enforced remotely

**Status: reproduced (absence of any remote view, verified by inspection); fixed.**

### Reproduction

Again a *missing* capability, so verified by inspection and then by demonstration.
Nothing under `config/claude/{lib,bin,hooks}` read any remote or PR state: the run
ledger records gates and artifact hashes — so a human gate whose artifact changed is
caught — but a PR merged, force-pushed or re-pointed **under an active run** left no
trace at all. The pilot: PR #26 was a draft, explicitly not cleared for merge or
review, and was merged through GitHub anyway; Plumbline noticed only afterwards, by
hand.

The 2026-07-08 C3 rule already added a *resume-time* ground-truth cross-check. That is
a different moment: it reconciles a stale ledger when a run restarts, and cannot notice
a merge that lands mid-run.

### Root cause

Plumbline controlled local agent and hook paths and had no remote-state watcher and no
technical merge-policy integration. A stop gate that exists only in prose has no effect
on a remote merge button.

### Implementation

`config/claude/lib/plumbline_remote.py` + `config/claude/bin/plumbline-remote-watch`:

- `snapshot` records what the run expects: PR number, head/base refs and SHAs, the
  draft flag, the PR state — and whether the head was **already** contained in the base.
- `verify` classifies every change as `REMOTE_STATE_CHANGED: kind=…` for `merged`,
  `force-push`, `base-advanced`, `base-changed`, `draft-changed`, `pr-state-changed`,
  `head-gone`, `base-gone`, and exits **3**.
- **Merge and force-push are read from git containment**, not from forge metadata, so
  they are caught even when the PR still reports OPEN (asserted).
- The audit names the account and mechanism **as reported by the remote** and states
  plainly that it does not infer whether a person or a program acted (AC-5). The words
  "human" and "automation" are asserted absent from the output.
- `publish-status --state pending|success|failure` publishes the run's merge gate as a
  forge check (AC-4); `--dry-run` prints the exact request and crosses no boundary.

Boundary discipline, per the repo's injectable-seam invariant: the forge half has a
test seam (`--pr-state-file`) **and** a paired real entrypoint (`gh pr view --json`)
gated OFF by default behind `PLUMBLINE_REMOTE_LIVE=1`. With neither, `verify`
**refuses** (exit 2) instead of checking only the git half and reporting success. A
`gh` failure is classified, never a fallback to "unchanged".

Wiring: `config/claude/commands/agileteam.md` documents snapshot/verify beside the C3
delivery-gate rules, where the resume-time cross-check already lives.

### A design defect the tests caught

The first implementation treated "the head is contained in the base" as the merge
signal. After a merge is reviewed and re-snapshotted the head *is* legitimately
contained in the base, so `verify` could never clear — the run would block forever
(`after explicit re-evaluation verify passes: expected '0', got '3'`). Merge detection
is now a **transition** check against `head_in_base` recorded at snapshot time.

That fix introduces its own risk — a blind spot for the *next* event — so the suite
carries falsifiers for exactly that: after a reviewed merge and a fresh snapshot, a
further base advance and a subsequent force-push both still block.

### Regression test + counter-check

`config/claude/tests/test_remote_state_watch.sh` — 60 assertions, registered in
`run_all.sh`; the new wrapper added to the shellcheck list. All four AC-6 events are
exercised against **real** git remotes (a bare repo plus a second clone that merges,
force-pushes and advances the base). Pre-implementation: 49 of 55 failed (exit 127).

The load-bearing controls:

- a **counter-based falsifier** for the live path: with `PLUMBLINE_REMOTE_LIVE=1` and a
  counting `gh` stub, the forge CLI must actually be invoked exactly once and the
  invocation must request `isDraft` — an outcome assertion alone would still pass if
  the wiring were reverted to the seam;
- the gate is proven **OFF by default** (no seam, no gate ⇒ exit 2, and the output must
  not claim verification);
- an unchanged remote must **not** be reported as changed;
- `verify` without a snapshot fails closed rather than passing by absence.

### Evidence ceiling (PLUM-14)

`integration-real` for the git-observable half — merge, force-push, base advance and
base re-point are measured against real git remotes. The forge half is
`integration-real` over an injected seam plus a **wiring-proven** (counter-falsified)
real entrypoint; the ticket's `real-boundary-smoke` target is **not** reached, and this
is not claimed: no test in this batch talks to api.github.com. Concretely not covered:

- a live `gh pr view` against a real GitHub PR, and a live `publish-status` write;
- AC-4's *enforcement* half — publishing a check does not make it **required**; branch
  protection ("require the `plumbline/no-merge-gate` status") is a repository setting
  the watcher cannot set for you. Without it, the published status is advisory;
- the snapshot lives in `docs/context/`, so it inherits the same trust boundary as the
  active-feature marker: an actor who can rewrite the snapshot can hide a transition.
