"""Invoices. mark_paid currently only flips status — no webhook is sent yet."""
from __future__ import annotations
from typing import Dict


class InvoiceService:
    def __init__(self, http, db: Dict[str, dict]) -> None:
        self.http = http
        self.db = db

    def create_invoice(self, invoice_id: str, customer_callback_url: str, amount: int) -> None:
        self.db[invoice_id] = {"status": "open", "url": customer_callback_url, "amount": amount}

    def mark_paid(self, invoice_id: str) -> None:
        # FEATURE TO ADD: when an invoice transitions to 'paid', send the customer an
        # HMAC-signed JSON payload via HTTP POST (self.http.post) to their callback URL.
        self.db[invoice_id]["status"] = "paid"
