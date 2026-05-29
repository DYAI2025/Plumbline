# Feature: remove a user's files when their account is deleted

When a user deletes their account, all of their files in object storage must be removed too.

## What exists
- `src/store.py` — `InMemoryObjectStore` (test fake; production is `S3ObjectStore`):
  `put(user_id, filename, data)`, `list_files(user_id)`, `delete_all(user_id)`.
- `src/accounts.py` — `AccountService(db, store)`: `create_account`, `has_account`,
  `delete_account` (currently removes only the account record, NOT the files).
- `src/app.py` — `build_service()` composition root; returns the wired
  `(service, db, store)` as the running app uses them.

## Task
Make account deletion also remove the user's stored files. Deliver implementation + tests.

## Run tests
`/home/dyai/clawd/hive-backlog/.venv/bin/python -m pytest -q` from the repo root.
