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
# A valid GitHub OWNER/REPO slug: two path segments of the GitHub-permitted
# charset. Anything else (extra slashes, traversal, injection chars) must be
# refused before it is interpolated into a request path (NOTE-2).
REPO_SLUG_RE = re.compile(r"^[A-Za-z0-9._-]+/[A-Za-z0-9._-]+$")
# The one host the GitHub release Authorization header is ever attached to.
# Sending it anywhere else (e.g. an attacker-controlled PLUMBLINE_GITHUB_API)
# would exfiltrate the token, so the header is host-gated to this value
# (CRITICAL-1). The PLUMBLINE_GITHUB_API_ALLOW_INSECURE_TOKEN gate is the only,
# explicit, default-OFF exception (used by the offline 127.0.0.1 tests).
GITHUB_API_HOST = "api.github.com"
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


def resolve_install_home() -> Path | None:
    """Return the Claude-home root this CLI was INVOKED from, or None.

    The install-identity anchor (`.plumbline-install.json`) is written by
    install.sh at the Claude-home root, beside the installed `bin/` and `lib/`.
    The installed CLI is invoked as `$CLAUDE_HOME/lib/plumbline_update.py` (the
    bin wrapper `exec`s that path), so the anchor's directory IS `$CLAUDE_HOME`.

    Critically this walks up the UNRESOLVED invocation path (NOT `.resolve()`):
    in the DEFAULT symlink install the lib is a symlink INTO the source checkout,
    so `.resolve()` would dereference to the source tree (where there is no anchor)
    and miss the home entirely. The invocation path stays in `$CLAUDE_HOME`, which
    is exactly the home a natural `plumbline update` must target (REQ-PUR-04) —
    independent of symlink-vs-copy install mode. Returns None for a dev/source
    invocation (no anchor in the invocation ancestry).
    """
    here = Path(__file__)
    for parent in [here.parent, *here.parents]:
        if (parent / INSTALL_ANCHOR_NAME).is_file():
            return parent.resolve()
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


