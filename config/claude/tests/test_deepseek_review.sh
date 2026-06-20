#!/usr/bin/env bash
set -u
#
# Phase-1 BLACK-BOX acceptance contract for the DEEPSEEK-REVIEW council-body runner
# + typed presets module (Slice 2). Written BEFORE any implementation exists (TDD
# RED). The coder implements the runner/preset/resolver to satisfy EXACTLY this
# contract. RED until then: config/claude/lib/deepseek_review.py and
# config/claude/lib/council_presets.py are ABSENT, so every assertion below fails.
#
# THE TESTS ARE THE CONTRACT. If the plan/coder later conflicts with an assertion
# here, the test wins (derived independently from the FROZEN spec, not the plan).
#
# Spec sources (FROZEN, user-confirmed 2026-06-19):
#   docs/prd/deepseek-review-agent.prd.md      (REQ-DS-001..016)
#   docs/canvas/deepseek-review-agent.canvas.md (CAN-DS-*, RISK-DS-*, honesty invariant)
#
# Honesty: every assertion below is `integration-fake` (injected transport, injected
# catalog, 0 credits, 0 network). NONE claims real OpenRouter invocability or real
# diversity — that is earned only by the FULL-preset live smoke (REQ-DS-011), which
# lives OUTSIDE run_all.sh and is NOT exercised here.
#
# ===========================================================================
# SEAM / CLI CONTRACT THE CODER MUST IMPLEMENT  (mirror of council_inference.py)
# ===========================================================================
# A deterministic, NETWORK-FREE, KEY-FREE Python module
# config/claude/lib/deepseek_review.py exposing subcommands via the SAME argparse
# style as council_inference.py. The test resolves the module via the
# DEEPSEEK_REVIEW_MODULE env override (default: config/claude/lib/deepseek_review.py);
# the coder creates the module at that path. The typed presets live in a SECOND
# module config/claude/lib/council_presets.py (resolved by DEEPSEEK_PRESETS_MODULE,
# default config/claude/lib/council_presets.py) — typed, importable Python, NO
# markdown-parse layer (OQ-DS-4 RESOLVED).
#
# ---------------------------------------------------------------------------
# SUBCOMMANDS
#
#   run      Run ONE body OR ONE character.
#     --body <name>            concilium/<name>.md  (XOR --character)
#     --character <slug>       concilium/characters/<slug>/references/role-contract.md
#     --subject <text>         the user subject
#     --model <id>             explicit model override (highest precedence)
#     --dry-run                build messages / resolve only; NO transport
#     --json                   emit the JSON result object
#     --live                   arm the real transport (gated; see live-gate below)
#
#   preset   Resolve + run a named preset (default A).
#     --preset <A|B|C>
#     --subject <text>
#     --json
#     --live
#
# ---------------------------------------------------------------------------
# OFFLINE TEST SEAMS (0 credits, 0 network — REQUIRED on every transport/catalog path):
#
#   --inject-response '<json>'    A fake HTTP 200 chat/completions BODY. The only
#                                 way the offline suite drives a "successful"
#                                 completion. NO real urlopen.
#   --inject-error <class>        A fake transport FAILURE class, one of:
#                                   http-402 | http-429 | http-500 | timeout | malformed
#   --inject-catalog "<csv>"      A comma-separated list of catalog model ids that
#                                 FEEDS the dynamic resolver INSTEAD of a live GET to
#                                 OpenRouter (replaces council_backend._fetch_catalog_ids).
#                                 An EMPTY value ("") simulates an unreachable/empty
#                                 catalog (fail-closed, REQ-DS-015).
#   --inject-call-counter <path>  A file the transport seam writes its invocation
#                                 count to (0,1,...). Proves the network was NOT called
#                                 on budget/dry-run/live-gate-off paths and was called
#                                 exactly per-role on a preset.
#
# A transport-reaching `run` REQUIRES one of --inject-response / --inject-error in
# the offline suite. A run that reaches the transport with NEITHER injected MUST
# classify (never fall through to a real urlopen). The resolver, when it needs a
# catalog, REQUIRES --inject-catalog offline (never a live GET in this suite).
#
# ---------------------------------------------------------------------------
# JSON RESULT CONTRACT
#   run:    { "code": "<COUNCIL_*|classified>", "model": <id>,
#             "prompt_source": <path>, "position": <prose-or-null>,
#             "diversity": { "distinct_bases": <int>,
#                            "gate": "COUNCIL_DIVERSITY_OK|COUNCIL_DIVERSITY_UNAVAILABLE" } }
#   preset: { ..., "positions": [ {role, character, model, code, position}, ... ],
#             "diversity": { "distinct_bases": <int>, "gate": ... } }
#
# CLASSIFIED CODES (reused from council_inference.py / council_backend.py + new):
#   COUNCIL_INFERENCE_OK            success, non-empty completion
#   COUNCIL_BUDGET_EXCEEDED         estimate > per-call cap, NO call (REQ-DS-008)
#   COUNCIL_MODEL_UNAVAILABLE       5xx/malformed/2xx-no-completion/{error} (REQ-DS-007)
#   COUNCIL_DIVERSITY_UNAVAILABLE   <2 distinct bases over the resolved set (REQ-DS-006)
#   prompt-missing                  body file unreadable (REQ-DS-001)
#   character-missing               character dir / role-contract.md absent (REQ-DS-002)
#   xml-block-missing               "## Direkt kopierbarer Systemprompt" heading absent
#   xml-block-malformed             unclosed / malformed ```xml fence
#   xml-block-empty                 the extracted xml block is empty
#   unknown-preset                  unknown --preset (REQ-DS-004)
#   unknown-character-slug          a preset role names a slug not in the library
#   model-unresolvable              a role's model cannot be resolved (REQ-DS-004)
#   catalog-unreachable             injected/empty/unreachable catalog (REQ-DS-015)
#
# Exit codes: 0 for any successfully-CLASSIFIED outcome (classification IS success);
# no raw Python traceback may reach output; unknown subcommand / argparse error is non-zero.
#
# Per-feature kritische semantische Glättung (Beat 0 boundary gate):
#   The ONE real boundary (POST .../chat/completions AND the live catalog GET) is
#   SCOPED OUT of the offline suite by the spec (REQ-DS-009/010/015 injectable seams;
#   REQ-DS-011 full-preset smoke lives OUTSIDE run_all.sh). The slice-level
#   counter-thesis ("built but never invoked for real") is ALREADY COVERED by the
#   env-gated full-preset smoke (CAN-DS-EVN-PRE-010) and stays real-boundary-smoke in
#   the Reality Ledger — NOT re-asserted here. Everything below is PURE in-process
#   logic (load / extract / resolve / diversity-count / classify / redact) driven
#   against the INJECTED transport + INJECTED catalog. No invented network/NaN/overflow
#   failure modes beyond the spec's own classified ones.
# ===========================================================================

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"
cd "$REPO_DIR" || exit 1
# shellcheck source=config/claude/tests/lib.sh
source "$HERE/lib.sh"

MOD="${DEEPSEEK_REVIEW_MODULE:-config/claude/lib/deepseek_review.py}"
PRESETS_MOD="${DEEPSEEK_PRESETS_MODULE:-config/claude/lib/council_presets.py}"
SENTINEL="sk-or-LEAKCANARY-DO-NOT-PRINT-9f3c1a"
SUBJECT="Should we ship the council runner this slice?"

