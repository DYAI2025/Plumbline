# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this repo is

**Plumbline** — a defense-in-depth Claude Code agent framework whose one obsession is
proving work is *actually* done, not that it merely *looks* done. It is three things in
one repo, and editing one usually means touching another:

1. **An agent collection** — ~87 subagent prompt files (`*.md` with YAML frontmatter)
   organized into category directories (`core/`, `agileteam/`, `github/`, `consensus/`,
   `sparc/`, `swarm/`, `hive-mind/`, `concilium/`, …). These are the deliverable.
2. **A vendored workflow + tooling tree** under `config/claude/` — the `/agileteam`
   orchestrator, `/concilium` council, vendored skills, hooks, the runtime-integrity
   layer (PRIL), and the metrics harness. This is what makes the agents *portable* and
   *governed*.
3. **An empirical instrument** — `metrics/` holds deterministic mutation-oracle corpora
   and the honest write-ups. The framework's central claims (e.g. "reaching the real
   test boundary is governed by model capability, not prompt cleverness") are *measured*
   here, not asserted. Preserve that intellectual honesty: never downgrade a RED result
   or fabricate a passing one — mark missing tooling `MISSING`.

Read `README.md` for the philosophy and `SETUP.md` for portability/web-bootstrap.

## Common commands

```bash
# Full CI check suite (frontmatter, metrics scripts, settings JSON, hooks,
# governance + PRIL tests, shellcheck). This is exactly what .github/workflows/ci.yml runs.
bash config/claude/tests/run_all.sh

# Run a single test module (each is a standalone bash script):
bash config/claude/tests/test_stop_hook.sh
bash config/claude/tests/test_true_line_governance.sh
bash config/claude/tests/test_product_canvas_gate.sh
bash config/claude/tests/test_runtime_integrity_layer.sh
bash config/claude/tests/test_web_bootstrap.sh

# Rebuild the Agent Explorer after ANY agent frontmatter change.
# Re-extracts frontmatter → bundles a single self-contained agent-explorer.html
# AND syncs docs/index.html (the GitHub Pages live demo) — they must never drift.
./build-explorer.sh            # needs python3+PyYAML, pnpm/node, artifacts-builder skill

# Install onto a machine: symlink repo → ~/.claude/agents, install commands/skills,
# and idempotently register the learning-loop Stop hook in ~/.claude/settings.json.
./config/claude/install.sh           # or: --copy  (Windows / prefer copies over symlinks)

# Benchmark harness (metrics/):
python3 config/claude/metrics/emit_run.py --corpus-id <id> --mode <core|full> \
  --metrics '{...}' --gate-outcomes '{...}' --human-overrides 0   # append a run to runs.jsonl
python3 config/claude/metrics/process_health.py                   # SPC + drift attribution

# PRIL runtime-integrity checks (bash wrappers over config/claude/lib/*.py):
config/claude/bin/plumbline-reality-check   # evidence-class / wired-in-prod gate
config/claude/bin/plumbline-scope-check
config/claude/bin/plumbline-context-check
config/claude/bin/plumbline-redact          # strip secrets/private data from output
```

Requirements: `git`, `bash`, `python3` (+ `PyYAML` for the explorer/validators), and
`jq` (for hook registration). CI also installs `shellcheck`.

## Agent frontmatter contract

Every agent is a markdown file beginning with a `---` YAML frontmatter block. The CI
validator (inside `run_all.sh`) enforces, across all `**/*.md` except `explorer/`:
- frontmatter parses as a YAML mapping,
- a `description:` key is present,
- `name:` values are **globally unique** (no duplicates across the whole tree).

Typical keys: `name`, `description`, `model` (usually `inherit`), `type`, `color`,
`capabilities`, `priority`, `hooks`. **Note:** per-agent `model:` frontmatter is *not*
applied by the current Claude Code runtime — only an explicit dispatch parameter takes
effect, so model control lives in the orchestrator, transparently. After editing any
agent, run `build-explorer.sh` and the frontmatter validator before committing.

**Resolving whether an agent exists — quote-aware, by `name:` not filename.** Agent files
are named by topic, not by their `name:` value (e.g. `name: "backend-dev"` lives in
`development/backend/dev-backend-api.md`), and `name:` is often YAML-quoted. `find -name
"<role>.md"` and `grep '^name: <role>$'` both miss these — resolve with a quote-aware scan
(`grep -rlE '^name: *"?<role>"?[[:space:]]*$' --include='*.md'`) before claiming an agent
is absent.

## Core invariants (don't violate these)

- **True-Line governance** — Plumbline optimizes for staying true to confirmed human
  customer value, not for *finishing*. Green tests, completed tasks, and agent consensus
  are never sufficient on their own.
- **Reality Ledger** — every requirement carries an evidence class
  (`unit-fake → integration-fake → real-boundary-smoke → production-verified`). Anything
  touching I/O, a remote, an external API, or UI that stays `*-fake` is **RED regardless
  of green tests**, and that RED cannot be silently downgraded.
- **Wired-in-prod** — a real implementation with no test through the production
  composition root is *not satisfiable*. (This is the original incident the whole repo
  exists to prevent: "exists in tests, never composed in prod.")
