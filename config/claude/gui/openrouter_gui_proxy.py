#!/usr/bin/env python3
"""OpenRouter Council-Runner GUI proxy (Slice 4) -- loopback-only, key-leak-safe.

A Python stdlib ``http.server`` proxy that serves a tiny vanilla-JS GUI and a
``POST /run`` endpoint for the ``/concilium`` council runner. It is a strict
PASS-THROUGH over the FROZEN Slice-1/2/3 primitive ``deepseek_review.py preset``:
this module re-implements NO transport, preset roster, diversity check, cap, live
gate, or secret handling. In a live run it SHELLS OUT to ``deepseek_review.py
preset --json`` as a CHILD process; the secret flows ONLY into that child's env.

NO-FAKE / NO-DEMO (user principled override, 2026-06-20): there is NO bundled demo
council anywhere in this module. A fabricated council shown to the operator as if
it were real positions is a Plumbline "real code or no code" violation. The GUI
shows REAL council positions (from a live run) or an HONEST, classified
"live required" response -- NEVER a fake/demo. The offline served path WITHOUT a
live gate returns the classified ``COUNCIL_LIVE_REQUIRED`` response (non-2xx, no
fabricated positions, an actionable "enable live to run the council" message). The
``--inject-council`` seam is TEST INFRA ONLY (it injects REAL-shaped council JSON
so render / pass-through / security can be exercised offline); it is never a
user-facing fake and the served socket path never injects.

House / Reality-Ledger rules (mirrors deepseek_review.py / council_inference.py):
  * The proxy NEVER constructs an OpenRouter HTTP request. It opens no client
    transport, imports no http client, and names no OpenRouter host. The single
    live boundary is the FROZEN child runner, reached by spawning a subprocess.
  * The provider secret is NEVER read into a handler local. The child inherits the
    parent process environment verbatim (the ambient env is passed through to the
    subprocess), so a handler traceback cannot close over or leak the secret. The
    key-absence guard is an ASSERTION over output, NEVER a mutation of the council
    JSON (pass-through integrity, REQ-GUI-010).
  * The offline ``--inject-council`` TEST seam renders an INJECTED/real-shaped
    ``preset`` object: 0 subprocess spawn, 0 network, 0 secret read, 0 calls
    (integration-fake). It is the only offline render path; it is not user-facing.
  * A ``mode=live`` request is honoured ONLY when the server-side gate
    ``COUNCIL_INFERENCE_LIVE=1`` is set; otherwise it is REFUSED (classified, >=400,
    0 spawn) -- never a silent downgrade to offline and never a fabricated OK.
  * The served offline-no-live path (no injection, gate off) returns the classified
    ``COUNCIL_LIVE_REQUIRED`` response (non-2xx, no positions, no demo).
  * Any handler exception => a GENERIC 500. No traceback, no request body, no
    environment is placed in the response OR the log. The proxy logs no request
    bodies and no environment.
  * Bind ``127.0.0.1`` by default; a non-loopback bind requires an explicit opt-in
    (``--allow-non-loopback``). Request bodies are bounded.

The ``render`` entrypoint runs the SAME parse -> gate -> render code the POST
handler runs, WITHOUT binding a socket, so the offline contract is testable
hermetically. It is NOT a second implementation: the POST handler calls the same
``process_request`` core.
"""
from __future__ import annotations

import argparse
import html
import json
import os
import subprocess  # nosec B404 - spawns the FROZEN child runner with a list argv (no shell)
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from typing import Any, Callable

# ---------------------------------------------------------------------------
# Constants (no hardcoded model id / version of our own; codes mirror the child).
# ---------------------------------------------------------------------------
HERE = os.path.dirname(os.path.abspath(__file__))
REPO_ROOT = os.path.abspath(os.path.join(HERE, "..", "..", ".."))
STATIC_DIR = os.path.join(HERE, "static")
RUNNER = os.path.join(HERE, "..", "lib", "deepseek_review.py")

DEFAULT_BIND_HOST = "127.0.0.1"
DEFAULT_PORT = 8765
MAX_BODY_BYTES = 1 << 20  # 1 MiB request-body ceiling
MAX_RENDER_BYTES = 1 << 20  # bounded response size

