#!/usr/bin/env bash
# PLUM-15 contract tests: an allowed target path can still be changed the WRONG way.
#
# Measured starting state (2026-07-30): the scope guard models paths only -- one glob
# matcher, no producer/output relationship, no notion of an allowed generation command.
# In the EYT-88 pilot `packages/contracts/openapi/v1.json` was an allowed change target
# while its generator under `packages/contracts/src/openapi/**` was not, and a HAND edit
# of the generated file would have passed the scope gate despite being wrong.
#
# Contract:
#   * the manifest declares generated artifacts, their producer and the allowed
#     generation command (AC-1);
#   * a manual change to a generated output is reported as a provenance violation even
#     though its path is allowed (AC-2);
#   * a generator change plus a reproducible output is accepted when both are in scope
#     (AC-3);
#   * drift and provenance are separately visible classes (AC-4);
#   * manual edit, correct generator run, non-deterministic output and missing producer
#     are all covered (AC-5).
#
# Portability: bash-3.2 safe (NO $()-wrapped heredocs), shellcheck-clean.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"

# shellcheck source=lib.sh
. "$HERE/lib.sh"

echo "test_artifact_provenance"

PROV_BIN="$REPO_DIR/config/claude/bin/plumbline-provenance-check"
SCOPE_BIN="$REPO_DIR/config/claude/bin/plumbline-scope-check"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

assert_file "provenance-check CLI exists" "$PROV_BIN"

# A repo with a real generator: gen.sh reads the source and writes the artifact
# deterministically, so a correct run is byte-reproducible.
new_repo() {
  local name="$1" repo
  repo="$WORK/$name"
  mkdir -p "$repo/docs/scope" "$repo/pkg/src/openapi" "$repo/pkg/openapi" "$repo/scripts"
  git -C "$repo" init -q
  git -C "$repo" config user.email prov-test@example.com
  git -C "$repo" config user.name "Prov Test"
  printf 'paths:\n  /a: ok\n' >"$repo/pkg/src/openapi/spec.src"
  cat >"$repo/scripts/gen.sh" <<'EOF'
#!/usr/bin/env bash
# Deterministic generator: the artifact is a pure function of the source.
set -eu
cd "$(dirname "$0")/.."
{
  printf '{\n  "generated": true,\n'
  printf '  "source_sha1": "%s",\n' "$(shasum pkg/src/openapi/spec.src | cut -d' ' -f1)"
  printf '  "lines": %s\n}\n' "$(wc -l <pkg/src/openapi/spec.src | tr -d ' ')"
} >pkg/openapi/v1.json
EOF
  chmod +x "$repo/scripts/gen.sh"
  ( cd "$repo" && ./scripts/gen.sh )
  git -C "$repo" add -A
  git -C "$repo" commit -q -m "baseline: source, generator and generated artifact"
  printf '%s' "$repo"
}

write_manifest() {
  local repo="$1" feat="$2"
  cat >"$repo/docs/scope/$feat.scope.json" <<'EOF'
{
  "schema": 1,
  "feature": "gen",
  "allowed_change_scope": [
    "pkg/openapi/v1.json",
    "pkg/src/openapi/**",
    "scripts/gen.sh"
  ],
  "governance_paths": ["docs/scope/**"],
  "generated_artifacts": [
    {
      "path": "pkg/openapi/v1.json",
      "producer": "pkg/src/openapi/**",
      "command": "./scripts/gen.sh",
      "deterministic": true
    }
  ]
}
EOF
}

# run_prov <repo> <feature> [flags...] -- changed files come from real git status.
# The list lives OUTSIDE the repo: written inside, the list file itself would show up
# as an untracked, unignored change and read as out-of-scope.
run_prov() {
  local repo="$1" feat="$2"
  shift 2
  local list="$WORK/changed-$feat.txt"
  {
    git -C "$repo" diff --name-only
    git -C "$repo" diff --name-only --cached
    git -C "$repo" ls-files --others --exclude-standard
  } | sort -u >"$list"
  local outf="$WORK/prov.out"
  "$PROV_BIN" --repo "$repo" --feature "$feat" --changed-files "$list" "$@" \
    >"$outf" 2>&1
  PROV_RC=$?
  PROV_OUT="$(cat "$outf")"
}

# ---------------------------------------------------------------------------
# A. A manual edit of a generated output (AC-2) -- the pilot's wrong-way change.
# ---------------------------------------------------------------------------

