"""Application assembly."""
from __future__ import annotations

from src.service import AuditService
from src.store import FileStore


def build_service(path: str) -> AuditService:
    """Build the AuditService as production runs it (file-backed)."""
    return AuditService(FileStore(path))