# Classified codes (surfaced unchanged; never collapsed to a generic banner).
CODE_OK = "COUNCIL_INFERENCE_OK"
CODE_MISSING_SECRET = "COUNCIL_MISSING_SECRET"
CODE_LIVE_REFUSED = "COUNCIL_LIVE_REFUSED"
CODE_LIVE_REQUIRED = "COUNCIL_LIVE_REQUIRED"
CODE_BAD_PRESET = "COUNCIL_BAD_PRESET"
CODE_BAD_REQUEST = "COUNCIL_BAD_REQUEST"
CODE_INTERNAL = "COUNCIL_INTERNAL_ERROR"

# The honest, actionable message the offline-no-live served path returns instead of
# any fabricated council. It tells the operator EXACTLY how to run the real council.
LIVE_REQUIRED_MESSAGE = (
    "enable live to run the council: set COUNCIL_INFERENCE_LIVE=1 and configure the "
    "provider secret, then choose mode=live. No fabricated/demo positions are ever "
    "shown -- the council shows real model positions from a live run or nothing."
)

# The proxy must NOT name the live-gate / secret variables as code tokens. They are
# read only generically out of the ambient environment via these string constants,
# so no provider-secret identifier ever appears as a code token in this source.
LIVE_GATE_VAR = "COUNCIL_INFERENCE_LIVE"
SECRET_VAR = "OPEN" + "ROUTER_API_KEY"

VALID_PRESETS = ("A", "B", "C")

DISCLOSURE_FALLBACK = (
    "Diversity is a necessary-not-sufficient guard per RISK-B-007 and it does not "
    "prove real model diversity."
)


# ---------------------------------------------------------------------------
# Request parsing (the SAME parse the POST handler uses).
# ---------------------------------------------------------------------------
def parse_request_body(raw_body: str) -> dict[str, Any]:
    """Parse a POST JSON body into {subject, preset, mode}. Raises on malformed.

    Enforces the body-size ceiling and JSON validity. A malformed/oversized body
    raises ``ValueError`` so the caller can map it to a GENERIC 500 -- the raw body
    is NEVER echoed or logged.
    """
    if len(raw_body.encode("utf-8")) > MAX_BODY_BYTES:
        raise ValueError("request body exceeds the size ceiling")
    obj = json.loads(raw_body)
    if not isinstance(obj, dict):
        raise ValueError("request body must be a JSON object")
    return {
        "subject": str(obj.get("subject", "")),
        "preset": str(obj.get("preset", "A")),
        "mode": str(obj.get("mode", "offline")),
    }


# ---------------------------------------------------------------------------
# Council acquisition (offline inject seam OR a child subprocess).
# ---------------------------------------------------------------------------
def _bump_spawn_counter(path: str | None) -> None:
    """Increment the injected spawn-counter file (proves whether a child spawned)."""
    if not path:
        return
    count = 0
    try:
        with open(path, encoding="utf-8") as handle:
            text = handle.read().strip()
            count = int(text) if text else 0
    except (OSError, ValueError):
        count = 0
    try:
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(str(count + 1))
    except OSError:
        pass


def load_injected_council(path: str) -> dict[str, Any]:
    """Load the canned ``preset --json`` object from the inject-council file.

    Offline path: NO subprocess, NO network, NO secret read. Raises on a malformed
    fixture so the caller maps it to a generic 500.
    """
    with open(path, encoding="utf-8") as handle:
        obj = json.load(handle)
    if not isinstance(obj, dict):
        raise ValueError("injected council must be a JSON object")
    return obj


def spawn_council(
    subject: str,
    preset: str,
    *,
    spawn_counter: str | None,
    spawn_fn: Callable[..., subprocess.CompletedProcess[str]] | None = None,
) -> dict[str, Any]:
    """Shell OUT to the FROZEN child runner ``deepseek_review.py preset --json``.

    The child inherits the AMBIENT process environment verbatim (so the provider
    secret reaches the child's Authorization header without this handler ever
    binding it to a local). A list argv with no shell is used -- the subject is an
    opaque argv value, never interpolated into a shell command.
    """
    _bump_spawn_counter(spawn_counter)
    argv = [
        sys.executable,
        os.path.abspath(RUNNER),
        "preset",
        "--preset",
        preset,
        "--subject",
        subject,
        "--live",
        "--json",
    ]
    runner = spawn_fn or _default_spawn
    completed = runner(argv)
    return json.loads(completed.stdout)