# A real, committed character slug for the happy path (verified present, roster=10).
REAL_SLUG="die-visionaerin"
# A real, committed body prompt (verified present).
REAL_BODY="market-realist"

# Per-test scratch dir for injected counters + synthetic character fixtures.
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

# ---------------------------------------------------------------------------
# CONTRACT DECISION (binding on the coder): for the REQ-DS-002 failure-branch
# fixtures (missing heading / malformed fence / empty block / missing dir) we need
# character dirs that DO NOT and MUST NOT exist in the READ-ONLY committed library
# (NGOAL-DS-009: concilium/characters/** is never edited/created by this slice). So
# the runner MUST accept a CHARACTERS-ROOT override env var, DEEPSEEK_CHARACTERS_DIR,
# pointing at an alternate characters root; default = "concilium/characters". The
# test builds synthetic fixtures under $SCRATCH and points the runner at them via
# that env var. (The happy path uses the REAL committed library, default root.)
# ---------------------------------------------------------------------------
FIXROOT="$SCRATCH/characters"
mkdir -p \
  "$FIXROOT/fix-good/references" \
  "$FIXROOT/fix-noheading/references" \
  "$FIXROOT/fix-malformed/references" \
  "$FIXROOT/fix-empty/references" \
  "$FIXROOT/fix-nofile"
# The fixture bodies are intentionally LITERAL (no shell expansion): the markdown
# must contain the verbatim heading + ```xml fence, and any $VAR-looking text must
# NOT expand. Single quotes + literal \n are deliberate (SC2016 disabled here).
# shellcheck disable=SC2016
{
  # good synthetic block (heading + closed xml fence with content)
  printf '## Direkt kopierbarer Systemprompt\n\n```xml\n<role>SYNTHETIC-GOOD-PROMPT-MARKER</role>\n```\n' \
    > "$FIXROOT/fix-good/references/role-contract.md"
  # heading absent
  printf '## Some Other Heading\n\n```xml\n<role>x</role>\n```\n' \
    > "$FIXROOT/fix-noheading/references/role-contract.md"
  # malformed: unclosed fence under the right heading
  printf '## Direkt kopierbarer Systemprompt\n\n```xml\n<role>unterminated never closes\n' \
    > "$FIXROOT/fix-malformed/references/role-contract.md"
  # empty: heading + an empty xml block
  printf '## Direkt kopierbarer Systemprompt\n\n```xml\n```\n' \
    > "$FIXROOT/fix-empty/references/role-contract.md"
}
# fix-nofile: directory exists but NO references/role-contract.md

# Helper: run the CLI under a clean, injected env (env -i) so no real key leaks and
# the test is hermetic regardless of the developer's shell (mirrors council_inference).
dsr() { # dsr <env-assignments-as-string> -- <cli args...>
  local envstr="$1"; shift
  [ "${1:-}" = "--" ] && shift
  # shellcheck disable=SC2086  # $envstr is intentionally word-split into KEY=VALUE tokens
  env -i PATH="$PATH" $envstr python3 "$MOD" "$@" 2>&1
}

# Helper: read an injected call-counter file (absent/empty => 0 calls).
calls() { if [ -s "$1" ]; then cat "$1"; else printf '0'; fi; }

printf 'DeepSeek-Review council runner — Phase-1 acceptance contract (RED until implemented)\n'

# --- Module presence (drives the RED state before implementation) -----------
assert_file "deepseek_review module exists" "$MOD"
assert_file "council_presets module exists" "$PRESETS_MOD"

# ===========================================================================
# 1. REQ-DS-001 — Body prompt -> messages; missing -> classified; traversal rejected.
#    These: "the body loads." Gegenthese: a runner that fabricates / silently
#    substitutes a body on a bad name builds a council on a fictional prompt — the
#    council's value is gone and nobody knows. Schärfung: assert messages carry the
#    REAL body text + subject with ZERO calls; a missing name classifies
#    prompt-missing (no fabrication); a traversal name is rejected BEFORE any read.
# ===========================================================================
CC_BODY="$SCRATCH/body.calls"
body_ok="$(dsr "OPENROUTER_API_KEY=$SENTINEL" -- run --body "$REAL_BODY" --subject "$SUBJECT" --dry-run --inject-call-counter "$CC_BODY" --json)"
assert_contains "REQ-DS-001 valid body builds a system message (role:system)" "$body_ok" '"system"'
assert_contains "REQ-DS-001 valid body builds a user message (role:user)" "$body_ok" '"user"'
assert_contains "REQ-DS-001 the user message carries the subject verbatim" "$body_ok" "$SUBJECT"
assert_contains "REQ-DS-001 prompt_source discloses the body file path" "$body_ok" "concilium/$REAL_BODY.md"
assert_eq "REQ-DS-001 body-build made ZERO transport calls" "0" "$(calls "$CC_BODY")"

# Missing body -> prompt-missing, never a fabricated/substituted body.
miss_body="$(dsr "OPENROUTER_API_KEY=$SENTINEL" -- run --body no-such-body-xyz --subject "$SUBJECT" --dry-run --json 2>&1)"
assert_contains "REQ-DS-001 missing body classifies prompt-missing" "$miss_body" "prompt-missing"
assert "REQ-DS-001 missing body does NOT fall back to a real body name" "! printf '%s' \"$miss_body\" | grep -qF '$REAL_BODY'"
assert "REQ-DS-001 missing body raises no Python traceback" "! printf '%s' \"$miss_body\" | grep -qE 'Traceback|FileNotFoundError'"

# Path traversal / absolute body name -> rejected BEFORE any read (slug-only).
trav_body="$(dsr "OPENROUTER_API_KEY=$SENTINEL" -- run --body '../../etc/passwd' --subject "$SUBJECT" --dry-run --json 2>&1)"
assert_contains "REQ-DS-001 traversal body name is rejected (classified, slug-only)" "$trav_body" "prompt-missing"
assert "REQ-DS-001 traversal body name never leaks /etc/passwd content" "! printf '%s' \"$trav_body\" | grep -qF 'root:'"
abs_body="$(dsr "OPENROUTER_API_KEY=$SENTINEL" -- run --body '/etc/hostname' --subject "$SUBJECT" --dry-run --json 2>&1)"
assert_contains "REQ-DS-001 absolute body path is rejected (classified, slug-only)" "$abs_body" "prompt-missing"

# ===========================================================================
# 2. REQ-DS-002 — Character XML extraction; ALL failure branches classified distinctly.
#    These: "a character can run as a body." Gegenthese (RISK-DS-CHR-012): a brittle
#    parser silently yields a partial/wrong/empty system prompt — a body presented as
#    valid that is actually broken. Schärfung: the REAL slug extracts the FIRST xml
#    block under the heading as the system prompt; each malformed case classifies its
#    OWN distinct error and NEVER fabricates a prompt.
# ===========================================================================
char_ok="$(dsr "OPENROUTER_API_KEY=$SENTINEL" -- run --character "$REAL_SLUG" --subject "$SUBJECT" --dry-run --json)"
# The extracted system prompt must be the XML block content of the real character.
assert_contains "REQ-DS-002 valid slug extracts the xml block as the system prompt" "$char_ok" '<role>'
assert_contains "REQ-DS-002 extracted prompt is the visionaerin role (real content)" "$char_ok" 'Die Visionaerin'
assert_contains "REQ-DS-002 character run builds the user message with the subject" "$char_ok" "$SUBJECT"
assert_contains "REQ-DS-002 prompt_source discloses the role-contract path" "$char_ok" "concilium/characters/$REAL_SLUG/references/role-contract.md"

