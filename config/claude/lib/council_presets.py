#!/usr/bin/env python3
"""Typed Concilium PRESETS + dynamic free-model RESOLVER (network-free, key-free).

Companion to ``council_backend.py`` (governance) and ``council_inference.py``
(the real inference path). This module is PURE, importable Python — there is NO
markdown-parse layer (OQ-DS-4 RESOLVED): the rosters A/B/C are typed in source.

Reality Ledger / house rules (mirrors council_backend.py / council_inference.py):
  * Every resolution is exercised entirely OFFLINE over an INJECTED catalog id
    list (REQ-DS-015). The resolver NEVER performs a live GET in the offline
    suite — the caller (live path only) fetches the catalog via the reused
    ``council_backend._fetch_catalog_ids`` (fixed host → no SSRF) and passes the
    id list in. These checks are ``integration-fake`` and prove NO real diversity.
  * The dynamic resolver NEVER auto-selects a non-``:free`` (paid) id and NEVER
    falls back to a stale hardcoded default. An empty/unreachable catalog FAILS
    CLOSED with the classified code ``catalog-unreachable`` (never a stale pick).
  * There is NO Claude-family literal anywhere in this module — a role that cannot
    resolve a foreign model classifies ``model-unresolvable`` (no silent Claude
    substitution; RISK-DS-PRE-015 / MEDIUM-1).
  * The diversity check is a NECESSARY-NOT-SUFFICIENT structural floor (RISK-B-007 /
    RISK-DS-004); it does NOT prove real model diversity. The disclosure is carried
    VERBATIM from ``concilium.md``.
"""
from __future__ import annotations

import argparse
import json
import os
import re
from typing import Any, Callable

from council_backend import distinct_base_count, normalize_model_id

# ---------------------------------------------------------------------------
# Classified codes (distinct, never collapsed). The COUNCIL_* family is reused
# from council_backend / council_inference; the slug-style codes are new.
# ---------------------------------------------------------------------------
CODE_DIVERSITY_OK = "COUNCIL_DIVERSITY_OK"
CODE_DIVERSITY_UNAVAILABLE = "COUNCIL_DIVERSITY_UNAVAILABLE"
CODE_OK = "COUNCIL_INFERENCE_OK"

CODE_UNKNOWN_PRESET = "unknown-preset"
CODE_UNKNOWN_CHARACTER_SLUG = "unknown-character-slug"
CODE_MODEL_UNRESOLVABLE = "model-unresolvable"
CODE_CATALOG_UNREACHABLE = "catalog-unreachable"

# A character slug must be a safe slug — no separators, traversal, or absolute
# paths. Reused pattern shape from council_backend._BODY_RE.
_SLUG_RE = re.compile(r"^[a-z0-9-]+$")

# ---------------------------------------------------------------------------
# Typed rosters (REQ-DS-003). Each role = {role_name, character_slug, model?}.
# model is None unless an explicit per-role override is desired (none today).
# Default preset = "A".
# ---------------------------------------------------------------------------
DEFAULT_PRESET = "A"

PRESETS: dict[str, list[dict[str, Any]]] = {
    "A": [
        {"role_name": "Visionaerin", "character_slug": "die-visionaerin", "model": None},
        {"role_name": "Pruefer", "character_slug": "der-pruefer", "model": None},
        {"role_name": "Nutzeranwalt", "character_slug": "der-nutzeranwalt", "model": None},
        {"role_name": "Macherin", "character_slug": "die-macherin", "model": None},
    ],
    "B": [
        {"role_name": "Systemdenker", "character_slug": "der-systemdenker", "model": None},
        {"role_name": "Risiko-Waechterin", "character_slug": "die-risiko-waechterin", "model": None},
        {"role_name": "Macherin", "character_slug": "die-macherin", "model": None},
        {"role_name": "Minimalist", "character_slug": "der-minimalist", "model": None},
    ],
    "C": [
        {"role_name": "Visionaerin", "character_slug": "die-visionaerin", "model": None},
        {"role_name": "Provokateur", "character_slug": "der-provokateur", "model": None},
        {"role_name": "Uebersetzerin", "character_slug": "die-uebersetzerin", "model": None},
        {"role_name": "Marktschaerferin", "character_slug": "die-marktschaerferin", "model": None},
    ],
}

