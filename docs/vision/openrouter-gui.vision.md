# Product Vision: OpenRouter Council-Runner GUI (Slice 4)

Feature-Slug: openrouter-gui
Slice: 4 of the OpenRouter Council line (follows Slice 1 inference, Slice 2
deepseek-review-agent / `/concilium` presets, Slice 3a/3b measurement)
Status: user-confirmed (Ben, 2026-06-20) — authored by product-owner, consistent with the
user-confirmed Canvas, and confirmed by the user at the Phase-0 Vision gate (see §10).
Phase 0 is complete; this Vision is the basis for AgileTeam planning.
Owner: product-owner

Linked Product Canvas (user-confirmed, Ben 2026-06-20): docs/canvas/openrouter-gui.canvas.md
Linked PRD (finalized 2026-06-20): docs/prd/openrouter-gui.prd.md (REQ-GUI-001..018)
Traceability: docs/trace/openrouter-gui.trace.md (stub in PRD; built in Phase 0/0.5)
Reality Ledger (authored Phase 3 / Gate C): docs/reality/openrouter-gui.evidence.jsonl

> This Vision is bound to the confirmed Canvas and the finalized PRD above and must stay
> consistent with them. It is the customer-value line — the *direction* — not a second
> PRD. Where the Canvas/PRD say HOW, this says WHO it is for, WHAT changes for them, and
> WHAT would make it useless despite passing tests. The load-bearing honesty split below
> survives every rewrite: **Slice 4 makes the existing foreign council VISIBLE and USABLE
> from a local browser — it does NOT produce a verdict; it shows REAL live council
> positions or an HONEST classified message, NEVER a demo/injected council; and the
> user-facing live path DOES cross the real OpenRouter boundary (a `real-boundary-smoke`).**
>
> USER PRINCIPLED OVERRIDE (Ben, 2026-06-20) — SUPERSEDES the earlier "offline MVP renders
> INJECTED/demo positions" framing. The bundled DEMO council violates the core Plumbline
> principle "real code or no code" (`placeholder` is a FORBIDDEN_TOKEN). Ben's directive:
> "nur echt und nur was geht. Fake=Demo, dann weglassen." => the GUI is LIVE-ONLY-REAL:
> it shows REAL live council positions or NOTHING (an honest classified message). No
> canned/demo/injected council is ever shown to the operator; when live is unavailable
> (gate OFF, no key, rate-limit, attrition) the GUI shows a classified message, never a
> fake fallback. The `--inject-council` seam survives ONLY as test infrastructure. The
> evidence floor for the live render path RISES to `real-boundary-smoke` (an honest raise —
> a real boundary is now crossed), while the offline-tested mechanics stay
> `integration-fake`. This Vision stays `user-confirmed` — a user-directed re-scope of a
> confirmed direction, reconciled below.
>
> Spec-sanity remediation (2026-06-20, Phase 0.5): the spec-auditor findings are reflected
> here as HARDENING/CLARIFICATION of the SAME confirmed value, not a value reversal. The
> architecture is a SUBPROCESS with the key only in the child env; the key-leak gate is
> MVP-critical at full strength; the headline flow is wired through the REAL launcher; the
> real path fails LOUD on a missing precondition rather than rendering a plausible empty
> council; and mixed/partial council results render honestly. NOTE: the spec-sanity
> "offline renders INJECTED/demo positions as the MVP value" point is SUPERSEDED by the
> USER PRINCIPLED OVERRIDE above (LIVE-ONLY-REAL). This Vision stays `user-confirmed` — no
> confirmed product direction is re-opened against the user's own directive.

---

## 1. North Star (the confirmed customer value)

The foreign-model council already exists and is vetted (Slices 1–3). But running it is a
terminal-only act: you must know the right `deepseek_review.py preset` invocation, the
env gating, and how to read raw JSON. The council's *reasoning* — each character's
position, the diversity / foreign-only status, the RISK-B-007 disclosure — is buried in
JSON nobody reads casually.

