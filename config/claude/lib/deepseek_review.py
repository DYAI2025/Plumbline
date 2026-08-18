#!/usr/bin/env python3
"""DeepSeek-Review council-body/character RUNNER (network-free, key-free offline).

Runs a ``/concilium`` body — a ``concilium/<body>.md`` prompt OR a character's
extracted ``xml`` system prompt — on a real FOREIGN (non-Claude) OpenRouter model
through the REUSED Slice-1 ``council_inference.run_inference`` path. A ``preset``
subcommand resolves + runs a typed roster (``council_presets``).

Reality Ledger / house rules (mirrors council_inference.py / council_backend.py):
  * EVERY real call is delegated to ``council_inference.run_inference`` — this
    module re-implements NO transport, cap, key-handling, COUNCIL_* code, or live
    gate. The offline suite drives it via the SAME injected seams
    (``--inject-response`` / ``--inject-error`` / ``--inject-call-counter``) plus
    an injected catalog (``--inject-catalog``) for the resolver — 0 credits, 0
    network. These checks are ``integration-fake`` and prove NO real invocability.
  * The per-call input estimate is computed by the runner's OWN estimator
    (``council_inference.estimate_input_tokens``) — NEVER hand-fed (Slice-1 retro
    RISK-DS-005), so the budget instrument measures itself.
  * Body/character names are untrusted slugs validated + realpath-contained BEFORE
    any read (traversal/absolute rejected → classified, no file content leak).
  * The raw ``OPENROUTER_API_KEY`` lives ONLY in run_inference's Authorization
    header; it MUST NEVER appear in any output (REQ-DS-013).
  * NO Claude-family literal anywhere: an unresolvable role classifies, never
    substitutes a Claude model (MEDIUM-1 / RISK-DS-PRE-015).
"""
from __future__ import annotations

import argparse
import json
import os
import re
from typing import Any, Callable

import council_presets
from council_inference import estimate_input_tokens, run_inference
from council_presets import (
    CODE_CATALOG_UNREACHABLE,
    CODE_MODEL_UNRESOLVABLE,
    CODE_UNKNOWN_CHARACTER_SLUG,
    CODE_UNKNOWN_PRESET,
    RISK_B_007_DISCLOSURE,
    diversity_check,
    get_preset,
    resolve_model,
)

# Classified slug codes (distinct, never collapsed). The preset/resolver codes
# (unknown-preset, unknown-character-slug, model-unresolvable, catalog-unreachable)
# are owned by council_presets and surfaced here unchanged — NEVER substituted with a
# Claude-family model on an unresolvable role (MEDIUM-1 / RISK-DS-PRE-015).
CODE_OK = "COUNCIL_INFERENCE_OK"
CODE_MODEL_UNAVAILABLE = "COUNCIL_MODEL_UNAVAILABLE"
CODE_DIVERSITY_UNAVAILABLE = "COUNCIL_DIVERSITY_UNAVAILABLE"
CODE_PROMPT_MISSING = "prompt-missing"
CODE_CHARACTER_MISSING = "character-missing"
CODE_XML_BLOCK_MISSING = "xml-block-missing"
CODE_XML_BLOCK_MALFORMED = "xml-block-malformed"
CODE_XML_BLOCK_EMPTY = "xml-block-empty"

# A slug must be a safe name — no separators, traversal, or absolute paths.
_SLUG_RE = re.compile(r"^[a-z0-9-]+$")

DEFAULT_MAX_TOKENS = 256
_XML_HEADING = "## Direkt kopierbarer Systemprompt"

# Reuse the Slice-1 default timeout (council_backend) so the live catalog fetch uses
# the SAME budget resolution (COUNCIL_TIMEOUT_SECONDS / default) as `reachable`.
from council_backend import DEFAULT_TIMEOUT_SECONDS  # noqa: E402

