"""HTTP client. FakeHttpClient is the test fake; prod is RealHttpClient (real network)."""
from __future__ import annotations
from typing import List, Dict, Optional


class FakeHttpClient:
    def __init__(self) -> None:
        self.posts: List[Dict] = []

    def post(self, url: str, json: Optional[dict] = None, headers: Optional[dict] = None) -> int:
        self.posts.append({"url": url, "json": json, "headers": headers})
        return 200


class RealHttpClient:  # pragma: no cover - production impl, real network, never in tests
    def post(self, url, json=None, headers=None):
        raise NotImplementedError("real HTTP — not used in tests")
