# Concilium Report — Plumbline (self-evaluation)

Date: 2026-05-30 · Subject: the Plumbline agent framework itself · First-ever /concilium run.

## Framed subject
- **(a) Idea:** Plumbline = defense-in-depth Claude-Code agent framework (85 subagents,
  16 skills, /agileteam TDD pipeline, /concilium council, /honest-status, /bench-oracle).
  Distinguisher: empirical honesty — it mutation-oracle-benchmarked its OWN agents and
  published that its cleverest QA-prompt idea did NOT improve build-level outcomes
  (model capability dominated; only Opus caught the planted defect, Sonnet & Haiku 3/3).
- **(b) Underlying user goal (a pivot must preserve):** (1) genuinely reduce the
  "tests green ≠ it works" failure class in the author's own multi-project work; (2) earn
  public recognition (stated proxy: a "GitHub Awesome" YouTube mention).
- **(c) Team/constellation:** 85 agents, but ~74 are vendored-unbenchmarked from
  claude-flow; the original layer is thin (/agileteam 6 role files + 3 concilium + QA DNA
  + the benchmark corpora).

## ⚠ Diversity disclosure (read this before trusting the verdict)
**All three bodies ran on Claude (model: inherit).** The foreign-model diversity the
council is designed to use was **not achieved**: the `gemini` CLI probe hung on
interactive MCP auth prompts and timed out; codex/qwen are installed but not wired as MCP
tools. Per the council's own rule, correlated blind spots are **NOT covered** — treat the
Round-1 unanimity as a *single* correlated opinion, not three independent ones. This
disclosure is itself load-bearing in the verdict below.

## Round 1 — independent positions
| Body | POSITION | One-line |
|---|---|---|
| Market Realist | `pull-pivot` | Subagent-collection category is saturated (claude-flow ~31k★, VoltAgent 154+, wshobson 191); the honest benchmark is the only scarce wedge → ship that, cut the agent zoo. |
| Tech Arbiter | `pull-pivot` | The marquee "catches green≠works" claim is, by its own data, model-tier-bound, not framework-delivered; /concilium's diversity premise is a no-op right now; ship the instrument + finding. |
| Skeptic | `pull-pivot` (propose-alternative, bar met) | Product and footnote are swapped; make the Reality-Ledger harness the product, agents become one tested workload. |

**Round-1 trajectory = total resonance** (3×`pull-pivot`, same thesis). Given the
diversity disclosure, that very unanimity was the signal to attack, not to trust.

## Round 2 — collision (Skeptic ordered to attack the consensus; run twice)
Both runs **broke their own Round-1 pivot**:
- The pivot "make the benchmark THE product" conflated *scarcity of an artifact* with
  *adoptability of a product* — two different axes. (ableitbar)
- **Adoption asymmetry:** a working `/agileteam` is *runnable* (clone → it does a job); a
  benchmark harness is *read/cited* by a sub-niche and only gains value as a coordination
  point won by distribution/incumbency, not correctness. (ableitbar)
- **The benchmark's value is parasitic on the team:** "I built a harness and found agent
  evals lie" detached from a product is a blog post, not a product. The consensus wanted
  to "amputate the body and keep the scar." (ableitbar)
- **Goal check the council skipped:** for goal (1) the author needs the *instrument
  running privately* (wired into /agileteam-bench) — he need not ship a product at all;
  for goal (2), the claim that a niche harness out-traction a polished framework is
  **ungeprüft** and was downgraded, not asserted.
- **Aesthetic-capture diagnosis:** three instances of one model independently reaching the
  same counterintuitive-but-noble conclusion is the textbook signature of shared inductive
  bias. Evidentiary weight ≈ 1 opinion.

Both runs settled on **`pull-go` / SHARPEN**, not pivot. One run explicitly judged the
Round-1 friction "substantially theater."

## Trajectory summary
- **Resonance (survived collision):** the 74 vendored, unbenchmarked agents ARE commodity
  ballast; the mutation-oracle + honest negative result IS the scarce, differentiating
  asset. (All three bodies, both rounds.)
- **Repulsion (the real axis):** does "scarce asset" imply "the asset should BE the
  product"? Round 1 said yes (3×); Round 2 said **no** — scarcity makes it the *spearhead/
  trust weapon*, not the *spear*.
- **Instability resolved:** the Round-1 pivot depended on an **unverified** adoption
  theory; once evidence-classed, it collapsed to SHARPEN.
- **Unanswered (open questions, see below):** real adoption data; the author's true
  intent re shipping vs. private instrument; benchmark statistical power (n=3/cell).

---

