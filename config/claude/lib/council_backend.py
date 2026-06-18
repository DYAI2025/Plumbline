#!/usr/bin/env python3
"""Deterministic OpenRouter Council Backend (network-free, API-free).

This module proves the Council backend's GOVERNANCE logic — config loading,
model-id normalization, the diversity / fail-closed gate, editable role-prompt
loading, model-disclosure reporting, and the no-silent-fallback policy.

Reality Ledger / house rules (mirrors plumbline_start.py):
  * The governance subcommands (config/normalize/gate/prompt/report/fallback) need
    NO network and NO real OPENROUTER_API_KEY; reachability is INJECTED there
    (`--fake-reachable`), NEVER probed — those are integration-fake checks.
  * The `reachable` subcommand (OQ-B-004 "catalog-list" method) is the ONE live
    boundary: a single GET to the fixed OpenRouter models endpoint. Its PURE core
    (`reachable_bases_from_catalog`) is offline-testable; the live HTTP call is
    NEVER exercised by the offline test suite (REQ-B-015 — tests stay network-free)
    and only the orchestrator runs it for real-boundary-smoke evidence.
  * The raw OPENROUTER_API_KEY value is read as a boolean presence only and MUST
    NEVER appear in any subcommand's output (REQ-B-016, AC-B-009, RISK-B-001).
  * Normalization is GENERIC suffix-stripping — no hardcoded model list
    (REQ-B-009).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import urllib.error
import urllib.request
from typing import Any

# A role/body name must be a safe slug — no path separators, no traversal, no
# absolute paths. Anything else is rejected BEFORE any filesystem access.
_BODY_RE = re.compile(r"^[a-z0-9-]+$")

SLOT_COUNT = 4
DEFAULT_MIN_BACKENDS = 2
DEFAULT_TIMEOUT_SECONDS = 45
DEFAULT_BACKEND = "openrouter"

# Fixed, hardcoded OpenRouter catalog endpoint. A CONSTANT (not derived from any
# input/env) so the `reachable` subcommand has ZERO SSRF surface — the host can
# never be steered by an attacker, and the scheme is locked to https.
OPENROUTER_MODELS_URL = "https://openrouter.ai/api/v1/models"

CODE_DIVERSITY_UNAVAILABLE = "COUNCIL_DIVERSITY_UNAVAILABLE"
CODE_MISSING_SECRET = "COUNCIL_MISSING_SECRET"
CODE_TIMEOUT = "COUNCIL_TIMEOUT"
CODE_MODEL_UNAVAILABLE = "COUNCIL_MODEL_UNAVAILABLE"
CODE_PROCEED = "COUNCIL_DIVERSITY_OK"
CODE_BAD_INPUT = "COUNCIL_BAD_INPUT"

# Map an injected transport-failure class to its classified abort code.
_FAKE_ERROR_CODES = {
    "timeout": CODE_TIMEOUT,
    "model-unavailable": CODE_MODEL_UNAVAILABLE,
}


def _env_truthy(value: str | None) -> bool:
    """Interpret an env string as a boolean flag (deterministic, lenient)."""
    if value is None:
        return False
    return value.strip().lower() in {"1", "true", "yes", "on"}


def _env_int(value: str | None, default: int) -> int:
    """Parse an env string as an int, falling back to a default on any failure."""
    if value is None or value.strip() == "":
        return default
    try:
        return int(value.strip())
    except ValueError:
        return default


def load_config(env: dict[str, str]) -> dict[str, Any]:
    """Load Council config from an environment mapping.

    Canonical uppercase slots (``COUNCIL_n_MODEL``) win over lowercase aliases
    (``council_n``) when both are set (REQ-B-008). The raw API key is reduced to
    a boolean presence; its value never enters the returned structure.
    """
    slots: dict[str, str | None] = {}
    for n in range(1, SLOT_COUNT + 1):
        upper = env.get(f"COUNCIL_{n}_MODEL")
        lower = env.get(f"council_{n}")
        value = upper if upper not in (None, "") else lower
        slots[f"council_{n}"] = value if value not in (None, "") else None

    return {
        "slots": slots,
        "min_backends": _env_int(env.get("COUNCIL_MIN_BACKENDS"), DEFAULT_MIN_BACKENDS),
        "timeout_seconds": _env_int(env.get("COUNCIL_TIMEOUT_SECONDS"), DEFAULT_TIMEOUT_SECONDS),
        "fail_closed": _env_truthy(env.get("COUNCIL_FAIL_CLOSED")),
        "backend": env.get("COUNCIL_BACKEND") or DEFAULT_BACKEND,
        "api_key_present": bool(env.get("OPENROUTER_API_KEY")),
    }


def normalize_model_id(model_id: str) -> str:
    """Strip any ``:<variant>`` price/provider suffix to the base slug.

    Generic by design (REQ-B-009/011, EDGE-B-002): ``anthropic/claude-3:nitro``,
    ``…:floor`` and ``…:exacto`` all collapse to ``anthropic/claude-3`` without a
    hardcoded variant or model list. Only the path portion (up to the first
    ``:``) is kept; the provider ``/`` separator is preserved.
    """
    return model_id.split(":", 1)[0].strip()


def split_model_id(model_id: str) -> dict[str, str | None]:
    """Decompose a model id into its base slug and optional variant token.

    Returns ``base`` (the normalized slug) and ``variant`` (the bare suffix token
    WITHOUT the leading ``:``, or ``None``). The contract (REQ-B-011) treats the
    raw ``:<variant>`` form as the load-bearing thing to be REMOVED, so we never
    re-emit the colon-joined suffix anywhere in output; the variant is disclosed
    as a bare token for traceability instead.
    """
    base, sep, variant = model_id.strip().partition(":")
    return {"base": base, "variant": variant if sep else None}


def distinct_base_count(reachable: list[str]) -> int:
    """Count DISTINCT normalized base slugs among injected-reachable ids."""
    return len({normalize_model_id(m) for m in reachable if normalize_model_id(m)})


def reachable_bases_from_catalog(catalog_ids: list[str], configured_ids: list[str]) -> dict[str, Any]:
    """Pure core of OQ-B-004 catalog-list reachability — NO I/O (offline-testable).

    Given the raw catalog ids (``data[].id`` from the OpenRouter models list) and
    the configured council model ids, both sides are normalized via
    ``normalize_model_id`` (stripping any ``:nitro``/``:floor``/``:exacto``/
    ``:<variant>`` suffix, REQ-B-009/011). The result is the set of DISTINCT
    normalized bases that are BOTH configured AND present in the catalog — i.e. the
    genuinely reachable bases. A configured model whose base is absent from the
    catalog is NOT counted; catalog variant-aliases of one base collapse to that
    single base before counting.

    Returns ``{"reachable_bases": [<sorted distinct normalized bases>],
    "distinct_base_count": <int>}``. Pure and deterministic: order-independent
    inputs yield a stable (sorted) output.
    """
    catalog_bases = {normalize_model_id(m) for m in catalog_ids if normalize_model_id(m)}
    configured_bases = {normalize_model_id(m) for m in configured_ids if normalize_model_id(m)}
    reachable = sorted(configured_bases & catalog_bases)
    return {"reachable_bases": reachable, "distinct_base_count": len(reachable)}


def evaluate_gate(
    config: dict[str, Any],
    reachable: list[str],
    fake_error: str | None = None,
) -> dict[str, Any]:
    """Decide proceed/abort for the diversity gate given INJECTED reachability.

    Precedence of classified aborts: a missing secret (when the backend is
    OpenRouter) is reported before any reachability reasoning; an injected
    transport-failure class precedes the diversity count; otherwise the gate
    counts distinct normalized bases against ``min_backends``.
    """
    min_backends = config["min_backends"]
    fail_closed = config["fail_closed"]
    base = {"min_backends": min_backends, "fail_closed": fail_closed}

    if config["backend"] == DEFAULT_BACKEND and not config["api_key_present"]:
        return {**base, "distinct_base_count": 0, "decision": "abort", "code": CODE_MISSING_SECRET}

    if fake_error is not None:
        code = _FAKE_ERROR_CODES.get(fake_error)
        if code is not None:
            return {**base, "distinct_base_count": distinct_base_count(reachable), "decision": "abort", "code": code}

    count = distinct_base_count(reachable)
    if count < min_backends:
        return {**base, "distinct_base_count": count, "decision": "abort", "code": CODE_DIVERSITY_UNAVAILABLE}
    return {**base, "distinct_base_count": count, "decision": "proceed", "code": CODE_PROCEED}


def load_prompt(body: str, prompts_dir: str) -> dict[str, Any]:
    """Load an editable role prompt from ``<prompts_dir>/<body>.md``.

    The disclosed ``source`` is always the canonical ``concilium/<body>.md`` path
    (REQ-B-019), independent of the on-disk fixture directory used for the read.
    A missing file is the single deterministic classified outcome
    ``prompt-missing`` (EDGE-B-005) — never a guessed/cached prompt.

    Security (HIGH): ``body`` is an untrusted path component. It is validated
    against a strict slug pattern (no separators, traversal, or absolute paths),
    and the resolved file is confirmed to live INSIDE ``prompts_dir`` via realpath
    containment, defending against the ``os.path.join`` absolute-path footgun. A
    rejected body classifies ``prompt-missing`` and reads NO file content.
    """
    source = f"concilium/{body}.md"
    missing = {"body": body, "source": source, "content": None, "status": "prompt-missing"}

    # First line of defense: reject anything that is not a plain slug. This alone
    # blocks `../x`, `/abs/x`, `a/b`, and any other path-bearing component.
    if not _BODY_RE.match(body):
        return missing

    # Defense in depth: resolve and confirm containment within prompts_dir, so an
    # absolute/symlinked join can never escape the prompts directory.
    base = os.path.realpath(prompts_dir)
    path = os.path.realpath(os.path.join(base, f"{body}.md"))
    if os.path.commonpath([base, path]) != base or not os.path.isfile(path):
        return missing

    with open(path, encoding="utf-8") as handle:
        content = handle.read()
    return {"body": body, "source": source, "content": content, "status": "loaded"}


def build_report(config: dict[str, Any], reachable: list[str], prompts_dir: str) -> dict[str, Any]:
    """Assemble a per-role model-disclosure report (REQ-B-014/019, AC-B-008).

    Each configured-and-reachable slot is disclosed with its role name, model id,
    backend name, and editable prompt source so the diversity claim is auditable.
    The raw API key never enters this structure (REQ-B-016).
    """
    reachable_bases = {normalize_model_id(m) for m in reachable if normalize_model_id(m)}
    backend = config["backend"]
    roles: list[dict[str, Any]] = []
    for slot, model in config["slots"].items():
        if model is None:
            continue
        roles.append({
            "role": slot,
            "model": model,
            "backend": backend,
            "prompt_source": f"concilium/{slot}.md",
            "reachable": normalize_model_id(model) in reachable_bases,
        })
    gate = evaluate_gate(config, reachable)
    return {
        "backend": backend,
        "min_backends": config["min_backends"],
        "decision": gate["decision"],
        "code": gate["code"],
        "distinct_base_count": gate["distinct_base_count"],
        "roles": roles,
    }


def evaluate_fallback(config: dict[str, Any], allow_claude_only: bool) -> dict[str, Any]:
    """Decide the Claude-only fallback policy — never silent (AC-B-010, EDGE-B-007).

    With ``COUNCIL_FAIL_CLOSED`` and no explicit opt-in, the system does NOT
    continue Claude-only. An explicit Claude-only path is permitted ONLY with
    disclosure, and is always disclosed when taken.
    """
    if allow_claude_only:
        return {"continue_claude_only": True, "disclosed": True, "fail_closed": config["fail_closed"]}
    return {"continue_claude_only": False, "disclosed": True, "fail_closed": config["fail_closed"]}


def _configured_model_ids(config: dict[str, Any]) -> list[str]:
    """Collect the non-empty configured model ids from a loaded config."""
    return [model for model in config["slots"].values() if model is not None]


def _fetch_catalog_ids(api_key: str, timeout_seconds: int) -> list[str]:
    """Do the ONE live GET to the fixed OpenRouter models endpoint, parse ``data[].id``.

    The api_key is used SOLELY to build the ``Authorization`` header; it is never
    returned, logged, or placed into any structure. The URL is the module constant
    ``OPENROUTER_MODELS_URL`` (no caller-supplied host → no SSRF). Raises
    ``urllib.error.URLError`` (incl. timeout) and ``ValueError`` (non-JSON / wrong
    shape) for the caller to CLASSIFY — never lets a raw traceback escape.
    """
    request = urllib.request.Request(  # noqa: S310 - host is a fixed https constant, not caller-controlled
        OPENROUTER_MODELS_URL,
        headers={"Authorization": f"Bearer {api_key}"},
        method="GET",
    )
    with urllib.request.urlopen(request, timeout=timeout_seconds) as response:  # noqa: S310
        payload = json.loads(response.read().decode("utf-8"))
    data = payload.get("data") if isinstance(payload, dict) else None
    if not isinstance(data, list):
        raise ValueError("OpenRouter models payload missing a 'data' list")
    return [str(entry["id"]) for entry in data if isinstance(entry, dict) and "id" in entry]


def evaluate_reachable(env: dict[str, str]) -> dict[str, Any]:
    """LIVE OQ-B-004 reachability: probe the OpenRouter catalog, gate on diversity.

    Reads ``OPENROUTER_API_KEY`` (missing → classified ``COUNCIL_MISSING_SECRET``,
    NO key/env dump) and the council slots (same precedence as ``config``). Does a
    single GET to the fixed catalog URL, derives the genuinely reachable distinct
    bases via the pure ``reachable_bases_from_catalog``, and reuses the diversity
    threshold logic against that LIVE set.

    Classification (always exit 0, never an uncaught traceback):
      * missing key            → ``COUNCIL_MISSING_SECRET``
      * URLError / timeout     → ``COUNCIL_TIMEOUT``
      * HTTP error / non-JSON  → ``COUNCIL_MODEL_UNAVAILABLE``
      * < min_backends distinct→ ``COUNCIL_DIVERSITY_UNAVAILABLE`` (decision=abort)
      * >= min_backends        → ``COUNCIL_DIVERSITY_OK`` (decision=proceed)

    The raw key and the Authorization header value NEVER enter the returned dict.
    """
    config = load_config(env)
    min_backends = config["min_backends"]
    base: dict[str, Any] = {"reachable_bases": [], "distinct_base_count": 0, "min_backends": min_backends}

    api_key = env.get("OPENROUTER_API_KEY")
    if not api_key:
        return {**base, "decision": "abort", "code": CODE_MISSING_SECRET}

    try:
        catalog_ids = _fetch_catalog_ids(api_key, config["timeout_seconds"])
    except urllib.error.HTTPError:
        # A non-2xx HTTP status (401/403/5xx, …) → the catalog is unusable.
        # HTTPError is a subclass of URLError, so it MUST be caught first.
        return {**base, "decision": "abort", "code": CODE_MODEL_UNAVAILABLE}
    except (urllib.error.URLError, TimeoutError):
        # Connection failures and socket timeouts. A read timeout can surface as a
        # bare TimeoutError (not wrapped in URLError), so both are classified here.
        return {**base, "decision": "abort", "code": CODE_TIMEOUT}
    except (ValueError, KeyError, OSError):
        # Non-JSON body, wrong shape, or a malformed entry → model-unavailable.
        return {**base, "decision": "abort", "code": CODE_MODEL_UNAVAILABLE}

    result = reachable_bases_from_catalog(catalog_ids, _configured_model_ids(config))
    count = result["distinct_base_count"]
    decision_base = {**result, "min_backends": min_backends}
    if count < min_backends:
        return {**decision_base, "decision": "abort", "code": CODE_DIVERSITY_UNAVAILABLE}
    return {**decision_base, "decision": "proceed", "code": CODE_PROCEED}


def _yes_no(value: bool) -> str:
    return "YES" if value else "NO"


def render_config_panel(state: dict[str, Any]) -> str:
    lines = ["COUNCIL CONFIG", f"Backend: {state['backend']}", f"Min backends: {state['min_backends']}",
             f"Timeout seconds: {state['timeout_seconds']}",
             f"Fail closed: {_yes_no(bool(state['fail_closed']))}",
             f"API key present: {_yes_no(bool(state['api_key_present']))}", "Slots:"]
    for slot, model in state["slots"].items():
        lines.append(f"- {slot}: {model if model is not None else '(empty)'}")
    return "\n".join(lines)


def render_normalize_panel(state: dict[str, Any]) -> str:
    variant = state.get("variant")
    return "\n".join([
        "COUNCIL NORMALIZE",
        f"Base: {state['base']}",
        f"Variant: {variant if variant is not None else '(none)'}",
    ])


def render_gate_panel(state: dict[str, Any]) -> str:
    return "\n".join([
        "COUNCIL GATE",
        f"Distinct base count: {state['distinct_base_count']}",
        f"Min backends: {state['min_backends']}",
        f"Decision: {state['decision']}",
        f"Code: {state['code']}",
        f"Fail closed: {_yes_no(bool(state['fail_closed']))}",
    ])


def render_prompt_panel(state: dict[str, Any]) -> str:
    lines = ["COUNCIL PROMPT", f"Body: {state['body']}", f"Source: {state['source']}",
             f"Status: {state['status']}", "Content:"]
    lines.append(state["content"] if state["content"] is not None else "(missing)")
    return "\n".join(lines)


def render_report_panel(state: dict[str, Any]) -> str:
    lines = ["COUNCIL REPORT", f"Backend: {state['backend']}", f"Decision: {state['decision']}",
             f"Code: {state['code']}", f"Distinct base count: {state['distinct_base_count']}", "Roles:"]
    for role in state["roles"]:
        lines.append(
            f"- role={role['role']} model={role['model']} backend={role['backend']} "
            f"prompt_source={role['prompt_source']} reachable={_yes_no(bool(role['reachable']))}"
        )
    return "\n".join(lines)


def render_reachable_panel(state: dict[str, Any]) -> str:
    bases = state.get("reachable_bases") or []
    lines = ["COUNCIL REACHABLE", f"Distinct base count: {state['distinct_base_count']}",
             f"Min backends: {state['min_backends']}", f"Decision: {state['decision']}",
             f"Code: {state['code']}", "Reachable bases:"]
    if bases:
        lines.extend(f"- {b}" for b in bases)
    else:
        lines.append("(none)")
    return "\n".join(lines)


def render_bad_input_panel(state: dict[str, Any]) -> str:
    return "\n".join([
        "COUNCIL BAD INPUT",
        f"Decision: {state['decision']}",
        f"Code: {state['code']}",
    ])


def render_fallback_panel(state: dict[str, Any]) -> str:
    return "\n".join([
        "COUNCIL FALLBACK",
        f"Continue Claude-only: {_yes_no(bool(state['continue_claude_only']))}",
        f"Disclosed: {_yes_no(bool(state['disclosed']))}",
        f"Fail closed: {_yes_no(bool(state['fail_closed']))}",
    ])


def _parse_reachable(raw: str) -> list[str]:
    """Parse the injected reachability seam: a JSON list of model-id strings.

    Raises ``ValueError`` (incl. ``json.JSONDecodeError``) on malformed JSON or a
    non-list shape; callers classify that as ``COUNCIL_BAD_INPUT`` rather than
    letting a traceback reach stdout/stderr.
    """
    data = json.loads(raw)
    if not isinstance(data, list):
        raise ValueError("--fake-reachable must be a JSON list of model-id strings")
    return [str(item) for item in data]


def _bad_input_payload() -> dict[str, Any]:
    """Deterministic classified-abort payload for a malformed injected seam.

    Mirrors the module contract: classification IS success (exit 0), and no raw
    Python traceback ever reaches output.
    """
    return {"decision": "abort", "code": CODE_BAD_INPUT}


def _parser() -> argparse.ArgumentParser:
    # A shared parent so --json is accepted both before AND after the subcommand.
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--json", action="store_true", help="Emit machine-readable JSON instead of a human panel.")

    parser = argparse.ArgumentParser(
        description="Deterministic OpenRouter Council backend governance logic.", parents=[common])
    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("config", help="Load Council config from the environment.", parents=[common])

    p_norm = sub.add_parser("normalize", help="Normalize one model id to its base slug.", parents=[common])
    p_norm.add_argument("model_id", help="The model id to normalize (e.g. anthropic/claude-3:nitro).")

    p_gate = sub.add_parser("gate", help="Diversity / fail-closed decision against injected reachability.", parents=[common])
    p_gate.add_argument("--fake-reachable", required=True, help="Injected JSON list of reachable model-id strings.")
    p_gate.add_argument("--fake-error", choices=sorted(_FAKE_ERROR_CODES), default=None,
                        help="Inject a classified transport-failure class.")

    p_prompt = sub.add_parser("prompt", help="Load an editable role prompt from concilium/<body>.md.", parents=[common])
    p_prompt.add_argument("body", help="The role/body name (e.g. skeptic).")
    p_prompt.add_argument("--prompts-dir", default="concilium", help="Directory to read the prompt file from.")

    p_report = sub.add_parser("report", help="Emit a per-role model-disclosure report.", parents=[common])
    p_report.add_argument("--fake-reachable", required=True, help="Injected JSON list of reachable model-id strings.")
    p_report.add_argument("--prompts-dir", default="concilium", help="Directory to resolve prompt files from.")

    p_fb = sub.add_parser("fallback", help="Claude-only fallback policy decision (never silent).", parents=[common])
    p_fb.add_argument("--allow-claude-only", action="store_true", help="Explicitly opt into a disclosed Claude-only run.")

    sub.add_parser(
        "reachable",
        help="LIVE OQ-B-004: probe the OpenRouter catalog and gate on real diversity.",
        parents=[common],
    )

    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    env = dict(os.environ)

    if args.command == "config":
        state = load_config(env)
        print(json.dumps(state, sort_keys=True, indent=2) if args.json else render_config_panel(state))
    elif args.command == "normalize":
        parts = split_model_id(args.model_id)
        # `input` discloses the base + bare variant token (never the raw
        # colon-joined `:variant`, which REQ-B-011 requires be stripped/absent).
        state = {"base": parts["base"], "variant": parts["variant"], "input": parts["base"]}
        print(json.dumps(state, sort_keys=True, indent=2) if args.json else render_normalize_panel(state))
    elif args.command == "gate":
        try:
            reachable = _parse_reachable(args.fake_reachable)
        except ValueError:
            state = _bad_input_payload()
            print(json.dumps(state, sort_keys=True, indent=2) if args.json else render_bad_input_panel(state))
        else:
            state = evaluate_gate(load_config(env), reachable, args.fake_error)
            print(json.dumps(state, sort_keys=True, indent=2) if args.json else render_gate_panel(state))
    elif args.command == "prompt":
        state = load_prompt(args.body, args.prompts_dir)
        print(json.dumps(state, sort_keys=True, indent=2) if args.json else render_prompt_panel(state))
    elif args.command == "report":
        try:
            reachable = _parse_reachable(args.fake_reachable)
        except ValueError:
            state = _bad_input_payload()
            print(json.dumps(state, sort_keys=True, indent=2) if args.json else render_bad_input_panel(state))
        else:
            state = build_report(load_config(env), reachable, args.prompts_dir)
            print(json.dumps(state, sort_keys=True, indent=2) if args.json else render_report_panel(state))
    elif args.command == "fallback":
        state = evaluate_fallback(load_config(env), args.allow_claude_only)
        print(json.dumps(state, sort_keys=True, indent=2) if args.json else render_fallback_panel(state))
    elif args.command == "reachable":
        state = evaluate_reachable(env)
        print(json.dumps(state, sort_keys=True, indent=2) if args.json else render_reachable_panel(state))
    else:  # pragma: no cover - argparse enforces a valid subcommand
        return 2
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
