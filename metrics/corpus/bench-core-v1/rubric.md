# bench-core-v1 — Detection rubric (JUDGE-ONLY — never show to an arm)

The judge sees an arm's output (BLIND to which arm produced it) + this rubric, and
returns per task: for gap tasks `caught | missed`; for control tasks `clean |
false_positive`. "Caught" requires the arm to surface a test/finding that would
actually fail under the planted gap, OR explicitly name the gap class with a concrete
killing check — vague gestures ("test thoroughly", "consider integration") do not count.

---

## T01 — wiring-not-composed
**Planted gap:** natural impl adds the limiter class + unit tests but the application
factory never registers the middleware → no limiting in production.
**CAUGHT iff** the plan includes a test that drives the **assembled app via the factory**
(full middleware stack) and asserts a real 429 after the 101st request — i.e. proves the
limiter is actually wired, not just that `limiter.check()` works in isolation. Naming
"verify the limiter is registered in the running app / not just unit-tested" counts.
**MISSED iff** all limiter tests are unit-level against the class/limiter directly with no
assembled-app/middleware path.

## T02 — fake-only-reality
**Planted gap:** every test uses the fake `HttpClient`; nothing proves a real POST leaves
the process or that a real receiver can verify the HMAC signature.
**CAUGHT iff** the arm flags — **in any phrasing** — that fake-only coverage does NOT prove
real delivery and calls for at least one reality/boundary check: e.g. a quarantined test
against a local HTTP sink, a signature contract test a real receiver could run, or a
caveat that "the fake receiving the call doesn't prove a real POST leaves the process /
this isn't done until proven against a real endpoint". Score the *substance*, not house
vocabulary — do NOT require any specific term.
**MISSED iff** the plan treats "fake HttpClient received the call" as sufficient proof of
the feature with no reality/boundary caveat.

## T03 — named-failure-mode-not-tested
**Planted gap:** the cache-backend timeout/error fallback is described but obvious tests
cover only hit + miss.
**CAUGHT iff** the plan includes a test that **forces a cache-backend timeout/error** and
asserts the live-pricing fallback still returns a price (the named failure-mode becomes a
falsifying test).
**MISSED iff** only hit and miss are tested; the timeout/down path is absent or only
mentioned in prose without a test.

## T04 — disproven-external-api
**Fixture:** the runner places `vendor/ticketing_sdk.py` exposing only `close_ticket(id)`
and `set_status(id, status)` — **no `archive` method**.
**CAUGHT iff** the arm does NOT silently assume `.archive()`; it either reads the real SDK
and flags that no archive operation exists (so the requirement's premise is unverified /
must be confirmed), or demands verifying the SDK method against the real file before
treating it as a build premise.
**MISSED iff** the arm plans tests that mock/assume `ticketing_client.archive(...)` as if
it exists, treating the external contract as given.

## T05 — docstring-lie (review)
**Planted gap:** the docstring promises "raises InsufficientFunds … never left negative"
but the body has no check and can go negative; tests cover only the happy path.
**CAUGHT iff** the review flags that the docstring/contract promises behaviour the code
does not implement (the missing InsufficientFunds check / negative-balance possibility)
AND/OR that the guarantee is untested.
**MISSED iff** the review approves, comments only on style, or misses the contract↔code
divergence.

## T06 — CONTROL (pure logic, no I/O)
**No planted gap.** Correct behaviour = boundary/precision/precedence edge cases
(empty coupons, >100% discount floor at 0, rounding, percentage-vs-fixed ordering).
**CLEAN iff** the arm focuses on those and raises NO reality-ledger/wired-in-prod/external
flag (there is no I/O boundary to flag).
**FALSE_POSITIVE iff** the arm invents a reality/wiring/external-boundary gap or marks the
feature RED-for-confidence when none applies. (This penalises crying wolf.)

## T07 — CONTROL (already correctly specified)
**No planted gap** — the spec already states wiring (factory route), an assembled-app
acceptance test, and a real-tmpdir reality test exist.
**CLEAN iff** the arm acknowledges those are covered and adds only genuine *additional*
edge cases (encoding, huge exports, empty set, injection in CSV cells).
**FALSE_POSITIVE iff** the arm re-flags wiring or reality as a gap despite the spec stating
they are covered (failure to read what is already done = the inverse blind spot).

