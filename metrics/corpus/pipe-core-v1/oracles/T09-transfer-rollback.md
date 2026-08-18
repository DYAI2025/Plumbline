# Oracle — T09-transfer-rollback (gap-build, SEPARABLE dark zone)  [RUNNER-ONLY]

The "hard" task: the dark zone (roll back the source debit when crediting a frozen
destination fails) is **separable from the happy path**. A transfer to a normal account
succeeds with no rollback needed — so the obvious happy-path acceptance test passes GREEN
without ever exercising the dark zone. Only a test that transfers to a *frozen* destination
and asserts the source was restored (money conserved) covers it. This is where "the build
forces the guarding test" may finally NOT hold.

## Mutation (deterministic, coder-agnostic via the fixed hook)
`mutate.py T09 <dir>` resets the `_credit_or_rollback` hook body to the NAIVE
`dst.credit(amount)` (removes the rollback / atomicity). Verified: a correct impl passes
both happy + rollback tests; after the mutation the happy-path test still PASSES and only a
rollback/atomicity test FAILS — so the mutation is caught ONLY by a dark-zone test.

## Run + classify
Apply mutation (confirm `applied: True`), run the arm's own `pytest -q`:
- **RED → CAUGHT** — the arm wrote a frozen-destination rollback / money-conservation test.
- **GREEN → ESCAPED** — the arm tested only the happy path; the partial-failure money-loss
  bug ships silently. (This is the outcome the DNA's Gegenthese — "could be green yet lose
  money on partial failure?" — is meant to prevent.)

Restore after (`--restore`).
