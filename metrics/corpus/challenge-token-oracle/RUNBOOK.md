# RUNBOOK — Challenge-Gate Token Oracle (Part 2, GATED measurement)

This runbook is the faithful, honest procedure that turns **Finding #2** — *"the
challenge gate's `≤ ~15k tokens total` bound is aspirational prose, not an enforced
fact"* (`config/claude/commands/concilium.md` §"Challenge mode") — into a **measured**
result, using the deterministic scorer `config/claude/metrics/challenge_token_oracle.py`
(Part 1) against the seeded, leak-checked fixture in this directory.

> **GATED. Costs real model tokens. Model-dependent. Result → `agileteam-improved`,
> never `main` or the feature branch.** Run ONLY on explicit human go. Part 1 (the
> instrument + this fixture) is what merges to `main`; this run is Part 2.

---

## What this measures (and what it does not)

The scorer computes two v1 verdicts from captured run-data:

- **O1 — total tokens ≤ bound (15000).** The decisive answer to Finding #2: do the three
  challenge roles' reported tokens actually sum at or under the prose bound? Reported
  *with* the measured total beside it, never as a bare "passes".
- **O3 — the three role outputs are DISTINCT** (max pairwise Jaccard ≤ 0.6). Guards
  against consensus-theater: a gate whose three roles parrot each other produces no
  friction even if it is cheap. **Read this verdict through the shared-base lens below —
  the faithful mapping reuses one body across two roles, so a high Challenger↔Critic
  similarity is structurally EXPECTED, not a defect.**

**O2 ("≤1-page summary") is intentionally NOT scored** in v1. The one-pager is the
gate's *distilled* output (produced by the orchestrator after the role rounds), not the
sum of the three raw role contributions. Scoring it faithfully needs the distillation
step captured; doing it from the raw role texts would be a wrong-thing proxy. Deferred
to keep the pilot lean and the measurement valid.

**Reach honesty.** A few runs on one model can *refute* "the bound always holds" (a
single over-bound run does that) but cannot *establish* it generally. Report `n`, the
model, and the distribution — never generalize from a small sample.

---

## Reading O3 under the shared-base confound (MANDATORY when scoring)

The faithful `concilium.md` mapping reuses **one body** — `concilium-skeptic` — for BOTH
**Challenger** (requirement lens) and **Critic** (concept lens). Two roles driven by the
same body share vocabulary, framing, and stock phrasing, so their **lexical (Jaccard)
similarity is structurally elevated even on a perfectly healthy run**. This is a known
confound of measuring distinctness on a gate that intentionally DRYs two roles onto one
body — not evidence of consensus-theater.

How to read the verdict (use the scorer's `pairwise_similarity` object — the three pairs
`challenger_advisor`, `challenger_critic`, `advisor_critic`):

- **`challenger_critic` (shared `concilium-skeptic` base) — elevated is EXPECTED.** A high
  value here is the structural baseline of the faithful gate. Do **not** read it as a
  defect, and do **not** read it as consensus-theater.
- **Genuine consensus-theater shows on a CROSS-body pair** — `challenger_advisor` or
  `advisor_critic` (skeptic vs. tech-arbiter, different bodies). If a *cross-body* pair is
  high, the roles are converging despite different bodies — that is the real theater signal
  worth flagging.
- **Interpreting `O3_roles_distinct == false` (max pairwise > cap):** do **not**
  auto-treat it as a gate failure. First inspect `pairwise_similarity`:
  - If the over-cap pair is **`challenger_critic`** → it is most likely the **shared-base
    artifact**. Report O3 as *false-with-shared-base-caveat*: "max similarity driven by the
    Challenger↔Critic pair, which share the `concilium-skeptic` body by design; not read as
    consensus-theater." Note it; do not headline it as a gate defect.
  - If the over-cap pair is a **cross-body pair** (`challenger_advisor` /
    `advisor_critic`) → that **is** a genuine distinctness concern and should be flagged as
    such.
  - In the report, always quote the per-pair numbers, name which pair drove `max`, and
    state the shared-base caveat explicitly so the O3 verdict is never read out of context.

(The earlier "use three distinct bodies so O3 isn't biased" plan tried to *engineer away*
this confound — but doing so changes the gate under test. The honest move is to measure the
real gate and *interpret* O3 with the shared-base caveat, which is what this section does.)

---

## Leak check (done at fixture-authoring time — bench-oracle guardrail)

