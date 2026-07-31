#!/usr/bin/env python3
"""Immutable run-trust anchor for the Plumbline gates.

The previous design bound trust to two things the judged party still controlled:

* **checker integrity was measured against the current ``HEAD``.** Modify the
  checker, *commit* it, and it becomes tracked and byte-identical to ``HEAD`` --
  so the guard trusted it. "Change the checker, commit, then be trusted" is not a
  supported maintenance path, and a moving reference cannot carry trust.
* **the scope baseline lived inside the controlled repository** and was created
  by the gate itself on first use. An artifact the judged party can rewrite, and
  that the judge will cheerfully re-create, is not an anchor. It also meant the
  first gate run *was* the arming moment, so any widening performed before it was
  silently adopted as the baseline.

The anchor fixes the frame of reference:

* it is written **outside** the governed repository, under a Plumbline state
  directory, so a repository write cannot reach it;
* it is written by an **externally installed** Plumbline CLI -- a candidate
  checkout may not nominate itself as the trusted runtime;
* it is written **once**, before implementation writes begin, and re-arming an
  armed run is refused;
* **gates only read it.** No gate creates, repairs, or updates an anchor. A
  missing, altered or unreadable anchor is a classified block, never a silent
  pass and never an auto-arm.

What it binds: canonical repository path and id, feature, start branch and start
commit, the manifest path and digest, the physical in-repo checker/updater paths
and their digests, and the arming timestamp.
"""

from __future__ import annotations

import hashlib
import json
import os
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from plumbline_cli import (  # noqa: E402  (path shim above must run first)
    PlumblineArgumentParser,
)

EXIT_PASS = 0
EXIT_MISSING = 2
EXIT_VIOLATION = 3
EXIT_MALFORMED = 4

ANCHOR_SCHEMA = 1

TOKEN_MISSING = "RUN_TRUST_BASELINE_MISSING"
TOKEN_CHANGED = "RUN_TRUST_BASELINE_CHANGED"
TOKEN_UNREADABLE = "RUN_TRUST_BASELINE_UNREADABLE"
TOKEN_CHECKER = "RUN_TRUST_CHECKER_CHANGED"
TOKEN_SELF_HOSTED = "TRUST_ANCHOR_SELF_HOSTED"
TOKEN_ALREADY_ARMED = "TRUST_ANCHOR_ALREADY_ARMED"
TOKEN_ANCHOR_MISSING = "TRUST_ANCHOR_MISSING"

# In-repo runtime that a candidate checkout could rewrite between arming and the
# gate run. Recorded by digest at arming; compared, never refreshed.
CHECKER_GLOBS = (
    "config/claude/bin/plumbline-*",
    "config/claude/lib/plumbline_*.py",
    "config/claude/lib/plumbline_python.sh",
)


def state_dir() -> Path:
    """Where anchors live. Never inside a governed repository."""
    explicit = os.environ.get("PLUMBLINE_STATE_DIR")
    if explicit:
        return Path(explicit)
    xdg = os.environ.get("XDG_STATE_HOME")
    if xdg:
        return Path(xdg) / "plumbline"
    return Path(os.path.expanduser("~")) / ".local" / "state" / "plumbline"


def repo_id(repo: Path) -> str:
    canonical = str(repo.resolve())
    return hashlib.sha256(canonical.encode("utf-8")).hexdigest()[:16]


def anchor_path(repo: Path, feature: str) -> Path:
    return state_dir() / "run-trust" / repo_id(repo) / f"{feature}.json"


def digest_file(path: Path) -> str | None:
    try:
        return hashlib.sha256(path.read_bytes()).hexdigest()
    except OSError:
        return None


def manifest_rel(feature: str) -> str:
    return f"docs/scope/{feature}.scope.json"


