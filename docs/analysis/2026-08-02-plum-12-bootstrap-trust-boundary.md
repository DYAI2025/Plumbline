# PLUM-12 bootstrap trust boundary — reproduced, not fixed

Baseline under analysis: `agent/fix-plum-12-scope-drift` @ `42320c320e0827d02d777866aab3dcbf7dab91b0`
Probe: `config/claude/tests/research/probe_bootstrap_trust_boundary.sh` (deliberately **not** in `run_all.sh`)
Probe result on that baseline: `PROBE_RESULT=WEAKNESS_CONFIRMED`

**This document reports a reproduced weakness. It is not a fix, it is not a merge
recommendation, and it makes no claim about full machine compromise.** A green
probe run means the bypass is still open, not that the tree is healthy.

## 1. The problem

PLUM-12 adds a PreToolUse gate so a write the active plan does not declare is
refused *before* it happens. The gate is only worth its name if the thing being
governed cannot decide the outcome. On this baseline it can.

`pretool-scope-gate.sh` selects its independent authority — the checker it will
trust — at line 243. Everything the hook does before that is done with programs
resolved from `PATH`, inside the very repository under governance:

| line | program | branch it feeds |
|---|---|---|
| 10 | `cat` | `:11 [ -n "$PAYLOAD" ] \|\| exit 0` |
| 17 | `jq` | `:53 case "$tool_name" in *) exit 0` |
| 25–41 | `sed`, `head` | same, on the jq-less path |
| 59 | `tr` | `:60 [ -n "$feature" ] \|\| exit 0` |
| 77 | `python3` | Bash-arm updater classification |
| 202 | `python3` | `:224 [ "$manifest_kind" = "legacy" ] && exit 0` |
| 253, 270 | `python3` | the checker-provenance test itself |

Every one of those is a fail-**open** branch: a program that prints nothing and
exits 0 disables the gate. The repository therefore only has to ship an
executable named `jq`, `cat`, `sed`, `tr` or `python3` somewhere that lands
earlier on `PATH` — a `.venv/bin`, a `tools/bin`, an activated virtualenv.

The Stop hook has the same shape with a sharper edge, and is treated separately
below.

## 2. Reproduced cases

Foreign throwaway repository, armed (`docs/context/.active-feature`), canonical
`schema_version: 1` manifest allowing `src/demo/**`, plan declaring exactly
`Create: src/demo/app.py`. The probed action is a `Write` to
`src/demo/unplanned.py` — inside the manifest, absent from the plan.

Each negative case reports three **independent** observations, because any one of
them alone can be satisfied for the wrong reason:

- `repo_program_executed` — did the repository-owned program actually run?
- `decision` — allow or deny
- `target` — unchanged or modified. The harness performs the write when the gate
  does not deny, so the file's bytes are the falsifier. A text-only assertion
  would also be satisfied by a Stop-time block *after* the write landed, which is
  precisely the difference PLUM-12 exists to make.

| case | program | executed | decision | target | verdict |
|---|---|---|---|---|---|
| N1 | `python3` in `.venv/bin` | yes | allow | modified | `FULL_BYPASS` |
| N4 | `python3` in `tools/bin` | yes | allow | modified | `FULL_BYPASS` |
| N2 | external entry → symlink target inside the repo | yes | allow | modified | `FULL_BYPASS` |
| N7 | `jq` | yes | allow | modified | `FULL_BYPASS` |
| N8 | `cat` | yes | allow | modified | `FULL_BYPASS` |
| N8b | `sed` (jq-free PATH) | yes | allow | modified | `FULL_BYPASS` |
| N10 | `tr` | yes | allow | modified | `FULL_BYPASS` |
| N3 | repo-internal entry, delegating to an external interpreter | yes | deny | unchanged | `EXECUTION_ONLY` |
| N5 | `PLUMBLINE_PYTHON` inside the repo | yes | deny | unchanged | `EXECUTION_ONLY` |
| N9 | `uv` (ranked above `python3` by `plumbline_python.sh`) | yes | deny | unchanged | `EXECUTION_ONLY` |
| S1 | `python3`, Stop hook | yes | block | n/a | `EXECUTION_ONLY` |
| S2 | `git`, Stop hook | yes | block | n/a | `EXECUTION_ONLY` |
| N6 | no external `python3`/`uv`/`jq`/`sed` reachable | **no** | allow | modified | `FAIL_OPEN_NO_REPO_PROGRAM` |

