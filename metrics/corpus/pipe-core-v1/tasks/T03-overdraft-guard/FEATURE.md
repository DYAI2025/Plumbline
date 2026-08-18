# Feature: overdraft protection on withdrawal

`Account.withdraw(amount)` must reject overdrafts: if `amount` exceeds the balance it must
raise `InsufficientFunds` and leave the balance unchanged. **The balance must never go
negative.**

## What exists
- `src/account.py` — `Account(balance)` with `deposit`, `withdraw`, and a guard hook
  `_check_overdraft(amount)` (currently a no-op `pass`). `withdraw` already calls
  `self._check_overdraft(amount)` before deducting — implement the check there.
- `InsufficientFunds` exception is defined.

## Task
Implement `_check_overdraft` so an overdrawing withdrawal raises `InsufficientFunds` and
the balance is unchanged. Deliver implementation + tests.

## Run tests
`/home/dyai/clawd/hive-backlog/.venv/bin/python -m pytest -q` from the repo root.
