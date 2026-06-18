#!/usr/bin/env bash
set -u
#
# Phase-1 BLACK-BOX acceptance contract for the OpenRouter Council Backend.
# Written BEFORE any implementation exists (TDD RED). The coder implements
# config/claude/lib/council_backend.py to satisfy EXACTLY this contract.
#
# Spec sources (frozen, user-confirmed 2026-06-18, spec-remediated):
#   docs/prd/openrouter-council-backend.prd.md      (REQ-B-001..020/006b, AC-B-001..010,
#                                                    EDGE-B-001..007, EV-B-001..007, §11)
#   docs/canvas/openrouter-council-backend.canvas.md (CAN-B-008/014, RISK-B-001/007, OQ-B-004)
#   docs/vision/openrouter-council-backend.vision.md (SS-B-001..006, VCHK via Success Signals)
#
# ===========================================================================
# SEAM / CLI CONTRACT THE CODER MUST IMPLEMENT  (mirror of plumbline_start.py)
# ===========================================================================
# A deterministic, API-FREE, NETWORK-FREE Python module with an argparse CLI:
#
#   python3 config/claude/lib/council_backend.py <subcommand> [flags]
#
# House rules (Reality Ledger): NO network, NO real OPENROUTER_API_KEY required to
# run any subcommand. Reachability is INJECTED, never probed. These tests are
# evidence-class `integration-fake`; they do NOT prove real OpenRouter reachability
# or real model diversity (that stays RED(confidence) per the Reality Ledger and
# OQ-B-004). The reachability METHOD is an OPEN QUESTION (OQ-B-004): the gate LOGIC
# is tested here against injected reachability ONLY.
#
# Subcommands (all accept `--json` to emit a single machine-readable JSON object;
# without `--json` they emit a deterministic human panel):
#
# 1) config            Load Council config from environment.
#      Reads: COUNCIL_1_MODEL..COUNCIL_4_MODEL (canonical, uppercase),
#             lowercase aliases council_1..council_4 (REQ-B-007; uppercase wins,
#             REQ-B-008), OPENROUTER_API_KEY, COUNCIL_BACKEND, COUNCIL_FAIL_CLOSED,
#             COUNCIL_MIN_BACKENDS (default 2), COUNCIL_TIMEOUT_SECONDS.
#      JSON output MUST include: {"slots": {"council_1":<id-or-null>, ...council_4},
#             "min_backends": <int>, "fail_closed": <bool>, "backend": <str>,
#             "api_key_present": <bool>}.
#      The raw OPENROUTER_API_KEY value MUST NEVER appear anywhere in output/repr
#      (REQ-B-016, AC-B-009, RISK-B-001) — only a boolean `api_key_present`.
#
# 2) normalize <model-id>     Print the normalized base-model slug for ONE id.
#      Strips known variant/price/provider suffixes (:nitro, :floor, :exacto and any
#      :<variant>) before comparison (REQ-B-011, EDGE-B-002). JSON: {"input":..,"base":..}.
#
# 3) gate              Diversity / fail-closed decision given INJECTED reachability.
#      Required flag:  --fake-reachable '<json list of reachable model-ID strings>'
#                      (the injected seam; replaces any network call entirely).
#      Honors COUNCIL_MIN_BACKENDS (default 2) and COUNCIL_FAIL_CLOSED.
#      Counts DISTINCT NORMALIZED base slugs among reachable ids (REQ-B-011/012).
#      JSON MUST include: {"distinct_base_count": <int>, "min_backends": <int>,
#             "decision": "proceed"|"abort", "code": <str>, "fail_closed": <bool>}.
#      <COUNCIL_MIN_BACKENDS distinct normalized bases  => decision=abort,
#             code=COUNCIL_DIVERSITY_UNAVAILABLE (AC-B-004/005/012, EDGE-B-002).
#      >=COUNCIL_MIN_BACKENDS distinct normalized bases => decision=proceed (AC-B-006).
#      A `--fake-error timeout|model-unavailable` flag injects a transport failure
#      class: timeout => decision=abort, code=COUNCIL_TIMEOUT (EDGE-B-004, REQ-B-017);
#      model-unavailable => decision=abort, code=COUNCIL_MODEL_UNAVAILABLE (EDGE-B-003).
#      Missing key with backend=openrouter => decision=abort,
#             code=COUNCIL_MISSING_SECRET, and NO raw env dump (EDGE-B-001).
#
# 4) prompt <body>     Load an editable role prompt from concilium/<body>.md.
#      Optional --prompts-dir <dir> to point at a fixture dir (deterministic test seam).
#      Existing file  => JSON {"body":..,"source":"concilium/<body>.md","content":<text>,
#             "status":"loaded"} (content is the edited file's bytes; REQ-B-010, AC-B-007).
#      Missing file   => decision=abort, code/status="prompt-missing" (EDGE-B-005,
#             deterministic single classified outcome — NOT "X or Y").
#
# 5) report            Emit a model-disclosure report for the assembled council.
#      Required: --fake-reachable (as in gate) so it can map roles->models; optional
#      --prompts-dir. JSON MUST include a per-role list where each entry has:
#             role (name), model (id), backend (name), prompt_source (concilium/<body>.md)
#             (REQ-B-014/019, AC-B-008). Raw key MUST NOT appear (REQ-B-016).
#
# 6) fallback          Claude-only fallback policy decision (no silent fallback).
#      With COUNCIL_FAIL_CLOSED=true and a validation failure => JSON
#             {"continue_claude_only": false, "disclosed": <bool>} — does NOT continue
#             Claude-only (AC-B-010, REQ-B-013, NGOAL-B-003). Explicit Claude-only is
#             only allowed with disclosure (--allow-claude-only) => continue_claude_only
#             true AND disclosed true (EDGE-B-007).
#
# Exit codes: 0 for a successfully-classified result (incl. classified aborts — the
# CLASSIFICATION is the success, mirroring plumbline_start.py which always exits 0 and
# encodes the gate in the payload). Tests assert on payload fields, not exit status,
# EXCEPT that an unknown subcommand / argparse error is non-zero.
#
# Per-REQ kritische semantische Glättung (Beat 0 boundary gate): every seam below is
# PURE in-process logic (env parse / string normalize / set-count / file read / dict
# redact). The only real boundary (OpenRouter reachability) is SCOPED OUT by the spec
# (OQ-B-004) and INJECTED via --fake-reachable. So: no invented network/NaN/overflow
# failure modes beyond the spec's own classified ones; the Schärfung for each REQ is a
# real falsifying assertion on the logic, recorded inline as "Gegenthese:".
# ===========================================================================

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"
cd "$REPO_DIR" || exit 1
# shellcheck source=config/claude/tests/lib.sh
source "$HERE/lib.sh"

