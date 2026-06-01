## Evidence and source boundary

Known Plumbline evidence from repository inspection:

Existing test entrypoint: `config/claude/tests/run_all.sh`.

Existing test helpers: `config/claude/tests/lib.sh`.

Existing hooks: `config/claude/hooks/session-start.sh`, `config/claude/hooks/stop-learning-loop.sh`.

Existing metrics scripts: `config/claude/metrics/emit_run.py`, `config/claude/metrics/process_health.py`.

Existing governance command: `config/claude/commands/agileteam.md`.

Existing Watcher: `agileteam/plumbline-watcher.md`.

Existing templates: `docs/templates/product-canvas.template.md`, `docs/templates/product-vision.template.md`, `docs/templates/true-line-gate-check.template.md`, `docs/templates/traceability-true-line-fields.template.md`.

MISSING but referenced by Plumbline workflow and therefore planned as runtime-checked feature artifacts:

`docs/prd/<feature>.prd.md`

`docs/vision/<feature>.vision.md`

`docs/traceability.md`

`docs/contradictions/<feature>.contradictions.md`

ASSUMPTION: Missing feature artifact directories can be created by `/agileteam` during normal feature work. PRIL should not require them globally at repo root unless a feature check is invoked.

BLOCKER: None. The plan can proceed with additive files and fixtures.

---

## Requirements

IDRequirementSourceVerification

REQ-F-001Provide a Context Integrity CLI that checks feature Canvas, PRD, Vision, and traceability presence plus confirmation status.user-provided + repo evidenceFixture tests: complete context passes; missing/unconfirmed context fails

REQ-F-002Provide a Reality Evidence CLI that rejects final completion with missing, fake-only, placeholder, mock-only, or unverified evidence.user-provided + Plumbline invariantFixture tests for fake-only fail and integration/user-confirmed pass

REQ-F-003Provide a Scope Guard CLI that checks changed files against a declared feature scope.gstack learning adapted to PlumblineFixture tests for in-scope and out-of-scope file lists

REQ-F-004Provide a Redaction CLI for Metrics/Learnings text and JSONL before persistence.gstack learning adapted to PlumblineSecret fixture must not leak original secret; invalid JSONL fails

REQ-F-005Provide a Learnings Store CLI with `add`, `search`, `inject`, and `prune` behavior.user-providedJSONL tests for approved, unapproved, expired, and feature-matched learnings

REQ-S-001Persisted metrics/learnings must never store obvious tokens, API keys, private env dumps, or credentials unredacted.securityRedaction tests and fail-closed invalid input tests

REQ-A-001PRIL must be additive and not replace existing Plumbline gates or Watcher judgement.architecture constraintReview changed files; no deletion of existing gate text

REQ-O-001PRIL tests must run inside existing `run_all.sh`.repo evidence`bash config/claude/tests/run_all.sh`

REQ-NF-001PRIL must use Bash plus Python standard library only.repo styleNo new package lockfiles or dependency declarations

---

## Architecture and file boundaries

### Create

`config/claude/bin/plumbline-context-check
config/claude/bin/plumbline-reality-check
config/claude/bin/plumbline-scope-check
config/claude/bin/plumbline-redact
config/claude/bin/plumbline-learnings

config/claude/lib/plumbline_context.py
config/claude/lib/plumbline_reality.py
config/claude/lib/plumbline_scope.py
config/claude/lib/plumbline_redact.py
config/claude/lib/plumbline_learnings.py

config/claude/hooks/pretool-plumbline-guard.sh

config/claude/tests/test_runtime_integrity_layer.sh
config/claude/tests/fixtures/pril/context-pass/
config/claude/tests/fixtures/pril/context-missing-vision/
config/claude/tests/fixtures/pril/context-unconfirmed-canvas/
config/claude/tests/fixtures/pril/reality-fake-only/
config/claude/tests/fixtures/pril/reality-integration-pass/
config/claude/tests/fixtures/pril/scope-pass/
config/claude/tests/fixtures/pril/scope-fail/
config/claude/tests/fixtures/pril/redaction/
config/claude/tests/fixtures/pril/learnings/

docs/templates/reality-ledger-evidence.schema.json
docs/templates/learnings-entry.schema.json
metrics/learnings.jsonl.example
docs/plans/2026-06-01-plumbline-runtime-integrity-layer.md`

### Modify

`config/claude/tests/run_all.sh
config/claude/commands/agileteam.md
agileteam/plumbline-watcher.md
docs/templates/true-line-gate-check.template.md
docs/templates/product-canvas.template.md
docs/templates/product-vision.template.md
docs/templates/traceability-true-line-fields.template.md`

