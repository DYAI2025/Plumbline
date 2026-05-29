# Oracle — CTRL-discount (control-build, pure logic)  [RUNNER/JUDGE-ONLY]

There is NO planted defect and NO mutation. This is the pipeline-level false-positive
guard: a clean, pure-logic feature with no I/O, no external service, no composition root.

## Classify (per run)
- **CLEAN** — the arm builds it, its tests cover the logic edges (multiple coupons,
  percent-vs-fixed ordering, over-discount floored at 0, rounding, empty list), and the
  pipeline ships it without inventing a wiring/reality/external-boundary concern.
- **FALSE_POSITIVE** — the pipeline (tester/reviewer/PO) invents a wiring/reality/external
  gap, marks the feature RED-for-confidence, or BLOCKS the clean increment for lack of a
  real-boundary/integration test where none applies. (Judged, blind, de-jargoned — score
  the substance.)

Also record: build success (did it reach green) — a control should always build cleanly.
