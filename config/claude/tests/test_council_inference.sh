#!/usr/bin/env bash
set -u
#
# Phase-1 BLACK-BOX acceptance contract for the OpenRouter INFERENCE path (Slice 1).
# Written BEFORE any implementation exists (TDD RED). The coder implements the
# inference seam to satisfy EXACTLY this contract. RED until then: the inference
# subcommand / module is ABSENT, so every assertion below fails.
#
# Spec sources (FROZEN, user-confirmed 2026-06-19, Phase-0.7 spec-sanity PROCEED):
#   docs/prd/openrouter-inference.prd.md       (REQ-INF-001..019, AC-INF-001..016,
#                                               EDGE-INF-001..012, EV-INF-001..008,
#                                               NFR-INF-001..007, carried I-1/I-2/I-3)
#   docs/canvas/openrouter-inference.canvas.md (CAN-INF-008..016, RISK-INF-001..008, OQ-1..3)
#
# ===========================================================================
# SEAM / CLI CONTRACT THE CODER MUST IMPLEMENT  (mirror of council_backend.py / plumbline_start.py)
# ===========================================================================
# A deterministic, NETWORK-FREE, KEY-FREE Python module exposing an `infer`
# subcommand via the SAME argparse style as council_backend.py:
#
#   python3 <MODULE> infer [flags] [--json]
#
# The planner may put this in a NEW module config/claude/lib/council_inference.py
# OR extend config/claude/lib/council_backend.py. The test resolves the module via
# the COUNCIL_INFERENCE_MODULE env override (default: council_inference.py); the
# coder sets that default by creating the module at that path (or pointing the test
# at council_backend.py through that one variable). Either placement is in scope per
# the canvas "Allowed change scope".
#
# ---------------------------------------------------------------------------
# THE INJECTED-TRANSPORT SEAM (replaces the network entirely — REQ-INF-015):
#
# `infer` MUST accept EXACTLY ONE injected-transport flag in place of urllib:
#
#   --inject-response '<json>'   A fake HTTP 200 BODY (a JSON string). The path
#                                parses it as if it were the chat/completions
#                                response. This is the ONLY way the offline suite
#                                drives a "successful" transport — NO real urlopen.
#
#   --inject-error <class>       A fake transport FAILURE class, one of:
#                                  http-402   -> HTTP 402 (insufficient credit)
#                                  http-429   -> HTTP 429 (rate limited);
#                                               pair with --inject-retry-after <val>
#                                               to simulate the Retry-After header
#                                  http-500   -> HTTP 500 (any 5xx / other non-2xx)
#                                  timeout    -> connection error / socket timeout
#                                  malformed  -> non-JSON / unparseable body
#
#   --inject-call-counter <path> A file the seam MUST write the number of transport
#                                invocations to (0, 1, ...). Lets the test PROVE the
#                                network was NOT called on the budget/dry-run/missing-
#                                key paths, and was called EXACTLY ONCE (no retry) on
#                                the 429 path. The fake transport increments this; a
#                                path that aborts before the transport leaves it at 0.
#
# Exactly one of --inject-response / --inject-error is supplied for a transport-
# reaching run; dry-run and the abort-before-call paths supply NEITHER and MUST
# leave the call counter at 0 (or unwritten/absent). There MUST be NO flag that
# performs a REAL network call from this test (REALITY-LEDGER GUARD below).
#
# ---------------------------------------------------------------------------
# REQUIRED `infer` FLAGS (logic inputs, all offline):
#
#   --model <id>          Model id. Optional; resolves from COUNCIL_INFERENCE_MODEL,
#                         then the built-in free default (REQ-INF-010, AC-INF-013).
#   --messages '<json>'   JSON array of {role,content} message objects (the prompt).
#   --max-tokens <int>    The OUTPUT cap to be SENT on the request body (REQ-INF-004).
#                         Optional knob; the point under test is that SOME explicit
#                         max_tokens is ALWAYS placed on the body.
#   --input-estimate <int> The offline input_token_estimate heuristic value
#                         (I-3 — a NAMED heuristic, NOT exact). Supplied by the test
#                         so the estimate/cap math is deterministic and falsifiable
#                         without depending on a particular tokenizer.
#   --dry-run             Return the estimate, make NO transport call (REQ-INF-008).
#   --build-only          Emit the REQUEST BODY that WOULD be sent (no transport),
#                         so the test can assert max_tokens is on the body and the
#                         raw key is absent (REQ-INF-004, AC-INF-001).
#
# Reads from env (reuse OD-3 helpers): OPENROUTER_API_KEY (presence only),
# COUNCIL_MAX_TOKENS_PER_RUN (default 20000), COUNCIL_INFERENCE_MODEL,
# COUNCIL_TIMEOUT_SECONDS (default 45).
#
# ---------------------------------------------------------------------------
# JSON RESULT CONTRACT (every `infer` run emits ONE JSON object with --json):
#   {
#     "decision": "proceed" | "abort" | "dry-run",
#     "code": "<COUNCIL_* code>",          # see code family below
#     "estimate": {                        # the pre-call estimate (REQ-INF-005)
#        "input_token_estimate": <int>,    # the named heuristic (I-3)
#        "max_tokens": <int>,              # the SENT output cap (REQ-INF-004)
#        "total_estimate": <int>,          # == input_token_estimate + max_tokens
#        "approximate": true,              # labeled approximate (≈) — REQ-INF-005
#        "cap": <int>                      # COUNCIL_MAX_TOKENS_PER_RUN
#     },
#     "completion": <str|null>,            # the completion text on success
#     "usage": {...}|null,                 # reconciliation block on success (below)
#     "retry_after": <str|null>            # recorded on 429 ONLY, never acted on
#   }
# On --build-only the object additionally carries "request_body": {... incl. max_tokens ...}.
#
# Reconciliation block on a successful call (REQ-INF-009, I-1, I-3 — AC-INF-005):
#   "usage": {
#      "prompt_tokens": <int>, "completion_tokens": <int>,   # the REAL counts
#      "input_token_estimate": <int>,                        # the heuristic again
#      "input_estimate_drift": <int>   # prompt_tokens - input_token_estimate (I-3:
#                                      # the heuristic's measured drift, exposed)
#   }
#
# COUNCIL_* CODE FAMILY (distinct, never collapsed — REQ-INF-012):
#   COUNCIL_INFERENCE_OK        success, non-empty completion
#   COUNCIL_BUDGET_EXCEEDED     estimate > cap, NO call made (REQ-INF-006)
#   COUNCIL_MISSING_SECRET      no key on a real (non-dry-run) call (REQ-INF-011)
#   COUNCIL_INSUFFICIENT_CREDIT HTTP 402 (REQ-INF-012, EDGE-INF-005)
#   COUNCIL_RATE_LIMITED        HTTP 429, fail-closed, no retry (REQ-INF-013)
#   COUNCIL_MODEL_UNAVAILABLE   5xx/other non-2xx, malformed, 2xx-no-completion,
#                               usage absent/misshaped (REQ-INF-012, I-1, I-2)
#   COUNCIL_TIMEOUT             connection error / socket timeout (EDGE-INF-008)
#
# Exit codes: 0 for any successfully-CLASSIFIED outcome (incl. classified aborts —
# classification IS success, REQ-INF-014); no raw Python traceback may reach output.
# An unknown subcommand / argparse error is non-zero.
#
# Per-REQ kritische semantische Glättung (Beat 0 boundary gate):
#   The ONE real boundary (POST .../chat/completions) is SCOPED OUT of the offline
#   suite by the spec (OQ-3 `ungeprüft`, REQ-INF-015 injectable seam, REQ-INF-016
#   smoke lives OUTSIDE run_all.sh). The slice-level counter-thesis ("built but never
#   invoked for real") is ALREADY COVERED by the env-gated real smoke (EV-INF-006)
#   and stays RED(confidence) in the Reality Ledger — so it is NOT re-asserted here as
#   a missing gap. Everything below is PURE in-process logic (body-build / estimate /
#   cap-order / dry-run / classify / redact) driven against the INJECTED transport.
#   No invented network/NaN/overflow failure modes beyond the spec's own classified
#   ones; each Schärfung is a real falsifying assertion on the LOGIC, inline below.
#   Honesty: these assertions are `integration-fake`; NONE claims real OpenRouter
#   invocability or real diversity (that is earned only by the smoke, one model only).
# ===========================================================================

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"
cd "$REPO_DIR" || exit 1
# shellcheck source=config/claude/tests/lib.sh
source "$HERE/lib.sh"

