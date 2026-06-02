#!/usr/bin/env python3
"""Plumbline version and update layer (stdlib-only)."""
from __future__ import annotations

import argparse
import datetime as _dt
import json
import os
import re
import shutil
import subprocess
import sys
import tarfile
import tempfile
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

SEMVER_RE = re.compile(r"(?<!\d)(\d+)\.(\d+)\.(\d+)(?:[-+][0-9A-Za-z.-]+)?(?!\d)")
GITHUB_REMOTE_RE = re.compile(r"github\.com[:/]+([^/]+)/([^/]+?)(?:\.git)?/?$")
HTTP_TIMEOUT = 30
USER_AGENT = "plumbline-update"
DEFAULT_REPO_SLUG = "DYAI2025/Plumbline"


class PlumblineError(RuntimeError):
    pass


def repo_root(start: Path | None = None) -> Path:
    here = (start or Path(__file__)).resolve()
    for parent in [here, *here.parents]:
        if (parent / "config" / "claude" / "install.sh").is_file():
            return parent
    return Path.cwd().resolve()


def read_version(root: Path) -> str:
    path = root / "VERSION"
    if not path.is_file():
        raise PlumblineError(f"VERSION not found at {path}")
    match = SEMVER_RE.search(path.read_text(encoding="utf-8"))
    if not match:
        raise PlumblineError(f"VERSION has no MAJOR.MINOR.PATCH value: {path}")
    return match.group(0)


def parse_semver(value: str) -> tuple[int, int, int]:
    value = value.strip().lstrip("v")
    match = SEMVER_RE.search(value)
    if not match:
        raise PlumblineError(f"not a SemVer value: {value}")
    return tuple(int(part) for part in match.groups())


def compare_versions(left: str, right: str) -> int:
    a = parse_semver(left)
    b = parse_semver(right)
    return (a > b) - (a < b)


def load_json(path: Path) -> Any:
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as exc:
        raise PlumblineError(f"invalid JSON in {path}: {exc}") from exc


def load_compatibility(root: Path) -> dict[str, Any]:
    path = root / "compatibility.json"
    if not path.is_file():
        raise PlumblineError(f"compatibility.json not found at {path}")
    data = load_json(path)
    if not isinstance(data, dict):
        raise PlumblineError("compatibility.json must be a JSON object")
    required = ["version", "schema", "verifyCommand", "frozenContracts"]
    missing = [key for key in required if key not in data]
    if missing:
        raise PlumblineError(f"compatibility.json missing: {', '.join(missing)}")
    parse_semver(str(data["version"]))
    if not isinstance(data["frozenContracts"], list) or not data["frozenContracts"]:
        raise PlumblineError("compatibility.json frozenContracts must be a non-empty list")
    return data


def latest_from_source(source: Path) -> tuple[str, str]:
    if source.is_dir():
        for name in ("latest-release.json", "release.json"):
            candidate = source / name
            if candidate.is_file():
                return latest_from_release_json(candidate)
        releases = source / "releases.json"
        if releases.is_file():
            data = load_json(releases)
            if not isinstance(data, list) or not data:
                raise PlumblineError("releases.json must contain at least one release")
            stable = [item for item in data if isinstance(item, dict) and not item.get("draft") and not item.get("prerelease")]
            item = stable[0] if stable else data[0]
            return release_item_version(item, str(releases))
        version_file = source / "VERSION"
        if version_file.is_file():
            return read_version(source), f"local VERSION ({source})"
    if source.is_file():
        if source.name.endswith(".json"):
            return latest_from_release_json(source)
        return read_version(source.parent), f"local VERSION ({source})"
    raise PlumblineError(f"no supported update source found at {source}")


def latest_from_release_json(path: Path) -> tuple[str, str]:
    return release_item_version(load_json(path), str(path))


def release_item_version(item: Any, label: str) -> tuple[str, str]:
    if not isinstance(item, dict):
        raise PlumblineError(f"release metadata must be a JSON object: {label}")
    raw = item.get("tag_name") or item.get("name") or item.get("version")
    if not raw:
        raise PlumblineError(f"release metadata missing tag_name/name/version: {label}")
    version = ".".join(str(part) for part in parse_semver(str(raw)))
    return version, label


