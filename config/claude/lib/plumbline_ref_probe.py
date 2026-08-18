#!/usr/bin/env python3
"""Proof of CURRENT remote refs. Nothing else.

This module answers exactly one question: **what OIDs does the remote have,
right now, for these exact refs?** It is deliberately not a PR-state provider,
not a lifecycle, and not a merge detector.

`git ls-remote` shows ref tips. It cannot say *why* a ref moved or vanished, so
this module never classifies a merge — a deleted ref is `REMOTE_REF_MISSING`, and
what that means is somebody else's judgement to make from forge evidence or graph
evidence. Overclaiming here is how a previous attempt reported "the branch was
merged into the base" for an unrelated hotfix.

It also never reads `origin/*`. A local remote-tracking ref is a cached answer to
a question asked earlier; if the remote cannot be consulted the answer is
``REMOTE_UNREACHABLE``, never the cache.

Classes
-------
``REMOTE_REF_UNCHANGED``      every expected ref matches the OID it was bound to
``REMOTE_REF_CHANGED``        an expected ref resolves to a different OID
``REMOTE_REF_NOT_PUBLISHED``  a ref with no expectation is absent (a branch that
                              has not been pushed yet — a fact, not a failure)
``REMOTE_REF_MISSING``        a ref that WAS bound is gone from the remote
``REMOTE_IDENTITY_CHANGED``   the remote name or URL is not the bound one
``REMOTE_UNREACHABLE``        the remote could not be contacted
``REMOTE_AUTH_FAILED``        credentials were refused or unavailable
``REMOTE_TIMEOUT``            no answer inside the internal budget
``REMOTE_OUTPUT_MALFORMED``   the output was not exactly what was asked for
``MALFORMED_REQUEST``         the caller asked for something ambiguous

Exit codes: 0 pass · 3 changed/missing/identity · 4 malformed request ·
5 unverified (unreachable / auth / timeout / malformed output).
"""

from __future__ import annotations

import json
import os
import re
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from plumbline_cli import (  # noqa: E402  (path shim above must run first)
    PlumblineArgumentParser,
)

EXIT_PASS = 0
EXIT_CHANGED = 3
EXIT_MALFORMED_REQUEST = 4
EXIT_UNVERIFIED = 5

UNCHANGED = "REMOTE_REF_UNCHANGED"
CHANGED = "REMOTE_REF_CHANGED"
NOT_PUBLISHED = "REMOTE_REF_NOT_PUBLISHED"
MISSING = "REMOTE_REF_MISSING"
IDENTITY_CHANGED = "REMOTE_IDENTITY_CHANGED"
UNREACHABLE = "REMOTE_UNREACHABLE"
AUTH_FAILED = "REMOTE_AUTH_FAILED"
TIMEOUT = "REMOTE_TIMEOUT"
OUTPUT_MALFORMED = "REMOTE_OUTPUT_MALFORMED"
MALFORMED_REQUEST = "MALFORMED_REQUEST"

SCHEMA = 1
DEFAULT_TIMEOUT_S = 4

# Full ref names only. A short branch name is ambiguous -- `x` could be a branch,
# a tag or a remote -- and resolving it would silently pick one.
REF_RE = re.compile(r"^refs/heads/[A-Za-z0-9._/-]+$")
# sha1 (40) or sha256 (64).
OID_RE = re.compile(r"^[0-9a-f]{40}([0-9a-f]{24})?$")
LINE_RE = re.compile(r"^([0-9a-f]+)\t(\S+)$")

AUTH_MARKERS = (
    "authentication failed",
    "could not read username",
    "could not read password",
    "permission denied",
    "access denied",
    "invalid username or password",
    "terminal prompts disabled",
)


def _emit(payload: dict, code: int) -> int:
    """Structured result on stdout, always. Diagnostics stay on stderr."""
    print(json.dumps(payload, indent=2, sort_keys=True))
    return code