# The coder selects the module placement by setting this default (create the module
# here, or point at council_backend.py). Default mirrors the new-sibling option.
MOD="${COUNCIL_INFERENCE_MODULE:-config/claude/lib/council_inference.py}"
SENTINEL="sk-or-LEAKCANARY-DO-NOT-PRINT-9f3c1a"
MSGS='[{"role":"user","content":"ping"}]'

# Per-test scratch dir for the injected call-counter files.
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT

# Helper: run the inference CLI under a clean, injected env (env -i) so no real key
# leaks in and the test is hermetic regardless of the developer's shell. Mirrors the
# council() helper in test_council_backend.sh (OD-3 OD-3 style).
infer() { # infer <env-assignments-as-string> -- <cli args...>
  local envstr="$1"; shift
  [ "${1:-}" = "--" ] && shift
  # shellcheck disable=SC2086  # $envstr is intentionally word-split into KEY=VALUE tokens for env -i
  env -i PATH="$PATH" $envstr python3 "$MOD" "$@" 2>&1
}

# Helper: read an injected call-counter file (absent/empty => 0 calls).
calls() { # calls <counter-file>
  if [ -s "$1" ]; then cat "$1"; else printf '0'; fi
}

printf 'OpenRouter Inference Path — Phase-1 acceptance contract (RED until implemented)\n'