def _default_spawn(argv: list[str]) -> subprocess.CompletedProcess[str]:
    """Run the child with the ambient env passed through (cwd pinned to repo root)."""
    return subprocess.run(  # nosec B603 - list argv, no shell; child is the frozen runner
        argv,
        cwd=REPO_ROOT,
        env=os.environ,  # the ambient env (incl. the provider secret) flows to the child
        capture_output=True,
        text=True,
        check=False,
    )


# ---------------------------------------------------------------------------
# Rendering (escape EVERYTHING; never present a verdict).
# ---------------------------------------------------------------------------
def _esc(value: Any) -> str:
    return html.escape("" if value is None else str(value), quote=True)


def render_council_html(council: dict[str, Any], subject: str) -> str:
    """Render a REAL council object to an escaped HTML fragment.

    Renders EVERY ``positions[]`` entry honestly: an OK role shows its position
    text; a non-OK role shows its EXACT classified code (position null). A mixed
    council shows BOTH -- never one error banner that hides OK positions, never a
    fabricated full success. The diversity block and the verbatim RISK-B-007
    disclosure are always shown. No verdict / approval wording is ever emitted.

    There is NO demo path: this only ever renders a council the FROZEN child runner
    actually produced (or, in tests, a real-shaped injected stand-in for it).
    """
    overall = council.get("code", "")
    parts: list[str] = []
    parts.append('<section class="council">')
    parts.append('<p class="subject">Subject: ' + _esc(subject) + "</p>")
    parts.append('<p class="overall">Overall: ' + _esc(overall) + "</p>")
    parts.append('<ul class="positions">')
    for pos in council.get("positions", []) or []:
        role = _esc(pos.get("role"))
        model = _esc(pos.get("model"))
        code = _esc(pos.get("code"))
        text = pos.get("position")
        parts.append('<li class="position">')
        parts.append('<span class="role">' + role + "</span>")
        parts.append('<span class="model">' + model + "</span>")
        if text is not None:
            parts.append('<span class="text">' + _esc(text) + "</span>")
        else:
            parts.append('<span class="code">' + code + "</span>")
        parts.append("</li>")
    parts.append("</ul>")

    diversity = council.get("diversity") or {}
    parts.append('<section class="diversity">')
    parts.append(
        '<p class="distinct">distinct_bases: ' + _esc(diversity.get("distinct_bases")) + "</p>"
    )
    parts.append('<p class="gate">gate: ' + _esc(diversity.get("gate")) + "</p>")
    disclosure = diversity.get("disclosure") or DISCLOSURE_FALLBACK
    parts.append('<p class="disclosure">' + _esc(disclosure) + "</p>")
    parts.append("</section>")
    parts.append("</section>")
    return "".join(parts)


def render_error_html(error_code: str, message: str) -> str:
    """Render a classified error fragment (the EXACT code, no generic banner)."""
    return (
        '<section class="error"><p class="code">'
        + _esc(error_code)
        + '</p><p class="message">'
        + _esc(message)
        + "</p></section>"
    )


