"""REAL-BOUNDARY reference suite (evidence-class: real-boundary-smoke).

Exercises AuditService against the real FileStore with a temp file and reads
the file back. If FileStore's real persistence is broken, this goes RED ->
the defect is CAUGHT. Temp files are permitted (no real network/service).
"""
import tempfile, os

from src.service import AuditService
from src.store import FileStore


def test_record_action_persists_to_file():
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "audit.log")
        svc = AuditService(FileStore(path))
        svc.record_action("ben", "login")
        # Re-open from disk: proves the bytes actually landed on the boundary.
        assert FileStore(path).read_all() == ["ben:login"]


def test_history_round_trips_through_disk():
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "audit.log")
        svc = AuditService(FileStore(path))
        svc.record_action("ben", "login")
        svc.record_action("ann", "edit")
        assert AuditService(FileStore(path)).history() == ["ben:login", "ann:edit"]
