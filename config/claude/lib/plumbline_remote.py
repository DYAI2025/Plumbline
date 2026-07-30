#!/usr/bin/env python3
"""Plumbline remote-state watcher (PLUM-14).

Plumbline governs local agent and hook paths. It had no view of the remote at all:
the run ledger records gates and artifact hashes, so a human gate whose artifact
changed is caught -- but a pull request that was merged, force-pushed or re-pointed
UNDER an active run left no trace. The pilot: PR #26 was a draft, explicitly not
cleared for merge or review, and was merged through GitHub anyway; Plumbline only
noticed afterwards, by hand.

This module records the remote state an active run expects, and refuses to continue
once that state has changed:

    snapshot   record PR number, head/base refs, their SHAs and the draft state
    verify     compare the live remote against the snapshot; classify every change
    publish-status  optionally publish the run's no-merge/review gate as a check

Boundary honesty. The git-side facts -- head SHA, base SHA, merge containment,
force-push -- are read from real git and need no seam. Draft/merged metadata belongs
to the forge, so it has a TEST seam (`--pr-state-file`) *and* a paired real entrypoint
(`gh pr view --json`) that is gated OFF by default behind `PLUMBLINE_REMOTE_LIVE=1`.
Neither seam is allowed to be silently absent: with no injected file and no live gate,
`verify` REFUSES rather than verifying the git half and calling it done.

Exit codes: 0 pass, 2 missing/unavailable input, 3 remote state changed (blocking),
4 malformed input.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

EXIT_PASS = 0
EXIT_MISSING = 2
EXIT_CHANGED = 3
EXIT_MALFORMED = 4

CLASS_CHANGED = "REMOTE_STATE_CHANGED"
LIVE_GATE = "PLUMBLINE_REMOTE_LIVE"
CHECK_CONTEXT = "plumbline/no-merge-gate"
STATE_SCHEMA = 1

# The forge fields the watcher needs. Kept as one list so the live invocation and the
# injected seam cannot drift apart.
PR_FIELDS = ("number", "isDraft", "state", "baseRefName", "headRefName", "mergedBy")


def _git(repo: Path, *args: str) -> subprocess.CompletedProcess:
    return subprocess.run(
        ["git", "-C", str(repo), *args], capture_output=True, text=True, check=False
    )


def _is_git_repo(repo: Path) -> bool:
    return _git(repo, "rev-parse", "--git-dir").returncode == 0


def _rev(repo: Path, ref: str) -> str | None:
    result = _git(repo, "rev-parse", "--verify", f"{ref}^{{commit}}")
    if result.returncode != 0:
        return None
    sha = result.stdout.strip()
    return sha or None


def _resolve_remote_ref(repo: Path, ref: str) -> tuple[str | None, str | None]:
    """Resolve a branch name to its remote-tracking SHA. Returns (refname, sha)."""
    for candidate in (f"refs/remotes/origin/{ref}", ref, f"refs/heads/{ref}"):
        sha = _rev(repo, candidate)
        if sha:
            return candidate, sha
    return None, None


def _contains(repo: Path, container: str, commit: str) -> bool:
    """True when `commit` is an ancestor of (contained in) `container`."""
    result = _git(repo, "merge-base", "--is-ancestor", commit, container)
    return result.returncode == 0


def state_path(repo: Path, feature: str) -> Path:
    return repo / "docs" / "context" / f"{feature}.remote-state.json"


def _load_injected_pr_state(path: Path) -> tuple[int, dict]:
    try:
        raw = path.read_text(encoding="utf-8")
    except FileNotFoundError:
        print(f"ERROR: missing injected PR state file: {path}", file=sys.stderr)
        return EXIT_MISSING, {}
    except UnicodeDecodeError:
        print(f"ERROR: injected PR state is not UTF-8 text: {path}", file=sys.stderr)
        return EXIT_MALFORMED, {}
    try:
        data = json.loads(raw)
    except json.JSONDecodeError as exc:
        print(
            f"ERROR: malformed injected PR state {path}: invalid JSON "
            f"({exc.msg} at line {exc.lineno})",
            file=sys.stderr,
        )
        return EXIT_MALFORMED, {}
    if not isinstance(data, dict):
        print(
            f"ERROR: malformed injected PR state {path}: top level must be an object",
            file=sys.stderr,
        )
        return EXIT_MALFORMED, {}
    return EXIT_PASS, data


def _fetch_live_pr_state(repo: Path, pr: int) -> tuple[int, dict]:
    """The REAL forge entrypoint. Gated OFF by default by the caller."""
    tool = shutil.which("gh")
    if not tool:
        print(
            f"ERROR: {LIVE_GATE}=1 but the 'gh' CLI is not on PATH; the forge half of "
            "the remote state cannot be read. Install gh, or inject the state with "
            "--pr-state-file for an offline check.",
            file=sys.stderr,
        )
        return EXIT_MISSING, {}
    result = subprocess.run(
        [
            tool,
            "pr",
            "view",
            str(pr),
            "--json",
            ",".join(PR_FIELDS),
        ],
        cwd=str(repo),
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip().splitlines()
        first = detail[0] if detail else f"exit {result.returncode}"
        print(
            f"ERROR: 'gh pr view {pr}' failed, so the forge state is UNKNOWN: {first}. "
            "Refusing to report the remote as verified from the git half alone.",
            file=sys.stderr,
        )
        return EXIT_MISSING, {}
    try:
        data = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        print(
            f"ERROR: 'gh pr view {pr}' returned unparseable JSON ({exc.msg})",
            file=sys.stderr,
        )
        return EXIT_MALFORMED, {}
    if not isinstance(data, dict):
        print(f"ERROR: 'gh pr view {pr}' returned a non-object", file=sys.stderr)
        return EXIT_MALFORMED, {}
    return EXIT_PASS, data


def _pr_state(
    repo: Path, pr: int | None, pr_state_file: str | None
) -> tuple[int, dict, str]:
    """Resolve the forge half of the state. Returns (status, data, source)."""
    if pr_state_file:
        status, data = _load_injected_pr_state(Path(pr_state_file))
        return status, data, "inject"
    if os.environ.get(LIVE_GATE) == "1":
        if pr is None:
            print(
                "ERROR: a live remote check needs the PR number; none recorded and "
                "none passed with --pr",
                file=sys.stderr,
            )
            return EXIT_MISSING, {}, "live"
        status, data = _fetch_live_pr_state(repo, pr)
        return status, data, "live"
    print(
        f"ERROR: the forge half of the remote state is unavailable: {LIVE_GATE} is not "
        "set (default OFF) and no --pr-state-file was injected. Draft and merge "
        "metadata live on the forge, so this check REFUSES rather than verifying only "
        f"the git half. Set {LIVE_GATE}=1 for a real check, or pass --pr-state-file.",
        file=sys.stderr,
    )
    return EXIT_MISSING, {}, "none"


def _normalize(data: dict) -> dict:
    """Normalize forge fields to the watcher's vocabulary."""
    merged_by = data.get("mergedBy")
    if isinstance(merged_by, dict):
        merged_by = merged_by.get("login")
    actor = str(merged_by).strip() if merged_by else ""
    return {
        "pr": data.get("number"),
        "is_draft": bool(data.get("isDraft")),
        "pr_state": str(data.get("state") or "").strip().upper(),
        "base_ref": str(data.get("baseRefName") or "").strip(),
        "head_ref": str(data.get("headRefName") or "").strip(),
        "merged_by": actor,
        "merge_mechanism": str(data.get("mergeMechanism") or "").strip(),
    }