MOD="config/claude/lib/council_backend.py"
SENTINEL="sk-or-LEAKCANARY-DO-NOT-PRINT-9f3c1a"

# Helper: run the module CLI with a clean, injected env so no real key leaks in and
# the test is hermetic regardless of the developer's shell environment.
council() { # council <env-assignments-as-string> -- <cli args...>
  local envstr="$1"; shift
  [ "${1:-}" = "--" ] && shift
  # shellcheck disable=SC2086  # $envstr is intentionally word-split into KEY=VALUE tokens for env -i
  env -i PATH="$PATH" $envstr python3 "$MOD" "$@" 2>&1
}

printf 'OpenRouter Council Backend — Phase-1 acceptance contract (RED until implemented)\n'

# --- Module presence (drives the RED state before implementation) -----------
assert_file "council_backend module exists" "$MOD"

# ===========================================================================
# 1. CONFIG LOADER  (AC-B-001/002/003, REQ-B-002..008/006b)
#    These: "4 configurable slots load." Gegenthese: a loader that 'works' could
#    still echo the API key into its own output → value zero, secret leaked.
#    Schärfung: assert the sentinel key is absent AND the booleans/slots are right.
# ===========================================================================

# AC-B-001: four slots load, key NOT exposed.
cfg="$(council "COUNCIL_1_MODEL=anthropic/claude-3 COUNCIL_2_MODEL=openai/gpt-4 COUNCIL_3_MODEL=google/gemini COUNCIL_4_MODEL=meta/llama OPENROUTER_API_KEY=$SENTINEL" -- config --json)"
assert_contains "AC-B-001 slot 1 loaded" "$cfg" "anthropic/claude-3"
assert_contains "AC-B-001 slot 2 loaded" "$cfg" "openai/gpt-4"
assert_contains "AC-B-001 slot 3 loaded" "$cfg" "google/gemini"
assert_contains "AC-B-001/REQ-B-006b slot 4 loaded" "$cfg" "meta/llama"
assert_contains "AC-B-001 exposes api_key_present boolean" "$cfg" '"api_key_present": true'
assert "AC-B-009/REQ-B-016 raw key NEVER in config output" "! printf '%s' \"$cfg\" | grep -qF '$SENTINEL'"

