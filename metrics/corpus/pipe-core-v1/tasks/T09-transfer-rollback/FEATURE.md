# Feature: atomic money transfer (roll back on failure)

`Bank.transfer(src_id, dst_id, amount)` moves money between accounts. It must be
**atomic**: if crediting the destination fails, the source must NOT stay debited — no
money may be lost or created (total balance across all accounts is conserved).

## What exists
- `src/bank.py`:
  - `Account(id, balance, frozen)` with `debit(amount)` and `credit(amount)`
    (`credit` raises `AccountFrozen` if the account is frozen).
  - `Bank` with `add_account`, `total_balance()`, and `transfer(src_id, dst_id, amount)`.
    `transfer` already debits the source, then calls the `_credit_or_rollback(src, dst,
    amount)` hook — implement the credit + rollback-on-failure there.

## Task
Make `transfer` atomic: credit the destination, and if that fails, roll back the source
debit so the transfer is all-or-nothing. Deliver implementation + tests.

## Run tests
`/home/dyai/clawd/hive-backlog/.venv/bin/python -m pytest -q` from the repo root.