# ---------------------------------------------------------------------------
# NAMED, EDITABLE free-model family preference order (REQ-DS-015 / CAN-DS-EVN-RES-012).
# Edit THIS list to change which free families the dynamic resolver prefers — the
# resolver never hardcodes a single id. Each entry is {name, match} where `match`
# is a deterministic substring/token predicate over a catalog id's BASE slug.
# Order is preference order:
#   1 DeepSeek v4 -> 2 Qwen3.x -> 3 Kimi K2.7 -> 4 Kimi K2.6 -> 5 GLM 5.x
# After these named families, the OpenRouter free-route fallback picks any :free id.
# (No Claude/anthropic family is or may be listed — MEDIUM-1.)
# ---------------------------------------------------------------------------
FREE_MODEL_FAMILY_PREFERENCE: tuple[dict[str, Any], ...] = (
    {"name": "DeepSeek v4", "match": ("deepseek", "v4")},
    {"name": "Qwen3.x", "match": ("qwen3",)},
    {"name": "Kimi K2.7", "match": ("kimi", "k2-7")},
    {"name": "Kimi K2.6", "match": ("kimi", "k2-6")},
    {"name": "GLM 5.x", "match": ("glm-5",)},
)

# RISK-B-007 disclosure — carried VERBATIM (substrings asserted by the contract).
# Canonical source: config/claude/commands/concilium.md ("necessary-not-sufficient"
# guard ... "does not prove real model diversity").
# NOTE: kept free of shell-breaking metacharacters (parentheses, backticks) so it
# survives the contract's eval-based leak/diversity assertions; the two load-bearing
# substrings the contract pins are present verbatim.
RISK_B_007_DISCLOSURE = (
    "Diversity is a necessary-not-sufficient guard per RISK-B-007 and "
    "it does not prove real model diversity."
)


def get_preset(name: str | None) -> list[dict[str, Any]] | None:
    """Return the typed roster for ``name`` or ``None`` for an unknown preset.

    There is NO silent default to A on an unknown name (REQ-DS-004) — ``None`` is
    the unknown-preset signal the caller classifies.
    """
    if name is None:
        name = DEFAULT_PRESET
    return PRESETS.get(name)


def _is_free(catalog_id: str) -> bool:
    """A catalog id is free iff its id ends with the ``:free`` variant suffix."""
    return catalog_id.strip().endswith(":free")


def family_match(entry: dict[str, Any], catalog_ids: list[str]) -> str | None:
    """First ``:free`` catalog id whose base matches every token of a family entry.

    Deterministic: scans the catalog ids in stable (sorted) order and returns the
    first ``:free`` id whose normalized base contains ALL the family's match
    tokens, else ``None`` (family absent → caller advances the preference order).
    """
    tokens = entry["match"]
    for catalog_id in sorted(catalog_ids):
        if not _is_free(catalog_id):
            continue
        base = normalize_model_id(catalog_id).lower()
        if all(token in base for token in tokens):
            return catalog_id
    return None


def free_route_fallback(catalog_ids: list[str]) -> str | None:
    """Pick any available ``:free`` catalog id (deterministic: first sorted), else None.

    Used only when none of the named preferred families is present. NEVER returns a
    paid id; ``None`` when no ``:free`` id exists at all (caller fails closed).
    """
    free_ids = sorted(c for c in catalog_ids if _is_free(c))
    return free_ids[0] if free_ids else None


def resolve_free_default(catalog_ids: list[str], *, skip: tuple[str, ...] = ()) -> dict[str, Any]:
    """The dynamic resolver core (REQ-DS-015). Pure over a catalog id list.

    Walks ``FREE_MODEL_FAMILY_PREFERENCE`` in order, returning the first family's
    first matching ``:free`` id; an absent family is skipped. If no named family
    matches, the OpenRouter free-route fallback picks any ``:free`` id. If no
    ``:free`` id is available at all → classified ``model-unresolvable`` (the
    resolver NEVER invents a paid/stale id).

    ``skip`` is a set of already-assigned base slugs the resolver should avoid when
    a DISTINCT family is wanted per role (diversity distribution). When skipping
    would leave nothing, the resolver falls back to the best available pick (so a
    role is still resolved; the diversity check then judges the resulting set).
    """
    # First pass: honor `skip` so each role gets the next DISTINCT free family.
    if skip:
        picked = _resolve_first_pick(catalog_ids, skip=skip)
        if picked is not None:
            return picked
    # Second pass (or no skip): the unconstrained best pick.
    picked = _resolve_first_pick(catalog_ids, skip=())
    if picked is not None:
        return picked
    return {"model": None, "source": "resolver", "family": None, "code": CODE_MODEL_UNRESOLVABLE}