# --- Module presence (drives the RED state before implementation) -----------
assert_file "council_inference module exists" "$MOD"

# ===========================================================================
# 1. EXPLICIT max_tokens IS SENT  (REQ-INF-004 CRITICAL, AC-INF-001, EDGE-INF-004)
#    These: "the request is built." Gegenthese: a cap is unenforceable if the
#    request never SENDS max_tokens — the model can return unbounded output and the
#    "cap" is theatre (REQ-INF-004 calls a capless call FORBIDDEN). Schärfung:
#    inspect the built body and assert an explicit max_tokens field is present.
# ===========================================================================
body="$(infer "OPENROUTER_API_KEY=$SENTINEL" -- infer --messages "$MSGS" --max-tokens 256 --input-estimate 100 --build-only --json)"
assert_contains "REQ-INF-004 built request body contains an explicit max_tokens field" "$body" '"max_tokens"'
assert_contains "REQ-INF-004 the sent max_tokens carries the requested value (256)" "$body" "256"
assert_contains "AC-INF-001 build-only emits the request_body it WOULD send" "$body" '"request_body"'
# Gegenthese kill: the body must also carry the messages (a real prompt, not empty).
assert_contains "AC-INF-001 request body carries the messages array" "$body" '"messages"'
# REQ-INF-004 negative: the raw key must NEVER be in the built body (it goes only in
# the Authorization header, which --build-only does NOT emit).
assert "REQ-INF-004/NFR-INF-001 raw key absent from the built request body" "! printf '%s' \"$body\" | grep -qF '$SENTINEL'"

# ===========================================================================
# 2. ESTIMATE = input_token_estimate + max_tokens, LABELED APPROXIMATE
#    (REQ-INF-005, AC-INF-001) — and the heuristic is NAMED (I-3).
#    These: "we estimate the cost." Gegenthese: an estimate that silently equals
#    only max_tokens (or only the input) under-counts and lets an over-budget run
#    through. Schärfung: assert total_estimate == input + max_tokens exactly, and
#    that it is disclosed as approximate (≈) — a named heuristic, not a billing oracle.
# ===========================================================================
est="$(infer "OPENROUTER_API_KEY=$SENTINEL" -- infer --messages "$MSGS" --max-tokens 256 --input-estimate 100 --dry-run --json)"
assert_contains "REQ-INF-005 estimate exposes the named input_token_estimate heuristic" "$est" '"input_token_estimate"'
assert_contains "REQ-INF-005 estimate echoes the sent max_tokens" "$est" '"max_tokens"'
# 100 + 256 = 356 — the load-bearing sum (NOT 256, NOT 100).
assert_contains "REQ-INF-005 total_estimate == input_token_estimate + max_tokens (356)" "$est" "356"
assert_contains "REQ-INF-005 estimate is labeled approximate (≈)" "$est" '"approximate": true'

