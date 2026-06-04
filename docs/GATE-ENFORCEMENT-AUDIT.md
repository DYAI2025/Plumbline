# Gate Enforcement Audit — the Reality Ledger applied to Plumbline itself

> **Honest disclosure artifact.** This catalogs *how* every Plumbline gate is actually
> enforced — runtime fail-closed code vs. prose the model is merely asked to honor vs.
> a test that only guards wording. It is read-only: **no gate behavior was changed.**
>
> **By Plumbline's own Reality-Ledger standard, THIS DOCUMENT is evidence-class
> `unit-fake`:** it proves the catalog exists, not that any gate fires. It is the *map*
> that scopes the enforcement work (roadmap B1 dispatch-model enforcement, B2-conversion),
> not that work. Calling it "we hardened the gates" would be exactly the kind of
> looks-done-≠-is-done claim Plumbline exists to refuse. It is committed as `docs:`.

**Date:** 2026-06-04 · **Branch of origin:** `feat/gate-enforcement-audit`
**Method:** read-only inspection by independent inspectors that (a) **executed** the PRIL
Python modules against pass/fail fixtures to observe real exit codes, and (b)
cross-referenced every `config/claude/tests/*.sh`, `lib/*.py`, `bin/*`, `hooks/*.sh`,
`commands/agileteam.md`, `commands/concilium.md`, `.claude/settings.json`, and
`metrics/runs.jsonl`. Every row cites `file:line`.
**Scope limit (honest):** the inspectors read all enforcement code and all gate-relevant
tests; they did **not** read every agent `.md` line-by-line (e.g. `plumbline-watcher.md`),
but confirmed by grep that **no executable computes a Watcher verdict** anywhere.

---

## The enforcement classes (the audit's own ladder)

| Class | Meaning | Mechanically |
|-------|---------|--------------|
| **`machine-checked-runtime`** | A script **fails closed** when the gate's real condition is violated at runtime (non-zero exit / `decision:block`). | runs the gate against ground-truth, asserts refusal |
| **`drift-protection-only`** | A test asserts a **prose string is present** in a prompt/doc. Guards the governance text from silent erosion; does **not** prove the gate fires. | `grep -qF` / `grep -Fq` |
| **`structural-validation`** | Checks file/JSON/frontmatter **shape** or cross-source vocab consistency. | parse / `jq -e` / `py_compile` / set-equality |
| **`prompt-only`** | Only the model is **asked** to honor it; **no code checks it**. | — |
| **`un-enforceable-by-construction`** | Needs genuine human/model judgment, or has **no recordable substrate**. | — |

> **The load-bearing distinction this audit refuses to blur:** `machine-checked-runtime`
> means a script refuses work when the *behavior* is violated. `drift-protection-only`
> means a `grep` confirms a *sentence still exists*. Most of Plumbline's test suite is the
> second kind. Conflating them would make this honesty artifact commit the very sin it audits.

---

## Headline (the honest summary)

**Genuinely fail-closed at runtime = a narrow PRIL core**, all Python validators wired
(for scope/context/reality) into the `plumbline-enforce.sh` Stop hook which reads real
`git` ground-truth and emits `decision:block`:

- evidence-class floor (`plumbline_reality.py`),
- scope containment (`plumbline_scope.py`) — the strongest gate,
- context-artifact confirmation (`plumbline_context.py`),
- secret redaction (`plumbline_redact.py`) — real but **not** in the hook,
- resumable run-ledger state (`plumbline_run_ledger.py`),
- plus offline/CI instruments that fail closed on fixtures (metrics emitter, rule-ledger,
  challenge-token oracle, update layer) and the two Stop-hook transports + `install.sh`
  registration.

**Everything that makes `/agileteam` distinctive *as governance* is `prompt-only`** —
model-honored prose, guarded only by drift-protection tests:

