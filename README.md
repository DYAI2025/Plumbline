<div align="center">

# Plumbline

### *Does it hang true?*

**A truth-oriented agent framework for Claude Code that treats green tests as evidence, not as proof of value.**

`86 subagents` · `16 vendored skills` · `11 slash commands` · `/agileteam` governance · `/concilium` council · `Runtime Integrity / Reality Layer` · `benchmarked with explicit evidence ceilings`

Plumbline is built for software work where the expensive failure is not “the test failed.” The expensive failure is: **the test passed, the artifact looked complete, but the real user problem was still not solved.**

**[Live Agent Explorer](https://dyai2025.github.io/Plumbline/)** · inspect the 86 subagents in a browser, no install required.

<br/>

![Plumbline Agent Explorer — searching, filtering and inspecting the colour-coded subagent library](docs/images/explorer-demo.gif)

</div>

---

## What Plumbline is

Plumbline is a local Claude Code framework for agentic software delivery. It combines:

- a governed `/agileteam` workflow,
- a Product Vision / Product Canvas start gate,
- TDD and independent review roles,
- a Plumbline Watcher with pause authority,
- a Runtime Integrity / Reality Layer for evidence checks,
- a multi-model `/concilium` council path,
- experiment logs and benchmark write-ups that preserve null results and failures.

The core question is always the same:

> **Does this work hang true against the only reference that matters: the real problem the user wanted solved?**

A test suite can prove that code follows an expected behavior. It cannot, by itself, prove that the expected behavior is worth shipping. Plumbline exists to hold that gap open long enough for the system to notice it.

---

## The real problem Plumbline addresses

Most agent frameworks can generate plans, tasks, tests, and code. That is no longer the hard part. The hard part is preventing agentic systems from optimizing for local completion signals:

- all tasks checked off,
- all tests green,
- all documents generated,
- all agents agreeing,
- no obvious runtime error,
- no one pausing the process.

Those signals are useful, but they are not the same as customer value. If the system optimizes only for green tests, the maximum value it can reliably produce is **green tests**. That may still leave the user with an unsolved problem.

Plumbline's advantage is its rigorous truth orientation: every important completion claim must name its evidence class, its missing boundary, and its honest ceiling. Combined with continuous learning, this creates a compounding benefit: the framework does not only complete work; it records where its own process confused “looks done” with “is done,” then tightens the next run under guardrails.

This is valuable because software products fail less often from a missing checklist item than from a semantic gap: the team built a correct artifact for the wrong interpretation of the problem.

---

## Key features

| Feature | What it means | Honest status |
|---|---|---|
| **True-Line Governance** | Product Vision and Product Canvas alignment are treated as first-class gates. Requirements must stay linked to the confirmed user problem, value promise, success signal, non-goals, and risks. | Partly machine-backed, partly model-judgment. Human confirmation remains final. |
| **Runtime Integrity / Reality Layer** | PRIL-style checks for reality evidence, context artifacts, scope containment, run ledgers, redaction, and fail-closed hook behavior. | The narrow PRIL core has executable tests and CLIs; not every governance rule is mechanically enforced. |
| **Plumbline Watcher** | Independent value gate that can return `pass`, `review-required`, `pause`, or `blocked`. It may pause when tests are green but value remains unproven or contradicted. | Watcher judgment is model-mediated. Benchmarks show specific real cases, not universal correctness. |
| **Multi-model Council** | `/concilium` can stress-test ideas through market, technical, skeptical, distribution, and character-based lenses. OpenRouter-backed foreign-model paths exist for real boundary crossings. | Capability smokes exist. Council quality lift is not proven; underpowered runs are reported as underpowered. |
| **Reality Ledger** | Requirements and claims carry evidence classes such as fake/mock, integration, real-boundary-smoke, or stronger observed evidence. Fake-only evidence cannot silently become “done.” | Useful for preventing evidence laundering; only as strong as the recorded artifacts and invoked gates. |
| **Continuous Learning** | Retrospectives can become persistent rules only through guarded persistence, diff preview, tests, and explicit approval. | Designed to reduce repeated process errors without blind self-modification. |
| **Honest update/install boundary** | Plumbline installs through scripts and local Claude Code config. It is not a Claude Code plugin and ships no MCP server. | See [`DEPENDENCIES.md`](DEPENDENCIES.md). |

---

## Space between impulse and action in a frontier model

One recent design insight is that the real leverage point is the small space between a model's impulse and the system's action.

A frontier model can produce a plausible next step very quickly: plan, write code, mark done, proceed, merge. Plumbline inserts governed friction into that gap:

1. **Impulse:** the model wants to continue because the local signal is green.
2. **Check:** the framework asks what the action is true *against*: Product Vision, Canvas, traceability, reality evidence, scope, risk, non-goals.
3. **Pause option:** the Watcher or hook may stop the process before the next action leaves the model and changes the project.
4. **Human authority:** if the gap is semantic or value-based, the user decides. The model may recommend; it may not silently redefine value.

This is not “slowing the model down” for ceremony. It is using the moment before action as a control surface. That moment is where an agentic system can still choose truth over momentum.

---

## Typical use case: green tests, no real value

A team starts a larger software initiative with good discipline: Product Vision, PRD, traceability, TDD, implementation, review, security, validation. The tests are green.

But the increment has a hidden semantic failure: it satisfies the written test while violating the confirmed product meaning. For example, the Product Canvas says tracking must not become surveillance, but the implemented “analytics improvement” quietly ships behavior the Canvas named a non-goal.

In a normal green-test pipeline, the work may proceed because the local evidence says “pass.” In Plumbline, the Watcher can stop the process anyway:

```text
Tests: green
Implementation: present
Local acceptance criteria: satisfied
True-Line check: contradiction with confirmed Canvas non-goal
Watcher verdict: pause
Required decision: user must confirm reframe, remove the conflicting requirement, or change implementation
```

The point is not that tests are unimportant. The point is that tests are not gravity. The real solved problem is gravity. If the code does not solve the practical problem, the work does not hang true — even if every test is green.

---

## Latest evidence in this repository

| Date | Evidence artifact | What it supports | What it does **not** prove |
|---|---|---|---|
| 2026-06-13 | [`docs/benchmarks/2026-06-13-true-line-live-validation.md`](docs/benchmarks/2026-06-13-true-line-live-validation.md) | Watcher caught a planted green-but-untrue value contradiction in the tested setup. | Does not prove full `/agileteam` orchestration wiring or subtle-case perfection. |
| 2026-06-18 | [`docs/benchmarks/2026-06-18-runtime-start-governance.md`](docs/benchmarks/2026-06-18-runtime-start-governance.md) | A PreToolUse hook can deny planning/coding under `VISION_MISSING` at the runtime boundary. | Does not prove the model-level `/agileteam` command always obeys its own prose. |
| 2026-06-18 | [`docs/benchmarks/2026-06-18-openrouter-council-backend-smoke.md`](docs/benchmarks/2026-06-18-openrouter-council-backend-smoke.md) | OpenRouter catalog reachability and normalized-base diversity gate crossed a real boundary. | Reachability is not invocability; distinct IDs are not deep cognitive diversity. |
| 2026-06-19 | [`docs/benchmarks/2026-06-19-openrouter-inference-smoke.md`](docs/benchmarks/2026-06-19-openrouter-inference-smoke.md) | One free OpenRouter model completed a real inference call; unavailable models are classified, not faked. | Does not generalize invocability or token-estimate accuracy across models. |
| 2026-06-19 | [`docs/benchmarks/2026-06-19-deepseek-review-smoke.md`](docs/benchmarks/2026-06-19-deepseek-review-smoke.md) | A character/preset council path produced at least one real foreign-model position and classified failures. | Does not prove council quality lift. |
| 2026-06-20 | [`docs/benchmarks/2026-06-20-openrouter-gui-live-smoke.md`](docs/benchmarks/2026-06-20-openrouter-gui-live-smoke.md) | The GUI served path can cross the live OpenRouter boundary without demo fallback and without key leakage. | It is a wiring smoke, not a usability or value verdict. |
| 2026-06-20 | [`docs/benchmarks/2026-06-20-free-diversity-probe.md`](docs/benchmarks/2026-06-20-free-diversity-probe.md) | A free-only diversity probe ran end to end and exposed a likely noise/cry-wolf risk. | It was underpowered and not a Claude-vs-council verdict. |
| 2026-06-20 | [`docs/benchmarks/2026-06-20-free-model-preference-refresh.md`](docs/benchmarks/2026-06-20-free-model-preference-refresh.md) | The free-model preference list was refreshed against the live catalog, improving reachability in that run. | Free-tier availability remains intermittent. |
| 2026-06-21 | [`CHANGELOG.md`](CHANGELOG.md) | Latest release entries include `/openrouter-live-smoke` and `/persist-learning`. | Changelog entries are project records, not independent runtime proof. |

Plumbline's README intentionally separates capability, evidence, and value. A live smoke proves that a path can cross a boundary. It does not prove that the resulting council, model, or workflow is better in general.

---

## Quickstart

**Requirements:** Claude Code, `git`, `bash`, `python3`, and `jq`.

```bash
git clone https://github.com/DYAI2025/Plumbline plumbline
cd plumbline
./config/claude/install.sh
```

Then, inside a Claude Code project:

```bash
/agileteam "add OAuth2 login with refresh-token rotation"
```

Useful commands:

```bash
plumbline doctor
plumbline update --check
plumbline update
bash config/claude/tests/run_all.sh
```

Installation boundary:

- Plumbline is installed through `install.sh` / `plumbline install` style local setup.
- It is **not** a Claude Code plugin.
- It ships no MCP server.
- Some vendored agents reference external MCP tools; those are referenced-but-not-shipped unless installed separately. Vendored agents are treated as a tested-workload dependency, not as individually benchmarked Plumbline-native team members.
- Plain install is lean by default; MCP-coupled flow agents are omitted unless explicitly requested with `--with-flow-agents`.

See [`SETUP.md`](SETUP.md) and [`DEPENDENCIES.md`](DEPENDENCIES.md).

---

## `/agileteam` governance flow

`/agileteam <feature>` is not just a coder dispatcher. It is a governed product-building flow:

0. **Product Vision / Canvas gate** — confirm target user, real problem, value promise, non-goals, risks, and success signal.
1. **Requirements** — produce PRD, REQ IDs, acceptance criteria, and traceability.
2. **Challenge / sanity pass** — test for weak requirements, false assumptions, and better approaches.
3. **Planning** — architecture and atomic tasks.
4. **TDD loop** — failing test first, minimal implementation second.
5. **Independent review** — reviewer sees artifacts and diff, not the coder's private reasoning.
6. **Security and dependency review** — secrets, dependency, threat, and injection checks where applicable.
7. **Validation** — requirements checked against evidence and traceability.
8. **Watcher / True-Line gate** — asks whether the increment still serves confirmed customer value.
9. **Human acceptance** — semantic reframes and final acceptance stay human-owned.
10. **Retro / learning loop** — process learnings can persist only under guardrails.

The framework deliberately distinguishes:

- **test-green**: code passed available tests,
- **evidence-green**: the relevant boundary was actually checked,
- **true-green**: the work still serves the confirmed customer value.

---

## `/concilium` and the multi-model council

`/concilium` stress-tests a product idea or team setup through independent bodies such as Market Realist, Tech Arbiter, Skeptic, and Distribution Realist. The goal is not consensus theater. The goal is useful friction before committing to a build.

Recent OpenRouter work adds a governed path for foreign-model and character-based council runs:

- key-safe live inference primitives,
- reachability and invocability distinction,
- normalized-base diversity gates,
- typed character/preset runners,
- GUI runner with no fake demo fallback,
- underpowered measurement runs reported as underpowered.

The honest conclusion is narrower than the marketing version would be:

> Plumbline has a real multi-model council capability path and real-boundary smokes. It has **not** proven that the council is generally better than a Claude-only baseline. The current evidence shows both potential and noise risk.

---

## Reality Layer: evidence classes

Plumbline uses evidence classes to prevent laundering weak proof into strong claims.

Examples:

| Evidence class | Meaning |
|---|---|
| `fake-only` / `mock-only` | Useful during development, not enough for completion where real behavior matters. |
| `integration-fake` | Components are wired through test doubles or injected seams. Better than prose, still not reality. |
| `real-boundary-smoke` | A real external/runtime boundary was crossed once or narrowly. Stronger, but still not broad proof. |
| `production-observed` | Behavior observed in the actual production-like or production context. Stronger than source inspection. |
| `user-confirmed` | The user explicitly confirmed semantic or product meaning. Required for value reframes. |

A claim must not be raised above the evidence it actually has. That rule is the practical meaning of “truth orientation” in this repository.

---

## What's inside

| Area | Purpose |
|---|---|
| `core/` | Base roles such as coder, planner, researcher, reviewer, tester. |
| `agileteam/` | Product-governed workflow roles: requirements, Product Owner, Watcher, security, spec audit, context. |
| `concilium/` | Council bodies, reports, and character-based critique structures. |
| `config/claude/commands/` | Slash commands: `/agileteam`, `/concilium`, `/honest-status`, `/bench-oracle`, `/merge-when-true`, `/openrouter-live-smoke`, `/persist-learning`, and reflection/update commands. |
| `config/claude/lib/` | Runtime integrity, council, update, scope, context, redaction, and run-ledger libraries. |
| `config/claude/tests/` | Shell/Python regression checks for commands, gates, update layer, council paths, GUI, and docs honesty. |
| `config/claude/skills/` | 16 vendored skills for portable workflows. |
| `docs/benchmarks/` | Captured benchmark and live-smoke write-ups with evidence ceilings. |
| `docs/reality/` | Reality-ledger evidence JSONL files. |
| `metrics/` | Corpus, runs, measurement tools, and experiment artifacts. |
| `explorer/` | Source for the visual Agent Explorer. |

Browse the full agent set in the **Agent Explorer**.

---

## Quality assurance

Run the local suite:

```bash
bash config/claude/tests/run_all.sh
```

The suite validates frontmatter, metrics contracts, settings, hooks, update-layer safety, README honesty, dependency disclosure, council logic, GUI proxy paths, runtime start governance, and related guardrails. Some live-boundary checks are intentionally outside the default suite and require explicit live gates or credentials; offline tests must not pretend to have crossed live boundaries.

---

## Design principles

- **Truth over throughput** — finishing faster is not progress if the result is untrue to the user problem.
- **Evidence over vibes** — every claim needs an artifact, test, trace, boundary smoke, or explicit assumption.
- **Green tests are not gravity** — they matter, but they are not the final reference for product value.
- **Human value is not self-confirmed by agents** — the user confirms semantic reframes and product meaning.
- **Diversity must be earned** — multiple prompts on one model are not automatically independent cognition.
- **No fake fallback** — if a live boundary fails, the framework reports the failure instead of substituting a demo.
- **Continuous learning stays governed** — learnings persist only with review, diff visibility, and tests.

---

## License & attribution

[MIT](LICENSE) © 2026 DYAI2025.

The agent base is derived in part from **Claude Flow** by [`ruvnet`](https://github.com/ruvnet/) (MIT, © ruvnet). The repo path [`ruvnet/claude-flow`](https://github.com/ruvnet/claude-flow) now points to [`ruvnet/ruflo`](https://github.com/ruvnet/ruflo). Keep this attribution and the MIT notice when redistributing forks or major rewrites.

<div align="center">

---

**Plumbline** — for teams that do not want agentic software to merely look complete. They want it to hang true.

`#AIEngineering` `#AgentOrchestration` `#AgenticWorkflow` `#ClaudeCode` `#SoftwareGovernance` `#TDD` `#LLMOps`

</div>