# Injectable catalog FETCHER seam (REQ-DS-015 paired real entrypoint). Defaults to
# the REUSED Slice-1 live boundary ``council_backend._fetch_catalog_ids`` (fixed
# OpenRouter host → no SSRF; key header-only). A test monkeypatches this module-level
# hook to supply a fake fetcher and exercise the live-no-inject path with 0 network.
# The signature is ``(api_key: str, timeout_seconds: int) -> list[str]``; it may raise
# (URLError/ValueError/timeout) which the caller CLASSIFIES as catalog-unreachable.
_CATALOG_FETCHER: Callable[[str, int], list[str]] | None = None


def _catalog_fetcher() -> Callable[[str, int], list[str]]:
    """Return the active catalog fetcher (the test hook if set, else the real one)."""
    if _CATALOG_FETCHER is not None:
        return _CATALOG_FETCHER
    from council_backend import _fetch_catalog_ids

    return _fetch_catalog_ids


def _live_catalog_ids(env: dict[str, str]) -> list[str] | None:
    """Fetch the REAL OpenRouter catalog ids for the resolver, fail-closed.

    Reuses the Slice-1 key + timeout resolution: requires ``OPENROUTER_API_KEY``
    presence (the raw value stays header-only inside the fetcher — never logged or
    returned) and the ``COUNCIL_TIMEOUT_SECONDS`` / default budget. Any failure
    (missing key, URLError/timeout/ValueError, or an empty catalog) returns ``None``
    so the resolver classifies ``catalog-unreachable`` — NEVER a stale/guessed pick.
    """
    api_key = env.get("OPENROUTER_API_KEY")
    if not api_key:
        return None
    timeout_seconds = _env_int(env.get("COUNCIL_TIMEOUT_SECONDS"), DEFAULT_TIMEOUT_SECONDS)
    try:
        ids = _catalog_fetcher()(api_key, timeout_seconds)
    except Exception:  # noqa: BLE001 - any fetch failure fails closed to unreachable
        return None
    return ids or None


def _needs_catalog_for_run(env: dict[str, str], cli_model: str | None) -> bool:
    """True only when the run-path resolver will actually consult the catalog.

    Mirrors ``resolve_model``'s precedence ladder: an explicit ``--model`` or the
    ``COUNCIL_INFERENCE_MODEL`` env both short-circuit BEFORE the catalog, so the
    live fetch must NOT fire for them (keeps the gated-live no-inject path 0-network).
    """
    if cli_model:
        return False
    if env.get("COUNCIL_INFERENCE_MODEL"):
        return False
    return True


def _needs_catalog_for_preset(roster: list[dict[str, Any]] | None, env: dict[str, str]) -> bool:
    """True unless EVERY preset role has an explicit model (per-role or env override).

    A preset role with no ``model`` falls through to the catalog resolver, so the live
    fetch is needed whenever any role lacks an explicit pick.
    """
    if not roster:
        return False
    if env.get("COUNCIL_INFERENCE_MODEL"):
        return False
    return any(not role.get("model") for role in roster)


def _prompts_dir() -> str:
    """The concilium bodies directory (constant; not caller-controlled)."""
    return "concilium"


def _characters_dir() -> str:
    """The characters root — overridable via DEEPSEEK_CHARACTERS_DIR for fixtures.

    The override exists SOLELY so the failure-branch fixtures (missing heading /
    malformed fence / empty block / missing dir) can be tested without touching the
    READ-ONLY committed library (NGOAL-DS-009). Default = ``concilium/characters``.
    """
    return os.environ.get("DEEPSEEK_CHARACTERS_DIR") or "concilium/characters"


