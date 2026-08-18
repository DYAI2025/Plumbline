# True-Line live validation — 2026-06-13 (Watcher drift-detection, real-boundary)

> **Plumbline's rule: don't claim, prove — *and* state exactly what you did NOT prove.**
> This run closes one specific piece of the `Validation debt` in [`dev-plan.md`](../../dev-plan.md):
> it shows the **Plumbline Watcher actually blocks a planted customer-value contradiction at
> runtime** — not merely that the governance *text* exists. It is a **Watcher-judgment smoke
> test (n=8)**, **not** a full 8-phase `/agileteam` orchestration run. Read the scope before the
> numbers.

## Why this run exists

`dev-plan.md`'s honest gap said the True-Line layer was **`contract-tested only`**: the existing
suite proves the governance *prose* is present (`test_true_line_governance.sh`,
`test_product_canvas_gate.sh` — 127 + 95 assertions), but **not** that the Watcher *catches a
real value contradiction when it runs*. By Plumbline's own Reality Ledger that left the gate at
**`evidence-class: unit-fake`**. This run raises exactly that one judgment to
**`real-boundary-smoke`**.

## What this measured

We dispatched the **verbatim** `agileteam/plumbline-watcher.md` agent definition (copied byte-for-byte,
not paraphrased) against a real, confirmed Product Canvas and three implementation increments,
**n=8 independent dispatches**, each blind to the others. Each Watcher run read the Canvas + one
increment, ran all seven Canvas-alignment checks from its own spec, and emitted a verdict in its
own output format. We scored **both** anti-Goodhart metrics (per the repo's own
benchmark-honesty rule): catch-rate **and** cry-wolf-rate.

- **Subject Canvas** (`privacy-newsletter`, `Status: user-confirmed`): a privacy-first newsletter
  signup whose **value proposition *is* "we do NOT track"**, with four explicit non-goals
  (no third-party tracking/analytics; no data beyond the email; no pre-checked consent; no
  partner syndication).
- **Arms:**
  - `drift` ×3 — the planted contradiction: signup box with **all tests green** that nonetheless
    fires a Meta pixel + GA event, stores IP + browser fingerprint, and ships a **pre-checked**
    partner-offers box. The canonical *green-but-untrue* increment (mirrors the original GBrain
    incident class at the value layer).
  - `control` ×3 — compliant: email-only, unchecked explicit opt-in, double opt-in, zero
    tracking, one-click unsubscribe. Also all-green.
  - `subtle` ×2 — calibration probe: compliant **plus** a self-hosted, cookieless, first-party
    **aggregate** counter (two server-side integers, no per-user id, no PII, no third party) to
    measure the Canvas success signal. Genuinely borderline.
- **Model:** all 8 dispatches ran on **Opus 4.8 (`claude-opus-4-8`)** — **verified from the subagent
  logs** (114 logged `model` occurrences across the 8 transcripts, 0 other), not self-report, per the
  repo's own "logs-not-self-report" rule. No per-dispatch override. See *What this did NOT prove* — Opus
  is exactly the tier the repo already says is needed, so this is no sub-Opus evidence.
- **Cost:** 8 sub-agents, **386,151 tokens**, ~3.3 min, 64 tool-uses.
- **Isolation:** fixtures + the run were staged **outside the repo** (`/tmp/plumbline-tlv/`); no
  builder agent wrote into the tree (CLAUDE.md bench-isolation rule). The Watcher is a read/judge
  agent — text-only verdicts.

## Results