def cmd_snapshot(
    repo: Path,
    feature: str,
    pr: int | None,
    base: str | None,
    pr_state_file: str | None,
) -> int:
    if not _is_git_repo(repo):
        print(f"ERROR: not a git repository: {repo}", file=sys.stderr)
        return EXIT_MISSING

    status, raw, source = _pr_state(repo, pr, pr_state_file)
    if status != EXIT_PASS:
        return status
    forge = _normalize(raw)

    base_ref = base or forge["base_ref"]
    if not base_ref:
        print(
            "ERROR: no base branch recorded: pass --base, or supply a PR state that "
            "names baseRefName",
            file=sys.stderr,
        )
        return EXIT_MISSING
    head_ref = forge["head_ref"] or _git(
        repo, "rev-parse", "--abbrev-ref", "HEAD"
    ).stdout.strip()

    base_name, base_sha = _resolve_remote_ref(repo, base_ref)
    if not base_sha:
        print(
            f"ERROR: cannot resolve the base ref '{base_ref}' to a commit; refusing to "
            "snapshot an unverifiable baseline",
            file=sys.stderr,
        )
        return EXIT_MISSING
    head_name, head_sha = _resolve_remote_ref(repo, head_ref)
    if not head_sha:
        print(
            f"ERROR: cannot resolve the head ref '{head_ref}' to a commit",
            file=sys.stderr,
        )
        return EXIT_MISSING

    # Record whether the head is ALREADY in the base. `verify` must detect the
    # TRANSITION into a merged state, not the state itself: after a merge has been
    # reviewed and re-snapshotted the head is legitimately contained in the base, and
    # a state-based check could never clear (it would block the run forever).
    record = {
        "schema": STATE_SCHEMA,
        "feature": feature,
        "pr": pr if pr is not None else forge["pr"],
        "base_ref": base_ref,
        "base_tracking_ref": base_name,
        "base_sha": base_sha,
        "head_ref": head_ref,
        "head_tracking_ref": head_name,
        "head_sha": head_sha,
        "head_in_base": _contains(repo, base_sha, head_sha),
        "is_draft": forge["is_draft"],
        "pr_state": forge["pr_state"],
        "source": source,
    }
    target = state_path(repo, feature)
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text(json.dumps(record, indent=2) + "\n", encoding="utf-8")
    print(
        f"snapshot: feature={feature} pr={record['pr']} base={base_ref}@{base_sha[:12]} "
        f"head={head_ref}@{head_sha[:12]} draft={record['is_draft']} source={source}"
    )
    print(f"wrote {target}")
    return EXIT_PASS


