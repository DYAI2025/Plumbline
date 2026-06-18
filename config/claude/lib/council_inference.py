#!/usr/bin/env python3
"""Deterministic, governed OpenRouter INFERENCE path (Slice 1 — offline-testable).

This module is the inference analogue of OD-3's ``council_backend.py``: it adds a
real, single ``POST https://openrouter.ai/api/v1/chat/completions`` call behind
hard, fail-closed, token-only budget guardrails, and classifies every outcome
into a distinct ``COUNCIL_*`` code instead of leaking a raw traceback.

Reality Ledger / house rules (mirrors council_backend.py):
  * The pure inference logic (estimate → cap-check → request-build → classify) is
    exercised entirely OFFLINE via an INJECTED transport seam (REQ-INF-015). The
    offline suite NEVER performs a real ``urlopen`` — a transport-reaching run
    REQUIRES one of ``--inject-response`` / ``--inject-error``; the real POST runs
    ONLY when neither injection flag is given (never in the offline suite). These
    offline checks are ``integration-fake`` and prove NO real invocability.
  * The raw ``OPENROUTER_API_KEY`` is read as boolean presence and placed ONLY in
    the ``Authorization: Bearer <key>`` header inside the real transport. It MUST
    NEVER appear in any returned structure, error, request-echo, or output
    (REQ-INF-011, NFR-INF-001) — ``--build-only`` deliberately omits the header.
  * Classification IS success: every classified outcome is exit-0 (REQ-INF-014).
  * ``input_token_estimate`` is a NAMED offline heuristic (I-3), ``ableitbar`` not
    ``belegt`` — NOT the provider's native tokenizer and NOT a billing oracle. Its
    drift against the real ``usage.prompt_tokens`` is exposed so it is MEASURABLE.
  * The response ``usage`` shape is ``ungeprüft`` (OQ-3): absent/misshaped usage,
    or a 2xx with no usable completion, classifies ``COUNCIL_MODEL_UNAVAILABLE``
    (I-1, I-2) — never a crash, never fabricated numbers, never a false success. A
    response ``cost`` field is NEVER assumed present and NEVER relied on.
"""
from __future__ import annotations

import argparse
import json
import os
from typing import Any, Callable

# Fixed, hardcoded OpenRouter chat/completions endpoint. A CONSTANT (never derived
# from any input/env) so the inference path has ZERO SSRF surface — the host can
# never be steered by a caller, and the scheme is locked to https (REQ-INF-002).
OPENROUTER_CHAT_URL = "https://openrouter.ai/api/v1/chat/completions"

DEFAULT_TIMEOUT_SECONDS = 45
DEFAULT_MAX_TOKENS_PER_RUN = 20000
# A FREE OpenRouter model id used only as the default. Per REQ-INF-010 this is NOT
# asserted stable-true; its availability is runtime-verified, never hardcoded truth.
DEFAULT_INFERENCE_MODEL = "meta-llama/llama-3.1-8b-instruct:free"

CODE_OK = "COUNCIL_INFERENCE_OK"
CODE_BUDGET_EXCEEDED = "COUNCIL_BUDGET_EXCEEDED"
CODE_MISSING_SECRET = "COUNCIL_MISSING_SECRET"
CODE_INSUFFICIENT_CREDIT = "COUNCIL_INSUFFICIENT_CREDIT"
CODE_RATE_LIMITED = "COUNCIL_RATE_LIMITED"
CODE_MODEL_UNAVAILABLE = "COUNCIL_MODEL_UNAVAILABLE"
CODE_TIMEOUT = "COUNCIL_TIMEOUT"


def _env_int(value: str | None, default: int) -> int:
    """Parse an env string as an int, falling back to a default on any failure."""
    if value is None or value.strip() == "":
        return default
    try:
        return int(value.strip())
    except ValueError:
        return default


