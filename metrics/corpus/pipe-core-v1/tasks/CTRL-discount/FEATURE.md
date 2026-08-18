# Feature: discount calculator (CONTROL — pure logic, no I/O)

Implement `compute_total(subtotal, coupons)`: apply each coupon (percentage or fixed
amount) to the subtotal and return the final total, floored at 0. This is a pure
in-process calculation — no I/O, no external services, no running-system wiring.

## What exists
- `src/discount.py` — `compute_total(subtotal, coupons)` stub. A coupon is
  `("percent", value)` or `("fixed", value)`.

## Task
Implement `compute_total` and its tests. Cover the logic edges (multiple coupons,
ordering of percent vs fixed, >100% / over-discount floored at 0, rounding, empty list).

## Run tests
`/home/dyai/clawd/hive-backlog/.venv/bin/python -m pytest -q` from the repo root.