# AC-B-002: lowercase aliases mapped when uppercase empty.
cfg_lc="$(council "council_1=alias/one council_2=alias/two council_3=alias/three council_4=alias/four" -- config --json)"
assert_contains "AC-B-002 lowercase alias 1 maps to slot" "$cfg_lc" "alias/one"
assert_contains "AC-B-002 lowercase alias 4 maps to slot" "$cfg_lc" "alias/four"

# AC-B-003: uppercase precedence when both set.
cfg_pr="$(council "COUNCIL_1_MODEL=UPPER/win council_1=lower/lose" -- config --json)"
assert_contains "AC-B-003 uppercase value wins" "$cfg_pr" "UPPER/win"
assert "AC-B-003 lowercase value does NOT win when uppercase set" "! printf '%s' \"$cfg_pr\" | grep -qF 'lower/lose'"

# ===========================================================================
# 2. NORMALIZATION + DIVERSITY GATE  (B1 CORE — REQ-B-011/012, AC-B-004/005/006, EDGE-B-002)
#    These: "two configured slots => two backends." Gegenthese: anthropic/x:nitro
#    and anthropic/x:floor LOOK like two but are ONE base → fake diversity, council
#    appears plural while monoculture. Schärfung: count on normalized base; the
#    variant-pair must FAIL-CLOSED, the genuinely-distinct pair must proceed.
# ===========================================================================

# normalize: variant suffix stripping is the load-bearing operation.
n1="$(council "" -- normalize 'anthropic/claude-3:nitro' --json)"
n2="$(council "" -- normalize 'anthropic/claude-3:floor' --json)"
assert_contains "REQ-B-011 :nitro strips to base" "$n1" "anthropic/claude-3"
assert "REQ-B-011 :nitro suffix is removed from base" "! printf '%s' \"$n1\" | grep -qF ':nitro'"
assert_contains "REQ-B-011 :floor strips to base" "$n2" "anthropic/claude-3"
assert "REQ-B-011 :exacto/:<variant> generic suffix removed" "! council '' -- normalize 'x/y:exacto' --json | grep -qF ':exacto'"

# EDGE-B-002 / AC-B-004/005/012: same base via distinct variant-IDs => 1 => fail-closed.
g_alias="$(council "COUNCIL_BACKEND=openrouter COUNCIL_FAIL_CLOSED=true OPENROUTER_API_KEY=$SENTINEL" -- gate --fake-reachable '["anthropic/claude-3:nitro","anthropic/claude-3:floor"]' --json)"
assert_contains "EDGE-B-002 variant-aliases collapse to 1 distinct base" "$g_alias" '"distinct_base_count": 1'
assert_contains "EDGE-B-002 1 distinct base aborts" "$g_alias" '"decision": "abort"'
assert_contains "REQ-B-012 abort code is COUNCIL_DIVERSITY_UNAVAILABLE" "$g_alias" "COUNCIL_DIVERSITY_UNAVAILABLE"