def _github_token() -> str | None:
    """Resolve a GitHub token for authenticated release fetches, best-effort.

    Order: $GITHUB_TOKEN -> $GH_TOKEN -> `gh auth token` (only if `gh` is on
    PATH). A non-empty env value wins. If EITHER token env var is *defined*
    (present in the environment) — even as an empty string — the caller has taken
    explicit control of token provisioning, so an empty value is an explicit
    "unauthenticated" opt-out and the `gh` fallback is NOT consulted (otherwise
    `gh auth token` would silently re-authenticate a deliberately-cleared run).
    The `gh` lookup is best-effort over a list-argv subprocess (no shell): any
    failure (gh missing, not authenticated, error) is swallowed and yields None.
    The token is used ONLY to build the Authorization header and is NEVER logged,
    printed, or embedded in any message — including exception text — so it cannot
    leak on any path.
    """
    env_token_defined = False
    for env_name in ("GITHUB_TOKEN", "GH_TOKEN"):
        if env_name in os.environ:
            env_token_defined = True
            # Strip before the truthiness check: a whitespace-only value (e.g.
            # GITHUB_TOKEN="   ") must resolve to "no token", never a garbage
            # `Bearer    ` header with a blank credential (NOTE-1). Matches the
            # existing `.strip()` on the `gh auth token` path below.
            value = os.environ[env_name].strip()
            if value:
                return value
    # An explicitly-defined-but-empty token env var means "unauthenticated";
    # do not let `gh auth token` override that deliberate choice.
    if env_token_defined:
        return None
    if shutil.which("gh") is None:
        return None
    try:
        proc = subprocess.run(
            ["gh", "auth", "token"],
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            timeout=HTTP_TIMEOUT,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode == 0:
        token = proc.stdout.strip()
        if token:
            return token
    return None


def fetch_latest_release(slug: str) -> dict[str, Any]:
    """GET the latest release metadata from the GitHub API (no traceback on failure).

    Sends an `Authorization: Bearer <token>` header when a token is resolvable
    AND the resolved base host is the real GitHub API host (REQ-PUR-03 AC-1 /
    CRITICAL-1 — never to an attacker-controlled PLUMBLINE_GITHUB_API host,
    except under the explicit default-OFF insecure-token gate the offline tests
    set); proceeds unauthenticated otherwise (AC-2). HTTP errors are
    classified DISTINCTLY (AC-3): 403 -> a rate-limit message, 404 -> a
    release/repo-not-found message, both escaping the generic "could not reach"
    wrapper that other transport errors keep. The token is never included in any
    message (AC-4): error text is built only from the HTTP status code, never the
    raw exception (which urllib does not embed the token in, but we avoid it as a
    belt) and never the token itself.
    """
    # Validate the slug BEFORE it touches the request path: a malformed slug
    # (extra path segments, traversal, control/injection chars) must be a clear
    # classified error, never a path-injected request (NOTE-2).
    if not REPO_SLUG_RE.match(slug):
        raise PlumblineError(
            f"invalid GitHub repo slug (expected OWNER/REPO): {slug!r}"
        )
    headers = {"User-Agent": USER_AGENT, "Accept": "application/vnd.github+json"}
    base = github_api_base()
    token = _github_token()
    # CRITICAL-1: the Authorization header is attached ONLY to the real GitHub
    # API host. PLUMBLINE_GITHUB_API is honored in prod, so a token + an
    # attacker-controlled host would otherwise exfiltrate the token. The only
    # non-github allowance is the EXPLICIT, default-OFF insecure-token gate (so
    # the offline 127.0.0.1 tests can exercise the header path); localhost is NOT
    # implicitly trusted (an attacker could bind it). Absent both, no header is
    # sent and the request proceeds unauthenticated (no crash).
    if token:
        base_host = urllib.parse.urlparse(base).hostname
        insecure_gate = os.environ.get("PLUMBLINE_GITHUB_API_ALLOW_INSECURE_TOKEN") == "1"
        if base_host == GITHUB_API_HOST or insecure_gate:
            headers["Authorization"] = f"Bearer {token}"
    url = require_safe_url(f"{base}/repos/{slug}/releases/latest")
    request = urllib.request.Request(url, headers=headers)
    try:
        with _SAFE_OPENER.open(request, timeout=HTTP_TIMEOUT) as response:
            payload = response.read()
    except urllib.error.HTTPError as exc:
        # Classify the distinct, actionable HTTP error paths. These messages must
        # NOT contain the generic "could not reach GitHub release API" wrapper, so
        # they are recognizably different from each other and from transport
        # failures. The error text is built from the status CODE only — never from
        # the exception object or the token — so no header/token can leak.
        code = exc.code
        if code == 403:
            raise PlumblineError(
                "GitHub API rate-limited (HTTP 403) - "
                "set GITHUB_TOKEN to raise the rate limit"
            ) from None
        if code == 404:
            raise PlumblineError(
                f"GitHub release/repo not found (HTTP 404): {slug} "
                "has no published release, or the repo slug is wrong"
            ) from None
        raise PlumblineError(
            f"could not reach GitHub release API: HTTP error {code}"
        ) from None
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


def resolve_payload_source(
    args: argparse.Namespace, root: Path, explicit_root: bool = True
) -> tuple[Path, Path | None]:
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
    slug = getattr(args, "repo", None) or default_repo_slug(root, explicit_root=explicit_root)
    release = fetch_latest_release(slug)
    url = release.get("tarball_url")
    if not url:
        raise PlumblineError("GitHub release metadata missing tarball_url")
    # SEC-3 (hardening): when the resolved API base is the REAL GitHub API host,
    # require the payload be fetched over https — refuse a plain-http network
    # payload (downgrade / MITM surface). http stays allowed ONLY under the
    # explicit localhost/test gate (PLUMBLINE_GITHUB_API_ALLOW_INSECURE_TOKEN),
    # exactly as the token-header host gate does, so the offline 127.0.0.1 tests
    # are unaffected. require_safe_url below still blocks non-http(s) schemes.
    base_host = urllib.parse.urlparse(github_api_base()).hostname
    insecure_gate = os.environ.get("PLUMBLINE_GITHUB_API_ALLOW_INSECURE_TOKEN") == "1"
    if base_host == GITHUB_API_HOST and not insecure_gate:
        if urllib.parse.urlparse(str(url)).scheme.lower() != "https":
            raise PlumblineError(
                "refusing non-https release tarball from the GitHub API: "
                f"{url}"
            )
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
    # CR-3: the target-clear delete-set is SYMMETRIC with snapshot_target's
    # ignore-set ({.git, .plumbline, __pycache__}). snapshot_target SKIPS those
    # entries when copying the home into the snapshot, so the snapshot never holds
    # them — deleting them here would WIPE an ignored-but-present user entry (e.g.
    # a user's $CLAUDE_HOME/__pycache__) with nothing to restore it from (silent
    # data loss masquerading as a safe rollback). Leave them in place instead.
    ignored = {".git", ".plumbline", "__pycache__"}
    for item in list(target.iterdir()):
        if item.name in ignored:
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


def run_command(
    command: str, cwd: Path, env: dict[str, str] | None = None
) -> subprocess.CompletedProcess[str]:
    return subprocess.run(
        command,
        cwd=str(cwd),
        shell=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        env=env,
    )


def run_migrations(target: Path, previous: str, new: str) -> None:
    state = target / ".plumbline" / "update" / "migrations.log"
    state.parent.mkdir(parents=True, exist_ok=True)
    with state.open("a", encoding="utf-8") as fh:
        fh.write(f"{_dt.datetime.now(_dt.UTC).isoformat().replace('+00:00', '')}Z {previous} -> {new}: no migrations declared\n")


def installed_lib_is_symlink(home: Path) -> bool:
    """True when this CLI was installed in SYMLINK mode into `home`.

    install.sh symlinks `$CLAUDE_HOME/lib/plumbline_update.py` into the source
    checkout for a default (symlink) install, and materializes a real file for a
    --copy install. The installed lib carries the same basename as this module, so
    the symlink-ness of `home/lib/<this-module>.py` is the authoritative install-mode
    signal (CR-1). Checked WITHOUT resolving so a symlink reads as a symlink.
    """
    installed = home / "lib" / Path(__file__).name
    return installed.is_symlink()


def symlink_checkout_root(home: Path) -> Path | None:
    """The live source checkout a SYMLINK install tracks, or None.

    Resolve the installed lib symlink to its real target inside the checkout, then
    walk up to the checkout's repo root (the dir holding config/claude/install.sh).
    This is the path `git pull` must run in to update a symlink install (CR-1).
    """
    installed = home / "lib" / Path(__file__).name
    if not installed.is_symlink():
        return None
    real = Path(os.path.realpath(installed))
    for parent in [real, *real.parents]:
        if (parent / "config" / "claude" / "install.sh").is_file():
            return parent
    return None


def install_home_target(args: argparse.Namespace) -> Path | None:
    """The $CLAUDE_HOME apply TARGET for a natural `plumbline update`, or None.

    Returns the installed Claude-home root ONLY when this is the real installed
    copy AND the operator gave no explicit `--target` (the path every user hits:
    `plumbline update` from anywhere). An explicit `--target <checkout>` keeps the
    old checkout-patch behavior, and a dev checkout (not installed) returns None
    so existing dev/test flows are unchanged.

    $CLAUDE_HOME env wins when it agrees with where the anchor was found; otherwise
    the anchor's own directory is authoritative (it is the home this lib was
    installed into), never the cwd.
    """
    if getattr(args, "target", None):
        return None
    # The apply TARGET is keyed on the INVOCATION location carrying the anchor —
    # NOT on `_is_installed_copy()` (which `.resolve()`s the lib symlink to the
    # source and would wrongly report a symlink install as "not installed"). When
    # an anchor sits in the invocation ancestry, this is a real installed CLI and
    # $CLAUDE_HOME is the home to refresh; otherwise (dev/source run) None keeps
    # the old checkout/cwd behavior.
    return resolve_install_home()


def _home_anchor_version(home: Path) -> str:
    """The installed Plumbline version recorded in $CLAUDE_HOME's identity anchor.

    The installed home carries no top-level VERSION file (install.sh mounts only
    agents/commands/lib/bin + the anchor), so the authoritative installed version
    lives in `.plumbline-install.json`. Read it directly; fail loud if it is
    absent or has no usable SemVer (the apply must know the prior version to gate
    MAJOR/up-to-date and to record the migration).
    """
    anchor = home / INSTALL_ANCHOR_NAME
    if not anchor.is_file():
        raise PlumblineError(
            f"no install-identity anchor at {anchor} "
            "(re-run install.sh to write the identity anchor)"
        )
    try:
        data = json.loads(anchor.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as exc:
        raise PlumblineError(f"install-identity anchor is unreadable: {exc}") from exc
    version = data.get("version") if isinstance(data, dict) else None
    if not isinstance(version, str) or not SEMVER_RE.search(version):
        raise PlumblineError(
            "install-identity anchor has no usable version "
            "(re-run install.sh to write the identity anchor)"
        )
    return SEMVER_RE.search(version).group(0)  # type: ignore[union-attr]


def update_apply(args: argparse.Namespace, root: Path) -> int:
    home_target = install_home_target(args)
    # CR-1: REFUSE a natural `plumbline update` on a SYMLINK install. The
    # confirmed two-mode contract is: COPY installs update via `plumbline update`;
    # SYMLINK installs update via `git pull` in the tracked checkout. Copy-converting
    # a symlink install in place (the old `install.sh --copy --update` behavior)
    # would silently destroy the user's live `git pull` workflow and freeze the
    # install to a copy — so refuse it BEFORE any payload is fetched/applied,
    # naming `git pull` and the checkout to run it in. An explicit `--target`
    # (home_target is None) keeps the checkout-patch path; a copy install (lib is a
    # real file) falls through to the normal home apply.
    if home_target is not None and installed_lib_is_symlink(home_target):
        checkout = symlink_checkout_root(home_target)
        where = str(checkout) if checkout is not None else "the checkout it points at"
        raise PlumblineError(
            "symlink install -> update via `git pull` in " + where + " "
            "(this is a symlink install: it tracks a live checkout; "
            "`plumbline update` would copy-convert and freeze it, so it is refused; "
            "run `git pull` there instead)"
        )
    explicit_root = bool(getattr(args, "root", None))
    source, tmp = resolve_payload_source(args, root, explicit_root=explicit_root)
    try:
        if home_target is not None:
            return _apply_into_home(args, home_target, source)
        target = Path(args.target).resolve() if args.target else root
        return _apply_from_source(args, target, source)
    finally:
        if tmp is not None:
            shutil.rmtree(tmp, ignore_errors=True)


def _apply_into_home(args: argparse.Namespace, home: Path, source: Path) -> int:
    """Real apply of a staged payload into the installed $CLAUDE_HOME, with a
    full snapshot + verify-or-revert safety floor (REQ-PUR-04/05/06).

    Sequence: read the installed (anchor) version; resolve the payload version and
    gate MAJOR/up-to-date exactly like the checkout path; SNAPSHOT the whole home;
    run the REAL `install.sh --update` from the STAGED payload against $CLAUDE_HOME
    (overwriting changed targets, adding new files, re-stamping the anchor); VERIFY
    from the staged checkout (the operator's --verify-cmd or the fixed repo-pinned
    command — NEVER the payload's verifyCommand string); on a verify failure REVERT
    the ENTIRE home to the snapshot (stale-but-prior files back, anchor back, added
    files gone) and exit non-zero. A failed update never leaves a half-updated home.
    """
    previous = _home_anchor_version(home)
    latest, _ = latest_from_source(source)
    if compare_versions(previous, latest) >= 0 and not args.force:
        print(f"status: up-to-date ({previous})")
        return 0
    major_delta = parse_semver(latest)[0] != parse_semver(previous)[0]
    if major_delta and not args.yes_major:
        raise PlumblineError("MAJOR update requires explicit --yes-major")

    # Validate the payload's contract (fail-closed on a malformed
    # compatibility.json) BEFORE we touch the home — but never execute its
    # verifyCommand string.
    load_compatibility(source)

    installer = source / "config" / "claude" / "install.sh"
    if not installer.is_file():
        raise PlumblineError(f"update payload has no installer at {installer}")

    snapshot = snapshot_target(home)
    print(f"snapshot: {snapshot}")
    try:
        # Run the REAL installer (NOT --dry-run) from the staged payload into the
        # installed home. --copy so content is materialized into $CLAUDE_HOME (a
        # symlink would point into the throwaway payload that is cleaned up after
        # this apply). --update so changed targets are overwritten and new files
        # added. NO --no-skills (CR-2): skills are part of the confirmed refresh set
        # (REQ-PUR-05 — agents/commands/skills/libs/bin), so an existing skill is
        # content-compared + refreshed and a new shipped skill is added. KEEP
        # --no-hook deliberately: the global settings.json Stop-hook registration is
        # NOT in the confirmed refresh set, and re-registering it on every self-update
        # is intrusive jq/settings churn — a named scope decision, not an oversight.
        env = dict(os.environ)
        env["CLAUDE_HOME"] = str(home)
        # SEC-2 (hardening): scrub GITHUB_TOKEN/GH_TOKEN from the subprocess env.
        # The release fetch already happened before this apply; the staged install.sh
        # / verify subprocess never needs the token, and a compromised payload's
        # installer must not be able to read the operator's token from its own
        # environment. Remove both names (present-but-empty included).
        for _tok in ("GITHUB_TOKEN", "GH_TOKEN"):
            env.pop(_tok, None)
        result = subprocess.run(
            ["bash", str(installer), "--copy", "--update", "--no-hook"],
            cwd=str(source),
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
        )
        print(result.stdout, end="")
        if result.returncode != 0:
            raise PlumblineError("install.sh --update failed")

        new = _home_anchor_version(home)
        run_migrations(home, previous, new)

        # Verify from the STAGED payload checkout (so the verify command runs
        # against the new code), with the FIXED/operator command — never the
        # payload-supplied verifyCommand string. SEC-2: reuse the token-scrubbed
        # env so the verify subprocess (which runs over the staged payload) also
        # cannot read GITHUB_TOKEN/GH_TOKEN.
        verify = args.verify_cmd or DEFAULT_VERIFY
        print(f"verify: {verify}")
        vres = run_command(verify, source, env=env)
        print(vres.stdout, end="")
        if vres.returncode != 0:
            raise PlumblineError(f"verification failed: {verify}")

        marker = home / ".plumbline" / "update" / "last-success.json"
        marker.parent.mkdir(parents=True, exist_ok=True)
        marker.write_text(
            json.dumps({"previous": previous, "version": new, "snapshot": str(snapshot)}, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"status: changed and verified ({previous} -> {new})")
        return 0
    except Exception:
        restore_snapshot(snapshot, home)
        print(f"status: reverted to snapshot {snapshot}")
        # CR-4: name the exact recovery command so a crash MID-revert is still
        # recoverable by hand (the snapshot survives; re-run rollback against it).
        print(f"recover: plumbline rollback {snapshot}")
        raise


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
        # CR-4: name the exact recovery command so a crash MID-revert is still
        # recoverable by hand (the snapshot survives; re-run rollback against it).
        print(f"recover: plumbline rollback {snapshot} --target {target}")
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


def doctor(args: argparse.Namespace, root: Path) -> int:
    explicit_root = bool(getattr(args, "root", None))
    version = read_version(root, explicit_root=explicit_root)
    # The contracted version/update-slug lines (resolved from the install anchor)
    # must print regardless of cwd; a missing/invalid compatibility.json off-tree
    # is reported as the `compatibility.json: fail` check below (preserving the
    # off-tree non-zero exit), not raised as a fatal error that aborts before the
    # version/slug lines are ever printed.
    try:
        compat = load_compatibility(root)
    except PlumblineError:
        compat = {}
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
    slug = default_repo_slug(root, explicit_root=explicit_root)
    print(f"update slug: {slug}")
    if slug != DEFAULT_REPO_SLUG:
        print(f"  note: fork detected — for upstream updates: plumbline update --repo {DEFAULT_REPO_SLUG}")
        print(f"        (or set PLUMBLINE_REPO={DEFAULT_REPO_SLUG})")
    return 0 if all(ok for _, ok in checks) else 1


def honest_status(args: argparse.Namespace, root: Path) -> int:
    explicit_root = bool(getattr(args, "root", None))
    print("changed, not yet verified")
    print(f"version: {read_version(root, explicit_root=explicit_root)}")
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
