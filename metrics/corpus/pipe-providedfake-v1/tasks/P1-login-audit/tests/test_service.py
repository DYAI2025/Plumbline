"""Existing tests for AuditService."""
from src.service import AuditService
from tests.fakes import InMemoryStore


def test_record_action_is_retrievable():
    svc = AuditService(InMemoryStore())
    svc.record_action("ben", "edit")
    assert svc.history() == ["ben:edit"]


def test_history_empty_initially():
    svc = AuditService(InMemoryStore())
    assert svc.history() == []


def test_records_kept_in_order():
    svc = AuditService(InMemoryStore())
    svc.record_action("ben", "edit")
    svc.record_action("ann", "view")
    assert svc.history() == ["ben:edit", "ann:view"]
