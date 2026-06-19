# Product Vision: Foreign-Model Council Bodies + Character/Preset Composition for /concilium (Slice 2)

Feature-Slug: deepseek-review-agent
Slice: 2 of 4
Status: user-confirmed (Ben 2026-06-19; confirmed together with the PRD at the Phase-0 gate)
Owner: product-owner
Confirmed by user: yes (Ben 2026-06-19)

Linked Product Canvas (user-confirmed, Ben 2026-06-19): docs/canvas/deepseek-review-agent.canvas.md
Linked PRD: docs/prd/deepseek-review-agent.prd.md (REQ-DS-001..016)
Traceability: docs/traceability.md (slice deepseek-review-agent)

> This Vision is bound to the confirmed Canvas and the PRD above and must stay consistent
> with them. It is the customer-value line — the *direction* — not a second PRD. Where the
> Canvas/PRD say HOW, this says WHO it is for, WHAT changes for them, and WHAT would make it
> useless despite passing tests. The honesty split below is load-bearing and survives every
> rewrite: **Slice 2 ships a CAPABILITY + INTEGRATION, not a measured VALUE.**

---

## 1. North Star (the confirmed customer value — GOAL, not yet evidence)

`/concilium` exists to convene a council whose entire worth rests on **diverse, uncorrelated
perspectives under friction**. Today every body runs on Claude-family cognition — effectively
4× Claude — so the council shares the very bias blind spots it was built to break.

The north star: **`/concilium` runs its bodies on real foreign (non-Claude) models →
genuinely uncorrelated cognition → fewer SHARED bias blind spots → higher review/judgment
quality.**

This is the *direction the slice serves*. It is stated here as a GOAL. It is **not** claimed
as achieved evidence — whether foreign cognition actually catches more, or is genuinely
uncorrelated, is the **deferred Slice-3 measurement** (see §5). Reaching the real boundary at
all is governed by the model/run on the day, not by prompt cleverness — a free model can 402 /
429 / time out, and the honest outcome of a real call is "a real position came back" *or* a
cleanly-classified failure code, never a manufactured success.

**The default model is a dynamic preference-ordered free-model resolver — NOT a hardcoded
"DeepSeek default" (BLOCKER-1, Ben 2026-06-19).** A live OpenRouter catalog check found there is
**NO free DeepSeek model** today, so a hardcoded "free DeepSeek default" would be a `do-not-claim`
over-claim. Instead the default is resolved AT RUNTIME against the live catalog by a named,
editable preference-ordered family list (DeepSeek v4 → Qwen3.x → Kimi K2.7 → Kimi K2.6 → GLM 5.x →
OpenRouter free-routing), picking the first family available as `:free`. **DeepSeek is the top
preference when free-available and otherwise a configurable PAID override** — paid DeepSeek is
never auto-selected (it would incur cost); the resolver only ever auto-picks a `:free` model
(REQ-DS-015). The feature keeps the `deepseek-review-agent` slug (DeepSeek is the headline
configurable model) but Slice 2 does not claim it as the realized default.

---

## 2. Who benefits, and what changes for them

- **Ben / the Plumbline operator.** Today, getting a foreign-model perspective into the
  council is a manual copy/paste into an external chat — no budget guard, no key discipline,
  no integration with the council flow. After Slice 2 they can select a role-composition
  PRESET (A/B/C, or the default) and have its CHARACTERS actually run on real foreign models
  through the governed inference path — each role's model dynamically resolved to a free
  catalog model by the preference-ordered resolver (REQ-DS-015) unless explicitly overridden —
  with the Slice-1 per-call token cap (fail-closed), key-safety, and classified failure codes
  inherited for free. The council stops being
  aspirationally diverse and becomes *mechanically* diverse: real non-Claude bodies, really
  running.

- **The Slice-3 developer (the measurement owner).** They need a real, reusable multi-model
  council to *measure* — there is nothing to compute a Claude-only-vs-multi-model catch-rate /
  cry-wolf delta against until a full preset of foreign characters can actually run and return
  real positions. Slice 2 hands them exactly that substrate, with the diversity gate already
  applied over the resolved preset. Without this slice, Slice-3's measurement has no
  instrument; the OD-3 diversity gate guards a council that is still single-cognition.

- **The reviewer / auditor.** They benefit from the *honesty* itself: a record where the
  capability is classified at its true evidence class — offline assembly and the `concilium.md`
  wiring are `integration-fake`; the one full-preset live smoke is `real-boundary-smoke` for
  that run only; and the quality/diversity lift is explicitly NOT claimed. The value here
  includes refusing to over-claim.

## 3. When they would use it

When convening a council on a real subject (a product idea, a design, a diff) and wanting
genuinely foreign cognition in the room — picking a preset whose roles are mapped to
characters and to real non-Claude models (default resolved dynamically to a free catalog model
by the preference-ordered resolver, per-role overridable), exercised offline at zero credits, and
provable live via one opt-in full-preset smoke.

---

## 4. What "true to value" means here (True-Line discipline)