# Synthetic-good (alternate root) must extract the marker, proving the heading+fence parse.
good="$(dsr "OPENROUTER_API_KEY=$SENTINEL DEEPSEEK_CHARACTERS_DIR=$FIXROOT" -- run --character fix-good --subject "$SUBJECT" --dry-run --json)"
assert_contains "REQ-DS-002 good synthetic block extracts its xml content" "$good" 'SYNTHETIC-GOOD-PROMPT-MARKER'

# Missing character directory -> character-missing.
miss_dir="$(dsr "OPENROUTER_API_KEY=$SENTINEL DEEPSEEK_CHARACTERS_DIR=$FIXROOT" -- run --character no-such-slug --subject "$SUBJECT" --dry-run --json 2>&1)"
assert_contains "REQ-DS-002 missing character dir classifies character-missing" "$miss_dir" "character-missing"
assert "REQ-DS-002 missing character dir does not fabricate a prompt" "! printf '%s' \"$miss_dir\" | grep -qF 'SYNTHETIC-GOOD-PROMPT-MARKER'"

# Directory present but role-contract.md absent -> character-missing.
nofile="$(dsr "OPENROUTER_API_KEY=$SENTINEL DEEPSEEK_CHARACTERS_DIR=$FIXROOT" -- run --character fix-nofile --subject "$SUBJECT" --dry-run --json 2>&1)"
assert_contains "REQ-DS-002 missing role-contract.md classifies character-missing" "$nofile" "character-missing"

# Heading absent -> xml-block-missing (distinct from character-missing).
noheading="$(dsr "OPENROUTER_API_KEY=$SENTINEL DEEPSEEK_CHARACTERS_DIR=$FIXROOT" -- run --character fix-noheading --subject "$SUBJECT" --dry-run --json 2>&1)"
assert_contains "REQ-DS-002 absent heading classifies xml-block-missing" "$noheading" "xml-block-missing"
assert "REQ-DS-002 absent-heading is NOT collapsed into character-missing" "! printf '%s' \"$noheading\" | grep -qF 'character-missing'"

# Malformed/unclosed fence -> xml-block-malformed (no silent truncation).
malformed="$(dsr "OPENROUTER_API_KEY=$SENTINEL DEEPSEEK_CHARACTERS_DIR=$FIXROOT" -- run --character fix-malformed --subject "$SUBJECT" --dry-run --json 2>&1)"
assert_contains "REQ-DS-002 unclosed xml fence classifies xml-block-malformed" "$malformed" "xml-block-malformed"
assert "REQ-DS-002 malformed fence does not leak a partial truncated prompt as valid" "! printf '%s' \"$malformed\" | grep -qF 'COUNCIL_INFERENCE_OK'"
assert "REQ-DS-002 malformed fence raises no Python traceback" "! printf '%s' \"$malformed\" | grep -qE 'Traceback'"

# Empty extracted block -> xml-block-empty (distinct from malformed).
emptyb="$(dsr "OPENROUTER_API_KEY=$SENTINEL DEEPSEEK_CHARACTERS_DIR=$FIXROOT" -- run --character fix-empty --subject "$SUBJECT" --dry-run --json 2>&1)"
assert_contains "REQ-DS-002 empty xml block classifies xml-block-empty" "$emptyb" "xml-block-empty"
assert "REQ-DS-002 empty-block is NOT collapsed into xml-block-malformed" "! printf '%s' \"$emptyb\" | grep -qF 'xml-block-malformed'"

# Traversal slug -> rejected before read (classified).
trav_char="$(dsr "OPENROUTER_API_KEY=$SENTINEL DEEPSEEK_CHARACTERS_DIR=$FIXROOT" -- run --character '../../etc' --subject "$SUBJECT" --dry-run --json 2>&1)"
assert_contains "REQ-DS-002 traversal slug is rejected (classified character-missing)" "$trav_char" "character-missing"
assert "REQ-DS-002 traversal slug never leaks /etc content" "! printf '%s' \"$trav_char\" | grep -qF 'root:'"

# ===========================================================================
# 3. REQ-DS-015 — Dynamic resolver over an INJECTED catalog (0 network), per branch.
#    These: "there is a default model." Gegenthese: a resolver that hardcodes a stale
#    id (the OD-3 / Slice-1 sin) or silently picks a paid/non-:free id re-introduces
#    cost + dead-default risk. Schärfung: assert the EXACT chosen id per branch;
#    skip-unavailable-family; free-route fallback; fail-closed on unreachable; and
#    that no non-:free id is ever auto-selected.
# ===========================================================================
# Branch A: DeepSeek-v4 :free present -> picks DeepSeek (TOP preference).
cat_ds='deepseek/deepseek-v4:free,qwen/qwen3-235b:free,moonshotai/kimi-k2-7:free'
res_ds="$(dsr "OPENROUTER_API_KEY=$SENTINEL" -- run --body "$REAL_BODY" --subject "$SUBJECT" --dry-run --inject-catalog "$cat_ds" --json)"
assert_contains "REQ-DS-015 DeepSeek :free present -> resolver picks the DeepSeek id" "$res_ds" "deepseek/deepseek-v4:free"

# Branch B: DeepSeek ABSENT but Qwen3.x :free present -> skip-unavailable-family -> Qwen.
cat_qwen='qwen/qwen3-235b:free,moonshotai/kimi-k2-7:free'
res_qwen="$(dsr "OPENROUTER_API_KEY=$SENTINEL" -- run --body "$REAL_BODY" --subject "$SUBJECT" --dry-run --inject-catalog "$cat_qwen" --json)"
assert_contains "REQ-DS-015 DeepSeek absent, Qwen3 :free present -> resolver picks Qwen" "$res_qwen" "qwen/qwen3-235b:free"
assert "REQ-DS-015 skip-unavailable-family did NOT pick an absent DeepSeek id" "! printf '%s' \"$res_qwen\" | grep -qF 'deepseek'"

# Branch C: NONE of the five preferred families :free, but some :free id exists ->
#           OpenRouter free-route fallback (picks an available :free id).
cat_other='someorg/random-model:free,another/thing:free'
res_other="$(dsr "OPENROUTER_API_KEY=$SENTINEL" -- run --body "$REAL_BODY" --subject "$SUBJECT" --dry-run --inject-catalog "$cat_other" --json)"
assert_contains "REQ-DS-015 no preferred family :free -> free-route fallback picks a :free id" "$res_other" ":free"
assert "REQ-DS-015 free-route fallback chose a :free id (never a paid id)" "! printf '%s' \"$res_other\" | grep -qE '\"model\": *\"[^\"]*[^e]\",' "