def default_repo_slug(root: Path) -> str:
    """Derive owner/repo from the git origin remote, with env + literal fallback."""
    try:
        proc = subprocess.run(
            ["git", "-C", str(root), "remote", "get-url", "origin"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
        )
    except OSError:
        proc = None
    if proc is not None and proc.returncode == 0:
        match = GITHUB_REMOTE_RE.search(proc.stdout.strip())
        if match:
            return f"{match.group(1)}/{match.group(2)}"
    return os.environ.get("PLUMBLINE_REPO", DEFAULT_REPO_SLUG)


def github_api_base() -> str:
    return os.environ.get("PLUMBLINE_GITHUB_API", "https://api.github.com").rstrip("/")


def fetch_latest_release(slug: str) -> dict[str, Any]:
    """GET the latest release metadata from the GitHub API (no traceback on failure)."""
    url = f"{github_api_base()}/repos/{slug}/releases/latest"
    request = urllib.request.Request(
        url,
        headers={"User-Agent": USER_AGENT, "Accept": "application/vnd.github+json"},
    )
    try:
        with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT) as response:
            payload = response.read()
    except (urllib.error.URLError, OSError, ValueError) as exc:
        raise PlumblineError(f"could not reach GitHub release API: {exc}") from exc
    try:
        data = json.loads(payload.decode("utf-8"))
    except (json.JSONDecodeError, UnicodeDecodeError) as exc:
        raise PlumblineError(f"could not reach GitHub release API: invalid JSON ({exc})") from exc
    if not isinstance(data, dict):
        raise PlumblineError("could not reach GitHub release API: unexpected response shape")
    return data


def download_tarball(url: str, dest: Path) -> Path:
    request = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(request, timeout=HTTP_TIMEOUT) as response:
            dest.write_bytes(response.read())
    except (urllib.error.URLError, OSError, ValueError) as exc:
        raise PlumblineError(f"could not download release tarball: {exc}") from exc
    return dest


def _member_escapes(member: tarfile.TarInfo, into: Path) -> bool:
    """True if extracting this member would write/point outside `into`."""
    base = into.resolve()

    def outside(candidate: str) -> bool:
        if os.path.isabs(candidate) or candidate.startswith(("/", "\\")):
            return True
        target = (base / candidate).resolve()
        return target != base and base not in target.parents

    if outside(member.name):
        return True
    # Link targets are resolved relative to the link's own directory.
    if member.issym() or member.islnk():
        link_dir = os.path.dirname(member.name)
        link_target = os.path.join(link_dir, member.linkname) if not os.path.isabs(member.linkname) else member.linkname
        if outside(link_target):
            return True
    return False


def safe_extract_tarball(tar_path: Path, into: Path) -> Path:
    """Extract a tarball, refusing any member that escapes `into`. Returns the
    single top-level directory (GitHub tarballs ship exactly one)."""
    into.mkdir(parents=True, exist_ok=True)
    with tarfile.open(tar_path, "r:*") as tar:
        members = tar.getmembers()
        for member in members:
            if _member_escapes(member, into):
                raise PlumblineError(f"unsafe tarball member: {member.name}")
        tar.extractall(into)  # noqa: S202 - every member validated above
    tops = sorted({Path(m.name).parts[0] for m in members if m.name not in ("", ".")})
    if len(tops) == 1:
        return into / tops[0]
    return into


def resolve_payload_source(args: argparse.Namespace, root: Path) -> tuple[Path, Path | None]:
    """Return (payload_dir, tempdir_to_cleanup). tempdir is None for plain dirs."""
    if args.source:
        source = Path(args.source)
        if source.is_dir():
            return source.resolve(), None
        if source.is_file() and (source.name.endswith(".tar.gz") or source.name.endswith(".tgz")):
            tmp = Path(tempfile.mkdtemp(prefix="plumbline-update-"))
            try:
                return safe_extract_tarball(source.resolve(), tmp), tmp
            except Exception:
                shutil.rmtree(tmp, ignore_errors=True)
                raise
        raise PlumblineError(f"unsupported --source payload: {source}")
    # No --source: fetch the latest published release tarball over the network.
    slug = getattr(args, "repo", None) or default_repo_slug(root)
    release = fetch_latest_release(slug)
    url = release.get("tarball_url")
    if not url:
        raise PlumblineError("GitHub release metadata missing tarball_url")
    tmp = Path(tempfile.mkdtemp(prefix="plumbline-update-"))
    try:
        archive = download_tarball(str(url), tmp / "release.tar.gz")
        return safe_extract_tarball(archive, tmp / "extracted"), tmp
    except Exception:
        shutil.rmtree(tmp, ignore_errors=True)
        raise