# ===========================================================================
# 3. CAP ENFORCED BEFORE THE NETWORK CALL — FAIL-CLOSED, ZERO CALLS
#    (REQ-INF-006, NFR-INF-007, AC-INF-002, EDGE-INF-003, CAN-INF-015)
#    These: "there is a budget cap." Gegenthese: a cap computed but checked only
#    AFTER the call has already spent the credits is worthless — the exact incident
#    "spend money only on purpose" exists to prevent. Schärfung: with an estimate
#    OVER the cap, assert COUNCIL_BUDGET_EXCEEDED *and* that the injected transport
#    counter is still 0 (the call never happened).
# ===========================================================================
CC_OVER="$SCRATCH/over.calls"
over="$(infer "OPENROUTER_API_KEY=$SENTINEL COUNCIL_MAX_TOKENS_PER_RUN=20000" -- infer --messages "$MSGS" --max-tokens 5000 --input-estimate 19000 --inject-response '{"choices":[{"message":{"content":"should never run"}}]}' --inject-call-counter "$CC_OVER" --json)"
assert_contains "REQ-INF-006 over-cap estimate aborts COUNCIL_BUDGET_EXCEEDED" "$over" "COUNCIL_BUDGET_EXCEEDED"
assert_contains "AC-INF-002 over-cap decision is abort" "$over" '"decision": "abort"'
assert_eq "NFR-INF-007 over-cap made ZERO transport calls (cap checked BEFORE call)" "0" "$(calls "$CC_OVER")"
# Negative: an over-cap run must NOT emit a success code even though a fake response was injected.
assert "AC-INF-002 over-cap never returns COUNCIL_INFERENCE_OK" "! printf '%s' \"$over\" | grep -qF 'COUNCIL_INFERENCE_OK'"

# EDGE-INF-002: estimate EXACTLY equal to the cap is WITHIN cap => proceeds (one
# deterministic boundary rule). input 19000 + max 1000 = 20000 == cap.
CC_EQ="$SCRATCH/eq.calls"
eq="$(infer "OPENROUTER_API_KEY=$SENTINEL COUNCIL_MAX_TOKENS_PER_RUN=20000" -- infer --messages "$MSGS" --max-tokens 1000 --input-estimate 19000 --inject-response '{"choices":[{"message":{"content":"ok"}}],"usage":{"prompt_tokens":19000,"completion_tokens":3}}' --inject-call-counter "$CC_EQ" --json)"
assert_contains "EDGE-INF-002 estimate == cap is within cap (proceeds)" "$eq" '"decision": "proceed"'
assert_eq "EDGE-INF-002 within-cap run made exactly ONE transport call" "1" "$(calls "$CC_EQ")"

# AC-INF-003: within-cap + valid completion => exactly one POST, completion returned.
CC_OK="$SCRATCH/ok.calls"
ok="$(infer "OPENROUTER_API_KEY=$SENTINEL COUNCIL_MAX_TOKENS_PER_RUN=20000" -- infer --messages "$MSGS" --max-tokens 64 --input-estimate 50 --inject-response '{"choices":[{"message":{"content":"PONG-INFER-MARKER"}}],"usage":{"prompt_tokens":48,"completion_tokens":2}}' --inject-call-counter "$CC_OK" --json)"
assert_contains "AC-INF-003 within-cap proceeds with COUNCIL_INFERENCE_OK" "$ok" "COUNCIL_INFERENCE_OK"
assert_contains "AC-INF-003 the completion text is returned" "$ok" "PONG-INFER-MARKER"
assert_eq "AC-INF-003 within-cap valid completion = exactly ONE transport call" "1" "$(calls "$CC_OK")"

# ===========================================================================
# 4. DRY-RUN SPENDS NOTHING  (REQ-INF-008, AC-INF-004)
#    These: "dry-run is free." Gegenthese: a dry-run that quietly still calls the
#    API (to 'check' the model) spends credits while pretending not to. Schärfung:
#    dry-run returns the estimate AND the injected transport counter stays 0.
# ===========================================================================
CC_DRY="$SCRATCH/dry.calls"
dry="$(infer "OPENROUTER_API_KEY=$SENTINEL" -- infer --messages "$MSGS" --max-tokens 256 --input-estimate 100 --dry-run --inject-call-counter "$CC_DRY" --json)"
assert_contains "REQ-INF-008 dry-run reports the estimate" "$dry" '"total_estimate"'
assert_contains "AC-INF-004 dry-run decision is dry-run" "$dry" '"decision": "dry-run"'
assert_eq "AC-INF-004 dry-run made ZERO transport calls (0 credits)" "0" "$(calls "$CC_DRY")"

