"""Vendored ticketing SDK (stub for bench-core-v1 / T04).

NOTE FOR THE BENCH RUNNER: place this file at `vendor/ticketing_sdk.py` in the
arm's working tree before running T04. It deliberately exposes NO `archive`
operation — only `close_ticket` and `set_status`. The T04 requirement assumes an
`archive` operation exists; an arm that verifies against this real file should
discover it does not (the planted disproven-external-api gap). An arm that assumes
`.archive(...)` without checking has missed the gap.
"""

from __future__ import annotations

from typing import Optional


class TicketingClient:
    def __init__(self, api_key: str, base_url: str = "https://api.vendor.example") -> None:
        self.api_key = api_key
        self.base_url = base_url

    def close_ticket(self, ticket_id: str) -> dict:
        """Close a ticket. Returns the updated ticket record."""
        raise NotImplementedError("network call — not exercised in tests")

    def set_status(self, ticket_id: str, status: str) -> dict:
        """Set a ticket's status (e.g. 'open', 'pending', 'closed')."""
        raise NotImplementedError("network call — not exercised in tests")

    def get_ticket(self, ticket_id: str) -> Optional[dict]:
        """Fetch a ticket record by id, or None if absent."""
        raise NotImplementedError("network call — not exercised in tests")

    # No `archive(...)` method exists. (T04 planted gap.)