def _run_git(repo: Path, args: list[str], timeout: int) -> tuple[str, subprocess.CompletedProcess | None, str]:
    """Run git with prompting disabled and stdin closed.

    ``GIT_TERMINAL_PROMPT=0`` stops git asking for credentials on the terminal,
    and ``stdin=DEVNULL`` means nothing can be read from the caller's terminal
    even if something tried. A hook that blocks on a hidden prompt is a hook that
    never returns a decision.
    """
    env = dict(os.environ)
    env["GIT_TERMINAL_PROMPT"] = "0"
    env.setdefault("GIT_CONFIG_NOSYSTEM", "1")
    try:
        proc = subprocess.run(
            ["git", "-C", str(repo), *args],
            stdin=subprocess.DEVNULL,
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
            check=False,
        )
    except subprocess.TimeoutExpired:
        return TIMEOUT, None, f"the remote did not answer within {timeout}s"
    except OSError as exc:
        return UNREACHABLE, None, f"git could not be executed: {exc}"
    return "", proc, ""


def _classify_failure(proc: subprocess.CompletedProcess) -> tuple[str, str]:
    text = ((proc.stderr or "") + " " + (proc.stdout or "")).lower()
    for marker in AUTH_MARKERS:
        if marker in text:
            return AUTH_FAILED, (proc.stderr or proc.stdout or "").strip().splitlines()[0]
    detail = (proc.stderr or proc.stdout or "").strip().splitlines()
    return UNREACHABLE, detail[0] if detail else f"git ls-remote exited {proc.returncode}"


def parse_ls_remote(text: str, refs: list[str]) -> tuple[str | None, dict[str, str], str]:
    """Accept exactly one valid OID per requested ref, and nothing else.

    Kept as a separate function because real git refuses a malformed transport
    before its bytes ever reach us -- so this is the only place the rejection can
    actually be exercised. That is a unit test, and calling it anything else
    would be an overclaim: a broken remote helper is classified UNREACHABLE by
    git long before parsing begins.
    """
    seen: dict[str, str] = {}
    for line in text.splitlines():
        if not line.strip():
            continue
        m = LINE_RE.match(line)
        if not m:
            return OUTPUT_MALFORMED, {}, f"unparseable ls-remote line: {line!r}"
        oid, name = m.group(1), m.group(2)
        if not OID_RE.match(oid):
            return OUTPUT_MALFORMED, {}, f"not an object id: {oid!r} for {name!r}"
        if name not in refs:
            return OUTPUT_MALFORMED, {}, f"the remote returned {name!r}, which was not requested"
        if name in seen:
            return OUTPUT_MALFORMED, {}, f"the remote returned {name!r} more than once"
        seen[name] = oid
    return None, seen, ""