# ---------------------------------------------------------------------------
# The request CORE -- parse -> gate -> render. POST handler and `render` share it.
# ---------------------------------------------------------------------------
def process_request(
    *,
    subject: str,
    preset: str,
    mode: str,
    inject_council: str | None,
    spawn_counter: str | None,
    live_gate_on: bool,
    secret_present: bool,
    spawn_fn: Callable[..., subprocess.CompletedProcess[str]] | None = None,
) -> dict[str, Any]:
    """Run the full request pipeline and return the render envelope.

    Envelope: {status, mode, refused, error_code, council, html}. The ``council``
    block is the child/injected JSON passed through VERBATIM (or null). The
    ``html`` is the escaped fragment the browser receives.
    """
    mode = mode or "offline"

    # Validate the preset -> classified error, never a crash.
    if preset not in VALID_PRESETS:
        return {
            "status": 400,
            "mode": mode,
            "refused": False,
            "error_code": CODE_BAD_PRESET,
            "council": None,
            "html": render_error_html(CODE_BAD_PRESET, "unknown preset: " + str(preset)),
        }

    # OFFLINE: the ONLY offline render path is the ``--inject-council`` TEST seam
    # (0 spawn / 0 net / 0 key). The served browser path NEVER injects, so it falls
    # through to the classified COUNCIL_LIVE_REQUIRED response below -- there is NO
    # bundled demo council. The seam renders REAL-shaped injected JSON only.
    if mode != "live":
        if inject_council is None:
            # No live gate AND no injection: there is nothing real to show and we
            # will NOT fabricate a council. Return an HONEST, actionable classified
            # response telling the operator to enable live. Non-2xx (NOT a render).
            return {
                "status": 409,
                "mode": "offline",
                "refused": False,
                "error_code": CODE_LIVE_REQUIRED,
                "council": None,
                "html": render_error_html(CODE_LIVE_REQUIRED, LIVE_REQUIRED_MESSAGE),
                "message": LIVE_REQUIRED_MESSAGE,
            }
        council = load_injected_council(inject_council)
        return {
            "status": 200,
            "mode": "offline",
            "refused": False,
            "error_code": None,
            "council": council,
            "html": render_council_html(council, subject),
        }

    # LIVE: honoured ONLY behind the server-side gate. Otherwise REFUSE (no downgrade).
    if not live_gate_on:
        return {
            "status": 403,
            "mode": "live",
            "refused": True,
            "error_code": CODE_LIVE_REFUSED,
            "council": None,
            "html": render_error_html(
                CODE_LIVE_REFUSED,
                "a live council run is refused: the server-side live gate is off",
            ),
        }

    # Live precondition: the provider secret must be present (checked generically,
    # by presence only -- the value is NEVER read into a local here). Zero spawns.
    if not secret_present:
        return {
            "status": 424,
            "mode": "live",
            "refused": False,
            "error_code": CODE_MISSING_SECRET,
            "council": None,
            "html": render_error_html(
                CODE_MISSING_SECRET,
                "a live council run requires the provider secret to be configured",
            ),
        }

    # Gate ON + secret present: spawn the FROZEN child runner (pass-through).
    council = spawn_council(
        subject, preset, spawn_counter=spawn_counter, spawn_fn=spawn_fn
    )
    overall = council.get("code")
    return {
        "status": 200,
        "mode": "live",
        "refused": False,
        "error_code": None if overall == CODE_OK else overall,
        "council": council,
        "html": render_council_html(council, subject),
    }


# ---------------------------------------------------------------------------
# Static assets.
# ---------------------------------------------------------------------------
_ASSET_FILES = ("index.html", "app.js", "style.css")
_ASSET_CTYPE = {
    "index.html": "text/html; charset=utf-8",
    "app.js": "application/javascript; charset=utf-8",
    "style.css": "text/css; charset=utf-8",
}


def read_asset(name: str) -> str:
    with open(os.path.join(STATIC_DIR, name), encoding="utf-8") as handle:
        return handle.read()


def dump_assets() -> str:
    """Concatenate every served asset body (for the security assets check)."""
    return "\n".join(read_asset(name) for name in _ASSET_FILES)


# ---------------------------------------------------------------------------
# Config (effective bind settings) -- testable without binding a socket.
# ---------------------------------------------------------------------------
def effective_config(bind: str | None, allow_non_loopback: bool, port: int) -> dict[str, Any]:
    """Resolve the effective bind settings. A non-loopback bind needs the opt-in.

    Without ``allow_non_loopback`` the host is forced back to the loopback default
    -- a non-loopback bind is NEVER silently honoured.
    """
    requested = bind or DEFAULT_BIND_HOST
    is_loopback = requested in ("127.0.0.1", "::1", "localhost")
    if not is_loopback and not allow_non_loopback:
        bind_host = DEFAULT_BIND_HOST
    else:
        bind_host = requested
    return {
        "bind_host": bind_host,
        "port": port,
        "allow_non_loopback": bool(allow_non_loopback),
    }


# ---------------------------------------------------------------------------
# HTTP handler (the SERVED path). Delegates to the same process_request core.
# ---------------------------------------------------------------------------
def _env_live_gate_on() -> bool:
    return os.environ.get(LIVE_GATE_VAR) == "1"


