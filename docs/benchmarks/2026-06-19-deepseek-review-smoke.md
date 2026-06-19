# Foreign-Model Council — Full-Preset Real-Boundary Smoke (2026-06-19)

Slice 2 `deepseek-review-agent`. REQ-DS-001/002/004/006/008/015 · CAN-DS-EVN-003/006 · OQ-DS-6.
Branch `agileteam/deepseek-review-agent`. This is a **real captured run** against the live
OpenRouter API, not a fabricated snapshot. The API key was loaded at runtime from
`~/.openclaw/.env`, used only in the `Authorization` header (inside the reused Slice-1
`run_inference` / `_real_transport`), and is **never** in this trace (leak-check = 0). Gated by
`COUNCIL_INFERENCE_LIVE=1` + `preset --live`. Cost: **$0** (all roles resolved to `:free` models).

> **Why this smoke matters (a real defect it caught).** The first dry-run returned
> `catalog-unreachable` for every role: the dynamic resolver (REQ-DS-015) had an injectable
> `--inject-catalog` seam but **no wired live catalog fetch** — `catalog_ids` was always `None`
> in production, so every live preset would have aborted. This is the Slice-1 retro lesson (an
> injectable seam needs a PAIRED real entrypoint, or the real path is dead code). The live
> catalog fetch was then wired (`council_backend._fetch_catalog_ids`, fixed host, fail-closed)
> and a paired regression test added. The capture below is the post-fix run.

## Command

```
# COUNCIL_INFERENCE_LIVE=1, key from ~/.openclaw/.env (never printed), preset A (default round),
# NO --inject-catalog → the resolver fetches the LIVE catalog and distributes distinct free families.
$ COUNCIL_INFERENCE_LIVE=1 python3 config/claude/lib/deepseek_review.py preset \
    --preset A --subject "Add a dark-mode toggle to our mobile app." --live --json
```

## Captured result (preset A — Visionaerin · Pruefer · Nutzeranwalt · Macherin)

| Role | Character | Model (resolved live, distinct family) | Code |
|---|---|---|---|
| Visionaerin | die-visionaerin | `qwen/qwen3-coder:free` | `COUNCIL_RATE_LIMITED` |
| Pruefer | der-pruefer | `cognitivecomputations/dolphin-mistral-24b-venice-edition:free` | `COUNCIL_RATE_LIMITED` |
| Nutzeranwalt | der-nutzeranwalt | `cohere/north-mini-code:free` | `COUNCIL_MODEL_UNAVAILABLE` |
| **Macherin** | **die-macherin** | **`google/gemma-4-26b-a4b-it:free`** | **`COUNCIL_INFERENCE_OK`** |

- **Diversity: `distinct_bases: 4`, `COUNCIL_DIVERSITY_OK`** — the resolver distributed **four
  distinct free model families** (qwen / cognitivecomputations / cohere / google) across the four
  roles, live, by construction (REQ-DS-006). Diversity disclosure carried verbatim: *"Diversity is
  a necessary-not-sufficient guard per RISK-B-007 and it does not prove real model diversity."*
- **Secret leak-check = 0** (`grep -cE 'sk-or-'` over the full output = 0).
- Aggregate `code`: `COUNCIL_MODEL_UNAVAILABLE` (the preset surfaces the worst per-role outcome).

### The real in-character foreign position (Macherin / google-gemma)

A real foreign model adopted the **Macherin** character's exact output structure (Objekt →
Umsetzungsbefund → MVP → Aufwand/Daten/Schnittstellen → Akzeptanzkriterien):

```
**Objekt:** Dark-Mode-Toggle in der Mobile App.
**Umsetzungsbefund:** Noch zu vage. (Es fehlt an technischer Basis, Design-Vorgaben …)
**Naechster Schritt / MVP:** … technischer Proof-of-Concept, der prüft, ob das globale
Theme-Management einen harten Light/Dark-Wechsel ohne Crash/Artefakte erlaubt.
**Aufwand:** Gering (ca. 1-2 Entwicklertage). **Daten:** keine neuen. **Schnittstellen:**
Theme-Provider. **Akzeptanzkriterien:** Klick triggert App-weiten Farbwechsel …
```

## What this proves (capability) — and what it does NOT (value)

| Claim | Evidence class | Status |
|---|---|---|
| The live catalog fetch (REQ-DS-015) works in production and the resolver distributes distinct free families across a preset | **real-boundary-smoke** | proven (4 distinct families resolved live) |
| A `/concilium` CHARACTER runs on a real foreign (non-Claude) model and returns a real, in-character position | **real-boundary-smoke** | proven (Macherin → google-gemma, real structured position) |
| A full preset issues one real call PER role and CLASSIFIES per-role failures (rate-limit / unavailable) instead of crashing or fabricating | **real-boundary-smoke** | proven (4 role-calls; 1 OK, 2 rate-limited, 1 unavailable — all classified) |
| Secret never leaks across the live path | verified | leak-check = 0 |
| The foreign council "catches more" / is "more diverse in cognition" / higher quality than Claude-only | — | **NOT CLAIMED** — deferred **Slice-3** measurement (catch-rate / cry-wolf delta), NGOAL-DS-003/011 |

## Honest ceiling (F3)

This run got **one of four** roles to a real position; the other three hit free-tier
flakiness (two `429 rate-limited`, one `model-unavailable`) — **RISK-DS-007 confirmed
empirically: reachable ≠ invocable**, free tiers are flaky and a smoke is a snapshot. That is
the honest outcome of a real call, not a defect: the path returned a real position **or** a
cleanly-classified code for every role, never a manufactured success. The CAPABILITY (live
catalog resolution → distinct-family diversity → real in-character foreign position → classified
failures → no key leak) is proven end-to-end for this run; broader invocability across all
roles/models, and the diversity/quality LIFT, remain **PASS(tests)/RED(confidence)** —
not downgradable except by the user. The offline suite stays `integration-fake` (0 credits); the
`concilium.md` orchestration wiring stays `integration-fake` (markdown instructs; live
orchestrator obedience unproven by code).
