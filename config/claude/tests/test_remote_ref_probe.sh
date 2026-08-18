#!/usr/bin/env bash
# The remote-ref probe, in isolation. `ls-remote` ONLY: exact ref names, parsing,
# process properties, timeout, and remote identity.
#
# SCOPE, deliberately narrow. This module knows nothing about run states, PR
# binding, GO arming, hooks, write coverage or recovery. Two previous slices died
# by growing one monolithic integration test whose fixtures never reached the
# state that broke; this one validates the primitive and stops.
#
# What the probe is: proof of CURRENT remote refs. What it is NOT: a PR-state
# provider. `ls-remote` shows ref tips. It cannot say WHY a ref moved or vanished,
# so this module never classifies a merge -- P13 pins that.
#
# Failure injection uses GIT REMOTE HELPERS (`<helper>::<address>` invokes
# `git-remote-<helper>` from PATH), so hang / auth-failure / malformed-output are
# deterministic and need no production seam and no network.
#
# Portability: bash-3.2 safe (NO $()-wrapped heredocs), shellcheck-clean.
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"

# shellcheck source=lib.sh
. "$HERE/lib.sh"

echo "test_remote_ref_probe"

PROBE="$REPO_DIR/config/claude/bin/plumbline-ref-probe"

if ! command -v jq >/dev/null 2>&1; then
  _skip "jq not installed; the probe's output is structured JSON"
  finish "test_remote_ref_probe"
  exit $?
fi

WORK="$(mktemp -d)"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT
NOHOME="$WORK/nohome"
STUBS="$WORK/stubs"
mkdir -p "$NOHOME" "$STUBS"

SANITISED_PATH=""
_old_ifs="$IFS"
IFS=':'
for _p in $PATH; do
  [ -n "$_p" ] || continue
  [ -e "$_p/plumbline-ref-probe" ] && continue
  if [ -n "$SANITISED_PATH" ]; then SANITISED_PATH="$SANITISED_PATH:$_p"; else SANITISED_PATH="$_p"; fi
done
IFS="$_old_ifs"

# --- deterministic remote helpers ---------------------------------------------
# `git ls-remote hang::x` runs git-remote-hang. Nothing here touches the network.
cat >"$STUBS/git-remote-plhang" <<'EOF'
#!/bin/sh
while IFS= read -r line; do
  case "$line" in
    capabilities) printf 'fetch\n\n' ;;
    list) sleep 300 ;;
    "") exit 0 ;;
    *) printf '\n' ;;
  esac
done
EOF
cat >"$STUBS/git-remote-plauth" <<'EOF'
#!/bin/sh
# Anything that wants credentials it cannot get, without opening a prompt.
echo "fatal: Authentication failed for 'https://example.invalid/repo.git'" >&2
exit 128
EOF
cat >"$STUBS/git-remote-plgarbage" <<'EOF'
#!/bin/sh
while IFS= read -r line; do
  case "$line" in
    capabilities) printf 'fetch\n\n' ;;
    list)
      # Not an OID, a duplicate ref, and a truncated line.
      printf 'not-a-valid-object-id refs/heads/main\n'
      printf 'deadbeefdeadbeefdeadbeefdeadbeefdeadbeef refs/heads/main\n'
      printf 'garbage-without-a-ref\n'
      printf '\n'
      ;;
    "") exit 0 ;;
    *) printf '\n' ;;
  esac
done
EOF
chmod +x "$STUBS"/git-remote-*
STUB_PATH="$STUBS:$SANITISED_PATH"