# ---------------------------------------------------------------------------
# Body loading (REQ-DS-001) — reuse load_prompt slug + realpath-containment.
# ---------------------------------------------------------------------------
def load_body_messages(body: str, subject: str, *, prompts_dir: str) -> dict[str, Any]:
    """Load ``concilium/<body>.md`` and build [system, user] messages.

    Reuses ``council_backend.load_prompt`` semantics (slug-only, realpath
    containment). Missing/rejected → ``prompt-missing`` (never fabricated, never
    substituted). ``prompt_source`` is the canonical ``concilium/<body>.md`` path.
    """
    from council_backend import load_prompt

    loaded = load_prompt(body, prompts_dir)
    source = loaded["source"]
    if loaded["status"] != "loaded":
        return {"status": CODE_PROMPT_MISSING, "prompt_source": source, "messages": None}
    messages = [
        {"role": "system", "content": loaded["content"]},
        {"role": "user", "content": subject},
    ]
    return {"status": "loaded", "prompt_source": source, "messages": messages}


# ---------------------------------------------------------------------------
# Character XML extraction (REQ-DS-002) — first ```xml block under the heading.
# ---------------------------------------------------------------------------
def extract_character_xml(slug: str, *, characters_dir: str) -> dict[str, Any]:
    """Extract the FIRST ```xml block under the heading from a role-contract.

    Slug-validated + realpath-contained BEFORE any read. Classifies, in order:
    ``character-missing`` (bad slug / dir / file absent), ``xml-block-missing``
    (heading absent or no ```xml fence before EOF/next heading),
    ``xml-block-malformed`` (unclosed fence), ``xml-block-empty`` (empty block).
    NEVER fabricates or substitutes a prompt.
    """
    source = f"concilium/characters/{slug}/references/role-contract.md"
    missing = {"status": CODE_CHARACTER_MISSING, "prompt_source": source, "system_prompt": None}

    if not _SLUG_RE.match(slug):
        return missing

    base = os.path.realpath(characters_dir)
    path = os.path.realpath(os.path.join(base, slug, "references", "role-contract.md"))
    if os.path.commonpath([base, path]) != base or not os.path.isfile(path):
        return missing

    with open(path, encoding="utf-8") as handle:
        lines = handle.read().splitlines()

    # 1. Locate the heading.
    heading_idx = None
    for idx, line in enumerate(lines):
        if line.strip() == _XML_HEADING:
            heading_idx = idx
            break
    if heading_idx is None:
        return {"status": CODE_XML_BLOCK_MISSING, "prompt_source": source, "system_prompt": None}

    # 2. Find the first ```xml fence after the heading (before the next ## heading).
    open_idx = None
    for idx in range(heading_idx + 1, len(lines)):
        stripped = lines[idx].strip()
        if stripped == "```xml":
            open_idx = idx
            break
        if stripped.startswith("## "):
            break
    if open_idx is None:
        return {"status": CODE_XML_BLOCK_MISSING, "prompt_source": source, "system_prompt": None}

    # 3. Find the closing fence.
    close_idx = None
    for idx in range(open_idx + 1, len(lines)):
        if lines[idx].strip() == "```":
            close_idx = idx
            break
    if close_idx is None:
        return {"status": CODE_XML_BLOCK_MALFORMED, "prompt_source": source, "system_prompt": None}

    # 4. Extract + validate non-empty.
    block = "\n".join(lines[open_idx + 1:close_idx])
    if block.strip() == "":
        return {"status": CODE_XML_BLOCK_EMPTY, "prompt_source": source, "system_prompt": None}

    return {"status": "loaded", "prompt_source": source, "system_prompt": block}


def build_character_messages(slug: str, subject: str, *, characters_dir: str) -> dict[str, Any]:
    """Extract the character xml and build [system, user] messages, or classify."""
    extracted = extract_character_xml(slug, characters_dir=characters_dir)
    if extracted["status"] != "loaded":
        return {"status": extracted["status"], "prompt_source": extracted["prompt_source"], "messages": None}
    messages = [
        {"role": "system", "content": extracted["system_prompt"]},
        {"role": "user", "content": subject},
    ]
    return {"status": "loaded", "prompt_source": extracted["prompt_source"], "messages": messages}