def _resolve_first_pick(catalog_ids: list[str], *, skip: tuple[str, ...]) -> dict[str, Any] | None:
    """First family/free-route id whose base is not in ``skip``; None if none fit."""
    skip_bases = {normalize_model_id(s) for s in skip}
    for entry in FREE_MODEL_FAMILY_PREFERENCE:
        match = family_match(entry, catalog_ids)
        if match is not None and normalize_model_id(match) not in skip_bases:
            return {"model": match, "source": "resolver", "family": entry["name"], "code": CODE_OK}
    # Free-route fallback: first sorted :free id whose base is not skipped.
    for catalog_id in sorted(catalog_ids):
        if _is_free(catalog_id) and normalize_model_id(catalog_id) not in skip_bases:
            return {"model": catalog_id, "source": "free-route", "family": None, "code": CODE_OK}
    return None


def resolve_model(
    *,
    env: dict[str, str],
    per_role_model: str | None,
    catalog_ids: list[str] | None,
    skip: tuple[str, ...] = (),
) -> dict[str, Any]:
    """Precedence ladder: explicit per-role/``--model`` > env > dynamic resolver.

    The resolver runs ONLY when no explicit model is set. ``catalog_ids is None``
    signals an unreachable/empty catalog → fail closed with ``catalog-unreachable``
    (never a stale/unverified pick). Returns ``{model, source, code, family?}``.
    """
    if per_role_model:
        return {"model": per_role_model, "source": "field", "code": CODE_OK}
    env_model = env.get("COUNCIL_INFERENCE_MODEL")
    if env_model:
        return {"model": env_model, "source": "env", "code": CODE_OK}
    if not catalog_ids:
        return {"model": None, "source": "resolver", "code": CODE_CATALOG_UNREACHABLE}
    return resolve_free_default(catalog_ids, skip=skip)


def diversity_check(resolved_models: list[str]) -> dict[str, Any]:
    """Wrap ``distinct_base_count`` into the diversity gate (REQ-DS-006, HIGH-1).

    >=2 distinct normalized bases → ``COUNCIL_DIVERSITY_OK``; <2 →
    ``COUNCIL_DIVERSITY_UNAVAILABLE``. Carries the VERBATIM RISK-B-007 disclosure
    so the necessary-not-sufficient framing travels with every gate result. This is
    deliberately NOT ``evaluate_gate`` (that is the council_backend reachability
    gate, not the resolved-set diversity floor).
    """
    present = [m for m in resolved_models if m]
    distinct = distinct_base_count(present)
    gate = CODE_DIVERSITY_OK if distinct >= 2 else CODE_DIVERSITY_UNAVAILABLE
    return {
        "distinct_bases": distinct,
        "gate": gate,
        "disclosure": RISK_B_007_DISCLOSURE,
    }


