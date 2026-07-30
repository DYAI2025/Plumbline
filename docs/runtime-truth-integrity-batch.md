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