# ---------------------------------------------------------------------------
# Position wrapping (REQ-DS-007).
# ---------------------------------------------------------------------------
def wrap_position(inference_result: dict[str, Any], *, model: str, prompt_source: str) -> dict[str, Any]:
    """Wrap a run_inference result into a council position, or pass the classified code.

    On OK → the completion prose becomes the position with model + prompt_source.
    On any non-OK COUNCIL_* code → the code passes through unchanged with a NULL
    position (never a fabricated position; no body/error leak — run_inference never
    returns the raw body/error text in its result).
    """
    code = inference_result.get("code")
    if code == CODE_OK:
        return {"code": CODE_OK, "model": model, "prompt_source": prompt_source,
                "position": inference_result.get("completion")}
    return {"code": code, "model": model, "prompt_source": prompt_source, "position": None}


def _resolve_run_model(
    env: dict[str, str], cli_model: str | None, catalog_ids: list[str] | None
) -> dict[str, Any]:
    """Resolve a single run's model: --model > env > dynamic resolver (catalog)."""
    return resolve_model(env=env, per_role_model=cli_model, catalog_ids=catalog_ids)


def _run_one(
    env: dict[str, str],
    *,
    messages: list[dict[str, Any]],
    model: str,
    prompt_source: str,
    transport: Callable[..., Any] | None,
    inject_response: str | None,
    inject_error: str | None,
    dry_run: bool,
    on_transport_call: Callable[[], None] | None,
) -> dict[str, Any]:
    """Build the estimate (own estimator), delegate to run_inference, wrap position."""
    input_estimate = estimate_input_tokens(messages)
    cap = _env_int(env.get("COUNCIL_MAX_TOKENS_PER_RUN"), 20000)
    max_tokens = min(DEFAULT_MAX_TOKENS, cap) if cap > 0 else DEFAULT_MAX_TOKENS
    result = run_inference(
        env,
        model=model,
        messages=messages,
        max_tokens=max_tokens,
        input_estimate=input_estimate,
        dry_run=dry_run,
        build_only=False,
        inject_response=inject_response,
        inject_error=inject_error,
        inject_retry_after=None,
        transport=transport,
        on_transport_call=on_transport_call,
    )
    return wrap_position(result, model=model, prompt_source=prompt_source)


def _env_int(value: str | None, default: int) -> int:
    if value is None or value.strip() == "":
        return default
    try:
        return int(value.strip())
    except ValueError:
        return default


def _character_exists(characters_dir: str) -> Callable[[str], bool]:
    def _exists(slug: str) -> bool:
        if not _SLUG_RE.match(slug):
            return False
        base = os.path.realpath(characters_dir)
        path = os.path.realpath(os.path.join(base, slug, "references", "role-contract.md"))
        return os.path.commonpath([base, path]) == base and os.path.isfile(path)

    return _exists


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------
def _parse_catalog(raw: str | None) -> list[str] | None:
    return council_presets._parse_catalog(raw)


def _parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--json", action="store_true", help="Emit machine-readable JSON.")
    parser = argparse.ArgumentParser(
        description="DeepSeek-Review council-body/character runner.", parents=[common])
    sub = parser.add_subparsers(dest="command", required=True)

    p_run = sub.add_parser("run", help="Run ONE body OR ONE character.", parents=[common])
    p_run.add_argument("--body", default=None)
    p_run.add_argument("--character", default=None)
    p_run.add_argument("--subject", default="")
    p_run.add_argument("--model", default=None)
    p_run.add_argument("--dry-run", action="store_true")
    p_run.add_argument("--live", action="store_true")
    p_run.add_argument("--inject-response", default=None)
    p_run.add_argument("--inject-error", default=None)
    p_run.add_argument("--inject-catalog", default=None)
    p_run.add_argument("--inject-call-counter", default=None)

    p_pre = sub.add_parser("preset", help="Resolve + run a named preset (default A).", parents=[common])
    p_pre.add_argument("--preset", default=council_presets.DEFAULT_PRESET)
    p_pre.add_argument("--subject", default="")
    p_pre.add_argument("--dry-run", action="store_true")
    p_pre.add_argument("--live", action="store_true")
    p_pre.add_argument("--inject-response", default=None)
    p_pre.add_argument("--inject-error", default=None)
    p_pre.add_argument("--inject-catalog", default=None)
    p_pre.add_argument("--inject-call-counter", default=None)
    return parser