# Branch D: EMPTY / unreachable injected catalog -> fail-closed classified code
#           (NOT a stale/unverified pick).
res_empty="$(dsr "OPENROUTER_API_KEY=$SENTINEL" -- run --body "$REAL_BODY" --subject "$SUBJECT" --dry-run --inject-catalog "" --json 2>&1)"
assert_contains "REQ-DS-015 empty/unreachable catalog fails closed (catalog-unreachable)" "$res_empty" "catalog-unreachable"
assert "REQ-DS-015 unreachable catalog does NOT silently pick the stale Slice-1 default" "! printf '%s' \"$res_empty\" | grep -qF 'meta-llama/llama-3.1-8b-instruct:free'"
assert "REQ-DS-015 unreachable catalog raises no Python traceback" "! printf '%s' \"$res_empty\" | grep -qE 'Traceback'"

# Branch E: a catalog containing ONLY non-:free (paid) ids -> resolver must NOT
#           auto-select a paid id; it fails closed (no :free available).
cat_paid='deepseek/deepseek-v4,qwen/qwen3-235b'
res_paid="$(dsr "OPENROUTER_API_KEY=$SENTINEL" -- run --body "$REAL_BODY" --subject "$SUBJECT" --dry-run --inject-catalog "$cat_paid" --json 2>&1)"
assert "REQ-DS-015 resolver NEVER auto-selects a non-:free (paid) id" "! printf '%s' \"$res_paid\" | grep -qE '\"model\": *\"deepseek/deepseek-v4\"'"

# The named preference list must be an editable constant in the module source.
assert "REQ-DS-015 module source exposes a NAMED editable preference-order family constant" "grep -qiE 'PREFERENCE|PREFERRED|FAMILY|FAMILIES' '$MOD' '$PRESETS_MOD'"
assert "REQ-DS-015 the preference constant names DeepSeek" "grep -qi 'deepseek' '$MOD' '$PRESETS_MOD'"
assert "REQ-DS-015 the preference constant names Qwen" "grep -qi 'qwen' '$MOD' '$PRESETS_MOD'"

# --- Updated free-model family preference (verified-current strong free families) ---
# These: "the resolver prefers the right free families." Gegenthese: the named list
# went stale (Slice-2 sin, replicated) -- its families are no longer in the live free
# catalog, so the resolver silently drops to the arbitrary free-route fallback and the
# council's "preferred strong free model" guarantee is gone, invisibly. Schaerfung: the
# constant source must NAME the verified-current strong families and must NO LONGER name
# the catalog-absent stale ones (kimi / glm-5) it is replacing. (Mirrors the existing
# names-DeepSeek / names-Qwen assertions; same integration-fake source-grep honesty.)
# RED now: the strong families are absent and the stale families are still present.
assert "FREE-PREF the preference constant names GPT-OSS (new strong free family)" "grep -qi 'gpt-oss' '$MOD' '$PRESETS_MOD'"
assert "FREE-PREF the preference constant names Nemotron (new strong free family)" "grep -qi 'nemotron' '$MOD' '$PRESETS_MOD'"
assert "FREE-PREF the preference constant names Gemma (new strong free family)" "grep -qi 'gemma' '$MOD' '$PRESETS_MOD'"
assert "FREE-PREF the preference constant names Llama (new strong free family)" "grep -qi 'llama' '$MOD' '$PRESETS_MOD'"
# Stale, catalog-absent families being DROPPED must no longer be named in the constant.
assert "FREE-PREF the preference constant NO LONGER names the stale Kimi family" "! grep -qi 'kimi' '$MOD' '$PRESETS_MOD'"
assert "FREE-PREF the preference constant NO LONGER names the stale GLM-5 family" "! grep -qi 'glm-5' '$MOD' '$PRESETS_MOD'"

# ===========================================================================
# 4. PRECEDENCE — explicit --model > env (COUNCIL_INFERENCE_MODEL) > resolver.
#    These: "you can override the model." Gegenthese: a resolver that overrides an
#    explicit user model defeats the override and may pick something else. Schärfung:
#    with an injected catalog (resolver would pick DeepSeek), an explicit --model
#    and an env model EACH win over the resolver's catalog pick.
# ===========================================================================
prec_flag="$(dsr "OPENROUTER_API_KEY=$SENTINEL" -- run --body "$REAL_BODY" --subject "$SUBJECT" --model vendor/explicit-model --dry-run --inject-catalog "$cat_ds" --json)"
assert_contains "REQ-DS-005/015 explicit --model wins over the resolver catalog pick" "$prec_flag" "vendor/explicit-model"
assert "REQ-DS-005/015 explicit --model means the resolver's DeepSeek pick is NOT used" "! printf '%s' \"$prec_flag\" | grep -qF 'deepseek/deepseek-v4:free'"

prec_env="$(dsr "OPENROUTER_API_KEY=$SENTINEL COUNCIL_INFERENCE_MODEL=vendor/env-model" -- run --body "$REAL_BODY" --subject "$SUBJECT" --dry-run --inject-catalog "$cat_ds" --json)"
assert_contains "REQ-DS-005/015 env COUNCIL_INFERENCE_MODEL wins over the resolver catalog pick" "$prec_env" "vendor/env-model"
assert "REQ-DS-005/015 env model means the resolver's DeepSeek pick is NOT used" "! printf '%s' \"$prec_env\" | grep -qF 'deepseek/deepseek-v4:free'"

# ===========================================================================
# 5. REQ-DS-004/006 — Preset resolution roster + fail-closed branches + diversity.
#    These: "a preset resolves to a roster." Gegenthese: a preset that silently drops
#    an unresolvable role / substitutes a character / collapses to one model lets a
#    broken or non-diverse council run unnoticed. Schärfung: assert the EXACT preset-A
#    roster; each fail-closed branch names its distinct error; diversity over the
#    resolved set proceeds at >=2 bases and aborts at <2.
# ===========================================================================
# Preset A roster (exact 4 slugs, role order preserved) — resolve only, no calls.
presetA="$(dsr "OPENROUTER_API_KEY=$SENTINEL" -- preset --preset A --subject "$SUBJECT" --dry-run --inject-catalog "$cat_ds" --json)"
assert_contains "REQ-DS-003/004 preset A resolves die-visionaerin" "$presetA" "die-visionaerin"
assert_contains "REQ-DS-003/004 preset A resolves der-pruefer" "$presetA" "der-pruefer"
assert_contains "REQ-DS-003/004 preset A resolves der-nutzeranwalt" "$presetA" "der-nutzeranwalt"
assert_contains "REQ-DS-003/004 preset A resolves die-macherin" "$presetA" "die-macherin"

# Unknown preset -> unknown-preset (no silent default to A).
unkp="$(dsr "OPENROUTER_API_KEY=$SENTINEL" -- preset --preset ZZZ --subject "$SUBJECT" --dry-run --inject-catalog "$cat_ds" --json 2>&1)"
assert_contains "REQ-DS-004 unknown preset classifies unknown-preset" "$unkp" "unknown-preset"
assert "REQ-DS-004 unknown preset does NOT silently resolve preset A's roster" "! printf '%s' \"$unkp\" | grep -qF 'die-visionaerin'"

# Diversity OK: resolver yields >=2 distinct base models across roles -> proceed.
# (Injected catalog with two distinct preferred families; resolver picks differ per role
#  only if per-role models differ — preset roles without per-role models all resolve to
#  the same top free pick, so to prove the >=2 path the preset must carry >=2 distinct
#  per-role model overrides OR the test injects distinct ids. We assert the gate FIELD
#  and the OK code when the resolved set has >=2 bases.)
assert_contains "REQ-DS-006 preset result exposes a diversity block with distinct_bases" "$presetA" '"distinct_bases"'
assert_contains "REQ-DS-006 preset result exposes the diversity gate field" "$presetA" '"gate"'