# Sets: P_JSON P_RC P_STATUS ; stdout must be pure JSON, stderr kept separate.
probe() { # probe <path-for-git> <args...>
  local gitpath="$1"
  shift
  local outf errf
  outf="$WORK/p.out"
  errf="$WORK/p.err"
  env PATH="$gitpath" HOME="$NOHOME" "$PROBE" "$@" >"$outf" 2>"$errf"
  P_RC=$?
  P_JSON="$(cat "$outf")"
  P_ERR="$(cat "$errf")"
  P_STATUS="$(printf '%s' "$P_JSON" | jq -r '.status // ""' 2>/dev/null)"
  export P_JSON P_RC P_STATUS P_ERR
}
ref_class() { printf '%s' "$P_JSON" | jq -r --arg r "$1" '.refs[$r].class // ""' 2>/dev/null; }
ref_oid()   { printf '%s' "$P_JSON" | jq -r --arg r "$1" '.refs[$r].oid // ""' 2>/dev/null; }

# A real local origin with main published and a feature branch NOT published.
make_repo() { # make_repo -> prints repo path
  local bare repo
  bare="$(mktemp -d "$WORK/origin.XXXXXX")"
  repo="$(mktemp -d "$WORK/repo.XXXXXX")"
  git init -q --bare "$bare"
  mkdir -p "$repo/src"
  printf 'x\n' >"$repo/src/a"
  git -C "$repo" init -q
  git -C "$repo" config user.email p@example.com
  git -C "$repo" config user.name "P"
  git -C "$repo" checkout -q -b main
  git -C "$repo" add -A
  git -C "$repo" commit -q -m base
  git -C "$repo" remote add origin "$bare"
  git -C "$repo" push -q origin main
  git -C "$repo" checkout -q -b feat/x
  printf 'y\n' >>"$repo/src/a"
  git -C "$repo" commit -qam work
  printf '%s' "$repo"
}
origin_of() { git -C "$1" remote get-url origin; }

############################################################################
# P1 — unchanged base, and stdout is pure structured JSON
############################################################################
r1="$(make_repo)"
main_oid="$(git -C "$r1" rev-parse main)"
probe "$SANITISED_PATH" probe --repo "$r1" --remote origin \
  --ref refs/heads/main --expect "refs/heads/main=$main_oid" \
  --expect-url "$(origin_of "$r1")"
assert_eq "P1: an unchanged base ref passes" "0" "$P_RC"
assert_eq "P1: overall status" "REMOTE_REF_UNCHANGED" "$P_STATUS"
assert_eq "P1: per-ref class" "REMOTE_REF_UNCHANGED" "$(ref_class refs/heads/main)"
assert_eq "P1: the reported OID is the remote's" "$main_oid" "$(ref_oid refs/heads/main)"
assert "P1: stdout is valid JSON and nothing else" \
  "printf '%s' \"\$P_JSON\" | jq -e . >/dev/null 2>&1"
assert "P1: diagnostics never contaminate stdout" \
  "! printf '%s' \"\$P_JSON\" | grep -q 'PRIL_RUNTIME'"

############################################################################
# P2 — the base moves on the remote while the local ref stays stale
############################################################################
r2="$(make_repo)"
old_oid="$(git -C "$r2" rev-parse main)"
other="$(mktemp -d "$WORK/other.XXXXXX")"
git clone -q "$(origin_of "$r2")" "$other" 2>/dev/null
git -C "$other" checkout -q main
git -C "$other" config user.email p@example.com
git -C "$other" config user.name "P"
printf 'moved\n' >>"$other/src/a"
git -C "$other" commit -qam moved
git -C "$other" push -q origin main
new_oid="$(git -C "$other" rev-parse main)"
assert "P2 precondition: the remote main really moved" "[ '$new_oid' != '$old_oid' ]"
assert "P2 precondition: the local origin/main really is stale" \
  "[ \"\$(git -C '$r2' rev-parse origin/main 2>/dev/null)\" = '$old_oid' ]"
probe "$SANITISED_PATH" probe --repo "$r2" --remote origin \
  --ref refs/heads/main --expect "refs/heads/main=$old_oid"