# ===========================================================================
# 5. POST-CALL RECONCILIATION AGAINST usage  (REQ-INF-009, AC-INF-005)
#    + I-1 graceful-degrade + I-3 input-estimate DRIFT measurement.
#    These: "we get token counts back." Gegenthese (I-1): the `usage` shape is
#    `ungeprüft` (OQ-3) — code that ASSUMES it is present will crash or fabricate
#    numbers when it is absent/misshaped. Gegenthese (I-3): an estimate whose drift
#    against the real prompt_tokens is never compared is an unmeasurable heuristic.
#    Schärfung: with usage present, reconcile and EXPOSE the drift; with usage
#    absent/misshaped, classify COUNCIL_MODEL_UNAVAILABLE (don't crash, don't fake).
# ===========================================================================
rec="$(infer "OPENROUTER_API_KEY=$SENTINEL" -- infer --messages "$MSGS" --max-tokens 64 --input-estimate 40 --inject-response '{"choices":[{"message":{"content":"hi"}}],"usage":{"prompt_tokens":55,"completion_tokens":2}}' --json)"
assert_contains "REQ-INF-009 reconciliation surfaces real prompt_tokens" "$rec" '"prompt_tokens"'
assert_contains "REQ-INF-009 reconciliation surfaces real completion_tokens" "$rec" '"completion_tokens"'
assert_contains "AC-INF-005 reconciliation reports the input_token_estimate heuristic" "$rec" '"input_token_estimate"'
# I-3 drift: real prompt_tokens 55 - input_token_estimate 40 = 15. The drift MUST be
# exposed so the heuristic's fidelity is MEASURABLE (not silently swallowed).
assert_contains "I-3 reconciliation exposes input_estimate_drift" "$rec" '"input_estimate_drift"'
assert_contains "I-3 the measured drift value is exactly prompt_tokens-estimate (55-40=15), signed per contract" "$rec" '"input_estimate_drift": 15'

# I-1 graceful-degrade: a 2xx whose body OMITS usage MUST classify COUNCIL_MODEL_UNAVAILABLE
# (do NOT crash, do NOT invent token numbers). usage shape is the contract-under-test.
nousage="$(infer "OPENROUTER_API_KEY=$SENTINEL" -- infer --messages "$MSGS" --max-tokens 64 --input-estimate 40 --inject-response '{"choices":[{"message":{"content":"hi"}}]}' --json 2>&1)"
assert_contains "I-1 usage-absent body classifies COUNCIL_MODEL_UNAVAILABLE" "$nousage" "COUNCIL_MODEL_UNAVAILABLE"
assert "I-1 usage-absent path does NOT raise a Python traceback" "! printf '%s' \"$nousage\" | grep -qE 'Traceback|KeyError|TypeError'"

# I-1 misshaped usage (wrong types) MUST also degrade, not crash.
badusage="$(infer "OPENROUTER_API_KEY=$SENTINEL" -- infer --messages "$MSGS" --max-tokens 64 --input-estimate 40 --inject-response '{"choices":[{"message":{"content":"hi"}}],"usage":"not-an-object"}' --json 2>&1)"
assert_contains "I-1 misshaped usage classifies COUNCIL_MODEL_UNAVAILABLE" "$badusage" "COUNCIL_MODEL_UNAVAILABLE"
assert "I-1 misshaped usage does NOT raise a Python traceback" "! printf '%s' \"$badusage\" | grep -qE 'Traceback|KeyError|TypeError'"

# ===========================================================================
# 6. CLASSIFIED ERRORS — DISTINCT, NEVER COLLAPSED  (REQ-INF-012/013/014,
#    EDGE-INF-005..008, AC-INF-006..009, NFR-INF-002)
#    These: "errors are handled." Gegenthese: collapsing every HTTPError into one
#    generic code hides WHY a model failed — a caller can't tell "out of credit"
#    from "rate limited" from "down", so it can't branch (the OD-3 catalog path
#    DOES collapse; the inference path MUST NOT — REQ-INF-012). Schärfung: each
#    injected failure class maps to its OWN distinct code; 429 fails closed (no retry).
# ===========================================================================
# 402 -> insufficient credit.
e402="$(infer "OPENROUTER_API_KEY=$SENTINEL" -- infer --messages "$MSGS" --max-tokens 64 --input-estimate 40 --inject-error http-402 --json 2>&1)"
assert_contains "EDGE-INF-005/AC-INF-006 HTTP 402 -> COUNCIL_INSUFFICIENT_CREDIT" "$e402" "COUNCIL_INSUFFICIENT_CREDIT"
assert "AC-INF-006 402 path emits no raw traceback" "! printf '%s' \"$e402\" | grep -qE 'Traceback|HTTPError'"

# 429 -> rate limited, Retry-After RECORDED, NO auto-retry (exactly one call).
CC_429="$SCRATCH/r429.calls"
e429="$(infer "OPENROUTER_API_KEY=$SENTINEL" -- infer --messages "$MSGS" --max-tokens 64 --input-estimate 40 --inject-error http-429 --inject-retry-after 30 --inject-call-counter "$CC_429" --json 2>&1)"
assert_contains "EDGE-INF-006/AC-INF-007 HTTP 429 -> COUNCIL_RATE_LIMITED" "$e429" "COUNCIL_RATE_LIMITED"
assert_contains "EDGE-INF-006 429 records the Retry-After value (30)" "$e429" "30"
assert_eq "REQ-INF-013/AC-INF-007 429 fails closed — exactly ONE call, NO auto-retry" "1" "$(calls "$CC_429")"

