# Oracle — T03-overdraft-guard (gap-build, failure-mode class)  [RUNNER-ONLY]

Dark zone: the failure/guard path (overdraft → raise) is described but obvious tests may
cover only the happy path (withdraw < balance).

## Mutation (deterministic, coder-agnostic via the fixed hook)
The scaffold pre-wires `withdraw` to call `self._check_overdraft(amount)`; the coder fills
that method. **Reset `_check_overdraft`'s body to a no-op:** replace the method body with
`pass` (the guard is removed; overdrafts now succeed and the balance goes negative). The
fixed hook makes this a clean single-method neutralization regardless of the coder's
implementation.

## Run + classify
Run the arm's own suite: `pytest -q`.
- **RED → CAUGHT** — a test withdraws more than the balance and asserts `InsufficientFunds`
  (or balance-unchanged). The guard is regression-protected.
- **GREEN → ESCAPED** — no test exercises the overdraft path; a removed guard ships
  silently (balance goes negative).

Restore after.
