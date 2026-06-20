# SMK-006 · OpenRouter inference path (one-model invocability + heuristic-drift)

**ID:** SMK-006 · **Date:** 2026-06-19 · **Kind:** Real-boundary smoke · **Status:** complete.
Branch `agileteam/openrouter-inference`. Slice 1 of 4. REQ-INF-001/009/016/017 · OQ-3 · I-3.

A capability proof against the **live** OpenRouter API. Gated by `COUNCIL_INFERENCE_LIVE=1` +
`infer --live`; cost **$0** (free models). Key from `~/.openclaw/.env`, header-only, never in
trace (leak-check = 0).

> **Self-correction logged (the honesty rule in action):** an earlier capture supplied
> `--input-estimate 12` by hand, so the drift it reported (+6) measured a *typed-in* number, not
> the module's heuristic. An ultrathink plausibility pass over the *numbers* caught it. This entry
> documents the **corrected** run — no `--input-estimate` supplied, so the module computes its own
> value. We report the correction openly rather than re-wording around it.

## What it set out to prove

That the inference path performs a real `POST /chat/completions`, returns a real completion
(invocability), classifies an unavailable model instead of crashing/faking, and that the
module's OWN input-token heuristic drift can be measured against real `usage.prompt_tokens`.

## Method (real captured runs)

`config/claude/lib/council_inference.py infer --live` was run with no hand-fed estimate, on two
free models — one that answers and one that does not.

## Results (as captured)

| Claim | Evidence class | Status |
|---|---|---|
| Real completion returned for `nex-agi/nex-n2-pro:free` (invocability) | **real-boundary-smoke** | proven |
| Path classifies an unavailable model instead of crashing/faking (REQ-INF-017) | **real-boundary-smoke** | proven |
| Module's OWN heuristic drift measured vs real `usage.prompt_tokens` | **real-boundary-smoke** | proven (heuristic **10** vs real **18** → drift **+8**) |
| Secret never leaks | verified | leak-check = 0 |
| Invocability of **other** models / **general** estimate accuracy / a `cost` field | — | **RED(confidence)** — one model, one datapoint |

- The free model answered `"PLUMBLINE"` → `COUNCIL_INFERENCE_OK`, decision `proceed`.
- **I-3 in action:** the module's char-heuristic (`estimate_input_tokens`) computed **10** input
  tokens; real `usage.prompt_tokens` was **18**; `input_estimate_drift = 18 − 10 = +8`. The
  heuristic under-estimated by 8 (chat-template/role wrapper inflates the real count above the
  bare-content estimate) — so the cap is honestly *approximate* and the drift is now **measured,
  not hoped**. A `--dry-run` (no `--input-estimate`) re-emits `input_token_estimate=10`,
  confirming 10 is the module's value, not a supplied one.
- The unavailable free model (`cohere/north-mini-code:free`) returned a classified
  `COUNCIL_MODEL_UNAVAILABLE` (no traceback, no false success) — REQ-INF-017 at the real
  boundary, and empirical confirmation of RISK-INF-005 ("reachable ≠ invocable": two free
  models, one invocable, one not).
- Leak-check (`grep -cE 'sk-or-|Bearer '`) = **0**.

## Honest interpretation — what it does NOT show

Invocability is real-boundary-smoke **for the one model `nex-agi/nex-n2-pro:free` at this run
only.** Broader invocability across models, general input-estimate accuracy, and any
`cost`-field reliance stay `PASS(tests)/RED(confidence)` — one datapoint cannot generalize. The
offline suite stays `integration-fake` (0 credits); the `COUNCIL_INFERENCE_LIVE` gate keeps it
network-free by default. OQ-3 is **partially verified**: the request shape and
`usage.prompt_tokens`/`usage.completion_tokens` fields are confirmed present and used; no `cost`
field was assumed.

## Evidence class

`real-boundary-smoke` for one model's invocability + the heuristic-drift measurement +
classified-unavailable handling. `RED(confidence)` for everything broader.

## Source artifacts (read before writing)

- [`docs/benchmarks/2026-06-19-openrouter-inference-smoke.md`](../benchmarks/2026-06-19-openrouter-inference-smoke.md)
  — both captured JSON results, the drift arithmetic, and the self-correction note traced here.
- Artifact under test: `config/claude/lib/council_inference.py` (`infer`, `_real_transport`,
  `estimate_input_tokens`).
- Reality ledger: [`docs/reality/openrouter-inference.evidence.jsonl`](../reality/openrouter-inference.evidence.jsonl).
</content>
