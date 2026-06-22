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
- **Injectable seam ⇒ wired + gated + falsified + smoked** (the recurring
  wired-in-prod-one-level-down class — 4× this project). A fake/injected TEST seam standing in
  for a real boundary is *not* wired-in-prod until all four hold: (1) a paired real entrypoint
  actually composed through the prod root, env-gated OFF by default (`*_LIVE=1`); (2) a
  counter-based *falsifying* test that reddens if the wiring is reverted (not just an outcome
  assertion); (3) the headline real-boundary smoke run BEFORE the acceptance gate; (4) the
  gate-OFF-by-default proven offline. Offline-green over an injected seam proves nothing about
  prod. Incidents: dead `_real_transport` (Slice 1), unwired `catalog_ids` resolver (Slice 2),
  the GUI offline path that rendered only via the inject-seam while the real socket 400'd
  (Slice 4).
- **Independence** — whoever writes code does not review it; whoever derives tests does
  not implement them. Review/security/validation must not echo the coder's reasoning.
- **Human gates stay** — requirements confirmation, the Product Canvas, product
  judgment, and persistent self-improvement always require explicit human sign-off.

## Plumbline stance: truth through awareness (foundational — learned 2026-06-21)

**Wahrheit durch Bewusstsein — bewusstes Sein durch explizite Regeln und bewusste
Entscheidungen.** (Truth through awareness; conscious being through explicit rules and
conscious decisions.) This is the deepest stabilizer in the project — a *stance*, prior to
any gate. The gates above only hold because of it.

The incident that made it explicit: at the end of the OpenRouter arc the agent **silently
skipped the formal Phase-4 retro** and waved off the last slice's learning as "schon normal
/ a confirmation of an existing rule." No rule was broken — but an **implicit decision was
passed over as self-evident**, and in doing so it quietly declared something a rule
*without consciousness*: unexamined, unchangeable, ungovernable. A blind automatism. The
value was not lost only because the skip was later **named out loud** — and naming it gave
the team the chance to make the implicit explicit, and therefore changeable, governable,
safe.

The binding stance (not a tactic — a way of working):

- **Put space between impulse and action.** Before skipping, shortcutting, defaulting, or
  treating any discipline step as "normal / not needed / already covered" — pause (even
  briefly, even just after) and ask consciously: *was that actually something we want to do
  here, or am I just assuming it's normal — and thereby turning something implicit into an
  implicit rule?*
- **Make the implicit explicit.** A skip, a default, a "that's how it's done" is only safe
  once it is *named as a conscious decision*. The instant it is surfaced, it becomes
  changeable, governable, safe — the opposite of a silent automatism. Implicit habit
  silently accreting into rule is exactly what this stance exists to prevent.
- **Awareness is the act, not perfection.** The rule is **not** "never skip" — lean/skip is
  often right. The rule is to skip *consciously and visibly*: name it, offer the
  alternative, and where it would set precedent, confirm it with the human — so the team can
  examine and govern it, rather than letting an unexamined habit become the rule.

How to apply: when you catch yourself about to bypass a step on the grounds of
"normal/covered/not worth it," **surface that as an explicit, named decision** instead of
silently passing it. This is the mechanism by which Plumbline turns implicit habit into
explicit, governable, truthful practice — one conscious decision at a time. (This stance is
*why* the no-silent-downgrade, no-silent-cap, and human-gate invariants exist; it
generalizes them to every default the agent would otherwise take unseen.)

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

## /agileteam build hygiene (learned — openrouter-council-backend sprint, 2026-06-18)

Each rule is from a real incident in the OD-3 build. Binding for `/agileteam` feature work here.

