# The canonical scope manifest (`docs/scope/<feature>.scope.json`)

The Allowed change scope is a **security configuration**: the fail-closed PRIL Stop
hook refuses to finish a feature run when a changed file falls outside it. A
human markdown document is the wrong home for that. A formatter can rewrap a
bullet, an inline description can turn a path into prose, and a fenced code block
looks authoritative while being invisible to the parser. All three happened in the
EasyTree pilot (PLUM-10), in both directions: authorized paths silently vanished
(false RED with a misleading "missing Allowed change scope"), and a wrapped prose
line silently became an allowed pattern (false GREEN).

So the machine-readable manifest is canonical. The canvas stays the human
document and may *describe* the scope, but it no longer governs it.

## Shape (schema 1)

```json
{
  "schema": 1,
  "feature": "my-feature",
  "allowed_change_scope": [
    "src/feature/**",
    "config/claude/tests/test_my_feature.sh",
    "docs/canvas/my-feature.canvas.md"
  ],
  "notes": "free text for humans; never parsed as configuration"
}
```

| key | required | meaning |
|---|---|---|
| `schema` | no (defaults to `1`) | manifest version. An unsupported version is a hard error, never a best-effort parse. |
| `feature` | no | when present it must equal the feature being checked, so a copied manifest cannot govern the wrong feature. |
| `allowed_change_scope` | **yes** | product paths/globs, repo-relative. One entry per path. |
| `governance_paths` | no | the feature's own governance artifacts, modelled separately (see below). |
| `generated_artifacts` | no | producer/output declarations for generated files (see below). |
| `notes` | no | human prose. Ignored by the guard. |
| `provenance` | no | the scope-change audit trail (see below). |

Unknown keys are **refused**, not ignored: in a security configuration a typo'd
key must not read as "not configured".

## Entry rules

Every entry must be a plain, repo-relative path or glob. The guard rejects, with
the entry index and the reason:

- a non-string entry (`7`, `null`, an object);
- an empty entry;
- a leading `/` (must be repo-relative);
- a `..` segment;
- a `\` separator (use `/`);
- embedded whitespace — that is prose, not a path;
- a control character;
- a pattern with no concrete path segment (`*`, `**`, `?*`, `[a-z]*`): it would
  legitimize the whole repository and defeat the gate.

Legitimate glob metacharacters keep working: `src/**/*.py`,
`fixtures/file[0-9].txt`, non-ASCII directory names.

An **empty** `allowed_change_scope` is reported as *missing*, never as a wildcard:
an empty allow-list authorizes nothing.

## Precedence — the manifest is first and final

1. `docs/scope/<feature>.scope.json` — canonical. When this file exists it is the
   **only** source.
2. `docs/canvas/<feature>.canvas.md`, section `Allowed change scope` — legacy.
3. `docs/traceability.md` — legacy.

A **broken** manifest does not fall back to the canvas. Falling back would let
anyone re-enable the fragile source by corrupting the canonical one, so the
manifest's authority has to survive its own errors.

Every result names its source, so "which configuration governs me?" is never a
guess:

```
PRIL scope check passed for feature 'x' (3 changed files, source=manifest=docs/scope/x.scope.json)
ERROR: changed files outside Allowed change scope: …; source=canvas=docs/canvas/x.canvas.md
```

## Migration from a canvas section

The legacy canvas path is **still supported** — existing features keep working
untouched. What changed is that nothing is discarded silently any more:

- a line the parser cannot use is reported with its **line number and cause**
  (`NOTE: docs/canvas/x.canvas.md line 24 '- `lib/` (the new module)': contains
  whitespace (looks like prose, not a path) — not used as an allowed-scope
  pattern; the canonical source is docs/scope/x.scope.json`);
- if the section exists but **no** line in it is usable, that is a classified
  `malformed` error naming each line — not the old, misleading "missing Allowed
  change scope".

To migrate a feature:

1. Run the guard once and read the `NOTE:`/`ERROR:` lines — they list exactly
   which canvas lines were never really part of the scope.
2. Create `docs/scope/<feature>.scope.json` with one clean entry per path,
   including the feature's own governance artifacts (canvas, PRD, vision, plan,
   evidence ledger, trace matrix) and the test files the build will add.
3. Verify before building:

   ```bash
   config/claude/bin/plumbline-scope-check --repo . --feature <slug> \
     --changed-files <(git diff --name-only)
   ```

4. Keep the canvas section as human documentation, or replace it with a pointer to
   the manifest. Either way it no longer governs the gate.

Note for authors: a bullet like ``- `config/claude/lib/` (the new module)`` was
never a working pattern — it produced a junk pattern that matched nothing. After
migration those lines are dropped loudly rather than silently, which can surface a
scope gap that was always there. That is the intended outcome; add the real path
to the manifest.

## Class separation and provenance (PLUM-12)

Two more keys make the manifest the *single source of truth* rather than one copy
among several:

```json
{
  "schema": 1,
  "feature": "my-feature",
  "allowed_change_scope": ["src/feature/**"],
  "governance_paths": [
    "docs/canvas/my-feature.canvas.md",
    "docs/reality/my-feature.evidence.jsonl",
    "CLAUDE.md"
  ],
  "provenance": [
    {
      "paths": ["src/feature/**", "docs/canvas/my-feature.canvas.md"],
      "origin": "requirements confirmation, session 2026-07-30",
      "decided_by": "product owner (human)",
      "decided_at": "2026-07-30T09:15:00Z",
      "reason": "confirmed feature surface plus its own canvas"
    }
  ]
}
```

- `governance_paths` — the feature's own governance artifacts. Both classes
  authorize a change; keeping them apart means a drift report can say **which
  class** a path belongs to instead of flattening a canvas into the product
  surface. A governance-looking path declared in `allowed_change_scope` is
  reported as a probable misclassification (visible, non-blocking).
- `provenance` — who authorized which paths, when, from where, and why. Validation
  is **opt-in** (`--require-provenance`) so existing manifests keep working; when
  enabled, every scope entry must be covered by a record, every record must carry
  all four fields non-empty, and `decided_at` must be ISO-8601.

## Plan-vs-scope gate (`plumbline-plan-check`)

Run before coding starts:

```bash
config/claude/bin/plumbline-plan-check --repo . --feature <slug> \
  --plan docs/plans/2026-07-30-<slug>.md [--canvas <path>] [--require-provenance]
