# Traceability Matrix

Status: user-confirmed (both slices, Ben, 2026-06-18)

This matrix threads REQ ↔ vision ↔ canvas ↔ acceptance ↔ evidence ↔ wired-in-prod ↔
evidence-class ↔ True-Line status. `evidence-class` ∈
`unit-fake | integration-fake | real-boundary-smoke | production-verified`. A feature
touching I/O / remote / UI that stays `*-fake` is RED regardless of green tests.

---

## Slice: Runtime Start Governance (BL-002 / BL-003)

- Feature-Slug: runtime-start-governance
- canvas-link: docs/canvas/runtime-start-governance.canvas.md
- vision-link: docs/vision/runtime-start-governance.vision.md

| Trace ID | Requirement | Canvas | Acceptance | Evidence | wired-in-prod? | evidence-class (target) | True-Line |
|---|---|---|---|---|---|---|---|
| TRC-A-001 | REQ-A-001 (command-level Gate konsumiert Verdict, HALT vor Planning) | CAN-A-010 | AC-A-001 | EV-A-002 | instruction-only (cmd); realer HALT via Hook TRC-A-011 | real-boundary-smoke | pass |
| TRC-A-002 | REQ-A-002 | CAN-A-011 | AC-A-001 | EV-A-001, EV-A-004 | instruction-only | integration-fake | pass |
| TRC-A-003 | REQ-A-003 | CAN-A-012 | AC-A-002 | EV-A-001, EV-A-002, EV-A-004 | yes — Hook denied Planning (trace §2) | real-boundary-smoke | pass |
| TRC-A-004 | REQ-A-004 | CAN-A-012 | AC-A-003 | EV-A-001, EV-A-002, EV-A-004 | yes — Hook denied Coding (trace §3) | real-boundary-smoke | pass |
| TRC-A-005 | REQ-A-005 | CAN-A-013 | AC-A-004 | EV-A-002, EV-A-004 | instruction-only | integration-fake | pass |
| TRC-A-006 | REQ-A-006 (behavioraler real-boundary-Trace) | CAN-A-013 | AC-A-005 | EV-A-002 | yes — trace artifact (real run) | real-boundary-smoke | pass |
| TRC-A-007 | REQ-A-007 (LOCAL-Session, steuernd nicht fatal) | CAN-A-012 | AC-A-002, AC-A-003 | EV-A-002, EV-A-004 | yes — Hook fail-open (trace §5 + tests) | real-boundary-smoke | pass |
| TRC-A-008 | REQ-A-008 (Reuse, keine Duplizierung) | CAN-A-010 | AC-A-001 | EV-A-001 | instruction-only (Reuse per Test geprüft) | integration-fake | pass |
| TRC-A-009 | REQ-A-009 | CAN-A-011 | AC-A-001..005 | EV-A-001, EV-A-004 | instruction-only | integration-fake | pass |
| TRC-A-010 | REQ-A-010 | CAN-A-013 | AC-A-005 | EV-A-002 | instruction-only | integration-fake | pass |
| TRC-A-011 | REQ-A-011 (PreToolUse-Hook-Backstop, harness-erzwungen) | CAN-A-014 | AC-A-006 | EV-A-005 | yes — install.sh→settings.json PreToolUse (trace §2-4) | real-boundary-smoke | pass |

**BL-002/BL-003 closure (F3) — Stand 2026-06-18:** Der **Hook-Backstop (TRC-A-011)** und die
darüber getragenen Planning/Coding-Block-Zeilen (TRC-A-003/004/006/007) haben
`real-boundary-smoke` erreicht: reale Planning/Coding-Dispatches werden an der PreToolUse-
Prozessgrenze verweigert (Trace §2-4), wired via `install.sh`→`settings.json`. Der
**command-level Gate-HALT durch ein lebendes Modell (TRC-A-001/002/005/008/009/010)** bleibt
`integration-fake` und liest **PASS(tests)/RED(confidence)** — der Runtime bietet keinen
skriptbaren Zugriff auf den Kontrollfluss des Orchestrators, um „Planning nicht betreten"
modellseitig zu beweisen. Dieser RED darf NICHT heruntergestuft werden; nur der User darf am
Acceptance-Gate reklassifizieren.