# AC-B-004: zero reachable => fail-closed.
g0="$(council "COUNCIL_BACKEND=openrouter COUNCIL_FAIL_CLOSED=true OPENROUTER_API_KEY=$SENTINEL" -- gate --fake-reachable '[]' --json)"
assert_contains "AC-B-004 zero reachable count is 0" "$g0" '"distinct_base_count": 0'
assert_contains "AC-B-004 zero reachable aborts COUNCIL_DIVERSITY_UNAVAILABLE" "$g0" "COUNCIL_DIVERSITY_UNAVAILABLE"

# AC-B-005: one reachable => fail-closed.
g1="$(council "COUNCIL_BACKEND=openrouter COUNCIL_FAIL_CLOSED=true OPENROUTER_API_KEY=$SENTINEL" -- gate --fake-reachable '["anthropic/claude-3"]' --json)"
assert_contains "AC-B-005 one reachable count is 1" "$g1" '"distinct_base_count": 1'
assert_contains "AC-B-005 one reachable aborts COUNCIL_DIVERSITY_UNAVAILABLE" "$g1" "COUNCIL_DIVERSITY_UNAVAILABLE"

# AC-B-006: >=2 genuinely-distinct normalized bases => proceed.
g2="$(council "COUNCIL_BACKEND=openrouter COUNCIL_FAIL_CLOSED=true OPENROUTER_API_KEY=$SENTINEL" -- gate --fake-reachable '["anthropic/claude-3:nitro","openai/gpt-4:floor"]' --json)"
assert_contains "AC-B-006 two distinct bases count is 2" "$g2" '"distinct_base_count": 2'
assert_contains "AC-B-006 two distinct bases proceed" "$g2" '"decision": "proceed"'

# N2: threshold is configurable COUNCIL_MIN_BACKENDS (not hardcoded 2). With min=3,
# two distinct bases must abort (proves the default is read from env, not baked in).
g_min3="$(council "COUNCIL_BACKEND=openrouter COUNCIL_FAIL_CLOSED=true COUNCIL_MIN_BACKENDS=3 OPENROUTER_API_KEY=$SENTINEL" -- gate --fake-reachable '["anthropic/claude-3","openai/gpt-4"]' --json)"
assert_contains "REQ-B-011 min_backends reflects COUNCIL_MIN_BACKENDS=3" "$g_min3" '"min_backends": 3'
assert_contains "REQ-B-011 two distinct bases abort when threshold is 3" "$g_min3" '"decision": "abort"'

# ===========================================================================
# 3. SECRET REDACTION  (AC-B-009, REQ-B-016, RISK-B-001)
#    These: "the key is read." Gegenthese: a green system can still leak the key
#    in an ERROR or REPORT path even if config redacts it. Schärfung: the sentinel
#    must appear in NONE of config / gate-error / report output.
# ===========================================================================
err_path="$(council "COUNCIL_BACKEND=openrouter COUNCIL_FAIL_CLOSED=true OPENROUTER_API_KEY=$SENTINEL" -- gate --fake-reachable '[]' --json)"
rep_path="$(council "COUNCIL_BACKEND=openrouter COUNCIL_FAIL_CLOSED=true COUNCIL_1_MODEL=anthropic/claude-3 COUNCIL_2_MODEL=openai/gpt-4 OPENROUTER_API_KEY=$SENTINEL" -- report --fake-reachable '["anthropic/claude-3","openai/gpt-4"]' --json)"
assert "AC-B-009 sentinel absent from config path" "! printf '%s' \"$cfg\" | grep -qF '$SENTINEL'"
assert "REQ-B-016 sentinel absent from error/gate path" "! printf '%s' \"$err_path\" | grep -qF '$SENTINEL'"
assert "REQ-B-016 sentinel absent from report path" "! printf '%s' \"$rep_path\" | grep -qF '$SENTINEL'"

