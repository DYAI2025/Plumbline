"""Composition root — what runs in production."""
from __future__ import annotations
from .accounts import AccountService
from .store import InMemoryObjectStore


def build_service():
    """Construct the wired AccountService (+ db, store) as production uses it."""
    db: dict = {}
    store = InMemoryObjectStore()
    return AccountService(db, store), db, store
