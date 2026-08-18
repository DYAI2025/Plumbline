# Product Vision: OpenRouter Inference Path (Slice 1)

Use this canvas to keep product meaning owned by the user. Claude may draft from PRD or conversation context, but every inferred item must stay under `Assumption:` until the user confirms it. Do not treat a PRD-only draft as confirmed Product Vision.

Feature-Slug: openrouter-inference
Slice: 1 of 4 (foundation — inference path only)
Status: user-confirmed
Linked Product Canvas (user-confirmed, Ben 2026-06-19): docs/canvas/openrouter-inference.canvas.md
Linked PRD (draft): docs/prd/openrouter-inference.prd.md

> This Vision is `draft`. It is the customer-value line, not a feature checklist. It stays
> consistent with the **user-confirmed** canvas (problem, target user, value proposition,
> success signal) and the draft PRD's REQ-INF-001..019. The user confirms it at the
> Phase-0.5 gate with the exact phrase below; no agent may self-confirm.

## Target User
Explicit: The Plumbline maintainer / operator (Ben) — he needs a real, governed, budget-safe OpenRouter completion call he can build the council/review agents on, with hard guardrails so experimentation can't run up a surprise bill. (Source: CAN-INF-004, EXPLICIT Ben 2026-06-19)
Assumption: Later-slice Plumbline developers (Slice 2 DeepSeek reviewer, Slice 3 live council) are the secondary user — they need a stable, reusable inference function + classified error codes to call. Also the reviewer/auditor who needs the evidence honestly classified. (Source: CAN-INF-005, CAN-INF-006 — tagged ASSUMPTION in canvas)
Missing: No external/end-user persona — this slice is internal infrastructure. No paying customer beyond Ben's own credit. If there is a downstream human user whose value should be served, it is not named yet.
Source: docs/canvas/openrouter-inference.canvas.md §2 (CAN-INF-004/005/006); docs/prd/openrouter-inference.prd.md GOAL-INF-007.
User decision: (pending Phase-0.5 — confirm that "Ben as maintainer + later-slice developers" is the right and complete user set for this foundation slice; confirm the secondary-developer user is in-scope as an ASSUMPTION not a promise.)

## User Problem
Explicit: Plumbline can prove OpenRouter models are *reachable* (OD-3 catalog smoke) but has **no real inference path** — it cannot send a prompt and get a completion back. "reachable ≠ invocable" is unanswered: a listed model may still return 402/429/5xx for the user's key/credit. AND: a naive inference path can silently burn credits (runaway loops, large contexts, expensive models). (Source: CAN-INF-001, CAN-INF-003, EXPLICIT Ben 2026-06-19)
Assumption: The pain is felt today only as a *blocker* (Slices 2-4 cannot proceed), not yet as money already lost — there is no current overspend incident, the cost danger is anticipated, not observed.
Missing: No quantification of how often Ben hits "is this model actually answering?" today, nor an observed credit-burn event — the cost risk is prospective.
Source: docs/canvas/openrouter-inference.canvas.md §1 (CAN-INF-001/002/003), §3 (CAN-INF-007); docs/prd/openrouter-inference.prd.md §2.
User decision: (pending Phase-0.5 — confirm the problem is correctly framed as "no governed invocability path yet + anticipated spend risk", not "we are bleeding credits now".)

## Desired Change
Explicit: After this slice, Ben can make a single, real `POST .../chat/completions` call with a configurable model id and messages, behind a hard, fail-closed token budget cap checked BEFORE the network call, with a free dry-run mode and classified error codes — and get back either a completion or an honest classified failure, never a leaked key and never a raw traceback. The change for Ben: he can experiment with real non-Claude inference *without fear of an accidental bill* and with an honest answer to "did this model actually answer?". (Source: CAN-INF-008/009/010/016; PRD GOAL-INF-001..006, REQ-INF-001..016)
Assumption: Later-slice developers gain a reusable, stable inference signature returning a classified result object they can branch on deterministically. (Source: CAN-INF-005, PRD REQ-INF-019 — SHOULD/ASSUMPTION)
Missing: Nothing material for Slice 1; the broader "real multi-model council exists" change is explicitly NOT this slice (see Non-Goals).
Source: docs/canvas/openrouter-inference.canvas.md §4, §6; docs/prd/openrouter-inference.prd.md §3, §5, §8.
User decision: (pending Phase-0.5 — confirm the desired change is "governed, budget-safe, honestly-classified single inference call as a foundation", and that proving invocability for ONE probed model is the acceptable bar for this slice.)

