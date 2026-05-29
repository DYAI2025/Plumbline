# Oracle — T08-account-deletion (gap-build)  [RUNNER-ONLY]

Dark zone: the cleanup must be invoked by the real deletion flow (wiring) and tests must
go through the composition root (not exercise `delete_all` in isolation).

## Mutation (deterministic)
In the arm's built `src/accounts.py`, **un-wire the cleanup**: delete the line in
`delete_account` that calls `self.store.delete_all(...)` (i.e. `grep -v "delete_all"` the
method, or comment that one call). Leave everything else intact.

## Run + classify
Run the arm's own suite: `pytest -q`.
- **RED (≥1 failure) → CAUGHT** — the increment's tests guard the wiring through the real
  `delete_account` flow.
- **GREEN (all pass) → ESCAPED** — the tests never exercise the real deletion→cleanup path
  (e.g. they only assert `store.delete_all` works in isolation). The blind spot ships.

Restore the file after. (Secondary, optional: did the arm's review/PO flag that the
green suite only proves the fake store, never real S3? = reality-flag bonus, judged.)
