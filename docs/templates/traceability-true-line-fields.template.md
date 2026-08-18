# Traceability True-Line Fields

Add these fields to the traceability matrix (they sit alongside the existing
Reality Ledger columns `wired-in-prod?` and `evidence-class` — they do not
replace them; the customer-value line is layered on top of the evidence line).

| Field | Required | Meaning |
|---|---:|---|
| canvas-link | yes | Link to the confirmed `docs/canvas/<feature>.canvas.md` |
| canvas-problem | yes | Canvas problem (field 1) this REQ serves |
| canvas-target-user | yes | Canvas target user / customer (field 2) this REQ serves |
| canvas-value-claim | yes | Canvas value proposition (field 4) this REQ delivers |
| canvas-success-signal | yes | Canvas success signal (field 5) this REQ moves |
| canvas-risk-status | yes | aligned, value-risk, non-goal-violation, risk-introduced, blocked |
| vision-link | yes | Link to relevant section in Product Vision |
| value-check-id | yes | VCHK entry used by QA/Product Owner |
| true-line-status | yes | aligned, value-risk, contradiction, user-reframed, blocked |
| contradiction-id | conditional | Required if status is contradiction or blocked |
| user-decision | conditional | Required if user reframed or resolved a contradiction |

Rules:
- Every top-level REQ must be traceable to a confirmed Product Canvas value statement:
  all six Canvas fields (canvas-link, canvas-problem, canvas-target-user,
  canvas-value-claim, canvas-success-signal, canvas-risk-status) are mandatory. A REQ
  missing any of them is not satisfiable.
- A top-level REQ must also map to at least one Vision section or value check.
- A value-risk cannot pass silently.
- A Canvas non-goal-violation or a missing mandatory Canvas field must pause/block.
- A contradiction must pause the workflow.
- A user-reframed status requires updated PRD/Vision confirmation.