The seeded `CANVAS.md` and `IDEA.md` were scanned, case-insensitively, for any term that
could let a role trivially game the token count instead of doing real challenge work:

```
token  brevity/brief  concise  short  15k / 15000 / 15,000  terse  succinct
word count / word limit / word cap  page  length  "fewer words"
```

**Result: CLEAN** — no such term appears in either file. The only incidental hit during
authoring was the literal substring "token" inside the fixture's own provenance label
("challenge-token-oracle measurement"); that label was rephrased to "challenge-gate
oracle measurement" so even the metadata carries no brevity/token cue into a role's
context. The fixture describes a realistic, mid-complexity feature (a per-user
notifications **digest** delivery mode) and says nothing about how long or short a
response should be, nor anything about a token budget. Re-run the scan before any future
edit to these files:

```bash
grep -niE "token|brevit|concise|\bbrief\b|\bshort\b|15k|15[,.]?000|terse|succinct|word[ -]?(count|limit|cap)|\bpage\b|length|fewer words" \
  metrics/corpus/challenge-token-oracle/CANVAS.md metrics/corpus/challenge-token-oracle/IDEA.md
```

---

## Procedure

### 1. Pin the agent snapshot (reproducibility)

Record the exact commit/tag of the agent files being measured, so the gate slice is
reproducible:

```bash
git -C <repo> rev-parse HEAD        # record this SHA in the report
git -C <repo> describe --tags --always
```

The measured gate behaviour belongs to *that* snapshot of `concilium/skeptic.md`,
`concilium/tech-arbiter.md`, and `commands/concilium.md`. Agent files keep evolving on
`main`; a comparison or re-run must pin the same snapshot.

### 2. Dispatch the three REAL challenge-mode roles — TEXT-ONLY

Dispatch the three real concilium challenge-mode body prompts **exactly as the canonical
`concilium.md` §"Challenge mode" table prescribes** (this is the gate Finding #2 is
about — we measure the ACTUAL gate, not a more-favorable variant), each against this
directory's `CANVAS.md` + `IDEA.md`, honoring the gate's per-round cap
(**≤180 words per role per round, ≤2 collision rounds** — see `concilium.md`):

| Role (challenge mode) | Agent body (REAL gate)   | Lens / pulls toward |
|-----------------------|--------------------------|---------------------|
| **Challenger**        | `concilium-skeptic`      | on the *requirement* — "is this the **right ask**?" |
| **Advisor**           | `concilium-tech-arbiter` | (+ distribution lens) on the *build* — "a **materially better approach**?" |
| **Critic**            | `concilium-skeptic`      | (+ market lens) on the *concept* — "**should it exist**?" |