- **Independence** — whoever writes code does not review it; whoever derives tests does
  not implement them. Review/security/validation must not echo the coder's reasoning.
- **Human gates stay** — requirements confirmation, the Product Canvas, product
  judgment, and persistent self-improvement always require explicit human sign-off.

## `/agileteam` command

`/agileteam <feature>` orchestrates an autonomous TDD team: Product Canvas gate →
requirements → spec-sanity audit → planning → coder/reviewer TDD loop → security →
validation → product-judgment → human acceptance → retrospective. Canonical source:
**`config/claude/commands/agileteam.md`** (other commands in that dir:
`agileteam-bench`, `concilium`, `honest-status`, `bench-oracle`, `reflect`,
`reflect-skills`, `plumbline-update`, `merge-when-true`).

**Bootstrap:** the command must exist at `~/.claude/commands/agileteam.md` to be
invokable. If it is missing, offer to run `./config/claude/install.sh`. Keep the global
copy and the vendored copy in sync (or use the symlink so there is a single source).

`metrics/runs.jsonl` is meant to accumulate on the `agileteam-improved` branch; `main`
stays the frozen baseline. A valid `/agileteam-bench` comparison must pin the agent
snapshot (a commit/tag) across both arms, since agent files keep evolving on `main`.

## Agent Learning Loop

Spec: **`config/claude/skills/agent-learning-loop.json`**. Run at the end of an
`/agileteam` session (after the DoD gate) or before ending any session with substantial
implementation/review work.

**Trigger (real):** a sentinel-gated **Stop hook**
(`config/claude/hooks/stop-learning-loop.sh`, registered in `~/.claude/settings.json` by
`install.sh`). It only fires when `~/.claude/.agileteam-reflection-pending` exists
(created by `/agileteam` Phase 3 after the DoD clear), so normal sessions are never
interrupted. It returns `decision: block`, runs the loop, then removes the sentinel, and
honours `stop_hook_active` (no infinite loops). Note: this repo's own
`.claude/settings.json` registers only a **SessionStart** hook
(`config/claude/hooks/session-start.sh`); the Stop hook lives in the *global* settings.

The loop: (1) analyse the session (git diff, test/QA failures, recurring `code-reviewer`
findings, repeated coder↔reviewer iterations); (2) derive concrete recurring failure
patterns → one proposed process rule each; (3) **interactive gate — never write
blindly**, show each proposed rule and its target level and only write on explicit `y`;
(4) persist approved rules with `skill-creator` (+ `writing-skills`) at the **narrowest
fitting level**:
- **A · Local** → this project's `CLAUDE.md`.
- **B · Global agents** → the relevant `~/.claude/agents/<agent>.md`. Show the exact diff
  first; re-run `./build-explorer.sh` afterwards.
- **C · New skill** → `~/.claude/skills/<name>/SKILL.md`, only for a genuinely new
  reusable capability.

Prefer A over B over C; always preview diffs before writing shared/global config.

## Working-in-this-repo protocol

- Use `/agileteam` (or its phased workflow) for feature/bugfix work; TDD first, **no
  production code before a failing test**; frequent atomic commits; no placeholder code.
- This is a **nested git repo** (the parent home repo ignores `.claude/`). Don't stash,
  switch branches, or touch worktrees unless asked — this workspace is multi-agent.
- After editing agents: rebuild the explorer, run the frontmatter validator, and run
  `bash config/claude/tests/run_all.sh` before committing.
- Evidence over vibes: back claims with code/tests/logs or an explicit assumption; mark
  absent tooling `MISSING` rather than pretending it passes.
- **Landing an additive doc run_all-green has two tripwires.** A new `docs/**.md` is the
  safe way to ship a disclosure/finding, but: (a) start it with a plain `#` heading and
  **no `---` frontmatter**, or the frontmatter validator (`run_all.sh`, globs `**/*.md`)
  demands `name`/`description`; (b) do **not** quote a `mcp__<family>__` literal whose
  family isn't already in `DEPENDENCIES.md`, or `test_dependencies_doc.sh` reddens the
  suite — refer to MCP tools in prose instead.

## Process guidelines (learned — bench, release, merge safety)

Hard-won rules from the v0.10 milestone — each from a real incident this repo hit. Binding for benchmark/eval runs and release work here.

