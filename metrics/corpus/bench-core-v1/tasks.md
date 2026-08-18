# bench-core-v1 — Task specs (ARM-FACING)

These are the only texts an arm sees. Each reads like an ordinary feature/review
request. **No task reveals its own planted gap** (seeing other tasks is harmless —
they are independent). The hidden detection keys live in `rubric.md` (judge-only).

Per task the arm is asked to produce, as its role directs: the acceptance/E2E test
plan (tester), the requirements + acceptance criteria (requirements-analyst), or the
review findings (code-reviewer). Keep outputs concise (names + one-line intent).

---

## T01 — Per-client rate limiting

Add per-client rate limiting to our HTTP API: once a client exceeds **100
requests/minute**, further requests get **HTTP 429** until the window resets.

## T02 — Outbound signed webhooks

When an invoice transitions to **`paid`**, send the customer an HMAC-signed JSON
payload via HTTP `POST` to their configured callback URL. An `HttpClient` interface is
available (with a test fake). Add the webhook feature.

## T03 — Read-through price cache

Add a read-through `PriceCache` in front of the pricing service to cut latency.
Behaviour: on a **cache miss**, fetch from the pricing service and store the result;
on a **cache-backend error or timeout**, fall back to the pricing service directly so
the caller **always** receives a price. Add the cache.

## T04 — Nightly ticket archive

Add a nightly job that archives every support ticket older than 90 days by calling the
vendor ticketing SDK's archive operation for each ticket id. The vendor SDK is
vendored in this repo at `vendor/ticketing_sdk.py`. Specify the acceptance criteria and
test plan for the archive job.

## T05 — Review this diff (`withdraw`)

Review the following change for merge.

```diff
+def withdraw(account, amount):
+    """Withdraw `amount` from `account`.
+
+    Raises InsufficientFunds if `amount` exceeds the balance; the account
+    balance is never left negative.
+    """
+    account.balance -= amount
+    return account.balance
```
```python
# tests added with the diff:
def test_withdraw_reduces_balance():
    acct = Account(balance=100)
    assert withdraw(acct, 30) == 70
```

## T06 — Discount calculator

Add a discount calculator: given a cart subtotal and a list of coupons (each either a
percentage or a fixed amount), compute the final total. This is a pure in-process
calculation — no I/O, no external services. Add it and its test plan.

## T07 — CSV order export (additional tests)

We are adding CSV export of orders. The spec is already settled and these are already
in scope and implemented: the export is wired into the `/orders/export` route
registered in the application factory; an acceptance test drives the assembled app
end-to-end and asserts the downloaded CSV bytes; the file write goes through the
storage abstraction and has a real-tmpdir integration test in CI. Propose any
**additional** test cases you would add on top of what's described.

## T08 — Account deletion file cleanup

When a user deletes their account, all of their files in object storage must be
removed too. There is an `ObjectStore` interface (S3-backed in production, an
in-memory fake in tests) and an existing account-deletion flow. Add the file cleanup.

## T10 — Format a duration

Add a helper that formats a duration given in whole seconds as a human-readable
string — e.g. `90 → "1m 30s"`, `3661 → "1h 1m 1s"`, `0 → "0s"`. Pure in-process
function, no I/O. Add it and its test plan.

## T11 — SMS for 2FA codes

When a user requests a 2FA code, send it to their phone via the vendored SMS SDK's
send operation. The vendor SDK is vendored in this repo at `vendor/sms_sdk.py`.
Specify the acceptance criteria and test plan for the SMS-sending path.

## T12 — Signup input validation

Add input validation for the signup form: reject malformed email addresses and
passwords shorter than 12 characters, returning a field-level error message for each.
This is pure validation logic. Add it and its test plan.

## T09 — Review this diff (`refund`)

Review the following change for merge.

```diff
+def refund(payment, amount):
+    """Refund up to `amount` from a captured payment.
+
+    Raises RefundTooLarge if `amount` exceeds the captured total. Returns the
+    remaining refundable balance.
+    """
+    if amount > payment.refundable:
+        raise RefundTooLarge(amount, payment.refundable)
+    payment.refundable -= amount
+    return payment.refundable
```
```python
# tests added with the diff:
def test_refund_reduces_refundable():
    p = Payment(refundable=100)
    assert refund(p, 30) == 70

def test_refund_over_capture_raises():
    p = Payment(refundable=50)
    with pytest.raises(RefundTooLarge):
        refund(p, 80)

def test_refund_exact_balance_allowed():
    p = Payment(refundable=40)
    assert refund(p, 40) == 0
```
