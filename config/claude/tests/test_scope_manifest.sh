#!/usr/bin/env bash
# PLUM-10 contract tests: the machine-critical Allowed Scope must live in an
# explicit, schema-validated manifest -- not in fragile markdown prose.
#
# Measured pilot defects this file pins (all four reproduced on 2026-07-30
# against the pre-fix plumbline_scope.py):
#   A  a `- /src/feature/**` bullet was SILENTLY discarded, and the guard then
#      reported the generic "missing Allowed change scope" -- a false RED with a
#      misleading diagnosis, because the author HAD declared a scope.
#   B  paths written inside a fenced code block were ignored the same way.
#   C  a formatter-wrapped line starting with `*` became a real allowed pattern,
#      which both hid the intended path AND authorized a prose-shaped path
#      ("and every generated artifact under .../v1.json" passed).
#   D  docs/scope/<feature>.scope.json LOST to the canvas: a manifest restricted
#      to src/api/** did not stop a canvas-allowed src/feature/** change.
#
# Contract after the fix:
#   * the manifest is the CANONICAL source and is checked FIRST;
#   * manifest problems are HARD, classified, and name the offending entry;
#   * the legacy canvas keeps working (backward compatible) but never discards a
#     line silently: every ignored line is named with its line number + cause;
#   * prose-shaped candidates are DROPPED (never widen the scope) rather than
#     silently accepted.
#
# Portability: bash-3.2 safe (NO $()-wrapped heredocs), shellcheck-clean.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"

# shellcheck source=lib.sh
. "$HERE/lib.sh"

echo "test_scope_manifest"

SCOPE_BIN="$REPO_DIR/config/claude/bin/plumbline-scope-check"

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

# new_repo <feature> -- create a git repo with docs/canvas + docs/scope dirs.
# Echoes the repo path.
new_repo() {
  local feat="$1" repo
  repo="$WORK/$feat"
  mkdir -p "$repo/docs/canvas" "$repo/docs/scope"
  git -C "$repo" init -q
  git -C "$repo" config user.email scope-test@example.com
  git -C "$repo" config user.name "Scope Test"
  printf '%s' "$repo"
}

# write_canvas <repo> <feature> -- body arrives on stdin, appended under the
# "Allowed change scope" heading. Heredocs are piped IN, never wrapped in $().
write_canvas() {
  local repo="$1" feat="$2" out="$1/docs/canvas/$2.canvas.md"
  {
    printf '# %s Canvas\n\n' "$feat"
    printf 'Status: user-confirmed\nConfirmed by user: yes\n\n'
    printf '## Allowed change scope\n'
    cat
  } >"$out"
}

# run_scope <repo> <feature> <changed-path>...
# Sets SCOPE_RC / SCOPE_OUT (stdout+stderr merged, which is what an operator sees).
run_scope() {
  local repo="$1" feat="$2"
  shift 2
  local list="$repo/changed.txt" p
  : >"$list"
  for p in "$@"; do printf '%s\n' "$p" >>"$list"; done
  local outf="$WORK/scope.out"
  "$SCOPE_BIN" --repo "$repo" --feature "$feat" \
    --changed-files "$list" >"$outf" 2>&1
  SCOPE_RC=$?
  SCOPE_OUT="$(cat "$outf")"
}

# ---------------------------------------------------------------------------
# M. The manifest is the canonical, schema-validated security configuration.
# ---------------------------------------------------------------------------

# D (reproduced): the manifest must WIN over the canvas, not lose to it.
repo="$(new_repo precedence)"
write_canvas "$repo" precedence <<'EOF'
- `src/feature/**`
EOF
cat >"$repo/docs/scope/precedence.scope.json" <<'EOF'
{
  "schema": 1,
  "feature": "precedence",
  "allowed_change_scope": ["src/api/**"]
}
EOF
run_scope "$repo" precedence src/feature/app.py
assert_eq "manifest wins over canvas: canvas-only path violates" \
  "3" "$SCOPE_RC"