### Do not modify in first slice

`.claude/settings.json
config/claude/hooks/session-start.sh
config/claude/hooks/stop-learning-loop.sh`

Reason: First implement PRIL as callable checks. Only wire hard PreToolUse hooks after the CLIs and tests are stable.

---

## CLI contracts

### `plumbline-context-check`

Bash

`config/claude/bin/plumbline-context-check --repo . --feature <feature-slug>`

Exit behavior:

`0`: all required context exists and is confirmed enough for development.

`2`: product-critical artifact missing.

`3`: artifact exists but is unconfirmed or has `MISSING`, `OPEN QUESTION`, or `BLOCKER` in critical fields.

`4`: malformed artifact.

Required checks:

`docs/canvas/<feature>.canvas.md`

`docs/prd/<feature>.prd.md`

`docs/vision/<feature>.vision.md`

`docs/traceability.md`

Canvas contains `Status: user-confirmed` or `Confirmed by user: yes`.

Vision contains `Status: confirmed`.

PRD contains `Status: user-confirmed` or equivalent confirmed marker.

Traceability links to Canvas, PRD, and Vision.

### `plumbline-reality-check`

Bash

`config/claude/bin/plumbline-reality-check --repo . --feature <feature-slug> --min-evidence integration`

Evidence rank:

`fake-only < unit-only < integration < browser-live < production-observed < user-confirmed`

Fail if:

evidence class missing

`fake-only`

`mock-only`

`placeholder`

`unverified`

`wired-in-prod?: no` for production claims

final completion has no real evidence line

### `plumbline-scope-check`

Bash

`config/claude/bin/plumbline-scope-check --repo . --feature <feature-slug> --changed-files changed.txt`

Scope source order:

`docs/canvas/<feature>.canvas.md` section `Allowed change scope`

`docs/traceability.md` feature rows

optional `docs/scope/<feature>.scope.json`

ASSUMPTION: If no scope source exists, PRIL fails with actionable message instead of guessing.

### `plumbline-redact`

Bash

`config/claude/bin/plumbline-redact --mode check < input.jsonl
config/claude/bin/plumbline-redact --mode auto < input.txt`

Fail closed for:

invalid JSONL in check mode

oversized input

high-confidence secret pattern

environment dump with likely credentials

### `plumbline-learnings`

Bash

`config/claude/bin/plumbline-learnings add --repo . --json '<entry>'
config/claude/bin/plumbline-learnings search --repo . --feature <feature-slug> --limit 5
config/claude/bin/plumbline-learnings inject --repo . --feature <feature-slug>
config/claude/bin/plumbline-learnings prune --repo .`

Rules:

Only `approved_by_user: true` entries can be injected.

Entries with `expires_or_review_after` in the past are not injected.

Redaction runs before write.

Invalid schema fails.

---

## Implementation phases

### Phase 1: Foundation and tests

Build `config/claude/bin/`, `config/claude/lib/`, PRIL fixture structure, and one combined test script.

Outcome: PRIL exists as an isolated, tested layer.

### Phase 2: Context and Reality checks

Implement the two highest-value product-integrity checks first.

Outcome: Plumbline blocks missing product truth and fake completion evidence.

### Phase 3: Scope Guard and Redaction

Add edit-boundary protection and safe persistence.

Outcome: Plumbline gains practical safety around agent changes and memory.

### Phase 4: Learnings Store

Add approved learning persistence and retrieval.

Outcome: Plumbline's Kaizen loop becomes reusable across runs.

### Phase 5: Orchestrator/Watcher integration

Reference PRIL checks in `/agileteam`, Watcher, and templates.

Outcome: Existing governance text now points to executable gates.

---

## Tasks

### TASK-001: Add PRIL test harness

Objective: Create a single focused test file for all PRIL checks before implementation.

Requirement links: REQ-O-001, REQ-A-001

Files/modules:

Create: `config/claude/tests/test_runtime_integrity_layer.sh`

Create: `config/claude/tests/fixtures/pril/`

Modify: `config/claude/tests/run_all.sh`

Use: `config/claude/tests/lib.sh`

Steps:

Source `config/claude/tests/lib.sh`.

Add placeholder tests that call the five planned CLIs.

Assert missing CLIs fail initially.

Add this stage to `run_all.sh` after product canvas and true-line tests.

Run focused test and record expected failure.

Validation:

Bash

`bash config/claude/tests/test_runtime_integrity_layer.sh
bash config/claude/tests/run_all.sh`

Expected result before implementation: PRIL tests fail because CLIs do not exist.

Expected result after implementation: all PRIL tests pass.