- the Phase 0–8 **sequence/ordering**,
- the **Plumbline Watcher** verdicts (`pass`/`review-required`/`pause`/`blocked`),
- **wired-in-prod** — *the original incident the whole repo exists to prevent*,
- **no-silent-RED-downgrade** / escalation asymmetry,
- the **independence invariant** (writer ≠ reviewer; reviewer gets diff+spec, not the
  coder's reasoning),
- the **dispatch-model policy** (the "Opus-only safety net" claim),
- **Gates A–E** of Phase 3 (the only executable bolt-on is the embedded reality-check),
- the **Concilium** four-body mandate and its **fail-closed model-diversity** claim.

**Two structural caveats no reader may miss:**
1. The PRIL Stop hook is **not active in this repo's own sessions** — `.claude/settings.json`
   here registers only `SessionStart`. Both fail-closed Stop hooks fire **only after
   `install.sh` has registered them in the global `~/.claude/settings.json`** *and* the
   orchestrator wrote the `docs/context/.active-feature` marker (itself a prompt-only step).
2. **Most of the test suite is `grep`-presence on prose.** That has real value — it stops
   the governance text from being silently reworded or deleted — but it is drift protection,
   not behavioral enforcement.

---

## Table 1 — `machine-checked-runtime` (fail-closed code)

| Gate | Where | Fail-closed mechanism | Proven by | Honest caveat |
|------|-------|----------------------|-----------|---------------|
| **Reality-Ledger evidence-class floor** | `lib/plumbline_reality.py:89-129`, exits `:29-32`, RANKS/FORBIDDEN_TOKENS `:11-27` | reads `docs/reality/<feat>.evidence.jsonl`; `EXIT_INSUFFICIENT=3` when no record meets the floor or a FORBIDDEN_TOKEN (`fake-only/mock-only/placeholder/unverified`) appears; `2` missing, `4` malformed | `test_runtime_integrity_layer.sh:109-126` (executed live) | legacy alias class **`integration`** (rank 2) *passes* the default floor; only `*-fake` names + tokens are caught. Reality is **skipped unless** `docs/context/.feature-boundary` exists — a pure-logic feature is held to no floor. |
| **Scope containment** (strongest gate) | `lib/plumbline_scope.py:232-253`, broad-pattern reject `:162-173` | `EXIT_VIOLATION=3` when any changed file matches no Allowed-scope pattern; **refuses self-authored broad wildcards** (`*`/`**`) so a scope can't legitimize the whole repo | `test_pril_enforce_hook.sh:121-163, 311-345` (staged **and** untracked out-of-scope → `decision:block`) | fed by the hook's git surface, so even files no agent listed are caught |
| **Context-artifact gate** | `lib/plumbline_context.py:21-61`, markers/exits `:9-18` | requires canvas+prd+vision+`traceability.md` to exist; `EXIT_UNCONFIRMED=3` if an artifact lacks a `Status: user-confirmed` marker; `2` missing | `test_runtime_integrity_layer.sh:97-101` | the marker is a **string-presence** check — a file *containing* the literal passes; it does not prove a human signed (trust boundary = write-access to `docs/context/`) |
| **Secret redaction** | `lib/plumbline_redact.py:52-69` | `--mode check` → `EXIT_SECRET=3` on sk-/AKIA/`gh*_`/PRIVATE KEY/`TOKEN=…`; `4` malformed, `5` oversized | `test_runtime_integrity_layer.sh:166-179` | **not wired into `plumbline-enforce.sh`** — a manual CLI; fires only if the orchestrator calls it. Pattern-based (novel secret formats slip). |
| **Run-ledger resume/revalidate** | `lib/plumbline_run_ledger.py:143-179` | `resume-point` → `__START__` on missing/empty/**corrupt** ledger (never "all cleared"); `revalidate` exits `1` (`STALE`) unless latest row is `CLEARED` **and** `artifact_hash` matches | `test_run_ledger.sh:91-123` | `resume-point` signals fail-closed via the **stdout sentinel**, exit code is `0` in all cases — safe only if the orchestrator reads stdout. Passive: it governs only what the orchestrator chooses to record; `CLEARED` is whatever was written (a human clear is not independently verified). |
| **PRIL enforce Stop hook** (the transport) | `hooks/plumbline-enforce.sh:38-163`; registered `install.sh:185-222` | marker-driven (`docs/context/.active-feature`, **not** an env var the runtime never sets); blocks on empty/whitespace/malformed marker, on missing CLIs, on any non-zero gate; builds the changed-file surface from `merge-base..HEAD ∪ working ∪ staged ∪ untracked`; never exits non-zero ⇒ fails **closed** | `test_pril_enforce_hook.sh:99-345` (throwaway git repos) | **not active in this repo's sessions** (see caveat #1); only enforces scope+context+reality |
| **Learning-loop Stop hook** | `hooks/stop-learning-loop.sh:16-26` | sentinel-gated; emits `decision:block` to force the retro; honors `stop_hook_active` | `test_stop_hook.sh:23-41` | only **blocks the stop** — cannot verify the retro ran; the model self-clears the sentinel with `rm` |
| **Metrics emitter** (versioned/allowlist) | `metrics/emit_run.py` | `--dry-run` fails closed on non-allowlisted keys, invalid JSON, negative tokens, all-missing fingerprint | `test_metrics_contract.sh:18-166` | offline instrument, not a live-session gate |
| **Rule-ledger provenance** | `metrics/rule_ledger.py` | missing `--approved-at` fails closed and writes nothing; no wall-clock | `test_rule_ledger.sh:28-117` | append-only ledger |
| **Challenge-token oracle** | `metrics/challenge_token_oracle.py` | over-bound→exit 1; near-identical roles→exit 1; missing tokens→exit 2 `MISSING` (never a fake pass) | `test_challenge_token_oracle.sh:26-37` | scores **JSON fixtures** — **not wired into a live `/concilium` run** |
| **Update layer** (supply-chain) | `lib/plumbline_update.py` | path-traversal tarball refused; payload `verifyCommand` not executed; `file://`/`ftp://` refused; setuid stripped; MAJOR needs `--yes-major` | `test_update_layer.sh:14-238` | tooling, not a governance gate |
| **`install.sh` global hook registration** | `install.sh:144-230` | idempotent, dedup-keyed `jq` append of both Stop hooks | `test_pril_enforce_hook.sh:205-238` | proves the *mechanism*; real enforcement needs the user to have run `install.sh` |

---

## Table 2 — `prompt-only` (model-honored; **no code checks it**)

These are Plumbline's most-quoted invariants. None is machine-enforced at runtime.

| Gate | Where (prose) | Why it's prompt-only | Closest (non-enforcing) test |
|------|---------------|----------------------|------------------------------|
| **Phase 0–8 sequence/ordering** | `agileteam.md:43-66` | no script reads a phase counter or blocks phase N+1; the run-ledger trusts whatever gate names the orchestrator records | — |
| **Plumbline Watcher verdicts** | `agileteam.md:178-232` | the Watcher is an LLM subagent; **no executable computes** `pass/review-required/pause/blocked`. `watcher.md` says "PRIL fail ⇒ verdict cannot be `pass`", but nothing forces the model to run PRIL or honor it before declaring `pass` | `test_true_line_governance.sh:62-72` (grep) |
| **wired-in-prod** (the founding incident) | `agileteam.md:404-412, 594-598` | **no executable detects composition-root reachability**; it is a human/model-filled matrix column. `reality-check` enforces evidence-*class*, not wiring. | grep-presence only |
| **no-silent-RED-downgrade / escalation asymmetry** | `agileteam.md:207-210, 668-677` | no script detects a downgrade event or compares a prior RED finding to a later "by design" label | `test_true_line_governance.sh:80-86` (grep) |
| **Independence invariant** (writer ≠ reviewer) | `agileteam.md:336-338, 293-306` | **zero** machine enforcement that coder and reviewer are distinct dispatches, or that the reviewer's prompt excludes the coder's reasoning | only G4 roster *name* checks (composition, not dispatch independence) |
| **Dispatch-model policy** ("Opus-only safety net") | `agileteam.md:308-334` | see the centerpiece section below — **prompt-only AND unrecorded** | `test_true_line_governance.sh:151` (grep that the disclosure sentence still exists) |
| **Gates A–E** (Phase 3 hermetic gates) | `agileteam.md:586-628` | typecheck/lint/test/coverage/mutation/SAST are commands the orchestrator is *told* to run; no script runs the built project's suites. Only the embedded `plumbline-reality-check` block is real. | — |
| **Concilium four-body mandate** (parallel round-1 independence) | `concilium.md:51-62, 90-92` | no script dispatches the bodies or checks parallelism; G1-C4 resolves only **3 of 4** body files by name (`concilium-distribution-realist` is absent from the loop) | `test_gate_contracts.sh:80` (grep, 3 bodies) |
| **Concilium fail-closed model-diversity** ("≥2 independent bodies or abort") | `concilium.md:72-88` | the `for c in codex gemini qwen` probe is **illustrative text inside the prompt**, not an executed gate; nothing verifies the disclosure was emitted or the 2-body floor held. No test even greps these strings. | none |

---

## Table 3 — `drift-protection-only` (guards wording, not firing)

Real value — they stop silent erosion of the governance text — but they are `grep -qF`
presence assertions, **not** proof a gate fires.

| Test module | What it guards | Note |
|-------------|----------------|------|
| `test_true_line_governance.sh` | 117 `has()` prose-presence checks across agileteam/concilium/watcher/agent files | header itself: *"There is no runtime to exercise"* |
| `test_product_canvas_gate.sh` | 63 `has()` checks over command/template/spec/agent | adds `detects_removal()` — strips the line + re-greps, so the assertion has **teeth** against static docs |
| `test_gate_contracts.sh` (G1/G3/G4) | 21 `has()` (`2 collision rounds`, `180 words per role`, `USER ACCEPTANCE GATE`, role names) | minority structural: `gate_contracts.py` roster name-resolution + 2 negative fixtures (G3-C2 removed-acceptance-gate, G4-C5 unresolved role) |
| Council challenge bounds | collision-round / word-cap / **withdrawn** token cap | the `≈15k tokens total` cap is explicitly withdrawn as measured-false; "a hard cap would need a real token counter, not prose" |
| **Human acceptance gate** | `USER ACCEPTANCE GATE` present + negative fixture | guards the *string*, not actual runtime blocking for a human |
| `test_readme_honesty.sh` / `test_dependencies_doc.sh` | derived agent count / disclosed MCP families | derivation is dynamic (hardened), but the assertion guards doc wording/coverage |
| `test_runtime_integrity_layer.sh:190-205` (tail) | `/agileteam` & Watcher *reference* the PRIL CLIs | grep that the wiring instruction exists — the CLIs themselves are Table 1 |

---

## Table 4 — `structural-validation` & deliberately inert

| Item | Where | Note |
|------|-------|------|
| frontmatter validator (parse/description/duplicate-name/colon) | `run_all.sh:17-72` | file shape, not behavior |
| `py_compile` / `jq -e settings.json` / shellcheck | `run_all.sh:74-140` | shellcheck **skips (not fails)** when the linter is absent |
| evidence-vocab consistency | `test_evidence_vocab.sh:25-133` | enum == RANKS, ladder strictly increasing, crosswalk complete |
| release-please wiring | `test_release_please.sh:9-37` | manifest == VERSION == compatibility version |
| run-ledger `record` | `plumbline_run_ledger.py:119-140` | append-only writer; the fail-closed teeth are in resume/revalidate |
| `gate_contracts.py resolve-roster` | `lib/gate_contracts.py:86-117` | CI/test-only roster resolver; **not** in any hook |
| `session-start.sh` bootstrap | `hooks/session-start.sh:27-75` | installs commands/skills on remote; enforces nothing about work integrity |
| `pretool-plumbline-guard.sh` | `hooks/pretool-plumbline-guard.sh:1-18` | **intentionally inert**, pinned-unregistered (`test_pril_enforce_hook.sh:231`) — enforcement-by-absence |

---

## The centerpiece: the dispatch-model policy is `prompt-only` **and** unrecorded

Plumbline's headline empirical claim — *"review/security/validation/judgment is only
trustworthy on Opus; Haiku and Sonnet escaped the GBrain-class miss 3/3"*
(`agileteam.md:315-320`) — is **neither enforced nor recorded**:

- **`metrics/runs.jsonl` has no per-role `model` field at any nesting depth.** A recursive
  key walk of both records returns zero `model` hits; the only per-role data is
  `config_fingerprint` = sha256 **content-hashes of the agent prompt files**, not the
  runtime model. The ledger that is described as "the empirical instrument … measured, not
  asserted" does not carry the one column its headline claim is about.
- **`emit_run.py` has no `--model` arg** and no `model` key in its record dict; the metric
  allowlist would actively reject `model`, so it can't even be smuggled via `--metrics`.
- **`plumbline_run_ledger.py`** record schema is `{repo, feature, gate, status,
  artifact_hash, at}` — no `model`.
- **`agileteam.md:308-334`** states the policy (and the "frontmatter `model:` is inert /
  only an explicit dispatch param works" fact) purely as **prose instructions to the
  orchestrating model**. The one "test" (`test_true_line_governance.sh:151`) is a `grep`
  that the disclosure *sentence* still exists.

**The asymmetry, stated plainly:** a `/agileteam` run on Sonnet — silently skipping the
disclosure, or whose orchestrator simply doesn't honor `gates on opus` — produces a
`runs.jsonl` record **indistinguishable** from an all-Opus run. The framework cannot, from
its own data, tell you which runs had the safety net it claims is the whole point; and the
corpora that "prove" the Opus-only claim do not carry the model column needed to reproduce
or audit it. **This is the single highest-value `prompt-only → recorded → enforced`
conversion on the roadmap (B1).** *Caveat the audit cannot resolve:* the cited 2026-05-30
verification was "via subagent logs" external to this repo; the audit can only confirm none
of that attribution is **persisted in the repo's ledgers or checked by its code.**

---

## Trust-boundary caveats (where even "machine-checked" is conditional)

1. **The PRIL Stop hook is dormant in this repo's own sessions** — only the global
   `~/.claude/settings.json` (written by `install.sh`) arms it; this repo's
   `.claude/settings.json` registers only `SessionStart`.
2. **Activation depends on a prompt-only step** — the orchestrator must write
   `docs/context/.active-feature` at GO; the test only `grep`-confirms that instruction
   exists in `agileteam.md`.
3. **The context marker is string-presence**, not proof of a human signature.
4. **The reality floor** lets the legacy `integration` alias pass, and is **skipped**
   entirely unless `docs/context/.feature-boundary` exists.
5. **`redact` and `run-ledger` are not in the hook** — they fire only if the orchestrator
   invokes them.
6. **`resume-point` fails closed via stdout**, not exit code — a `$?`-only caller misses a
   corrupt ledger.

---

## What this implies for the backlog

- **B1 (dispatch-model enforcement)** is the highest-leverage conversion this audit
  surfaces — and it now has its evidence-grounded scope: add a per-role dispatched-model
  field to the run-ledger/`emit_run.py`, then make PRIL/merge fail closed when a critical
  role lacks Opus evidence. Note the substrate gap (no `model` field anywhere today) is
  exactly why it needs its own brainstorm→plan pass; it is **not** a quick edit.
- **B2-conversion** should target, in priority order, the `prompt-only` rows whose claims
  are load-bearing and *mechanically* checkable from the dispatch ledger: **independence**
  (writer ≠ reviewer is a ledger comparison) and **no-silent-RED-downgrade**. **wired-in-prod**
  and the **Watcher verdict** are partly judgment — disclose honestly which gates *cannot*
  be machine-enforced rather than over-claiming.
- Gates that are genuinely `un-enforceable-by-construction` (Product-Canvas *no-self-confirm*,
  product judgment, human acceptance) should stay human — and be **labeled** as such so the
  framework doesn't over-claim enforcement in the other direction either.

---

## Honesty note

This audit is **disclosure, not enforcement**. It converts a scattered, mostly-implicit
truth ("our gates are prose; here is exactly which ones") into one honest, evidence-cited
table — which is Plumbline's own thesis applied to itself. It deliberately does **not**
change any gate; converting a `prompt-only` row to `machine-checked-runtime` is separate,
heavier work (roadmap B1 / B2-conversion). Treat every `prompt-only` / `drift-protection`
verdict here as the auditors' reading of the named `file:line`, re-checkable by anyone.