assert_contains "manifest wins over canvas: manifest named as the source" \
  "$SCOPE_OUT" "docs/scope/precedence.scope.json"
run_scope "$repo" precedence src/api/handler.py
assert_eq "manifest wins over canvas: manifest path passes" "0" "$SCOPE_RC"
assert_contains "manifest pass names the manifest source" \
  "$SCOPE_OUT" "source=manifest"

# A (reproduced): an absolute pattern is a HARD, classified manifest error that
# names the entry -- never a silent drop that degrades to "missing".
repo="$(new_repo absolute)"
cat >"$repo/docs/scope/absolute.scope.json" <<'EOF'
{
  "schema": 1,
  "feature": "absolute",
  "allowed_change_scope": ["src/feature/**", "/src/api/**"]
}
EOF
run_scope "$repo" absolute src/feature/app.py
assert_eq "manifest absolute pattern: malformed exit 4" "4" "$SCOPE_RC"
assert_contains "manifest absolute pattern: names the entry index" \
  "$SCOPE_OUT" "entry #2"
assert_contains "manifest absolute pattern: names the cause" \
  "$SCOPE_OUT" "repo-relative"
assert_not_contains "manifest absolute pattern: not reported as missing" \
  "$SCOPE_OUT" "missing Allowed change scope"

# Traversal is refused with the same clarity.
repo="$(new_repo traversal)"
cat >"$repo/docs/scope/traversal.scope.json" <<'EOF'
{
  "schema": 1,
  "feature": "traversal",
  "allowed_change_scope": ["../outside/**"]
}
EOF
run_scope "$repo" traversal src/feature/app.py
assert_eq "manifest traversal pattern: malformed exit 4" "4" "$SCOPE_RC"
assert_contains "manifest traversal pattern: names the entry index" \
  "$SCOPE_OUT" "entry #1"
assert_contains "manifest traversal pattern: names the cause" \
  "$SCOPE_OUT" ".."

# A prose-shaped entry (embedded whitespace) is a HARD manifest error: the
# manifest is machine configuration, so guessing intent is not allowed.
repo="$(new_repo proseentry)"
cat >"$repo/docs/scope/proseentry.scope.json" <<'EOF'
{
  "schema": 1,
  "feature": "proseentry",
  "allowed_change_scope": ["and every generated artifact under pkg/openapi/**"]
}
EOF
run_scope "$repo" proseentry pkg/openapi/v1.json
assert_eq "manifest prose entry: malformed exit 4" "4" "$SCOPE_RC"
assert_contains "manifest prose entry: names whitespace as the cause" \
  "$SCOPE_OUT" "whitespace"

# Non-string entries, wrong shape, wrong schema and feature mismatch are all
# classified rather than coerced.
repo="$(new_repo nonstring)"
cat >"$repo/docs/scope/nonstring.scope.json" <<'EOF'
{"schema": 1, "feature": "nonstring", "allowed_change_scope": ["src/**", 7]}
EOF
run_scope "$repo" nonstring src/app.py
assert_eq "manifest non-string entry: malformed exit 4" "4" "$SCOPE_RC"
assert_contains "manifest non-string entry: names the entry index" \
  "$SCOPE_OUT" "entry #2"

repo="$(new_repo badschema)"
cat >"$repo/docs/scope/badschema.scope.json" <<'EOF'
{"schema": 99, "feature": "badschema", "allowed_change_scope": ["src/**"]}
EOF
run_scope "$repo" badschema src/app.py
assert_eq "manifest unsupported schema: malformed exit 4" "4" "$SCOPE_RC"
assert_contains "manifest unsupported schema: names the version" \
  "$SCOPE_OUT" "99"

