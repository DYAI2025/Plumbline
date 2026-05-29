# Faithful pipeline data point — T08, DNA-v4 vs baseline (2026-05-29)

**This is N=1 per arm — a single faithful data point, NOT a bench.** Option B from the
plan: scaffold one corpus task (T08) into a real buildable repo, run each arm's
tester→coder→reviewer DNA to build the feature with tests, then measure with a
deterministic ground-truth oracle. Clearly labelled: one run/arm, Haiku build+review,
one small feature. It tempers — does not overturn or confirm — the isolated-probe result.

## Setup
- Scaffold repo: `AccountService.delete_account` (removes DB record only) + `ObjectStore`
  (`InMemoryObjectStore` fake; `S3ObjectStore` prod stub) + `build_service()` composition
  root. Feature to build: "deleting an account also removes the user's files."
- Arms pinned: tester+reviewer `@ee77e4c` (baseline, pre-DNA) vs `@HEAD` (DNA-v4).
- Build agents (Haiku) implemented the feature TDD into their own repo copy; both reached
  green (baseline 9 tests, v4 7 tests).

## Measurement 1 — wiring mutation oracle (deterministic)
Un-wire the cleanup (delete the `store.delete_all` call from `delete_account`), then run
**each arm's own tests**:

| arm | result after un-wiring |
|---|---|
| baseline | **7 failed**, 2 passed → wiring guarded |
| v4 | **5 failed**, 2 passed → wiring guarded |

**No differential.** Both arms' built increments catch the wiring regression. Why: both
testers wrote the obvious acceptance test ("delete account → files gone") **through
`build_service()`** — which inherently exercises the wiring. **This means the isolated
test-PLAN probe (baseline 0/3 on T08) OVERSTATED the DNA's wiring value:** when the
pipeline actually *builds* the feature, the natural acceptance test covers the wiring
regardless of arm. "Articulating the wiring concern in a plan" ≠ "the built increment
guards it" — and the latter (what matters) was equal here.

## Measurement 2 — review layer (arm-pinned code-reviewer on the diff)
| arm | verdict | findings |
|---|---|---|
| baseline | **BLOCK** | error-handling gap (if S3 `delete_all` raises, account gone but files leak; no transactional safety, untested), DB-before-cleanup ordering, no audit log; noted real-S3 integration |
| v4 | **SHIP** | "wired through composition root + E2E'd, no critical/important issues" — only a docstring nit |

**This ran counter to the DNA hypothesis.** The baseline reviewer's open-ended scrutiny
caught substantive production gaps and blocked; the v4 reviewer's DNA "wired-in-prod"
check **passed** (the feature genuinely is wired + E2E'd), and it shipped — **missing** the
transactional/ordering/audit gaps. The DNA's reality-ledger did NOT fire either: v4 treated
the fake-based E2E as sufficient and did not flag "real S3 deletion unproven". On this run
the DNA lens appears to have **narrowed** the reviewer (focus on "is it wired?" → yes →
done), crowding out broader judgment, while the plain baseline reviewer was more thorough.

## Honest verdict
This faithful pipeline data point **does NOT support a DNA full-pipeline advantage on
T08**, and on the review layer it leans **against** the DNA (possible narrowing effect).
It does not refute the isolated-probe result either — they measure different things:

- **Validated (isolated tester probe, 3 runs/cell):** at the *test-plan derivation* level
  the DNA-v4 reaches baseline precision with 5× recall. That stands.
- **Not supported (this pipeline data point, N=1):** that the test-plan advantage
  translates into a better *built increment* end-to-end. Here the wiring was equally
  caught by both (natural acceptance test), and the v4 reviewer was weaker than baseline.

The instrument again did its job: it stopped me from generalising "DNA validated on the
tester probe" into "DNA improves the whole pipeline." It does not — not on this evidence.

## Caveats / what would settle it
- N=1 per arm; reviewer output is high-variance; one small feature whose wiring is
  naturally testable; Haiku; a scoped slice (tester→coder→reviewer), not every gate
  (no requirements-analyst/spec-auditor/security/production-validator/product-owner).
- A real conclusion needs **Option A**: a multi-task, ≥3-runs/arm full-pipeline bench with
  built-increment outcome oracles, AND a check for the **reviewer-narrowing** risk this
  point surfaced (does the wired-in-prod check crowd out broader review?). Until then:
  **claim only the tester-isolated-probe validation; make no full-pipeline improvement
  claim.**