assert_eq "P2: a moved base is CHANGED" "REMOTE_REF_CHANGED" "$P_STATUS"
assert_eq "P2: and the probe reports the REMOTE oid, not the cached one" \
  "$new_oid" "$(ref_oid refs/heads/main)"
assert_eq "P2: exit code 3" "3" "$P_RC"

############################################################################
# P3/P4 — an unpublished head is NOT_PUBLISHED; publishing invents nothing
############################################################################
r3="$(make_repo)"
probe "$SANITISED_PATH" probe --repo "$r3" --remote origin \
  --ref refs/heads/main --ref refs/heads/feat/x
assert_eq "P3: an unpublished head is not an error" "0" "$P_RC"
assert_eq "P3: it is classified NOT_PUBLISHED" \
  "REMOTE_REF_NOT_PUBLISHED" "$(ref_class refs/heads/feat/x)"
git -C "$r3" push -q origin feat/x
head_oid="$(git -C "$r3" rev-parse feat/x)"
probe "$SANITISED_PATH" probe --repo "$r3" --remote origin \
  --ref refs/heads/main --ref refs/heads/feat/x
assert_eq "P4: once published the head is reported with its OID" \
  "$head_oid" "$(ref_oid refs/heads/feat/x)"
assert_eq "P4: appearing is not a change when nothing was expected" "0" "$P_RC"
assert "P4: the probe never mentions pull requests at all" \
  "! printf '%s' \"\$P_JSON\" | grep -qi 'pull_request\\|\"pr\"\\|isDraft'"

############################################################################
# P5/P6 — a bound head that is force-pushed, then deleted
############################################################################
probe "$SANITISED_PATH" probe --repo "$r3" --remote origin \
  --ref refs/heads/feat/x --expect "refs/heads/feat/x=$head_oid"
assert_eq "P5 control: a bound, unchanged head passes" "0" "$P_RC"
git -C "$r3" reset -q --hard HEAD~1
printf 'rewritten\n' >>"$r3/src/a"
git -C "$r3" commit -qam rewritten
git -C "$r3" push -q --force origin feat/x
probe "$SANITISED_PATH" probe --repo "$r3" --remote origin \
  --ref refs/heads/feat/x --expect "refs/heads/feat/x=$head_oid"
assert_eq "P5: a force-pushed head is CHANGED" "REMOTE_REF_CHANGED" "$P_STATUS"
assert_eq "P5: exit 3" "3" "$P_RC"

git -C "$r3" push -q origin --delete feat/x
probe "$SANITISED_PATH" probe --repo "$r3" --remote origin \
  --ref refs/heads/feat/x --expect "refs/heads/feat/x=$head_oid"
assert_eq "P6: a DELETED bound ref is MISSING, not NOT_PUBLISHED" \
  "REMOTE_REF_MISSING" "$(ref_class refs/heads/feat/x)"
assert_eq "P6: exit 3" "3" "$P_RC"
assert "P6: the probe does not claim it was merged -- ls-remote cannot know why" \
  "! printf '%s' \"\$P_JSON\" | grep -qi 'merge'"

############################################################################
# P7 — the remote URL is swapped after binding
############################################################################
r7="$(make_repo)"
bound_url="$(origin_of "$r7")"
decoy="$(mktemp -d "$WORK/decoy.XXXXXX")"
git init -q --bare "$decoy"
git -C "$r7" push -q "$decoy" main
git -C "$r7" remote set-url origin "$decoy"
probe "$SANITISED_PATH" probe --repo "$r7" --remote origin \
  --ref refs/heads/main --expect-url "$bound_url"
assert_eq "P7: a swapped remote URL is REMOTE_IDENTITY_CHANGED" \
  "REMOTE_IDENTITY_CHANGED" "$P_STATUS"
assert_eq "P7: exit 3 -- a different remote is not a fresh valid starting point" "3" "$P_RC"