**User-Reklassifizierung am Acceptance-Gate (Ben, 2026-06-18):** Der Hook-Layer
(TRC-A-011 + getragene Block-Zeilen) wird als `real-boundary-smoke` **akzeptiert und
geschlossen** (BL-002). Der command-gate Live-Modell-HALT bleibt `RED(confidence)` und wird
**als Ceiling akzeptiert** (BL-003) — nicht als „proven" deklariert, da der Runtime keinen
Kontrollfluss-Probe bietet. Die `Bash`-Tool-Lücke ist als v1-Boundary akzeptiert (Follow-up
BL-005). Kein autonomes Schließen erfolgte vor dieser User-Entscheidung.

**EDGE-A-002 (F2, verifiziert):** PRD-present + Vision-vorhanden-aber-unconfirmed →
`VISION_MISSING` (Kurzschluss `plumbline_start.py:25`). `START_ARTIFACTS_MISSING` ist ein
separater Branch, nur erreichbar bei BESTÄTIGTER Vision + fehlendem Canvas/Traceability.

---

## Slice: OpenRouter Council Backend (OD-3)

- Feature-Slug: openrouter-council-backend
- canvas-link: docs/canvas/openrouter-council-backend.canvas.md
- vision-link: docs/vision/openrouter-council-backend.vision.md

| Trace ID | Requirement | Canvas | Acceptance | Evidence | wired-in-prod? | evidence-class (target) | True-Line |
|---|---|---|---|---|---|---|---|
| TRC-B-001 | REQ-B-001 | CAN-B-011 | AC-B-006 | EV-B-002 | cmd instruction-only (int-fake) | real-boundary-smoke | pass |
| TRC-B-002 | REQ-B-002 | CAN-B-011 | AC-B-001 | EV-B-001 | yes — tests (int-fake) | integration-fake | pass |
| TRC-B-003 | REQ-B-003 | CAN-B-011 | AC-B-009 | EV-B-003, EV-B-006 | yes — .env.example + .gitignore | integration-fake | pass |
| TRC-B-004 | REQ-B-004 | CAN-B-012 | AC-B-001 | EV-B-001 | yes — tests (int-fake) | integration-fake | pass |
| TRC-B-005 | REQ-B-005 | CAN-B-012 | AC-B-001 | EV-B-001 | yes — tests (int-fake) | integration-fake | pass |
| TRC-B-006 | REQ-B-006 | CAN-B-012 | AC-B-001 | EV-B-001 | yes — tests (int-fake) | integration-fake | pass |
| TRC-B-006b | REQ-B-006b | CAN-B-012 | AC-B-001 | EV-B-001 | yes — tests (int-fake) | integration-fake | pass |
| TRC-B-007 | REQ-B-007 | CAN-B-012 | AC-B-002 | EV-B-001 | yes — tests (int-fake) | integration-fake | pass |
| TRC-B-008 | REQ-B-008 | CAN-B-012 | AC-B-003 | EV-B-001 | yes — tests (int-fake) | integration-fake | pass |
| TRC-B-009 | REQ-B-009 | CAN-B-010 | EDGE-B-003 | EV-B-002 | yes — tests (int-fake) | integration-fake | pass |
| TRC-B-010 | REQ-B-010 | CAN-B-013 | AC-B-007 | EV-B-004 | yes — tests (int-fake) | integration-fake | pass |
| TRC-B-011 | REQ-B-011 | CAN-B-014 | AC-B-004..006, EV-B-007 | EV-B-002, smoke §1/§2 | real-boundary-smoke: catalog reachability live-verified; invocability RED(conf) | real-boundary-smoke | pass |
| TRC-B-012 | REQ-B-012 | CAN-B-014 | AC-B-004, AC-B-005 | EV-B-002 | gate logic tested (int-fake); real RED(conf) | real-boundary-smoke | pass |
| TRC-B-013 | REQ-B-013 | CAN-B-014 | AC-B-010 | EV-B-002 | logic tested (int-fake); real RED(conf) | real-boundary-smoke | pass |
| TRC-B-014 | REQ-B-014 | CAN-B-015 | AC-B-008 | EV-B-005 | yes — tests (int-fake) | integration-fake | pass |
| TRC-B-015 | REQ-B-015 | CAN-B-016 | AC-B-001..010 | EV-B-001..005 | yes — tests run offline | integration-fake | pass |
| TRC-B-016 | REQ-B-016 | CAN-B-011 | AC-B-009 | EV-B-003 | yes — tests (int-fake) | integration-fake | pass |
| TRC-B-017 | REQ-B-017 | CAN-B-014 | AC-B-004, AC-B-005, AC-B-010 | EV-B-002 | logic tested (int-fake); real RED(conf) | real-boundary-smoke | pass |
| TRC-B-018 | REQ-B-018 | CAN-B-011 | EDGE-B-004 | EV-B-002 | yes — tests (int-fake) | integration-fake | pass |
| TRC-B-019 | REQ-B-019 | CAN-B-013, CAN-B-015 | AC-B-008 | EV-B-004, EV-B-005 | yes — tests (int-fake) | integration-fake | pass |
| TRC-B-020 | REQ-B-020 | CAN-B-014 | AC-B-010 | EV-B-002 | cmd instruction-only (int-fake) | integration-fake | pass |

