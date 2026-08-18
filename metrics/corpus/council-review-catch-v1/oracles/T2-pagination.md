# Oracle — T2-pagination (human-readable companion)

The machine-readable truth is in `../oracle.json` (task `T2-pagination`); this file
mirrors the `pipe-core-v1` idiom for human review.

## Seeded defects (catch oracle)

| id | file | lines | type | what it is |
|---|---|---|---|---|
| D1 | `api/list.py` | 25 | resource-exhaustion | `int(limit)` is used unbounded — no max-page clamp, so a huge `limit` exhausts memory. |
| D2 | `api/list.py` | 36 | unhandled-exception | `int(offset)` is parsed without catching `ValueError` — a non-numeric offset crashes the handler. |

Two distinct seeded defects (vs. T1's one) are the source of the corpus's REAL
across-task variance (BLOCKER-2).

## Clean-control region (cry-wolf oracle)

| file | lines | why |
|---|---|---|
| `api/list.py` | 40-41 | The slicing + return block is correct and defect-free. Any flag landing here is a CRY-WOLF. |

## Recall / no-narrowing control

| file | lines | why |
|---|---|---|
| `api/list.py` | 30-31 | The `if page_size < 1` clamp is defensive, correct, in-scope code. A reviewer that flags it has falsely narrowed scope; the recall control drops to 0.0. |

## Independence

D1 and D2 were planted at authoring time from known input-handling anti-patterns,
BEFORE and INDEPENDENT of any review (NGOAL-DM-003). Neither was chosen because a model
caught or missed it.