############################################################################
# P8 — authentication failure, and no prompt is opened
############################################################################
r8="$(make_repo)"
git -C "$r8" remote set-url origin "plauth::x"
CANARY="$WORK/askpass-was-called"
cat >"$STUBS/askpass.sh" <<EOF
#!/bin/sh
touch "$CANARY"
echo "hunter2"
EOF
chmod +x "$STUBS/askpass.sh"
env PATH="$STUB_PATH" HOME="$NOHOME" GIT_ASKPASS="$STUBS/askpass.sh" \
  "$PROBE" probe --repo "$r8" --remote origin --ref refs/heads/main \
  >"$WORK/p.out" 2>"$WORK/p.err"
P_RC=$?
P_JSON="$(cat "$WORK/p.out")"
P_STATUS="$(printf '%s' "$P_JSON" | jq -r '.status // ""' 2>/dev/null)"
assert_eq "P8: an auth failure is REMOTE_AUTH_FAILED, distinct from unreachable" \
  "REMOTE_AUTH_FAILED" "$P_STATUS"
assert_eq "P8: exit 5 -- unverified, never a pass" "5" "$P_RC"
assert "P8: no credential prompt was opened" "[ ! -f '$CANARY' ]"
assert "P8: the implementation disables terminal prompting" \
  "grep -q 'GIT_TERMINAL_PROMPT' '$REPO_DIR/config/claude/lib/plumbline_ref_probe.py'"
assert "P8: and closes stdin" \
  "grep -q 'DEVNULL' '$REPO_DIR/config/claude/lib/plumbline_ref_probe.py'"

############################################################################
# P9 — the server does not answer inside the internal timeout
############################################################################
r9="$(make_repo)"
git -C "$r9" remote set-url origin "plhang::x"
T0=$SECONDS
probe "$STUB_PATH" probe --repo "$r9" --remote origin --ref refs/heads/main --timeout 2
ELAPSED=$((SECONDS - T0))
assert_eq "P9: a hanging remote is REMOTE_TIMEOUT, distinct from unreachable" \
  "REMOTE_TIMEOUT" "$P_STATUS"
assert_eq "P9: exit 5" "5" "$P_RC"
assert "P9: and it returns inside the internal budget (measured ${ELAPSED}s)" \
  "[ '$ELAPSED' -lt 15 ]"

############################################################################
# P10 — malformed / ambiguous output is refused, never parsed optimistically
############################################################################
# MEASURED: real git refuses a malformed transport itself, so the bytes never
# reach our parser and the honest end-to-end classification is UNREACHABLE, not
# OUTPUT_MALFORMED. Asserting OUTPUT_MALFORMED here would have been a claim about
# a code path this fixture cannot reach.
r10="$(make_repo)"
git -C "$r10" remote set-url origin "plgarbage::x"
probe "$STUB_PATH" probe --repo "$r10" --remote origin --ref refs/heads/main
assert_eq "P10a: git rejects a malformed transport first -- classified, never a pass" \
  "REMOTE_UNREACHABLE" "$P_STATUS"
assert_eq "P10a: exit 5 -- unverified" "5" "$P_RC"

# P10b -- the parser itself, exercised directly. This is a UNIT test and is
# labelled as one: it is the only place the OUTPUT_MALFORMED branch is reachable.
# The driver is written to a FILE, never a heredoc inside $(...): bash 3.2 does
# not skip a quoted heredoc body when scanning for the closing paren, which this
# repo has already been bitten by twice.
PARSE_DRIVER="$WORK/parse_driver.py"
cat >"$PARSE_DRIVER" <<'PYDRV'
import sys
sys.path.insert(0, sys.argv[1])
from plumbline_ref_probe import parse_ls_remote
status, seen, detail = parse_ls_remote(sys.argv[2], ["refs/heads/main"])
print(status or "OK")
PYDRV