def _make_transport(args: argparse.Namespace, env: dict[str, str]) -> Callable[..., Any] | None:
    """Arm the real transport ONLY when --live AND COUNCIL_INFERENCE_LIVE=1.

    Delegates to council_inference._real_transport (the Slice-1 gate logic is reused
    verbatim — we do not re-derive the gate). Offline (no env) => None => 0 calls.
    """
    if getattr(args, "live", False) and env.get("COUNCIL_INFERENCE_LIVE") == "1":
        from council_inference import _real_transport

        return _real_transport
    return None


def _emit(state: dict[str, Any]) -> None:
    print(json.dumps(state, sort_keys=True, indent=2))


def _cmd_run(args: argparse.Namespace, env: dict[str, str]) -> dict[str, Any]:
    if bool(args.body) == bool(args.character):
        # --body XOR --character: neither or both is a usage error, classified.
        return {"code": CODE_PROMPT_MISSING, "model": None, "prompt_source": None,
                "messages": None, "position": None, "diversity": _single_diversity(None)}

    if args.body is not None:
        built = load_body_messages(args.body, args.subject, prompts_dir=_prompts_dir())
        is_character = False
    else:
        built = build_character_messages(args.character, args.subject, characters_dir=_characters_dir())
        is_character = True

    if built["status"] != "loaded":
        return {"code": built["status"], "model": None, "prompt_source": built["prompt_source"],
                "messages": None, "position": None, "diversity": _single_diversity(None)}

    disclosed = _disclosed_messages(built["messages"], include_system_content=is_character)

    # --inject-catalog (offline test seam) STILL wins when SUPPLIED — including an
    # explicit empty value (``--inject-catalog ""`` => injected-unreachable, stays
    # 0-network). The live fetch is ONLY the fallback when the flag is ABSENT
    # (args.inject_catalog is None) AND the resolver actually needs the catalog.
    catalog = _parse_catalog(args.inject_catalog)
    if args.inject_catalog is None and _needs_catalog_for_run(env, args.model):
        catalog = _live_catalog_ids(env)
    resolved = _resolve_run_model(env, args.model, catalog)
    model = resolved["model"]

    # The built messages are ALWAYS disclosed (the dry-run shows what WOULD be sent);
    # model-resolution failure does not suppress them.
    if model is None:
        return {"code": resolved["code"], "model": None, "prompt_source": built["prompt_source"],
                "messages": disclosed, "position": None, "diversity": _single_diversity(None)}

    call_count = {"n": 0}

    def _bump() -> None:
        call_count["n"] += 1

    transport = _make_transport(args, env)
    wrapped = _run_one(
        env,
        messages=built["messages"],
        model=model,
        prompt_source=built["prompt_source"],
        transport=transport,
        inject_response=args.inject_response,
        inject_error=args.inject_error,
        dry_run=args.dry_run,
        on_transport_call=_bump,
    )
    _write_counter(args.inject_call_counter, call_count["n"])
    wrapped["messages"] = disclosed
    wrapped["diversity"] = _single_diversity(model)
    return wrapped


def _disclosed_messages(
    messages: list[dict[str, Any]], *, include_system_content: bool
) -> list[dict[str, Any]]:
    """Build the OUTPUT-disclosed message structure (the dry-run "what would be sent").

    The real inference call always receives the FULL, UNMODIFIED ``messages`` (system
    prompt + subject). The disclosed structure exposes the role markers and the user
    subject verbatim; the SYSTEM prompt body is included for a CHARACTER run (so the
    extracted role contract is auditable) and elided for a BODY run, where the full
    editable prompt is already disclosed via ``prompt_source`` (concilium/<body>.md).

    The disclosed system body is the VERBATIM character/role-contract prompt (no
    transform), so a disclosed prompt always equals its role-contract source — the
    auditability invariant. The prompt actually sent is identically unmodified.
    """
    disclosed: list[dict[str, Any]] = []
    for message in messages:
        role = message.get("role")
        if role == "system" and not include_system_content:
            disclosed.append({"role": "system", "content_source": "prompt_source"})
        elif role == "system":
            disclosed.append({"role": "system",
                              "content": str(message.get("content"))})
        else:
            disclosed.append({"role": role, "content": message.get("content")})
    return disclosed


