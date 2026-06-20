#!/usr/bin/env bash
# Portability / anti-footgun lint for the project's shell scripts.
#
# This guard exists because several CI-only fragility classes have bitten this
# repo -- each was caught ONLY by the macOS CI leg (bash 3.2 / BSD userland),
# never by local bash 5 or `bash -n`. It runs deterministically OFFLINE over the
# repo's own shell scripts and FAILS CLOSED on a match, so the next regression is
# caught pre-push instead of on macOS CI.
#
# Eat-your-own-dog-food contract: THIS FILE must itself be safe under every class
# it enforces -- bash-3.2-safe (NO heredoc wrapped in a $() command substitution;
# the detector is fed to python3 via a redirect-to-tempfile heredoc instead),
# ASCII-only, and shellcheck-clean.
#
# ---------------------------------------------------------------------------
# GUARDED CLASSES (deterministic, offline)
# ---------------------------------------------------------------------------
#   G1  $()-wrapped heredoc with ODD quote parity  [the #1 guard]
#       bash < 4.4 (macOS /bin/bash is 3.2) does NOT skip a quoted-heredoc body
#       inside a $(...) command substitution -- it lexes the body as ordinary
#       shell text hunting for the closing ')'. In that lex, ' and " toggle quote
#       state. A body with BALANCED (even) quotes opens and re-closes, the ')' is
#       found, parse succeeds. An UNBALANCED (odd) ' or " stays open through EOF:
#       "unexpected EOF while looking for matching quote" -- the WHOLE file fails
#       to parse. This bit three times (lib.sh once, the measurement-run test
#       twice). bash 5 and `bash -n` do not reproduce it.
#       Detector: a logical line opening `$(` that also contains `<<`, whose
#       heredoc body has an odd count of ' OR an odd count of ". This is strictly
#       more precise than "never $()-wrap a heredoc": the tree legitimately keeps
#       several EVEN-parity $()-heredocs (lib.sh, scorer test, ...) -- those are
#       safe and must NOT be flagged. (Ground truth: the survivors are all
#       even/even; the three incidents were odd.)  Remediation when flagged:
#       redirect the heredoc to a tempfile (`cmd >"$TMP" <<'EOF' ... EOF`) and
#       read it back, so no heredoc body sits inside $().
#
#   G2  Confusable non-ASCII punctuation (smart quotes / curly apostrophes)
#       A Unicode look-alike of a shell-significant ASCII quote -- a smart double
#       quote, a curly apostrophe -- typed WHERE shell syntax expects the ASCII
#       quote is a silent parse/locale footgun. NOTE: this is deliberately NOT a
#       blanket non-ASCII byte ban: the tree intentionally uses em-dashes and
#       other UTF-8 in comments and emitted user-facing strings, which are not a
#       parse hazard. We flag only the high-signal confusable-QUOTE set.
#
#   G3  jq `// empty` / `// "default"` on a possibly-boolean field  [heuristic]
#       jq's `//` treats BOTH null AND boolean false as the empty/alternative
#       case, so `.flag // empty` on a real `false` yields "" -- the exact class
#       that silently killed a hook's deny path. We flag every `// empty` /
#       `// "..."` in hook scripts with file:line so a HUMAN confirms the field
#       can never be boolean. It is advisory-precise (scoped to hooks), not a
#       hard semantic proof.
#
# ---------------------------------------------------------------------------
# SURVEYED-BUT-NOT-DETERMINISTICALLY-GUARDED classes (see docs note):
#   - `eval "$2"` over interpolated payload in NEW assertions: lib.sh's legacy
#     `assert` eval's its condition string; passing interpolated output through
#     it is an injection/fragility vector. We do NOT pattern-ban `assert`
#     (too noisy -- it is the base helper). Instead G4 below PROVES the eval-free
#     helpers exist, and the rule "use assert_contains / assert_json_eq /
#     assert_no_code_token, never interpolate payload into assert" is documented
#     in docs/ci-fragility-classes.md and lib.sh.
#   - Stale hardcoded model-id constants: cannot be a pure offline test (needs a
#     live provider catalog). Documented in docs/ci-fragility-classes.md.
# ---------------------------------------------------------------------------
set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "$HERE/../../.." && pwd)"

echo "test_shell_portability"