> **Faithful to `concilium.md` (no deviation).** This runbook dispatches the canonical
> challenge-mode mapping verbatim: the real gate reuses only **two distinct bodies** —
> `concilium-skeptic` plays BOTH Challenger and Critic (different lenses: requirement vs.
> concept), `concilium-tech-arbiter` plays Advisor, and `concilium-market-realist` is
> **NOT** dispatched (market is only a *lens* the Critic applies, not a separate body).
> **Correction note:** an earlier PR-2 *plan* had an inaccurate mapping
> (Challenger→skeptic, Advisor→`market-realist`, Critic→`tech-arbiter` — three distinct
> bodies, justified as "better for O3"). That was unfaithful: it would have measured a
> more-favorable *variant* of the gate, not the gate itself. This runbook supersedes that
> plan and dispatches the real mapping. The scorer is agnostic to role-name semantics (it
> only sees three labelled outputs), so the operator MUST map the labels per the table
> above and record the pinned `concilium.md` mapping in the report.
>
> *Optional, clearly-labelled extra arm (NOT the Finding #2 measurement):* if you want to
> probe how much the shared-skeptic base inflates Challenger↔Critic similarity, you MAY
> run a separate **distinct-body variant** (Critic→`concilium-tech-arbiter` or
> `concilium-market-realist`) and label it as such. Never report this variant as the
> headline Finding #2 result — it is a sensitivity check on the O3 confound below, not the
> real gate.

**Bench-isolation (binding):** every role subagent is **TEXT-ONLY**. Instruct each
explicitly: *"Respond with your challenge as text only; do NOT Write, Edit, or run Bash
on any files."* The seeded fixture is read-only. Stage any scratch input/output **outside
the repo** (e.g. `/tmp/...`), never in a tracked directory.

### 3. Force the model via the explicit dispatch parameter

Per-agent `model:` frontmatter is **not** honoured by the runtime — set the model via the
explicit dispatch `model` parameter.

- **Primary: Opus** — the model the gate's judgment is validated on. The headline result
  is the Opus number.
- **Optional floor model (e.g. Haiku)** to expose variance — run separately and label it
  clearly; never blend it into the Opus tally.

### 4. Capture run-data (MISSING discipline)

For each role, capture its reported `subagent_tokens` and its output text into a scratch
`run-data.json` **outside the tree** (e.g. `/tmp/run-data.json`), matching the scorer's
schema:

```json
{
  "model": "opus",
  "bound": 15000,
  "roles": {
    "challenger": {"tokens": <subagent_tokens>, "text": "<role output>"},
    "advisor":    {"tokens": <subagent_tokens>, "text": "<role output>"},
    "critic":     {"tokens": <subagent_tokens>, "text": "<role output>"}
  }
}
```

**If a role's token figure is not reported, record `null` — do NOT guess or default to
0.** The scorer will then return `status: MISSING` (exit 2). A MISSING run is recorded as
MISSING; it is never silently turned into a pass. This is the anti-fabrication guard.

### 5. Score

```bash
python3 config/claude/metrics/challenge_token_oracle.py score /tmp/run-data.json
# exit 0 = O1 and O3 both hold;  1 = scored, a verdict FAILED;  2 = MISSING
```

Capture the full JSON verdict (it includes `total_tokens`, `O1_token_bound_hold`,
`pairwise_similarity` (the three per-pair Jaccard values), `max_pairwise_similarity`, and
`O3_roles_distinct`). When O3 is `false`, inspect `pairwise_similarity` per the
shared-base section above before calling it a gate failure.

### 6. Repeat N=3 per model; report the distribution

Run steps 2–5 **three times** per model (LLM output is stochastic). Report the
distribution of `total_tokens` (min / median / max) and the **bound-hold count** (how
many of the 3 runs had `O1_token_bound_hold == true`). Never report a bare "passes":
always pair the verdict with the measured token total and the run count.

### 7. Emit ONE honest run — on `agileteam-improved` ONLY

On the `agileteam-improved` branch (never `main`, never the feature branch):

```bash
python3 config/claude/metrics/emit_run.py \
  --corpus-id challenge-token-oracle --mode full \
  --metrics '{"challenge_gate_tokens": <median_total_tokens>}' \
  --gate-outcomes '{"challenge_gate": "<pass|fail|MISSING>"}'
```

Use the **median** total across the N runs as the metric value. If any run was MISSING
and a real figure cannot be obtained, record the gate outcome as `MISSING`, not a number.

### 8. Write the honest report

Write `metrics/bench-<date>-challenge-token-oracle.md` (on `agileteam-improved`)
containing:
- The pinned agent snapshot SHA and the role→agent mapping actually dispatched — which
  MUST be the canonical `concilium.md` mapping (Challenger & Critic both
  `concilium-skeptic`, Advisor `concilium-tech-arbiter`). If any optional distinct-body
  variant was also run, report it separately and clearly labelled, never as Finding #2.
- Model + `n` per arm; the `total_tokens` distribution (min/median/max) and bound-hold
  count; the O3 distinctness verdict **with the per-pair `pairwise_similarity` numbers and
  the shared-base caveat** — name which pair drove `max`, and if it is the shared-base
  Challenger↔Critic pair say so explicitly (an elevated value there is expected, not
  consensus-theater).
- The explicit answer to Finding #2: *does the real challenge gate stay ≤15k, on which
  model, over how many runs — or does the bound need a real hard-stop?*
- Every limitation / confound / leak consideration (including the shared-base O3 confound),
  and the reach statement (§"What this measures"). A "the bound does NOT hold" result is a
  **success of the instrument** and triggers the follow-up "real token hard-stop" ticket.

### 9. Isolation check (binding)

After the run, confirm the tree is clean and the suite is green:

```bash
git -C <repo> status --short          # expect empty (no stray builder output in-tree)
bash config/claude/tests/run_all.sh   # expect: ALL CHECKS PASSED
```

Revert any stray file a builder subagent wrote into a tracked directory before
continuing.

---

## Files in this fixture

| File | Role |
|------|------|
| `CANVAS.md` | The `user-confirmed` Product Canvas (leak-checked, neutral). |
| `IDEA.md`   | The raw founder-voice idea fed alongside the Canvas (leak-checked). |
| `RUNBOOK.md`| This procedure. |