# Diversity UNAVAILABLE: force every role to the SAME single base -> <2 distinct -> abort.
# A catalog with exactly ONE :free family forces every role's resolver pick to the same
# base, collapsing distinct_base_count to 1.
cat_single='deepseek/deepseek-v4:free'
presetSame="$(dsr "OPENROUTER_API_KEY=$SENTINEL" -- preset --preset A --subject "$SUBJECT" --dry-run --inject-catalog "$cat_single" --json 2>&1)"
assert_contains "REQ-DS-006 all-roles-same-base collapses to COUNCIL_DIVERSITY_UNAVAILABLE" "$presetSame" "COUNCIL_DIVERSITY_UNAVAILABLE"

# RISK-B-007 disclosure carried verbatim from concilium.md:104-107 (HIGH-2).
assert_contains "REQ-DS-006 diversity disclosure carries the necessary-not-sufficient wording" "$presetSame" "necessary-not-sufficient"
assert_contains "REQ-DS-006 diversity disclosure carries the 'does not prove real model diversity' wording" "$presetSame" "does not prove real model diversity"

# ===========================================================================
# 5b. FREE-PREF -- Updated strong-free-family resolution across distinct roles.
#    These: "a deepseek-absent free catalog of the strong families resolves a diverse
#    roster." Gegenthese: with the stale preference list, only Qwen matches a named
#    family; the other three strong ids resolve only via the ARBITRARY free-route
#    fallback (sorted-order pick), so the resolver never PREFERS gpt-oss/nemotron/gemma
#    by name -- it just happens to grab whichever :free ids sort first, and gpt-oss (which
#    sorts AFTER gemma/llama/nemotron/qwen) is silently dropped from the 4-role roster.
#    Schaerfung: inject a deepseek-ABSENT catalog of EXACTLY the new strong families and
#    assert preset A resolves the FIRST-FOUR-PREFERRED named families
#    (qwen3 + gpt-oss + nemotron + gemma), with 4 distinct bases + diversity OK, and that
#    llama (the 5th preference) is NOT picked for the 4-role roster. This is the
#    discriminator: the stale list picks llama and drops gpt-oss; the updated list picks
#    gpt-oss and drops llama.
#    RED now: gpt-oss is absent from the roster (free-route picks llama instead).
#    Beat 0 (boundary gate): PURE in-process resolution over an INJECTED catalog
#    (0 network, 0 credits) -- same integration-fake honesty as the rest of the suite.
# ===========================================================================
# DeepSeek (top preference) is ABSENT here -> skip-unavailable-family -> the resolver
# walks to the next preferred-present families. Only the four strong :free families plus
# qwen are offered; deepseek is intentionally NOT in this catalog.
cat_strong='qwen/qwen3-coder:free,openai/gpt-oss-120b:free,nvidia/nemotron-3-super-120b-a12b:free,google/gemma-4-26b-a4b-it:free,meta-llama/llama-3.3-70b-instruct:free'
presetStrong="$(dsr "OPENROUTER_API_KEY=$SENTINEL" -- preset --preset A --subject "$SUBJECT" --dry-run --inject-catalog "$cat_strong" --json)"
# The four FIRST-PREFERRED-present strong families each resolve into the roster.
assert_contains "FREE-PREF preset A resolves the Qwen3 strong free id" "$presetStrong" "qwen/qwen3-coder:free"
assert_contains "FREE-PREF preset A resolves the GPT-OSS strong free id (named-preferred, not free-route)" "$presetStrong" "openai/gpt-oss-120b:free"
assert_contains "FREE-PREF preset A resolves the Nemotron strong free id" "$presetStrong" "nvidia/nemotron-3-super-120b-a12b:free"
assert_contains "FREE-PREF preset A resolves the Gemma strong free id" "$presetStrong" "google/gemma-4-26b-a4b-it:free"
# Llama is the 5th preference; with only 4 roles it must NOT displace a higher-preferred
# family. The stale list (which lacks gpt-oss as a named family) picks llama via the
# sorted free-route fallback -> this FAILS now and passes once gpt-oss is preferred.
assert "FREE-PREF the 5th-preferred Llama is NOT picked for the 4-role roster (gpt-oss outranks it)" "! printf '%s' \"$presetStrong\" | grep -qF 'meta-llama/llama-3.3-70b-instruct:free'"
# DeepSeek (top, absent) must not be fabricated into the roster.
assert "FREE-PREF absent DeepSeek is not fabricated into the strong-catalog roster" "! printf '%s' \"$presetStrong\" | grep -qF 'deepseek'"
# Four distinct strong families -> diversity floor met across the resolved set.
assert_contains "FREE-PREF strong-family roster yields 4 distinct bases" "$presetStrong" '"distinct_bases": 4'
assert_contains "FREE-PREF strong-family roster passes the diversity gate" "$presetStrong" "COUNCIL_DIVERSITY_OK"

# ===========================================================================
# 6. MEDIUM-1 — FALSIFYING no-Claude-fallback assertion (RISK-DS-PRE-015).
#    These: "unresolvable roles are handled." Gegenthese: a silent Claude substitution
#    on an unresolvable role defeats the WHOLE point (uncorrelated non-Claude cognition)
#    AND is invisible. Schärfung: an all-unavailable preset yields ONLY classified codes
#    and ZERO Claude-family ids in output; AND the runner SOURCE contains no Claude-family
#    literal in any fallback branch. FAILS if a Claude-fallback path is ever introduced.
# ===========================================================================
# All roles unresolvable: empty catalog + no per-role/env/explicit model => fail-closed.
allunavail="$(dsr "OPENROUTER_API_KEY=$SENTINEL" -- preset --preset A --subject "$SUBJECT" --dry-run --inject-catalog "" --json 2>&1)"
assert "MEDIUM-1 all-unavailable preset returns a classified code (catalog-unreachable / model-unresolvable)" "printf '%s' \"$allunavail\" | grep -qE 'catalog-unreachable|model-unresolvable|COUNCIL_[A-Z_]+'"
# FALSIFIER: no anthropic/ or claude id appears anywhere in the classified-failure output.
assert "MEDIUM-1 no anthropic/* model id leaks into the all-unavailable output" "! printf '%s' \"$allunavail\" | grep -qiE 'anthropic/'"
assert "MEDIUM-1 no claude-* model id leaks into the all-unavailable output" "! printf '%s' \"$allunavail\" | grep -qiE 'claude'"
# FALSIFIER (source): no Claude-family literal in the runner OR presets source (any fallback branch).
assert "MEDIUM-1 runner source contains NO anthropic/ model literal (no Claude-fallback path)" "! grep -qiE 'anthropic/|claude-[0-9]|claude-(opus|sonnet|haiku)' '$MOD'"
assert "MEDIUM-1 presets source contains NO anthropic/ model literal (no Claude-fallback path)" "! grep -qiE 'anthropic/|claude-[0-9]|claude-(opus|sonnet|haiku)' '$PRESETS_MOD'"

