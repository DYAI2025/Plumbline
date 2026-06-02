# M7 Architecture Spec — Risk-Router + Digest-Broker (two-metric-gated)

> **Status: SPEC (design only — NOT implemented).**
> **Empirical basis (declared sufficient):** the v0.10 `n=6` full-pipeline slice + the anti-Goodhart FP-control run — see [`docs/benchmarks/2026-06-02-full-pipeline.md`](../benchmarks/2026-06-02-full-pipeline.md). The full ~76M-token 12-task baseline is **deferred**; M7 is designed against the n=6 evidence with that as an explicit limitation.
> **Creed constraints:** defense-in-depth, independence, human gates, no-laundering, fail-closed — all preserved; M7 *aims* the existing defense, it does not thin it.

---

## 0. The non-negotiable, stated first: **two-metric gating**

The FP-control run proved that **catch-rate and cry-wolf-rate move in opposite directions** (the DNA was net-positive on Opus — same catch, 67%→17% false-positive — but a *trade-off* on sub-Opus — escape 0.67→0.33 yet false-positive 0.00→0.33). Therefore, from day 1:

> **Every M7 lever is promoted to "stable" only if, on the bench, it (a) does NOT worsen `escaped_defect_rate` AND (b) does NOT worsen `false_positive_rate`, each within the corpus MDE, on BOTH Opus and a sub-Opus model.** A lever that buys cost-reduction (or catch) at the price of cry-wolf is **rejected**, not shipped behind a caveat.

This gate is the spine of the whole design. Catch-only promotion is forbidden (and is now a written guideline in `CLAUDE.md`).

---

## 1. Why M7 exists (the cost it attacks)

Two measured/estimated hotspots in the current orchestration:
- **The G5 per-increment chain is uniform** — every increment, boundary-touching or pure-logic, pays the identical heavy `code-reviewer → tester → Watcher` chain (~50–60% of a run, estimated). Defense-in-depth means *uncorrelated checks where a defect could hide*, not *identical checks where none can*.
- **Cross-gate re-reads** — every independent gate re-opens the four raw artifacts (canvas + vision + PRD + traceability) per check (estimated ~72k tok/run of redundant reads).

M7 attacks both **without** thinning defense on the increments that can actually carry a defect — and proves it held the line via the two-metric gate.

---

## 2. Component 1 — Risk-Router (evidence-class-driven defense routing)

**Goal:** spend the expensive, uncorrelated chain on the increments that *can* be RED; give RED-incapable increments a lighter path — measured, not assumed.

### 2.1 Classification (deterministic, NOT new agent judgment)
At plan time, `planner` stamps each atomic task/increment with a `risk_class ∈ {boundary, logic, doc}` in the traceability matrix, **derived from existing columns**:
- `boundary` — the task's Reality-Ledger `evidence-class` ceiling reaches above `unit-fake` (it touches I/O / remote / external-API / UI / persistence), **OR** its changed files fall in a canvas `Allowed-change-scope` path typed as a boundary surface.
- `logic` — pure deterministic logic, no boundary.
- `doc` — docs/config only.
Derivation is a predicate over the `evidence-class` + `wired-in-prod?` + scope columns — it cannot contradict them, and `context-keeper` owns/records it.

### 2.2 The hardened predicate (binding — from the `T05` + FP lessons)
- **Any review-only, docstring-touching, or contract-touching diff routes to the FULL path regardless of I/O surface.** (`T05` is a docstring-lie on a pure-logic review diff — a defect with no boundary; "can-be-RED" ≠ "touches-a-boundary".)
- **Ambiguous → `boundary`.** Uncertainty resolves UP to the heavy path (fail-closed, mirrors "uncertainty resolves toward the user").
- The classifier is itself a model judgment that escapes below Opus → on a sub-Opus session the router **discloses** that the light path has no real-boundary net (Opus-or-disclose), and may force the full path.

### 2.3 Routing
- **boundary** → the FULL per-increment chain unchanged (`code-reviewer → tester → plumbline-watcher`), the five Opus-recommended checking gates, full `plumbline-reality-check` at integration minimum.
- **logic / doc** → a LIGHT path: **`code-reviewer` + `tester` still run** (this is what catches `T05` and what the FP run showed keeps cry-wolf down); only the **per-increment Watcher value-not-green check batches to the task boundary** (once per task, not per increment). The Watcher question survives verbatim.
- **FP-finding mandate:** the light path must keep the DNA-disciplined validator/reviewer — *not* a frozen one. The FP run measured the frozen validator crying wolf 67% on Opus pure-logic; the light path must not reintroduce that. The two-metric gate (§0) is what proves it didn't.

### 2.4 The router reads RAW, not the digest (separate provenance)
The router's `risk_class` decision reads the **raw traceability `evidence-class` + `wired-in-prod?` columns**, NOT the Digest-Broker's digest. This is the **correlated-failure mitigation**: if the router and the gates both trusted one digest, a single wrong-but-internally-consistent digest field would *simultaneously* mis-route an increment AND pass its gate. Router-input and gate-input stay on separate provenance.