Totals: 13 negative — 7 `FULL_BYPASS`, 5 `EXECUTION_ONLY`, 1
`FAIL_OPEN_NO_REPO_PROGRAM`, 0 unexplained. 4 positive controls, all `CONTROL_OK`.

### Reading the three verdicts

`FULL_BYPASS` — the repository's program ran, the gate allowed, and the unplanned
write landed. The gate was decorative.

`EXECUTION_ONLY` — the repository's program ran, but the outcome still failed
closed. This is **not** a mitigation: it held because the shim happened to break
something downstream, not because provenance was checked. N3, N5, N9 and S2 would
all have passed a decision-only assertion while the repository's program had
already executed. That is why the execution marker is a separate observation.

`FAIL_OPEN_NO_REPO_PROGRAM` (N6) — a finding the probe surfaced by accident and
is reported rather than filed under "not reproduced". With no external parser
reachable at all, the hook reaches the same fail-open branch and allows the
unplanned write **without the repository supplying anything**. Absence of a
bootstrap tool is as good as a hostile one. Any fix that only checks provenance
leaves this open; the branches themselves have to stop being fail-open.

### Positive controls (a fix must preserve all four)

| case | expectation | result |
|---|---|---|
| P1 external interpreter, unplanned write | deny | `CONTROL_OK` |
| P2 planned `Create:`/`Modify:` target | allow | `CONTROL_OK` |
| P3 unarmed session (no active-feature marker) | allow, silent | `CONTROL_OK` |
| P4 repository-owned permissive checker planted | deny | `CONTROL_OK` |

P4 matters: PR #102's **checker** entry/target containment (`:244-291`) already
works. The gap is that it is reached too late and is itself evaluated by
`python3` from `PATH`.

### Test isolation the probe had to build first

Three measurement errors were found and closed while building this; each had
produced results that read like passes.

1. **Shared fixture.** One repository reused across cases leaked each case's
   commit into the next through the `merge-base(HEAD,main)..HEAD` surface, so
   every case blocked identically — including the positive control. Each case now
   builds its own repository.
2. **A `python3` on `PATH` that refuses to run** (a wrapper insisting on
   `uv run python3`) silently broke every fixture; the wreckage read as "no
   weakness". The probe now rejects any candidate that cannot execute
   `print("PYOK")`, and any wrapper that re-execs another resolver.
3. **`CLAUDE_HOME` leakage.** Without pinning it, the fixtures resolved the
   machine's *installed* `plumbline-scope-check` from an unrelated checkout and
   measured that install. It is now an isolated empty directory.

A fourth was caught in N6 itself: pinning `PATH` to the repository directory alone
meant `env` could not find `bash`, the hook never started, and `rc=127` was being
recorded as "not reproduced". N6 now keeps a shell and coreutils external.

## 3. Why an interpreter-only resolver is not enough

The first fix considered was a trusted-interpreter resolver: reject any
`PLUMBLINE_PYTHON` / `uv` / `python3` whose entry path or resolved target lies
inside the governed repository, keep searching, fail closed when no independent
candidate remains.

N7, N8, N8b and N10 refute that as a complete answer. `jq`, `cat`, `sed` and `tr`
run *before* any interpreter is involved and each one alone produces a full
bypass. N6 refutes it a second way: the fail-open branches trigger on tool
*absence* too. A resolver that only vets interpreters would leave five of the
seven full bypasses untouched.

The invariant that actually covers the class:

> Before independently installed authority is selected, the registered hook uses
> only bash builtins. No PATH-resolved parser, interpreter, git or helper program
> is executed.

## 4. Scope separation

**In PLUM-12** — the PreToolUse bootstrap surface: N1–N10. This is the gate
PLUM-12 is building; a gate the governed repository can switch off is not a gate.

