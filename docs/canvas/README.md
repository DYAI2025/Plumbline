# `docs/canvas/` — Product Canvas artifacts

This directory holds the **user-confirmed Product Canvas** artifacts produced by the
mandatory Product Canvas gate in `/agileteam` (Phase 0.15).

- One file per feature: `docs/canvas/<feature>.canvas.md`.
- Generated from `docs/templates/product-canvas.template.md`.
- A canvas must reach `Status: user-confirmed` (the user confirms it explicitly; no agent
  may self-confirm) before the PRD is finalized or development starts.
- Every top-level requirement traces back to a confirmed Canvas value statement via the
  six mandatory Canvas traceability fields (`canvas-link`, `canvas-problem`,
  `canvas-target-user`, `canvas-value-claim`, `canvas-success-signal`,
  `canvas-risk-status`).

See `docs/agileteam-spec-v3.md` ("Required Product Canvas") and
`config/claude/commands/agileteam.md` ("Mandatory Product Canvas gate").