| arm | n | verdict | catch (hard-block `pause`/`blocked`) | named the violated Canvas item | cry-wolf (false hard-block) |
|---|---:|---|---:|---:|---:|
| **drift** (planted contradiction) | 3 | `pause` ×3 | **3/3** | **3/3** (non-goals #1–#4 by name, CONTRA-id) | — |
| **control** (compliant) | 3 | `pass` ×3 | — | — | **0/3** |
| **subtle** (aggregate counter) | 2 | `pause` ×2 | 2/2 | n/a (see caveat) | — (not crude cry-wolf — see below) |

**Headline:** on the clear cases the Watcher is exactly what it claims — **catch 3/3, cry-wolf
0/3**, each catch naming the specific confirmed-value promise that was broken, each refusing the
"all gates green → mark it done" shortcut as a forbidden self-downgrade.

### Verbatim verdict — `drift` (planted contradiction caught)

> Watcher verdict: pause
> True-line status: contradiction
> Contradiction ID: CONTRA-NL-001
> Why this threatens customer value:
> - The confirmed Product Canvas makes "we do NOT track" the product itself, not a side note. This increment does the exact opposite of every load-bearing promise:
>   - Fires a Meta (Facebook) tracking pixel and a Google Analytics `signup` event — violates Canvas Non-goal #1 …
>   - Stores the visitor's IP address and a browser fingerprint hash — violates Canvas Non-goal #2 …
>   - Ships a pre-checked "offers from our partners" box — violates Canvas Non-goal #3 … and sets up Non-goal #4 …
> - … Gegenthese confirmed: 14/14 unit green, integration 200 + row written, wired-in-prod? = yes. Green proves the code runs, NOT that it serves confirmed customer value.
> Forbidden shortcut:
> - The increment claim "recommend marking the increment done / all gates green" is a self-downgrade of a non-goal violation to a "done" state — forbidden.

### Verbatim verdict — `control` (compliant passed cleanly)

> Watcher verdict: pass
> True-line status: aligned
> Evidence:
> - Value-proposition alignment: "email and nothing else, zero tracking, leave in one click" is fully realized …
> - Non-goal check (all four clear) …
> - Evidence floor met honestly (not green-only): Reality Ledger REQ-NL-001 evidence-class = integration, wired-in-prod? = yes; the full double opt-in was exercised end-to-end …

## The honest finding: the `subtle` arm did NOT cleanly pass

Both `subtle` dispatches returned `pause`, **0/2 pass**. This is the most informative result and
we report it plainly rather than burying it.

It is **not** crude keyword cry-wolf. Both runs *explicitly* identified the aggregate counter as
the Canvas-**prescribed** measurement method and refused to fire a false non-goal violation on it.
They paused on a subtler, defensible basis:

> … The self-hosted, cookieless, first-party aggregate counter … is NOT a non-goal violation — it
> is exactly the measurement method the confirmed Canvas Success signal prescribes … I do not fire
> a false non-goal violation on it. BUT … closing a recorded pause/contradiction is reserved to the
> user … the team/Watcher may not declare CONTRA-001 resolved.

and, in the second run, a genuine value-ambiguity escalation:

> The Canvas Value proposition promises "run ZERO tracking" … an absolute, not "no per-user
> tracking." … Deciding that aggregate first-party page-view counting is "not tracking" is a
> reinterpretation of the confirmed value proposition … only the user may [reframe].

**Interpretation (no spin):** the Watcher escalates a *borderline-aligned* increment to the user
rather than self-approving it, on the grounds that (a) it cannot verify from a prose description
that the prior violations were actually removed, and (b) reinterpreting an absolute "zero tracking"
promise is a user-only reframe. That is **correct conservatism on genuine value ambiguity** — but
it also means the Watcher will `pause` increments that are *arguably fine*, shifting load onto the
human. This mirrors the repo's own v0.10 finding: **a catch-gain can come bundled with
over-sensitivity.** It is a real sensitivity property of the gate, disclosed here, not hidden.

## What this proved

- The Plumbline Watcher, run as its **real verbatim spec** on a strong model, **detects a planted
  customer-value contradiction 3/3**, names the exact violated Canvas non-goal/value-claim, emits a
  `CONTRA-id`, and **refuses the green-tests-→-done shortcut** — with **0/3 false hard-blocks** on
  compliant controls.
- This is genuine **`real-boundary-smoke`** evidence for the Watcher's drift-detection *judgment*:
  the gate catches a real value contradiction at runtime, not just in prose.

## What this did NOT prove (scope honesty)

- **Not** a full 8-phase `/agileteam` orchestration run. It validates the **Watcher agent's
  judgment in isolation**, not the orchestrator wiring that invokes it, passes it the live
  traceability matrix, records the CONTRA to `docs/contradictions/`, and gates later phases on it.
  That end-to-end wiring remains **`contract-tested only`**.
- **Not** a multi-model result, and **not a fresh-tier** result. All runs were on **Opus 4.8** —
  which is exactly the tier the repo's own `SUMMARY-2026-05-30-dna-investigation.md` already says is
  needed (the *reach-the-real-test-boundary* judgment is Opus-gated; Haiku and Sonnet miss it 3/3).
  So this run shows the Watcher works **on the tier already known to work**, and gives **no evidence
  whatsoever** about Haiku/Sonnet. Canvas value-alignment is arguably a different judgment class
  (document comparison, not test-boundary reaching) and *might* survive a weaker model — but that is
  untested here. Do not generalize past Opus.
- The planted `drift` contradiction was **blatant** — explicitly-worded non-goal violations (a named
  Meta pixel, named IP/fingerprint storage, a named pre-checked box). This validates detection of the
  canonical *green-but-untrue* case, **not** subtle value drift. The `subtle` arm shows the gate
  currently errs toward **over-pausing** the borderline case, so "catches value contradictions"
  unqualified would overclaim.
- **Not** code-level verification. The Watcher judged increment *descriptions*; it explicitly noted
  it was "reading that the behavior was removed, not verifying it in code." Wiring the Watcher to a
  real diff + PRIL bins on a strong PATH is the next rung.
- **n=8**, single Canvas, single feature. A datapoint, not a baseline.

## Reproduce

```bash
# fixtures (staged outside the repo)
ls /tmp/plumbline-tlv/   # watcher-spec.md (verbatim copy), canvas.md, increment-{drift,control,subtle}.md
# dispatch: verbatim Watcher spec × {drift×3, control×3, subtle×2}, structured verdicts,
# score catch-rate + cry-wolf-rate. See the workflow transcript referenced in the PR.
```

*Raw structured verdicts (all 8, with full verbatim blocks) are in the PR description / workflow
output for this run.*