Rollback note: Remove the PRIL test stage from `run_all.sh` and delete `test_runtime_integrity_layer.sh`.

---

### TASK-002: Implement Context Integrity Check

Objective: Block development when Product Canvas, PRD, Vision, or traceability context is missing or unconfirmed.

Requirement links: REQ-F-001, REQ-A-001

Files/modules:

Create: `config/claude/bin/plumbline-context-check`

Create: `config/claude/lib/plumbline_context.py`

Create: `config/claude/tests/fixtures/pril/context-pass/`

Create: `config/claude/tests/fixtures/pril/context-missing-vision/`

Create: `config/claude/tests/fixtures/pril/context-unconfirmed-canvas/`

Modify: `config/claude/tests/test_runtime_integrity_layer.sh`

Steps:

Write fixtures first:

full fixture with Canvas, PRD, Vision, and traceability

missing Vision fixture

unconfirmed Canvas fixture

Add failing tests:

complete fixture returns `0`

missing Vision returns non-zero

unconfirmed Canvas returns non-zero

Implement Python parser using standard library only.

Add Bash wrapper that resolves repo root and calls Python.

Emit concise human-readable errors plus optional `--json`.

Run focused and full tests.

Validation:

Bash

`config/claude/bin/plumbline-context-check --repo config/claude/tests/fixtures/pril/context-pass --feature demo
config/claude/bin/plumbline-context-check --repo config/claude/tests/fixtures/pril/context-missing-vision --feature demo
bash config/claude/tests/run_all.sh`

Acceptance criteria:

Pass fixture exits `0`.

Missing Vision exits `2`.

Unconfirmed Canvas exits `3`.

Error names exact missing or unconfirmed artifact.

Rollback note: Delete context CLI/lib/fixtures and remove tests.

---

### TASK-003: Implement Reality Evidence Check

Objective: Prevent final completion when evidence is fake-only, missing, placeholder, or unverified.

Requirement links: REQ-F-002

Files/modules:

Create: `config/claude/bin/plumbline-reality-check`

Create: `config/claude/lib/plumbline_reality.py`

Create: `docs/templates/reality-ledger-evidence.schema.json`

Create: `config/claude/tests/fixtures/pril/reality-fake-only/`

Create: `config/claude/tests/fixtures/pril/reality-integration-pass/`

Modify: `docs/templates/true-line-gate-check.template.md`

Modify: `docs/templates/traceability-true-line-fields.template.md`

Steps:

Define schema with fields:

`feature`

`requirement_id`

`evidence_class`

`evidence_ref`

`wired_in_prod`

`verified_by`

`notes`

Write fake-only fixture that must fail.

Write integration fixture that must pass.

Write tests before implementation.

Implement ranking and minimum evidence threshold.

Update True-Line template to require machine-check output.

Run full tests.

Validation:

Bash

`config/claude/bin/plumbline-reality-check --repo config/claude/tests/fixtures/pril/reality-fake-only --feature demo
config/claude/bin/plumbline-reality-check --repo config/claude/tests/fixtures/pril/reality-integration-pass --feature demo --min-evidence integration
bash config/claude/tests/run_all.sh`

Acceptance criteria:

`fake-only` fails.

missing evidence class fails.

`integration` passes when min evidence is `integration`.

Template documents the evidence classes.

Rollback note: Remove CLI/lib/schema/fixtures and revert template edits.

---

### TASK-004: Implement Scope Guard

Objective: Detect edits outside the declared feature scope before write-like actions or gate completion.

Requirement links: REQ-F-003, REQ-A-001

Files/modules:

Create: `config/claude/bin/plumbline-scope-check`

Create: `config/claude/lib/plumbline_scope.py`

Create: `config/claude/hooks/pretool-plumbline-guard.sh`

Create: `config/claude/tests/fixtures/pril/scope-pass/`

Create: `config/claude/tests/fixtures/pril/scope-fail/`

Modify: `docs/templates/product-canvas.template.md`

Steps:

Add `Allowed change scope` section to Product Canvas template.

Create fixture with allowed scope:

`src/demo/**`

`docs/canvas/demo.canvas.md`

`docs/prd/demo.prd.md`

Add test where changed files are all in scope.

Add test where changed file is outside scope.

Implement glob/path matching safely:

normalize paths

reject absolute paths outside repo

reject `..`

Add optional hook script that can read Claude PreToolUse JSON later.

Do not wire `.claude/settings.json` yet.

Validation:

Bash