# Unknown character slug inside a preset round trip -> unknown-character-slug, no Claude sub.
# (Driven by a preset whose role references a synthetic-missing slug; the runner must
#  classify, never substitute. We assert the named error appears for a known-bad preset
#  composition surfaced through the resolver's fail-closed path.)
assert "MEDIUM-1 unknown-character-slug is a NAMED classified error in the contract" "grep -qi 'unknown-character-slug' '$MOD'"

# ===========================================================================
# 7. REQ-DS-007 — Position wrapping; bad responses -> COUNCIL_MODEL_UNAVAILABLE.
#    These: "a completion becomes a position." Gegenthese: a 2xx-no-completion or an
#    {error:...} envelope sold as a real position fabricates a council position from
#    nothing, and may leak the body/error text. Schärfung: an injected completion is
#    wrapped with model + prompt_source; a bad response classifies UNAVAILABLE and
#    NEVER fabricates a position nor leaks the body.
# ===========================================================================
CC_WRAP="$SCRATCH/wrap.calls"
wrap_ok="$(dsr "OPENROUTER_API_KEY=$SENTINEL" -- run --body "$REAL_BODY" --subject "$SUBJECT" --model vendor/m --inject-response '{"choices":[{"message":{"content":"POSITION-PROSE-MARKER"}}],"usage":{"prompt_tokens":40,"completion_tokens":3}}' --inject-call-counter "$CC_WRAP" --json)"
assert_contains "REQ-DS-007 a completion is wrapped as the position prose" "$wrap_ok" "POSITION-PROSE-MARKER"
assert_contains "REQ-DS-007 the wrapped position discloses the model id" "$wrap_ok" "vendor/m"
assert_contains "REQ-DS-007 the wrapped position discloses the prompt_source" "$wrap_ok" "concilium/$REAL_BODY.md"
assert_eq "REQ-DS-007 a wrapped completion made exactly ONE transport call" "1" "$(calls "$CC_WRAP")"

# 2xx no usable completion -> COUNCIL_MODEL_UNAVAILABLE, no fabricated position.
wrap_empty="$(dsr "OPENROUTER_API_KEY=$SENTINEL" -- run --body "$REAL_BODY" --subject "$SUBJECT" --model vendor/m --inject-response '{"choices":[{"message":{"content":""}}],"usage":{"prompt_tokens":40,"completion_tokens":0}}' --json 2>&1)"
assert_contains "REQ-DS-007 2xx empty completion -> COUNCIL_MODEL_UNAVAILABLE" "$wrap_empty" "COUNCIL_MODEL_UNAVAILABLE"
assert "REQ-DS-007 2xx empty completion is NOT a false success" "! printf '%s' \"$wrap_empty\" | grep -qF 'COUNCIL_INFERENCE_OK'"

# {error:...} envelope -> UNAVAILABLE, body NOT leaked.
wrap_err="$(dsr "OPENROUTER_API_KEY=$SENTINEL" -- run --body "$REAL_BODY" --subject "$SUBJECT" --model vendor/m --inject-response '{"error":{"message":"BODY-SHOULD-NOT-LEAK","code":502}}' --json 2>&1)"
assert_contains "REQ-DS-007 {error:...} envelope -> COUNCIL_MODEL_UNAVAILABLE" "$wrap_err" "COUNCIL_MODEL_UNAVAILABLE"
assert "REQ-DS-007 {error:...} envelope does NOT leak its body text" "! printf '%s' \"$wrap_err\" | grep -qF 'BODY-SHOULD-NOT-LEAK'"

# ===========================================================================
# 8. REQ-DS-008 — Budget: PER-CALL cap, fail-closed BEFORE the call; per-role on presets.
#    These: "there is a budget cap." Gegenthese: a cap checked after the call has
#    already spent, or an aggregate cap that lets one big role pass, re-opens the
#    "spend only on purpose" incident. Schärfung: an oversized subject aborts
#    COUNCIL_BUDGET_EXCEEDED with ZERO calls; for a preset each role-call is
#    independently checked (no aggregate cap).
# ===========================================================================
CC_BUD="$SCRATCH/budget.calls"
# A subject crafted to exceed the cap. The runner computes its OWN input estimate
# (do NOT hand-feed it — Slice-1 retro RISK-DS-005). A tiny cap forces the overflow.
over="$(dsr "OPENROUTER_API_KEY=$SENTINEL COUNCIL_MAX_TOKENS_PER_RUN=10" -- run --body "$REAL_BODY" --subject "$SUBJECT this subject plus the body prompt vastly exceeds a ten token cap" --model vendor/m --inject-response '{"choices":[{"message":{"content":"should never run"}}]}' --inject-call-counter "$CC_BUD" --json 2>&1)"
assert_contains "REQ-DS-008 oversized subject aborts COUNCIL_BUDGET_EXCEEDED" "$over" "COUNCIL_BUDGET_EXCEEDED"
assert_eq "REQ-DS-008 over-cap made ZERO transport calls (cap checked BEFORE call)" "0" "$(calls "$CC_BUD")"
assert "REQ-DS-008 over-cap never returns COUNCIL_INFERENCE_OK" "! printf '%s' \"$over\" | grep -qF 'COUNCIL_INFERENCE_OK'"

# Preset budget: the cap is per role-call, not an aggregate. With a per-call cap big
# enough for one role, N roles each get an independent check (N calls possible).
CC_PRESET="$SCRATCH/preset.calls"
dsr "OPENROUTER_API_KEY=$SENTINEL COUNCIL_MAX_TOKENS_PER_RUN=20000" -- preset --preset A --subject "$SUBJECT" --inject-catalog "$cat_ds" --inject-response '{"choices":[{"message":{"content":"ok"}}],"usage":{"prompt_tokens":40,"completion_tokens":3}}' --inject-call-counter "$CC_PRESET" --json >/dev/null 2>&1
# 4 roles, each independently within cap -> 4 calls (per-call cap, no aggregate cap).
assert_eq "REQ-DS-008 a full preset issues one transport call PER role (per-call cap, no aggregate)" "4" "$(calls "$CC_PRESET")"

# ===========================================================================
# 9. REQ-DS-009 — Live gate OFF by default -> transport=None -> 0 network calls.
#    These: "live calls are gated." Gegenthese: a --live that fires without the env
#    gate (or a default that calls the network) spends credits in CI. Schärfung:
#    --live WITHOUT COUNCIL_INFERENCE_LIVE=1 makes ZERO real calls; and a plain run
#    with no injection reaches no real urlopen.
# ===========================================================================
LIVE_CTR="$SCRATCH/live.calls"
live_nogate="$(dsr "OPENROUTER_API_KEY=$SENTINEL" -- run --body "$REAL_BODY" --subject "$SUBJECT" --model vendor/m --live --inject-call-counter "$LIVE_CTR" --json 2>&1)"
assert_eq "REQ-DS-009 --live WITHOUT COUNCIL_INFERENCE_LIVE=1 makes ZERO real calls (gate off)" "0" "$(calls "$LIVE_CTR")"
assert "REQ-DS-009 --live ungated stays offline-classified (no traceback)" "! printf '%s' \"$live_nogate\" | grep -qE 'Traceback'"
assert "REQ-DS-009 --live ungated never leaks the key" "! printf '%s' \"$live_nogate\" | grep -qF '$SENTINEL'"

