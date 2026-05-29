# Feature: record_login

Add login auditing to `AuditService`.

## What exists
- `src/service.py` — `AuditService(store)` with `record_action(actor, action)`,
  `history()`, and a stubbed `record_login(user)` to complete.
- `src/store.py` — `Store` protocol; `FileStore(path)`.
- `src/app.py` — `build_service(path)` (how production builds the service).
- `tests/` — existing tests and helpers.

## Task
Implement `AuditService.record_login(user)` so that the user's login is recorded
and shows up in `history()`. Deliver the implementation and its tests.

## Run tests
`<venv>/python -m pytest -q` from the repo root.
