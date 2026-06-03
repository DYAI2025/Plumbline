# Bench — Challenge-Gate Token Oracle (Finding #2), 2026-06-03

**Claim under test (Finding #2):** the `/concilium --mode=challenge` gate's
`≤ ~15k tokens total` bound (`config/claude/commands/concilium.md` §"Challenge mode")
is *aspirational prose*, not an enforced or measured fact.

**Verdict: CONFIRMED — the bound does NOT hold.** Under the natural reading of
"tokens total" (total tokens consumed by the gate), a single faithful round already
costs **~103,464 tokens — ~6.9× the 15,000 bound** — and that is a *lower bound*. The
gate produces genuine, distinct friction (O3 holds); it is simply far more expensive than
the prose claims. This is a successful refutation by the instrument, not a defect to hide.

---

## Setup (reproducible)

- **Instrument:** `config/claude/metrics/challenge_token_oracle.py` (deterministic scorer; O1 token bound + O3 role distinctness; O2 deferred). Part 1, merged to `main` in PR #32.
- **Pinned agent snapshot:** `cc42573` (`v0.11.0-24-gcc42573`). The measured behaviour belongs to this snapshot of `concilium/skeptic.md`, `concilium/tech-arbiter.md`, `config/claude/commands/concilium.md`.
- **Fixture:** `metrics/corpus/challenge-token-oracle/{CANVAS.md,IDEA.md}` — a leak-checked, neutral mid-complexity feature (a per-user notifications digest service). Leak scan: CLEAN (no token/brevity/length cue).
- **Model:** Opus (the model the gate's judgment is validated on). **n = 1.**
- **Role → body mapping dispatched (canonical `concilium.md`, faithful — NOT the superseded three-distinct-body plan):**
  | Role | Body | Lens |
  |------|------|------|
  | Challenger | `concilium-skeptic` | requirement — "right ask?" |
  | Advisor | `concilium-tech-arbiter` | (+distribution) build — "better approach?" |
  | Critic | `concilium-skeptic` | (+market) concept — "should it exist?" |
  Two distinct bodies; `concilium-skeptic` plays Challenger AND Critic; `concilium-market-realist` not dispatched (market is only a lens).
- **Isolation:** all three role subagents TEXT-ONLY; run-data staged at `/tmp/cto-run1.json`; no builder output entered the tree.

## Measurement (n=1, Opus)

| Role (body) | reported `subagent_tokens` |
|-------------|----------------------------|
| Challenger (`concilium-skeptic`) | 34,627 |
| Advisor (`concilium-tech-arbiter`) | 34,446 |
| Critic (`concilium-skeptic`) | 34,391 |
| **total** | **103,464** |

Scorer verdict (`/tmp/cto-run1.json`):

```
O1_token_bound_hold: false   total_tokens: 103464   bound: 15000   (~6.9× over)
O3_roles_distinct:   true    max_pairwise_similarity: 0.1752 (cap 0.6)
pairwise: challenger_critic 0.1752 · challenger_advisor 0.1192 · advisor_critic 0.1206
pass: false (exit 1)
```

- **bound-hold count: 0 / 1.** O1 fails decisively (not borderline).
- **O3 holds.** Max similarity was the shared-base **Challenger↔Critic** pair (both `concilium-skeptic`) at **0.175** — exactly the pair the shared-base confound predicts would be highest, yet it is far below the 0.6 cap. The different lenses (requirement vs. concept) produced genuinely distinct content, so the confound we guarded against did **not** bite here: this is real friction, not consensus-theater. (Challenges raised: success-metric measures frequency not relevance; per-user-cron + windowing is a DST/“demo-green/prod-noop” trap; substitute saturation — per-project mute is the real lever.)

## Answer to Finding #2

**Does the real challenge gate stay ≤15k?** No — on Opus, a single round's three roles consume ~103k tokens (~6.9× the bound). One over-bound run refutes "the bound always holds." The bound needs either a real enforcement mechanism (a hard-stop that actually counts and truncates) or re-baselining to a measured value — and first, a definition of what "tokens total" counts.

## Limitations / confounds (honest)

1. **Lower bound, not the full gate.** The slice measured ONE round of three independent role outputs. The real gate also runs **≤2 collision rounds** (roles react to each other) and an **orchestrator distillation** of the ≤1-page summary — both omitted. The true cost is **higher** than 103k. Since the floor already exceeds the bound ~7×, this strengthens the verdict.
2. **What "tokens total" counts is undefined — itself a finding.** Under "total tokens consumed (incl. each body's system prompt + Opus extended reasoning)" → ~103k, fails. Under "visible output tokens only" (3 × ≤180 words ≈ ~700) → would pass easily. The prose pairs a *token* total with a *per-role word* cap, which reads as a cost ceiling, making the "total consumed" interpretation the natural one. The bound is not just violated — it is **unmeasurably specified**. The follow-up must define it before any enforcement.
3. **`subagent_tokens` provenance.** Each role's figure includes the full `concilium-*` body system prompt + Opus reasoning + output. The three figures clustered within 0.7% (34,391–34,627) regardless of role content — strong evidence the subagents did **not** inherit the orchestrator's (large, variable) session context, i.e. the number reflects a fresh per-body dispatch, not contamination.
4. **Reach.** n=1, Opus only. This **refutes** "the bound always holds" decisively; it does **not** establish a distribution, and says nothing about sub-Opus models. A distribution (N=3) was deliberately not run — the result is ~7× over, not borderline, so a distribution would not change the verdict (cost ~210k tokens saved).

## Follow-up (triggered)

Open a ticket: **"Challenge-gate token bound — define + enforce or re-baseline."** Options: (a) define "tokens total" precisely; (b) add a real hard-stop that counts tokens and stops at the cap; (c) re-baseline the prose to a measured ceiling. Until then, `concilium.md`'s `≤ ~15k tokens total` should be read as *aspirational, measured-false* (this bench is the evidence).
