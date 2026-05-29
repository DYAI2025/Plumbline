"""Persistence boundary for audit records."""
from __future__ import annotations

from typing import Protocol


class Store(Protocol):
    def append(self, record: str) -> None: ...
    def read_all(self) -> list[str]: ...


class FileStore:
    """Real boundary: persists records to a file, one per line.

    This is what production uses. A test that only exercises an in-memory fake
    of `Store` never proves THIS code works -- "tests green != it works".
    """

    def __init__(self, path: str) -> None:
        self.path = path

    def append(self, record: str) -> None:
        with open(self.path, "a", encoding="utf-8") as fh:
            fh.write(record + "\n")

    def read_all(self) -> list[str]:
        try:
            with open(self.path, encoding="utf-8") as fh:
                return [line.rstrip("\n") for line in fh if line.strip()]
        except FileNotFoundError:
            return []
