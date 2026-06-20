# SMK-007 · Foreign-model council (full-preset live, real in-character position)

**ID:** SMK-007 · **Date:** 2026-06-19 · **Kind:** Real-boundary smoke · **Status:** complete.
Branch `agileteam/deepseek-review-agent`. Slice 2. REQ-DS-001/002/004/006/008/015 · OQ-DS-6.

A capability proof against the **live** OpenRouter API. Gated by `COUNCIL_INFERENCE_LIVE=1` +
`preset --live`; cost **$0** (all roles resolved to `:free` models). Key from `~/.openclaw/.env`,
header-only, never in trace (leak-check = 0).

> **A real defect this smoke caught (logged, not hidden).** The first dry-run returned
> `catalog-unreachable` for every role: the dynamic resolver (REQ-DS-015) had an injectable
> `--inject-catalog` seam but **no wired live catalog fetch** — `catalog_ids` was always `None`
> in production, so every live preset would have aborted (a Slice-1 retro lesson: an injectable
> seam needs a paired real entrypoint, or the real path is dead code). The live fetch was then
> wired and a paired regression test added. The capture below is the **post-fix** run.

## What it set out to prove

That a `/concilium` character can run on a real **foreign (non-Claude)** model and return a real
in-character position; that the resolver distributes distinct free model families across a
preset live; and that a full preset classifies per-role failures instead of crashing/fabricating.

## Method (real captured run)

`config/claude/lib/deepseek_review.py preset --preset A --subject "Add a dark-mode toggle…"
--live --json` with **no** `--inject-catalog`, so the resolver fetches the live catalog and
distributes families across the four roles (Visionaerin · Pruefer · Nutzeranwalt · Macherin).

## Results (as captured)

| Role | Model (resolved live, distinct family) | Code |
|---|---|---|
| Visionaerin | `qwen/qwen3-coder:free` | `COUNCIL_RATE_LIMITED` |
| Pruefer | `cognitivecomputations/dolphin-mistral-24b-venice-edition:free` | `COUNCIL_RATE_LIMITED` |
| Nutzeranwalt | `cohere/north-mini-code:free` | `COUNCIL_MODEL_UNAVAILABLE` |
| **Macherin** | **`google/gemma-4-26b-a4b-it:free`** | **`COUNCIL_INFERENCE_OK`** |

- **Diversity:** `distinct_bases: 4`, `COUNCIL_DIVERSITY_OK` — four distinct free families
  (qwen / cognitivecomputations / cohere / google) across four roles, live, by construction
  (REQ-DS-006). The diversity disclosure carried verbatim: *"Diversity is a
  necessary-not-sufficient guard per RISK-B-007 and it does not prove real model diversity."*
- **The real foreign position:** the Macherin role on `google/gemma` adopted the character's exact
  output structure (Objekt → Umsetzungsbefund → MVP → Aufwand/Daten/Schnittstellen →
  Akzeptanzkriterien) — a real, structured, in-character answer from a non-Claude model.
- Aggregate `code`: `COUNCIL_MODEL_UNAVAILABLE` (the preset surfaces the worst per-role outcome).
- Leak-check (`grep -cE 'sk-or-'`) = **0**.

## What it proved / what it did NOT prove

| Claim | Evidence class | Status |
|---|---|---|
| Live catalog fetch works in prod; resolver distributes distinct free families across a preset | **real-boundary-smoke** | proven (4 distinct families) |
| A `/concilium` character runs on a real foreign model and returns a real in-character position | **real-boundary-smoke** | proven (Macherin → google-gemma) |
| A full preset issues one real call per role and CLASSIFIES per-role failures | **real-boundary-smoke** | proven (4 calls; 1 OK, 2 rate-limited, 1 unavailable — all classified) |
| Secret never leaks | verified | leak-check = 0 |
| The foreign council "catches more" / is "more diverse in cognition" / higher quality than Claude-only | — | **NOT CLAIMED** — deferred to Slice-3 measurement (NGOAL-DS-003/011) |

## Honest interpretation — the honest ceiling

This run got **one of four** roles to a real position; the other three hit free-tier flakiness
(two `429 rate-limited`, one `model-unavailable`) — **RISK-DS-007 confirmed empirically:
reachable ≠ invocable**, free tiers are flaky, a smoke is a snapshot. That is the honest outcome
of a real call, not a defect: every role returned a real position **or** a cleanly-classified
code, never a manufactured success. The **capability** chain (live catalog → distinct-family
diversity → real in-character foreign position → classified failures → no leak) is proven
end-to-end for this run. Broader invocability across all roles/models, and the **diversity /
quality LIFT**, remain `PASS(tests)/RED(confidence)` — not downgradable except by the user.
**distinct-ids ≠ proven diversity** holds (RISK-B-007). The `concilium.md` orchestration wiring
stays `integration-fake` (markdown instructs; live orchestrator obedience unproven by code).

## Evidence class

`real-boundary-smoke` for the capability chain (one of four roles invocable). `NOT-CLAIMED` for
any value/diversity/quality lift.

## Source artifacts (read before writing)

- [`docs/benchmarks/2026-06-19-deepseek-review-smoke.md`](../benchmarks/2026-06-19-deepseek-review-smoke.md)
  — the per-role table, the verbatim Macherin position, the caught-defect note, and the
  leak-check traced here.
- Artifact under test: `config/claude/lib/deepseek_review.py` (`preset`); live fetch wired in
  `council_backend._fetch_catalog_ids`.
- Reality ledger: [`docs/reality/deepseek-review-agent.evidence.jsonl`](../reality/deepseek-review-agent.evidence.jsonl).
</content>