def estimate_input_tokens(messages: list[dict[str, Any]]) -> int:
    """NAMED offline input-token heuristic (I-3) — approximate, NOT exact.

    This is an in-process, deterministic GUARD: roughly one token per four
    characters of message content (a documented char-based heuristic). It is
    ``ableitbar`` (approximate), NOT the provider's native tokenizer and NOT a
    billed-token oracle. The CLI lets the test inject an exact value so the
    cap/estimate math is falsifiable independent of any tokenizer choice; this
    function is the fallback when no explicit estimate is supplied.
    """
    chars = 0
    for message in messages:
        if isinstance(message, dict):
            content = message.get("content")
            if isinstance(content, str):
                chars += len(content)
    return (chars + 3) // 4


def estimate_total_tokens(input_estimate: int, max_tokens: int) -> int:
    """Pre-call total estimate = input_token_estimate + max_tokens (REQ-INF-005)."""
    return input_estimate + max_tokens


def build_estimate(input_estimate: int, max_tokens: int, cap: int) -> dict[str, Any]:
    """Assemble the labeled-approximate pre-call estimate block (REQ-INF-005)."""
    return {
        "input_token_estimate": input_estimate,
        "max_tokens": max_tokens,
        "total_estimate": estimate_total_tokens(input_estimate, max_tokens),
        "approximate": True,
        "cap": cap,
    }


def build_request_body(model: str, messages: list[dict[str, Any]], max_tokens: int) -> dict[str, Any]:
    """Build the chat/completions request body — ALWAYS with explicit max_tokens.

    [CRITICAL/REQ-INF-004] There is NO branch that omits ``max_tokens``: a capped
    call without a sent ``max_tokens`` is unenforceable theatre and is FORBIDDEN.
    The raw API key is NOT part of the body (it lives only in the Authorization
    header), so this body is safe to echo via ``--build-only``.
    """
    return {"model": model, "messages": messages, "max_tokens": max_tokens}


def _base_result(decision: str, code: str, estimate: dict[str, Any]) -> dict[str, Any]:
    """The stable result skeleton every inference outcome shares (REQ-INF-019)."""
    return {
        "decision": decision,
        "code": code,
        "estimate": estimate,
        "completion": None,
        "usage": None,
        "retry_after": None,
    }


def _reconcile_usage(usage: Any, input_estimate: int) -> dict[str, Any] | None:
    """Reconcile real ``usage`` counts against the input heuristic (I-1, I-3).

    Returns the reconciliation block on a well-shaped ``usage`` object, or ``None``
    when ``usage`` is absent/misshaped (the caller then classifies
    ``COUNCIL_MODEL_UNAVAILABLE`` — no crash, no fabricated numbers). The shape is
    ``ungeprüft`` (OQ-3), so it is validated, never assumed. A ``cost`` field is
    never required and never read.
    """
    if not isinstance(usage, dict):
        return None
    prompt_tokens = usage.get("prompt_tokens")
    completion_tokens = usage.get("completion_tokens")
    if not isinstance(prompt_tokens, int) or isinstance(prompt_tokens, bool):
        return None
    if not isinstance(completion_tokens, int) or isinstance(completion_tokens, bool):
        return None
    return {
        "prompt_tokens": prompt_tokens,
        "completion_tokens": completion_tokens,
        "input_token_estimate": input_estimate,
        # I-3: the heuristic's MEASURED drift vs. the real prompt_tokens, exposed
        # so the estimate's fidelity is falsifiable (not silently swallowed). Per
        # the result-schema contract the sign is prompt_tokens - input_token_estimate
        # (a positive drift means the heuristic UNDER-counted the real prompt).
        "input_estimate_drift": prompt_tokens - input_estimate,
    }


def _extract_completion(payload: Any) -> str | None:
    """Extract the completion text from a parsed 2xx body, or ``None`` (I-2).

    A 2xx body that parses as JSON but lacks a usable completion (missing/empty
    ``choices[].message.content``, or an ``{"error": ...}`` envelope) is NOT a
    success — it returns ``None`` so the caller classifies
    ``COUNCIL_MODEL_UNAVAILABLE`` and never sells an empty/error body as an answer.
    """
    if not isinstance(payload, dict):
        return None
    if "error" in payload:
        return None
    choices = payload.get("choices")
    if not isinstance(choices, list) or not choices:
        return None
    first = choices[0]
    if not isinstance(first, dict):
        return None
    message = first.get("message")
    if not isinstance(message, dict):
        return None
    content = message.get("content")
    if not isinstance(content, str) or content == "":
        return None
    return content