## Core Value Promise
Explicit (PROMISE 1 — must not be broken): **Spend money only on purpose.** A hard token cap (`COUNCIL_MAX_TOKENS_PER_RUN`, default 20000), an explicit `max_tokens` actually sent on every request, a pre-call estimate, a fail-closed abort BEFORE any network call, and a free dry-run mode. No silently-spending auto-retry; no auto credit management. (Source: CAN-INF-003/009, PRD REQ-INF-004/006/008/013, NFR-INF-007)
Explicit (PROMISE 2 — must not be broken): **Never overclaim.** Offline tests are `integration-fake` (0 credits). ONE opt-in tiny real smoke earns `real-boundary-smoke` for the ONE probed model only. Broader invocability ("all configured models work") and estimate accuracy stay `RED(confidence)`. RED may not be silently downgraded — only the user reclassifies at the acceptance gate. (Source: CAN-INF-012/014, CAN-INF-EVN-005, PRD REQ-INF-018, EV-INF-008, RISK-INF-006)
Assumption: The two promises are co-equal — neither budget-safety nor honesty may be traded for the other (e.g. you may not relax the cap to make a smoke succeed, nor claim broader invocability to look more "done").
Missing: Nothing — both promises are explicit in canvas and PRD.
Source: docs/canvas/openrouter-inference.canvas.md §1, §4, §8; docs/prd/openrouter-inference.prd.md §1, §5, §6.
User decision: (pending Phase-0.5 — confirm BOTH promises are load-bearing and co-equal: "spend on purpose" AND "never overclaim".)

## Why Now
Explicit: This is the foundation the next three slices (Slice 2 DeepSeek review agent, Slice 3 real 4-body council, Slice 4 GUI) all require. Without a governed, budget-safe inference call, none of them can run for real. It also closes the invocability gap OD-3 deliberately left at `RED(confidence)`. (Source: CAN-INF-002, EXPLICIT Ben 2026-06-19; PRD §2)
Assumption: There is sequencing urgency (Slice 1 unblocks 2-4) but no external deadline.
Missing: No dated deadline or external trigger named.
Source: docs/canvas/openrouter-inference.canvas.md §1 (CAN-INF-002); docs/prd/openrouter-inference.prd.md §1, §2.
User decision: (pending Phase-0.5 — confirm "now" is driven by it being the unblocking foundation for Slices 2-4, not an external deadline.)

## Non-Goals
Explicit: NOT in this slice — the DeepSeek code-review agent (Slice 2); running the 4-body council for real / orchestration (Slice 3); any GUI (Slice 4); auto credit purchase / management / top-up; a USD / max-cost cap (token-only this slice); proving invocability of MORE than the one probed model. (Source: CAN-NGOAL-INF-001..004/006, OQ-1; PRD NGOAL-INF-001..007)
Assumption: Also excluded — streaming, multi-turn conversation state, tool/function calling, model fallback chains; any third-party SDK (stdlib `urllib` only); auto-retry on 429/5xx (fail-closed instead). (Source: CAN-NGOAL-INF-005 ASSUMPTION; PRD NGOAL-INF-005/008/009)
Missing: Nothing material.
Source: docs/canvas/openrouter-inference.canvas.md §7; docs/prd/openrouter-inference.prd.md §4.
User decision: (pending Phase-0.5 — confirm the non-goals, especially: token-only cap with NO USD cap this slice, and stdlib-only / no-SDK / no-auto-retry as deliberate budget-safety choices.)

## Success Signal
Explicit (Slice-1, value-real): (1) The full offline suite (`run_all.sh`) is green with the inference module, exercising config / budget-estimate / dry-run / cap-fail-closed-before-call / error-classification / redaction network-free, 0 credits. (2) A run that would exceed the cap aborts fail-closed with `COUNCIL_BUDGET_EXCEEDED` BEFORE any network call (proven offline). (3) ONE opt-in real smoke sends a tiny `chat/completions` to the configured (free-by-default) model and returns a non-empty completion OR a classified code, with leak-check = 0, recorded in `docs/benchmarks/2026-06-19-openrouter-inference-smoke.md` — earning `real-boundary-smoke` for that one model only. (Source: CAN-INF-013/014/015; PRD AC-INF-002/004/014/015, EV-INF-006)
Assumption: The signal of "value delivered" for Ben is that he can run the smoke once, see a real completion (or an honest classified failure) and trust that no run can spend beyond the cap — i.e. confidence to build Slice 2 on it.
Missing (broader-arc, DEFERRED — NOT Slice-1 scope): The **diversity value** (uncorrelated cognition) is asserted, not measured. Slice 3 MUST report a Claude-only vs multi-model catch-rate / cry-wolf delta. Recorded here so the "uncorrelated cognition is valuable" premise stays falsifiable; owner: retro-analyst / metrics. (Source: PRD AC-INF-017 [DEFERRED]; carried from the council Critic.)
Source: docs/canvas/openrouter-inference.canvas.md §5; docs/prd/openrouter-inference.prd.md §8, AC-INF-017.
User decision: (pending Phase-0.5 — confirm the Slice-1 success signal is offline-green + cap-fail-closed + ONE honest smoke; and ACKNOWLEDGE the deferred diversity-value falsifier as a Vision-level forward obligation for Slice 3, not Slice 1.)

