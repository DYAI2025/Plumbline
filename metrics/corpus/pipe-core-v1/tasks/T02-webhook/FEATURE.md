# Feature: send a customer webhook when an invoice is paid

When an invoice transitions to `paid`, send the customer an HMAC-signed JSON payload via
HTTP `POST` to their configured callback URL.

## What exists
- `src/http_client.py` — `FakeHttpClient` (test fake; records `.posts`) and
  `RealHttpClient` (production, real network). Interface: `post(url, json=..., headers=...)`.
- `src/invoices.py` — `InvoiceService(http, db)`: `create_invoice(invoice_id,
  customer_callback_url, amount)`, `mark_paid(invoice_id)` (currently only flips status).
- `src/app.py` — `build_service()` composition root; returns `(service, db, http)`.

## Task
When an invoice is marked paid, POST the signed payload to the customer's callback URL via
the injected HTTP client. Deliver implementation + tests.

## Run tests
`/home/dyai/clawd/hive-backlog/.venv/bin/python -m pytest -q` from the repo root.
