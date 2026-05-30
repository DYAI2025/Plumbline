# Traceability True-Line Fields

Add these fields to the traceability matrix (they sit alongside the existing
Reality Ledger columns `wired-in-prod?` and `evidence-class` — they do not
replace them; the customer-value line is layered on top of the evidence line).

| Field | Required | Meaning |
|---|---:|---|
| vision-link | yes | Link to relevant section in Product Vision |
| value-check-id | yes | VCHK entry used by QA/Product Owner |
| true-line-status | yes | aligned, value-risk, contradiction, user-reframed, blocked |
| contradiction-id | conditional | Required if status is contradiction or blocked |
| user-decision | conditional | Required if user reframed or resolved a contradiction |

Rules:
- A top-level REQ must map to at least one Vision section or value check.
- A value-risk cannot pass silently.
- A contradiction must pause the workflow.
- A user-reframed status requires updated PRD/Vision confirmation.
