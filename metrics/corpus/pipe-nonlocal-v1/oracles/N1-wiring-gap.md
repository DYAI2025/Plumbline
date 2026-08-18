# Oracle N1 — composition-root wiring gap

**Dark zone.** A handler can be 100% correct in isolation yet never run in
production because it was never registered in the composition root. Unit tests of
the handler stay green forever; only a test that exercises the feature *through*
`build_app()` notices.

**Mutation (non-local).** `mutate_nonlocal.py N1 <dir>` removes the
`bus.register(...)` wiring line(s) from `src/app.py::build_app()`. The handler is
left untouched and still passes every unit test.

**Scoring.** Run the arm's own `pytest -q` after mutation:
- RED → the suite reaches the composition root → **caught**.
- GREEN → the suite only tested the unit → **escaped** (the real dark zone).

**Discrimination (validated 2026-05-29).**
- `ref/tests_unit_only/` → GREEN post-mutation → ESCAPED.
- `ref/tests_integration/` → RED post-mutation → CAUGHT.

**Fairness.** `FEATURE.md` says only "make welcome-on-signup work end to end";
it does **not** say "test it through build_app()". Whether the tester wires the
test through the production root is the arm's free choice — the variable under test.