parse_case() { # parse_case <label> <stdout-text> <expected-status>
  local got
  got="$(env PATH="$SANITISED_PATH" python3 "$PARSE_DRIVER" \
    "$REPO_DIR/config/claude/lib" "$2" 2>/dev/null)"
  assert_eq "P10b parser: $1" "$3" "$got"
}
OID_A="deadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
OID_B="deadbeefdeadbeefdeadbeefdeadbeefdeadbeee"
TAB="$(printf '\t')"
parse_case "a non-OID token is refused" \
  "not-a-valid-object-id${TAB}refs/heads/main" "REMOTE_OUTPUT_MALFORMED"
parse_case "a duplicated ref is refused" \
  "${OID_A}${TAB}refs/heads/main
${OID_B}${TAB}refs/heads/main" "REMOTE_OUTPUT_MALFORMED"
parse_case "an unrequested ref is refused" \
  "${OID_A}${TAB}refs/heads/other" "REMOTE_OUTPUT_MALFORMED"
parse_case "a truncated line is refused" \
  "garbage-without-a-ref" "REMOTE_OUTPUT_MALFORMED"
parse_case "a well-formed answer is accepted" \
  "${OID_A}${TAB}refs/heads/main" "OK"

############################################################################
# P11 — exact full ref names. No substring, no ambiguous resolution.
############################################################################
r11="$(make_repo)"
git -C "$r11" push -q origin feat/x
git -C "$r11" checkout -q -b feat/xy
git -C "$r11" push -q origin feat/xy
probe "$SANITISED_PATH" probe --repo "$r11" --remote origin --ref refs/heads/feat/x
assert_eq "P11: exactly one ref is reported" "1" \
  "$(printf '%s' "$P_JSON" | jq -r '.refs | length')"
assert "P11: the near-miss ref is not matched by substring" \
  "! printf '%s' \"\$P_JSON\" | grep -q 'refs/heads/feat/xy'"
probe "$SANITISED_PATH" probe --repo "$r11" --remote origin --ref feat/x
assert_eq "P11: a short branch name is refused, not resolved ambiguously" "4" "$P_RC"
assert_eq "P11: classified as a malformed request" "MALFORMED_REQUEST" "$P_STATUS"

############################################################################
# P12 — an unreachable remote NEVER falls back to a healthy local cache
############################################################################
r12="$(make_repo)"
cached="$(git -C "$r12" rev-parse origin/main)"
assert "P12 precondition: a healthy local origin/main exists" "[ -n '$cached' ]"
git -C "$r12" remote set-url origin "$WORK/does-not-exist.git"
probe "$SANITISED_PATH" probe --repo "$r12" --remote origin \
  --ref refs/heads/main --expect "refs/heads/main=$cached"
assert_eq "P12: an unreachable remote is REMOTE_UNREACHABLE" "REMOTE_UNREACHABLE" "$P_STATUS"
assert_eq "P12: exit 5 -- the cached ref is NOT accepted as proof" "5" "$P_RC"
assert "P12: the probe never reads origin/* as a substitute" \
  "! grep -q 'rev-parse' '$REPO_DIR/config/claude/lib/plumbline_ref_probe.py'"

############################################################################
# P13 — the probe does not overclaim. It reports ref tips, never a reason.
############################################################################
# Behavioural, not grep-based: the first version of these assertions matched the
# module's own docstring (which explains why it must NOT classify merges) and so
# failed while the code was correct. What matters is what the probe EMITS and
# what its interface offers.
HELP_OUT="$(env PATH="$SANITISED_PATH" "$PROBE" probe --help 2>&1 || true)"
export HELP_OUT   # read inside the assert below, via eval
assert "P13: the CLI surface offers no PR/draft/merge concept" \
  "! printf '%s' \"\$HELP_OUT\" | grep -qiE 'draft|pull.request|merge'"
probe "$SANITISED_PATH" probe --repo "$r1" --remote origin --ref refs/heads/main
assert "P13: a normal result carries no merge or PR vocabulary" \
  "! printf '%s' \"\$P_JSON\" | grep -qiE 'merge|draft|pull_request'"