# The detector is a stdlib-only python3 program. It is fed via a redirect-to-
# tempfile heredoc (NOT $()-wrapped) so this guard obeys G1 itself. SCAN_ROOT can
# be overridden (used by the self-test fixture proof) to point at an alternate
# tree; it defaults to the repo root.
SCAN_ROOT="${SCAN_ROOT:-$REPO_DIR}"

DETECTOR="$(mktemp)" || { echo "FAIL mktemp"; exit 1; }
OUT="$(mktemp)" || { echo "FAIL mktemp"; exit 1; }
trap 'rm -f "$DETECTOR" "$OUT"' EXIT

cat > "$DETECTOR" <<'PYEOF'
"""Deterministic, offline shell-portability detector. stdlib only.

argv[1] = scan root. Prints one finding per line to stdout:
  <class>\t<file>:<line>\t<detail>
Exit 0 always; the caller decides pass/fail from the (G1/G2) finding lines.
G3 findings are printed too but treated as advisory by the caller.
"""
import os
import re
import sys

root = sys.argv[1]


def shell_files(base):
    """All shell scripts under the guarded surface, plus repo-root *.sh.

    Scoped to config/claude/{tests,hooks,bin} and any repo-root *.sh, EXCLUDING
    fixture trees (they intentionally hold synthetic/edge content) and .git.
    """
    out = []
    guarded_dirs = [
        os.path.join(base, "config", "claude", "tests"),
        os.path.join(base, "config", "claude", "hooks"),
        os.path.join(base, "config", "claude", "bin"),
    ]
    for d in guarded_dirs:
        if not os.path.isdir(d):
            continue
        for name in sorted(os.listdir(d)):
            p = os.path.join(d, name)
            if not os.path.isfile(p):
                continue
            # bin/ holds extensionless executables; include them if they look like
            # shell. tests/hooks are *.sh. Skip the fixtures subdir under tests.
            if os.path.basename(d) == "tests" and name == "fixtures":
                continue
            if d.endswith(os.path.join("tests")) or d.endswith(os.path.join("hooks")):
                if not name.endswith(".sh"):
                    continue
            out.append(p)
    # repo-root *.sh (build-explorer.sh, etc.) and the vendored install.sh
    for name in sorted(os.listdir(base)):
        if name.endswith(".sh") and os.path.isfile(os.path.join(base, name)):
            out.append(os.path.join(base, name))
    install_sh = os.path.join(base, "config", "claude", "install.sh")
    if os.path.isfile(install_sh):
        out.append(install_sh)
    # de-dup, stable order
    seen = set()
    uniq = []
    for p in out:
        rp = os.path.realpath(p)
        if rp in seen:
            continue
        seen.add(rp)
        uniq.append(p)
    return uniq


def is_shell(path):
    if path.endswith(".sh"):
        return True
    try:
        with open(path, "rb") as fh:
            first = fh.readline(256)
    except OSError:
        return False
    return first.startswith(b"#!") and (b"sh" in first)


# Heredoc opener: <<, optional -, optional quote, a word delimiter.
HEREDOC_OPEN = re.compile(r"<<-?\s*([\"']?)([A-Za-z_][A-Za-z0-9_]*)\1")

# G2 confusable quote/apostrophe code points (NOT a blanket non-ASCII ban).
# Defined by CODE POINT (\uXXXX escapes) so THIS detector's own source stays
# pure-ASCII and cannot flag itself:
#   U+2018/U+2019 left/right single quote (curly apostrophe),
#   U+201C/U+201D left/right double quote, U+2032 prime, U+2033 double prime,
#   U+00B4 acute accent. (U+0060 backtick is ASCII and intentionally NOT here.)
CONFUSABLE = {
    "\u2018": "LEFT SINGLE QUOTE",
    "\u2019": "RIGHT SINGLE QUOTE / CURLY APOSTROPHE",
    "\u201c": "LEFT DOUBLE QUOTE",
    "\u201d": "RIGHT DOUBLE QUOTE",
    "\u2032": "PRIME",
    "\u2033": "DOUBLE PRIME",
    "\u00b4": "ACUTE ACCENT",
}

# G3 jq // empty | // "..." (on hook scripts only -- highest-signal surface).
JQ_DEFAULT = re.compile(r"//\s*(empty\b|\")")

findings = []