# 5xx / other non-2xx -> unavailable.
e500="$(infer "OPENROUTER_API_KEY=$SENTINEL" -- infer --messages "$MSGS" --max-tokens 64 --input-estimate 40 --inject-error http-500 --json 2>&1)"
assert_contains "EDGE-INF-007/AC-INF-008 HTTP 500 -> COUNCIL_MODEL_UNAVAILABLE" "$e500" "COUNCIL_MODEL_UNAVAILABLE"

# timeout / connection error -> timeout.
etimeout="$(infer "OPENROUTER_API_KEY=$SENTINEL" -- infer --messages "$MSGS" --max-tokens 64 --input-estimate 40 --inject-error timeout --json 2>&1)"
assert_contains "EDGE-INF-008/AC-INF-009 timeout -> COUNCIL_TIMEOUT" "$etimeout" "COUNCIL_TIMEOUT"

# malformed / non-JSON body -> unavailable, classified, no traceback.
emal="$(infer "OPENROUTER_API_KEY=$SENTINEL" -- infer --messages "$MSGS" --max-tokens 64 --input-estimate 40 --inject-error malformed --json 2>&1)"
assert_contains "EDGE-INF-009/AC-INF-010 malformed body -> COUNCIL_MODEL_UNAVAILABLE" "$emal" "COUNCIL_MODEL_UNAVAILABLE"
assert "AC-INF-010 malformed body does NOT raise a Python traceback" "! printf '%s' \"$emal\" | grep -qE 'Traceback|JSONDecodeError|ValueError'"

# DISTINCTNESS guard: the five classes must NOT collapse to a single code. 402 and
# 429 in particular must differ (the load-bearing non-collapse — REQ-INF-012).
assert "REQ-INF-012 402 and 429 are DISTINCT codes (not collapsed)" "! printf '%s' \"$e429\" | grep -qF 'COUNCIL_INSUFFICIENT_CREDIT'"
assert "REQ-INF-012 timeout and unavailable are DISTINCT codes" "! printf '%s' \"$etimeout\" | grep -qF 'COUNCIL_MODEL_UNAVAILABLE'"

# ===========================================================================
# 7. [I-2] 2xx WITH NO USABLE COMPLETION  (carried constraint I-2, EDGE-INF-009/011)
#    These: "HTTP 200 means success." Gegenthese: a 200 whose body has empty/missing
#    choices[].message.content, OR is an {"error":...} envelope, raises no exception
#    and parses as JSON — naive code reports a FALSE SUCCESS (empty completion sold as
#    a real answer). Schärfung: such a 2xx MUST classify COUNCIL_MODEL_UNAVAILABLE,
#    deterministically, never a crash and never COUNCIL_INFERENCE_OK.
# ===========================================================================
# 2xx with empty content.
i2_empty="$(infer "OPENROUTER_API_KEY=$SENTINEL" -- infer --messages "$MSGS" --max-tokens 64 --input-estimate 40 --inject-response '{"choices":[{"message":{"content":""}}],"usage":{"prompt_tokens":40,"completion_tokens":0}}' --json 2>&1)"
assert_contains "I-2 2xx empty completion -> COUNCIL_MODEL_UNAVAILABLE" "$i2_empty" "COUNCIL_MODEL_UNAVAILABLE"
assert "I-2 2xx empty completion is NOT a false success" "! printf '%s' \"$i2_empty\" | grep -qF 'COUNCIL_INFERENCE_OK'"

# 2xx with missing choices entirely.
i2_nochoices="$(infer "OPENROUTER_API_KEY=$SENTINEL" -- infer --messages "$MSGS" --max-tokens 64 --input-estimate 40 --inject-response '{"usage":{"prompt_tokens":40,"completion_tokens":0}}' --json 2>&1)"
assert_contains "I-2 2xx missing choices -> COUNCIL_MODEL_UNAVAILABLE" "$i2_nochoices" "COUNCIL_MODEL_UNAVAILABLE"

