"""Pure-logic discount calculator. No I/O, no services, no composition root."""
from __future__ import annotations
from typing import List, Tuple

# A coupon is a tuple: ("percent", value) e.g. ("percent", 10) = 10% off,
# or ("fixed", value) e.g. ("fixed", 5) = 5 currency units off.
Coupon = Tuple[str, float]


def compute_total(subtotal: float, coupons: List[Coupon]) -> float:
    # FEATURE TO ADD (see FEATURE.md): apply each coupon to the subtotal and return the
    # final total, floored at 0. Pure in-process calculation — there is NO I/O, no
    # external service, and no running-system wiring involved.
    raise NotImplementedError