def _git(repo: Path, *args: str) -> str | None:
    try:
        out = subprocess.run(
            ["git", "-C", str(repo), *args],
            capture_output=True, text=True, timeout=15, check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0:
        return None
    return out.stdout.strip()


def collect_checkers(repo: Path) -> dict[str, str]:
    """Digest every in-repo Plumbline runtime file, keyed by repo-relative path.

    Only files *inside* the governed repository are recorded: those are the ones
    a run could rewrite. An externally installed runtime is out of reach here and
    is anchored by being external.
    """
    found: dict[str, str] = {}
    for pattern in CHECKER_GLOBS:
        for path in sorted(repo.glob(pattern)):
            if not path.is_file():
                continue
            digest = digest_file(path)
            if digest is None:
                continue
            found[str(path.relative_to(repo))] = digest
    return found


def cli_is_inside(repo: Path) -> bool:
    """True when THIS module is itself part of the repository being armed."""
    here = Path(__file__).resolve()
    try:
        here.relative_to(repo.resolve())
    except ValueError:
        return False
    return True


def arm(repo: Path, feature: str) -> int:
    repo = repo.resolve()

    if cli_is_inside(repo):
        print(
            f"ERROR: {TOKEN_SELF_HOSTED}: this Plumbline runtime lives inside the "
            f"repository it was asked to arm ({repo}). A candidate checkout cannot "
            "declare itself the trusted checker. Arm the run with an externally "
            "installed Plumbline.",
            file=sys.stderr,
        )
        return EXIT_VIOLATION

    target = anchor_path(repo, feature)
    if target.exists():
        print(
            f"ERROR: {TOKEN_ALREADY_ARMED}: {target} already binds this run. An "
            "anchor is bound once. To change the confirmed scope, disarm the run "
            "explicitly, have the new scope confirmed, then re-arm.",
            file=sys.stderr,
        )
        return EXIT_VIOLATION

    manifest = repo / manifest_rel(feature)
    manifest_digest = digest_file(manifest)
    if manifest_digest is None:
        print(
            f"ERROR: no scope manifest at {manifest_rel(feature)}; there is nothing "
            "confirmed to bind. Author and confirm the manifest first.",
            file=sys.stderr,
        )
        return EXIT_MISSING

    payload = {
        "schema": ANCHOR_SCHEMA,
        "repo_path": str(repo),
        "repo_id": repo_id(repo),
        "feature": feature,
        "start_branch": _git(repo, "rev-parse", "--abbrev-ref", "HEAD") or "",
        "start_commit": _git(repo, "rev-parse", "HEAD") or "",
        "manifest_path": manifest_rel(feature),
        "manifest_digest": manifest_digest,
        "checkers": collect_checkers(repo),
        "armed_at": datetime.now(timezone.utc).isoformat(),
        "armed_by": str(Path(__file__).resolve()),
    }
    try:
        target.parent.mkdir(parents=True, exist_ok=True)
        tmp = target.with_name(target.name + ".tmp")
        tmp.write_text(json.dumps(payload, indent=2) + "\n", encoding="utf-8")
        os.replace(tmp, target)
    except OSError as exc:
        print(f"ERROR: could not write the run-trust anchor: {exc}", file=sys.stderr)
        return EXIT_MALFORMED

    print(
        f"run armed: feature={feature} repo={repo} anchor={target} "
        f"manifest={manifest_rel(feature)} checkers={len(payload['checkers'])}"
    )
    return EXIT_PASS


def disarm(repo: Path, feature: str) -> int:
    target = anchor_path(repo.resolve(), feature)
    if not target.exists():
        print(f"no anchor to disarm at {target}")
        return EXIT_PASS
    try:
        target.unlink()
    except OSError as exc:
        print(f"ERROR: could not remove the anchor: {exc}", file=sys.stderr)
        return EXIT_MALFORMED
    print(f"run disarmed: feature={feature} anchor={target}")
    return EXIT_PASS


def load_anchor(repo: Path, feature: str) -> tuple[str | None, dict | None]:
    """Read the anchor. Returns ``(error_token_message, payload)``.

    Never writes. Never repairs. A run this cannot prove is a blocked run.
    """
    target = anchor_path(repo.resolve(), feature)
    if not target.exists():
        return (
            f"{TOKEN_MISSING}: no run-trust anchor at {target}. This run was never "
            "armed, or its anchor was removed. Gates do not create anchors; arm the "
            "run with an externally installed Plumbline.",
            None,
        )
    try:
        data = json.loads(target.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return (
            f"{TOKEN_UNREADABLE}: the run-trust anchor at {target} cannot be read as "
            "JSON. It is left exactly as found; a gate never repairs an anchor. "
            "Disarm the run explicitly and re-arm it.",
            None,
        )
    if not isinstance(data, dict) or data.get("schema") != ANCHOR_SCHEMA:
        return (
            f"{TOKEN_UNREADABLE}: the run-trust anchor at {target} is not a schema "
            f"{ANCHOR_SCHEMA} record.",
            None,
        )
    return None, data


def verify_run_trust(repo: Path, feature: str) -> str | None:
    """Verify the current tree against the bound anchor. Read-only.

    Returns an error message on violation, or ``None`` when the run may proceed.
    """
    repo = repo.resolve()
    error, data = load_anchor(repo, feature)
    if error is not None:
        return error
    assert data is not None

    if data.get("feature") != feature:
        return (
            f"{TOKEN_CHANGED}: the anchor binds feature {data.get('feature')!r}, not "
            f"{feature!r}."
        )
    if data.get("repo_id") != repo_id(repo):
        return (
            f"{TOKEN_CHANGED}: the anchor was bound for a different repository "
            f"({data.get('repo_path')})."
        )

    manifest = repo / str(data.get("manifest_path") or manifest_rel(feature))
    current = digest_file(manifest)
    bound = data.get("manifest_digest")
    if current is None:
        return (
            f"{TOKEN_CHANGED}: the bound scope manifest {data.get('manifest_path')} is "
            "gone. An armed run cannot lose the artifact that defines its authority."
        )
    if current != bound:
        return (
            f"{TOKEN_CHANGED}: {data.get('manifest_path')} differs from the baseline "
            f"bound at arming (bound {str(bound)[:12]}, now {current[:12]}). The scope "
            "confirmed for this run cannot be widened from inside it. Disarm, have the "
            "new scope confirmed, then re-arm."
        )
    return None


def verify_checkers(repo: Path, feature: str) -> str | None:
    """Compare in-repo runtime files against the digests bound at arming.

    This is what defeats "modify the checker, commit it, be trusted": the
    comparison is against the state bound BEFORE the run, not against a ``HEAD``
    the run itself can move.
    """
    repo = repo.resolve()
    error, data = load_anchor(repo, feature)
    if error is not None:
        return error
    assert data is not None

    bound = data.get("checkers")
    if not isinstance(bound, dict):
        return f"{TOKEN_UNREADABLE}: the anchor carries no checker digests."

    current = collect_checkers(repo)
    for rel, digest in sorted(bound.items()):
        now = current.get(rel)
        if now is None:
            return (
                f"{TOKEN_CHECKER}: {rel} was bound at arming and is now missing."
            )
        if now != digest:
            return (
                f"{TOKEN_CHECKER}: {rel} differs from the runtime bound at arming "
                f"(bound {digest[:12]}, now {now[:12]}). Committing a checker change "
                "during a run does not make it trusted."
            )
    for rel in sorted(current):
        if rel not in bound:
            return (
                f"{TOKEN_CHECKER}: {rel} appeared after arming and was never part of "
                "the verified runtime."
            )
    return None


def build_parser() -> PlumblineArgumentParser:
    parser = PlumblineArgumentParser(
        prog="plumbline-run-trust",
        description="Bind and read the immutable run-trust anchor for a feature run.",
    )
    parser.add_argument("command", choices=["arm", "disarm", "path", "verify", "show"])
    parser.add_argument("--repo", required=True, help="Repository root")
    parser.add_argument("--feature", required=True, help="Feature slug")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    repo = Path(args.repo)
    if not repo.is_dir():
        print(f"ERROR: not a directory: {repo}", file=sys.stderr)
        return EXIT_MALFORMED
    feature = args.feature
    if not feature or "/" in feature or "\\" in feature or feature in {".", ".."}:
        print(f"ERROR: malformed feature slug: {feature!r}", file=sys.stderr)
        return EXIT_MALFORMED

    if args.command == "arm":
        return arm(repo, feature)
    if args.command == "disarm":
        return disarm(repo, feature)
    if args.command == "path":
        print(anchor_path(repo.resolve(), feature))
        return EXIT_PASS
    if args.command == "show":
        error, data = load_anchor(repo, feature)
        if error is not None:
            print(f"ERROR: {error}", file=sys.stderr)
            return EXIT_VIOLATION
        print(json.dumps(data, indent=2))
        return EXIT_PASS

    for check in (verify_run_trust, verify_checkers):
        problem = check(repo, feature)
        if problem is not None:
            print(f"ERROR: {problem}", file=sys.stderr)
            return EXIT_VIOLATION
    print(f"run trust verified for feature '{feature}'")
    return EXIT_PASS


if __name__ == "__main__":
    raise SystemExit(main())