repo="$(new_repo manual)"
write_manifest "$repo" gen
printf '{\n  "generated": true,\n  "hand": "edited"\n}\n' >"$repo/pkg/openapi/v1.json"

# Precondition: the path IS allowed, so the scope gate passes. The provenance gate
# must be what catches this -- that is the whole point of the ticket.
scope_out="$WORK/scope.out"
{
  git -C "$repo" diff --name-only
  git -C "$repo" ls-files --others --exclude-standard
} | sort -u >"$WORK/scope-changed.txt"
"$SCOPE_BIN" --repo "$repo" --feature gen --changed-files "$WORK/scope-changed.txt" \
  >"$scope_out" 2>&1
scope_rc=$?
assert_eq "precondition: the scope gate ALLOWS the hand-edited path" "0" "$scope_rc"
[ "$scope_rc" -eq 0 ] || printf 'DIAG scope: %s\n  changed: %s\n' \
  "$(cat "$scope_out")" "$(tr '\n' ' ' <"$WORK/scope-changed.txt")"

run_prov "$repo" gen
assert_eq "hand-edited generated artifact blocks (exit 3)" "3" "$PROV_RC"
assert_contains "hand edit is classified as a provenance violation" \
  "$PROV_OUT" "PROVENANCE_VIOLATION"
assert_contains "hand edit names the artifact" "$PROV_OUT" "pkg/openapi/v1.json"
assert_contains "hand edit names the producer that did not change" \
  "$PROV_OUT" "pkg/src/openapi/**"
assert_contains "hand edit names the allowed command" "$PROV_OUT" "./scripts/gen.sh"

# ---------------------------------------------------------------------------
# G. Generator change plus reproducible output (AC-3).
# ---------------------------------------------------------------------------

repo="$(new_repo regen)"
write_manifest "$repo" gen
printf 'paths:\n  /a: ok\n  /b: ok\n' >"$repo/pkg/src/openapi/spec.src"
( cd "$repo" && ./scripts/gen.sh )
run_prov "$repo" gen
assert_eq "producer change + regenerated output passes" "0" "$PROV_RC"
assert_contains "pass names the verified artifact" "$PROV_OUT" "pkg/openapi/v1.json"

# The same producer change with a HAND-WRITTEN output is not reproducible. Only the
# opt-in reproducibility check can tell these two apart, so it must be able to.
repo="$(new_repo notreproducible)"
write_manifest "$repo" gen
printf 'paths:\n  /a: ok\n  /b: ok\n' >"$repo/pkg/src/openapi/spec.src"
printf '{\n  "generated": true,\n  "faked": "by hand"\n}\n' >"$repo/pkg/openapi/v1.json"
run_prov "$repo" gen
assert_eq "producer changed, so path-level provenance alone passes" "0" "$PROV_RC"
assert_contains "path-level pass says reproducibility was NOT checked" \
  "$PROV_OUT" "not verified"
run_prov "$repo" gen --verify-reproducible
assert_eq "reproducibility check catches the faked output (exit 3)" "3" "$PROV_RC"
assert_contains "faked output is classified as drift, not provenance" \
  "$PROV_OUT" "ARTIFACT_DRIFT"
assert_not_contains "faked output is not misreported as a provenance violation" \
  "$PROV_OUT" "PROVENANCE_VIOLATION"

# AC-4: the two classes are separately visible. A run with BOTH problems must report
# both, not collapse them into one verdict.
repo="$(new_repo bothclasses)"
write_manifest "$repo" gen
cat >>"$repo/docs/scope/gen.scope.json.tmp" <<'EOF'
EOF
rm -f "$repo/docs/scope/gen.scope.json.tmp"
mkdir -p "$repo/pkg/src/other" "$repo/pkg/other"
# artifact 2: hand-edited (provenance); artifact 1: producer changed but output faked
# (drift). Both declared.
cat >"$repo/docs/scope/gen.scope.json" <<'EOF'
{
  "schema": 1,
  "feature": "gen",
  "allowed_change_scope": [
    "pkg/openapi/v1.json",
    "pkg/src/openapi/**",
    "pkg/other/v2.json",
    "pkg/src/other/**",
    "scripts/gen.sh"
  ],
  "generated_artifacts": [
    {
      "path": "pkg/openapi/v1.json",
      "producer": "pkg/src/openapi/**",
      "command": "./scripts/gen.sh",
      "deterministic": true
    },
    {
      "path": "pkg/other/v2.json",
      "producer": "pkg/src/other/**",
      "command": "./scripts/gen-other.sh",
      "deterministic": true
    }
  ]
}
EOF
printf 'src\n' >"$repo/pkg/src/other/spec.src"
cat >"$repo/scripts/gen-other.sh" <<'EOF'
#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
printf '{"other": "%s"}\n' "$(shasum pkg/src/other/spec.src | cut -d' ' -f1)" \
  >pkg/other/v2.json
