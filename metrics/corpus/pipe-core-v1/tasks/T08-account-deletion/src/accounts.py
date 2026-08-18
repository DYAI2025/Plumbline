"""Account lifecycle. delete_account currently removes only the DB record."""
from __future__ import annotations
from typing import Dict


class AccountService:
    def __init__(self, db: Dict[str, dict], store) -> None:
        self.db = db
        self.store = store

    def create_account(self, user_id: str) -> None:
        self.db[user_id] = {"active": True}

    def has_account(self, user_id: str) -> bool:
        return user_id in self.db

    def delete_account(self, user_id: str) -> None:
        # FEATURE TO ADD: deleting an account must also remove the user's files.
        self.db.pop(user_id, None)
