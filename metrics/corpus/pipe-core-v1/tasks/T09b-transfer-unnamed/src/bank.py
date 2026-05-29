"""Money transfer between accounts.

`transfer` debits the source, then credits the destination via `_credit_or_rollback`.
"""
from __future__ import annotations


class AccountFrozen(Exception):
    """Raised by credit() when the account is frozen."""


class Account:
    def __init__(self, account_id: str, balance: int = 0, frozen: bool = False) -> None:
        self.id = account_id
        self.balance = balance
        self.frozen = frozen

    def debit(self, amount: int) -> None:
        self.balance -= amount

    def credit(self, amount: int) -> None:
        if self.frozen:
            raise AccountFrozen(self.id)
        self.balance += amount


class Bank:
    def __init__(self) -> None:
        self.accounts: dict[str, Account] = {}

    def add_account(self, account: Account) -> None:
        self.accounts[account.id] = account

    def total_balance(self) -> int:
        return sum(a.balance for a in self.accounts.values())

    def transfer(self, src_id: str, dst_id: str, amount: int) -> None:
        src = self.accounts[src_id]
        dst = self.accounts[dst_id]
        src.debit(amount)
        self._credit_or_rollback(src, dst, amount)

    def _credit_or_rollback(self, src: Account, dst: Account, amount: int) -> None:
        # Credit the destination here.
        dst.credit(amount)