**Not in PLUM-12 — separate architecture finding (S2).** In
`plumbline-enforce.sh`, `git` is not a helper, it is the ground truth: the
changed-file surface (`:533-558`) and `file_matches_head` (`:207-212`) — the
checker-integrity test itself — are git invocations. A repository-owned `git`
therefore decides both what changed and whether the checker may be trusted. The
probe records S2 as `EXECUTION_ONLY`: the Stop hook still blocked, but only
because the shim broke something downstream. This is the Stop-hook trust root
shipped in PR #103, not PLUM-12's pre-write boundary, and it needs its own ticket
and its own design. It is documented here so it is not lost, and deliberately not
patched here.

S1 (`python3` in the Stop path) sits between the two: a shared runtime helper
would cover it as a side effect.

## 5. Architecture options

### A. Builtin bootstrap plus an independently installed dispatcher

The registered hook becomes a thin, independently installed copy that reads stdin
with bash builtins only, locates its own directory via `BASH_SOURCE` +
`cd`/`pwd -P`, sources one runtime helper installed beside it, and only then
hands over to an independently installed Python dispatcher that does all
parsing, classification and checking. One JSON parser, not three.

- Closes N1–N10 and S1 by construction: nothing from the repository runs before
  authority exists.
- Closes N6 only if the fail-open branches also become fail-closed once armed.
- Cost: enforcement authority must be installed as an independent **copy**, not a
  symlink. Consequence worth stating plainly — Plumbline can then no longer
  govern its own development checkout from the checkout itself; a developer
  working on Plumbline needs an installed external copy, and this repository's own
  CI fixtures change accordingly.
- Residual: the bootstrap still trusts `bash` itself and the kernel's `PATH`
  resolution for the dispatcher launch.

### B. A self-contained compiled runner binary

Ship enforcement as a single static binary with no interpreter or parser
dependency.

- Removes the entire bootstrap surface, including N6.
- Cost: a build/release toolchain, per-platform artifacts and signing this
  project does not have today; it also ends the "read the hook, it is shell"
  auditability that the current design is built on.

### C. External governance service or OS sandbox

Move the decision out of the governed process entirely — a local daemon, or
running the agent under a sandbox that denies writes the daemon has not approved.

- Strongest boundary: the repository cannot influence a process it does not own.
- Cost: an always-on component, platform-specific sandboxing, and a much larger
  failure surface when the service is down. Disproportionate for the current
  slice.

## 6. Recommendation

**Option A as the smallest next slice**, sequenced:

1. An independently installed bootstrap that uses builtins only, plus a runtime
   helper beside it that selects an independent interpreter under the entry- and
   target-containment rule.
2. Collapse the three parsers (`jq`, `sed`, Python) into the one Python
   dispatcher.
3. Turn the fail-open branches fail-closed **while armed**, which is the only
   thing that answers N6.
4. Counter-mutations, separately: remove entry containment; remove target
   containment; remove the `uv` check; move the bootstrap parser back ahead of
   authority selection; replace the runtime helper with a symlink into the
   repository. Each must be proven applied before its result is read.

Option B stays on the table if a later slice needs to close the residual in A.
Option C is out of proportion to the current product.

## 7. Risks and evidence ceiling

- **Evidence class: `real-boundary-smoke`.** The probe drives the real hook as a
  separate process over its real stdin/stdout contract, against real throwaway
  git repositories. It has never been run against a real Claude Code session, and
  the harness — not the harness under test — performs the write that proves the
  bypass. That is a faithful stand-in for the dispatch, not the dispatch itself.
- **Single machine, single OS.** All runs are macOS with one external interpreter.
  Linux behaviour is expected to match but is unmeasured here.
- **The `EXECUTION_ONLY` cases are not quantified as exploitable.** They prove the
  repository's program ran before authority; they do not demonstrate an end-to-end
  bypass, and it is not claimed that one exists for them.
- **No claim about full machine compromise.** An attacker who already controls the
  environment wholesale is out of scope. The threat modelled here is narrower and
  more realistic: content inside a repository an agent is working on.
- **Option A's cost is real and not yet paid.** The copy-only install requirement
  changes developer setup and this repository's own governance story; it is a
  decision, not an implementation detail.

## 8. What this document does not claim

- It does **not** contain a fix. No product behaviour changed in the commits that
  carry it.
- It does **not** make PR #102 merge-ready. PR #102 stays blocked pending the
  architecture decision, green CI on an old head notwithstanding.
- It does **not** close PLUM-12.
- It does **not** solve S2.