- **Branch each feature from `main`, not from another feature's tip.** Stacking branch B on branch A's HEAD made the fail-closed PRIL enforce hook (which scopes the whole `merge-base(HEAD,main)…HEAD` surface) read A's files as out-of-B-scope and **block the Stop gate**. So: start every `/agileteam` feature branch from `main`; if a sibling feature's confirmed intake is needed, restore only those specific files onto the clean branch. Keep one feature per branch surface.
- **Create the PRIL reality ledger during Phase 3, at the honest evidence class.** Gate E (`plumbline-watcher`) cannot return `pass` while `docs/reality/<feature>.evidence.jsonl` is absent — the executable reality floor has nothing to read. So author it in Phase 3 (Gate C) with one record per load-bearing REQ at its TRUE class (`integration-fake` for offline/fake-transport logic; `real-boundary-smoke` only when a real boundary was actually crossed), and run `plumbline-reality-check --min-evidence <the-feature's-honest-floor>` — never raise the ledger class to clear the default `integration` floor (that launders the ceiling). Avoid the `FORBIDDEN_TOKENS` (`fake-only`/`mock-only`/`placeholder`/`unverified`) in the ledger text.
- **Emit the canvas `Allowed change scope` machine-parseable at intake.** The PRIL scope guard (`plumbline_scope.py`) parses only `-`/`*`/`+` lines and strips backticks, so prose bullets with inline descriptions read as garbage and block the Stop gate. The `requirements-analyst` must write the scope as a clean one-path-per-line list (backtick-wrapped paths/globs) at Phase 0.15/0.6 and validate it with `plumbline-scope-check` THEN — not leave prose for the orchestrator to retrofit mid-build. Include the feature's own evidence/trace/plan/ledger paths and `CLAUDE.md` (the learning-loop target) in that list. **Scope the TEST surface too, not just production + docs (plumbline-update-reliability 2026-06-21 — the fail-closed Stop gate blocked TWICE mid-build):** list every test file the build will add (`config/claude/tests/test_<feature>.sh`) AND the shared test helper `config/claude/tests/lib.sh` (a new macOS-skip / assert helper lands there), or use a `config/claude/tests/` glob — a new test or helper not in the scope reddens the enforce Stop hook mid-build, costing a canvas edit + re-verify each time.

## Real-boundary evidence hygiene (learned — openrouter-inference sprint, 2026-06-19)

Each rule is from a real incident in the Slice-1 build, caught by the defense-in-depth gates.