repo="$(new_repo featmismatch)"
cat >"$repo/docs/scope/featmismatch.scope.json" <<'EOF'
{"schema": 1, "feature": "something-else", "allowed_change_scope": ["src/**"]}
EOF
run_scope "$repo" featmismatch src/app.py
assert_eq "manifest feature mismatch: malformed exit 4" "4" "$SCOPE_RC"
assert_contains "manifest feature mismatch: names the declared feature" \
  "$SCOPE_OUT" "something-else"

# A broad pattern stays refused inside the manifest (existing gate, not weakened).
repo="$(new_repo broadentry)"
cat >"$repo/docs/scope/broadentry.scope.json" <<'EOF'
{"schema": 1, "feature": "broadentry", "allowed_change_scope": ["src/**", "**"]}
EOF
run_scope "$repo" broadentry anything/at/all.py
assert_eq "manifest broad pattern: malformed exit 4" "4" "$SCOPE_RC"
assert_contains "manifest broad pattern: names the entry index" \
  "$SCOPE_OUT" "entry #2"

# Legitimate glob metacharacters and non-ASCII directory names still work: the
# fix must not narrow real patterns.
repo="$(new_repo specialchars)"
cat >"$repo/docs/scope/specialchars.scope.json" <<'EOF'
{
  "schema": 1,
  "feature": "specialchars",
  "allowed_change_scope": [
    "src/**/*.py",
    "fixtures/file[0-9].txt",
    "docs/uebersicht/**"
  ]
}
EOF
run_scope "$repo" specialchars src/deep/nested/app.py fixtures/file7.txt \
  docs/uebersicht/plan.md
assert_eq "manifest special chars: legitimate globs pass" "0" "$SCOPE_RC"

# Negative control: a BROKEN manifest must not silently degrade to the canvas.
# Falling back would let anyone re-enable the fragile source by corrupting the
# canonical one -- the manifest's authority has to survive its own errors.
repo="$(new_repo nofallback)"
write_canvas "$repo" nofallback <<'EOF'
- `src/feature/**`
EOF
cat >"$repo/docs/scope/nofallback.scope.json" <<'EOF'
{"schema": 1, "feature": "nofallback", "allowed_change_scope": ["/absolute/**"]}
EOF
run_scope "$repo" nofallback src/feature/app.py
assert_eq "broken manifest does NOT fall back to the canvas" "4" "$SCOPE_RC"
assert_contains "broken manifest names the manifest, not the canvas" \
  "$SCOPE_OUT" "docs/scope/nofallback.scope.json"
assert_not_contains "broken manifest does not report a canvas pass" \
  "$SCOPE_OUT" "scope check passed"

# Same for unparseable JSON: classified, never a fallback.
repo="$(new_repo brokenjson)"
write_canvas "$repo" brokenjson <<'EOF'
- `src/feature/**`
EOF
printf '{"schema": 1, "allowed_change_scope": [\n' \
  >"$repo/docs/scope/brokenjson.scope.json"
run_scope "$repo" brokenjson src/feature/app.py
assert_eq "truncated manifest JSON: malformed exit 4" "4" "$SCOPE_RC"
assert_contains "truncated manifest JSON: names the line" "$SCOPE_OUT" "line"

# An empty allow-list is "missing", not "everything".
repo="$(new_repo emptylist)"
cat >"$repo/docs/scope/emptylist.scope.json" <<'EOF'
{"schema": 1, "feature": "emptylist", "allowed_change_scope": []}
EOF
run_scope "$repo" emptylist src/app.py
assert_eq "manifest empty list: missing exit 2" "2" "$SCOPE_RC"

# ---------------------------------------------------------------------------
# L. Legacy canvas: still supported, but nothing is discarded silently.
# ---------------------------------------------------------------------------

# L1 backward compatibility: an ordinary canvas keeps working unchanged.
repo="$(new_repo legacyok)"
write_canvas "$repo" legacyok <<'EOF'
- `src/feature/**`
- `docs/`
EOF
run_scope "$repo" legacyok src/feature/app.py docs/notes.md
assert_eq "legacy canvas: still passes in-scope changes" "0" "$SCOPE_RC"
run_scope "$repo" legacyok src/billing/charge.py
assert_eq "legacy canvas: still blocks out-of-scope changes" "3" "$SCOPE_RC"