# EDGE-B-001: missing key + backend=openrouter => classified missing-secret, no raw env dump.
g_nokey="$(council "COUNCIL_BACKEND=openrouter COUNCIL_FAIL_CLOSED=true" -- gate --fake-reachable '["anthropic/claude-3","openai/gpt-4"]' --json)"
assert_contains "EDGE-B-001 missing key aborts with classified code" "$g_nokey" "COUNCIL_MISSING_SECRET"
assert "EDGE-B-001 no raw OPENROUTER_API_KEY env-name dump in output" "! printf '%s' \"$g_nokey\" | grep -q 'OPENROUTER_API_KEY='"

# ===========================================================================
# 4. PROMPT LOADER  (AC-B-007, REQ-B-010, EDGE-B-005)
#    These: "a prompt file exists." Gegenthese: a loader could ship a hardcoded /
#    cached prompt and ignore the EDITED file → editability claim is fake.
#    Schärfung: edit a fixture file, assert that exact edited content is returned;
#    missing file => deterministic single classified 'prompt-missing'.
# ===========================================================================
FIXTURE_DIR="$(mktemp -d)"
trap 'rm -rf "$FIXTURE_DIR"' EXIT
EDIT_MARK="EDITED-PROMPT-MARKER-$$-skeptic-axis"
printf '%s\n' "$EDIT_MARK" > "$FIXTURE_DIR/skeptic.md"

p_loaded="$(council "" -- prompt skeptic --prompts-dir "$FIXTURE_DIR" --json)"
assert_contains "AC-B-007 edited prompt CONTENT is used" "$p_loaded" "$EDIT_MARK"
assert_contains "REQ-B-019 prompt source is disclosed as concilium/skeptic.md" "$p_loaded" "concilium/skeptic.md"

p_missing="$(council "" -- prompt market-realist --prompts-dir "$FIXTURE_DIR" --json)"
assert_contains "EDGE-B-005 missing prompt => deterministic prompt-missing" "$p_missing" "prompt-missing"

# Real (committed) prompts must be loadable from the default concilium/ dir.
assert_file "default concilium/skeptic.md prompt source exists" "concilium/skeptic.md"

# ===========================================================================
# 5. MODEL DISCLOSURE  (AC-B-008, REQ-B-014/019)
#    These: "council ran." Gegenthese: a report that omits which model produced a
#    role makes the diversity claim unauditable → user can't verify value.
#    Schärfung: report must name role + model-ID + backend name + prompt source.
# ===========================================================================
rep="$(council "COUNCIL_BACKEND=openrouter COUNCIL_FAIL_CLOSED=true COUNCIL_1_MODEL=anthropic/claude-3 COUNCIL_2_MODEL=openai/gpt-4 OPENROUTER_API_KEY=$SENTINEL" -- report --fake-reachable '["anthropic/claude-3","openai/gpt-4"]' --json)"
assert_contains "AC-B-008 report includes model ID" "$rep" "anthropic/claude-3"
assert_contains "AC-B-008 report names backend" "$rep" "openrouter"
assert_contains "AC-B-008/REQ-B-019 report names prompt source" "$rep" "concilium/"
assert_contains "AC-B-008/REQ-B-014 report includes a role field" "$rep" '"role"'

# ===========================================================================
# 6. NO SILENT FALLBACK  (AC-B-010, REQ-B-013, NGOAL-B-003, EDGE-B-007)
#    These: "validation failed, stop." Gegenthese: a 'helpful' impl could silently
#    continue Claude-only, manufacturing pseudo-diversity → exactly the incident
#    this feature exists to prevent. Schärfung: with FAIL_CLOSED=true it must NOT
#    continue Claude-only; explicit Claude-only is allowed ONLY with disclosure.
# ===========================================================================
fb_closed="$(council "COUNCIL_FAIL_CLOSED=true" -- fallback --json)"
assert_contains "AC-B-010 fail-closed does NOT continue Claude-only" "$fb_closed" '"continue_claude_only": false'

