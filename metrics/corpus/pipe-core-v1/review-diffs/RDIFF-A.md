# PR for review: remove a user's files when their account is deleted

`src/accounts.py`:
```python
class AccountService:
    def __init__(self, db, store):
        self.db = db
        self.store = store
    def delete_account(self, user_id):
        self.db.pop(user_id, None)        # remove the account record
        self.store.delete_all(user_id)    # NEW: remove the user's files
```
Wiring: `src/app.py` `build_service()` constructs `AccountService(db, store)`; the
`DELETE /account/{user_id}` route calls `service.delete_account(user_id)`. Confirmed wired
into the running app. Store is `InMemoryObjectStore` (fake) in tests, `S3ObjectStore` in
production.
Tests (all green, through `build_service()`): create account+files → delete_account →
assert account gone and `store.list_files(user_id) == []`; plus multi-file,
other-users-unaffected, no-files, nonexistent-account.
