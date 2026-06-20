# SMK-005 · OpenRouter council backend (live catalog reachability + diversity gate)

**ID:** SMK-005 · **Date:** 2026-06-18 · **Kind:** Real-boundary smoke · **Status:** complete.
Branch `agileteam/openrouter-council-backend`. Slice OD-3. REQ-B-011 · OQ-B-004 · EV-B-007.

A capability proof against the **live** OpenRouter API (not a fabricated snapshot). The API
key was loaded at runtime from `~/.openclaw/.env`, used only in the `Authorization` header, and
**never** appears in the trace (leak-check = 0).

## What it set out to prove

That the council backend (a) verifies configured models are present/reachable in the live
OpenRouter catalog, and (b) counts **distinct normalized base models** so routing variant
aliases cannot inflate apparent diversity (the spec-sanity Goodhart finding, B1).

## Method (real captured runs)

`config/claude/lib/council_backend.py reachable --json` was run against the live catalog
(`GET /api/v1/models`, 341 models at run time) with the real key, in two configurations:
two genuinely distinct base models, and two variant aliases of the *same* base.

## Results (as captured)

| Claim | Evidence class | Status |
|---|---|---|
| Configured models present/reachable in the live catalog | **real-boundary-smoke** | proven |
| Diversity gate counts distinct normalized base models against live data (`:nitro`/`:floor` collapse to one) | **real-boundary-smoke** | proven |
| Configured models are actually **invocable** (a completion would succeed) | — | **RED(confidence)** — reachable ≠ invocable; a paid probe was deliberately NOT run (NGOAL-B-004) |
| "Real model diversity" in the deep sense (two distinct slugs are genuinely different models, not mirrors) | — | **RED(confidence)** — RISK-B-007 residual, unchanged |

- Distinct bases (`anthropic/claude-fable-5` + `openai/gpt-chat-latest`) →
  `COUNCIL_DIVERSITY_OK`, `distinct_base_count: 2`, decision `proceed`.
- Variant aliases (`…claude-fable-5:nitro` + `…claude-fable-5:floor`) →
  `COUNCIL_DIVERSITY_UNAVAILABLE`, `distinct_base_count: 1`, decision `abort` (fail-closed).
  Two distinct ID strings of the same base normalize to one → the B1 remediation holding
  against **real** OpenRouter routing aliases, not just an offline fixture.
- Leak-check (`grep -cE 'sk-or-|Bearer '` on the output) = **0**.

## Honest interpretation — what it does NOT show

The smoke lifts **catalog-reachability** and the **normalized-base diversity gate** to
real-boundary-smoke. It says **nothing** about whether the models actually return completions:
**a catalog listing does not prove a completion works.** Both **invocability** and **deep model
diversity** remain `PASS(tests)/RED(confidence)` — a paid completion probe would be required to
lift invocability and was not run. This RED is not downgradable except by the user.
**distinct-ids ≠ proven diversity** holds here explicitly (RISK-B-007).

## Evidence class

`real-boundary-smoke` for live catalog reachability + the normalized-base diversity gate.
`RED(confidence)` for invocability and deep diversity. OQ-B-004 reachability METHOD partially
resolved (catalog-list chosen and verified live; invocability open).

## Source artifacts (read before writing)

- [`docs/benchmarks/2026-06-18-openrouter-council-backend-smoke.md`](../benchmarks/2026-06-18-openrouter-council-backend-smoke.md)
  — both captured JSON results and the leak-check traced here.
- Artifact under test: `config/claude/lib/council_backend.py`
  (`reachable`, `_fetch_catalog_ids`).
- Reality ledger: [`docs/reality/openrouter-council-backend.evidence.jsonl`](../reality/openrouter-council-backend.evidence.jsonl).
</content>