fb_explicit="$(council "COUNCIL_FAIL_CLOSED=false" -- fallback --allow-claude-only --json)"
assert_contains "EDGE-B-007 explicit Claude-only is allowed" "$fb_explicit" '"continue_claude_only": true'
assert_contains "EDGE-B-007 explicit Claude-only is disclosed (never silent)" "$fb_explicit" '"disclosed": true'

# ===========================================================================
# 7. DETERMINISTIC EDGE CASES  (EDGE-B-003 model-unavailable, EDGE-B-004 timeout)
#    Network-class failures must be reported as Council UNAVAILABILITY (REQ-B-017),
#    never as a successful diverse council — each a single classified code.
# ===========================================================================
g_timeout="$(council "COUNCIL_BACKEND=openrouter COUNCIL_FAIL_CLOSED=true OPENROUTER_API_KEY=$SENTINEL" -- gate --fake-reachable '["anthropic/claude-3","openai/gpt-4"]' --fake-error timeout --json)"
assert_contains "EDGE-B-004 timeout aborts" "$g_timeout" '"decision": "abort"'
assert_contains "EDGE-B-004/REQ-B-017 timeout classified as COUNCIL_TIMEOUT" "$g_timeout" "COUNCIL_TIMEOUT"

g_unavail="$(council "COUNCIL_BACKEND=openrouter COUNCIL_FAIL_CLOSED=true OPENROUTER_API_KEY=$SENTINEL" -- gate --fake-reachable '["anthropic/claude-3","openai/gpt-4"]' --fake-error model-unavailable --json)"
assert_contains "EDGE-B-003 model-unavailable aborts" "$g_unavail" '"decision": "abort"'
assert_contains "EDGE-B-003 classified as COUNCIL_MODEL_UNAVAILABLE" "$g_unavail" "COUNCIL_MODEL_UNAVAILABLE"

# ===========================================================================
# REALITY-LEDGER GUARD (honesty invariant): these are integration-fake. There must
# be NO subcommand/flag that performs a real network reachability probe. The module
# may declare its evidence class; assert it does not claim a real boundary here.
# ===========================================================================
assert "no real-reachability flag is required to run gate (injected only)" "council '' -- gate --fake-reachable '[\"a/b\",\"c/d\"]' --json | grep -q 'distinct_base_count'"

# ===========================================================================
# 8. SECURITY HARDENING + CONTRACT-DOC TRUTH (independent review findings, 2026-06-18)
#    These → Gegenthese → Schärfung:
#    These: "prompt loads a role file." Gegenthese: an unvalidated <body> is a path
#    sink — `../x` or an absolute path reads ANY *.md on disk (os.path.join absolute
#    footgun), exfiltrating it via `content` and falsifying the source disclosure.
#    Schärfung: a traversal/absolute body must classify prompt-missing, never load.
# ===========================================================================
TRAVDIR="$(mktemp -d)"
printf 'SECRET-OUTSIDE-PROMPTS-DIR\n' > "$TRAVDIR/leak.md"
mkdir -p "$TRAVDIR/prompts"

# [HIGH] relative ../ traversal must NOT read the outside file.
p_trav="$(council "" -- prompt '../leak' --prompts-dir "$TRAVDIR/prompts" --json)"
assert "HIGH traversal: relative ../ body does NOT load an outside file" "! printf '%s' \"$p_trav\" | grep -qF 'SECRET-OUTSIDE-PROMPTS-DIR'"
assert_contains "HIGH traversal: relative ../ body classifies prompt-missing" "$p_trav" "prompt-missing"

# [HIGH] absolute-path body must NOT read the outside file (os.path.join footgun).
p_abs="$(council "" -- prompt "$TRAVDIR/leak" --prompts-dir "$TRAVDIR/prompts" --json)"
assert "HIGH traversal: absolute body does NOT load an outside file" "! printf '%s' \"$p_abs\" | grep -qF 'SECRET-OUTSIDE-PROMPTS-DIR'"
assert_contains "HIGH traversal: absolute body classifies prompt-missing" "$p_abs" "prompt-missing"
rm -rf "$TRAVDIR"