**Reality Ledger (OD-3, honest ceiling) — updated 2026-06-18 after the real-boundary smoke:**
- The config/redaction/prompt/report/fail-closed LOGIC is `integration-fake` (offline, injected reachability).
- **TRC-B-011 reachability is now `real-boundary-smoke`:** the catalog-/list-models method was run
  **live against the OpenRouter API** with a real key (`docs/benchmarks/2026-06-18-openrouter-council-backend-smoke.md`
  §1: two distinct normalized bases reachable → proceed; §2: `:nitro`/`:floor` collapse to one → abort).
  The key never leaked (leak-check = 0).
- **Still `PASS(tests)/RED(confidence)`:** **invocability** (reachable ≠ invocable — a listed model may
  still 402/429; no completion probe was run, NGOAL-B-004) and **deep model diversity** (RISK-B-007 —
  two distinct base slugs could still be mirrored/similar models). The command-gate wiring
  (TRC-B-001/B-020) remains `cmd instruction-only (int-fake)`.
This RED may not be downgraded; only the user may reclassify at the acceptance gate.

**User acceptance (Ben, 2026-06-18):** OD-3 accepted — catalog-reachability + normalized-base
diversity gate accepted as `real-boundary-smoke`; **invocability and deep model diversity
accepted as ceiling at `RED(confidence)`** (a paid completion probe was not required). The
invocability probe remains an optional future step; not claimed proven.

---

## Slice: OpenRouter Inference Path (openrouter-inference / Slice 1 of 4)

- Feature-Slug: openrouter-inference
- canvas-link: docs/canvas/openrouter-inference.canvas.md
- vision-link: docs/vision/openrouter-inference.vision.md
- Extends: OD-3 (openrouter-council-backend) — closes its invocability RED.

