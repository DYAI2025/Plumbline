# SMK-004 · Runtime start-governance (HALT-before-planning hook)

**ID:** SMK-004 · **Date:** 2026-06-18 · **Kind:** Real-boundary smoke (harness hook) ·
**Status:** complete. · Branch `agileteam/runtime-start-governance`.
REQ-A-001..011 · AC-A-001..006 · BL-002 / BL-003.

> **Correction 2026-09-01:** the `{"decision":"deny", …}` results below are rejected by the
> Claude Code 2.1.252 PreToolUse hook-output validator; they prove the hook process emitted a
> deny-shaped object, not that the harness honoured it. "Real-boundary smoke" here reads with
> that ceiling — see the dated correction at the end of this file.

A capability proof: does the PreToolUse hook *actually* deny a real planning/coding dispatch
under `VISION_MISSING`, or does only the orchestrator instruction exist? Every block in the
source is verbatim stdout/exit-code from executing the shipped artifacts. Provenance: commit
`1a6a260`, hook `sha256:327503475e…b6a2`.

## What it set out to prove

The HALT-before-planning guarantee (BL-002/003): when a PRD is present but the Product Vision
is not user-confirmed, planning and coding must be *blocked at the harness boundary*, not just
discouraged in prose.

## Method (real captured runs)

Real PreToolUse dispatches were piped to `config/claude/hooks/pretool-vision-gate.sh` with the
project in `VISION_MISSING` state, and the deterministic classifier
(`config/claude/bin/plumbline-start-check`) was run directly. Two detection paths were
exercised: path-1 (the `.start-gate` marker) and path-2 (independent recompute from real
artifacts with **no** marker).

## Results (as captured — verbatim)

| Layer | Artifact | What it proves | Evidence class |
|---|---|---|---|
| Classifier verdict | `plumbline-start-check` | the deterministic `VISION_MISSING` verdict the gate consumes | real-boundary-smoke (real process run) |
| **Harness backstop** | `hooks/pretool-vision-gate.sh` | a real planning/coding **dispatch is DENIED** at the harness boundary → planning not entered | **real-boundary-smoke** |
| Command-gate halt | `commands/agileteam.md` Phase-0 gate | the orchestrator instruction exists and names the executable | **integration-fake** (instruction exists, not that a live model obeyed) |

- A `Task`(planner) dispatch under `VISION_MISSING` → `{"decision":"deny", …}`, exit 0 — the
  planner did not enter planning.
- A `Write` dispatch → same `deny`.
- Path-2: with **no** `.start-gate` marker, the hook recomputed from `.active-feature` + PRD
  present + Vision not `user-confirmed` and still denied — backstop holds even if the
  command-gate never ran.
- Targeted, not a blanket session-kill: a read-only `Read` dispatch and a planning dispatch in
  a normal repo both **pass through** (empty stdout, exit 0). Fail-CLOSED for planning/coding
  under `VISION_MISSING`, fail-OPEN otherwise.

## What it proved / what it did NOT prove (honest ceilings, not laundered)

**Proved (real-boundary-smoke):** the hook denies real planning/coding dispatches at the
harness process boundary, via both detection paths, while passing through read-only and
normal-repo dispatches.

**Did NOT prove / RED:**
- **Command-gate halt = integration-fake.** A live `/agileteam` model actually stopping its own
  control flow before planning is **not** machine-assertable from outside the model; the runtime
  exposes no scriptable hook into the orchestrator's control flow. The command-gate edit proves
  the binding instruction exists, **not** live obedience. Reported as
  **PASS(tests)/RED(confidence)** for the live-model halt claim; per F3 this RED may not be
  silently downgraded — only the user reclassifies at acceptance.
- **The `Bash` tool is outside this backstop by design.** A shell-mediated file write via `Bash`
  under `VISION_MISSING` is **not** denied by this hook (documented scope of REQ-A-011); the
  orchestrator Phase-0 gate is the broader control. Recorded so it is visible, not
  assumed-covered.

The load-bearing guarantee is the hook layer; the command-gate is the orchestration/UX layer
and is **not** upgraded by the hook's stronger evidence (no laundering).

## Evidence class

`real-boundary-smoke` at the hook layer (real dispatches denied at the harness boundary).
Command-gate halt stays `integration-fake`. `Bash`-tool path explicitly out of scope.

## Source artifacts (read before writing)

- [`docs/benchmarks/2026-06-18-runtime-start-governance.md`](../benchmarks/2026-06-18-runtime-start-governance.md)
  — all verbatim captures and the evidence-class map traced here.
- Artifacts under test: `config/claude/hooks/pretool-vision-gate.sh`,
  `config/claude/bin/plumbline-start-check`, `config/claude/commands/agileteam.md` (Phase-0).
</content>

## Correction 2026-09-01 — hook-output protocol (evidence ceiling)

Under Claude Code 2.1.252, top-level `decision:"deny"` is rejected by the PreToolUse
hook-output validator and therefore cannot be used as current-version enforcement evidence.
Current valid permission denial uses `hookSpecificOutput.permissionDecision:"deny"`. The
`{"decision":"deny", …}` results above prove the hook process emitted a deny-shaped legacy
object, not that the harness honoured it; the Claude Code version of the original run is not recorded, so this
evidence is version-bound / insufficient for current-version enforcement. The "Harness
backstop → real-boundary-smoke" row reads with that ceiling. Whether the original run was
fail-open at the time is not established here.