EOF
chmod +x "$repo/scripts/gen-other.sh"
( cd "$repo" && ./scripts/gen-other.sh )
git -C "$repo" add -A
git -C "$repo" commit -q -m "second generated artifact"
# now: v1 producer changed + output faked (drift); v2 hand-edited (provenance)
printf 'paths:\n  /a: ok\n  /c: ok\n' >"$repo/pkg/src/openapi/spec.src"
printf '{\n  "faked": true\n}\n' >"$repo/pkg/openapi/v1.json"
printf '{"other": "hand-edited"}\n' >"$repo/pkg/other/v2.json"
run_prov "$repo" gen --verify-reproducible
assert_eq "both problems present: blocks" "3" "$PROV_RC"
assert_contains "both problems: provenance class reported" \
  "$PROV_OUT" "PROVENANCE_VIOLATION"
assert_contains "both problems: drift class reported" "$PROV_OUT" "ARTIFACT_DRIFT"
assert_contains "both problems: the drift artifact is named" \
  "$PROV_OUT" "pkg/openapi/v1.json"
assert_contains "both problems: the provenance artifact is named" \
  "$PROV_OUT" "pkg/other/v2.json"

# ---------------------------------------------------------------------------
# N. Non-deterministic output (AC-5) -- distinct from drift.
# ---------------------------------------------------------------------------

repo="$(new_repo nondet)"
mkdir -p "$repo/docs/scope"
cat >"$repo/scripts/gen-nondet.sh" <<'EOF'
#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
# A real-world footgun: the generator stamps a counter, so no two runs agree.
n=0
[ -f .gen-counter ] && n="$(cat .gen-counter)"
n=$((n + 1))
printf '%s' "$n" >.gen-counter
printf '{"run": %s}\n' "$n" >pkg/openapi/v1.json
EOF
chmod +x "$repo/scripts/gen-nondet.sh"
cat >"$repo/docs/scope/gen.scope.json" <<'EOF'
{
  "schema": 1,
  "feature": "gen",
  "allowed_change_scope": [
    "pkg/openapi/v1.json",
    "pkg/src/openapi/**",
    "scripts/gen-nondet.sh",
    ".gen-counter"
  ],
  "generated_artifacts": [
    {
      "path": "pkg/openapi/v1.json",
      "producer": "pkg/src/openapi/**",
      "command": "./scripts/gen-nondet.sh",
      "deterministic": true
    }
  ]
}
EOF
printf 'paths:\n  /a: ok\n  /d: ok\n' >"$repo/pkg/src/openapi/spec.src"
( cd "$repo" && ./scripts/gen-nondet.sh )
run_prov "$repo" gen --verify-reproducible
assert_eq "non-deterministic generator blocks (exit 3)" "3" "$PROV_RC"
assert_contains "non-determinism has its own class" \
  "$PROV_OUT" "NONDETERMINISTIC_OUTPUT"
assert_not_contains "non-determinism is not reported as drift" \
  "$PROV_OUT" "ARTIFACT_DRIFT"
assert_contains "non-determinism explains that two runs disagreed" \
  "$PROV_OUT" "two consecutive runs"

# A generator declared `deterministic: false` is accepted, but the reproducibility
# claim is explicitly withheld -- never silently assumed.
repo2="$(new_repo nondetdeclared)"
cp "$repo/scripts/gen-nondet.sh" "$repo2/scripts/gen-nondet.sh"
chmod +x "$repo2/scripts/gen-nondet.sh"
mkdir -p "$repo2/docs/scope"
sed 's/"deterministic": true/"deterministic": false/' \
  "$repo/docs/scope/gen.scope.json" >"$repo2/docs/scope/gen.scope.json"
printf 'paths:\n  /a: ok\n  /d: ok\n' >"$repo2/pkg/src/openapi/spec.src"
( cd "$repo2" && ./scripts/gen-nondet.sh )
run_prov "$repo2" gen --verify-reproducible
assert_eq "declared non-deterministic generator passes" "0" "$PROV_RC"
assert_contains "declared non-determinism withholds the reproducibility claim" \
  "$PROV_OUT" "deterministic=false"
