# Feature: money transfer

Implement `Bank.transfer(src_id, dst_id, amount)` to move `amount` from the source
account to the destination account.

## What exists
- `src/bank.py`:
  - `Account(id, balance, frozen)` with `debit(amount)` and `credit(amount)`.
  - `Bank` with `add_account`, `total_balance()`, and `transfer(src_id, dst_id, amount)`.
    `transfer` debits the source, then calls `_credit_or_rollback(src, dst, amount)` to
    credit the destination — complete that hook.

## Task
Make `transfer` move the money correctly. Deliver the implementation and its tests.

## Run tests
`/home/dyai/clawd/hive-backlog/.venv/bin/python -m pytest -q` from the repo root.
