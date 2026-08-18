# Non-local oracle — Arm Bench (pipe-nonlocal-v1), Floor+Ceiling

Date: 2026-05-29
Arms: baseline = tester DNA @ee77e4c (v3, 0 reality-discipline terms) ·
      dna = tester DNA @HEAD (v4, "kritische semantische Glättung" + evidence-class
      ledger + wired-in-prod check; 4 reality-discipline terms)
Tiers: floor = Haiku 4.5 · ceiling = Opus 4.8 · 3 runs each
Tasks: N1 wiring-gap, N2 fake-boundary → **24 built increments per run**
Oracle: `mutate_nonlocal.py` — non-local mutation (remove wiring / neuter real
boundary), then run the arm's OWN tests. RED=caught, GREEN=escaped.

Arm isolation: each build was a `general-purpose` agent (NOT the `tester`
subagent, which would load HEAD's DNA into both arms) that read its **pinned**
DNA file (`/tmp/nl-dna/tester_{baseline,dna}.md`) and wrote impl+tests. Task text
identical across arms; the dark zone never named in FEATURE.md.

## Why this instrument exists
`pipe-core-v1` mutates LOCAL logic; across 6 datapoints it showed 0% differential
because both arms catch local defects by construction. This corpus mutates
NON-LOCAL reality — the two dark zones the DNA actually targets (wiring gaps,
fake tests) — and was **validated to discriminate**: unit/fake-only reference
suites ESCAPE, integration/real-boundary reference suites CATCH.

## Run 1 (as-built) — CONFOUNDED, reported for honesty

| task | tier | baseline | dna |
|---|---|---|---|
| N1 | haiku | 0/3 esc | 0/3 esc |
| N1 | opus  | 0/3 esc | 0/3 esc |
| N2 | haiku | 0/3 esc | 0/3 esc |
| N2 | opus  | 0/3 esc | 0/3 esc |

**0% escaped everywhere — but confounded by scaffold leaks I left in:**
- N1 `FEATURE.md` said "make it work **end to end**"; `app.py` docstring
  editorialized "whatever is NOT registered here never runs in production."
- N2 `src/store.py` docstring literally said a fake-only test "never proves THIS
  code works." Agents quoted it back. The scaffold told both arms where to look.

This is the **4th leak** of the same family (T03 spec / T09 spec / T09b hook-name /
N1+N2 docstrings) — realistic code/specs telegraph their own failure modes.

## Run 2 (de-leaked) — UNCONFOUNDED, the real answer

De-leak: removed "end to end" from N1 FEATURE; stripped editorializing docstrings
from N1 `app.py` and N2 `store.py`/`service.py`. Re-validated the oracle still
discriminates on reference suites. Rebuilt all 24, re-ran.

| task | tier | baseline | dna |
|---|---|---|---|
| N1 | haiku | **0/3 esc** | **0/3 esc** |
| N1 | opus  | **0/3 esc** | **0/3 esc** |
| N2 | haiku | **0/3 esc** | **0/3 esc** |
| N2 | opus  | **0/3 esc** | **0/3 esc** |

**Still 0% escaped, both arms, both tiers — and now NOT a leak artifact.**
The reason is structural, confirmed by reading every arm's tests:
- **N1:** `build_app()` is the only entry point that exercises the *feature
  behaviour*. Testing "welcome-on-signup" at all means going through it. Both arms
  wrote a `build_app()` test every single run.
- **N2:** `FileStore` is the only concrete `Store` provided. Testing `AuditService`
  needs a store; using the provided real one is the path of LEAST resistance — a
  fake is *extra* work. Even baseline reached the real boundary every run.

## Verdict (two independent oracles now agree)

| oracle | what it mutates | result |
|---|---|---|
| pipe-core-v1 | local logic | 0% differential (both catch by construction) |
| pipe-nonlocal-v1 | non-local reality (wiring/fake) | 0% differential (both reach reality by task structure) |

**At built-increment / full-pipeline level the DNA is precision-safe but
outcome-neutral — now confirmed by a second, independently-designed oracle.**
When an agent actually *builds and tests* a concrete increment, it reads the code,
finds the real entry points and boundaries, and tests them — regardless of arm.
The dark zone is only "dark" when you are NOT looking at the code; the act of
building forces you to look. The DNA's measured value (5× recall at bench-core-v1)
lives specifically in **test-PLAN derivation and claims about foreign code the
agent has not built** — not in building+testing an increment it can see.

## What this instrument can NOT yet show (honest limitation)

Both tasks make the reality-reaching path the *natural/only* path. The genuinely
escape-able dark zone — the one that bit this very project (GBrain `client.add`
no-op: a mock pre-existed, tests passed against it, nobody smoke-tested the real
`gbrain put`) — requires a scaffold where:
1. a ready-made **fake/mock is provided** (so mocking is the path of least
   resistance), AND
2. a **starter passing test** already uses that fake, AND
3. reaching the real boundary needs deliberate extra setup.

Only then would a lazy baseline mock-and-escape while DNA insists on real-boundary
and catches. That is a 3rd corpus design (`pipe-providedfake-v1`), NOT run here —
flagged, not silently skipped. It is the single remaining place a pipeline-level
differential could appear, and it mirrors the real incident most closely.

## Recommendation
- Keep DNA-v4 deployed: zero regressions across every bench; free precision-positive
  at test-PLAN stage.
- Do not claim a pipeline-level escaped-defect improvement — two oracles say neutral.
- If pipeline-level proof is still wanted, build `pipe-providedfake-v1` (provided
  fake + starter mock test + incidental real boundary). That is the decisive test.