# A transport-reaching run with NO injection must classify, not hit a real urlopen.
CC_GUARD="$SCRATCH/guard.calls"
noinject="$(dsr "OPENROUTER_API_KEY=$SENTINEL COUNCIL_MAX_TOKENS_PER_RUN=20000" -- run --body "$REAL_BODY" --subject "$SUBJECT" --model vendor/m --inject-call-counter "$CC_GUARD" --json 2>&1)"
assert_eq "REQ-DS-009 no-injection transport-reaching run makes ZERO real calls" "0" "$(calls "$CC_GUARD")"
assert "REQ-DS-009 no-injection run does NOT raise a Python traceback" "! printf '%s' \"$noinject\" | grep -qE 'Traceback'"

# ===========================================================================
# 10. REQ-DS-013 — Key leak-check across EVERY output path (= 0 occurrences).
#     These: "the key authorizes the call." Gegenthese: a green success path can still
#     leak the key in an error/result structure. Schärfung: the sentinel appears in
#     NONE of the collected outputs across run/preset/resolver/error paths.
# ===========================================================================
for label in "body:$body_ok" "char:$char_ok" "wrap:$wrap_ok" "wrap_err:$wrap_err" "over:$over" "presetA:$presetA" "presetSame:$presetSame" "presetStrong:$presetStrong" "res_ds:$res_ds" "res_empty:$res_empty" "allunavail:$allunavail" "live:$live_nogate"; do
  name="${label%%:*}"; payload="${label#*:}"
  # Use assert_not_contains (parameter-passed, NOT eval-interpolated) so a payload
  # carrying shell-meta chars (e.g. the disclosed prompt "Die Visionaerin (The
  # Visionary)") can never break parsing or mask a real leak. Meaning is identical:
  # FAIL iff the raw key sentinel appears anywhere in this output path.
  assert_not_contains "REQ-DS-013 sentinel key absent from the $name path" "$payload" "$SENTINEL"
done

# ===========================================================================
# 11. REQ-DS-015 (PAIRED) — Live catalog FETCH is WIRED via the injectable
#     deepseek_review._CATALOG_FETCHER hook (default council_backend._fetch_catalog_ids).
#
#   Slice-1 retro lesson (RISK-DS-005 / "injectable seam needs a paired gated real
#   entrypoint or the real path is dead code"): the dynamic resolver's LIVE catalog
#   fetch was previously NEVER wired — every live preset returned catalog-unreachable.
#   The coder wired it through the module hook _CATALOG_FETCHER. The FALSIFIER below
#   (test #1) FAILS if that wiring is ever removed (fetcher never invoked -> the
#   resolver gets no catalog -> catalog-unreachable), so the real path cannot silently
#   become dead again.
#
#   These checks drive the hook with a FAKE in-process fetcher (0 network, 0 credits)
#   via a Python harness — the SAME integration-fake honesty class as the rest of this
#   suite. COUNCIL_INFERENCE_LIVE=1 is set ONLY to arm the FETCH-path branch
#   (args.inject_catalog absent); the COMPLETION never hits the network because every
#   case uses --dry-run (0 completion transport calls). NO real OpenRouter call is
#   ever made here; the fake fetcher counter PROVES the network boundary stays fake.
#
#   Beat 0 (boundary gate): the ONE real boundary (the live GET to OpenRouter) is the
#   thing under test, but it is exercised THROUGH the production wiring hook with an
#   injected fake — the real GET itself is earned only by the env-gated full-preset
#   smoke (REQ-DS-011, outside run_all.sh). Here we prove the WIRING (the fetcher is
#   actually consulted), fail-closed semantics, and --inject-catalog precedence — all
#   0-network. Counter-thesis "built but never invoked" is killed by test #1.
# ===========================================================================
# A reusable in-process harness. It sets OPENROUTER_API_KEY in the REAL os.environ
# (deepseek_review.main reads dict(os.environ), so the bash `env -i` indirection does
# not reach it), monkeypatches deepseek_review._CATALOG_FETCHER per the requested mode,
# invokes d.main(argv) capturing stdout, and prints a final line:
#   __CALLS__=<fetcher-invocation-count>
# followed by the captured JSON/stdout. Mode controls the fake fetcher:
#   ok     -> returns 5 ids across >=2 distinct preferred families (resolves diverse)
#   raise  -> raises urllib.error.URLError (transport failure)
#   value  -> raises ValueError (malformed catalog)
#   timeout-> raises TimeoutError
#   empty  -> returns [] (empty catalog)
# The hook is RESET to None at the end of every invocation (no cross-test bleed).
LIBDIR="$(cd "$(dirname "$MOD")" && pwd)"
HARNESS="$SCRATCH/fetch_harness.py"
# shellcheck disable=SC2016  # the harness body is literal Python; no shell expansion wanted
cat > "$HARNESS" <<'PYEOF'
import io, os, sys, contextlib, urllib.error

mode = sys.argv[1]
have_key = sys.argv[2] == "key"
argv = sys.argv[3:]

SENTINEL = "sk-or-LEAKCANARY-DO-NOT-PRINT-9f3c1a"
# Real os.environ (main() reads dict(os.environ)). Reset any inherited overrides.
os.environ.pop("COUNCIL_INFERENCE_MODEL", None)
if have_key:
    os.environ["OPENROUTER_API_KEY"] = SENTINEL
else:
    os.environ.pop("OPENROUTER_API_KEY", None)
# Arm ONLY the fetch-path branch (args.inject_catalog absent). The completion still
# never hits the network: every harness argv uses --dry-run (0 completion transport).
os.environ["COUNCIL_INFERENCE_LIVE"] = "1"

import deepseek_review as d
d._CATALOG_FETCHER = None
calls = {"n": 0}

def make_fetcher(mode):
    def fetcher(api_key, timeout_seconds):
        calls["n"] += 1
        # The fetcher must receive the REAL key (header-only inside the real one); it
        # must NEVER be logged/returned. We do not print it here.
        if mode == "raise":
            raise urllib.error.URLError("simulated transport failure")
        if mode == "value":
            raise ValueError("simulated malformed catalog payload")
        if mode == "timeout":
            raise TimeoutError("simulated catalog timeout")
        if mode == "empty":
            return []
        # ok: 5 ids spanning >=2 distinct preferred families (DeepSeek + Qwen) so the
        # per-role distinct-family distribution yields distinct_bases >= 2.
        return [
            "deepseek/deepseek-v4:free",
            "qwen/qwen3-235b:free",
            "google/gemma-9:free",
            "cohere/c:free",
            "meta-llama/l:free",
        ]
    return fetcher

d._CATALOG_FETCHER = make_fetcher(mode)
buf = io.StringIO()
try:
    with contextlib.redirect_stdout(buf):
        d.main(argv)
finally:
    d._CATALOG_FETCHER = None
out = buf.getvalue()
sys.stdout.write("__CALLS__=%d\n" % calls["n"])
sys.stdout.write(out)
PYEOF