def _load_snapshot(repo: Path, feature: str) -> tuple[int, dict]:
    path = state_path(repo, feature)
    if not path.exists():
        print(
            f"ERROR: no recorded remote state for feature '{feature}' "
            f"({path} is absent). Run `plumbline-remote-watch snapshot` at the start "
            "of the run; without a recorded expectation a change cannot be detected, "
            "so this fails closed rather than passing by absence.",
            file=sys.stderr,
        )
        return EXIT_MISSING, {}
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as exc:
        detail = getattr(exc, "msg", str(exc))
        print(f"ERROR: malformed remote state {path}: {detail}", file=sys.stderr)
        return EXIT_MALFORMED, {}
    if not isinstance(data, dict) or data.get("schema") != STATE_SCHEMA:
        print(
            f"ERROR: malformed remote state {path}: expected a schema-"
            f"{STATE_SCHEMA} object",
            file=sys.stderr,
        )
        return EXIT_MALFORMED, {}
    return EXIT_PASS, data


def cmd_verify(repo: Path, feature: str, pr_state_file: str | None) -> int:
    if not _is_git_repo(repo):
        print(f"ERROR: not a git repository: {repo}", file=sys.stderr)
        return EXIT_MISSING

    status, snap = _load_snapshot(repo, feature)
    if status != EXIT_PASS:
        return status

    status, raw, source = _pr_state(repo, snap.get("pr"), pr_state_file)
    if status != EXIT_PASS:
        return status
    forge = _normalize(raw)

    changes: list[tuple[str, str, str]] = []  # (kind, source, detail)

    # --- git ground truth ----------------------------------------------------
    base_name, base_sha = _resolve_remote_ref(repo, snap["base_ref"])
    head_name, head_sha = _resolve_remote_ref(repo, snap["head_ref"])

    recorded_head = snap["head_sha"]
    if head_sha is None:
        changes.append(
            (
                "head-gone",
                "git",
                f"the head ref '{snap['head_ref']}' no longer resolves; "
                f"recorded_head={recorded_head[:12]}",
            )
        )
    elif head_sha != recorded_head:
        # A fast-forward (recorded head still an ancestor) is ordinary progress; a
        # rewritten history is a force-push.
        if _contains(repo, head_sha, recorded_head):
            print(
                f"note: the head advanced normally "
                f"({recorded_head[:12]} -> {head_sha[:12]}); recorded head is still "
                "an ancestor"
            )
        else:
            changes.append(
                (
                    "force-push",
                    "git",
                    f"the head ref '{snap['head_ref']}' was rewritten: "
                    f"recorded_head={recorded_head[:12]} is no longer an ancestor of "
                    f"current_head={head_sha[:12]}",
                )
            )

    if base_sha is None:
        changes.append(
            (
                "base-gone",
                "git",
                f"the base ref '{snap['base_ref']}' no longer resolves",
            )
        )
    else:
        # Merge is detected from containment, independent of forge metadata: the head
        # commit the run started from is now part of the base branch. Only the
        # TRANSITION counts -- a snapshot taken after a reviewed merge already records
        # containment, and re-reporting it would block the run forever.
        if (
            recorded_head
            and not snap.get("head_in_base", False)
            and _contains(repo, base_sha, recorded_head)
        ):
            changes.append(
                (
                    "merged",
                    "git",
                    f"the recorded head {recorded_head[:12]} is now contained in the "
                    f"base ref '{snap['base_ref']}' ({base_sha[:12]}): the branch was "
                    "merged into the base under an active run",
                )
            )
        elif base_sha != snap["base_sha"]:
            changes.append(
                (
                    "base-advanced",
                    "git",
                    f"the base ref '{snap['base_ref']}' moved "
                    f"{snap['base_sha'][:12]} -> {base_sha[:12]} during the run, so "
                    "the scope baseline and CI surface are no longer the ones the run "
                    "was evaluated against",
                )
            )

    # --- forge state ---------------------------------------------------------
    if forge["base_ref"] and forge["base_ref"] != snap["base_ref"]:
        changes.append(
            (
                "base-changed",
                source,
                f"the pull request was re-pointed from base '{snap['base_ref']}' to "
                f"'{forge['base_ref']}'",
            )
        )
    if forge["is_draft"] != bool(snap.get("is_draft")):
        changes.append(
            (
                "draft-changed",
                source,
                f"the draft flag changed: recorded is_draft={snap.get('is_draft')}, "
                f"remote reports is_draft={forge['is_draft']}",
            )
        )
    if forge["pr_state"] and forge["pr_state"] != str(snap.get("pr_state") or ""):
        kind = "merged" if forge["pr_state"] == "MERGED" else "pr-state-changed"
        if not any(existing == "merged" for existing, _s, _d in changes) or kind != "merged":
            changes.append(
                (
                    kind,
                    source,
                    f"the pull request state changed: recorded "
                    f"{snap.get('pr_state') or '(none)'} -> remote {forge['pr_state']}",
                )
            )

    if not changes:
        print(
            f"remote state verified for feature '{feature}': pr={snap.get('pr')} "
            f"base={snap['base_ref']}@{(base_sha or '')[:12]} "
            f"head={snap['head_ref']}@{(head_sha or '')[:12]} "
            f"draft={forge['is_draft']} source={source}"
        )
        return EXIT_PASS

    for kind, src, detail in changes:
        print(f"{CLASS_CHANGED}: kind={kind} source={src} {detail}", file=sys.stderr)

    # AC-5: name the account and mechanism the remote reports, and say plainly that
    # the actor is not interpreted. Whether a person or an automation acted is not
    # observable from this data, so it is not claimed.
    actor = forge["merged_by"] or "(not reported)"
    mechanism = forge["merge_mechanism"] or "(not reported)"
    print(
        f"audit: account={actor} mechanism={mechanism} "
        f"(both as reported by the remote; this watcher does not infer whether a "
        f"person or a program performed the action)",
        file=sys.stderr,
    )
    print(
        f"BLOCKED: re-evaluate the run against the new remote state, then record the "
        f"reviewed state with `plumbline-remote-watch snapshot --repo {repo} "
        f"--feature {feature}`. Until then every further write is unsafe: the base, "
        "the scope baseline and CI may no longer be the ones this run was judged "
        "against.",
        file=sys.stderr,
    )
    return EXIT_CHANGED


