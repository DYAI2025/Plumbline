# Oracle — T1-auth-token (human-readable companion)

The machine-readable truth is in `../oracle.json` (task `T1-auth-token`); this file
mirrors the `pipe-core-v1` idiom for human review.

## Seeded defects (catch oracle)

| id | file | lines | type | what it is |
|---|---|---|---|---|
| D1 | `auth/token.py` | 17 | timing-side-channel | `token == self._secret` is a non-constant-time comparison; it leaks the secret via response timing. A correct review flags this line. |

## Clean-control region (cry-wolf oracle)

| file | lines | why |
|---|---|---|
| `auth/token.py` | 19-23 | The `issue`/`_sign` path is correct and defect-free. Any flag landing here is a CRY-WOLF (false positive). |

## Recall / no-narrowing control

| file | lines | why |
|---|---|---|
| `auth/token.py` | 8-9 | The `__init__` is correct, in-scope code. A reviewer that flags it has narrowed scope onto a non-defect; the recall control drops to 0.0. |

## Independence

D1 was planted at authoring time from a known secure-comparison anti-pattern, BEFORE
and INDEPENDENT of any review (NGOAL-DM-003). It was not chosen because a model caught
or missed it.
