#!/usr/bin/env python3
"""Deterministic mutation applier for pipe-core-v1 gap-build oracles.

Usage: mutate.py <task-id> <repo-dir> [--restore]
Applies the task's regression mutation in-place (backs up to *.bak), and prints
APPLIED/INEFFECTIVE + an effectiveness check. Run the arm's `pytest -q` AFTER this,
then `--restore`. RED tests = CAUGHT, GREEN = ESCAPED.

Pilot-hardened (2026-05-29): the T03 stub regex must match a def line that ends in a
return annotation (`-> None:`), not just `):` — an earlier naive `\\):` anchor silently
no-matched (n=0) and produced a FALSE 'escaped'. Hence the explicit `applied`/effectiveness
report below — never trust a green result without confirming the mutation took.
"""
import re, os, sys, shutil, subprocess

PYBIN = "/home/dyai/clawd/hive-backlog/.venv/bin/python"


def _backup(f): shutil.copy(f, f + ".bak")
def restore(f):
    if os.path.exists(f + ".bak"): shutil.move(f + ".bak", f)


def mutate(task_id, d):
    if task_id.startswith("T08"):
        f = os.path.join(d, "src/accounts.py"); _backup(f)
        src = open(f).read()
        new = "\n".join(l for l in src.splitlines() if "delete_all" not in l) + "\n"
        open(f, "w").write(new)
        applied = new != src
        return f, applied, "un-wired store.delete_all from accounts.py"
    if task_id.startswith("T02"):
        f = os.path.join(d, "src/http_client.py"); _backup(f)
        src = open(f).read()
        new = "\n".join(l for l in src.splitlines() if "self.posts.append" not in l) + "\n"
        open(f, "w").write(new)
        applied = new != src
        return f, applied, "dropped webhook recording (FakeHttpClient.post no longer records)"
    if task_id.startswith("T09"):
        f = os.path.join(d, "src/bank.py"); _backup(f)
        src = open(f).read()
        # reset the _credit_or_rollback hook to the NAIVE body (credit, no rollback) —
        # removes atomicity. Coder-agnostic via the fixed hook. Matches the method body
        # up to the next dedented def or EOF.
        new, n = re.subn(
            r'(def _credit_or_rollback\(self.*:\n)(?:[ \t]+.*\n|[ \t]*\n)+?(?=\n?[ \t]*def |\Z)',
            r'\1        dst.credit(amount)\n', src, count=1)
        open(f, "w").write(new)
        return f, (n == 1), "reset _credit_or_rollback -> naive credit (atomicity/rollback removed)"
    if task_id.startswith("T03"):
        f = os.path.join(d, "src/account.py"); _backup(f)
        src = open(f).read()
        # match the def line to its FINAL colon (handles `-> None:` annotation)
        new, n = re.subn(
            r'(def _check_overdraft\(self.*:\n)(?:[ \t]+.*\n|[ \t]*\n)+?(?=[ \t]*def )',
            r'\1        pass\n', src, count=1)
        open(f, "w").write(new)
        return f, (n == 1), "stubbed _check_overdraft -> pass (guard removed)"
    raise SystemExit(f"unknown task {task_id}")


if __name__ == "__main__":
    task_id, d = sys.argv[1], sys.argv[2]
    if "--restore" in sys.argv:
        for fn in ("src/accounts.py", "src/http_client.py", "src/account.py"):
            restore(os.path.join(d, fn))
        print("restored"); sys.exit(0)
    f, applied, what = mutate(task_id, d)
    print(f"mutation: {what}")
    print(f"applied: {applied}" + ("" if applied else "   <-- WARNING: mutation did NOT take; a GREEN result here is a FALSE escape"))
