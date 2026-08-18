"""Object storage. InMemoryObjectStore is the test fake; prod would be S3ObjectStore."""
from __future__ import annotations
from typing import Dict, List


class InMemoryObjectStore:
    def __init__(self) -> None:
        self._files: Dict[str, Dict[str, bytes]] = {}

    def put(self, user_id: str, filename: str, data: bytes) -> None:
        self._files.setdefault(user_id, {})[filename] = data

    def list_files(self, user_id: str) -> List[str]:
        return list(self._files.get(user_id, {}).keys())

    def delete_all(self, user_id: str) -> None:
        self._files.pop(user_id, None)


class S3ObjectStore:  # pragma: no cover - production impl, never used in tests
    def put(self, user_id, filename, data): raise NotImplementedError("real S3")
    def list_files(self, user_id): raise NotImplementedError("real S3")
    def delete_all(self, user_id): raise NotImplementedError("real S3")