---

## 3. Component 2 — Digest-Broker (context-keeper as canonical-state broker)

**Goal:** stop every isolated gate from re-opening four raw docs per check.

- `context-keeper` (already the sole curator) additionally emits `docs/context/value-digest.md`: a ≤1-page, **sha256-hash-bound** snapshot of only the value baseline a gate needs — the six canvas trace fields, `vision-link`, `value-check-id`, `true-line-status`, per-REQ `evidence-class` + `wired-in-prod?`, open `CONTRA-*` ids, and verbatim `MISSING/OPEN/BLOCKER` markers.
- **Gates** (`plumbline-watcher`, `product-owner`, `production-validator`, `spec-auditor`, `tester`) read the **digest** as their value baseline; they re-open a full raw doc ONLY when the digest flags a value-risk/contradiction needing detail, or when the hash is stale.
- **Hash-bound staleness = fail-closed:** the digest is prefixed with a sha256 over `(canvas+vision+prd+traceability)`. A gate recomputes the hash; **mismatch → forced full re-read** (never a stale pass). A mutation that silently alters the vision/canvas mid-run must still flip the dependent gate RED via this mismatch — a required bench correctness check.
- **Independence preserved:** the digest is curator-authored from confirmed artifacts and carries **zero coder reasoning** — it is Diff+Spec-class facts, the exact thing reviewers may see. It compacts the *encoding*, never the *value baseline*.

---

## 4. Invariants preserved (must be true of any implementation)
- **Defense-in-depth:** every `boundary` increment still crosses every uncorrelated gate; the router removes *redundant re-firing on RED-incapable paths*, never a gate from a path that can be RED.
- **Independence:** routing changes *which* gates fire and *from what* they read; it never lets an author review own code or a reviewer see coder reasoning.
- **Human gates are router-invariant:** Canvas/Vision/GO/acceptance fire by the same fixed rules regardless of `risk_class`.
- **No-laundering:** a `*-fake`/not-wired/value-risk finding can never be "light-pathed" away; it surfaces verbatim. Only the user reclassifies.
- **Fail-closed:** ambiguous class → boundary; stale digest hash → full re-read; missing classifier input → full path.

---

## 5. Promotion protocol (the day-1 two-metric gate, operationalized)
1. Implement a lever (router and/or digest) on a branch; pin the agent snapshot.
2. Run the bench harness in both modes against the lever vs. the frozen baseline:
   - **gaps** (full-pipeline, e.g. `T02/T08/T05` + the corpus boundary tasks) → `escaped_defect_rate`.
   - **controls** (pure-logic, e.g. `T06/T12` + the corpus controls) → `false_positive_rate`.
   - both on **Opus AND a sub-Opus model**, n≥3/cell.
3. **Promote iff** `Δescaped_defect_rate ≤ 0` (within MDE) **AND** `Δfalse_positive_rate ≤ 0` (within MDE), on **both** models. Report as "neutral within MDE X at n=Y", never a bare "neutral".
4. Else **reject** (document why). A cost win that holds both metrics is the only acceptable win.
5. Persist the run (`cost_per_validated_req`, both metrics, both models) to `runs.jsonl` + a `metrics/bench-<date>-m7-*.md` record. (Reuse the now-isolated, text-only bench harness per the `CLAUDE.md` benchmark-isolation rule.)

---

## 6. Risks + mitigations
- **Digest + router correlated failure** → §2.4 separate provenance (router reads raw columns).
- **Classifier is a new failure surface** (mis-route under-defends an increment) → ambiguous→boundary, Opus-or-disclose, and pre-trust validation against the corpus's known `gap_class` labels (a misclassification is caught by the corpus before any real build).
- **Sub-Opus trade-off** (the FP finding) → the light path keeps `code-reviewer`+`tester`; the two-metric gate blocks any lever that lifts cost/catch while raising cry-wolf on either model.
- **n=6 evidence basis** → M7 is designed, not declared proven; the full 76M baseline remains the way to tighten the promotion MDE later.

---

## 7. Out of scope (this spec)
- Building the components (spec only).
- The full 12-task ~76M-token baseline (deferred; M7 promotion uses focused gap+control runs with MDE-honest reporting).
- Any model up/down-grade not via the orchestrator's explicit per-dispatch parameter.

## Appendix — mapping to prior analysis
Risk-Router ← cost-altitude P1 + team-topology P1/P2 (hardened per the `T05` correctness gate and the FP-control finding). Digest-Broker ← cost-altitude P2 + team-topology P4 (with the separate-provenance mitigation). Two-metric gate ← the FP-control run + the corpus's `anti_goodhart` law. Measurement spine ← M3 cost emission + the isolated bench harness.
