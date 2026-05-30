"""FAKE-ONLY reference suite (extends the provided fake pattern).

Tests record_login via the in-memory fake — the path of least resistance the
scaffold hands you. Never touches FileStore, so a break in the real persistence
boundary is invisible -> the defect ESCAPES.
"""
from src.service import AuditService
from tests.fakes import InMemoryStore


def test_record_login_is_recorded():
    svc = AuditService(InMemoryStore())
    svc.record_login("ben")
    assert svc.history() == ["ben:login"]


def test_record_login_after_other_actions():
    svc = AuditService(InMemoryStore())
    svc.record_action("ben", "edit")
    svc.record_login("ann")
    assert svc.history() == ["ben:edit", "ann:login"]