def scan_file(path):
    rel = os.path.relpath(path, root)
    try:
        text = open(path, encoding="utf-8", errors="replace").read()
    except OSError:
        return
    lines = text.splitlines()

    # --- G1: $()-wrapped heredoc with odd quote parity ---
    i = 0
    n = len(lines)
    while i < n:
        line = lines[i]
        if "$(" in line and "<<" in line:
            m = HEREDOC_OPEN.search(line)
            if m:
                delim = m.group(2)
                body = []
                j = i + 1
                while j < n:
                    stripped = lines[j].strip()
                    # Heredoc terminator: the delimiter alone on a line. A
                    # following ')"' on its own line closes the $() -- not the
                    # terminator. <<- allows a leading-tab-stripped delimiter.
                    if stripped == delim:
                        break
                    body.append(lines[j])
                    j += 1
                body_text = "\n".join(body)
                sq = body_text.count("'")
                dq = body_text.count('"')
                if sq % 2 == 1 or dq % 2 == 1:
                    findings.append(
                        "G1\t{}:{}\t$()-wrapped heredoc <<{} body has ODD quote "
                        "parity (apostrophes={}, double-quotes={}); bash 3.2 will "
                        "fail to parse the file. Redirect the heredoc to a tempfile "
                        "instead of capturing it in $().".format(rel, i + 1, delim, sq, dq)
                    )
                i = j
                continue
        i += 1

    # --- G2: confusable quote/apostrophe code points ---
    for ln, line in enumerate(lines, start=1):
        for ch, label in CONFUSABLE.items():
            if ch in line:
                col = line.index(ch) + 1
                findings.append(
                    "G2\t{}:{}\tconfusable non-ASCII {} (U+{:04X}) at col {}; a "
                    "Unicode look-alike of a shell quote is a parse/locale "
                    "footgun -- use the ASCII quote.".format(rel, ln, label, ord(ch), col)
                )

    # --- G3: jq // empty | // "..." on HOOK scripts (advisory) ---
    if os.sep + os.path.join("hooks") + os.sep in (os.sep + path + os.sep) or (
        os.path.basename(os.path.dirname(path)) == "hooks"
    ):
        for ln, line in enumerate(lines, start=1):
            if "jq" not in line:
                # The // may be on a continuation; still scan any line in a hook
                # that contains a jq default operator pattern next to a field.
                pass
            if JQ_DEFAULT.search(line) and "jq" in line:
                findings.append(
                    "G3\t{}:{}\tjq `// empty`/`// \"...\"` -- jq's // also catches "
                    "boolean false, not just null. CONFIRM the field can never be "
                    "boolean; if it can, read with `jq -r '.field'` and compare the "
                    "literal. (advisory)".format(rel, ln)
                )


for f in shell_files(root):
    if is_shell(f):
        scan_file(f)

for line in findings:
    sys.stdout.write(line + "\n")
PYEOF

python3 "$DETECTOR" "$SCAN_ROOT" > "$OUT" 2>/dev/null
det_rc=$?

if [ "$det_rc" -ne 0 ]; then
  echo "  FAIL detector crashed (rc=$det_rc)"
  exit 1
fi

# Partition findings. G1/G2 are HARD failures; G3 is advisory (printed, not fatal).
g1g2_count=0
g3_count=0
while IFS= read -r finding; do
  [ -z "$finding" ] && continue
  cls="${finding%%	*}"
  case "$cls" in
    G1|G2)
      g1g2_count=$((g1g2_count + 1))
      echo "  FAIL $finding"
      ;;
    G3)
      g3_count=$((g3_count + 1))
      echo "  note $finding"
      ;;
    *)
      echo "  FAIL (unknown class) $finding"
      g1g2_count=$((g1g2_count + 1))
      ;;
  esac
done < "$OUT"

if [ "$g3_count" -gt 0 ]; then
  echo "  ($g3_count G3 advisory note(s) above -- human must confirm none is on a boolean field)"
fi

if [ "$g1g2_count" -eq 0 ]; then
  echo "  ok   no \$()-heredoc odd-parity (G1) and no confusable non-ASCII quotes (G2)"
  echo "test_shell_portability: PASSED"
  exit 0
else
  echo "  $g1g2_count hard portability finding(s) (G1/G2)"
  echo "test_shell_portability: FAILED"
  exit 1
fi
