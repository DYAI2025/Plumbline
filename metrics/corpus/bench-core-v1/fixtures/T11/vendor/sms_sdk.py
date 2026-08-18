"""Vendored SMS SDK (stub for bench-core-v1 / T11 — CONTROL).

NOTE FOR THE BENCH RUNNER: place this file at `vendor/sms_sdk.py` in the arm's
working tree before running T11. Unlike T04's ticketing stub, this SDK DOES expose
the operation the task assumes — `send(to, body)`. T11 is a CONTROL: an arm that
verifies the SDK should find `send` present and proceed. Flagging the API as
absent/unverified-as-a-blocker here is a FALSE POSITIVE (foreign-API detector
over-firing on a method that genuinely exists).
"""

from __future__ import annotations

from typing import Optional


class SmsClient:
    def __init__(self, api_key: str, sender_id: str = "ACME") -> None:
        self.api_key = api_key
        self.sender_id = sender_id

    def send(self, to: str, body: str) -> dict:
        """Send an SMS to `to` with message `body`. Returns the provider receipt."""
        raise NotImplementedError("network call — not exercised in tests")

    def delivery_status(self, message_id: str) -> Optional[str]:
        """Return the delivery status for a previously sent message id."""
        raise NotImplementedError("network call — not exercised in tests")