- **A real-boundary smoke must not hand-feed the value of the instrument it measures.** The invocability smoke supplied `--input-estimate 12` by hand, then the benchmark claimed "the heuristic estimated 12" and reported the drift of that typed-in number — the module's own heuristic actually computes 10 (real drift +8). A benchmark that measures an instrument's fidelity (a heuristic, an estimator, a classifier) MUST let the instrument compute its own value; supplying it by hand and attributing it to the instrument is a "looks-measured-but-isn't" claim. Re-run the smoke the honest way; never re-word around it. (Caught by an `ultrathink-craftsmanship` plausibility pass over the *numbers*, not the process — run one before committing benchmark claims.)
- **Assert exact signed/numeric values, not substrings, for numeric contract fields.** A drift test used `grep -F "15"`, which matched `-15` and masked a sign-inverted computation (`input-prompt` vs the contract's `prompt-input`). For any numeric/signed result field, assert the exact value (`"drift": 15`), never a bare substring — a substring silently passes wrong signs and magnitudes.
- **Injectable seam was dead in prod (Slice-1 instance of the *Injectable seam ⇒ wired+gated+falsified+smoked* core invariant):** `_real_transport` existed but the CLI hardwired `transport=None` → offline-green, real path unreachable, the headline smoke impossible. Full prescription: see that core invariant (in "Core invariants").

## Foreign-model council build hygiene (learned — deepseek-review-agent / Slice 2, 2026-06-19)

Each rule is from a real incident in the Slice-2 build, caught by the defense-in-depth gates.

- **Verify model ids against the LIVE catalog (or resolve dynamically) — never hardcode a model from memory.** A hardcoded model-id constant is a time-bomb: this sprint it went stale **twice** — Slice-1's `meta-llama/llama-3.1-8b-instruct:free` had dropped from the OpenRouter catalog, and the "fix" picked `qwen/qwen3-235b-a22b:free` which *also* wasn't in the catalog (a second stale default, caught only by a live `GET /api/v1/models` check). So: before freezing any model id, verify it against the live catalog, or resolve it at runtime against the catalog (preference-ordered, fail-closed on unreachable — never a stale pick). A hardcoded fallback is acceptable only as a documented no-catalog last resort with a periodic-recheck note. (This is the no-hardcoded-version rule applied to model ids.)
- **Smoke-before-acceptance caught a dead real-path (Slice-2 instance of the same core invariant):** the `--inject-catalog` resolver was 91/91 offline-green but its live catalog fetch was never wired (`catalog_ids` always `None`); two reviewers trusted a docstring — the real full-preset smoke exposed it on the first dry-run. Full prescription: see the *Injectable seam ⇒ wired+gated+falsified+smoked* core invariant.
- **No `eval`-based test assertions over payload content — it is an injection and fragility vector.** The leak-check loop ran `assert "! printf '%s' \"$payload\" | grep …"` through `eval`; a backtick / `$()` in a legitimate payload (a character system prompt) executed command substitution from the content (a scratch probe ran `touch /tmp/_pwned_canary`) and otherwise broke parsing — which had forced production code to *mangle its own disclosed output* to pass. Fix: assert via a parameter-passed `grep` helper (`assert_not_contains` using `printf '%s' "$2" | grep -qF -- "$3"`), never `eval` payload content. A test that forces production to mangle content to pass is the defect, not the content.

## Measurement-slice + portability hygiene (learned — council-diversity-measurement / Slice 3a, 2026-06-19)

Each rule is from a real incident in the Slice-3a build, caught by the defense-in-depth gates (one only by CI).

- **CI (macOS / bash 3.2) is the source of truth — and a quoted heredoc inside `$(...)` with an apostrophe/single-quote in its body breaks there while parsing fine locally (bash 5).** `lib.sh` grew an `assert_json_eq` helper whose `<<'PY' … PY` heredoc lives inside `got="$(… <<'PY' … PY)"`; bash < 4.4 (macOS `/bin/bash` is 3.2) does **not** skip a quoted-heredoc body when scanning for the closing `)`, so an apostrophe in the body comment (`test-author's`) read as an unclosed quote → `lib.sh` failed to parse → EVERY test that sources it died (`finish: command not found`). `bash -n` + `run_all.sh` were green locally; only macOS CI caught it. **CORRECTION (Slice-3b, a 2nd+3rd instance):** it is NOT just apostrophes — a `"` (double-quote) inside a `$(...)`-wrapped heredoc body breaks bash 3.2 the SAME way (`test_council_measurement_run.sh` died with `unexpected EOF looking for matching '"'` from double-quoted Python inside `VAR="$(python3 - <<'PY' … PY)"`). The only safe rule is: **do NOT wrap a heredoc inside `$(...)` at all** — redirect it to a temp file and read the file (`python3 - args >"$TMP" 2>&1 <<'PY' … PY; VAR="$(cat "$TMP")"`). "Use double-quotes instead of single-quotes" does NOT fix it. (`grep -nE '=\s*"\$\(.*<<'` over your test should return nothing.) And never trust local-green/`mergeable` — confirm the `ci` workflow `conclusion=success` on EVERY OS (macOS bash 3.2 is the strict one) before merge.
- **A measurement corpus needs an oracle↔diff *fidelity* falsifier — and you verify it by MEASURING, not reading.** The new review-catch corpus's oracle line numbers did not point at the seeded-defect lines (off-by-1..3 from inconsistent hunk counting), so a *correct* reviewer scored **0 catches + a cry-wolf per correct flag** — silently inverting the eventual measurement. Schema/variance tests were green (they used synthetic in-test oracles); the bug was caught only when the code-reviewer scored a known-correct reviewer against the real corpus. So: for any scored corpus, add a falsifying test that the oracle's defect lines fall on the real defect lines of the diff (and carry the expected token), and treat that fidelity test — not a hand-guessed number — as the arbiter of the correct line map.
- **Spec-sanity for a measurement/eval slice must verify the corpus/instrument contract against the REAL files before the build.** The Slice-3 canvas claimed `pipe-providedfake-v1` was the catch+cry-wolf+recall corpus — that property actually belongs to `pipe-core-v1`; the claim was read off the wrong file, and the named corpus was a single saturated task with no controls. It propagated through canvas→PRD until the spec-auditor opened the real corpus dirs. So: for measurement slices, the spec-sanity gate must open the actual corpus/harness/oracle files and confirm the named instrument has the claimed structure (controls, variance, scorer subject) — a corpus premise read off the wrong file is the same konfabulation class as a wrong API.
- **When re-confirming after a material re-scope, propagate the status to header + body + DoR checkboxes together — a partial flip is a contradiction the True-Line watcher pauses on.** After the user re-confirmed the re-scoped 3a intake, only the header `Status:` lines were flipped to `user-confirmed`; the analyst-written body text + unchecked DoR boxes still said "re-confirmation pending" → Gate E paused on the self-contradiction (the BLOCKER-4 shape, relocated). The resolution must record the REAL confirmation event and reconcile every place (header, body, checkboxes, traceability) to one consistent status — never flip a status that did not happen.

## Measurement-run honesty (learned — council-measurement-run / Slice 3b, 2026-06-20)

Each rule is from a real incident in the Slice-3b build, caught by the defense-in-depth gates.

- **An A/B comparison measurement must feed BOTH arms through the IDENTICAL instrument — same prompt protocol, same parser, same scorer.** Slice 3b's first design measured Arm A (Claude) on a structured flag protocol (near-lossless JSON parse) while Arm B (the council) returned free-text prose that a separate, lossy, one-arm parser converted to flags — and `parse_flag_set` can't parse prose at all, so the council would have scored structurally zero. The spec-auditor flagged this as the #1 BLOCKER: a parser that turns one arm's output into the scored form IS part of the instrument, and it touched only one arm → an asymmetric, biased, uninterpretable comparison. The fix is symmetric: prompt BOTH arms in the same structured protocol (appended to the subject) and parse both with the same parser; a non-protocol output is the same classified failure for both. When you build any A-vs-B measurement, prove the extraction/scoring path is byte-identical for both arms before trusting the numbers.
- **At tiny n, `demonstrated`/`refuted` are definitionally out of reach — frame the pilot as underpowered and never launder a lucky split.** The n=2 pilot's cross-task variance is unestimable, so no catch-delta lies "outside the noise band." The honest outcome vocabulary at n=2 is `underpowered` / `tradeoff-signal-to-investigate` only; the real risk is not underpowered-as-refuted but a lucky 2/2-vs-0/2 split sold as `demonstrated`. Pre-register that `demonstrated`/`refuted` require the powered run, make `underpowered` a distinct reachable outcome (survivors-below-floor OR delta-below-MDE), and treat the pilot's value as the cost/flakiness ESTIMATE, not a verdict. (Our pilot returned `underpowered` with 100% free-tier Arm-B attrition — the actionable finding was "free tier is unusable here; the powered run needs paid models," exactly what a pilot is for.)
- **Don't mis-apply a test invariant to a consumer that legitimately needs the dependency — fix the test's scope, don't obfuscate to pass it.** An `assert_no_code_token '_real_transport|urllib'` check was correct for the import-pure 3a scorer, but wrong for the 3b orchestrator, which legitimately consumes `council_inference._real_transport` for the live Arm-A boundary. The coder satisfied the prohibition with a `getattr(council_inference, "_"+"real"+...)` dodge so the literal wasn't a code token — test-gaming of the same family as the Slice-3a `_preview_safe` hack, making the source less readable to pass a contract that should not apply. The fix: relax the test to the real invariant ("defines no transport, imports no http") so a plain reference is allowed, then reference the dependency plainly. A test that forces obfuscation is mis-scoped — repair the test (tester), never game it (coder).

## Measurement-instrument + free-tier hygiene (learned — free-diversity-probe / EXP-009, 2026-06-20)

Each rule is from a real incident running the no-budget free reframe of the council measurement.

- **A measurement instrument that pins itself byte-unchanged cannot be reconfigured for a new experiment — build a SEPARATE harness that reuses its primitives read-only.** The 3b council-measurement orchestrator's own contract (`test_council_measurement_run.sh`) asserts `git diff --quiet -- council_presets.py` (+ the other instrument files) — the frozen-instrument invariant (REQ-MR-009). So repointing the council at chosen models by editing `FREE_MODEL_FAMILY_PREFERENCE`/the preset roster would have reddened run_all. The right move for a new experiment (EXP-009) was a NEW harness (`council_free_diversity_probe.py`) that IMPORTS the vetted primitives (`run_arm_a`, `score_flag_set`, `classify_outcome`) read-only and adds only the new dispatch loop — the frozen instrument stays byte-unchanged. When you need to vary what a frozen instrument measures, wrap it, never edit it.
- **A saturated corpus (baseline already scores 100%) cannot show the treatment's advantage — a diversity/quality corpus needs tasks the baseline MISSES.** EXP-009's free council showed catch-delta 0 — but only because both the single-model baseline AND the council caught 100% on the n=2 corpus (a ceiling). With no headroom, the only thing the comparison can surface is a cry-wolf difference (here the council added +0.25 cry-wolf — the "more reviewers → more noise" hint). Before a powered A/B over a corpus, verify the baseline does NOT already ace it; otherwise you are measuring noise, not the lever. Headroom (tasks a single model fails) is a corpus-design precondition, not an afterthought.
- **Free-tier model reachability is intermittent — probe it IMMEDIATELY before a live run and pin the baseline to a reachable model.** Two reachability probes minutes apart returned 2/5 then 5/8 reachable (429s shift minute-to-minute; they are often daily caps, not transient). The measurement's paired-exclusion drops a subject if EITHER arm's model 429s, so an unreachable baseline → 100% attrition regardless of the council (the pilot's outcome). So: probe the exact model set just before the run, set the baseline to a currently-reachable model, and treat reachability luck itself as a disclosed confound (the pilot got 100% attrition; EXP-009 got 0% — same corpus, days apart).

## GUI / live-boundary build hygiene (learned — openrouter-gui / Slice 4, 2026-06-20)

Each rule is from a real incident in the Slice-4 Council-Runner GUI build, caught by the defense-in-depth gates (one by the user, one by the watcher, one only by macOS CI).

- **Never invent a fake/demo to make a dead path look green — when a real path cannot render, return an honest classified message.** The spec-auditor found the served browser OFFLINE path returned 400 (no positions); the "fix" added a bundled `DEMO_COUNCIL` so the browser rendered canned positions — a direct violation of "real code or no code" (`placeholder` is a FORBIDDEN_TOKEN), caught by the USER, not the suite. The honest answer was: offline-without-live returns a classified `COUNCIL_LIVE_REQUIRED` ("enable live to run the council"), and REAL positions come only from the live boundary. So: if a path genuinely cannot produce real output (offline can't reach a live boundary, a precondition is unmet), surface a classified/actionable error — NEVER a canned/demo/sample fallback rendered to the user. A demo that makes the path "work" is the exact looks-done-but-isn't the repo exists to prevent. (Test-only injected fixtures are fine; a USER-FACING demo is not.)
- **A re-scope / status flip must propagate to EVERY artifact — including the traceability matrix.** After the user's no-demo override, the canvas/PRD/vision/reality-ledger were reconciled to LIVE-ONLY-REAL + the split evidence floor, but `docs/trace/openrouter-gui.trace.md` was left stale (still "every record integration-fake / live DEFERRED / no real boundary", no REQ-GUI-018 row) → the plumbline-watcher PAUSED (CONTRA-GUI-TRACE-STALE-01). This is the partial-flip class (BLOCKER-4) one artifact wider: when a re-scope changes evidence classes / status, update canvas AND prd AND vision AND the reality ledger AND the trace matrix together (and re-grep for the old vocabulary), or the watcher pauses on the self-contradiction. The trace matrix is an artifact, not an afterthought.
- **A long-lived spawned `http.server` is unreachable over loopback on the macOS CI runner — diagnose, then macOS-only SKIP with a loud notice (never a silent pass), keep Linux hard.** The GUI socket tests went green locally + on Linux but failed on macOS CI; GUI_SRV_DIAG instrumentation showed the `serve` subprocess was ALIVE (returncode None, empty stderr, no bind error) yet the client could not connect to 127.0.0.1:<port> within 30s — a macOS-CI-runner network/sandbox limitation on accepting loopback connections to a spawned server (the test header already noted "http.server in a bash test is flaky"), NOT a production defect (the in-process render/config/spawn seams pass on macOS; the real socket passes on Linux; security drove it live). The honest fix is a NARROW skip: only when `uname=Darwin` AND the marker is exactly `SERVER_NOT_READY` (server alive, unconnectable after the full retry budget), emit a tallied `GUI_SRV_SKIP:` notice and skip ONLY those socket-listening assertions; Linux stays a HARD real-boundary verifier, the in-process seams stay hard everywhere, and a reachable-but-WRONG response is still a hard fail on every OS (the skip keys off connectivity, never the assertion outcome). Don't silent-pass and don't redden the whole suite for a runner limitation — diagnose it first (instrument the failure to be CI-visible), prove it's the runner not prod, then skip-with-notice. **Generalize — this is NOT GUI-specific (2nd instance, plumbline-update-reliability 2026-06-21):** ANY test that stands up a loopback `http.server` stub hits the same macOS-CI limitation — the PUR `update --check` tests drove a `127.0.0.1` `PLUMBLINE_GITHUB_API` stub and went red on macOS CI (green on Linux + local) for the identical reason. Build the narrow skip in **from the start** via the reusable `config/claude/tests/lib.sh` helpers (`pur_stub_reachable` → `STUB_REACHABLE`/`STUB_NOT_READY`; `pur_macos_stub_skip_active`; `pur_stub_skip_notice`; the GUI `gui_*` variants alongside) — gate ONLY on `uname=Darwin` AND the connectivity marker (never the assertion outcome). Don't rediscover this as a red CI run per new stub family.

## /agileteam autonomous execution contract (learned — workflow-autonomy, 2026-06-21)

The headline value of `/agileteam` is the AUTONOMOUS sprint runthrough — the human acts ONLY at the confirmed gates. The harness already re-invokes the orchestrator on every subagent's completion (task-notification), so the run progresses on its own; do NOT bury that under handoff narration.

- **Never end a turn merely "waiting for subagent X" as if handing back to the user.** That surfaces a false stall, trains the terminal's response-suggestion to echo "Warten auf…", and makes a stuck/dead agent the user's job to notice. State in one line what is running, then ACTUALLY auto-continue on the notification (verify → dispatch the next phase → …).
- **Pause for the user ONLY at:** the confirmed human gates (Product Canvas confirm, Product Vision confirm, final acceptance), a real-money / live-spend decision, a genuine BLOCKER/contradiction, or a design choice that needs an explicit AskUserQuestion. Everything between gates runs through autonomously.
- **For a multi-step build pipeline (tester → coder → reviewer → security → reality-ledger → watcher), prefer ONE autonomous run** — use the Workflow tool (a single background orchestration that returns only at the human gate; a dead agent → null, the pipeline continues) rather than one-agent-per-turn. The orchestrator — never the user — detects and re-dispatches a stuck/dead subagent (e.g. the session-limit deaths: re-dispatch, don't wait).
- A user typing "warte auf den X, dann Y" is a SMELL that the orchestrator made the autonomy the user's job — fix the orchestration, don't normalize the babysitting.

## Security: new secret on an existing seam (learned — plumbline-update-reliability sprint, 2026-06-21)

- **When a change adds a secret/asset to a request path that ALREADY has an overridable/injectable seam, RE-THREAT-MODEL that seam for the NEW asset — do not assume the old threat model still covers it.** Gate-B caught a CRITICAL: Sprint-2 added a GitHub token (`Authorization: Bearer`) to the release fetch, whose base URL was ALREADY overridable via the prod-honored `PLUMBLINE_GITHUB_API` seam (a test seam never re-examined for prod). The original threat model only covered "token never printed" — NOT "token shipped to an attacker host via the existing override" → real token exfiltration (proven: a sentinel token was captured at a `127.0.0.1` attacker stub). The fix gates the secret on the trusted destination (`Authorization` attached only when the resolved host `== api.github.com`, with an explicit DEFAULT-OFF `PLUMBLINE_GITHUB_API_ALLOW_INSECURE_TOKEN` escape for offline tests) + a falsifier that reddens if the host-gate is reverted (proven by revert). So: adding a credential/secret to ANY path that has a pre-existing env / URL / transport override is a NEW threat surface — explicitly ask "can this secret now reach a caller-controlled endpoint?", gate it to the trusted destination, and make the escape default-off + test-only. The escape itself only closes the *accidental* leak (a full env-controlling attacker is out of scope); name that residual in the reality ledger, don't pretend it's eliminated.

## CI portability: test path-canonicalization parity (learned — plumbline-update-reliability, 2026-06-22)

- **A test that compares filesystem paths must canonicalize the EXPECTED value the SAME way the production code does (`.resolve()` / `cd && pwd -P` parity) — a raw `mktemp` path vs a resolved path passes locally + on Linux but FAILS on macOS.** macOS `mktemp` returns `/var/folders/...`, where `/var` is a symlink to `/private/var`; production code that prints a `.resolve()`-canonicalized path emits the `/private/var/...` form, so a test comparing it against the raw `$TMP_ROOT` (`/var/...`) mismatches by exact string. This bit **twice** in one feature — CR-4 (the `recover:`-line exact snapshot-path assertion) and the SAMEPATH block (the symlink-target-resolves-to assertions) — both green on Linux + local, both RED only on macOS CI. Fix: canonicalize the expected value identically (`cd "$dir" && pwd -P` + basename, matching the lib's `.resolve()`) BEFORE the exact `grep -qF`; keep it **HARD on every OS** (never substring-weaken). This is distinct from the macOS-loopback-`http.server` runner limitation (which legitimately macOS-SKIPs): a path-canonicalization mismatch is a real TEST bug present on macOS, not a runner limitation — FIX it, don't skip it. General rule: **macOS CI is the strict OS; never trust local/Linux-green for path or shell portability** (the same lesson the bash-3.2 `$()`-heredoc rule already encodes for shell — this is its filesystem-path analogue).
