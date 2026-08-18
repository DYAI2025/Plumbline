#!/usr/bin/env python3
"""Secure HTTPS transport for the GitHub API (PLUM-14 phase 1A, v2).

This slice is ONLY the transport. No repository-id resolution, no pull-request state,
no ref queries, no lifecycle, no hooks. Those are later slices and are deliberately
absent here.

Why it was rebuilt
------------------
The v1 provider (commit 32e0b46, preserved on
`backup/plum-14-github-provider-rejected-p0`) was rejected
`REWORK_REQUIRED / P0_CREDENTIAL_EXFILTRATION / FALSE_GREEN`. Its redirect refusal
lived in a `urllib` handler whose only proofs called `redirect_request(req=None, ...)`.
A handler that returns None only for `req is None` and otherwise delegates to the
stdlib satisfied every assertion while production followed redirects: measured
end-to-end, a 301 to `evil.example` produced `REMOTE_UNCHANGED`, allow-capable, exit 0,
and sent `Authorization: Bearer <token>` to the attacker host -- with the suite green.

Two structural lessons are built into this module rather than tested around:

1. **Redirects cannot be followed, because nothing here can follow them.**
   `http.client.HTTPSConnection` has no redirect machinery at all. A 3xx is just a
   response; classifying it is the only thing that can happen. There is no handler to
   mutate, so the vulnerable shape does not exist.
2. **One verdict, one truth.** The v1 result carried a separately serialised
   `allow_capable` alongside the state and the exit code, so a mutant could make the
   JSON say "allowed" while the exit code disagreed and no test noticed. Here a single
   `Verdict` determines the JSON classification AND the exit code; permission is
   DERIVED (`verdict is HTTP_OK`), never stored.

Trust
-----
The only trust source is the vendored bundle `plumbline_ca_bundle.pem`, sitting beside
this file so `install.sh` ships it (the lib layer installs `lib/*` at maxdepth 1; a
subdirectory would not ship). Its sha256 is pinned below. `create_default_context()`
and `load_default_certs()` are never called, because both read `SSL_CERT_FILE` /
`SSL_CERT_DIR`. There is no fallback to system CAs and no fallback to the environment:
a missing, empty, unreadable or hash-mismatched bundle is a blocking trust error and
no request is issued.

Evidence ceiling: `integration-fake` for the classification paths; the TLS paths are
exercised against a REAL local TLS server with a locally generated CA, which is
`integration-real` for verification behaviour. No public GitHub boundary is crossed.
"""

from __future__ import annotations

import argparse
import hashlib
import http.client
import json
import os
import socket
import ssl
import sys
from dataclasses import dataclass, field
from typing import Any, Callable, Dict, List, Optional, Sequence, Tuple

# --------------------------------------------------------------------------------------
# Constants -- none of these is settable from the CLI, the environment or a config file
# --------------------------------------------------------------------------------------

API_HOST = "api.github.com"
API_PORT = 443
API_VERSION = "2022-11-28"
DEFAULT_TIMEOUT = 8.0
MAX_RESPONSE_BYTES = 1000000

CA_BUNDLE_NAME = "plumbline_ca_bundle.pem"
CA_BUNDLE_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), CA_BUNDLE_NAME)
# Pinned identity of the vendored bundle. Refresh together with the file itself.
CA_BUNDLE_SHA256 = "a5b3251ebdee62a055134dc3afaea2c2883d970c48b22a0da556a63f7fe88249"
TRUST_SOURCE = "plumbline_bundle"


# --------------------------------------------------------------------------------------
# The single canonical verdict. JSON classification and exit code come from HERE and
# nowhere else; permission is derived, never serialised as an independent field.
# --------------------------------------------------------------------------------------

HTTP_OK = "HTTP_OK"
HTTP_REDIRECT_REFUSED = "HTTP_REDIRECT_REFUSED"
HTTP_AUTH_FAILED = "HTTP_AUTH_FAILED"
HTTP_FORBIDDEN = "HTTP_FORBIDDEN"
HTTP_RATE_LIMITED = "HTTP_RATE_LIMITED"
HTTP_TIMEOUT = "HTTP_TIMEOUT"
HTTP_TLS_UNVERIFIED = "HTTP_TLS_UNVERIFIED"
HTTP_RESPONSE_TOO_LARGE = "HTTP_RESPONSE_TOO_LARGE"
HTTP_RESPONSE_MALFORMED = "HTTP_RESPONSE_MALFORMED"
HTTP_UNAVAILABLE = "HTTP_UNAVAILABLE"
HTTP_REQUEST_REFUSED = "HTTP_REQUEST_REFUSED"
HTTP_TRUST_UNAVAILABLE = "HTTP_TRUST_UNAVAILABLE"

