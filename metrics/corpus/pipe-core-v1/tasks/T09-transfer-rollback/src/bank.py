"""Money transfer between accounts.

`transfer` debits the source first, then credits the destination via the
`_credit_or_rollback` hook. The hook is currently NAIVE: it credits the destination
but does NOT roll back the source debit if crediting fails — so a transfer to a frozen
destination silently destroys money (source debited, destination unchanged).
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
        src.debit(amount)                       # money leaves the source first
        self._credit_or_rollback(src, dst, amount)

    def _credit_or_rollback(self, src: Account, dst: Account, amount: int) -> None:
        # FEATURE TO ADD (see FEATURE.md): credit `dst` with `amount`. If crediting
        # FAILS (a frozen dst raises AccountFrozen), you MUST roll back the debit already
        # applied to `src` so the transfer is atomic — no money may be lost or created.
        dst.credit(amount)
