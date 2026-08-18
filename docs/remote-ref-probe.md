# The remote-ref probe

`plumbline-ref-probe` answers exactly one question: **what OIDs does the remote have,
right now, for these exact refs?**

It is deliberately **not** a PR-state provider, not a lifecycle, and not a merge detector.
`ls-remote` shows ref tips; it cannot say *why* a ref moved or vanished. Overclaiming here
is how an earlier attempt reported "the branch was merged into the base" for an unrelated
hotfix.

```bash
plumbline-ref-probe probe --repo . --remote origin \
  --ref refs/heads/main --ref refs/heads/feat/x \
  --expect refs/heads/main=<oid> \
  --expect-url <bound-remote-url> \
  --timeout 4
```

Output is structured JSON on **stdout**; diagnostics stay on stderr.

## Classes

| class | meaning |
|---|---|
| `REMOTE_REF_UNCHANGED` | every bound ref matches the remote as it is right now |
| `REMOTE_REF_CHANGED` | a bound ref resolves to a different OID |
| `REMOTE_REF_NOT_PUBLISHED` | a ref with **no** expectation is absent — a branch not pushed yet. A fact, not a failure. |
| `REMOTE_REF_MISSING` | a ref that **was** bound is gone from the remote |
| `REMOTE_IDENTITY_CHANGED` | the remote name or URL is not the bound one |
| `REMOTE_UNREACHABLE` | the remote could not be contacted |
| `REMOTE_AUTH_FAILED` | credentials refused or unavailable |
| `REMOTE_TIMEOUT` | no answer inside the internal budget |
| `REMOTE_OUTPUT_MALFORMED` | the answer was not exactly what was asked for |
| `MALFORMED_REQUEST` | the caller asked for something ambiguous |

Exit codes: **0** pass · **3** changed/missing/identity · **4** malformed request ·
**5** unverified (unreachable / auth / timeout / malformed output).

## Contract

- **Exact full ref names only.** `refs/heads/<branch>`. A short name is refused as
  `MALFORMED_REQUEST` rather than resolved by guessing, and `refs/heads/feat/x` is never
  satisfied by `refs/heads/feat/xy`.
- **Never reads `origin/*`.** A remote-tracking ref is a cached answer to a question asked
  earlier. If the remote cannot be consulted the answer is `REMOTE_UNREACHABLE` — never the
  cache.
- **Identity is checked before the refs.** A swapped remote URL is `REMOTE_IDENTITY_CHANGED`,
  not a fresh valid starting point.
- **Process properties:** `GIT_TERMINAL_PROMPT=0`, stdin closed, internal timeout well below
  any hook budget, stdout and stderr separate.
- **Parsing is strict:** exactly one valid OID per requested ref; an unrequested ref, a
  duplicate, a non-OID token or a truncated line is `REMOTE_OUTPUT_MALFORMED`.
- **No cache, no TTL.** The probe is meant to run before each write-capable call. A time
  window would re-admit exactly the write-after-remote-change it exists to stop. Latency and
  cry-wolf get measured separately, later.

## What this does NOT solve

Deliberately out of scope, tracked as separate lifecycle tasks: GO arming · PR binding ·
Task/Agent/MCP write coverage · recovery · unified exit-code classification across consumers
· forge state (draft/open/merged) · the Reality Ledger entry.

## Evidence ceiling

Exercised against **local** git remotes and deterministic `git-remote-*` helper stubs — no
network, no real forge, no authenticated host. `REMOTE_AUTH_FAILED` is proven against a
helper that reports an auth failure, and "no prompt is opened" is proven by an `GIT_ASKPASS`
canary that is never touched; a **real** credential prompt on a real host has not been
exercised. `REMOTE_OUTPUT_MALFORMED` is unreachable end-to-end — real git rejects a broken
transport itself and that is classified `REMOTE_UNREACHABLE` — so the parser is covered by a
**unit** test, and labelled as one.