# ONE table. The exit code is a projection of the verdict, so the two cannot diverge.
_EXIT = {
    HTTP_OK: 0,
    HTTP_REDIRECT_REFUSED: 3,
    HTTP_REQUEST_REFUSED: 4,
    HTTP_TRUST_UNAVAILABLE: 4,
    HTTP_AUTH_FAILED: 5,
    HTTP_FORBIDDEN: 5,
    HTTP_RATE_LIMITED: 5,
    HTTP_TIMEOUT: 5,
    HTTP_TLS_UNVERIFIED: 5,
    HTTP_RESPONSE_TOO_LARGE: 5,
    HTTP_RESPONSE_MALFORMED: 5,
    HTTP_UNAVAILABLE: 5,
}

ALL_VERDICTS: Tuple[str, ...] = tuple(sorted(_EXIT))


def exit_code_for(verdict: str) -> int:
    """The exit code of a verdict. Unknown verdicts are a programming error, and are
    reported as blocking rather than defaulting to success."""
    return _EXIT.get(verdict, 5)


def carries_payload(verdict: str) -> bool:
    """Only HTTP_OK may hand a body to a later provider layer. DERIVED, never stored:
    v1 shipped a separate serialised `allow_capable` that a mutant could flip while the
    exit code stayed correct, and no test could see the divergence."""
    return verdict == HTTP_OK


class TrustUnavailable(Exception):
    """The pinned CA bundle is missing, empty, unreadable or has the wrong hash."""


# --------------------------------------------------------------------------------------
# Redaction -- by registered secret VALUE, never by token prefix
# --------------------------------------------------------------------------------------


def redact(text: str, secrets: Sequence[str] = ()) -> str:
    """Mask every registered secret value, and any Bearer credential.

    v1 keyed redaction on GitHub token prefixes (`ghp_`, ...), so five token families
    and every non-GitHub bearer value leaked while the suite was green. Here the caller
    registers the exact secret values it passed in, and the Bearer masking is
    prefix-agnostic.
    """
    if not text:
        return text
    out = str(text)
    for secret in secrets:
        if secret:
            out = out.replace(secret, "***redacted***")
    lowered = out.lower()
    pos = lowered.find("bearer ")
    while pos >= 0:
        end = len(out)
        for scan in range(pos + 7, len(out)):
            if out[scan] in " \t\r\n\"'":
                end = scan
                break
        out = out[:pos] + "Bearer ***redacted***" + out[end:]
        lowered = out.lower()
        pos = lowered.find("bearer ", pos + 21)
    return out


# --------------------------------------------------------------------------------------
# Trust
# --------------------------------------------------------------------------------------


@dataclass
class TrustInfo:
    source: str
    bundle_sha256: str
    ca_count: int
    bundle_name: str

    def to_dict(self) -> Dict[str, Any]:
        # Deliberately no absolute path: the installation root is a personal path.
        return {
            "trust_source": self.source,
            "bundle_name": self.bundle_name,
            "bundle_sha256": self.bundle_sha256,
            "ca_count": self.ca_count,
        }


def load_trust(bundle_path: str = CA_BUNDLE_PATH,
               expected_sha256: str = CA_BUNDLE_SHA256) -> Tuple[ssl.SSLContext, TrustInfo]:
    """Build the TLS context from the vendored bundle alone. No fallbacks."""
    try:
        with open(bundle_path, "rb") as fh:
            raw = fh.read()
    except OSError as exc:
        raise TrustUnavailable("CA bundle %s is not readable: %s" % (CA_BUNDLE_NAME, exc.strerror or exc))
    if not raw.strip():
        raise TrustUnavailable("CA bundle %s is empty" % CA_BUNDLE_NAME)
    digest = hashlib.sha256(raw).hexdigest()
    if expected_sha256 and digest != expected_sha256:
        raise TrustUnavailable(
            "CA bundle %s has sha256 %s, expected %s" % (CA_BUNDLE_NAME, digest, expected_sha256))
    ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_CLIENT)
    ctx.check_hostname = True
    ctx.verify_mode = ssl.CERT_REQUIRED
    try:
        ctx.load_verify_locations(cafile=bundle_path)
    except (ssl.SSLError, OSError) as exc:
        raise TrustUnavailable("CA bundle %s could not be loaded: %s" % (CA_BUNDLE_NAME, exc))
    count = ctx.cert_store_stats().get("x509", 0)
    if count <= 0:
        raise TrustUnavailable("CA bundle %s loaded no certificates" % CA_BUNDLE_NAME)
    return ctx, TrustInfo(source=TRUST_SOURCE, bundle_sha256=digest, ca_count=count,
                          bundle_name=CA_BUNDLE_NAME)