`config/claude/bin/plumbline-scope-check --repo config/claude/tests/fixtures/pril/scope-pass --feature demo --changed-files config/claude/tests/fixtures/pril/scope-pass/changed.txt
config/claude/bin/plumbline-scope-check --repo config/claude/tests/fixtures/pril/scope-fail --feature demo --changed-files config/claude/tests/fixtures/pril/scope-fail/changed.txt
bash config/claude/tests/run_all.sh`

Acceptance criteria:

In-scope edit list exits `0`.

Out-of-scope edit list exits non-zero.

Error lists the violating file.

Missing scope fails with an actionable message.

Rollback note: Delete scope files and revert template addition.

---

### TASK-005: Implement Redaction Layer

Objective: Prevent unsafe secrets from being written into metrics, learnings, or reports.

Requirement links: REQ-F-004, REQ-S-001

Files/modules:

Create: `config/claude/bin/plumbline-redact`

Create: `config/claude/lib/plumbline_redact.py`

Create: `config/claude/tests/fixtures/pril/redaction/secrets.txt`

Create: `config/claude/tests/fixtures/pril/redaction/secrets.jsonl`

Steps:

Create fixtures using fake but structurally realistic secrets:

fake API key

fake bearer token

fake password assignment

fake private env dump

Write tests:

check mode returns non-zero for high-risk secret

auto mode replaces with placeholders

original secret does not appear in output

invalid JSONL fails closed

Implement deterministic standard-library regex scanner.

Add input size cap.

Add JSON output option for future audit logs.

Run full tests.

Validation:

Bash

`config/claude/bin/plumbline-redact --mode check < config/claude/tests/fixtures/pril/redaction/secrets.txt
config/claude/bin/plumbline-redact --mode auto < config/claude/tests/fixtures/pril/redaction/secrets.txt
bash config/claude/tests/run_all.sh`

Acceptance criteria:

Secret check exits non-zero.

Auto-redaction masks secrets.

Invalid JSONL exits non-zero.

No original secret appears in auto-redacted output.

Rollback note: Delete redaction CLI/lib/fixtures and remove tests.

---

### TASK-006: Implement Learnings Store

Objective: Make Plumbline's retrospective learning durable, searchable, approved, and safely injectable.

Requirement links: REQ-F-005, REQ-S-001

Files/modules:

Create: `config/claude/bin/plumbline-learnings`

Create: `config/claude/lib/plumbline_learnings.py`

Create: `docs/templates/learnings-entry.schema.json`

Create: `metrics/learnings.jsonl.example`

Create: `config/claude/tests/fixtures/pril/learnings/`

Steps:

Define JSONL schema:

`timestamp`

`feature`

`type`

`pattern`

`failure_mode`

`root_cause`

`new_rule`

`scope`

`approved_by_user`

`confidence`

`evidence`

`expires_or_review_after`

Write tests:

approved feature learning is found

unapproved learning is not injected

expired learning is not injected

invalid schema fails

redaction runs before write

Implement `add`.

Implement `search`.

Implement `inject`.

Implement `prune`.

Add example file, not live data.

Validation:

Bash

`config/claude/bin/plumbline-learnings search --repo config/claude/tests/fixtures/pril/learnings --feature demo --limit 5
config/claude/bin/plumbline-learnings inject --repo config/claude/tests/fixtures/pril/learnings --feature demo
bash config/claude/tests/run_all.sh`

Acceptance criteria:

Approved current learning is returned.

Unapproved learning is suppressed.

Expired learning is suppressed.

Invalid JSONL fails.

Redaction is applied before persistence.

Rollback note: Delete learnings CLI/lib/schema/example/fixtures and remove tests.

---

### TASK-007: Integrate PRIL into `/agileteam` and Watcher text

Objective: Make existing Plumbline agents call or require PRIL outputs at the right points.

Requirement links: REQ-A-001, REQ-O-001

Files/modules:

Modify: `config/claude/commands/agileteam.md`

Modify: `agileteam/plumbline-watcher.md`

Modify: `docs/templates/true-line-gate-check.template.md`

Modify: `docs/templates/product-canvas.template.md`

Modify: `docs/templates/product-vision.template.md`

Steps:

Add Phase 0.5 instruction:

run `plumbline-context-check` before development entry.

Add Gate C/D instruction:

run `plumbline-reality-check` before validation/judgement pass.

Add implementation-loop instruction:

run `plumbline-scope-check` on changed files before declaring scope-safe.

Add Retro instruction:

proposed learnings go through `plumbline-redact` and `plumbline-learnings add`.

Add Watcher rule:

Watcher cannot return `pass` when PRIL check failed.

Keep user override path explicit:

only user can reclassify a product-value contradiction.

Validation:

Bash

