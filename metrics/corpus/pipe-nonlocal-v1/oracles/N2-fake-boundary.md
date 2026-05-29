# Oracle N2 — fake-test / real-boundary gap

**Dark zone.** "Tests grün ≠ funktioniert." If the suite only exercises an
in-memory fake of the persistence boundary, a break in the *real* boundary impl
(the one production uses) is invisible. The evidence class is `unit-fake`, not
`real-boundary-smoke`.

**Mutation (non-local).** `mutate_nonlocal.py N2 <dir>` neuters
`FileStore.append()` to a no-op (`return`). The fake store is untouched.

**Scoring.** Run the arm's own `pytest -q` after mutation:
- RED → the suite round-trips through the real `FileStore` → **caught**.
- GREEN → the suite only used a fake → **escaped** (the real dark zone).

**Discrimination (validated 2026-05-29).**
- `ref/tests_fake_only/` → GREEN post-mutation → ESCAPED.
- `ref/tests_real_boundary/` → RED post-mutation → CAUGHT.

**Fairness.** `FEATURE.md` says only "recorded actions must be retrievable"; it
does **not** say "test against the real FileStore with a temp file". Choosing the
real boundary over a fake is the arm's free choice — the variable under test.
Temp files are permitted (no real network/service).