def update_check(args: argparse.Namespace, root: Path) -> int:
    local = read_version(root)
    if args.source:
        source = Path(args.source)
        if source.is_file() and (source.name.endswith(".tar.gz") or source.name.endswith(".tgz")):
            payload, tmp = resolve_payload_source(args, root)
            try:
                latest = read_version(payload)
            finally:
                if tmp is not None:
                    shutil.rmtree(tmp, ignore_errors=True)
            source_label = f"tarball ({source})"
        else:
            latest, source_label = latest_from_source(source.resolve())
    else:
        slug = getattr(args, "repo", None) or default_repo_slug(root)
        release = fetch_latest_release(slug)
        latest, _ = release_item_version(release, f"github:{slug}")
        source_label = f"github:{slug}"
    cmp = compare_versions(local, latest)
    if cmp < 0:
        state = "update-available"
    elif cmp == 0:
        state = "up-to-date"
    else:
        state = "local-ahead"
    print(f"local: {local}")
    print(f"latest: {latest}")
    print(f"source: {source_label}")
    print(f"status: {state}")
    return 0


def ignore_update_artifacts(_dir: str, names: list[str]) -> set[str]:
    return {name for name in names if name in {".git", ".plumbline", "__pycache__"}}


def snapshot_target(target: Path) -> Path:
    stamp = _dt.datetime.now(_dt.UTC).strftime("%Y%m%d%H%M%S")
    base = target / ".plumbline" / "update" / "snapshots"
    base.mkdir(parents=True, exist_ok=True)
    snapshot = base / stamp
    suffix = 0
    while snapshot.exists():
        suffix += 1
        snapshot = base / f"{stamp}-{suffix}"
    shutil.copytree(target, snapshot, ignore=ignore_update_artifacts)
    return snapshot


def copy_update_payload(source: Path, target: Path) -> None:
    if not source.is_dir():
        raise PlumblineError("plumbline update requires --source to be a directory in non-network mode")
    for item in source.iterdir():
        if item.name in {".git", ".plumbline", "latest-release.json", "release.json", "releases.json"}:
            continue
        destination = target / item.name
        if destination.exists() or destination.is_symlink():
            if destination.is_dir() and not destination.is_symlink():
                shutil.rmtree(destination)
            else:
                destination.unlink()
        if item.is_dir():
            shutil.copytree(item, destination, symlinks=True, ignore=ignore_update_artifacts)
        else:
            shutil.copy2(item, destination)


def restore_snapshot(snapshot: Path, target: Path) -> None:
    keep = target / ".plumbline"
    for item in list(target.iterdir()):
        if item == keep:
            continue
        if item.is_dir() and not item.is_symlink():
            shutil.rmtree(item)
        else:
            item.unlink()
    for item in snapshot.iterdir():
        destination = target / item.name
        if item.is_dir() and not item.is_symlink():
            shutil.copytree(item, destination, symlinks=True, ignore=ignore_update_artifacts)
        else:
            shutil.copy2(item, destination)


def run_command(command: str, cwd: Path) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=str(cwd), shell=True, text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT)


def run_migrations(target: Path, previous: str, new: str) -> None:
    state = target / ".plumbline" / "update" / "migrations.log"
    state.parent.mkdir(parents=True, exist_ok=True)
    with state.open("a", encoding="utf-8") as fh:
        fh.write(f"{_dt.datetime.now(_dt.UTC).isoformat().replace('+00:00', '')}Z {previous} -> {new}: no migrations declared\n")


def update_apply(args: argparse.Namespace, root: Path) -> int:
    target = Path(args.target).resolve() if args.target else root
    source, tmp = resolve_payload_source(args, root)
    try:
        return _apply_from_source(args, target, source)
    finally:
        if tmp is not None:
            shutil.rmtree(tmp, ignore_errors=True)


def _apply_from_source(args: argparse.Namespace, target: Path, source: Path) -> int:
    previous = read_version(target)
    latest, _ = latest_from_source(source)
    if compare_versions(previous, latest) >= 0 and not args.force:
        print(f"status: up-to-date ({previous})")
        return 0
    major_delta = parse_semver(latest)[0] != parse_semver(previous)[0]
    if major_delta and not args.yes_major:
        raise PlumblineError("MAJOR update requires explicit --yes-major")

    snapshot = snapshot_target(target)
    print(f"snapshot: {snapshot}")
    try:
        copy_update_payload(source, target)
        installer = target / "config" / "claude" / "install.sh"
        if installer.is_file():
            result = run_command("bash config/claude/install.sh --dry-run", target)
            print(result.stdout, end="")
            if result.returncode != 0:
                raise PlumblineError("install.sh dry-run failed")
        new = read_version(target)
        run_migrations(target, previous, new)
        verify = args.verify_cmd or str(load_compatibility(target).get("verifyCommand", "bash config/claude/tests/run_all.sh"))
        result = run_command(verify, target)
        print(result.stdout, end="")
        if result.returncode != 0:
            raise PlumblineError(f"verification failed: {verify}")
        marker = target / ".plumbline" / "update" / "last-success.json"
        marker.parent.mkdir(parents=True, exist_ok=True)
        marker.write_text(json.dumps({"previous": previous, "version": new, "snapshot": str(snapshot)}, indent=2) + "\n", encoding="utf-8")
        print(f"status: changed and verified ({previous} -> {new})")
        return 0
    except Exception:
        restore_snapshot(snapshot, target)
        print(f"status: reverted to snapshot {snapshot}")
        raise