def _classify_response(
    body: str, input_estimate: int, estimate: dict[str, Any]
) -> dict[str, Any]:
    """Classify a fake/real HTTP 200 BODY into a result (I-1, I-2, REQ-INF-009).

    Non-JSON → unavailable; usable completion + well-shaped usage → OK; a 2xx with
    no usable completion OR absent/misshaped usage → ``COUNCIL_MODEL_UNAVAILABLE``.
    """
    try:
        payload = json.loads(body)
    except (ValueError, TypeError):
        return _base_result("abort", CODE_MODEL_UNAVAILABLE, estimate)

    completion = _extract_completion(payload)
    if completion is None:
        return _base_result("abort", CODE_MODEL_UNAVAILABLE, estimate)

    usage_block = _reconcile_usage(
        payload.get("usage") if isinstance(payload, dict) else None, input_estimate
    )
    if usage_block is None:
        return _base_result("abort", CODE_MODEL_UNAVAILABLE, estimate)

    result = _base_result("proceed", CODE_OK, estimate)
    result["completion"] = completion
    result["usage"] = usage_block
    return result


# Map an injected transport-error class to its classified outcome. 429 carries a
# recorded Retry-After (never acted on); each class is DISTINCT (REQ-INF-012).
_INJECT_ERROR_CODES = {
    "http-402": CODE_INSUFFICIENT_CREDIT,
    "http-429": CODE_RATE_LIMITED,
    "http-500": CODE_MODEL_UNAVAILABLE,
    "timeout": CODE_TIMEOUT,
    "malformed": CODE_MODEL_UNAVAILABLE,
}


def resolve_model(env: dict[str, str], cli_model: str | None) -> str:
    """Resolve the model id: --model > COUNCIL_INFERENCE_MODEL > free default."""
    if cli_model:
        return cli_model
    configured = env.get("COUNCIL_INFERENCE_MODEL")
    if configured:
        return configured
    return DEFAULT_INFERENCE_MODEL


def _real_transport(api_key: str, body: dict[str, Any], timeout_seconds: int) -> dict[str, Any]:
    """Do the ONE real POST to the fixed chat/completions URL (REQ-INF-001/003).

    stdlib ``urllib`` only — no SDK, no auto-retry. The api_key is used SOLELY to
    build the ``Authorization`` header; it is never returned or logged. The URL is
    the module constant (no caller-supplied host → no SSRF). Imports are local so
    the offline-injected paths never even touch the network module. Returns a dict
    classifying the outcome; the caller never sees a raw traceback.

    NOTE: This is reached ONLY when no injection flag is supplied, i.e. NEVER in
    the offline suite. It is ``RED(confidence)`` until the env-gated real smoke.
    """
    import urllib.error
    import urllib.request

    estimate_holder: dict[str, Any] = body.pop("_estimate")  # type: ignore[assignment]
    input_estimate: int = body.pop("_input_estimate")  # type: ignore[assignment]
    data = json.dumps(body).encode("utf-8")
    request = urllib.request.Request(  # noqa: S310 - host is a fixed https constant
        OPENROUTER_CHAT_URL,
        data=data,
        headers={
            "Authorization": f"Bearer {api_key}",
            "Content-Type": "application/json",
        },
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=timeout_seconds) as response:  # noqa: S310
            raw = response.read().decode("utf-8")
    except urllib.error.HTTPError as exc:  # non-2xx — classify by status, never leak
        if exc.code == 402:
            return _base_result("abort", CODE_INSUFFICIENT_CREDIT, estimate_holder)
        if exc.code == 429:
            result = _base_result("abort", CODE_RATE_LIMITED, estimate_holder)
            retry_after = exc.headers.get("Retry-After") if exc.headers else None
            result["retry_after"] = retry_after
            return result
        return _base_result("abort", CODE_MODEL_UNAVAILABLE, estimate_holder)
    except (urllib.error.URLError, TimeoutError):
        return _base_result("abort", CODE_TIMEOUT, estimate_holder)
    except OSError:
        return _base_result("abort", CODE_TIMEOUT, estimate_holder)
    return _classify_response(raw, input_estimate, estimate_holder)