# deterministic=false skips the byte comparison entirely -- a comparison against a
# non-reproducible generator would prove nothing. That makes the flag a potential
# BYPASS (declare non-determinism, never be drift-checked again), so the pass must
# never read as a reproducibility pass: it must say the claim is NOT made, and it must
# not emit the reproduces-byte-identically wording.
assert_contains "declared non-determinism states the claim is not made" \
  "$PROV_OUT" "NOT claimed"
assert_not_contains "declared non-determinism never claims byte-identity" \
  "$PROV_OUT" "byte-identically"
assert_not_contains "declared non-determinism is not reported as drift-verified" \
  "$PROV_OUT" "provenance+drift ok"

# ---------------------------------------------------------------------------
# P. Missing / out-of-scope producer (AC-5) -- the pilot's contradiction.
# ---------------------------------------------------------------------------

# The producer glob matches nothing in the repository.
repo="$(new_repo noproducer)"
mkdir -p "$repo/docs/scope"
cat >"$repo/docs/scope/gen.scope.json" <<'EOF'
{
  "schema": 1,
  "feature": "gen",
  "allowed_change_scope": ["pkg/openapi/v1.json", "pkg/nowhere/**"],
  "generated_artifacts": [
    {
      "path": "pkg/openapi/v1.json",
      "producer": "pkg/nowhere/**",
      "command": "./scripts/gen.sh",
      "deterministic": true
    }
  ]
}
EOF
printf '{\n  "x": 1\n}\n' >"$repo/pkg/openapi/v1.json"
run_prov "$repo" gen
assert_eq "producer that matches no file blocks (exit 3)" "3" "$PROV_RC"
assert_contains "missing producer has its own class" "$PROV_OUT" "MISSING_PRODUCER"
assert_contains "missing producer names the glob" "$PROV_OUT" "pkg/nowhere/**"

# The pilot's exact contradiction: the artifact is allowed, its producer is NOT.
repo="$(new_repo producerunscoped)"
mkdir -p "$repo/docs/scope"
cat >"$repo/docs/scope/gen.scope.json" <<'EOF'
{
  "schema": 1,
  "feature": "gen",
  "allowed_change_scope": ["pkg/openapi/v1.json"],
  "generated_artifacts": [
    {
      "path": "pkg/openapi/v1.json",
      "producer": "pkg/src/openapi/**",
      "command": "./scripts/gen.sh",
      "deterministic": true
    }
  ]
}
EOF
run_prov "$repo" gen
assert_eq "producer outside the allowed scope is a contradiction (exit 4)" \
  "4" "$PROV_RC"
assert_contains "unscoped producer is classified" \
  "$PROV_OUT" "PRODUCER_OUT_OF_SCOPE"
assert_contains "unscoped producer names the producer" \
  "$PROV_OUT" "pkg/src/openapi/**"

# ---------------------------------------------------------------------------
# B. Backward compatibility and classified input failures.
# ---------------------------------------------------------------------------

# A manifest with no generated_artifacts is unaffected.
repo="$(new_repo nogenerated)"
mkdir -p "$repo/docs/scope"
cat >"$repo/docs/scope/gen.scope.json" <<'EOF'
{"schema": 1, "feature": "gen", "allowed_change_scope": ["pkg/**", "scripts/**"]}
EOF
printf 'anything\n' >"$repo/pkg/openapi/v1.json"
run_prov "$repo" gen
assert_eq "no generated_artifacts declared: passes" "0" "$PROV_RC"
assert_contains "no declarations is stated, not silent" \
  "$PROV_OUT" "no generated artifacts"

# A changed file that is not a declared artifact is not the provenance gate's business.
repo="$(new_repo unrelated)"
write_manifest "$repo" gen
printf 'paths:\n  /a: ok\n  /e: ok\n' >"$repo/pkg/src/openapi/spec.src"
( cd "$repo" && ./scripts/gen.sh )
printf '#!/usr/bin/env bash\necho hi\n' >"$repo/scripts/unrelated.sh"
run_prov "$repo" gen
assert_eq "unrelated changed files do not trip the gate" "0" "$PROV_RC"

# Malformed declarations are classified, never ignored.
repo="$(new_repo baddecl)"
mkdir -p "$repo/docs/scope"
cat >"$repo/docs/scope/gen.scope.json" <<'EOF'
{
  "schema": 1,
  "feature": "gen",
  "allowed_change_scope": ["pkg/**"],
  "generated_artifacts": [{"path": "pkg/openapi/v1.json"}]
}
EOF
run_prov "$repo" gen
assert_eq "declaration missing producer/command: malformed exit 4" "4" "$PROV_RC"
assert_contains "incomplete declaration names the missing field" \
  "$PROV_OUT" "producer"

