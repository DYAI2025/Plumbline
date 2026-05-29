"""Bank account. `withdraw` currently has NO overdraft protection (balance can go negative)."""
from __future__ import annotations


class InsufficientFunds(Exception):
    """Raised when a withdrawal would overdraw the account."""


class Account:
    def __init__(self, balance: int = 0) -> None:
        self.balance = balance

    def deposit(self, amount: int) -> int:
        self.balance += amount
        return self.balance

    def _check_overdraft(self, amount: int) -> None:
        # FEATURE TO ADD (see FEATURE.md): raise InsufficientFunds if `amount` would
        # overdraw the account. `withdraw` already calls this guard before deducting —
        # implement the check here so the balance can never go negative.
        pass

    def withdraw(self, amount: int) -> int:
        self._check_overdraft(amount)   # overdraft guard hook
        self.balance -= amount
        return self.balance
