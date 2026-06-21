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
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

SEMVER_RE = re.compile(r"(?<!\d)(\d+)\.(\d+)\.(\d+)(?:[-+][0-9A-Za-z.-]+)?(?!\d)")
GITHUB_REMOTE_RE = re.compile(r"github\.com[:/]+([^/]+)/([^/]+?)(?:\.git)?/?$")
HTTP_TIMEOUT = 30
USER_AGENT = "plumbline-update"
DEFAULT_REPO_SLUG = "DYAI2025/Plumbline"
# Only ever fetch over http(s); a malicious/compromised release pointing
# tarball_url at file://, ftp://, gopher:// etc. must be refused, not opened.
ALLOWED_URL_SCHEMES = ("http", "https")
# Self-update payloads for this repo are small; cap to refuse decompression
# bombs and runaway downloads (fail-closed, generous headroom).
MAX_DOWNLOAD_BYTES = 64 * 1024 * 1024
MAX_EXTRACT_BYTES = 256 * 1024 * 1024
# The fixed, repo-pinned verification command. Plumbline NEVER executes a
# verifyCommand string lifted from a (possibly untrusted) downloaded payload;
# the operator's --verify-cmd or this fixed command runs instead.
DEFAULT_VERIFY = "bash config/claude/tests/run_all.sh"


class PlumblineError(RuntimeError):
    pass


# Filename of the install-identity anchor written by install.sh into $CLAUDE_HOME.
# When the CLI runs as the INSTALLED copy (its lib lives under a Claude home that
# carries this anchor), the anchor — not the current working directory's checkout
# — is the authoritative source of "which Plumbline is this and where do its
# updates come from". This is what makes `plumbline version` / `update --check`
# cwd-independent (REQ-PUR-02): a user running the installed CLI from /tmp or from
# an unrelated git repo must get the installed Plumbline's identity, never the
# cwd's VERSION or git origin.
INSTALL_ANCHOR_NAME = ".plumbline-install.json"


def repo_root(start: Path | None = None) -> Path:
    here = (start or Path(__file__)).resolve()
    for parent in [here, *here.parents]:
        if (parent / "config" / "claude" / "install.sh").is_file():
            return parent
    return Path.cwd().resolve()