def _single_diversity(model: str | None) -> dict[str, Any]:
    div = diversity_check([model] if model else [])
    return {"distinct_bases": div["distinct_bases"], "gate": div["gate"],
            "disclosure": div["disclosure"]}


def _cmd_preset(args: argparse.Namespace, env: dict[str, str]) -> dict[str, Any]:
    roster = get_preset(args.preset)
    if roster is None:
        return {"code": CODE_UNKNOWN_PRESET, "positions": [],
                "diversity": {"distinct_bases": 0, "gate": CODE_DIVERSITY_UNAVAILABLE,
                              "disclosure": RISK_B_007_DISCLOSURE}}

    # --inject-catalog (offline test seam) STILL wins when SUPPLIED — including an
    # explicit empty value (injected-unreachable, stays 0-network). The live fetch is
    # ONLY the fallback when the flag is ABSENT (args.inject_catalog is None) AND at
    # least one role needs the resolver.
    catalog = _parse_catalog(args.inject_catalog)
    if args.inject_catalog is None and _needs_catalog_for_preset(roster, env):
        catalog = _live_catalog_ids(env)
    resolution = council_presets.resolve_preset(
        args.preset, env=env, catalog_ids=catalog,
        character_exists=_character_exists(_characters_dir()),
    )

    diversity = resolution["diversity"]
    div_block = {"distinct_bases": diversity["distinct_bases"], "gate": diversity["gate"],
                 "disclosure": diversity["disclosure"]}

    # Fail closed BEFORE any call when the roster cannot be resolved or is non-diverse.
    if resolution["decision"] == "abort":
        positions = [
            {"role": r["role_name"], "character": r["character_slug"], "model": r["model"],
             "code": r["code"], "position": None}
            for r in resolution["roles"]
        ]
        return {"code": resolution["code"], "positions": positions, "diversity": div_block}

    call_count = {"n": 0}

    def _bump() -> None:
        call_count["n"] += 1

    transport = _make_transport(args, env)
    positions: list[dict[str, Any]] = []
    for role in resolution["roles"]:
        slug = role["character_slug"]
        model = role["model"]
        built = build_character_messages(slug, args.subject, characters_dir=_characters_dir())
        if built["status"] != "loaded":
            positions.append({"role": role["role_name"], "character": slug, "model": model,
                              "code": built["status"], "position": None})
            continue
        wrapped = _run_one(
            env,
            messages=built["messages"],
            model=model,
            prompt_source=built["prompt_source"],
            transport=transport,
            inject_response=args.inject_response,
            inject_error=args.inject_error,
            dry_run=args.dry_run,
            on_transport_call=_bump,
        )
        positions.append({"role": role["role_name"], "character": slug, "model": model,
                          "code": wrapped["code"], "position": wrapped["position"]})

    _write_counter(args.inject_call_counter, call_count["n"])
    overall = CODE_OK if all(p["code"] == CODE_OK for p in positions) else CODE_MODEL_UNAVAILABLE
    return {"code": overall, "positions": positions, "diversity": div_block}


def _write_counter(path: str | None, count: int) -> None:
    if not path:
        return
    try:
        with open(path, "w", encoding="utf-8") as handle:
            handle.write(str(count))
    except OSError:
        pass


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    env = dict(os.environ)
    if args.command == "run":
        state = _cmd_run(args, env)
    elif args.command == "preset":
        state = _cmd_preset(args, env)
    else:  # pragma: no cover - argparse enforces a valid subcommand
        return 2
    _emit(state)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