def run_inference(
    env: dict[str, str],
    *,
    model: str | None,
    messages: list[dict[str, Any]],
    max_tokens: int,
    input_estimate: int,
    dry_run: bool,
    build_only: bool,
    inject_response: str | None,
    inject_error: str | None,
    inject_retry_after: str | None,
    transport: Callable[[str, dict[str, Any], int], dict[str, Any]] | None = None,
    on_transport_call: Callable[[], None] | None = None,
) -> dict[str, Any]:
    """The stable, reusable inference entrypoint (REQ-INF-019).

    Order is fail-closed by construction (NFR-INF-007): resolve → estimate →
    cap-check → key-check → (only then) transport. Every branch returns the stable
    result skeleton; classification is always exit-0 at the CLI boundary.
    ``on_transport_call`` is invoked exactly once per real transport invocation so
    the test can prove zero/one calls.
    """
    cap = _env_int(env.get("COUNCIL_MAX_TOKENS_PER_RUN"), DEFAULT_MAX_TOKENS_PER_RUN)
    timeout_seconds = _env_int(env.get("COUNCIL_TIMEOUT_SECONDS"), DEFAULT_TIMEOUT_SECONDS)
    resolved_model = resolve_model(env, model)
    estimate = build_estimate(input_estimate, max_tokens, cap)
    request_body = build_request_body(resolved_model, messages, max_tokens)

    # --build-only: emit the body that WOULD be sent. No transport, no key needed.
    if build_only:
        result = _base_result("dry-run", CODE_OK, estimate)
        result["request_body"] = request_body
        return result

    # Dry-run: return the estimate, spend nothing, work without a key (no call to
    # authorize) — REQ-INF-008.
    if dry_run:
        return _base_result("dry-run", CODE_OK, estimate)

    # [SEC] A non-positive max_tokens is rejected BEFORE the cap/transport: an
    # unbounded/negative output cap is not an enforceable budget, and a negative
    # value would shrink total_estimate UNDER the cap and slip a call through. Fail
    # closed with ZERO transport calls — never a success, never a traceback.
    if max_tokens <= 0:
        return _base_result("abort", CODE_MODEL_UNAVAILABLE, estimate)

    # Cap enforced BEFORE the network call. == cap is within cap (proceeds);
    # strictly over the cap aborts fail-closed with ZERO transport calls.
    if estimate["total_estimate"] > cap:
        return _base_result("abort", CODE_BUDGET_EXCEEDED, estimate)

    # Real (non-dry-run) call requires a key. Missing → classified, ZERO calls,
    # no env dump (REQ-INF-011).
    api_key = env.get("OPENROUTER_API_KEY")
    if not api_key:
        return _base_result("abort", CODE_MISSING_SECRET, estimate)

    # Injected transport seam (offline suite): exactly ONE invocation, no retry.
    if inject_error is not None:
        if on_transport_call is not None:
            on_transport_call()
        code = _INJECT_ERROR_CODES.get(inject_error, CODE_MODEL_UNAVAILABLE)
        result = _base_result("abort", code, estimate)
        if code == CODE_RATE_LIMITED:
            result["retry_after"] = inject_retry_after
        return result

    if inject_response is not None:
        if on_transport_call is not None:
            on_transport_call()
        return _classify_response(inject_response, input_estimate, estimate)

    # No injection: in the offline suite this MUST NOT fall through to a real
    # urlopen (REQ-INF-015 reality-ledger guard). Only an explicit real transport
    # callable reaches the network — supplied solely by the live (non-test) path.
    if transport is None:
        # Classified, ZERO calls — proves the offline suite can never spend a credit.
        return _base_result("abort", CODE_MODEL_UNAVAILABLE, estimate)

    if on_transport_call is not None:
        on_transport_call()
    body_for_transport = dict(request_body)
    body_for_transport["_estimate"] = estimate
    body_for_transport["_input_estimate"] = input_estimate
    return transport(api_key, body_for_transport, timeout_seconds)


