"""FAKE-ONLY reference suite (evidence-class: unit-fake).

Exercises AuditService against an in-memory fake Store. Never touches FileStore,
so a break in the real persistence boundary is invisible -> the defect ESCAPES.
"""
from src.service import AuditService


class FakeStore:
    def __init__(self):
        self._items: list[str] = []

    def append(self, record: str) -> None:
        self._items.append(record)

    def read_all(self) -> list[str]:
        return list(self._items)


def test_record_action_appends():
    svc = AuditService(FakeStore())
    svc.record_action("ben", "login")
    assert svc.history() == ["ben:login"]


def test_record_multiple():
    svc = AuditService(FakeStore())
    svc.record_action("ben", "login")
    svc.record_action("ben", "logout")
    assert svc.history() == ["ben:login", "ben:logout"]