## Risks if Misbuilt
Explicit (what makes it useless / harmful despite passing tests):
- A cap that isn't really enforced — e.g. no `max_tokens` actually sent on the request, or the cap checked only AFTER the call. This breaks PROMISE 1 and is FORBIDDEN. (RISK-INF-002, REQ-INF-004, NFR-INF-007)
- A silently-spending auto-retry on 429/5xx that multiplies spend. Forbidden — fail closed instead. (PRD REQ-INF-013, NGOAL-INF-009)
- The API key leaking into logs / returned dict / error output. (RISK-INF-001, NFR-INF-001)
- Overclaiming: presenting offline tests OR a single-model smoke as broader "real model diversity / invocability proven". (RISK-INF-006, breaks PROMISE 2)
- Freezing the OpenRouter `chat/completions` contract from memory: the request/response shape and the `usage` fields the estimate relies on are `ungeprüft` until verified live at the smoke (OQ-3). Building the estimate/reconciliation on an unverified contract is a false premise. (RISK-INF-003, REQ-INF-018)
Assumption: A subtler misbuild — making the smoke "succeed" by quietly loosening the cap or picking a model to flatter the result — would technically pass but betray both promises.
Missing: Nothing material.
Source: docs/canvas/openrouter-inference.canvas.md §8 (RISK-INF-001..008); docs/prd/openrouter-inference.prd.md §6, §10, §11.
User decision: (pending Phase-0.5 — confirm these are the wrong/harmful implementations to guard against; in particular that "cap not truly enforced", "silent auto-retry", "key leak", and "overclaiming invocability" are each disqualifying.)

## QA Value Checks
Explicit (VCHK — what QA must verify as customer VALUE, not just function):
- VCHK-INF-01 (spend-on-purpose, proven offline): a run whose estimate exceeds the cap makes ZERO network calls and returns `COUNCIL_BUDGET_EXCEEDED` (fake transport asserts zero calls). Ties to AC-INF-002. The *value*: Ben cannot accidentally spend.
- VCHK-INF-02 (dry-run is free): dry-run returns the `≈` estimate with NO network call, 0 credits. Ties to AC-INF-004. The *value*: Ben can preview cost before paying anything.
- VCHK-INF-03 (no key leak): the raw key never appears in any config / result / error / output. Ties to AC-INF-011/012, NFR-INF-001. The *value*: experimentation can't exfiltrate the secret.
- VCHK-INF-04 (honest invocability, not overclaimed): the ONE opt-in smoke earns `real-boundary-smoke` for the probed model ONLY; a free-model 402/429 is a classified result, not a code failure; broader invocability + estimate accuracy stay `RED(confidence)`. Ties to AC-INF-015, EV-INF-008. The *value*: Ben/auditor can trust the evidence class is not inflated.
- VCHK-INF-05 (contract verified live, not from memory): the real `chat/completions` request/response + `usage` fields are confirmed and recorded at the smoke; until then `ungeprüft`. Ties to AC-INF-016, OQ-3. The *value*: the budget guard rests on the real API, not a guess.
- VCHK-INF-06 (no silent multiplier): a 429 returns `COUNCIL_RATE_LIMITED` with exactly one call asserted — no auto-retry. Ties to AC-INF-007. The *value*: a rate-limit can't quietly become N billed calls.
Assumption: VCHK-INF-04/05 are the two checks that most directly defend "never overclaim"; a green suite that skips them would be function-real but not value-real.
Missing (DEFERRED, Vision-level, NOT Slice-1 QA): a value check that the multi-model diversity actually catches things Claude-only misses — deferred to Slice 3 (Claude-only vs multi-model catch-rate / cry-wolf delta). Recorded so it is not forgotten.
Source: docs/canvas/openrouter-inference.canvas.md §5, §9; docs/prd/openrouter-inference.prd.md §8 (AC-INF-*), §9 (EV-INF-*).
User decision: (pending Phase-0.5 — confirm these VCHKs are the customer-value checks QA must prove, and confirm the deferred diversity-value check belongs to Slice 3.)

## User Confirmation
Explicit: This Vision is `draft`. It restates the user-confirmed canvas's value line and the draft PRD's requirements without adding new product meaning. The user confirms at the Phase-0.5 gate.
Assumption: On confirmation, Status flips to `confirmed` and planning may proceed (subject to the Plumbline Watcher verdict `pass`).
Missing: User confirmation itself (this is the artifact awaiting it).
Source: docs/canvas/openrouter-inference.canvas.md §10, "User confirmation"; docs/prd/openrouter-inference.prd.md §12 DoD.
User decision: CONFIRMED by Ben, 2026-06-19 at the /agileteam Phase-0.5 gate (basis for AgileTeam planning).

Required confirmation phrase:

```text
I confirm this Product Vision as the basis for AgileTeam planning.
```

Status: user-confirmed
Confirmed by: Ben
Confirmed at: 2026-06-19
Open contradictions: none at draft time. Carried-forward open item (NOT a Slice-1 blocker): OQ-3 — the OpenRouter `chat/completions` external contract is `ungeprüft` until verified live at the smoke; it may not be frozen as a working premise nor downgraded to a "documented risk". Carried-forward deferred falsifier: the diversity value (uncorrelated cognition) is asserted, not measured — Slice 3 must report the Claude-only vs multi-model catch-rate / cry-wolf delta.