## T08 — wiring+fake-only, UNANNOUNCED (anti-confound)
**Planted gaps (two):** (a) the cleanup must actually be invoked by the real
account-deletion flow — natural impl adds a `cleanup()` never called by the deletion path;
(b) it is only ever tested against the in-memory `ObjectStore` fake. The spec deliberately
does NOT mention a factory / composition root / "what runs in prod".
**CAUGHT iff** the arm — unprompted — probes whether deletion actually triggers the
cleanup (a test through the real deletion flow, not `cleanup()` in isolation) **and/or**
flags that fake-only object-store coverage doesn't prove real S3 deletion. Catching
EITHER planted gap = caught; catching both = strong.
**MISSED iff** the plan only tests `cleanup()` directly against the fake and never
questions invocation-by-the-deletion-flow or real-store reality.

## T10 — CONTROL (pure logic, no failure mode) — over-fire control for the failure-mode detector
**No planted gap.** A duration formatter has an obvious happy path and **no risky failure
mode / no fallback / no I/O**. Correct behaviour = boundary edge cases (0, exactly 60s,
sub-minute, multi-hour, very large; negative input policy is a fair real nit).
**CLEAN iff** the arm tests those edges and raises NO invented failure-mode/fallback test,
no reality-ledger flag, no wiring/external flag.
**FALSE_POSITIVE iff** the arm invents a "what if it times out / degrades / the backend
fails" failure-mode test or any reality/wiring/external gap where none exists. (Penalises
the failure-mode detector over-firing.)

## T11 — CONTROL (foreign API genuinely present) — over-fire control for the foreign-API detector
**Fixture:** the runner stages `vendor/sms_sdk.py` exposing a real `send(to, body)` method
(see `fixtures/T11/`). The `send` operation the task assumes **does exist**.
**No planted gap.** The correct move is to verify the SDK and find `send` present, then
proceed.
**CLEAN iff** the arm either proceeds normally, or verifies the SDK and confirms `send`
exists. (Verifying and confirming-present is the *correct* outcome, not a flag.)
**FALSE_POSITIVE iff** the arm declares the SMS `send` API unverified-as-a-BLOCKER or
absent/disproven when reading the staged stub shows it is present. (Penalises the
foreign-API detector crying "unverified" reflexively when the method is in fact there.)
*Note: like T04, file-dependent — only run in a mode where the arm can read the stub.*

## T12 — CONTROL (pure validation logic)
**No planted gap.** Pure field validation, no I/O/wiring/external boundary.
**CLEAN iff** the arm tests the validation rules + boundaries (empty, exactly-12-char
password, valid/invalid email shapes, both-fields-bad) with no reality/wiring/external flag.
**FALSE_POSITIVE iff** the arm invents a reality-ledger, wired-in-prod, or external-API gap
where none exists.

## T09 — CONTROL (honest review)
**No planted gap** — the `refund` docstring matches the code (guard present) and tests
cover happy path, over-capture, and the exact-balance boundary.
**CLEAN iff** the review approves or raises only minor/legitimate nits (e.g. negative-amount
input not covered — a fair, real edge case).
**FALSE_POSITIVE iff** the arm invents a docstring-lie or a contract↔code divergence that
isn't there. (Penalises a docstring-lie detector that over-fires.)

---

## Scoring
- `escaped_defect_rate = missed / (6 gap tasks: T01,T02,T03,T04,T05,T08)`  → lower better.
- `false_positive_rate = false_positive / (6 control tasks: T06,T07,T09,T10,T11,T12)` → lower better.
- Denominators are balanced (6:6) so catch-rate and cry-wolf-rate are equally powered.
  Each control surface has a matched detector: T06/T12 (pure-logic reality/wiring over-fire),
  T07 (re-flagging already-done), T10 (failure-mode over-fire), T11 (foreign-API over-fire),
  T09 (docstring-lie over-fire).
- Report both per arm × model. A DNA arm "wins" only if it lowers escaped-defect-rate
  **without** raising false-positive-rate beyond the noise threshold. Judge must be blind
  to arm identity; run each cell ≥3× and report mean + a signal/noise verdict (a delta
  inside one judged-task's worth of noise — here 1/6 ≈ 17 pts on either rate — is NOT a
  signal; state the minimum detectable effect honestly).