def resolve_preset(
    name: str | None,
    *,
    env: dict[str, str],
    catalog_ids: list[str] | None,
    character_exists: Callable[[str], bool] | None = None,
) -> dict[str, Any]:
    """Resolve a named preset roster to per-role models + the diversity gate.

    Role order is preserved. Each role resolves via the precedence ladder; roles
    with NO explicit model are assigned DISTINCT free families across the roster
    (diversity-by-construction) so a multi-family catalog yields >=2 distinct
    bases. Classifies ``unknown-preset`` / ``unknown-character-slug`` /
    ``model-unresolvable`` / ``catalog-unreachable``; NEVER substitutes a Claude
    model on an unresolvable role. 0 network (catalog injected).
    """
    roster = get_preset(name)
    if roster is None:
        return {"roles": [], "decision": "abort", "code": CODE_UNKNOWN_PRESET,
                "diversity": {"distinct_bases": 0, "gate": CODE_DIVERSITY_UNAVAILABLE,
                              "disclosure": RISK_B_007_DISCLOSURE}}

    roles: list[dict[str, Any]] = []
    assigned_bases: list[str] = []
    code = CODE_OK
    decision = "proceed"

    for role in roster:
        slug = role["character_slug"]
        if character_exists is not None and not character_exists(slug):
            roles.append({"role_name": role["role_name"], "character_slug": slug,
                          "model": None, "code": CODE_UNKNOWN_CHARACTER_SLUG})
            code = CODE_UNKNOWN_CHARACTER_SLUG
            decision = "abort"
            continue
        resolved = resolve_model(
            env=env,
            per_role_model=role.get("model"),
            catalog_ids=catalog_ids,
            skip=tuple(assigned_bases),
        )
        model = resolved["model"]
        rcode = resolved["code"]
        if model is None:
            roles.append({"role_name": role["role_name"], "character_slug": slug,
                          "model": None, "code": rcode})
            code = rcode if code == CODE_OK else code
            decision = "abort"
            continue
        roles.append({"role_name": role["role_name"], "character_slug": slug,
                      "model": model, "code": CODE_OK})
        assigned_bases.append(model)

    diversity = diversity_check([r["model"] for r in roles])
    # If every role resolved but diversity floor is not met, the gate downgrades.
    if decision == "proceed" and diversity["gate"] == CODE_DIVERSITY_UNAVAILABLE:
        decision = "abort"
        code = CODE_DIVERSITY_UNAVAILABLE

    return {"roles": roles, "decision": decision, "code": code, "diversity": diversity}


# ---------------------------------------------------------------------------
# Optional CLI surface (mirrors the council_* --json seam). Never live in run_all.
# ---------------------------------------------------------------------------
def _parse_catalog(raw: str | None) -> list[str] | None:
    """Parse ``--inject-catalog`` (CSV or JSON list). Empty/None => None (unreachable)."""
    if raw is None:
        return None
    raw = raw.strip()
    if raw == "":
        return None
    if raw.startswith("["):
        try:
            data = json.loads(raw)
        except (ValueError, TypeError):
            return None
        if not isinstance(data, list):
            return None
        ids = [str(x).strip() for x in data if str(x).strip()]
        return ids or None
    ids = [part.strip() for part in raw.split(",") if part.strip()]
    return ids or None


def _parser() -> argparse.ArgumentParser:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--json", action="store_true", help="Emit machine-readable JSON.")
    parser = argparse.ArgumentParser(
        description="Typed Concilium presets + dynamic free-model resolver.", parents=[common])
    sub = parser.add_subparsers(dest="command", required=True)

    p_rp = sub.add_parser("resolve-preset", help="Resolve a preset roster + diversity.", parents=[common])
    p_rp.add_argument("--preset", default=DEFAULT_PRESET)
    p_rp.add_argument("--inject-catalog", default=None)

    p_rm = sub.add_parser("resolve-model", help="Resolve a single free-default model.", parents=[common])
    p_rm.add_argument("--inject-catalog", default=None)
    p_rm.add_argument("--model", default=None)

    p_div = sub.add_parser("diversity", help="Diversity check over a model id list.", parents=[common])
    p_div.add_argument("--models", default="[]", help="JSON list of resolved model ids.")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _parser().parse_args(argv)
    env = dict(os.environ)

    if args.command == "resolve-preset":
        catalog = _parse_catalog(args.inject_catalog)
        state = resolve_preset(args.preset, env=env, catalog_ids=catalog)
    elif args.command == "resolve-model":
        catalog = _parse_catalog(args.inject_catalog)
        state = resolve_model(env=env, per_role_model=args.model, catalog_ids=catalog)
    elif args.command == "diversity":
        try:
            models = json.loads(args.models)
            if not isinstance(models, list):
                models = []
        except (ValueError, TypeError):
            models = []
        state = diversity_check([str(m) for m in models])
    else:  # pragma: no cover - argparse enforces a valid subcommand
        return 2

    print(json.dumps(state, sort_keys=True, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