def cmd_publish_status(
    repo: Path, feature: str, state: str, dry_run: bool
) -> int:
    """Optionally publish the run's no-merge/review gate as a forge check (AC-4)."""
    if not _is_git_repo(repo):
        print(f"ERROR: not a git repository: {repo}", file=sys.stderr)
        return EXIT_MISSING
    status, snap = _load_snapshot(repo, feature)
    if status != EXIT_PASS:
        return status

    sha = snap.get("head_sha") or ""
    description = {
        "pending": "Plumbline run in progress: not cleared for merge",
        "success": "Plumbline run accepted: merge gate cleared",
        "failure": "Plumbline run blocked: do not merge",
    }[state]

    if dry_run:
        print(
            f"would publish check context={CHECK_CONTEXT} state={state} "
            f"sha={sha[:12]} description={description!r}"
        )
        print(
            "dry-run only: no request was made and no boundary was crossed."
        )
        return EXIT_PASS

    if os.environ.get(LIVE_GATE) != "1":
        print(
            f"ERROR: publishing a check status crosses the forge boundary, so it is "
            f"gated OFF by default. Set {LIVE_GATE}=1 to publish, or use --dry-run to "
            "see the exact request.",
            file=sys.stderr,
        )
        return EXIT_MISSING

    tool = shutil.which("gh")
    if not tool:
        print(
            f"ERROR: {LIVE_GATE}=1 but the 'gh' CLI is not on PATH; cannot publish the "
            "check status",
            file=sys.stderr,
        )
        return EXIT_MISSING
    result = subprocess.run(
        [
            tool,
            "api",
            "-X",
            "POST",
            f"repos/{{owner}}/{{repo}}/statuses/{sha}",
            "-f",
            f"state={state}",
            "-f",
            f"context={CHECK_CONTEXT}",
            "-f",
            f"description={description}",
        ],
        cwd=str(repo),
        capture_output=True,
        text=True,
        check=False,
    )
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip().splitlines()
        first = detail[0] if detail else f"exit {result.returncode}"
        print(f"ERROR: publishing the check status failed: {first}", file=sys.stderr)
        return EXIT_MISSING
    print(f"published check context={CHECK_CONTEXT} state={state} sha={sha[:12]}")
    return EXIT_PASS


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Record and verify the remote PR/branch state an active "
        "Plumbline run depends on.",
    )
    sub = parser.add_subparsers(dest="command", required=True)

    snap = sub.add_parser("snapshot", help="record the expected remote state")
    snap.add_argument("--repo", required=True)
    snap.add_argument("--feature", required=True)
    snap.add_argument("--pr", type=int, help="pull request number")
    snap.add_argument("--base", help="expected base branch")
    snap.add_argument(
        "--pr-state-file",
        help="offline/test seam: read the forge PR state from this JSON file "
        "instead of calling the forge",
    )

    ver = sub.add_parser("verify", help="compare the remote against the snapshot")
    ver.add_argument("--repo", required=True)
    ver.add_argument("--feature", required=True)
    ver.add_argument("--pr-state-file", help="offline/test seam (see snapshot)")

    pub = sub.add_parser(
        "publish-status", help="publish the run's merge gate as a forge check"
    )
    pub.add_argument("--repo", required=True)
    pub.add_argument("--feature", required=True)
    pub.add_argument(
        "--state", required=True, choices=("pending", "success", "failure")
    )
    pub.add_argument(
        "--dry-run",
        action="store_true",
        help="print the request without crossing the boundary",
    )
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    repo = Path(args.repo)
    repo = repo.resolve() if repo.exists() else repo
    if args.command == "snapshot":
        return cmd_snapshot(repo, args.feature, args.pr, args.base, args.pr_state_file)
    if args.command == "verify":
        return cmd_verify(repo, args.feature, args.pr_state_file)
    return cmd_publish_status(repo, args.feature, args.state, args.dry_run)


if __name__ == "__main__":
    raise SystemExit(main())