def probe(
    repo: Path,
    remote: str,
    refs: list[str],
    expected: dict[str, str],
    expect_url: str | None,
    timeout: int,
) -> tuple[dict, int]:
    result: dict = {
        "schema": SCHEMA,
        "remote": {"name": remote, "url": None},
        "refs": {},
        "status": None,
        "detail": None,
    }

    for ref in refs:
        if not REF_RE.match(ref):
            result["status"] = MALFORMED_REQUEST
            result["detail"] = (
                f"{ref!r} is not a full ref name. Ask for refs/heads/<branch> exactly; "
                "a short name is ambiguous and would be resolved by guessing."
            )
            return result, EXIT_MALFORMED_REQUEST
    for ref in expected:
        if ref not in refs:
            result["status"] = MALFORMED_REQUEST
            result["detail"] = f"an expectation was given for {ref!r}, which was not requested"
            return result, EXIT_MALFORMED_REQUEST
    for ref, oid in expected.items():
        if not OID_RE.match(oid):
            result["status"] = MALFORMED_REQUEST
            result["detail"] = f"the expected OID for {ref!r} is not an object id"
            return result, EXIT_MALFORMED_REQUEST
    if not refs:
        result["status"] = MALFORMED_REQUEST
        result["detail"] = "no refs requested"
        return result, EXIT_MALFORMED_REQUEST

    # --- identity: the remote must still be the one that was bound -------------
    cls, proc, detail = _run_git(repo, ["remote", "get-url", remote], timeout)
    if cls:
        result["status"] = cls
        result["detail"] = detail
        return result, EXIT_UNVERIFIED
    assert proc is not None
    if proc.returncode != 0:
        result["status"] = IDENTITY_CHANGED
        result["detail"] = f"the remote {remote!r} does not exist in this repository"
        return result, EXIT_CHANGED
    url = proc.stdout.strip()
    result["remote"]["url"] = url
    if expect_url is not None and url != expect_url:
        result["status"] = IDENTITY_CHANGED
        result["detail"] = (
            f"the remote {remote!r} now points at {url!r}, not the bound {expect_url!r}. "
            "A different remote is not a fresh valid starting point."
        )
        return result, EXIT_CHANGED

    # --- the one question this module answers ---------------------------------
    cls, proc, detail = _run_git(repo, ["ls-remote", "--", remote, *refs], timeout)
    if cls:
        result["status"] = cls
        result["detail"] = detail
        return result, EXIT_UNVERIFIED
    assert proc is not None
    if proc.returncode != 0:
        status, detail = _classify_failure(proc)
        result["status"] = status
        result["detail"] = detail
        return result, EXIT_UNVERIFIED

    problem, seen, detail = parse_ls_remote(proc.stdout, refs)
    if problem:
        result["status"] = problem
        result["detail"] = detail
        return result, EXIT_UNVERIFIED

    changed = False
    for ref in refs:
        oid = seen.get(ref)
        want = expected.get(ref)
        if oid is None:
            # Absent. Whether that is a fact or a loss depends entirely on
            # whether anything was ever bound to it.
            cls = MISSING if want else NOT_PUBLISHED
            if want:
                changed = True
            result["refs"][ref] = {"class": cls, "oid": None, "expected": want}
            continue
        if want is None:
            result["refs"][ref] = {"class": UNCHANGED, "oid": oid, "expected": None}
            continue
        if oid == want:
            result["refs"][ref] = {"class": UNCHANGED, "oid": oid, "expected": want}
        else:
            changed = True
            result["refs"][ref] = {"class": CHANGED, "oid": oid, "expected": want}

    if changed:
        result["status"] = CHANGED
        result["detail"] = "at least one bound ref no longer matches the remote"
        return result, EXIT_CHANGED
    result["status"] = UNCHANGED
    result["detail"] = "every bound ref matches the remote as it is right now"
    return result, EXIT_PASS


def build_parser() -> PlumblineArgumentParser:
    parser = PlumblineArgumentParser(
        prog="plumbline-ref-probe",
        description="Proof of current remote refs. Not a PR-state provider.",
    )
    sub = parser.add_subparsers(dest="command", required=True)
    p = sub.add_parser("probe", help="read the remote's current OIDs for exact refs")
    p.add_argument("--repo", required=True)
    p.add_argument("--remote", default="origin")
    p.add_argument("--ref", action="append", default=[],
                   help="full ref name, e.g. refs/heads/main (repeatable)")
    p.add_argument("--expect", action="append", default=[],
                   help="refs/heads/x=<oid> (repeatable)")
    p.add_argument("--expect-url", help="the remote URL this run was bound to")
    p.add_argument("--timeout", type=int, default=DEFAULT_TIMEOUT_S)
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    repo = Path(args.repo)
    if not repo.is_dir():
        return _emit(
            {"schema": SCHEMA, "status": MALFORMED_REQUEST,
             "detail": f"not a directory: {repo}", "refs": {}},
            EXIT_MALFORMED_REQUEST,
        )
    expected: dict[str, str] = {}
    for item in args.expect:
        if "=" not in item:
            return _emit(
                {"schema": SCHEMA, "status": MALFORMED_REQUEST,
                 "detail": f"--expect needs ref=oid, got {item!r}", "refs": {}},
                EXIT_MALFORMED_REQUEST,
            )
        ref, oid = item.split("=", 1)
        expected[ref.strip()] = oid.strip()

    payload, code = probe(
        repo, args.remote, list(args.ref), expected, args.expect_url, args.timeout
    )
    if code != EXIT_PASS:
        print(f"{payload['status']}: {payload.get('detail')}", file=sys.stderr)
    return _emit(payload, code)


if __name__ == "__main__":
    raise SystemExit(main())
