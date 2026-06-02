# True-Line Gate Check

Required inputs:
- PRD
- Product Vision
- Traceability Matrix
- Reality Ledger / evidence
- Current implementation/test/design output
- Contradiction Ledger, if present

Questions:
1. Is this still true to the confirmed customer value?
2. Does this still serve the real user described in the Vision?
3. Does this still match the real usage moment?
4. Does anything here make the product technically correct but practically useless?
5. Does anything rely on mocks, placeholders, fake-only evidence, or unconfirmed assumptions?
6. Has the team optimized for completion instead of truth?
7. Has any user-value contradiction appeared?
8. If yes, has the Watcher paused the workflow and written a contradiction record?

PRIL check output:
Scope check output:
Redaction check output:
- context-check: <command/output or N/A before Phase 0.5>
- reality-check: <command/output or N/A before Gate C/D>

Gate result:
- pass
- value-risk
- contradiction
- blocked

Pause reason (required for any non-`pass` verdict — leave empty/`N/A` only when the result is `pass`):
- failed-check: <the specific check that did not pass, e.g. `reality-check (min-evidence integration)`, `scope-check`, `PRIL context`, or the True-Line question number/letter that triggered the pause>
- evidence: <artifact:line — the concrete pointer the verdict rests on, e.g. `docs/reality/<feature>.evidence.jsonl:42` or `<command> output line`; cite the evidence, never memory>
- required user decision: <the one decision the user must make to unblock, stated as a question — e.g. "reclassify this `*-fake` boundary as accepted, or direct a real-boundary test?"; this is a human gate, the loop does not self-resolve it>

Continuation rule:
- pass: may continue
- value-risk: Watcher review required
- contradiction: pause and user resolution required
- blocked: pause and user or human review required