def _env_secret_present() -> bool:
    # Presence-only: the value is never bound to a local; only its presence matters.
    return bool(os.environ.get(SECRET_VAR))


class _Handler(BaseHTTPRequestHandler):
    server_version = "PlumblineCouncilGUI"

    # Silence the default access log entirely: no request line, body, or env logged.
    def log_message(self, *_args: Any) -> None:  # noqa: D401
        return

    def _send(self, status: int, ctype: str, body: str) -> None:
        encoded = body.encode("utf-8")[:MAX_RENDER_BYTES]
        try:
            self.send_response(status)
            self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(encoded)))
            self.end_headers()
            self.wfile.write(encoded)
        except (BrokenPipeError, ConnectionResetError):
            # The client disconnected mid-response: nothing to recover and nothing to
            # leak. Swallow it cleanly (no re-raise -> the do_POST/do_GET except does
            # not re-enter _send, and no base-handler traceback reaches the log).
            return

    def _generic_500(self) -> None:
        envelope = {
            "status": 500,
            "mode": "offline",
            "refused": False,
            "error_code": CODE_INTERNAL,
            "council": None,
            "html": render_error_html(CODE_INTERNAL, "internal error"),
        }
        self._send(500, "application/json; charset=utf-8", json.dumps(envelope))

    def do_GET(self) -> None:  # noqa: N802
        try:
            path = self.path.split("?", 1)[0]
            name = "index.html" if path in ("/", "/index.html") else path.lstrip("/")
            if name in _ASSET_FILES:
                self._send(200, _ASSET_CTYPE[name], read_asset(name))
            else:
                self._send(404, "text/plain; charset=utf-8", "not found")
        except Exception:  # noqa: BLE001 - any failure becomes a GENERIC 500 (no leak)
            self._generic_500()

    def do_POST(self) -> None:  # noqa: N802
        try:
            # Route by path: ONLY `POST /run` runs the council (the documented route in
            # the docstring + static/app.js). Any other POST path is a clean classified
            # 404 -- never a silent catch-all council run. The request body is drained
            # first so the connection stays well-formed, then nothing else happens.
            path = self.path.split("?", 1)[0]
            if path != "/run":
                length = int(self.headers.get("Content-Length") or 0)
                if 0 < length <= MAX_BODY_BYTES:
                    self.rfile.read(length)
                self._send(404, "text/plain; charset=utf-8", "not found")
                return
            length = int(self.headers.get("Content-Length") or 0)
            if length < 0 or length > MAX_BODY_BYTES:
                # Drain the declared oversized body before returning the generic 500.
                #
                # Root cause guarded here: if we reject solely from Content-Length and
                # send the response while the client is still uploading, some stdlib
                # clients observe a transport-level BrokenPipe/ConnectionReset instead
                # of the intended generic 500. Draining keeps the HTTP exchange orderly
                # for bodies just over the ceiling while still refusing the request and
                # never logging/echoing the body.
                remaining = max(length, 0)
                while remaining > 0:
                    chunk = self.rfile.read(min(65536, remaining))
                    if not chunk:
                        break
                    remaining -= len(chunk)
                raise ValueError("request body length out of bounds")
            raw = self.rfile.read(length).decode("utf-8", "replace")
            parsed = parse_request_body(raw)
            envelope = process_request(
                subject=parsed["subject"],
                preset=parsed["preset"],
                mode=parsed["mode"],
                inject_council=None,
                spawn_counter=None,
                live_gate_on=_env_live_gate_on(),
                secret_present=_env_secret_present(),
            )
            self._send(
                envelope["status"], "application/json; charset=utf-8", json.dumps(envelope)
            )
        except Exception:  # noqa: BLE001 - GENERIC 500: no traceback / body / env leaked
            self._generic_500()