| Trace ID | Requirement | Canvas | Acceptance | Evidence | wired-in-prod? | evidence-class (target) | True-Line |
|---|---|---|---|---|---|---|---|
| TRC-INF-001 | REQ-INF-001 (real POST /chat/completions) | CAN-INF-008 | AC-INF-001 | EV-INF-003 (smoke) | yes — see reality ledger for class | real-boundary-smoke (1 model only) | pass |
| TRC-INF-002 | REQ-INF-003 (stdlib urllib, no SDK) | CAN-INF-008 | AC-INF-003 | EV-INF-001 | yes — see reality ledger for class | integration-fake | pass |
| TRC-INF-003 | REQ-INF-004 (max_tokens MUST be sent) | CAN-INF-009 | AC-INF-001/002 | EV-INF-001 | yes — see reality ledger for class | integration-fake | pass |
| TRC-INF-004 | REQ-INF-005/006 (estimate + cap pre-call, fail-closed) | CAN-INF-009 | AC-INF-002 | EV-INF-001 | yes — see reality ledger for class | integration-fake | pass |
| TRC-INF-005 | REQ-INF-008 (dry-run, 0 credits) | CAN-INF-009 | AC-INF-004 | EV-INF-001 | yes — see reality ledger for class | integration-fake | pass |
| TRC-INF-006 | REQ-INF-009 (post-call reconcile vs usage) | CAN-INF-EVN-004 | AC-INF-005 | EV-INF-003 (smoke) | yes — see reality ledger for class | real-boundary-smoke | pass |
| TRC-INF-007 | REQ-INF-010 (free default, configurable, runtime-verified) | CAN-INF-008 | AC-INF-010 | EV-INF-001/003 | yes — see reality ledger for class | integration-fake | pass |
| TRC-INF-008 | REQ-INF-011 (key presence-only, never leaked) | CAN-INF-011 | AC-INF-011 | EV-INF-002 | yes — see reality ledger for class | integration-fake | pass |
| TRC-INF-009 | REQ-INF-012/013 (finer 402/429/5xx/timeout codes; 429 fail-closed) | CAN-INF-010 | AC-INF-006..009 | EV-INF-001 | yes — see reality ledger for class | integration-fake | pass |
| TRC-INF-010 | REQ-INF-015 (tests network-free, 0 credits) | CAN-INF-EVN-001 | AC-INF-012 | EV-INF-001 | yes — see reality ledger for class | integration-fake | pass |
| TRC-INF-011 | REQ-INF-016/017 (smoke out-of-CI, classifies-not-crashes) | CAN-INF-EVN-003 | AC-INF-015 | EV-INF-003 | yes — see reality ledger for class | real-boundary-smoke (1 model only) | pass |
| TRC-INF-012 | REQ-INF-018 (chat/completions contract ungeprüft until smoke) | CAN-INF-EVN-004 | AC-INF-005 | EV-INF-003 | yes — see reality ledger for class | OPEN (OQ-3, ungeprüft) | pass |

**Reality Ledger (OI, honest ceiling):** offline logic = `integration-fake`. Invocability +
post-call `usage` reconciliation reach `real-boundary-smoke` only via the ONE opt-in smoke,
for the ONE probed model only (EV-INF-003). Estimate-accuracy, broader invocability, and the
`cost`-field assumption stay `PASS(tests)/RED(confidence)` / `ungeprüft` (OQ-3) — only the user
reclassifies at the acceptance gate.

**BUILT + live smoke (2026-06-19):** module `config/claude/lib/council_inference.py` (75/75
offline), wired into `run_all.sh`. Live opt-in smoke
(`docs/benchmarks/2026-06-19-openrouter-inference-smoke.md`): invocability **proven** for
`nex-agi/nex-n2-pro:free` (real completion, key leak-check=0, $0), the module's own input
heuristic drift **measured live** (heuristic 10 vs real prompt_tokens 18 → +8; no hand-supplied
estimate), and an unavailable free model
**classified** not crashed (TRC-INF-001/006/009/011 → `real-boundary-smoke`, 1 model only). All
offline rows = `integration-fake`. OQ-3 contract partially verified live (`usage` confirmed; no
`cost` field assumed). Broader invocability + general estimate accuracy stay RED(confidence).

## Slice: Foreign-Model Council — Character/Preset Composition (deepseek-review-agent / Slice 2 of 4)

- Feature-Slug: deepseek-review-agent
- canvas-link: docs/canvas/deepseek-review-agent.canvas.md (user-confirmed, Ben 2026-06-19)
- vision-link: docs/vision/deepseek-review-agent.vision.md (user-confirmed)
- reality-ledger: docs/reality/deepseek-review-agent.evidence.jsonl
- benchmark: docs/benchmarks/2026-06-19-deepseek-review-smoke.md