def rollback(args: argparse.Namespace, root: Path) -> int:
    target = Path(args.target).resolve() if args.target else root
    snapshot = Path(args.snapshot).resolve() if args.snapshot else None
    if snapshot is None:
        base = target / ".plumbline" / "update" / "snapshots"
        snapshots = sorted([p for p in base.iterdir() if p.is_dir()]) if base.is_dir() else []
        if not snapshots:
            raise PlumblineError("no rollback snapshots found")
        snapshot = snapshots[-1]
    restore_snapshot(snapshot, target)
    print(f"status: rolled back to {snapshot}")
    return 0


def doctor(_args: argparse.Namespace, root: Path) -> int:
    version = read_version(root)
    compat = load_compatibility(root)
    checks = [
        ("install.sh", (root / "config" / "claude" / "install.sh").is_file()),
        ("VERSION", (root / "VERSION").is_file()),
        ("run_all.sh", (root / "config" / "claude" / "tests" / "run_all.sh").is_file()),
        ("compatibility.json", compat.get("version") == version),
    ]
    for name, ok in checks:
        print(f"{name}: {'ok' if ok else 'fail'}")
    print(f"version: {version}")
    return 0 if all(ok for _, ok in checks) else 1


def honest_status(_args: argparse.Namespace, root: Path) -> int:
    print("changed, not yet verified")
    print(f"version: {read_version(root)}")
    print("verification: run bash config/claude/tests/run_all.sh before claiming changed and verified")
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(prog="plumbline")
    parser.add_argument("--root", help="repository root (default: auto-detect)")
    sub = parser.add_subparsers(dest="command", required=True)
    sub.add_parser("version")
    sub.add_parser("doctor")
    sub.add_parser("honest-status")
    update = sub.add_parser("update")
    update.add_argument("--check", action="store_true", help="only check for latest release")
    update.add_argument("--source", help="local release metadata or payload source (dir or .tar.gz)")
    update.add_argument("--repo", help="GitHub OWNER/REPO to fetch releases from (default: origin remote)")
    update.add_argument("--target", help="target checkout for apply/rollback tests")
    update.add_argument("--verify-cmd", help="verification command after update")
    update.add_argument("--force", action="store_true", help="apply even when versions compare equal")
    update.add_argument("--yes-major", action="store_true", help="allow a MAJOR update")
    rollback_parser = sub.add_parser("rollback")
    rollback_parser.add_argument("--target", help="target checkout")
    rollback_parser.add_argument("--snapshot", help="specific snapshot path")
    # `install` forwards every unrecognized flag (including --help, --dry-run,
    # --copy, --force, --no-*) verbatim to install.sh. add_help=False keeps the
    # subparser from swallowing --help so the installer prints its own usage.
    sub.add_parser(
        "install",
        help="run config/claude/install.sh, forwarding any extra flags",
        add_help=False,
    )
    return parser


def cmd_install(args: argparse.Namespace, root: Path, extra: list[str]) -> int:
    installer = root / "config" / "claude" / "install.sh"
    if not installer.is_file():
        raise PlumblineError(f"install.sh not found at {installer}")
    result = subprocess.run(["bash", str(installer), *extra], cwd=str(root))
    return result.returncode


def main(argv: list[str] | None = None) -> int:
    parser = build_parser()
    # `install` forwards arbitrary flags to install.sh, so tolerate unknown args
    # only for that subcommand; every other command must reject them strictly.
    args, extra = parser.parse_known_args(argv)
    if extra and args.command != "install":
        parser.error(f"unrecognized arguments: {' '.join(extra)}")
    root = Path(args.root).resolve() if args.root else repo_root()
    try:
        if args.command == "version":
            print(read_version(root)); return 0
        if args.command == "doctor":
            return doctor(args, root)
        if args.command == "honest-status":
            return honest_status(args, root)
        if args.command == "update":
            if args.check:
                return update_check(args, root)
            return update_apply(args, root)
        if args.command == "rollback":
            return rollback(args, root)
        if args.command == "install":
            return cmd_install(args, root, extra)
        parser.error("unknown command")
    except PlumblineError as exc:
        print(f"plumbline: {exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
