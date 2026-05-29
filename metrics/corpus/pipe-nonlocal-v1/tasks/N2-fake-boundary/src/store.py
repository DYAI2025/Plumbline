"""Storage for audit records."""
from __future__ import annotations

from typing import Protocol


class Store(Protocol):
    def append(self, record: str) -> None: ...
    def read_all(self) -> list[str]: ...


class FileStore:
    """Persists records to a file, one per line."""

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
