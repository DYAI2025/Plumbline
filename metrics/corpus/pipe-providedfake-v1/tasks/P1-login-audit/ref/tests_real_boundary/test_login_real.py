"""REAL-BOUNDARY reference suite (deliberate extra setup).

Tests record_login through the production assembly build_service() with a real
temp-file FileStore, then reads the file back. If the real persistence boundary
is broken, this goes RED -> the defect is CAUGHT. Requires the extra work of a
temp file (tempfile permitted; no real network/service).
"""
import tempfile, os

from src.app import build_service
from src.store import FileStore


def test_record_login_persists_to_real_file():
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "audit.log")
        svc = build_service(path)
        svc.record_login("ben")
        # Re-read from disk: proves the login actually landed on the real boundary.
        assert FileStore(path).read_all() == ["ben:login"]


def test_login_survives_fresh_service_instance():
    with tempfile.TemporaryDirectory() as d:
        path = os.path.join(d, "audit.log")
        build_service(path).record_login("ben")
        assert build_service(path).history() == ["ben:login"]