## RECOMMENDATION: **SHARPEN** (not pivot, not kill)

Keep `/agileteam` + a **curated** agent subset as the product. **Demote** the "85 agents"
headline; lead with provenance honesty. **Weaponize** the mutation-oracle + honest
negative result as (a) the trust/credibility differentiator and (b) the author's private
QA instrument wired into `/agileteam-bench` — **not** as a standalone product. This
preserves both goals better than either the status quo ("85 agents", commodity) or the
Round-1 pivot ("a benchmark", unadoptable).

### Concrete, converged changes
1. **Reframe the headline.** Stop leading with "85 subagents". Lead with: "a working
   multi-agent TDD pipeline whose 'green' is proven to mean 'works' — and the honest
   benchmark that proves where it doesn't." State the 11-original vs ~74-vendored split
   openly (the honesty brand demands it; the gap is already visible to any skeptic).
2. **Benchmark = CI badge / credibility gate, not product.** Fold bench-oracle into
   /agileteam-bench as the internal honesty gate; cite the negative result as proof of
   method, not as the thing users adopt.
3. **Curate the collection.** Mark the vendored agents as a *tested workload / dependency*,
   not constellation breadth.

### Conditions / falsifiers under which this verdict flips
- → **PIVOT** (to benchmark-as-product) **iff**: evidence that solo-authored agent
  benchmarks reliably out-adopt solo-authored agent frameworks (test: name ≥3 solo
  benchmarks >500★ in 18 months without a lab behind them), OR the author states he wants
  no product at all (then: keep the instrument private, discard productization entirely).
- → **GO as-is** **iff**: the original layer (/agileteam + QA DNA) is shown to reduce
  "green≠works" on the author's real repos at adequate power (n ≥ ~20, not 3) AND the
  README leads with provenance — then the collection framing is harmless packaging.

## TEAM-CONSTELLATION VERDICT
- **MISSING — Distribution / Go-to-Market body.** Both Skeptic runs independently
  identified this as the *root cause of the council's own error*: a council blind to
  distribution over-values an artifact's intrinsic merit and under-values adoption
  machinery — which is exactly how it picked the elegant benchmark over the adoptable
  team in Round 1. **Draft written** to `concilium/proposed/distribution-realist.md`
  (NOT activated — user reviews).
- **MISSING — inward honesty/provenance owner** (konfabulations-audit applied to
  Plumbline's own claims; the 85-vs-11 gap proves the need). Lower priority — partially
  covered by the existing /honest-status command.
- **MISCAST — the 74 vendored agents as "team members."** They are dependencies; recast
  as a tested workload.

## Evidence-class ledger (load-bearing claims)
| Claim | Class |
|---|---|
| Subagent-collection category is saturated (claude-flow ~31k★, VoltAgent 154+, wshobson 191) | belegt (Market/Skeptic WebSearch) |
| "tests-pass-but-broken" is an observed, public pain (claude-code issue #37818; METR; ImpossibleBench; SWE-bench Illusion) | belegt (WebSearch) |
| Plumbline's own benchmark: DNA outcome-neutral at build level, model-tier-bound | belegt (repo: SUMMARY-2026-05-30, pipe-opus-ceiling) |
| model: frontmatter inert in this runtime; only dispatch param works | belegt (repo measurement) |
| /concilium foreign-model diversity not wired (this run = single-model) | belegt (this run: gemini probe failed, no MCP) |
| ~74 of 85 agents vendored & unbenchmarked | ableitbar (brief + repo structure) |
| Benchmark harness adopts worse than a runnable framework | ungeprüft (downgraded; NOT asserted) |
| "GitHub Awesome" rewards count vs. novelty | ungeprüft (channel criteria unknown) |

## Open questions for the user (not closed by the council)
1. Do you actually want to **ship a product**, or is goal (1) satisfied by keeping the
   benchmark a **private** instrument? This single answer changes the whole verdict.
2. What is Plumbline's current external traction (stars/forks/users besides you)? None was
   available to the council.
3. By what mechanism does "GitHub Awesome" select repos — trending-by-stars, or editorial
   novelty? The visibility goal's strategy depends on it.
4. Should the council gain a Distribution body (draft proposed) before the next decision?

## Method note (honest)
This run's strongest finding is procedural: a single-model council produced a confident,
elegant, **wrong-in-its-leap** unanimous verdict in Round 1, and only the adversarial
collision round corrected it. That is direct evidence for *why the council needs real
model diversity* — and a live demonstration of Plumbline's own thesis (a confident green
result that did not, on inspection, hang true). The friction was not theater; it was the
instrument working.