- **Benchmark/eval isolation — never run builder agents in-tree.** A full-pipeline bench whose `coder`/builder sub-agents have file tools + the repo cwd *will* pollute the tree: ours wrote real files into `metrics/corpus/**`, and its staged arm-prompt copies tripped the frontmatter validator's duplicate-`name:` scan (it globs `**/*.md`) — turning `run_all.sh` **RED, twice**. So: (a) **stage all bench inputs OUTSIDE the repo** (`/tmp/…` or a dedicated worktree), never in a tracked dir; (b) **hard-constrain builder agents to TEXT-ONLY output** ("respond with code as text; do NOT Write/Edit/Bash any files"); (c) **after every bench run, verify `git status` is clean and `run_all.sh` is green**, and revert any stray files before continuing.
- **No hardcoded version numbers in tests/fixtures — read `VERSION` dynamically.** Tests that pinned the release-please-managed version broke the instant the repo released past their literal (`expected '0.9.0', got '0.10.0'`; a fixture "latest" of `v0.10.0` that the repo caught up to). A hardcoded version in a test is a time-bomb that fails on the next release. Instead: read the version from `VERSION` at runtime (or assert *consistency* — CLI/manifest must match `VERSION`); synthesize any "newer" fixture relative to the current version (e.g. minor+1) so the suite survives every bump.
- **Verify the CI conclusion before merging — `mergeable`/`CLEAN` ≠ tested.** A release PR merged on `mergeable=CLEAN` landed version-hardcoded test failures on `main` (briefly RED). `status=CLEAN`/`mergeable=MERGEABLE` only means "no *failing required* check" — and a release-please branch pushed by `GITHUB_TOKEN` gets **no CI run at all** (GitHub suppresses workflow-triggered workflows). So before merging to a shared branch: confirm the actual `ci` workflow conclusion is `success`; if the branch has no CI run, **run `run_all.sh` on the branch locally first**. Never merge to `main` on `mergeable` alone.
- **Use release-please-recognized commit types so work is never invisible in the changelog.** The v0.11.0 release silently dropped its security hardening from `CHANGELOG.md` because the commits used a non-standard `harden:` type that release-please maps to no section — the user-facing release looked like it shipped only features, hiding the verifyCommand/zip-slip/SSRF fixes. So: for anything that should appear in the changelog, use a recognized Conventional-Commits type — **`fix:` (or `feat:` with a security scope, e.g. `feat(security):`) for security hardening**, not ad-hoc verbs. Reserve `chore:`/`docs:`/`test:` for changes you deliberately want to keep *out* of the release notes (and remember `fix:`/`feat:` will trigger a release-please version bump).
- **No brittle exact counts in honesty/disclosure docs — prefer `~approximate` or derive them.** The gate-enforcement audit hardcoded `63`/`117` `has()` counts; an independent fidelity review found the real figures were `61`/`115`/`117` — they differ *purely by counting method* (`grep` line-anchored vs. anywhere). An exact integer that's contestable is *less* honest than an explicit `~`. So in docs that make a counted claim, use an approximate figure (or one a test re-derives), and reserve exact counts for values something machine-verifies. (The no-hardcoded-version rule above, applied to prose.)

## Benchmark-claim honesty (learned)

When publishing benchmark results (README/docs), a claim must carry its own scope and **both** anti-Goodhart metrics. The v0.10 n=6 slice showed catch-rate and false-positive-rate can move in *opposite* directions (the DNA was net-positive on Opus but a catch-vs-cry-wolf trade-off on sub-Opus). So: never headline catch-rate alone ("DNA halves escapes") without the cry-wolf number beside it; keep `n=`, task count, and model scope visible; "strictly better" is a claim that needs *both* metrics to support it. Any cost-optimization lever (M7) is promoted only when it holds catch **and** does not raise cry-wolf — gated on **BOTH**.

## Defense-in-depth build hygiene (learned — runtime-start-governance sprint, 2026-06-18)

Each rule is from a real incident in the BL-002/003 build. Binding for hook/test/PRIL work here.

- **A multi-branch claim needs a test per branch — a test that still passes with a branch deleted does not cover it.** The `pretool-vision-gate` hook shipped "dual-path" but Path-2 (the independent recompute) was **dead on every machine with jq**, and the suite stayed green because the contract test only exercised Path-1. The false-green was caught by the *independent* code-reviewer, not the suite. So: when an implementation claims N detection/decision paths, write ≥1 falsifying test per path that fails if that path is removed; treat a branch with no path-specific test as RED, not covered. (Independent review on Opus is what catches this class — keep the review gate non-optional.)
- **Never `jq '.field // empty'` (or `// "default"`) on a field that can be boolean `false`.** jq's `//` treats `false` AND `null` as the empty/alternative case, so `.planning_allowed // empty` on a real `false` returns `""` — the exact bug that silently killed Path-2's deny. Use `jq -r '.field'` and compare the literal (`= "false"`), guarding jq error → empty → fail-open. Applies to every jq-using hook in `config/claude/hooks/**`.
- **A confirmed `Allowed change scope` (Phase 0.6) must be a machine-parseable one-path-per-line list, validated with `plumbline-scope-check` at intake — not prose.** The canvas scope was written as prose with inline descriptions; `plumbline_scope.py` (parses only `-`/`*`/`+` lines, strips backticks) read garbage and the fail-closed PRIL enforce Stop hook blocked the session — *every* changed file read out-of-scope. So: emit the scope as clean backtick-wrapped paths/globs (keep human prose separately if wanted), and run `plumbline-scope-check --repo . --feature <slug> --changed-files <list>` during Phase 0.6 so the gate is proven parseable before build. Note the enforce hook scopes the whole `merge-base(HEAD,main)…HEAD` surface, so a branch carrying sibling-feature intake must list those co-located (not-modified) artifacts too, or split features onto separate branches.