# [MEDIUM] malformed --fake-reachable must CLASSIFY, not crash with a traceback.
g_bad="$(council "COUNCIL_BACKEND=openrouter COUNCIL_FAIL_CLOSED=true OPENROUTER_API_KEY=$SENTINEL" -- gate --fake-reachable 'NOT JSON {' --json 2>&1)"
assert "MEDIUM malformed --fake-reachable does NOT raise a Python traceback" "! printf '%s' \"$g_bad\" | grep -qE 'Traceback|JSONDecodeError|ValueError'"
assert_contains "MEDIUM malformed --fake-reachable classifies COUNCIL_BAD_INPUT" "$g_bad" "COUNCIL_BAD_INPUT"

# [I1] COUNCIL_TIMEOUT_SECONDS is a documented config input (REQ-B-018) — read & expose it.
cfg_to="$(council "COUNCIL_TIMEOUT_SECONDS=99" -- config --json)"
assert_contains "I1 config exposes timeout_seconds from COUNCIL_TIMEOUT_SECONDS" "$cfg_to" "99"

# ===========================================================================
# 9. OQ-B-004 CATALOG-LIST REACHABILITY — PURE PARSER, OFFLINE ONLY (REQ-B-015)
#    These: "a real reachability method exists." Gegenthese: a parser could count
#    catalog variant-aliases as separate backends (fake diversity), or count a
#    configured model that the catalog never lists (phantom reachability) → the
#    LIVE gate would proceed on a monoculture / unavailable model.
#    Schärfung: drive the PURE `reachable_bases_from_catalog` against an in-test
#    FIXTURE catalog (a Python list literal) — NO network, NO key, NO live GET.
#    Assert: catalog variant-aliases collapse to one base; a configured model
#    ABSENT from the catalog is not counted; >=2 genuinely-distinct => count 2.
#    The live `reachable` subcommand is NEVER invoked here (it would hit the
#    network); only the offline-testable core is exercised.
# ===========================================================================
reach_pure="$(env -i PATH="$PATH" python3 - <<'PYEOF'
import importlib.util, json, pathlib
mod_path = pathlib.Path("config/claude/lib/council_backend.py")
spec = importlib.util.spec_from_file_location("council_backend", mod_path)
m = importlib.util.module_from_spec(spec)
spec.loader.exec_module(m)

# FIXTURE catalog (data[].id values), entirely in-process — never fetched:
#   - anthropic/claude-3 appears thrice as variant-aliases (:nitro/:floor/base)
#   - openai/gpt-4 appears once (genuinely distinct second base)
#   - mistral/large is in the catalog but NOT configured (must be ignored)
catalog = [
    "anthropic/claude-3:nitro",
    "anthropic/claude-3:floor",
    "anthropic/claude-3",
    "openai/gpt-4",
    "mistral/large",
]
# Configured council: two distinct bases + one model ABSENT from the catalog.
configured = [
    "anthropic/claude-3:exacto",   # variant of a base present in catalog
    "openai/gpt-4",                # base present in catalog
    "google/gemini-not-in-catalog" # configured but NOT in catalog => not counted
]
print(json.dumps(m.reachable_bases_from_catalog(catalog, configured), sort_keys=True))
PYEOF
)"
assert_contains "OQ-B-004 pure parser: variant-aliases collapse to base anthropic/claude-3" "$reach_pure" "anthropic/claude-3"
assert_contains "OQ-B-004 pure parser: second distinct base openai/gpt-4 counted" "$reach_pure" "openai/gpt-4"
assert_contains "OQ-B-004 pure parser: >=2 distinct reachable bases => count 2" "$reach_pure" '"distinct_base_count": 2'
assert "OQ-B-004 pure parser: configured-but-absent model NOT counted as reachable" "! printf '%s' \"$reach_pure\" | grep -qF 'google/gemini-not-in-catalog'"
assert "OQ-B-004 pure parser: catalog-only model (not configured) NOT counted" "! printf '%s' \"$reach_pure\" | grep -qF 'mistral/large'"

finish "OpenRouter Council Backend acceptance contract"