# A (reproduced) in the legacy path: the only declared pattern is absolute, so
# the effective scope is empty. That must be classified and name the line -- not
# reported as if the author had written no scope at all.
repo="$(new_repo legacyslash)"
write_canvas "$repo" legacyslash <<'EOF'
- `/src/feature/**`
EOF
run_scope "$repo" legacyslash src/feature/app.py
# Derive the expected line number from the file so the assertion cannot drift
# with the canvas preamble.
slash_line="$(grep -n 'src/feature' "$repo/docs/canvas/legacyslash.canvas.md" | cut -d: -f1)"
assert_eq "legacy absolute-only canvas: malformed exit 4" "4" "$SCOPE_RC"
assert_contains "legacy absolute-only canvas: names the line number" \
  "$SCOPE_OUT" "line $slash_line"
assert_contains "legacy absolute-only canvas: points at the manifest" \
  "$SCOPE_OUT" "docs/scope/legacyslash.scope.json"

# B (reproduced): paths inside a fenced code block are not bullets. They stay
# unparsed (guessing prose is not allowed) but the operator is told exactly that.
repo="$(new_repo legacyblock)"
write_canvas "$repo" legacyblock <<'EOF'
```
src/feature/**
docs/**
```
EOF
run_scope "$repo" legacyblock src/feature/app.py
assert_eq "legacy fenced-block canvas: malformed exit 4" "4" "$SCOPE_RC"
assert_contains "legacy fenced-block canvas: names the ignored code block" \
  "$SCOPE_OUT" "fenced code block"

# C (reproduced): a formatter-wrapped `*` line must NOT become a pattern, and
# must never authorize a prose-shaped path.
repo="$(new_repo legacyprose)"
write_canvas "$repo" legacyprose <<'EOF'
- `src/feature/**`
* and every generated artifact under pkg/openapi/**
EOF
run_scope "$repo" legacyprose src/feature/app.py
prose_line="$(grep -n 'and every generated' "$repo/docs/canvas/legacyprose.canvas.md" | cut -d: -f1)"
assert_eq "legacy prose line: valid bullet still passes" "0" "$SCOPE_RC"
assert_contains "legacy prose line: dropped line is named" \
  "$SCOPE_OUT" "line $prose_line"
assert_contains "legacy prose line: cause is named" \
  "$SCOPE_OUT" "whitespace"
run_scope "$repo" legacyprose "and every generated artifact under pkg/openapi/v1.json"
assert_eq "legacy prose line: prose-shaped path is NOT authorized" \
  "3" "$SCOPE_RC"

# An indented continuation (a wrapped bullet) is ignored by the parser; say so.
repo="$(new_repo legacywrap)"
write_canvas "$repo" legacywrap <<'EOF'
- `src/feature/**`
  `docs/really/long/path/**`
EOF
run_scope "$repo" legacywrap src/feature/app.py
wrap_line="$(grep -n 'really/long' "$repo/docs/canvas/legacywrap.canvas.md" | cut -d: -f1)"
assert_eq "legacy wrapped continuation: valid bullet still passes" "0" "$SCOPE_RC"
assert_contains "legacy wrapped continuation: ignored line is named" \
  "$SCOPE_OUT" "line $wrap_line"

# The canvas is documented as non-canonical: the pass message must say which
# source was actually used, so "which config governs me" is never a guess.
repo="$(new_repo legacysource)"
write_canvas "$repo" legacysource <<'EOF'
- `src/feature/**`
EOF
run_scope "$repo" legacysource src/feature/app.py
assert_contains "legacy canvas: pass names the canvas source" \
  "$SCOPE_OUT" "source=canvas"

finish "test_scope_manifest"