```

It answers three questions in one place:

1. **Does the plan stay inside the confirmed scope?** Files the plan will touch are
   read from a `plumbline-touches` fenced block (`mode=declared`, exact) or, when
   absent, inferred from backticked paths in the prose (`mode=heuristic`, announced
   as such because an inferred candidate may be a read-only mention). Any path the
   scope does not authorize exits **3** and is named, together with the manifest to
   edit.
2. **Does the canvas contradict the manifest?** A canvas pattern the manifest does
   not authorize exits **3** — the canvas is documentation, the manifest decides.
   A canvas that documents a *subset* passes, and the extra manifest patterns are
   listed so the difference is visible rather than hidden.
3. **Is every scope decision attributable?** With `--require-provenance`, an
   unattributed entry, a missing field or an unparseable timestamp exits **4**.

Exit codes: `0` pass · `2` missing input (no scope, no plan) · `3` drift /
contradiction · `4` malformed input.

## Generated artifacts and provenance (PLUM-15)

The scope guard judges **paths**. It cannot tell a regenerated file from a hand-edited
one, so an allowed target path can still be changed the wrong WAY. Declare the
producer relationship and the provenance gate can:

```json
{
  "schema": 1,
  "feature": "contracts",
  "allowed_change_scope": [
    "pkg/openapi/v1.json",
    "pkg/src/openapi/**",
    "scripts/gen.sh"
  ],
  "generated_artifacts": [
    {
      "path": "pkg/openapi/v1.json",
      "producer": "pkg/src/openapi/**",
      "command": "./scripts/gen.sh",
      "deterministic": true
    }
  ]
}
```

| field | required | meaning |
|---|---|---|
| `path` | **yes** | the generated artifact. |
| `producer` | **yes** | path/glob of the source that legitimately produces it. Must itself be inside the allowed scope. |
| `command` | **yes** | the allowed generation command. |
| `deterministic` | no (default `true`) | whether the command is byte-reproducible. |

Run beside the scope gate:

```bash
config/claude/bin/plumbline-provenance-check --repo . --feature <slug> \
  --changed-files <list> [--verify-reproducible]
```

Four classes stay **separately visible**, because each needs a different fix:

| class | exit | meaning |
|---|---|---|
| `PROVENANCE_VIOLATION` | 3 | the artifact changed but nothing matching its producer did — a hand edit of generated output. The path is allowed; the production route is not. |
| `ARTIFACT_DRIFT` | 3 | the producer changed, but re-running the declared command does not reproduce the committed artifact. |
| `NONDETERMINISTIC_OUTPUT` | 3 | the command does not agree with itself across two consecutive runs, so drift cannot be attributed at all. |
| `MISSING_PRODUCER` | 3 | the producer glob matches no file, so the declared production route does not exist. |
| `PRODUCER_OUT_OF_SCOPE` | 4 | the producer is not inside the allowed scope, so the artifact could only ever change by an unauthorized route (the EYT-88 contradiction). |

A byte-level drift test alone cannot separate "changed" from "changed legitimately" —
that is exactly why provenance and drift remain two answers rather than one verdict.

**`--verify-reproducible` executes the declared command**, so it is opt-in. Without it
no command runs and the report says reproducibility was *not verified* rather than
implying it was. The check always restores the committed artifact, so it never leaves
the tree dirty.

**`deterministic: false`** skips the byte comparison entirely (a comparison against a
non-reproducible generator proves nothing) and reports `provenance ok, drift NOT
checked`. That makes the flag a potential bypass — declare non-determinism, never be
drift-checked again — so it deliberately never reads as a reproducibility pass.
