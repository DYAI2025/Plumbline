# Free-Model Family Preference Refresh — before/after (2026-06-20)

`council_presets.FREE_MODEL_FAMILY_PREFERENCE` was stale: its named families
(DeepSeek-v4, Qwen3.x, Kimi-K2.7, Kimi-K2.6, GLM-5.x) had only **Qwen3.x** still in the live
OpenRouter free catalog, so 3 of 4 council roles fell to the arbitrary free-route fallback
(alphabetically-first `:free` ids). This refresh keeps DeepSeek (top, contract-pinned) + Qwen,
drops the catalog-absent Kimi/GLM, and adds the **verified-against-the-live-catalog** strong
free families GPT-OSS-120B, NVIDIA Nemotron-Super, Google Gemma-4, Meta Llama-3.3. The resolver
logic is unchanged (skip-absent → next preference → free-route fallback → fail-closed on no
`:free`), so a later-dropping family degrades gracefully — not a stale-hardcode risk.

Both runs are REAL captured live runs through the GUI served `POST /run` path (the production
composition root); key server-side / child-env only, leak-check 0 in both.

## Default preset-A resolution (live catalog)

| Role | BEFORE (stale list) | AFTER (refreshed list) |
|---|---|---|
| Visionaerin | qwen/qwen3-coder:free *(Qwen3.x)* | qwen3 *(Qwen3.x)* |
| Pruefer | dolphin-mistral:free *(free-route fallback)* | **openai/gpt-oss-120b:free** *(named)* |
| Nutzeranwalt | cohere/north-mini-code:free *(fallback)* | **nvidia/nemotron-3-super-120b:free** *(named)* |
| Macherin | google/gemma-4-26b:free *(fallback)* | **google/gemma-4-26b:free** *(named)* |
| distinct strong named families | 1 (only qwen) | **4** |

## Live council reach (GUI `POST /run`, mode=live, preset A)

| | BEFORE | AFTER |
|---|---|---|
| roles returning a REAL position | **1 / 4** | **3 / 4** |
| OK roles | Macherin (gemma, 907 chars) | Pruefer (gpt-oss-120b, 2625), Nutzeranwalt (nemotron, 1167), Macherin (gemma, 917) |
| attrition | 3/4 rate-limited/unavailable | 1/4 (qwen3-coder rate-limited) |
| overall | `COUNCIL_MODEL_UNAVAILABLE` | `COUNCIL_MODEL_UNAVAILABLE` (honest partial) |
| leak-check | 0 | 0 |

## Honest interpretation
The default council now reaches **3/4 roles with real positions** (up from 1/4) because the
strong free families resolve by name instead of arbitrary fallbacks. This is a **reachability /
wiring improvement**, NOT a council-quality or value verdict — the positions' usefulness is
unmeasured (that needs the powered measurement run). Free-tier remains intermittent: this run
still lost qwen3-coder to a rate limit, and a re-run may show different per-role attrition. The
overall is honestly `COUNCIL_MODEL_UNAVAILABLE` while any role fails (partial render shows the
3 real positions + the 1 classified code). The match tokens are catalog-verified as of
2026-06-20; the comment carries a periodic-recheck note (the catalog churns).