# 2xx that is actually an {"error":...} envelope.
i2_errbody="$(infer "OPENROUTER_API_KEY=$SENTINEL" -- infer --messages "$MSGS" --max-tokens 64 --input-estimate 40 --inject-response '{"error":{"message":"model offline","code":502}}' --json 2>&1)"
assert_contains "I-2 2xx {error:...} envelope -> COUNCIL_MODEL_UNAVAILABLE" "$i2_errbody" "COUNCIL_MODEL_UNAVAILABLE"
assert "I-2 2xx error-envelope is NOT a false success" "! printf '%s' \"$i2_errbody\" | grep -qF 'COUNCIL_INFERENCE_OK'"
assert "I-2 2xx error-envelope does NOT leak its body as a completion" "! printf '%s' \"$i2_errbody\" | grep -qF 'model offline'"

# ===========================================================================
# 8. MISSING KEY FAIL-CLOSED  (REQ-INF-011, AC-INF-012, EDGE-INF-001)
#    These: "the key is read." Gegenthese: a real call with NO key either crashes
#    or worse dumps the environment. Schärfung: missing key on a non-dry-run call
#    => COUNCIL_MISSING_SECRET, NO network call, NO env dump.
# ===========================================================================
CC_NOKEY="$SCRATCH/nokey.calls"
nokey="$(infer "COUNCIL_MAX_TOKENS_PER_RUN=20000" -- infer --messages "$MSGS" --max-tokens 64 --input-estimate 40 --inject-response '{"choices":[{"message":{"content":"x"}}],"usage":{"prompt_tokens":40,"completion_tokens":1}}' --inject-call-counter "$CC_NOKEY" --json)"
assert_contains "EDGE-INF-001/AC-INF-012 missing key -> COUNCIL_MISSING_SECRET" "$nokey" "COUNCIL_MISSING_SECRET"
assert_eq "AC-INF-012 missing-key path made ZERO transport calls" "0" "$(calls "$CC_NOKEY")"
assert "AC-INF-012 missing-key path does NOT dump the OPENROUTER_API_KEY env name" "! printf '%s' \"$nokey\" | grep -q 'OPENROUTER_API_KEY='"

# Dry-run WITHOUT a key is still free and does NOT require a secret (no call to make).
drynokey="$(infer "" -- infer --messages "$MSGS" --max-tokens 64 --input-estimate 40 --dry-run --json)"
assert_contains "REQ-INF-008 dry-run works without a key (no call to authorize)" "$drynokey" '"decision": "dry-run"'

# ===========================================================================
# 9. SECRET REDACTION ACROSS EVERY OUTPUT/ERROR PATH  (NFR-INF-001, AC-INF-011, RISK-INF-001)
#    These: "the key authorizes the call." Gegenthese: a green success path can still
#    leak the key in an ERROR or RESULT structure even if the success path is clean.
#    Schärfung: the sentinel key must appear in NONE of: build-only / success /
#    estimate / budget-exceeded / 402 / 429 / 500 / timeout / malformed / I-2 outputs.
# ===========================================================================
for label in "build:$body" "ok:$ok" "estimate:$est" "budget:$over" "credit:$e402" "ratelimit:$e429" "unavail:$e500" "timeout:$etimeout" "malformed:$emal" "i2empty:$i2_empty"; do
  name="${label%%:*}"; payload="${label#*:}"
  assert "NFR-INF-001 sentinel key absent from the $name path" "! printf '%s' \"$payload\" | grep -qF '$SENTINEL'"
done

# ===========================================================================
# 10. CONFIGURABLE MODEL, FREE DEFAULT, RUNTIME-VERIFIED (NOT hardcoded truth)
#     (REQ-INF-010, AC-INF-013)
#     These: "there is a default model." Gegenthese: hardcoding a free model id as
#     STABLE TRUTH re-introduces the OD-3 sin (a listed id is not guaranteed live).
#     A user-set COUNCIL_INFERENCE_MODEL must override it for ANY OpenRouter id.
#     Schärfung: a user-set model id appears in the built body; default resolves when
#     unset; neither output ASSERTS the model is invocable (that stays smoke-only).
# ===========================================================================
usermodel="$(infer "OPENROUTER_API_KEY=$SENTINEL COUNCIL_INFERENCE_MODEL=vendor/custom-model" -- infer --messages "$MSGS" --max-tokens 64 --input-estimate 40 --build-only --json)"
assert_contains "AC-INF-013 user-set COUNCIL_INFERENCE_MODEL overrides the default in the body" "$usermodel" "vendor/custom-model"

defmodel="$(infer "OPENROUTER_API_KEY=$SENTINEL" -- infer --messages "$MSGS" --max-tokens 64 --input-estimate 40 --build-only --json)"
assert_contains "AC-INF-013 a model id is resolved when COUNCIL_INFERENCE_MODEL is unset (free default)" "$defmodel" '"model"'
# Honesty: offline output must NOT claim the model is invocable/reachable — invocability
# is earned only by the env-gated smoke, for the one probed model (RISK-INF-006).
assert "RISK-INF-006 build-only does NOT claim real invocability/reachability offline" "! printf '%s' \"$defmodel\" | grep -qiE '\"invocable\": *true|\"reachable\": *true'"