| Trace ID | Requirement | Canvas | Evidence | wired-in-prod? | evidence-class (target) | True-Line |
|---|---|---|---|---|---|---|
| TRC-DS-001 | REQ-DS-001 (body prompt → messages; missing/traversal classified) | CAN-DS-009/018 | test_deepseek_review.sh | yes — see reality ledger | integration-fake | pass |
| TRC-DS-002 | REQ-DS-002 (character XML system-prompt extraction; 4 fail classes) | CAN-DS-CHR-020 | test + smoke §Macherin | yes — see reality ledger | integration-fake + real-boundary-smoke (1 char run) | pass |
| TRC-DS-004 | REQ-DS-004 (preset resolution; unknown-preset/slug/model fail-closed; no silent Claude fallback) | CAN-DS-PRE-021 | test_deepseek_review.sh | yes — see reality ledger | integration-fake | pass |
| TRC-DS-006 | REQ-DS-006 (diversity via distinct_base_count over resolved preset; RISK-B-007) | CAN-DS-PRE-023 | smoke (distinct_bases 4 live) + test (collapse) | yes — see reality ledger | real-boundary-smoke + integration-fake | pass |
| TRC-DS-008 | REQ-DS-008 (per-call token cap fail-closed; no aggregate cap, accepted) | CAN-DS-010 | test_deepseek_review.sh | yes — see reality ledger | integration-fake | pass |
| TRC-DS-013 | REQ-DS-013 (key presence-only, never leaked; eval-injection in test harness fixed) | CAN-DS-EVN-006 | smoke (leak-check=0) + security review | yes — see reality ledger | real-boundary-smoke | pass |
| TRC-DS-015 | REQ-DS-015 (dynamic preference-ordered free-model resolver over LIVE catalog; fail-closed) | CAN-DS-RES-029 | smoke (live fetch wired + reached) + test (paired falsifier) | yes — see reality ledger | real-boundary-smoke + integration-fake | pass |
| TRC-DS-016 | REQ-DS-016 (Slice-1 stale default fixed → live-verified free id) | CAN-DS-RES-029 | test_council_inference.sh 75/75 | yes — see reality ledger | integration-fake | pass |
| TRC-DS-012 | REQ-DS-012 (concilium.md wiring routes a body through the runner) | CAN-DS-019 | concilium.md Step 0.7 | cmd instruction-only | integration-fake | pass |

