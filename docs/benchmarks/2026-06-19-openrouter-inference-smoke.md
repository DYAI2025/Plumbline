# OpenRouter Inference Path — Real-Boundary Smoke (2026-06-19)

REQ-INF-001/009/016/017 · EV-INF-006 · OQ-3 · I-3. Slice `openrouter-inference` (1 of 4).
Branch `agileteam/openrouter-inference`. This is a **real captured run** against the live
OpenRouter API, not a fabricated snapshot. The API key was loaded at runtime from
`~/.openclaw/.env`, used only in the `Authorization` header, and is **never** in this trace
(leak-check = 0). Gated by `COUNCIL_INFERENCE_LIVE=1` + `infer --live`; cost: **$0** (free models).

> **Honesty note (ultrathink plausibility pass, 2026-06-19):** an earlier capture supplied
> `--input-estimate 12` by hand, so the drift it reported (+6) measured a typed-in number, not
> the module's heuristic. This trace is the corrected run: **no `--input-estimate` is supplied**,
> so the value drift-measured is the module's OWN char-heuristic (`estimate_input_tokens`).

## What this proves (and what it does NOT)

| Claim | Evidence class | Status |
|---|---|---|
| The inference path performs a real `POST /chat/completions` and returns a real completion (invocability) for the **one probed model** `nex-agi/nex-n2-pro:free` | **real-boundary-smoke** | proven (§1) |
| The path reaches the real boundary and **classifies** an unavailable model instead of crashing/faking (REQ-INF-017) | **real-boundary-smoke** | proven (§2) |
| The module's OWN input heuristic drift is **measured** against real `usage.prompt_tokens` | **real-boundary-smoke** | proven (§1: heuristic 10 vs real 18 → drift +8) |
| Secret never leaks across the live path | verified | leak-check = 0 |
| Invocability of **other** models / **general** estimate accuracy / a `cost` field | — | **RED(confidence)** — one model, one data point; OQ-3 `cost` not assumed; only the user reclassifies |

The OQ-3 contract is **partially verified live**: the `chat/completions` request shape and the
`usage.prompt_tokens`/`usage.completion_tokens` fields are confirmed present and used; no `cost`
field was assumed or required.

## 1 — Successful invocability (free model) — real-boundary-smoke

```
# COUNCIL_INFERENCE_LIVE=1, key from ~/.openclaw/.env (never printed), free model,
# NO --input-estimate (module's own heuristic is used and drift-measured)
$ COUNCIL_INFERENCE_MODEL=nex-agi/nex-n2-pro:free \
  python3 config/claude/lib/council_inference.py infer --live \
    --messages '[{"role":"user","content":"Reply with exactly the word: PLUMBLINE"}]' \
    --max-tokens 16 --json
{
  "code": "COUNCIL_INFERENCE_OK",
  "completion": "PLUMBLINE",
  "decision": "proceed",
  "estimate": {"approximate": true, "cap": 20000, "input_token_estimate": 10, "max_tokens": 16, "total_estimate": 26},
  "retry_after": null,
  "usage": {"completion_tokens": 7, "input_estimate_drift": 8, "input_token_estimate": 10, "prompt_tokens": 18}
}
# verification that 10 is the module heuristic (not supplied): `infer ... --dry-run` (no
# --input-estimate) emits input_token_estimate=10, total_estimate=26.
```

A real model answered → invocability proven for `nex-agi/nex-n2-pro:free`. **I-3 in action:** the
module's char-heuristic (`estimate_input_tokens`) computed **10** input tokens; the real
`usage.prompt_tokens` was **18**; `input_estimate_drift = prompt_tokens − input_token_estimate =
+8`. The heuristic under-estimated input by 8 tokens (chat-template/role wrapper inflates the
real count above the bare-content estimate) — so the cap is honestly **approximate**, and the
heuristic's real-world drift is now measured, not hoped. (General estimate accuracy across
models/inputs stays RED — this is one data point.)

## 2 — Unavailable free model is CLASSIFIED, not crashed — real-boundary-smoke

```
$ COUNCIL_INFERENCE_MODEL=cohere/north-mini-code:free  ... infer --live ...
{ "code": "COUNCIL_MODEL_UNAVAILABLE", "completion": null, "decision": "abort", "usage": null, ... }
```

A free model that did not answer returned a **classified** `COUNCIL_MODEL_UNAVAILABLE` (no
traceback, no false success, error body not leaked as a completion). This is REQ-INF-017 holding
at the real boundary: a free-model flake is **not** a code failure. It also confirms RISK-INF-005
("reachable ≠ invocable") empirically — two free models, one invocable, one not.

## Secret handling

The raw `OPENROUTER_API_KEY` (length 73) was used solely to build the `Authorization: Bearer`
header inside `_real_transport`; it appears in neither result above. `grep -cE 'sk-or-|Bearer '`
over the outputs = **0**.

## Honest ceiling (F3)

Invocability is `real-boundary-smoke` **for the one model `nex-agi/nex-n2-pro:free` at this run
only**. Broader invocability, general input-estimate accuracy, and any `cost`-field reliance stay
**PASS(tests)/RED(confidence)** — not downgradable except by the user at the acceptance gate. The
offline suite remains `integration-fake` (0 credits); the gate (`COUNCIL_INFERENCE_LIVE`) keeps it
network-free.