assert "P13: the result schema is exactly refs + remote + status + detail" \
  "[ \"\$(printf '%s' \"\$P_JSON\" | jq -r 'keys | join(\",\")')\" = 'detail,refs,remote,schema,status' ]"

############################################################################
# Counter-mutations. Three, as required: freshness removed, remote-swap
# detection removed, timeout fail-open.
#
# Mutations are EXACT LITERAL replacements that fail loudly when the target text
# is absent. The precondition is not "the file differs" -- a failed replacement
# leaves an empty or unparseable file, which also differs. And a mutant module
# must ship its sibling, or it dies on ImportError and the assertion passes
# because NOTHING RAN. Both are lessons paid for in earlier slices.
############################################################################

mutate_probe() { # mutate_probe <name> <old> <new> -> prints mutant dir
  local name="$1"
  local dir="$WORK/mut-$name"
  mkdir -p "$dir"
  cp "$REPO_DIR/config/claude/lib/plumbline_cli.py" "$dir/"
  python3 "$WORK/mutate.py" "$REPO_DIR/config/claude/lib/plumbline_ref_probe.py" \
    "$dir/plumbline_ref_probe.py" "$2" "$3" 2>/dev/null
  printf '%s' "$dir"
}
cat >"$WORK/mutate.py" <<'PYMUT'
import pathlib, sys
src, dst, old, new = sys.argv[1:5]
text = pathlib.Path(src).read_text()
if old not in text:
    sys.stderr.write("MUTATION TARGET NOT FOUND\n")
    raise SystemExit(2)
pathlib.Path(dst).write_text(text.replace(old, new))
PYMUT

# Called indirectly through assert's eval; ShellCheck cannot see that call edge.
# shellcheck disable=SC2317
mutant_ok() { # mutant_ok <dir> -- differs, substantial, parses, and RUNS
  local f="$1/plumbline_ref_probe.py"
  local orig="$REPO_DIR/config/claude/lib/plumbline_ref_probe.py"
  [ -f "$f" ] || return 1
  cmp -s "$orig" "$f" && return 1
  local o m
  o="$(wc -c <"$orig" | tr -d ' ')"
  m="$(wc -c <"$f" | tr -d ' ')"
  [ "$m" -gt $((o / 2)) ] || return 1
  env PATH="$SANITISED_PATH" python3 -c "import ast,sys; ast.parse(open(sys.argv[1]).read())" "$f" >/dev/null 2>&1 || return 1
  # It must actually execute -- an ImportError mutant proves nothing.
  env PATH="$SANITISED_PATH" python3 "$f" probe --repo "$REPO_DIR" --remote origin \
    --ref refs/heads/main >/dev/null 2>&1
  [ "$?" -ne 1 ] || return 1
  return 0
}

run_mutant() { # run_mutant <dir> <repo> <args...>
  local dir="$1" repo="$2"
  shift 2
  M_JSON="$(env PATH="$STUB_PATH" HOME="$NOHOME" python3 "$dir/plumbline_ref_probe.py" \
    probe --repo "$repo" --remote origin "$@" 2>/dev/null)"
  M_RC=$?
  M_STATUS="$(printf '%s' "$M_JSON" | jq -r '.status // ""' 2>/dev/null)"
  export M_JSON M_RC M_STATUS
}

# CM-A: freshness removed -- answer from the local cache instead of the remote.
# Freshness removed: answer from the LOCAL remote-tracking refs, mapped back to
# the requested names so the parser is satisfied and ONLY the freshness differs.
# Two earlier versions of this mutation failed for unrelated reasons (wrong ref
# names in the output) -- a counter-mutation that dies on a technicality proves
# nothing about the guard it targets.
CMA_NEW='    _st = subprocess.run(["git","-C",str(repo),"for-each-ref","--format=%(objectname) %(refname)"] + ["refs/remotes/" + remote + "/" + r[len("refs/heads/"):] for r in refs], capture_output=True, text=True).stdout
    _st = "\n".join(q[0] + "\t" + q[1].replace("refs/remotes/" + remote + "/", "refs/heads/") for q in (l.split() for l in _st.splitlines()) if len(q) == 2)
    problem, seen, detail = parse_ls_remote(_st, refs)'