**Reality Ledger (DS, honest ceiling):** offline logic = `integration-fake`. The dynamic live
catalog fetch, the distinct-family diversity distribution, ONE character running on a real
foreign model, classified per-role failures, and key-leak=0 reach `real-boundary-smoke` via the
ONE opt-in full-preset live smoke. The diversity/quality **LIFT** ("foreign cognition catches
more / is genuinely uncorrelated") is NOT claimed — deferred Slice-3 measurement (NGOAL-DS-003).
Distinct model ids are a structural floor, not proof of uncorrelated cognition (RISK-B-007).

**BUILT + live smoke (2026-06-19):** modules `config/claude/lib/{deepseek_review,council_presets}.py`
(126/126 offline), wired into `run_all.sh`; Slice-1 default fixed (75/75), OD-3 unchanged (59/59).
Full-preset live smoke (`docs/benchmarks/2026-06-19-deepseek-review-smoke.md`): preset A resolved
**4 distinct free families live** (`COUNCIL_DIVERSITY_OK`), die-macherin returned a real
in-character position on `google/gemma-4-26b-a4b-it:free`, three roles **classified** (2
rate-limited, 1 unavailable — RISK-DS-007 confirmed: reachable ≠ invocable), key leak-check = 0.
The smoke CAUGHT a wired-in-prod defect (the live catalog fetch was never wired → fixed + paired
regression test). Capability proven end-to-end; broader invocability + the quality lift stay
RED(confidence) — only the user reclassifies at the acceptance gate.

## Slice: Council Diversity Measurement — Slice 3a: the measurement SUBSTRATE (council-diversity-measurement / 3a of 4)

- Feature-Slug: council-diversity-measurement (Slice 3 SPLIT: 3a substrate / 3b deferred measurement run)
- canvas-link: docs/canvas/council-diversity-measurement.canvas.md (user-confirmed, re-scoped after spec-auditor 4 BLOCKERs, Ben 2026-06-19)
- vision-link / prd-link: docs/vision/ + docs/prd/council-diversity-measurement.* (user-confirmed)
- reality-ledger: docs/reality/council-diversity-measurement.evidence.jsonl

| Trace ID | Requirement | Evidence | wired-in-prod? | evidence-class | True-Line |
|---|---|---|---|---|---|
| TRC-DM-3a-001 | REQ-DM-3a-001 (frozen council-independent review-catch corpus; seeded-defect oracle + clean controls + recall control + >=2-outcome variance; oracle<->diff fidelity) | metrics/corpus/council-review-catch-v1/ + test (incl. BLOCKER-1 fidelity falsifier) | n/a — offline substrate | integration-fake | pass |
| TRC-DM-3a-002 | REQ-DM-3a-002 (Arm-A Claude-only review runner; structured flag protocol; separate entrypoint, instrument byte-unchanged) | test_arm_a_review_runner.sh (offline injected transport, live-gate off) | live path DEFERRED to 3b | integration-fake | pass |
| TRC-DM-3a-004 | REQ-DM-3a-004 (deterministic location-overlap matcher; judge-free; import-pure) OQ-DM-7 | test_council_review_scorer.sh | n/a | integration-fake | pass |
| TRC-DM-3a-003 | REQ-DM-3a-003 (both metric families together: catch + cry-wolf + recall; n/scope; foreign_only_ok) | test_council_review_scorer.sh | n/a | integration-fake | pass |
| TRC-DM-3a-005 | REQ-DM-3a-005 (emit-blob review metrics via --raw; round-trip vs real emit_run.py) | test + emit_run --dry-run | n/a | integration-fake | pass |

**Reality Ledger (DM-3a, honest ceiling):** the WHOLE slice is `integration-fake` — 3a builds + offline-validates the measurement substrate and **produces NO measurement number**. There is deliberately NO `real-boundary-smoke` here: the Arm-A runner's live call and the actual Arm-A-vs-Arm-B measurement RUN (with the paid pilot + pre-registered pass/fail eval) are the DEFERRED Slice-3b work (backlog BL-DM-002). The independent code-reviewer caught + measured a BLOCKER (corpus oracle line numbers didn't point at the seeded defects → a correct reviewer would have scored 0 catches) — fixed + guarded by a new oracle↔diff fidelity falsifier; the corpus freeze-hash is `sha256:fb5f22df…`. Goodhart provenance verified (defects authored independently of the council). Nothing in 3a may be read as a diversity/quality result.

## Slice: Council Measurement RUN — Slice 3b: the measurement RUN (council-measurement-run / 3b of 4)

- Feature-Slug: council-measurement-run (3a substrate consumed READ-ONLY; 3b RUNS it; Slice 4 = GUI)
- canvas/prd/vision: docs/{canvas,prd,vision}/council-measurement-run.* (user-confirmed, Ben 2026-06-20; spec-auditor remediated)
- reality-ledger: docs/reality/council-measurement-run.evidence.jsonl
- plan: docs/plans/2026-06-20-council-measurement-run.md

| Trace ID | Requirement | Evidence | wired-in-prod? | evidence-class | True-Line |
|---|---|---|---|---|---|
| TRC-MR-002 | REQ-MR-002 (ARM SYMMETRY: same structured flag protocol both arms, same parse_flag_set) | test_council_measurement_run.sh | n/a — offline | integration-fake | pass |
| TRC-MR-004 | REQ-MR-004 (foreign-only fail-closed; paired-exclusion; OK-empty scored; survivors floor→underpowered) | test | n/a | integration-fake | pass |
| TRC-MR-005 | REQ-MR-005 (Arm-A real boundary via run_inference direct, reachable-when-armed [code-reviewer proved by execution]; MAX-CALLS up-front ceiling; gate off by default) | test + code-review | live call DEFERRED to budget-gated pilot | integration-fake | pass |
| TRC-MR-006 | REQ-MR-006 (emit_run --raw round-trip; both metric families + n/scope) | test + emit_run | n/a | integration-fake | pass |
| TRC-MR-007 | REQ-MR-007 (frozen pre-registration; MDE/delta rubric: zero/below-MDE delta→underpowered; demonstrated/refuted unreachable at n=2) | metrics/pre-registration-…json + test (MDE falsifier) | n/a | integration-fake | pass |
| TRC-MR-009 | REQ-MR-009 (instrument + corpus byte-unchanged; orchestrator defines no transport, imports no http) | git diff --quiet + AST test | n/a | integration-fake | pass |
| TRC-MR-011 | REQ-MR-011 (security N1/N2/N3: @path confined, OSError surfaced, no fabricated flag, no key leak) | test + security-review | n/a | integration-fake | pass |

