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

Continuation rule:
- pass: may continue
- value-risk: Watcher review required
- contradiction: pause and user resolution required
- blocked: pause and user or human review required
