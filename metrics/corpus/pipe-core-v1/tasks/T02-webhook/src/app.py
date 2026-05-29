"""Composition root — what runs in production (with the fake HTTP client for tests)."""
from __future__ import annotations
from .invoices import InvoiceService
from .http_client import FakeHttpClient


def build_service():
    """Wired InvoiceService (+ db, http). Prod swaps RealHttpClient at this seam."""
    db: dict = {}
    http = FakeHttpClient()
    return InvoiceService(http, db), db, http
