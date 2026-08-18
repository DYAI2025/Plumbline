---
description: Check or apply Plumbline updates with verified-or-revert semantics. Use for `/plumbline-update check`, `/plumbline-update apply`, or rollback planning.
---

You are running **/plumbline-update**. Keep Plumbline completion language honest:
report `changed, not yet verified` until the verification command prints `ALL CHECKS PASSED`.

## Contracts

- Check only: `plumbline update --check --source <fixture-or-release-metadata>`.
- Apply: `plumbline update --source <checkout-or-release-payload>`.
- MAJOR updates require explicit human confirmation and `--yes-major`.
- Rollback: `plumbline rollback [--snapshot <path>]`.

## Required evidence before claiming verified

```bash
bash config/claude/tests/run_all.sh
bash config/claude/tests/test_update_layer.sh
./config/claude/install.sh --dry-run
```

If any command fails, say what changed and what reverted or remains unverified.