def _parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--json", action="store_true", help="Emit machine-readable JSON.")

    parser = argparse.ArgumentParser(
        description="Deterministic, governed OpenRouter inference path.", parents=[common])
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("infer", help="Run (or dry-render) a single governed inference call.",
                       parents=[common])
    p.add_argument("--model", default=None, help="Model id (overrides COUNCIL_INFERENCE_MODEL).")
    p.add_argument("--messages", default="[]", help="JSON array of {role,content} message objects.")
    p.add_argument("--max-tokens", type=int, default=256, help="Explicit output cap SENT on the body.")
    p.add_argument("--input-estimate", type=int, default=None,
                   help="Offline input_token_estimate heuristic value (I-3); defaults to the char heuristic.")
    p.add_argument("--dry-run", action="store_true", help="Return the estimate, make NO call.")
    p.add_argument("--build-only", action="store_true", help="Emit the request_body that WOULD be sent.")
    p.add_argument("--live", action="store_true",
                   help="Opt in to the ONE real POST — GATED: only fires when COUNCIL_INFERENCE_LIVE=1 is "
                        "also set in the env (otherwise stays offline-classified). For the env-gated smoke only.")
    p.add_argument("--inject-response", default=None, help="Fake HTTP 200 body (offline transport seam).")
    p.add_argument("--inject-error", choices=sorted(_INJECT_ERROR_CODES), default=None,
                   help="Fake transport failure class (offline transport seam).")
    p.add_argument("--inject-retry-after", default=None, help="Fake Retry-After value paired with http-429.")
    p.add_argument("--inject-call-counter", default=None,
                   help="File to write the transport-invocation count to (proves zero/one calls).")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    env = dict(os.environ)

    if args.command != "infer":  # pragma: no cover - argparse enforces a valid subcommand
        return 2

    # Parse messages defensively — a malformed array classifies, never crashes.
    try:
        messages = json.loads(args.messages)
        if not isinstance(messages, list):
            messages = []
    except (ValueError, TypeError):
        messages = []

    input_estimate = (
        args.input_estimate if args.input_estimate is not None else estimate_input_tokens(messages)
    )

    # The transport-invocation counter: written exactly when a transport is hit
    # (0 for dry-run/build-only/budget-abort/missing-key/no-injection guard).
    call_count = {"n": 0}

    def _bump() -> None:
        call_count["n"] += 1

    # [C1] The real transport is reachable ONLY via the GATED --live opt-in: the
    # flag arms it, but the ENV (COUNCIL_INFERENCE_LIVE=1) is the gate. Without that
    # env set, --live stays transport=None — an offline-classified path that makes
    # ZERO network calls — so the offline suite (which never sets the env) can never
    # reach a real urlopen (REQ-INF-015). No injection overrides the seam first.
    transport = (
        _real_transport
        if args.live and env.get("COUNCIL_INFERENCE_LIVE") == "1"
        else None
    )

    state = run_inference(
        env,
        model=args.model,
        messages=messages,
        max_tokens=args.max_tokens,
        input_estimate=input_estimate,
        dry_run=args.dry_run,
        build_only=args.build_only,
        inject_response=args.inject_response,
        inject_error=args.inject_error,
        inject_retry_after=args.inject_retry_after,
        transport=transport,
        on_transport_call=_bump,
    )

    if args.inject_call_counter:
        try:
            with open(args.inject_call_counter, "w", encoding="utf-8") as handle:
                handle.write(str(call_count["n"]))
        except OSError:
            pass

    # Output is always JSON (the result is a single machine-readable object).
    # --json is still accepted for CLI compatibility but no longer gates the format.
    print(json.dumps(state, sort_keys=True, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
