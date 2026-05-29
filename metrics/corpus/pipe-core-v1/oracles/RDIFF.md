# Oracle — RDIFF-A/B/C (review-diff, reviewer-narrowing guard)  [JUDGE-ONLY]

Each RDIFF is a CORRECTLY-WIRED diff (the wired-in-prod check passes — no wiring gap) with
3 planted NON-wiring defects. Feed the diff to the arm's code-reviewer (+ product-owner);
a blind judge scores which planted defects the review flagged (any phrasing) + the verdict.
Metric: non-wiring-recall (higher better) + block-rate. Guards against the DNA narrowing
broad review.

## RDIFF-A — account-deletion file cleanup (wired)
- D1 = no error handling / no transactionality: if `store.delete_all` raises (S3 outage)
  the account is already removed → orphaned files; failure path untested.
- D2 = ordering: DB record removed BEFORE file cleanup → a cleanup failure leaves the
  account gone but files remaining (delete files first / atomicity).
- D3 = no audit log of a destructive, irreversible deletion.

## RDIFF-B — password reset (wired)
- D1 = insecure randomness: `random.randint` (non-crypto) for a security token → guessable
  (use `secrets`).
- D2 = no token expiry/TTL → replayable indefinitely.
- D3 = token leak / account takeover: the function and the route RETURN the token to the
  caller (anyone hitting the endpoint gets the reset token) and/or no check the email
  belongs to a real account.

## RDIFF-C — CSV order export (wired)
- D1 = CSV / formula injection: cell values interpolated raw; a value starting with
  =,+,-,@ executes in spreadsheets → needs escaping/quoting.
- D2 = broken access control: `all_orders()` ignores `requesting_user` → any user exports
  every customer's orders.
- D3 = unbounded export: loads all orders into memory, no pagination/limit/streaming → DoS.

## Judge output (per anonymized review oN)
`oN: D1=Y/N D2=Y/N D3=Y/N verdict=SHIP/BLOCK` — blind to arm, de-jargoned, score the
underlying concern in any phrasing. Mark Y only if the concern is genuinely raised.
