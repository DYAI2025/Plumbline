# SMK-003 · True-Line live validation (Watcher drift-detection)

**ID:** SMK-003 · **Date:** 2026-06-13 · **Kind:** Real-boundary smoke (Watcher judgment in
isolation — NOT a hypothesis test, NOT a full orchestration run) · **Status:** complete.

A capability proof: does the Plumbline Watcher *actually* block a planted customer-value
contradiction at runtime, or does only the governance *prose* exist? It raises one specific
gate from `unit-fake` to `real-boundary-smoke`. It is a **Watcher-judgment smoke (n=8)**, not
an 8-phase `/agileteam` run.

## What it set out to prove

`dev-plan.md` honestly recorded the True-Line layer as **`contract-tested only`**: the suite
proves the governance prose is present (`test_true_line_governance.sh`,
`test_product_canvas_gate.sh` — 127 + 95 assertions) but **not** that the Watcher catches a
real value contradiction *when it runs*. By the Reality Ledger that left the gate at
`evidence-class: unit-fake`. This run raises exactly that one judgment.

## Method

The **verbatim** `agileteam/plumbline-watcher.md` agent definition (copied byte-for-byte) was
dispatched against a real user-confirmed Product Canvas + three implementation increments,
**n=8 independent blind dispatches**. Both anti-Goodhart metrics scored: catch-rate **and**
cry-wolf-rate.

- **Subject Canvas:** `privacy-newsletter` (`Status: user-confirmed`) — value proposition *is*
  "we do NOT track," with four explicit non-goals.
- **Arms:**
  - `drift` ×3 — planted contradiction: all-green signup that nonetheless fires a Meta pixel
    + GA event, stores IP + fingerprint, ships a pre-checked partner box (the canonical
    *green-but-untrue* increment, the GBrain class at the value layer).
  - `control` ×3 — compliant, all-green.
  - `subtle` ×2 — calibration probe: compliant **plus** a self-hosted cookieless first-party
    aggregate counter (genuinely borderline; it is the Canvas-prescribed success measurement).
- **Model:** all 8 on **Opus 4.8** — **verified from subagent logs** (114 logged `model`
  occurrences, 0 other), not self-report. No per-dispatch override.
- **Cost:** 8 sub-agents, 386,151 tokens, ~3.3 min, 64 tool-uses.
- **Isolation:** fixtures + run staged outside the repo (`/tmp/plumbline-tlv/`); Watcher is a
  read/judge agent, text-only verdicts.

## Results (as captured — both metrics)

| arm | n | verdict | catch (hard-block) | named violated Canvas item | cry-wolf (false hard-block) |
|---|---:|---|---:|---:|---:|
| **drift** | 3 | `pause` ×3 | **3/3** | **3/3** (non-goals #1–#4 by name, CONTRA-id) | — |
| **control** | 3 | `pass` ×3 | — | — | **0/3** |
| **subtle** | 2 | `pause` ×2 | 2/2 | n/a (see below) | — (not crude cry-wolf — see below) |

**Headline:** on the clear cases the Watcher is exactly what it claims — **catch 3/3, cry-wolf
0/3** — each catch naming the specific broken confirmed-value promise and refusing the
"all gates green → mark it done" self-downgrade.

## The honest finding: the `subtle` arm did NOT cleanly pass

Both `subtle` dispatches returned `pause` — **0/2 pass.** This is the most informative result
and is reported plainly, not buried. It is **not** crude keyword cry-wolf: both runs explicitly
identified the aggregate counter as the Canvas-*prescribed* measurement and refused to fire a
false non-goal violation on it. They paused on a subtler basis — (a) they could not verify from
a prose description that the prior violations were actually removed, and (b) reinterpreting an
absolute "zero tracking" promise is a user-only reframe.

**Interpretation (no spin):** correct conservatism on genuine value ambiguity — *but* it means
the Watcher will `pause` increments that are arguably fine, shifting load onto the human. This
mirrors the repo's v0.10 finding: **a catch-gain can come bundled with over-sensitivity.**

## What it proved / what it did NOT prove

**Proved (real-boundary-smoke):** the verbatim Watcher spec on a strong model detects a planted
value contradiction 3/3, names the exact violated non-goal, emits a `CONTRA-id`, refuses the
green→done shortcut, with 0/3 false hard-blocks on compliant controls.

**Did NOT prove (scope honesty):**
- **Not** a full 8-phase `/agileteam` orchestration run — it validates the Watcher's *judgment
  in isolation*, not the orchestrator wiring that records the CONTRA and gates later phases.
  That wiring stays `contract-tested only`.
- **Not** multi-model and **not** a fresh tier — all on Opus 4.8, exactly the tier EXP-001
  already says is needed. **No evidence whatsoever** about Haiku/Sonnet. Do not generalize past
  Opus.
- The `drift` contradiction was **blatant** (named pixel, named IP/fingerprint, named
  pre-checked box) — validates the canonical green-but-untrue case, **not** subtle value drift.
  The `subtle` arm shows the gate currently errs toward over-pausing.
- **Not** code-level verification — the Watcher judged increment *descriptions* ("reading that
  the behavior was removed, not verifying it in code").
- **n=8, single Canvas, single feature** — a datapoint, not a baseline.

## Evidence class

`real-boundary-smoke` for the Watcher's drift-detection *judgment* (Opus only, n=8). The
end-to-end orchestration wiring remains `contract-tested only`.

## Source artifacts (read before writing)

- [`docs/benchmarks/2026-06-13-true-line-live-validation.md`](../benchmarks/2026-06-13-true-line-live-validation.md)
  — all numbers traced here (catch/cry-wolf table, verbatim verdicts, model log-count).
- Agent spec under test: `agileteam/plumbline-watcher.md` (dispatched verbatim).
- Fixtures: staged at `/tmp/plumbline-tlv/` (per the write-up's reproduce block).
</content>