**Reality Ledger (MR-3b, honest ceiling):** the offline harness is `integration-fake`; the n=2 pilot **RAN LIVE** (2026-06-20, user-approved budget MAX-CALLS=10, Arm A `anthropic/claude-haiku-4.5` vs Arm B preset-A free) → `real-boundary-smoke` for the RUN MECHANISM only (4 real calls, both arms crossed the boundary, leak=0). **Outcome = `underpowered`** (survivors 0/2; both tasks paired-excluded on `COUNCIL_RATE_LIMITED`) — a run-mechanism smoke + cost/flakiness estimate, **NOT a value verdict** (`docs/benchmarks/2026-06-20-council-measurement-pilot.md`). Key finding: free-tier Arm-B is 100% rate-limited → the powered full run needs PAID Arm-B + corpus expansion + A/B/C. NO measurement number / value claim. The value verdict needs the powered full run (corpus expansion + A/B/C). Defense-in-depth caught + fixed, pre-merge: 4 measurement-integrity BLOCKERs at spec-sanity (arm asymmetry, REQ-MR-005/009 contradiction, unmeasurable aggregate cost, n=2 refutability), 2 HIGH at code-review (MDE rubric unimplemented; MAX-CALLS not enforced), and a getattr test-gaming smell (test relaxed + de-obfuscated). The live Arm-A path was proven reachable BY EXECUTION (not the Slice-2 dead-seam failure).

## Slice: Plumbline Update Reliability (plumbline-update-reliability)

- Feature-Slug: plumbline-update-reliability (iterative 4-sprint build; Sprint 1 [install identity] + Sprint 2 [token-aware resilient fetch] built, gated A-E green, committed; Sprint 3 [install-refresh] next)
- canvas-link: docs/canvas/plumbline-update-reliability.canvas.md (Status: user-confirmed 2026-06-21)
- prd-link: docs/prd/plumbline-update-reliability.prd.md (Status: user-confirmed 2026-06-21)
- vision-link: docs/vision/plumbline-update-reliability.vision.md (Status: user-confirmed 2026-06-21)
- reality-ledger: docs/reality/plumbline-update-reliability.evidence.jsonl (REQ-PUR-01/02 integration-fake [Sprint 1]; REQ-PUR-03 real-boundary-smoke [Sprint 2, live --check] + integration-fake auth mechanics; doctor follow-up tracked)
- plan: docs/plans/2026-06-21-plumbline-update-reliability.md