# --------------------------------------------------------------------------------------
# Request / response shapes
# --------------------------------------------------------------------------------------


@dataclass
class TransportResult:
    verdict: str
    detail: str
    status: Optional[int] = None
    headers: Dict[str, str] = field(default_factory=dict)
    body: bytes = b""
    trust: Optional[Dict[str, Any]] = None

    @property
    def exit_code(self) -> int:
        return exit_code_for(self.verdict)

    def to_dict(self) -> Dict[str, Any]:
        # `verdict` is the ONLY permission-bearing field. There is deliberately no
        # separate boolean: a consumer derives permission from the verdict, exactly as
        # the exit code does, so the two cannot disagree.
        return {
            "verdict": self.verdict,
            "exit_code": self.exit_code,
            "status": self.status,
            "detail": self.detail,
            "trust": self.trust,
        }

    def to_json(self) -> str:
        return json.dumps(self.to_dict(), indent=2, sort_keys=True)


_PATH_FORBIDDEN = set("\r\n\t\x00 ")


def _valid_path(path: Any) -> bool:
    if not isinstance(path, str) or not path.startswith("/"):
        return False
    if any(ch in _PATH_FORBIDDEN for ch in path):
        return False
    if any(ord(ch) < 32 or ord(ch) == 127 for ch in path):
        return False
    if "//" in path or "/../" in path or path.endswith("/..") or "://" in path:
        return False
    return len(path) <= 2048


def _valid_token(token: Any) -> bool:
    if token is None:
        return True
    if not isinstance(token, str) or not token:
        return False
    return all(32 <= ord(ch) <= 126 for ch in token)


def _headers(token: Optional[str]) -> Dict[str, str]:
    out = {
        "Host": API_HOST,
        "Accept": "application/vnd.github+json",
        "X-GitHub-Api-Version": API_VERSION,
        "User-Agent": "plumbline-github-transport",
        "Connection": "close",
    }
    if token:
        out["Authorization"] = "Bearer %s" % token
    return out


def _real_connection(context: ssl.SSLContext, timeout: float) -> http.client.HTTPSConnection:
    """The production connection. Host and port are constants; there is no parameter,
    environment variable or flag that can retarget them."""
    return http.client.HTTPSConnection(API_HOST, API_PORT, timeout=timeout, context=context)