# ===========================================================================
# REALITY-LEDGER / NETWORK-FREE GUARD (honesty invariant — mirrors OD-3 OD-3).
# These are integration-fake. There must be NO `infer` flag/path that performs a
# REAL network call from this suite: the ONLY transport is the injected seam, and a
# transport-reaching run REQUIRES one of --inject-response / --inject-error. A run
# that reaches the transport with NEITHER injected MUST classify (e.g. bad-input /
# missing-injection) rather than fall back to a real urlopen — proving the offline
# suite can never spend a credit (REQ-INF-015, AC-INF-014, CAN-INF-EVN-001).
# ===========================================================================
CC_GUARD="$SCRATCH/guard.calls"
noinject="$(infer "OPENROUTER_API_KEY=$SENTINEL COUNCIL_MAX_TOKENS_PER_RUN=20000" -- infer --messages "$MSGS" --max-tokens 64 --input-estimate 40 --inject-call-counter "$CC_GUARD" --json 2>&1)"
assert_eq "REQ-INF-015 a transport-reaching run with NO injected response/error makes ZERO real calls" "0" "$(calls "$CC_GUARD")"
assert "REQ-INF-015 no-injection run classifies (does not fall through to a real urlopen)" "printf '%s' \"$noinject\" | grep -qE 'COUNCIL_[A-Z_]+'"
assert "REQ-INF-015 no-injection run does NOT raise a Python traceback" "! printf '%s' \"$noinject\" | grep -qE 'Traceback'"

# ===========================================================================
# 8. BUILD-REVIEW FIXES (independent review, 2026-06-19)
#    C1: a gated --live opt-in must route to the real transport, but --live
#    WITHOUT COUNCIL_INFERENCE_LIVE=1 must stay OFFLINE (no real call) — so the
#    offline suite (which never sets that env) can never reach the network.
#    SEC: a non-positive --max-tokens must be rejected BEFORE any transport call
#    (an unbounded/negative value would shrink the estimate under the cap).
# ===========================================================================
LIVE_CTR="$(mktemp)"
live_nogate="$(infer "OPENROUTER_API_KEY=$SENTINEL" -- infer --messages "$MSGS" --max-tokens 16 --input-estimate 5 --live --inject-call-counter "$LIVE_CTR" --json 2>&1)"
assert "C1 --live WITHOUT COUNCIL_INFERENCE_LIVE makes ZERO real calls (gate off)" "[ \"$(cat "$LIVE_CTR" 2>/dev/null || echo X)\" = 0 ]"
assert_contains "C1 --live ungated stays offline-classified COUNCIL_MODEL_UNAVAILABLE" "$live_nogate" "COUNCIL_MODEL_UNAVAILABLE"
assert "C1 --live ungated raises no traceback" "! printf '%s' \"$live_nogate\" | grep -qE 'Traceback'"
assert "C1 --live ungated never leaks the key" "! printf '%s' \"$live_nogate\" | grep -qF '$SENTINEL'"

# SEC: negative max_tokens + an injected success body — WITHOUT the fix this would
# proceed (estimate 5+(-50)<cap) and call the transport (counter=1) returning _OK;
# WITH the fix it is rejected before the transport (counter=0, not _OK).
NEG_CTR="$(mktemp)"
neg="$(infer "OPENROUTER_API_KEY=$SENTINEL" -- infer --messages "$MSGS" --max-tokens -50 --input-estimate 5 --inject-response '{"choices":[{"message":{"content":"hi"}}],"usage":{"prompt_tokens":5,"completion_tokens":2}}' --inject-call-counter "$NEG_CTR" --json 2>&1)"
assert "SEC negative max_tokens is rejected BEFORE the transport (ZERO calls)" "[ \"$(cat "$NEG_CTR" 2>/dev/null || echo X)\" = 0 ]"
assert "SEC negative max_tokens is NOT a success (_OK)" "! printf '%s' \"$neg\" | grep -qF 'COUNCIL_INFERENCE_OK'"
assert "SEC negative max_tokens raises no traceback" "! printf '%s' \"$neg\" | grep -qE 'Traceback'"
rm -f "$LIVE_CTR" "$NEG_CTR"

finish "OpenRouter Inference Path acceptance contract"