`bash config/claude/tests/run_all.sh
grep -R "plumbline-context-check" config/claude/commands/agileteam.md agileteam/plumbline-watcher.md
grep -R "plumbline-reality-check" config/claude/commands/agileteam.md agileteam/plumbline-watcher.md`

Acceptance criteria:

`/agileteam` names all required PRIL checks.

Watcher treats PRIL failure as non-pass.

Existing True-Line governance tests still pass.

No existing gate is removed.

Rollback note: Revert only documentation/integration edits; CLIs remain callable.

---

### TASK-008: Optional hard hook wiring after stability

Objective: Prepare but do not prematurely activate hard PreToolUse enforcement.

Requirement links: REQ-F-003, REQ-S-001

Files/modules:

Existing optional file: `config/claude/hooks/pretool-plumbline-guard.sh`

MISSING target until decision: `.claude/settings.json` PreToolUse hook configuration

Steps:

Document hook input expectations.

Test hook with sample JSON payloads if Claude Code PreToolUse payload shape is known.

OPEN QUESTION: exact Claude Code PreToolUse JSON shape in target environment.

Only after confirmation, add optional settings snippet to docs, not auto-enabled.

Keep default integration command-driven, not hard-hook-driven.

Validation:

Bash

`bash config/claude/tests/run_all.sh`

Acceptance criteria:

Hook script exists and is testable with fixture payloads.

`.claude/settings.json` is not modified until payload contract is verified.

No accidental blocking of normal sessions.

Rollback note: Delete optional hook script.

---

## Validation strategy

### Full validation

Bash

`bash config/claude/tests/run_all.sh`

Expected final output:

`ALL CHECKS PASSED`

### Focused validation

Bash

`bash config/claude/tests/test_runtime_integrity_layer.sh`

Expected final output:

`runtime integrity layer tests: 0 failed`

### Manual review checklist

No new external dependencies.

No replacement of existing Plumbline Watcher authority.

No automatic process-rule persistence without user approval.

No secret-like string from fixtures appears in redacted output.

Missing feature context gives actionable error messages.

Fake-only evidence cannot pass final validation.

Out-of-scope edits cannot be silently accepted.

---

## Rollback and safety

Rollback is low-risk because the change is additive.

Rollback sequence:

Remove PRIL stage from `config/claude/tests/run_all.sh`.

Remove new files under:

`config/claude/bin/plumbline-*`

`config/claude/lib/plumbline_*`

`config/claude/tests/test_runtime_integrity_layer.sh`

`config/claude/tests/fixtures/pril/`

Revert modified templates and `/agileteam`/Watcher references.

Keep `metrics/learnings.jsonl` archived if created during real usage.

Do not delete existing metrics or benchmark data.

Safety notes:

Do not enable hard PreToolUse blocking until its input contract is verified.

Do not treat PRIL as proof of product truth; it is a machine-checkable floor.

Do not allow agents to self-confirm product-value artifacts.

Do not store live secrets in test fixtures.

---

## Execution handoff

Implement in this order:

`TASK-001` test harness.

`TASK-002` Context Integrity Check.

`TASK-003` Reality Evidence Check.

`TASK-004` Scope Guard.

`TASK-005` Redaction Layer.

`TASK-006` Learnings Store.

`TASK-007` `/agileteam` and Watcher integration.

`TASK-008` optional hook spike only after payload contract is known.

Smallest useful merge slice:

`TASK-001 + TASK-002 + TASK-003`

This already gives Plumbline the highest-impact improvement: it blocks missing context and fake completion evidence with executable checks.

---

## Options considered

### Option A: Copy gstack-style broad skill stack

Rejected. Plumbline already has many agents and strong governance. More skills would increase complexity without fixing the core weakness.

### Option B: Add only more Markdown governance tests

Rejected as insufficient. Existing tests already check many textual contracts. The weakness is runtime enforceability.

### Option C: Add PRIL as small executable integrity layer

Selected. It preserves Plumbline's identity while adding gstack's most valuable practical pattern: executable guardrails, safe persistence, and reusable learnings.

---

## Plausibility and truth self-check

Goal block is compact and under the required limit.

File paths marked as existing are based on repository inspection.

Missing directories are marked as MISSING or planned creates.

No dependency on gstack internals is required.

No destructive commands are included.

Acceptance criteria are binary and testable.

The plan does not claim PRIL proves correctness; it only raises Plumbline's executable integrity floor.

Main failure-mode chain is addressed: agent skips/forgets governance -> PRIL detects missing context/evidence/scope -> gate fails -> Watcher cannot pass -> user or team resolves the contradiction.
