# CI fragility classes (build / run / architecture)

This note catalogs the fragility classes that have bitten this project's CI -- several
caught ONLY by the macOS leg of the matrix (bash 3.2 / BSD userland), never by local
bash 5 or `bash -n`. It records which classes now have a DETERMINISTIC offline guard and
which are surveyed-but-unguarded (so they stay visible rather than silently forgotten).

The deterministic guards live in `config/claude/tests/test_shell_portability.sh`, wired
into `config/claude/tests/run_all.sh` (which CI runs on every push, on both Linux and
macOS).

## Guarded (deterministic, offline)

- **G1 -- `$()`-wrapped heredoc with ODD quote parity (the #1 guard).**
  bash < 4.4 (macOS `/bin/bash` is 3.2) does not skip a quoted-heredoc body inside a
  `$(...)` command substitution: it lexes the body as ordinary shell text hunting for the
  closing `)`, and `'`/`"` toggle quote state during that lex. A body with BALANCED (even)
  quotes re-closes and parses; an UNBALANCED (odd) `'` or `"` stays open through EOF
  ("unexpected EOF while looking for matching quote") and the WHOLE file fails to parse.
  This bit three times (`lib.sh` once, the measurement-run test twice). The guard flags a
  logical line opening `$(` that also contains `<<` whose heredoc body has an odd `'` or
  odd `"` count. This is strictly more precise than "never `$()`-wrap a heredoc": the tree
  legitimately keeps several EVEN-parity `$()`-heredocs, which are safe and are not
  flagged. Remediation when flagged: redirect the heredoc to a tempfile
  (`cmd >"$TMP" <<'EOF' ... EOF`) and read it back, so no heredoc body sits inside `$()`.

- **G2 -- confusable non-ASCII punctuation (smart quotes / curly apostrophes).**
  A Unicode look-alike of a shell-significant ASCII quote (smart double quote, curly
  apostrophe, prime, acute accent) typed where shell syntax expects the ASCII quote is a
  silent parse/locale footgun. This is deliberately NOT a blanket non-ASCII byte ban: the
  tree intentionally uses em-dashes and other UTF-8 in comments and in emitted
  user-facing strings, which are not a parse hazard. The guard flags only the high-signal
  confusable-QUOTE code points.

- **G3 -- jq `// empty` / `// "default"` on a possibly-boolean field (heuristic, advisory).**
  jq's `//` treats BOTH `null` AND boolean `false` as the empty/alternative case, so
  `.flag // empty` on a real `false` yields `""` -- the exact class that once silently
  killed a hook's deny path. The guard prints every `// empty` / `// "..."` in hook scripts
  with `file:line` so a human confirms the field can never be boolean. It is advisory
  (printed, non-fatal), scoped to hooks, because proving a JSON field is never boolean is
  not decidable from the shell source alone.

## Surveyed but NOT deterministically guarded

- **`eval "$2"` over interpolated payload in assertions.** `lib.sh`'s legacy `assert`
  helper runs `eval "$2"`; passing interpolated command output through it is an injection +
  fragility vector (a backtick in a payload once executed a command). This is NOT pattern-
  banned because `assert` is the base helper and a blanket ban would be noisy/false-positive.
  Instead the eval-free helpers (`assert_contains`, `assert_not_contains`, `assert_json_eq`,
  `assert_no_code_token`) exist and are documented in `lib.sh`; the rule is: never
  interpolate payload/output into `assert` -- use the eval-free helpers. A future precise
  guard could flag NEW `assert "..." "...$VAR..."` call sites (interpolation inside the
  eval'd second argument) without touching the legacy helper, but that needs careful
  shell-aware parsing to avoid noise and is not yet implemented.

- **Stale hardcoded model-id constants.** Hardcoded provider model ids (e.g. council /
  inference backends) go stale when a provider retires or renames a model. This cannot be a
  PURE offline test -- verifying an id is still served needs a live provider catalog call
  (which is non-deterministic and network-gated, and would violate the offline-CI contract).
  A live catalog smoke (opt-in, env-gated, like the existing real-boundary smokes) is the
  right home for it, not `run_all.sh`. Tracked here so the staleness risk stays visible.

- **GNU-vs-BSD userland flag drift.** GNU-only flags (`tar`, `sed -i`, `date`, `grep -P`)
  silently differ on macOS BSD userland; one such case (`tar`) already RED-ed macOS CI and
  was fixed by switching to Python `tarfile`. There is no single deterministic lint for this
  class today; the macOS CI leg itself is the backstop. Prefer Python stdlib or POSIX-portable
  invocations over GNU-specific flags in new shell code.