def resolve_install_identity() -> dict[str, Any] | None:
    """Locate and read the install-identity anchor for the INSTALLED copy.

    Walk up from this module's own location looking for `.plumbline-install.json`
    beside the installed `lib/` (i.e. at the Claude-home root). Returns the parsed
    anchor mapping when found and well-formed, else None.

    Returns None for the dev checkout (the source tree has no anchor — its lib is
    symlinked/edited in place and resolves its identity from the source VERSION /
    git origin via `repo_root`), and None for an installed copy whose anchor is
    absent (an OLD install made before this anchor existed) — callers fall back to
    safe defaults and advise re-running install.sh, never to a wrong cwd pick.
    """
    here = Path(__file__).resolve()
    for parent in here.parents:
        anchor = parent / INSTALL_ANCHOR_NAME
        if anchor.is_file():
            try:
                data = json.loads(anchor.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                return None
            if isinstance(data, dict):
                return data
            return None
    return None


def _is_installed_copy() -> bool:
    """True when this module runs from an installed tree (NOT the dev checkout).

    The dev checkout's lib sits under `config/claude/lib` next to `install.sh`;
    `repo_root` walks up to find that `install.sh`. An installed copy's lib has no
    such ancestor. We use the absence of a source `install.sh` ancestor as the
    "installed" signal so the anchor-precedence rules below apply only off-tree.
    """
    here = Path(__file__).resolve()
    for parent in here.parents:
        if (parent / "config" / "claude" / "install.sh").is_file():
            return False
    return True


def read_version(root: Path, explicit_root: bool = True) -> str:
    # Installed-copy precedence (REQ-PUR-02): with NO explicit --root, prefer the
    # install-identity anchor's captured version over the cwd's VERSION. With an
    # explicit --root (dev/test use), keep today's behavior and read root/VERSION.
    if not explicit_root:
        anchor = resolve_install_identity()
        if anchor is not None:
            version = anchor.get("version")
            if isinstance(version, str) and SEMVER_RE.search(version):
                return SEMVER_RE.search(version).group(0)  # type: ignore[union-attr]
            # Anchor present but its version is missing/unusable. On the INSTALLED
            # copy this must FAIL LOUD exactly like the no-anchor case: silently
            # reading the cwd's VERSION here is the cwd-dependence bug (the
            # installed CLI would report whatever VERSION the current directory
            # happens to carry). Only the dev/--root path may read root/VERSION.
            if _is_installed_copy():
                raise PlumblineError(
                    "install-identity anchor has no usable version for the "
                    "installed plumbline "
                    "(re-run install.sh to write the identity anchor)"
                )
            # Not an installed copy (dev checkout with a stray anchor): fall
            # through to root/VERSION as before.
        elif _is_installed_copy():
            # Installed, but no anchor (old install): never silently read the
            # cwd's VERSION as if it were ours — that is the exact cwd-dependence
            # bug. Fail with a clear, actionable message.
            raise PlumblineError(
                "no install-identity anchor found for the installed plumbline "
                "(re-run install.sh to write the identity anchor)"
            )
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


def default_repo_slug(root: Path, explicit_root: bool = True) -> str:
    """Derive owner/repo for update fetches.

    Installed-copy precedence (REQ-PUR-02): with NO explicit --root, prefer the
    install-identity anchor's `repo_slug` so an installed CLI run from a FOREIGN
    git repo queries the installed Plumbline's upstream (DYAI2025/Plumbline by
    default), never the foreign repo's origin. With an explicit --root, or when
    no anchor applies, fall back to the git-origin / $PLUMBLINE_REPO / literal
    chain below (dev checkout + back-compat).
    """
    if not explicit_root:
        anchor = resolve_install_identity()
        if anchor is not None:
            slug = anchor.get("repo_slug")
            if isinstance(slug, str) and "/" in slug:
                return slug
            # Anchor present but its slug is missing/unusable. On the INSTALLED
            # copy, never trust the foreign cwd's git origin as our upstream:
            # return the literal default (PLUMBLINE_REPO override honoured) so an
            # installed CLI run from a foreign repo still targets the installed
            # Plumbline's upstream. Only the dev path may consult git origin.
            if _is_installed_copy():
                return os.environ.get("PLUMBLINE_REPO", DEFAULT_REPO_SLUG)
            # Not an installed copy (dev checkout with a stray anchor): fall
            # through to the git-origin / env / literal chain below.
        elif _is_installed_copy():
            # Installed, no anchor (old install): never trust the foreign cwd's
            # origin as our upstream. Use the literal default and (caller-side)
            # advise re-running install.sh.
            return os.environ.get("PLUMBLINE_REPO", DEFAULT_REPO_SLUG)
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


def require_safe_url(url: str) -> str:
    """Refuse any URL that is not http(s) (blocks file://, ftp://, etc.)."""
    scheme = urllib.parse.urlparse(url).scheme.lower()
    if scheme not in ALLOWED_URL_SCHEMES:
        raise PlumblineError(f"refusing non-http(s) URL: {url}")
    return url


class _SafeRedirectHandler(urllib.request.HTTPRedirectHandler):
    """Re-validate the scheme on every redirect hop. urllib's own 30x allowlist
    permits ftp:// targets; this makes `require_safe_url` authoritative across
    redirects, not just the first URL."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # type: ignore[override]
        require_safe_url(newurl)
        return super().redirect_request(req, fp, code, msg, headers, newurl)


# Opener that follows redirects only to http(s) targets.
_SAFE_OPENER = urllib.request.build_opener(_SafeRedirectHandler)


def fetch_latest_release(slug: str) -> dict[str, Any]:
    """GET the latest release metadata from the GitHub API (no traceback on failure)."""
    url = require_safe_url(f"{github_api_base()}/repos/{slug}/releases/latest")
    request = urllib.request.Request(
        url,
        headers={"User-Agent": USER_AGENT, "Accept": "application/vnd.github+json"},
    )
    try:
        with _SAFE_OPENER.open(request, timeout=HTTP_TIMEOUT) as response:
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
    request = urllib.request.Request(require_safe_url(url), headers={"User-Agent": USER_AGENT})
    try:
        with _SAFE_OPENER.open(request, timeout=HTTP_TIMEOUT) as response:
            data = response.read(MAX_DOWNLOAD_BYTES + 1)
    except (urllib.error.URLError, OSError, ValueError) as exc:
        raise PlumblineError(f"could not download release tarball: {exc}") from exc
    if len(data) > MAX_DOWNLOAD_BYTES:
        raise PlumblineError(f"release tarball exceeds {MAX_DOWNLOAD_BYTES} byte limit")
    dest.write_bytes(data)
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


def _is_apple_double(name: str) -> bool:
    """True for macOS metadata members: AppleDouble (`._*`) and `__MACOSX/`.

    macOS `tar`/`bsdtar` injects these into archives it writes (e.g. a GitHub
    source tarball downloaded and re-packed on a Mac, or a fixture built with
    the system tar). They are not part of the payload tree, and a top-level
    `._<dir>` member sorts before the real top-level directory — which would
    otherwise break single-top-level-dir detection and make apply silently
    no-op. Match at any depth so both `._top` and `top/._VERSION` are caught.
    """
    return any(part == "__MACOSX" or part.startswith("._") for part in Path(name).parts)


def safe_extract_tarball(tar_path: Path, into: Path) -> Path:
    """Extract a tarball, refusing any member that escapes `into`. Returns the
    single top-level directory (GitHub tarballs ship exactly one). macOS
    AppleDouble / __MACOSX metadata members are skipped (not payload, and a
    top-level `._<dir>` entry would corrupt top-level-dir detection)."""
    into.mkdir(parents=True, exist_ok=True)
    with tarfile.open(tar_path, "r:*") as tar:
        members = tar.getmembers()
        total = 0
        # Escape and size guards run over EVERY member (security is never
        # relaxed for `._*` names — an attacker could hide `../` behind one).
        for member in members:
            if _member_escapes(member, into):
                raise PlumblineError(f"unsafe tarball member: {member.name}")
            total += max(member.size, 0)
            if total > MAX_EXTRACT_BYTES:
                raise PlumblineError(f"tarball expands beyond {MAX_EXTRACT_BYTES} byte limit")
        # Payload = everything except macOS metadata. Only payload members are
        # written and only they count toward top-level-dir detection.
        payload = [m for m in members if not _is_apple_double(m.name)]
        # `filter="data"` is the second, independent guard: it strips setuid/
        # setgid/sticky bits and refuses device/special-file members that the
        # name-only check above does not inspect.
        try:
            tar.extractall(into, members=payload, filter="data")  # noqa: S202 - every member validated above
        except tarfile.FilterError as exc:
            raise PlumblineError(f"unsafe tarball member: {exc}") from exc
    tops = sorted({Path(m.name).parts[0] for m in payload if m.name not in ("", ".")})
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
    # Provenance: show exactly what will be downloaded and applied. `plumbline
    # update` runs the downloaded release's installer, so the operator must see
    # the source. There is no signature verification yet (declared limitation):
    # only update from releases you trust, over verified TLS, from this slug.
    tag = release.get("tag_name") or release.get("name") or "?"
    print(f"fetching release {tag} from github:{slug}")
    print(f"tarball: {url}")
    tmp = Path(tempfile.mkdtemp(prefix="plumbline-update-"))
    try:
        archive = download_tarball(str(url), tmp / "release.tar.gz")
        return safe_extract_tarball(archive, tmp / "extracted"), tmp
    except Exception:
        shutil.rmtree(tmp, ignore_errors=True)
        raise


def update_check(args: argparse.Namespace, root: Path) -> int:
    explicit_root = bool(getattr(args, "root", None))
    local = read_version(root, explicit_root=explicit_root)
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
        slug = getattr(args, "repo", None) or default_repo_slug(root, explicit_root=explicit_root)
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
        # Validate the payload's contract (fail-closed on a malformed
        # compatibility.json), but NEVER execute its verifyCommand string — a
        # downloaded payload must not be able to run arbitrary shell. The
        # operator's --verify-cmd or the fixed repo-pinned command runs instead.
        load_compatibility(target)
        verify = args.verify_cmd or DEFAULT_VERIFY
        print(f"verify: {verify}")
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
    # PATH discoverability of the installed CLI — the 'command not found' self-diagnosis.
    bindir = Path(os.environ.get("CLAUDE_HOME", str(Path.home() / ".claude"))) / "bin"
    on_path = str(bindir) in os.environ.get("PATH", "").split(os.pathsep)
    print(f"PATH: {bindir} {'on' if on_path else 'NOT on'} $PATH")
    if not on_path:
        print(f'  fix: export PATH="{bindir}:$PATH"  (add to your shell rc, then restart the shell)')
    # Update source — surface the resolved slug so a fork user sees where updates come from,
    # and that the upstream override already exists (no new capability, just discoverability).
    slug = default_repo_slug(root)
    print(f"update slug: {slug}")
    if slug != DEFAULT_REPO_SLUG:
        print(f"  note: fork detected — for upstream updates: plumbline update --repo {DEFAULT_REPO_SLUG}")
        print(f"        (or set PLUMBLINE_REPO={DEFAULT_REPO_SLUG})")
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
    explicit_root = bool(args.root)
    root = Path(args.root).resolve() if args.root else repo_root()
    try:
        if args.command == "version":
            print(read_version(root, explicit_root=explicit_root)); return 0
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
