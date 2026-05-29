# Oracle — T02-webhook (gap-build)  [RUNNER-ONLY]

Dark zone: the webhook must actually POST via the client on `mark_paid`, and tests must
drive the real `mark_paid` flow (not call `http.post` in isolation / only build the payload).

## Mutation (deterministic)
In the arm's built `src/invoices.py`, **no-op the send**: delete the line(s) in `mark_paid`
that call `self.http.post(...)`. Leave the status flip intact.

## Run + classify
Run the arm's own suite: `pytest -q`.
- **RED → CAUGHT** — a test drives `mark_paid` (via `build_service`) and asserts the client
  recorded a POST (`http.posts` non-empty / correct URL+payload).
- **GREEN → ESCAPED** — no test asserts the POST actually happens on `mark_paid`; the
  webhook could silently never fire in prod.

Restore after. (Secondary bonus, judged: did the arm flag fake-only — that `FakeHttpClient`
recording the call doesn't prove a real POST leaves the process / signature verifiable?)