Success is **staying true to the confirmed value**, not "finishing" and not "tests green."
Concretely, this slice is true to value when:

- A full preset of foreign characters **really runs** and **real positions come back** — that
  full-preset live run is the `real-boundary-smoke` (each role / character / model run for
  real). This is the customer-value proof for the run, and it must be earned by the run, never
  hand-fed (RISK-DS-005: never tune the subject/prompt to manufacture a "good" position; never
  hand-feed the input-token heuristic it measures).
- The capability is **honestly classified** — offline `integration-fake`, the one full-preset
  live run `real-boundary-smoke`, the `concilium.md` wiring `integration-fake` (markdown
  instructs; live orchestrator obedience is unproven by code).
- Foreign cognition is **really foreign** — a role that cannot run on its resolved foreign
  model returns its classified `COUNCIL_*` code; there is **no silent Claude fallback** (any
  fallback is disclosed). A silent Claude substitution would defeat the council's entire
  purpose invisibly — that is the value-killer, not a passing test.
- The diversity gate stays an **honest structural floor** — ≥2 distinct normalized base models
  over the resolved preset, carrying RISK-B-007 verbatim: distinct model ids ≠ uncorrelated
  cognition. The gate is not allowed to read as proof of perspective diversity.

The classic Reality-Ledger Gegenthese to hold against this slice at the final gate: *could it
be fully green yet deliver zero user value?* — e.g. a preset that assembles perfectly offline
but no role ever crosses a real boundary; or a smoke that "passes" by quietly substituting
Claude; or a benchmark that reports diversity the run never proved. Any such shape is RED and
may not be downgraded to a known limitation except by the user.

---

## 5. Explicit non-claims (the deferred value — do NOT read as proven here)

Stating the north star as a goal while refusing to claim it as evidence is itself part of the
value. This slice does **NOT** prove or claim:

- **The quality lift** — "the foreign body/preset catches what Claude misses" / "the council
  is now more diverse / higher quality." This is the deferred **Slice-3 measurement**
  (Claude-only vs. multi-model catch-rate / cry-wolf delta; owner retro-analyst / metrics) —
  NGOAL-DS-003 / NGOAL-DS-011. The carried falsifier.
- **Proven-uncorrelated cognition** — distinct model ids are a structural floor, not proof
  (RISK-DS-004 / RISK-B-007). N distinct characters on N distinct ids still does not prove
  uncorrelated cognition.
- **Live orchestrator obedience** — `concilium.md` wiring is `integration-fake`.
- **A general live capability** — only the ONE opt-in full-preset (4-role) live smoke earns
  `real-boundary-smoke`, and for that run only. `run_all.sh` makes zero live calls.

Adding presets, characters, and a full-preset-live smoke proves the **CAPABILITY**. It does
not let Slice 2 claim the **lift**.

---

## 6. Success signals (already in the Canvas — VCHK customer-value checks)

- **VCHK-DS-1** — Offline suite (`run_all.sh`) green, 0 credits: character XML extraction
  (valid + every fail-closed branch), body-prompt loading, full preset resolution (unknown
  preset / unknown slug / model-unresolvable each a named fail-closed error), per-role model
  precedence (field > env > free default), diversity gate over the resolved set, position
  wrapping, per-call budget fail-closed, key leak-check = 0, live-gate-off-by-default.
  (CAN-DS-014/025, REQ-DS-010.)
- **VCHK-DS-2** — ONE opt-in FULL-preset (4 roles) live smoke (`--live` +
  `COUNCIL_INFERENCE_LIVE=1`, OUTSIDE `run_all.sh`): each role returns its real prose position
  or its own classified code; leak-check = 0 across all calls; recorded with each role's model
  id + character slug + result. Earns `real-boundary-smoke` for that run. (CAN-DS-PRE-026,
  REQ-DS-011.) — this is the load-bearing customer-value signal.
- **VCHK-DS-3** — No key leak anywhere (presence-only, header-only). (NFR-DS-SEC-1.)
- **VCHK-DS-4** — No over-claim: the smoke benchmark explicitly records what it does NOT prove
  (no catch-rate, no cry-wolf, no proven diversity, no quality lift); no silent Claude
  fallback; diversity gate carries RISK-B-007. (CAN-DS-017, CAN-DS-EVN-007, RISK-DS-001/002.)

---

## 7. Traceability links

Product Canvas: docs/canvas/deepseek-review-agent.canvas.md (user-confirmed, Ben 2026-06-19)
PRD: docs/prd/deepseek-review-agent.prd.md (REQ-DS-001..016)
Traceability Matrix: docs/traceability.md (slice deepseek-review-agent)
Reality Ledger (authored Phase 3 / Gate C): docs/reality/deepseek-review-agent.evidence.jsonl
Smoke benchmark: docs/benchmarks/2026-06-19-deepseek-review-smoke.md

True-Line status: draft — Vision NOT self-confirmed. Phase 0 completes only when BOTH the PRD
and this Vision are user-confirmed together at the next gate.