CMA="$(mutate_probe nofresh '    problem, seen, detail = parse_ls_remote(proc.stdout, refs)' "$CMA_NEW")"
assert "CM-A precondition: the remote read was actually replaced" "mutant_ok '$CMA'"
cma_repo="$(make_repo)"
cma_old="$(git -C "$cma_repo" rev-parse main)"
cma_other="$(mktemp -d "$WORK/cmao.XXXXXX")"
git clone -q "$(origin_of "$cma_repo")" "$cma_other" 2>/dev/null
git -C "$cma_other" checkout -q main
git -C "$cma_other" config user.email p@example.com
git -C "$cma_other" config user.name "P"
printf 'moved\n' >>"$cma_other/src/a"
git -C "$cma_other" commit -qam moved
git -C "$cma_other" push -q origin main
cma_new="$(git -C "$cma_other" rev-parse main)"
assert "CM-A precondition: the remote main really moved" "[ '$cma_new' != '$cma_old' ]"
assert "CM-A precondition: the local cache is still stale" \
  "[ \"\$(git -C '$cma_repo' rev-parse origin/main 2>/dev/null)\" = '$cma_old' ]"
run_mutant "$CMA" "$cma_repo" --ref refs/heads/main --expect "refs/heads/main=$cma_old"
assert "CM-A: answering from the local cache misses the remote change" \
  "[ '$M_RC' -eq 0 ]"

# CM-B: remote-swap detection removed.
CMB="$(mutate_probe noswap '    if expect_url is not None and url != expect_url:' \
  '    if False:')"
assert "CM-B precondition: the identity check was actually removed" "mutant_ok '$CMB'"
cmb_repo="$(make_repo)"
cmb_bound="$(origin_of "$cmb_repo")"
cmb_decoy="$(mktemp -d "$WORK/cmbd.XXXXXX")"
git init -q --bare "$cmb_decoy"
git -C "$cmb_repo" push -q "$cmb_decoy" main
git -C "$cmb_repo" remote set-url origin "$cmb_decoy"
run_mutant "$CMB" "$cmb_repo" --ref refs/heads/main --expect-url "$cmb_bound"
assert "CM-B: without the identity check a swapped remote passes" "[ '$M_RC' -eq 0 ]"
assert "CM-B: and it is not reported as an identity change" \
  "[ '$M_STATUS' != 'REMOTE_IDENTITY_CHANGED' ]"

# CM-C: the timeout fails OPEN instead of classifying.
CMC="$(mutate_probe timeoutopen '    except subprocess.TimeoutExpired:
        return TIMEOUT, None, f"the remote did not answer within {timeout}s"' \
  '    except subprocess.TimeoutExpired:
        class _P:
            returncode = 0
            stdout = ""
            stderr = ""
        return "", _P(), "MUTANT: timeout ignored"')"
assert "CM-C precondition: the timeout branch was actually changed" "mutant_ok '$CMC'"
cmc_repo="$(make_repo)"
git -C "$cmc_repo" remote set-url origin "plhang::x"
run_mutant "$CMC" "$cmc_repo" --ref refs/heads/main --timeout 2
assert "CM-C: a timeout treated as an empty answer stops being classified" \
  "[ '$M_STATUS' != 'REMOTE_TIMEOUT' ]"
assert "CM-C: and the run is no longer refused as unverified" "[ '$M_RC' -ne 5 ]"

finish "test_remote_ref_probe"