| Trace ID | Requirement (AC) | Evidence (test) | wired-in-prod? | evidence-class | True-Line |
|---|---|---|---|---|---|
| TRC-PUR-01 | REQ-PUR-01 install-identity anchor written at install (AC-PUR-01.1/.2) | test_update_layer.sh | yes — install.sh install_bin* writes $CLAUDE_HOME/.plumbline-install.json | integration-fake | aligned |
| TRC-PUR-02 | REQ-PUR-02 cwd-independent installed identity in BOTH modes, honestly sourced (anchor for copy installs; symlinked checkout's current VERSION/origin for symlink installs); foreign-repo + copy-install fallback + symlink-tracks-checkout-after-pull (AC-PUR-02.1..5); closes G1 (C1 refinement, user/Ben 2026-06-21) | test_update_layer.sh (installed plumbline from /tmp + /tmp/fakerepo, no --root; symlink-mode post-pull version) | yes — plumbline_update.py resolve_install_identity is cwd-independent per mode (copy: anchor; symlink: checkout VERSION+origin) via read_version/default_repo_slug | integration-fake | aligned |
| TRC-PUR-03 | REQ-PUR-03 token-aware fetch; unauth-fallback; 403-vs-404 distinct; token never printed (AC-PUR-03.1..4); closes G2 | test_update_layer.sh (offline via PLUMBLINE_GITHUB_API seam) | yes — fetch_latest_release sets Authorization header in prod path | integration-fake (+ gated real-boundary-smoke: live --check) | aligned |
| TRC-PUR-04 | REQ-PUR-04 update applies into $CLAUDE_HOME via REAL install.sh --update, not --dry-run; real ~/.claude never written (AC-PUR-04.1..4); closes G3 apply | test_update_layer.sh (sandbox $CLAUDE_HOME) | yes — update_apply (no --target) runs real installer into $CLAUDE_HOME | integration-fake (+ real-boundary-smoke: sandbox-HOME apply) | aligned |
| TRC-PUR-05 | REQ-PUR-05 install update-mode content-compares + overwrites changed targets in BOTH modes + adds new + rewrites anchor; no stale skip (AC-PUR-05.1..3); closes G3 refresh | test_update_layer.sh (stale agent+command+lib) | yes — install.sh --update / transfer() content-compares + overwrites changed target (both symlink and --copy) | integration-fake | aligned |
| TRC-PUR-06 | REQ-PUR-06 verify-or-revert: snapshot $CLAUDE_HOME, revert whole HOME on injected verify-fail; mechanism itself tested (AC-PUR-06.1..3) | test_update_layer.sh (injected verify-failure) | yes — update_apply snapshot/verify/revert wired into apply | integration-fake (+ real-boundary-smoke: sandbox-HOME revert) | aligned |
| TRC-PUR-07 | REQ-PUR-07 falsifiers for G1-G3 are behaviour/counter (red if fix reverted), wired into run_all.sh (AC-PUR-07.1..4); closes G4 | test_update_layer.sh + run_all.sh | yes — falsifiers run in CI via run_all.sh | integration-fake | aligned |
| TRC-PUR-08 | REQ-PUR-08 on-by-default / opt-out, non-blocking, throttled, notify-only session-start update-check (AC-PUR-08.1..4) | test_update_layer.sh (+ session-start.sh) | yes — config/claude/hooks/session-start.sh env opt-out check | integration-fake | aligned |

**Reality Ledger (PUR, honest ceiling):** offline mechanics = `integration-fake` (cwd-independent
identity, token-on-header + unauth-fallback + 403/404 classification via the injectable
`PLUMBLINE_GITHUB_API` seam, headline apply/refresh/revert into a sandbox `$CLAUDE_HOME`,
falsifiers). `real-boundary-smoke` (gated, NOT in CI) for the opt-in live `update --check` against
`DYAI2025/Plumbline` and the real sandbox-`$CLAUDE_HOME` apply vN->vN+1 + forced-verify-fail
revert. The SANDBOX-`$CLAUDE_HOME` rule is binding: no test/smoke runs the real installer against
the operator's real `~/.claude`. No "every user's real HOME upgraded" claim is made by tests.

**Open Questions:** OQ-PUR-01 (affects REQ-PUR-05) and OQ-PUR-02 (affects REQ-PUR-08) are both
RESOLVED (user, 2026-06-21): OQ-PUR-01 → content-compare + overwrite in BOTH modes; OQ-PUR-02 →
auto-check on-by-default / opt-out (notify-only; APPLY stays explicit, NFR-PUR-06 unchanged).
**Status:** Canvas/PRD/Vision all `user-confirmed` (Ben, 2026-06-21, exact phrase; OQs resolved);
True-Line `aligned`. Build in progress (autonomous, one final acceptance): Sprint 1 (REQ-PUR-01/02)
+ Sprint 2 (REQ-PUR-03) built, Gates A-E green, committed; Sprint 3 (REQ-PUR-04/05/06 install-refresh)
+ Sprint 4 (REQ-PUR-07/08) pending. TRC-PUR-04..08 evidence rows are the planned contract (their
tests land in their sprints).
