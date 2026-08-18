# bench-core-v1 — drift-vs-precision corpus for the agileteam DNA

A **frozen, gap-seeded** corpus to measure whether the agileteam DNA (Reality Ledger,
composition-root/wired-in-prod test, failure-mode→test, foreign-API verification,
docstring-lie review) actually catches the dark-zone defect class the baseline misses —
**without** crying wolf on clean code.

Origin: the canary `metrics/bench-2026-05-29-canary.md` found signal but was confounded
(N=1, one task that spoon-fed "this is the composition root"). This corpus fixes both:
multiple tasks across the failure classes, **no task names its own gap**, and explicit
**controls** to measure false positives.

## Files
- `manifest.json` — machine index: task id, gap_class, is_control, target_agent, fixtures.
- `tasks.md` — **arm-facing** specs (the only thing an arm sees).
- `rubric.md` — **judge-only** detection keys + control criteria. NEVER show to an arm.
- `fixtures/<id>/…` — files the runner stages into the arm's working tree (T04 SDK stub).

## Task mix (12) — balanced 6 gap / 6 control
- **Gap (6):** T01 wiring-not-composed · T02 fake-only-reality · T03 failure-mode-not-tested
  · T04 disproven-external-api · T05 docstring-lie(review) · T08 wiring+fake-only-unannounced.
- **Control (6):** T06 pure-logic · T07 already-correctly-specified · T09 honest-review ·
  T10 failure-mode-detector over-fire · T11 foreign-api-detector over-fire (API present) ·
  T12 pure-validation. Each control is a matched over-fire surface for a detector, so the
  bench penalises crying wolf as hard as it credits catching gaps.

> v2 note: this corpus was revised once after an independent fairness audit (de-cued
> T01/T02, fixed T04's mode, de-jargoned the T02 rubric, balanced controls 3→6). It was
> never baselined under v1, so nothing is owed a re-baseline.

## Metrics
- **Primary — escaped_defect_rate** = missed / 6 gap tasks (lower better).
- **Secondary — false_positive_rate** = false_positive / 6 control tasks (lower better).
- Anti-Goodhart: a lower escaped-defect-rate bought with a higher false-positive-rate is
  NOT an improvement. Weight both over flow/throughput.
- **Power / minimum detectable effect:** at 6+6 tasks, one judged flip ≈ 17 points on
  either rate per run. Report the MDE explicitly and run ≥3×/cell; a between-arm delta
  smaller than ~one task is **no signal**, on either metric. Balanced denominators mean the
  bench is now as able to detect DNA crying wolf as DNA catching gaps (the v1 asymmetry —
  6 gaps vs only 3 controls — is fixed).

## Arms × models × runs
- **Arms (pinned):** `baseline@ee77e4c` vs `dna@<HEAD>` — extract the target agent's prompt
  from each commit (`git show <commit>:<agent>.md`) and run identically otherwise.
- **Models:** `haiku` AND `opus` — weak reveals floor-raising, strong reveals ceiling.
- **Runs:** ≥3 per cell (arm × model × task). Never conclude from one run.
- **Confounder fix:** pin ONE agent snapshot per arm across all runs; record in
  `config_fingerprint`. Compare arms only at the same agent state.

## Run modes
1. **Isolated probe (cheap, default):** for each task, feed `tasks.md`'s spec to the
   `target_agent`'s prompt under each arm. This is the canary method, now multi-task +
   controlled. Best ROI.
2. **Full pipeline (faithful, expensive):** run `/agileteam` over each task per arm — all
   DNA interventions together. Budget heavy (~a full sprint per task per run).

### File-dependent tasks (T04, T11) — MANDATORY access guarantee
T04 and T11 are `file_dependent` / `probe_requires_file_access: true`: their (gap or
control) verdict depends on the arm actually reading the staged stub SDK. A **prompt-only**
probe with no file/tool access CANNOT run them fairly — the arm could neither discover the
missing `archive` (T04) nor confirm the present `send` (T11), collapsing both into a
vocabulary test. So run T04/T11 ONLY in a mode where the arm has a read tool AND the
`fixtures/<id>/vendor/*.py` file is staged into its working tree (or the file's contents are
inlined into the task input). Otherwise exclude them and say so in the report — never score
them under prompt-only probe. (Their `target_agent` therefore excludes the prompt-only
tester arm.)

## Judging (blind)
For each arm output, give an independent judge **only** the output + the task's `rubric.md`
entry, **withholding which arm/model produced it**. Judge returns `caught|missed` (gap) or
`clean|false_positive` (control), with the one-line evidence. Shuffle order; ideally a
different model judges than produced the output.

**De-jargon before judging (anti-leak):** DNA outputs may carry signature vocabulary
("Reality Ledger", "evidence-class", "Gegenthese", "kritische semantische Glättung") that
de-blinds the arm to the judge even without a label. Normalise it out — strip/relabel house
terms before handing the output to the judge — and instruct the judge to score the
underlying *concern in any phrasing*, never the presence of a term. The rubric keys are
written term-agnostic for this reason.

## Recording
After each run: `python3 config/claude/metrics/emit_run.py --corpus-id bench-core-v1
--mode <full|probe> [--baseline for the control arm] --metrics-file <m.json>
--gate-outcomes '<...>'`. Then `python3 config/claude/metrics/process_health.py
--runs metrics/runs.jsonl --out metrics/process-health.md`. Write the comparison to
`metrics/bench-<date>.md`: per-metric arm means + delta + signal/noise verdict.

## Honesty guards (baked in)
- The corpus is **frozen** — do not edit tasks/rubric between arms or runs (edit = new
  corpus version, re-baseline).
- Controls exist so "caught more gaps" can't hide "invented more phantom gaps".
- T08 is the anti-confound task: it never mentions a composition root, so a "caught" there
  is real unprompted probing, not a cued response.
- A delta inside one judged-task's worth of noise across 3 runs is reported as **no signal**.