def fetch(path: str, token: Optional[str] = None, *, timeout: float = DEFAULT_TIMEOUT,
          _connection_factory: Optional[Callable] = None,
          _bundle_path: str = CA_BUNDLE_PATH,
          _expected_sha256: str = CA_BUNDLE_SHA256) -> TransportResult:
    """One GET against api.github.com. Total: every failure yields a verdict.

    `_connection_factory` and the bundle overrides are private keyword-only parameters
    for the contract tests. Nothing on the CLI, in the environment, in the repository
    or in any config file reaches them -- asserted by the contract test, including a
    runtime probe that records every os.environ lookup through a re-import.
    """
    secrets = [token] if token else []
    if not _valid_token(token):
        return TransportResult(verdict=HTTP_REQUEST_REFUSED,
                               detail="the supplied token is not a sendable header value")
    if not _valid_path(path):
        return TransportResult(verdict=HTTP_REQUEST_REFUSED,
                               detail="the request path is not an acceptable absolute API path")
    if not isinstance(timeout, (int, float)) or isinstance(timeout, bool) or timeout <= 0:
        return TransportResult(verdict=HTTP_REQUEST_REFUSED,
                               detail="the timeout must be a positive number")

    try:
        context, trust = load_trust(_bundle_path, _expected_sha256)
    except TrustUnavailable as exc:
        # No request is issued: without a trust anchor nothing can be verified.
        return TransportResult(verdict=HTTP_TRUST_UNAVAILABLE, detail=redact(str(exc), secrets))
    trust_dict = trust.to_dict()

    factory = _connection_factory if _connection_factory is not None else _real_connection
    conn = None
    try:
        conn = factory(context, timeout)
        conn.request("GET", path, headers=_headers(token))
        response = conn.getresponse()
        status = int(response.status)
        headers = dict((str(k).lower(), str(v)) for k, v in response.getheaders())
        body = response.read(MAX_RESPONSE_BYTES + 1)
    except ssl.SSLCertVerificationError as exc:
        return TransportResult(verdict=HTTP_TLS_UNVERIFIED, trust=trust_dict,
                               detail=redact("certificate verification failed: %s" % exc, secrets))
    except ssl.SSLError as exc:
        return TransportResult(verdict=HTTP_TLS_UNVERIFIED, trust=trust_dict,
                               detail=redact("TLS failure: %s" % exc, secrets))
    except socket.timeout as exc:
        return TransportResult(verdict=HTTP_TIMEOUT, trust=trust_dict,
                               detail=redact("the request timed out: %s" % (exc or ""), secrets))
    except (http.client.HTTPException, OSError, ValueError, TypeError, AttributeError) as exc:
        if isinstance(exc, socket.timeout):
            return TransportResult(verdict=HTTP_TIMEOUT, trust=trust_dict,
                                   detail=redact("the request timed out", secrets))
        return TransportResult(verdict=HTTP_UNAVAILABLE, trust=trust_dict,
                               detail=redact("%s: %s" % (type(exc).__name__, exc), secrets))
    except Exception as exc:  # noqa: BLE001 -- totality is the point
        return TransportResult(verdict=HTTP_UNAVAILABLE, trust=trust_dict,
                               detail=redact("unclassified failure %s: %s" % (type(exc).__name__, exc), secrets))
    finally:
        if conn is not None:
            try:
                conn.close()
            except Exception:  # noqa: BLE001
                pass

    if len(body) > MAX_RESPONSE_BYTES:
        return TransportResult(verdict=HTTP_RESPONSE_TOO_LARGE, status=status, trust=trust_dict,
                               detail="the response exceeded %d bytes and was discarded" % MAX_RESPONSE_BYTES)

    # A redirect is REFUSED, not followed. There is no redirect machinery in this
    # module to mutate: http.client never follows one, so the only reachable behaviour
    # is to classify it. The Location target is never contacted and never receives the
    # Authorization header.
    if 300 <= status < 400:
        return TransportResult(verdict=HTTP_REDIRECT_REFUSED, status=status, headers=headers,
                               trust=trust_dict,
                               detail="the API answered %d; redirects are never followed" % status)
    if status == 401:
        return TransportResult(verdict=HTTP_AUTH_FAILED, status=status, headers=headers,
                               trust=trust_dict, detail="the API rejected the credential")
    exhausted = headers.get("x-ratelimit-remaining") == "0"
    if status == 429 or (status == 403 and exhausted):
        extra = ""
        if headers.get("retry-after"):
            extra = " (retry-after=%s)" % headers.get("retry-after")
        return TransportResult(verdict=HTTP_RATE_LIMITED, status=status, headers=headers,
                               trust=trust_dict, detail="the API rate limit is exhausted" + extra)
    if status == 403:
        return TransportResult(verdict=HTTP_FORBIDDEN, status=status, headers=headers,
                               trust=trust_dict, detail="the API refused the request")
    if status >= 500:
        return TransportResult(verdict=HTTP_UNAVAILABLE, status=status, headers=headers,
                               trust=trust_dict, detail="the API returned a server error")
    if status != 200:
        # 404 and every other non-200 is not a transport success. Interpreting a 404 is
        # a PROVIDER concern and this slice deliberately has no provider semantics.
        return TransportResult(verdict=HTTP_RESPONSE_MALFORMED, status=status, headers=headers,
                               trust=trust_dict, detail="unexpected status %d" % status)
    return TransportResult(verdict=HTTP_OK, status=status, headers=headers, body=body,
                           trust=trust_dict, detail="the API answered")


# --------------------------------------------------------------------------------------
# Output surface
# --------------------------------------------------------------------------------------


def emit(result: TransportResult) -> int:
    sys.stdout.write(result.to_json() + "\n")
    if result.exit_code != 0:
        sys.stderr.write("%s: %s\n" % (result.verdict, result.detail))
    return result.exit_code


def _build_parser() -> argparse.ArgumentParser:
    p = argparse.ArgumentParser(
        prog="plumbline-github-transport",
        description="Perform one verified HTTPS GET against the GitHub API and classify the outcome.",
    )
    # No --host, --url, --api-base, --ca-file, --opener and no --token: the host and the
    # trust source are constants, and a token flag would put the credential in the
    # process table.
    p.add_argument("--path", required=True, help="absolute API path, e.g. /rate_limit")
    p.add_argument("--timeout", type=float, default=DEFAULT_TIMEOUT)
    return p


def cli_option_strings() -> List[str]:
    out: List[str] = []
    for action in _build_parser()._actions:
        out.extend(action.option_strings)
    return out


def main(argv: Optional[List[str]] = None, token: Optional[str] = None) -> int:
    args = _build_parser().parse_args(argv)
    return emit(fetch(args.path, token=token, timeout=args.timeout))


if __name__ == "__main__":
    sys.exit(main())