repo="$(new_repo badtype)"
mkdir -p "$repo/docs/scope"
cat >"$repo/docs/scope/gen.scope.json" <<'EOF'
{
  "schema": 1,
  "feature": "gen",
  "allowed_change_scope": ["pkg/**"],
  "generated_artifacts": "pkg/openapi/v1.json"
}
EOF
run_prov "$repo" gen
assert_eq "generated_artifacts of the wrong type: malformed exit 4" "4" "$PROV_RC"

# A failing generator command is classified as a tool failure, never as "clean".
repo="$(new_repo genfails)"
mkdir -p "$repo/docs/scope"
cat >"$repo/scripts/gen-broken.sh" <<'EOF'
#!/usr/bin/env bash
echo "generator exploded" >&2
exit 7
EOF
chmod +x "$repo/scripts/gen-broken.sh"
cat >"$repo/docs/scope/gen.scope.json" <<'EOF'
{
  "schema": 1,
  "feature": "gen",
  "allowed_change_scope": [
    "pkg/openapi/v1.json", "pkg/src/openapi/**", "scripts/gen-broken.sh"
  ],
  "generated_artifacts": [
    {
      "path": "pkg/openapi/v1.json",
      "producer": "pkg/src/openapi/**",
      "command": "./scripts/gen-broken.sh",
      "deterministic": true
    }
  ]
}
EOF
printf 'paths:\n  /a: ok\n  /f: ok\n' >"$repo/pkg/src/openapi/spec.src"
printf '{"x": 2}\n' >"$repo/pkg/openapi/v1.json"
run_prov "$repo" gen --verify-reproducible
assert_eq "failing generator is a tool failure (exit 2)" "2" "$PROV_RC"
assert_contains "generator failure names the command" \
  "$PROV_OUT" "./scripts/gen-broken.sh"
assert_contains "generator failure reports its exit code" "$PROV_OUT" "7"
assert_not_contains "generator failure does not claim reproducibility" \
  "$PROV_OUT" "reproducible"

# Reproducibility execution is OPT-IN: without the flag no command is ever run.
repo="$(new_repo noexec)"
mkdir -p "$repo/docs/scope"
cat >"$repo/scripts/gen-canary.sh" <<'EOF'
#!/usr/bin/env bash
set -eu
cd "$(dirname "$0")/.."
printf 'ran\n' >>.generator-was-executed
printf '{"x": 1}\n' >pkg/openapi/v1.json
EOF
chmod +x "$repo/scripts/gen-canary.sh"
cat >"$repo/docs/scope/gen.scope.json" <<'EOF'
{
  "schema": 1,
  "feature": "gen",
  "allowed_change_scope": [
    "pkg/openapi/v1.json", "pkg/src/openapi/**", "scripts/gen-canary.sh"
  ],
  "generated_artifacts": [
    {
      "path": "pkg/openapi/v1.json",
      "producer": "pkg/src/openapi/**",
      "command": "./scripts/gen-canary.sh",
      "deterministic": true
    }
  ]
}
EOF
printf 'paths:\n  /a: ok\n  /g: ok\n' >"$repo/pkg/src/openapi/spec.src"
printf '{"x": 1}\n' >"$repo/pkg/openapi/v1.json"
run_prov "$repo" gen
assert_eq "default run does not execute the generator" "0" "$PROV_RC"
assert "no canary file: the generator was never executed" \
  "[ ! -f '$repo/.generator-was-executed' ]"
run_prov "$repo" gen --verify-reproducible
assert "with the flag the generator IS executed (canary present)" \
  "[ -f '$repo/.generator-was-executed' ]"

# The reproducibility check must not leave the artifact modified behind it.
repo="$(new_repo restores)"
write_manifest "$repo" gen
printf 'paths:\n  /a: ok\n  /h: ok\n' >"$repo/pkg/src/openapi/spec.src"
( cd "$repo" && ./scripts/gen.sh )
before="$(shasum "$repo/pkg/openapi/v1.json" | cut -d' ' -f1)"
run_prov "$repo" gen --verify-reproducible
after="$(shasum "$repo/pkg/openapi/v1.json" | cut -d' ' -f1)"
assert_eq "reproducibility check passes on a real regeneration" "0" "$PROV_RC"
assert_eq "reproducibility check leaves the artifact byte-identical" \
  "$before" "$after"

finish "test_artifact_provenance"