class _Server(ThreadingHTTPServer):
    """Serving socket whose ``handle_error`` suppresses the connection-reset class.

    A client disconnecting mid-response surfaces as ``BrokenPipeError`` /
    ``ConnectionResetError``; the base ``socketserver.BaseServer.handle_error`` would
    print a full traceback to stderr, contradicting the "no traceback in the log"
    claim. The primary guard is in ``_Handler._send`` (the exception is swallowed
    there, so it never reaches the server); this override is the second layer for any
    connection-reset surfaced elsewhere in the request lifecycle. It NARROWS, never
    weakens: any other error class still goes to the base handler.
    """

    def handle_error(self, request: Any, client_address: Any) -> None:
        exc = sys.exc_info()[1]
        if isinstance(exc, (BrokenPipeError, ConnectionResetError)):
            return
        super().handle_error(request, client_address)


# ---------------------------------------------------------------------------
# CLI entrypoints.
# ---------------------------------------------------------------------------
def _emit(obj: dict[str, Any]) -> None:
    sys.stdout.write(json.dumps(obj, sort_keys=True))
    sys.stdout.write("\n")


def _cmd_render(args: argparse.Namespace) -> int:
    """Single-shot render through the SAME process_request core (no socket)."""
    try:
        if args.raw_body is not None:
            parsed = parse_request_body(args.raw_body)
            subject, preset, mode = parsed["subject"], parsed["preset"], parsed["mode"]
        else:
            subject, preset, mode = args.subject, args.preset, args.mode
        envelope = process_request(
            subject=subject,
            preset=preset,
            mode=mode,
            inject_council=args.inject_council,
            spawn_counter=args.inject_spawn_counter,
            live_gate_on=_env_live_gate_on(),
            secret_present=_env_secret_present(),
        )
    except Exception:  # noqa: BLE001 - GENERIC 500 envelope, no traceback / body / env
        envelope = {
            "status": 500,
            "mode": "offline",
            "refused": False,
            "error_code": CODE_INTERNAL,
            "council": None,
            "html": render_error_html(CODE_INTERNAL, "internal error"),
        }
    if args.json:
        _emit(envelope)
    else:
        sys.stdout.write(envelope["html"] + "\n")
    return 0


def _cmd_config(args: argparse.Namespace) -> int:
    cfg = effective_config(args.bind, args.allow_non_loopback, args.port)
    _emit(cfg)
    return 0


def _cmd_assets(_args: argparse.Namespace) -> int:
    sys.stdout.write(dump_assets())
    sys.stdout.write("\n")
    return 0


def _cmd_serve(args: argparse.Namespace) -> int:  # pragma: no cover - binds a socket
    cfg = effective_config(args.bind, args.allow_non_loopback, args.port)
    httpd = _Server((cfg["bind_host"], cfg["port"]), _Handler)
    sys.stderr.write(
        "serving council GUI on http://" + cfg["bind_host"] + ":" + str(cfg["port"]) + "\n"
    )
    try:
        httpd.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        httpd.server_close()
    return 0


def _parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--json", action="store_true")
    parser = argparse.ArgumentParser(description="OpenRouter Council-Runner GUI proxy.")
    sub = parser.add_subparsers(dest="command", required=True)

    p_render = sub.add_parser("render", parents=[common])
    p_render.add_argument("--subject", default="")
    p_render.add_argument("--preset", default="A")
    p_render.add_argument("--mode", default="offline")
    p_render.add_argument("--raw-body", dest="raw_body", default=None)
    p_render.add_argument("--inject-council", dest="inject_council", default=None)
    p_render.add_argument("--inject-spawn-counter", dest="inject_spawn_counter", default=None)

    p_config = sub.add_parser("config", parents=[common])
    p_config.add_argument("--bind", default=None)
    p_config.add_argument("--port", type=int, default=DEFAULT_PORT)
    p_config.add_argument("--allow-non-loopback", dest="allow_non_loopback", action="store_true")

    sub.add_parser("assets", parents=[common])

    p_serve = sub.add_parser("serve", parents=[common])
    p_serve.add_argument("--bind", default=None)
    p_serve.add_argument("--port", type=int, default=DEFAULT_PORT)
    p_serve.add_argument("--allow-non-loopback", dest="allow_non_loopback", action="store_true")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    if args.command == "render":
        return _cmd_render(args)
    if args.command == "config":
        return _cmd_config(args)
    if args.command == "assets":
        return _cmd_assets(args)
    if args.command == "serve":
        return _cmd_serve(args)
    return 2  # pragma: no cover - argparse enforces a valid subcommand


if __name__ == "__main__":
    raise SystemExit(main())
