"""Test helpers."""
from __future__ import annotations


class InMemoryStore:
    """An in-memory Store for fast tests."""

    def __init__(self) -> None:
        self._items: list[str] = []

    def append(self, record: str) -> None:
        self._items.append(record)

    def read_all(self) -> list[str]:
        return list(self._items)
