# OpenRouter Council Backend — Real-Boundary Smoke (2026-06-18)

REQ-B-011 reachability (OQ-B-004 catalog-list method) · EV-B-007. Slice OD-3.
Branch `agileteam/openrouter-council-backend`. This is a **real captured run** against the
live OpenRouter API, not a fabricated snapshot. The API key was loaded at runtime from
`~/.openclaw/.env` and is **never** present in this trace (leak-check below = 0).

## What this proves (and what it does not)

| Claim | Evidence class | Status |
|---|---|---|
| Configured models are **present/reachable in the live OpenRouter catalog** (`GET /api/v1/models`) | **real-boundary-smoke** | proven below |
| The diversity gate counts **distinct normalized base models** against **live** catalog data (`:nitro`/`:floor` collapse to one) | **real-boundary-smoke** | proven below |
| The configured models are actually **invocable** (a completion would succeed) | — | **RED(confidence)** — reachable ≠ invocable; a catalog listing does not prove a completion works (a paid probe was deliberately NOT run; NGOAL-B-004) |
| "Real model diversity" in the deep sense (two distinct base slugs are genuinely different models, not mirrors) | — | **RED(confidence)** — RISK-B-007 residual, unchanged |

So this smoke **lifts catalog-reachability + the normalized-base gate to real-boundary-smoke**;
the **invocability** and **deep-diversity** sub-claims remain RED(confidence) and may be
reclassified only by the user.

## 1 — Live reachability, two genuinely distinct base models — real-boundary-smoke

```
# key loaded from ~/.openclaw/.env at runtime (value never printed); length 73
$ COUNCIL_BACKEND=openrouter COUNCIL_FAIL_CLOSED=true COUNCIL_MIN_BACKENDS=2 \
  COUNCIL_1_MODEL=anthropic/claude-fable-5 COUNCIL_2_MODEL=openai/gpt-chat-latest \
  python3 config/claude/lib/council_backend.py reachable --json
{
  "code": "COUNCIL_DIVERSITY_OK",
  "decision": "proceed",
  "distinct_base_count": 2,
  "min_backends": 2,
  "reachable_bases": ["anthropic/claude-fable-5", "openai/gpt-chat-latest"]
}
# leak-check on the output for 'sk-or-' / 'Bearer ' => 0
```

The live catalog (341 models at run time) was queried with the real key; both configured
base models were found reachable; two distinct normalized bases → council may proceed.

## 2 — Goodhart resistance at the real boundary: variant-aliases collapse — real-boundary-smoke

```
$ ... COUNCIL_1_MODEL=anthropic/claude-fable-5:nitro \
      COUNCIL_2_MODEL=anthropic/claude-fable-5:floor \
  python3 config/claude/lib/council_backend.py reachable --json
{
  "code": "COUNCIL_DIVERSITY_UNAVAILABLE",
  "decision": "abort",
  "distinct_base_count": 1,
  "min_backends": 2,
  "reachable_bases": ["anthropic/claude-fable-5"]
}
```

Two *distinct ID strings* (`:nitro`, `:floor`) of the **same base model**, checked against
the **live** catalog, normalize to one base → count 1 → fail-closed. This is the B1
remediation (the spec-sanity Goodhart finding) holding against real OpenRouter routing
aliases, not just an offline fixture.

## Secret handling

The raw `OPENROUTER_API_KEY` is used solely to build the `Authorization: Bearer` header in
`council_backend.py:_fetch_catalog_ids`; it never enters the returned payload, the trace, or
any log. The leak-check (`grep -cE 'sk-or-|Bearer '` on the output) returned **0**.

## Honest ceiling (F3)

Catalog-reachability and the normalized-base diversity gate are **real-boundary-smoke**.
**Invocability** (reachable ≠ invocable) and **deep model diversity** remain
**PASS(tests)/RED(confidence)** — a real completion probe (paid) would be required to lift
invocability, and was not run. This RED may not be downgraded; only the user reclassifies.
OQ-B-004 reachability METHOD is now **partially resolved**: the catalog-list method is chosen
and verified live; the invocability question stays open.
