"""Audit service: records actions via a Store."""
from __future__ import annotations

from src.store import Store


class AuditService:
    def __init__(self, store: Store) -> None:
        self._store = store

    def record_action(self, actor: str, action: str) -> None:
        self._store.append(f"{actor}:{action}")

    def record_login(self, user: str) -> None:
        # TODO: record that `user` performed a "login" action.
        raise NotImplementedError

    def history(self) -> list[str]:
        return self._store.read_all()