# dsfetch <mode> <key|nokey> -- <cli args...>  -> prints "__CALLS__=N\n<json>"
dsfetch() {
  local mode="$1" keyflag="$2"; shift 2
  [ "${1:-}" = "--" ] && shift
  env -i PATH="$PATH" PYTHONPATH="$LIBDIR" python3 "$HARNESS" "$mode" "$keyflag" "$@" 2>&1
}
# fcalls <harness-output> -> the fetcher invocation count line value
fcalls() { printf '%s\n' "$1" | sed -n 's/^__CALLS__=//p' | head -n1; }
# fdistinct <harness-output> -> the resolved diversity distinct_bases integer (0 if absent).
# Extracted with sed (NOT eval) so the multiline JSON payload never reaches an eval'd
# grep — keeping the numeric assertion robust against shell-meta chars in the output.
fdistinct() {
  local n
  n="$(printf '%s\n' "$1" | sed -n 's/.*"distinct_bases": *\([0-9][0-9]*\).*/\1/p' | head -n1)"
  printf '%s' "${n:-0}"
}

# --- Test #1: FALSIFIER — the live path (no --inject-catalog) INVOKES the fetcher ---
# With the gate armed and NO --inject-catalog, the resolver MUST consult the live
# fetcher hook. If the wiring is deleted (catalog stays unreached), the fetcher is
# never called -> catalog-unreachable -> EVERY assertion below FAILS. This is the
# regression guard for the wired-in-prod defect the coder just fixed.
f1="$(dsfetch ok key -- preset --preset A --subject "$SUBJECT" --dry-run --json)"
assert "REQ-DS-015 PAIRED live-path WITHOUT --inject-catalog INVOKES the fetcher (>=1 call)" "[ \"$(fcalls "$f1")\" -ge 1 ]"
assert_contains "REQ-DS-015 PAIRED live-fetch feeds the resolver -> diversity gate OK" "$f1" "COUNCIL_DIVERSITY_OK"
assert "REQ-DS-015 PAIRED live-fetch yields >=2 distinct bases" "[ \"$(fdistinct "$f1")\" -ge 2 ]"
assert "REQ-DS-015 PAIRED live-fetch path is NOT catalog-unreachable (wiring alive)" "! printf '%s' \"$f1\" | grep -qF 'catalog-unreachable'"
assert "REQ-DS-015 PAIRED live-fetch path raises no Python traceback" "! printf '%s' \"$f1\" | grep -qE 'Traceback'"
# A single-body run-path live fetch is also wired (mirrors the preset path).
f1b="$(dsfetch ok key -- run --body "$REAL_BODY" --subject "$SUBJECT" --dry-run --json)"
assert "REQ-DS-015 PAIRED run-path live fetch is also wired (fetcher invoked >=1)" "[ \"$(fcalls "$f1b")\" -ge 1 ]"
assert_contains "REQ-DS-015 PAIRED run-path live-fetch resolves a :free id (not unreachable)" "$f1b" ":free"

# --- Test #2: fail-closed when the fetcher RAISES (URLError/ValueError/TimeoutError) ---
for emode in raise value timeout; do
  fe="$(dsfetch "$emode" key -- preset --preset A --subject "$SUBJECT" --dry-run --json)"
  assert "REQ-DS-015 PAIRED fetcher $emode -> attempted (fetcher invoked)" "[ \"$(fcalls "$fe")\" -ge 1 ]"
  assert_contains "REQ-DS-015 PAIRED fetcher $emode fails closed -> catalog-unreachable" "$fe" "catalog-unreachable"
  assert "REQ-DS-015 PAIRED fetcher $emode raises no Python traceback" "! printf '%s' \"$fe\" | grep -qE 'Traceback'"
  assert "REQ-DS-015 PAIRED fetcher $emode does NOT silently pick a stale Slice-1 default" "! printf '%s' \"$fe\" | grep -qF 'meta-llama/llama-3.1-8b-instruct:free'"
done

# --- Test #3: fail-closed when the fetcher returns [] (empty catalog) ---
f3="$(dsfetch empty key -- preset --preset A --subject "$SUBJECT" --dry-run --json)"
assert "REQ-DS-015 PAIRED empty-catalog fetcher was invoked" "[ \"$(fcalls "$f3")\" -ge 1 ]"
assert_contains "REQ-DS-015 PAIRED empty-catalog fetcher result fails closed (catalog-unreachable)" "$f3" "catalog-unreachable"
assert "REQ-DS-015 PAIRED empty-catalog returns no COUNCIL_DIVERSITY_OK" "! printf '%s' \"$f3\" | grep -qF 'COUNCIL_DIVERSITY_OK'"

# --- Test #4: --inject-catalog STILL wins over the live fetch (precedence; 0-network) ---
# When --inject-catalog is SUPPLIED, the fake fetcher must NOT be invoked (counter 0)
# and resolution uses the injected csv. This keeps the offline suite 0-network.
f4="$(dsfetch ok key -- preset --preset A --subject "$SUBJECT" --dry-run --inject-catalog "deepseek/deepseek-v4:free,qwen/qwen3-235b:free" --json)"
assert_eq "REQ-DS-015 PAIRED --inject-catalog present -> live fetcher NOT invoked (0 calls)" "0" "$(fcalls "$f4")"
assert_contains "REQ-DS-015 PAIRED --inject-catalog drives resolution (uses injected csv)" "$f4" "deepseek/deepseek-v4:free"
assert "REQ-DS-015 PAIRED --inject-catalog precedence path raises no traceback" "! printf '%s' \"$f4\" | grep -qE 'Traceback'"
# Explicit-empty --inject-catalog "" must ALSO short-circuit the live fetch (0 calls)
# and fail closed — an EMPTY injected catalog is NOT a live-fetch trigger.
f4e="$(dsfetch ok key -- preset --preset A --subject "$SUBJECT" --dry-run --inject-catalog "" --json)"
assert_eq "REQ-DS-015 PAIRED explicit-empty --inject-catalog does NOT trigger a live fetch (0 calls)" "0" "$(fcalls "$f4e")"
assert_contains "REQ-DS-015 PAIRED explicit-empty --inject-catalog fails closed (catalog-unreachable)" "$f4e" "catalog-unreachable"

# --- Test #5: key-absent -> fetcher NOT invoked (no key, no fetch; key never leaks) ---
# Without OPENROUTER_API_KEY the live-fetch guard short-circuits BEFORE calling the
# fetcher (the raw key is required header-only inside the real fetcher and must never
# be reached/logged/returned when absent).
f5="$(dsfetch ok nokey -- preset --preset A --subject "$SUBJECT" --dry-run --json)"
assert_eq "REQ-DS-015 PAIRED key-absent -> live fetcher NOT invoked (0 calls)" "0" "$(fcalls "$f5")"
assert_contains "REQ-DS-015 PAIRED key-absent fails closed (catalog-unreachable, no fetch)" "$f5" "catalog-unreachable"
assert "REQ-DS-015 PAIRED key-absent path never leaks the sentinel key" "! printf '%s' \"$f5\" | grep -qF '$SENTINEL'"
assert "REQ-DS-015 PAIRED key-absent path raises no Python traceback" "! printf '%s' \"$f5\" | grep -qE 'Traceback'"

# --- Sentinel leak-check across the PAIRED fetch paths (= 0 occurrences). ---
for label in "f1:$f1" "f1b:$f1b" "f4:$f4" "f4e:$f4e"; do
  name="${label%%:*}"; payload="${label#*:}"
  assert_not_contains "REQ-DS-013 sentinel key absent from the paired-fetch $name path" "$payload" "$SENTINEL"
done

finish "DeepSeek-Review council runner acceptance contract"
