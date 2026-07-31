"""Shared CLI-invocation contract for the PRIL checkers.

NEW-1. `argparse` exits **2** on a usage error — an unknown flag, a missing
required option, a bad arity. The PRIL exit contract already assigns **2** the
meaning *MISSING*: the checker ran and found no evidence to judge. The enforce
hook therefore classified a mis-invoked checker as `PRIL_INPUT_MISSING`, i.e.
"nothing to check", which is indistinguishable from a clean absence of input.

A checker that could not be invoked has produced **no verdict at all**. That is a
tool fault, not a finding, and it must never be readable as "nothing to check" —
the tool-error / policy-violation / unresolvable-evidence distinction is the whole
point of the exit contract.

`PlumblineArgumentParser` moves usage errors onto their own reserved code
(**122**, `TOOL_INVOCATION_ERROR`) and prints a machine-readable token. 120 and
121 are already reserved for tool-unavailable and tool-broken; 122 joins that
*tool* family, and no policy code is ever added in that range.
"""

from __future__ import annotations

import argparse
import sys
from typing import NoReturn

# Reserved tool-fault exit codes. Policy codes (0/2/3/4) never appear here.
EXIT_TOOL_UNAVAILABLE = 120
EXIT_TOOL_BROKEN = 121
EXIT_TOOL_INVOCATION_ERROR = 122

TOOL_INVOCATION_TOKEN = "PRIL_TOOL_INVOCATION_ERROR"


class PlumblineArgumentParser(argparse.ArgumentParser):
    """An ArgumentParser whose usage errors are tool faults, not policy results."""

    def error(self, message: str) -> NoReturn:
        print(
            f"{TOOL_INVOCATION_TOKEN}: {self.prog}: {message}",
            file=sys.stderr,
        )
        print(
            f"{TOOL_INVOCATION_TOKEN}: the checker was invoked incorrectly and "
            "produced NO verdict. This is not a finding and not an absence of "
            "input; do not read it as either.",
            file=sys.stderr,
        )
        raise SystemExit(EXIT_TOOL_INVOCATION_ERROR)

    # argparse also calls exit() directly for --help (status 0) and, in some
    # paths, for errors raised by subparsers. Route any non-zero status that
    # would otherwise collide with a policy code onto the tool-fault code.
    def exit(self, status: int = 0, message: str | None = None) -> NoReturn:
        if message:
            print(message, file=sys.stderr, end="")
        if status != 0:
            raise SystemExit(EXIT_TOOL_INVOCATION_ERROR)
        raise SystemExit(0)
