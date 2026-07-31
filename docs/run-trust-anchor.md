# The immutable run-trust anchor

A gate is only as trustworthy as its frame of reference. Two earlier attempts bound
trust to something the judged party still controlled, and both were defeated:

| attempt | how it was defeated |
|---|---|
| checker must be **tracked and byte-identical to `HEAD`** | modify the checker, **commit it**, and it is tracked and identical to `HEAD` — so the guard trusts it. A reference the run can move is not an anchor. |
| scope baseline in **`.plumbline/scope-authority/`**, created by the gate on first use | the file lives inside the repository the run can write, and the gate cheerfully re-creates it. The first gate run *was* the arming moment, so widening before it was adopted as the baseline rather than detected. |

The anchor fixes the frame of reference instead of patching the symptoms.

## What it is

A JSON record written **outside** the governed repository, under the Plumbline state
directory:

```
${PLUMBLINE_STATE_DIR:-${XDG_STATE_HOME:-~/.local/state}/plumbline}/run-trust/<repo-id>/<feature>.json
```

`<repo-id>` is a digest of the canonical repository path, so two checkouts of the same
project never share an anchor.

It binds:

| field | why |
|---|---|
| `repo_path`, `repo_id` | an anchor cannot be moved to a different repository |
| `feature` | an anchor cannot be replayed onto another feature |
| `start_branch`, `start_commit` | where the run began |
| `manifest_path`, `manifest_digest` | the confirmed scope, frozen |
| `checkers` | every in-repo Plumbline runtime file and its digest at arming |
| `armed_at`, `armed_by` | when, and by which installation |

## The rules

1. **Written by an externally installed Plumbline**, before implementation writes begin.
   A candidate checkout that tries to arm itself is refused with
   `TRUST_ANCHOR_SELF_HOSTED` — a checkout cannot declare itself the trusted runtime.
2. **Bound once.** Re-arming an armed run is refused with `TRUST_ANCHOR_ALREADY_ARMED`.
3. **Gates only read it.** No gate creates, repairs or updates an anchor. Missing,
   altered or unreadable is a classified block, never a silent pass and never an auto-arm.
4. **The anchor reader must itself be external.** The hook ignores an in-repo
   `plumbline-run-trust` and continues its search; if only the in-repo copy exists the
   run blocks with `TRUST_ANCHOR_MISSING` rather than falling back to the candidate.

## Commands

```bash
plumbline-run-trust arm    --repo . --feature <slug>   # before implementation writes
plumbline-run-trust verify --repo . --feature <slug>   # what the gates do
plumbline-run-trust show   --repo . --feature <slug>
plumbline-run-trust path   --repo . --feature <slug>
plumbline-run-trust disarm --repo . --feature <slug>   # end the run
```

Changing a confirmed scope mid-run is not a file edit. It is: **disarm → have the new
scope confirmed → re-arm.** Provenance recorded inside the manifest cannot authorize its
own change, because whoever can edit the scope can edit its audit trail in the same write.

## Classified outcomes

| token | meaning |
|---|---|
| `TRUST_ANCHOR_MISSING` | no anchor, or no external reader — the run was never armed |
| `TRUST_ANCHOR_SELF_HOSTED` | a candidate checkout tried to arm itself |
| `TRUST_ANCHOR_ALREADY_ARMED` | re-arming refused; disarm explicitly first |
| `RUN_TRUST_BASELINE_MISSING` | the bound anchor is gone |
| `RUN_TRUST_BASELINE_CHANGED` | the manifest differs from the baseline bound at arming |
| `RUN_TRUST_BASELINE_UNREADABLE` | the anchor cannot be parsed; it is left as found |
| `RUN_TRUST_CHECKER_CHANGED` | a runtime file differs from the set bound at arming |

## Plumbline governing itself

`plumbline-run-trust` is in the **enforced** reachability class: the Stop hook blocks on
it. That makes Plumbline's own development a governed case, and the rule is deliberately
strict:

- an already-installed **external** Plumbline verifies the candidate checkout;
- the candidate does **not** become the trust anchor by committing during the same run;
- adopting a new runtime happens in a **separate, explicitly approved upgrade step**;
- with no external immutable checker the answer is `TRUST_ANCHOR_MISSING`, never a
  fallback to the candidate.

**"Change the checker, commit it, then be trusted" is not a supported maintenance path.**

## Known residual

The anchor is required for features governed by a **scope manifest**
(`docs/scope/<feature>.scope.json`). A legacy **canvas-only** feature that was never armed
keeps the pre-existing, weaker posture, so that existing installations do not all block on
upgrade. That is a transition state, not a design goal: it means an unarmed canvas-only
feature is still governed only by artifacts inside the repository. Closing it means
migrating those features to manifests and arming them.

Covered by `config/claude/tests/test_run_trust_anchor.sh` (T1 commit-based checker bypass,
T2 rewritable baseline, T3 widening before the first gate run), each with a
counter-mutation that asserts the mutation actually applied.
