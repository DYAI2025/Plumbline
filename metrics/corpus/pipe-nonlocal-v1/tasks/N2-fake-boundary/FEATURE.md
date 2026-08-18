# Feature: action audit log

Record user actions so they can be retrieved later.

## What exists
- `src/store.py` — `Store` protocol; `FileStore(path)` persists records to a file
  (this is what production uses).
- `src/service.py` — `AuditService(store)` with `record_action(actor, action)` and
  `history()`.

## Task
Make action auditing work: recorded actions must be retrievable. Deliver the
implementation and its tests.

## Run tests
`<venv>/python -m pytest -q` from the repo root.
