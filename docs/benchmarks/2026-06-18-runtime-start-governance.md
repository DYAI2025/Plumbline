# Runtime Start Governance — Behavioral Real-Boundary Trace (2026-06-18)

REQ-A-001..011 · AC-A-001..006 · EV-A-001/002/004/005 · BL-002 / BL-003.
Branch `agileteam/runtime-start-governance`. This is a **real captured run** (not a
fabricated snapshot): every block below is verbatim stdout/exit-code from executing the
shipped artifacts. Reproduce with the commands shown.

Provenance: commit `1a6a260` (pre-commit working tree of this slice), branch
`agileteam/runtime-start-governance`, hook
`sha256:327503475ef2b8d360053496764f782df449ac1a9f0af22099251c06a901b6a2`.

## Evidence-class map (honest, per layer)

| Layer | Artifact | What it proves | Evidence class |
|---|---|---|---|
| Classifier verdict | `plumbline-start-check` | the deterministic VISION_MISSING verdict the gate consumes | real-boundary-smoke (real process run) |
| **Harness backstop** | `hooks/pretool-vision-gate.sh` (PreToolUse) | a real planning/coding **dispatch is DENIED** at the harness process boundary → planning is not entered | **real-boundary-smoke** |
| Command-gate halt | `commands/agileteam.md` Phase-0 gate | the orchestrator instruction to halt before planning exists and names the executable | **integration-fake** (proves the instruction exists, not that a live model obeyed it) |

The **load-bearing guarantee is the hook layer**. The command-gate is the orchestration/UX
layer and is honestly integration-fake on its own — it is **not** silently upgraded by the
hook's stronger evidence (no laundering). See "Honest ceilings" below.

## 1 — Classifier verdict (the input the gate consumes) — real

```
$ config/claude/bin/plumbline-start-check --prd-present --vision-missing
PLUMBLINE START STATUS
Phase: VISION_INTAKE
Gate: VISION_MISSING
Planning allowed: NO
Coding allowed: NO
Missing:
- confirmed Product Vision Canvas
Next allowed step:
- Run Vision Extraction and request explicit user confirmation.
```

## 2 — PreToolUse backstop DENIES a real planning dispatch (path-1, marker) — real-boundary-smoke

```
# project state: docs/context/.start-gate = "VISION_MISSING"
$ stdin: {"tool_name":"Task","tool_input":{"subagent_type":"planner","description":"plan the feature"}}
$ CLAUDE_PROJECT_DIR=<repo> bash config/claude/hooks/pretool-vision-gate.sh
stdout: {"decision":"deny","reason":"Plumbline start gate: VISION_MISSING — confirmed Product Vision required before planning/coding. Run Vision Extraction and request explicit user confirmation."}
exit:   0
```

The dispatch is **denied at the PreToolUse boundary** — the planner **did not enter planning**.
This is the HALT-before-planning, enforced by the harness, not by model goodwill.

## 3 — Backstop DENIES a real coding (Write) dispatch — real-boundary-smoke

```
$ stdin: {"tool_name":"Write","tool_input":{"file_path":"src/feature.py","content":"x=1"}}
stdout: {"decision":"deny","reason":"Plumbline start gate: VISION_MISSING — confirmed Product Vision required before planning/coding. Run Vision Extraction and request explicit user confirmation."}
exit:   0
```

## 4 — Independent recompute (path-2) denies with NO marker — real-boundary-smoke

Defense-in-depth: even with no `.start-gate` marker, the hook recomputes from real artifacts
(`.active-feature` + PRD present + Product Vision not `user-confirmed`) by reusing the
classifier, and still denies — so the backstop holds even if the command-gate never ran.

```
# project state: .active-feature=demo-feature, docs/prd/demo-feature.prd.md present,
#                 docs/vision/demo-feature.vision.md Status: draft (NOT user-confirmed),
#                 NO docs/context/.start-gate
$ stdin: {"tool_name":"Task","tool_input":{"subagent_type":"coder","description":"implement"}}
stdout: {"decision":"deny","reason":"Plumbline start gate: VISION_MISSING — confirmed Product Vision required before planning/coding. Run Vision Extraction and request explicit user confirmation."}
exit:   0
```

## 5 — Targeted, not a blanket session-kill — real

```
# read-only dispatch under VISION_MISSING:
$ stdin: {"tool_name":"Read","tool_input":{"file_path":"docs/prd/x.md"}}
stdout: (empty)   exit: 0   → PASS THROUGH

# planning dispatch in a normal repo (no gate state):
$ stdin: {"tool_name":"Task","tool_input":{"subagent_type":"planner","description":"plan"}}
stdout: (empty)   exit: 0   → PASS THROUGH
```

The gate is fail-CLOSED for planning/coding under VISION_MISSING and fail-OPEN otherwise, so
normal sessions (and the Vision-Extraction work itself) are never bricked.

## Honest ceilings & coverage boundaries (not laundered)

- **Command-gate halt = integration-fake.** A live `/agileteam` model actually stopping its
  own control flow before planning is **not** machine-assertable from outside the model; the
  runtime exposes no scriptable hook into the orchestrator's control flow to prove "planning
  was not entered" by the model. The command-gate edit in `agileteam.md` proves the binding
  instruction exists; it does not prove live obedience. The hook layer (sections 2–4) is what
  carries the hard real-boundary guarantee.
- **`Bash` tool is outside this backstop by design.** The PreToolUse matcher and the hook's
  affected-tool set cover `Task`(planning/coding roles)/`Write`/`Edit`/`MultiEdit`/
  `NotebookEdit`. A shell-mediated file write via the `Bash` tool under VISION_MISSING is
  **not** denied by this hook. This is the documented scope of REQ-A-011; the orchestrator
  Phase-0 gate is the broader control. Recorded here so it is visible, not assumed-covered.

## Closure note (F3)

The HALT-before-planning guarantee reaches **real-boundary-smoke** at the hook layer
(sections 2–4: real dispatches denied at the harness boundary). The command-gate portion
remains **integration-fake** and is reported as **PASS(tests)/RED(confidence)** for the
live-model halt claim. Per F3 this RED may not be silently downgraded; only the user may
reclassify it at the acceptance gate.