The north star: **a LOCAL, secure, honest Council-Runner UI — paste an idea or a diff,
run the existing foreign-model council (Slice-2 characters/presets) LIVE, and SEE each
character's REAL position plus the diversity status, without leaving the local machine —
or an HONEST classified message when the live council cannot answer, NEVER a demo.**
(USER PRINCIPLED OVERRIDE, Ben 2026-06-20: LIVE-ONLY-REAL — "nur echt und nur was geht.
Fake=Demo, dann weglassen.")

The value is *making the foreign council's reasoning visible and usable* — friction
removed for the operator — **not** producing a verdict, an approval, or a value judgment.
The council shows its positions; the human still does the judging.

---

## 2. Who benefits, and what changes for them

- **Ben / the local Plumbline operator (the single local user).** Today, getting the
  council's view on an idea or a diff means hand-typing a CLI invocation, remembering the
  env gates, and squinting at raw JSON for `positions` / `diversity.gate` /
  `diversity.disclosure`. After Slice 4 they open a local page on `127.0.0.1`, paste the
  subject, pick a preset (A/B/C), click Run, and read each character's model + position
  side by side with the diversity / foreign-only status and the honesty disclosure —
  rendered from the **real** `deepseek_review preset` JSON. No CLI literacy, no JSON
  reading, no key handling on their part. The already-vetted council primitive stops
  being effectively unused for quick exploratory passes.

- **The reviewer / auditor.** They benefit from the *honesty* and *safety* themselves:
  a UI that surfaces the RISK-B-007 disclosure beside every result (distinct ids ≠ proven
  cognitive diversity), refuses to present the run as a verdict, keeps the API key
  server-side only, binds loopback-only, and fires zero live calls by default. The value
  here includes refusing to leak, refusing to over-claim, and refusing to spend credits.

## 3. When they would use it

When the operator wants a quick "what would the council say about this?" pass on a real
subject (an idea, a design note, a diff) and does not want to leave the local machine or
touch the CLI — an interactive, LIVE paste→Run→REAL-positions loop over the frozen
primitives (gated by `COUNCIL_INFERENCE_LIVE=1` + key, never fired by default), with an
honest classified message whenever the live council cannot answer. (USER PRINCIPLED
OVERRIDE, Ben 2026-06-20: LIVE-ONLY-REAL — no demo/injected council is ever shown.)

---

## 4. The True-Line invariants (staying true to confirmed value)

Success is **staying true to the confirmed value**, not "finishing" and not "tests
green." Concretely, this slice is true to value ONLY while all four invariants hold —
each is a value contract, not merely a functional one:

1. **Key stays server-side, always — and only in the subprocess child env.** The
   `OPENROUTER_API_KEY` is read server-side only (process env first, then
   `~/.openclaw/.env`) and used ONLY in the existing transport's `Authorization: Bearer`
   header. Architecturally (spec-sanity decision 1) the key lives ONLY in the spawned
   `deepseek_review.py preset` CHILD process env — the proxy's HTTP handler never reads it
   into its own locals, so a handler traceback cannot leak it. It is NEVER placed in the
   browser, the served HTML/JS, any HTTP response body, or any log. The leak gate is
   MVP-CRITICAL at FULL strength (NOT reduced by offline mode): an INDUCED-ERROR test
   forces exceptions and asserts the key is absent from BOTH the response body and
   stderr/log, and any error yields a GENERIC 500 with no traceback/body/env. The proxy
   binds `127.0.0.1` (loopback) by default; a non-loopback bind requires an explicit
   separate opt-in and is OUT of MVP scope. (Canvas RISK-GUI-1/2; PRD
   REQ-GUI-005/006/007/013/015.) **This is the highest-severity invariant — a key leak is
   the worst failure of this feature.**

2. **Reuse the vetted primitives — do NOT reimplement or diverge.** The GUI is
   presentation + a thin server-side proxy over the FROZEN primitives
   (`deepseek_review preset` → `council_inference` → `council_presets`). The proxy drives
   the existing entrypoint by SHELLING OUT to `deepseek_review.py preset --json` as a child
   process (spec-sanity decision 1 — NOT in-process import) and renders its JSON unchanged;
   it defines NO inference, preset, cap, key-derivation, live-gate, or diversity logic of
   its own, and constructs no HTTP request to OpenRouter itself. The key-absence guard is
   an ASSERTION over the output (denylist-absence check), NOT a transform of the council
   JSON — pass-through is preserved (spec-sanity decision 7). And the headline
   paste→run→render is exercised through the REAL `plumbline-council-gui` launcher (not only
   an injected handler), with a from-wrong-cwd test asserting fail-loud-or-resolve, so the
   launcher is wired in prod and not dead code (spec-sanity decision 5). (Canvas
   RISK-GUI-3/9; PRD REQ-GUI-005/010/013/016.)

3. **Honesty — positions, never a verdict.** The UI shows the council's positions and a
   visible in-UI "no verdict" disclosure carrying RISK-B-007 (distinct model ids ≠ proven
   cognitive diversity), rendered verbatim beside the diversity block. It MUST NOT imply
   the council's output is a validated answer, an approval, or a value verdict, nor that
   distinct ids prove cognitive diversity. (Canvas RISK-GUI-5; PRD REQ-GUI-004.)

4. **LIVE-ONLY-REAL; no demo fallback; live gated, never fired by default.** (USER
   PRINCIPLED OVERRIDE, Ben 2026-06-20; SUPERSEDES the earlier "offline MVP renders
   INJECTED/demo positions" framing.) The user-facing run is the REAL live council:
   paste→Run runs `deepseek_review.py preset --live` (gated by `COUNCIL_INFERENCE_LIVE=1` +
   key) and renders REAL positions — or an HONEST classified message (rate-limit /
   unavailable / attrition / "live required - gate OFF or no key"), NEVER a fake/demo
   fallback. The live gate is proven OFF-by-default by an offline test; when OFF the proxy
   REFUSES the run and returns the classified "live required" message (never a silent
   downgrade, never injected positions). Live is reached only by the explicit gated Run
   action, never on page load. With no budget the council runs on FREE models => real but
   rate-limited; attrition is shown honestly (per EXP-009), never beautified into a demo.
   The `--inject-council` seam survives ONLY as test infrastructure (real-shaped JSON to
   exercise render/security offline at 0 credits) — it is NOT a user-facing mode and never
   shows the operator a demo council. The evidence floor is SPLIT: the user-facing LIVE
   path crosses the real OpenRouter boundary and is a `real-boundary-smoke` (run at
   acceptance, an HONEST raise — a real boundary is now crossed), while the offline-tested
   mechanics stay `integration-fake` — never raise a class to clear a floor. (Canvas
   RISK-GUI-4 / the override; PRD REQ-GUI-001/008/009, evidence-class floor.) Pasted input
   is treated as opaque data (no `eval`, no shell interpolation, escaped render) so
   diff/XML/shell-meta content cannot execute or break the page. (Canvas RISK-GUI-6; PRD
   REQ-GUI-011.)

5. **Fail loud, never a plausible empty council; render mixed results honestly.**
   (spec-sanity decisions 2 + 6.) Driving the REAL council has three preconditions — a key
   in env, a catalog with ≥2 distinct free families, and cwd == repo-root (or
   `DEEPSEEK_CHARACTERS_DIR`) — and the launcher enforces each with a LOUD classified error
   rather than rendering a plausible all-`character-missing` / all-error result that reads
   as "the council had no opinion". When the council returns `overall:
   COUNCIL_MODEL_UNAVAILABLE` with SOME roles OK and some classified, the UI renders the
   MIXED state honestly — the OK positions AND the per-role codes — never a single error
   banner hiding the OK positions, never a fake success. (Canvas RISK-GUI-7/8; PRD
   REQ-GUI-014/017.)

---

## 5. The Gegenthese — what GREEN-BUT-UNTRUE looks like (for the plumbline-watcher)

The classic Reality-Ledger Gegenthese to hold against this slice at the final gate:
*could it be fully green yet deliver zero — or negative — user value?* Each shape below
is a value contradiction the watcher MUST catch; none may be downgraded to a "known
limitation" except by the user:

- **(a) Key leak.** The GUI passes its tests but the `OPENROUTER_API_KEY` reaches the
  browser, appears in an HTTP response body, is templated into the served HTML/JS, is
  written to a log, OR surfaces in an induced-error traceback / a non-generic 500 (the
  proxy handler closed over the key, or it logged the request body / env). Green tests with
  a leaked key is the worst possible outcome — it turns a convenience tool into a
  credential-exfiltration surface. (Falsifies invariant 1.)

- **(b) Re-implementation / divergence.** The proxy reaches around the CLI/library and
  re-derives inference, preset, cap, live-gate, or diversity logic — so it can silently
  drift from the vetted council and the gate while still rendering plausible output.
  (Falsifies invariant 2.)

- **(c) Verdict masquerade.** The UI presents the council's output as a validated answer
  or value verdict, or implies distinct ids prove cognitive diversity, with the RISK-B-007
  disclosure missing or buried. A confident-looking "the council approved this" is worse
  than no tool — it manufactures false assurance. (Falsifies invariant 3.)

- **(d) Beyond-loopback or live-by-default.** The proxy binds a non-loopback interface by
  default (exposing a key-holding endpoint to the LAN), or fires live calls by default
  (burning credits / hitting the free-tier rate limits — EXP-009 showed 100% free-tier
  attrition). (Falsifies invariants 1 and 4.)

- **(e) Evidence-class mismatch in EITHER direction.** Two shapes, both RED: (i) the live
  render path actually reaches the real OpenRouter boundary while the Reality Ledger still
  claims `integration-fake` (laundering the ceiling down); OR (ii) a record claims
  `real-boundary-smoke` for a path that did NOT cross the real boundary (a faked-up real
  smoke). The ledger class must match what each run actually did; the live path is
  `real-boundary-smoke`, the offline mechanics are `integration-fake` — never raise OR lower
  a class to clear a floor, and never cross (or claim to cross) the boundary dishonestly.
  (Falsifies invariant 4 / Reality-Ledger honesty.)

- **(i) Demo/injected council shown to the operator (the override's crux).** The GUI shows
  the operator a canned/demo/injected council — as the run result, or as a "fallback" when
  live is unavailable — instead of REAL live positions or an HONEST classified message. A
  fake council dressed as the real one violates "real code or no code" (`placeholder` is a
  FORBIDDEN_TOKEN) and manufactures false assurance the same way a verdict masquerade does.
  Per the USER PRINCIPLED OVERRIDE (Ben, 2026-06-20): "nur echt und nur was geht.
  Fake=Demo, dann weglassen." The `--inject-council` seam reaching a user-facing path is
  this shape. (Falsifies invariant 4.)

- **(f) Plausible-empty-council masquerade.** (spec-sanity decision 2.) A misconfigured
  real run — wrong cwd, no key, or a single-family catalog — renders a tidy
  all-`character-missing` / all-error result that READS like "the council ran and had no
  opinion", instead of failing loud with the real classified cause. A convincing empty
  council is a silent lie about whether the council ran at all. (Falsifies invariant 5.)

- **(g) Mixed-result hidden behind one banner / faked success.** (spec-sanity decision 6.)
  A partial run (`overall: COUNCIL_MODEL_UNAVAILABLE`, some roles OK, some classified)
  collapses to a single generic error banner that HIDES the OK positions, or is dressed up
  as a full success. Either way the operator loses the real, honest signal the per-role
  `positions[]` carries. (Falsifies invariant 5.)

- **(h) Real entrypoint dead, only the injected handler green.** (spec-sanity decision 5;
  the repo's signature false-green.) Tests drive an in-process injected handler and pass,
  while the real `plumbline-council-gui` launcher (cwd-pin, key-in-child, precondition
  enforcement) is never started — so the headline flow is unproven through the real
  entrypoint and could be dead on a real machine. (Falsifies invariant 2.)

A GUI exhibiting any of (a)–(i) is RED regardless of green tests, and that RED cannot be
silently downgraded.

---

## 6. Success signals (VCHK customer-value checks QA must verify)

These are the customer-value checks (mapped to the PRD acceptance criteria) that QA must
verify as *value*, not merely *function*:

- **VCHK-GUI-1 (the core value, LIVE-ONLY-REAL)** — From a browser on `127.0.0.1`, paste a
  subject, click Run with the live gate ON (`COUNCIL_INFERENCE_LIVE=1` + key), and SEE the
  per-role REAL positions + the diversity gate + the RISK-B-007 disclosure rendered in the
  real `deepseek_review preset` JSON shape — OR an HONEST classified message (rate-limit /
  unavailable / attrition on free models, per EXP-009), NEVER a demo/injected council. This
  crosses the real OpenRouter boundary and is a `real-boundary-smoke` (USER PRINCIPLED
  OVERRIDE, Ben 2026-06-20). (PRD AC-1L / AC-LIVE; REQ-GUI-001.) — the load-bearing
  customer-value signal. (The render/security MECHANICS are separately proven offline at 0
  credits via the test-only injected seam — PRD AC-1; REQ-GUI-002/003/009/018 — which is
  test infra, NOT a user-facing demo.)
- **VCHK-GUI-2 (key never in browser)** — The served HTML/JS and EVERY proxy response
  body contain NO `OPENROUTER_API_KEY` material; no key in logs. (PRD AC-2 / SEC matrix;
  REQ-GUI-005/006.)
- **VCHK-GUI-3 (loopback default)** — The proxy binds `127.0.0.1` and not a non-loopback
  interface by default. (PRD AC-3; REQ-GUI-007.)
- **VCHK-GUI-4 (live gate OFF => classified "live required", no fake fallback)** — With no
  live gate env set (or no key), a run makes no real transport call and is REFUSED with a
  classified "live required to run the council" message — never silently downgraded, never a
  demo, never injected positions — proven OFFLINE. (PRD AC-4; REQ-GUI-008.)
- **VCHK-GUI-5 (honesty / no verdict)** — On a completed run, the RISK-B-007 disclosure
  is shown and the UI states no value verdict. (PRD AC-5; REQ-GUI-004.)
- **VCHK-GUI-6 (classified errors surfaced)** — A classified non-OK `code` is surfaced
  unchanged — never a generic error, never a fabricated success. (PRD AC-6; REQ-GUI-012.)
- **VCHK-GUI-7 (input is opaque data)** — Pasted content with backtick / `$()` /
  `<script>` does not execute and is escaped. (PRD SEC matrix; REQ-GUI-011.)
- **VCHK-GUI-8 (real-path preconditions fail loud)** — A real run missing a precondition
  (no key, <2 distinct free families, or wrong cwd) returns a LOUD classified error, NOT a
  plausible all-`character-missing` / all-error render. (PRD AC-7; REQ-GUI-014.)
- **VCHK-GUI-9 (induced-error leak resistance + generic-500)** — Under an induced error
  (malformed POST, oversized body, broken pipe) the key sentinel is absent from BOTH the
  response body and stderr/log, and the response is a generic 500 with no
  traceback/body/env. (PRD AC-8; REQ-GUI-005/015.)
- **VCHK-GUI-10 (wired-in-prod via real launcher)** — The headline paste→run→render is
  exercised through the REAL `plumbline-council-gui` launcher start, and a from-wrong-cwd
  start fails loud or resolves (never a plausible all-`character-missing` render). (PRD
  AC-9; REQ-GUI-013/016.)
- **VCHK-GUI-11 (mixed/partial render honesty)** — A partial result (`overall:
  COUNCIL_MODEL_UNAVAILABLE`, some roles OK, some classified) renders the OK positions AND
  the per-role codes — not one error banner, not a fake success. (PRD AC-10; REQ-GUI-017.)
- **VCHK-GUI-12 (LIVE-status / attrition indicator; no demo ever shown)** — A visible
  LIVE-status indicator honestly shows whether a run was a REAL live call and its outcome
  class (real positions / rate-limit / unavailable / attrition / "live required"), so a
  non-answer can never read as a council opinion; and NO demo/injected council is ever shown
  to the operator. (USER PRINCIPLED OVERRIDE, Ben 2026-06-20; PRD AC-11; REQ-GUI-018.)

---

## 7. Explicit non-goals / non-claims (do NOT read as in-scope or proven here)

Consistent with Canvas §7 and the PRD. This slice does NOT build and does NOT claim:

- NO authentication / accounts / multi-user / sessions.
- NO network exposure beyond loopback by default (no `0.0.0.0` bind, no public deploy).
- NO persistence / run history / database.
- NO re-implementation of inference, presets, key handling, capping, the live gate, or
  the diversity check.
- NO new runtime dependency / build step (single self-contained HTML + vanilla JS over
  Python stdlib `http.server`).
- NO fake/demo council as user-facing value (USER PRINCIPLED OVERRIDE, Ben 2026-06-20,
  SUPERSEDES the earlier deferred-live framing): no canned/demo/injected council is ever
  shown to the operator; the `--inject-council` seam survives ONLY as test infrastructure.
- NO silent fake fallback: when live is unavailable (gate OFF, no key, rate-limit,
  unavailable, attrition) the GUI shows an HONEST classified message, never demo positions.
- NO value verdict, and NO claim that distinct model ids prove cognitive diversity.
- NO in-process import of the council — the proxy SHELLS OUT to `deepseek_review.py preset`
  as a child process, with the key only in the child env (spec-sanity decision 1).

---

## 8. Why now

Slices 1–3 built and measured the foreign-model council; the primitive is vetted and
frozen but its reasoning is locked behind CLI/JSON literacy, so it is effectively unused
for the quick exploratory passes it is most valuable for. A thin, safe presentation layer
unlocks that already-built value at near-zero added surface — no new deps, no key exposure,
loopback-only — surfacing the REAL live council (USER PRINCIPLED OVERRIDE, Ben 2026-06-20:
LIVE-ONLY-REAL, no demo). The one real boundary it crosses (the gated live call) is the
honest cost of showing real council reasoning, recorded as a `real-boundary-smoke`; there
is no fake shortcut. That is the cheap, honest next step.

---

## 9. Traceability links

Product Canvas: docs/canvas/openrouter-gui.canvas.md (user-confirmed, Ben 2026-06-20)
PRD: docs/prd/openrouter-gui.prd.md (finalized 2026-06-20; REQ-GUI-001..018)
Traceability Matrix: docs/trace/openrouter-gui.trace.md (stub in PRD; built in Phase 0/0.5)
Reality Ledger (authored Phase 3 / Gate C): docs/reality/openrouter-gui.evidence.jsonl

True-Line status: aligned with the user-confirmed Canvas. Vision status is `user-confirmed`
(Ben, 2026-06-20) — the user confirmed it at the Phase-0 gate. Phase 0 is complete.

---

## 10. User confirmation

This Vision is authored consistent with the user-confirmed Canvas and the finalized PRD,
and is **user-confirmed**: the user confirmed it as the basis for AgileTeam planning at the
Phase-0 Vision gate (via the AskUserQuestion gate, "Bestätigt — weiter zu Spec-Sanity + Build").

```text
I confirm this Product Vision as the basis for AgileTeam planning.
```

Status: user-confirmed
Confirmed by: Ben
Confirmed at: 2026-06-20
Open contradictions: none — consistent with the user-confirmed Canvas (problem, target
user, value proposition, success signal, non-goals, risks) and the finalized PRD
(REQ-GUI-001..018, acceptance criteria, SPLIT evidence-class floor: the live render path
`real-boundary-smoke`, the offline mechanics `integration-fake`). The 2026-06-20 USER
PRINCIPLED OVERRIDE (Ben) — DEMO removed from the product contract; LIVE-ONLY-REAL;
classified "live required" when the gate is OFF / no key; `--inject-council` kept as
test-only infra; evidence floor for the live path RAISED to `real-boundary-smoke`; UI/UX =
role cards + diversity block + LIVE-status/attrition indicator + preset choice + RISK-B-007
— is a user-directed re-scope reconciled across Canvas + PRD + Vision; it enforces the core
"real code or no code" principle and re-opens no decision against the user's own directive,
so this Vision stays user-confirmed. The 2026-06-20 Phase-0.5 spec-sanity remediation
(architecture=subprocess; fail-loud preconditions; MVP-critical leak gate; wired-in-prod;
mixed render; REQ-GUI-005=assertion) remains in force as hardening/clarification; its
"MVP-honesty=injected/demo offline" point is superseded by the override above.
