# Diff under review — T2-pagination

A change that adds offset/limit pagination to a list endpoint. TWO defects were seeded
into this diff BEFORE and INDEPENDENT of any review (see oracle.json), so this task has
a DIFFERENT defect count than T1-auth-token — that is the source of the corpus's real
across-task variance (BLOCKER-2). The line numbers in the oracle index the NEW-file side
of the hunk below.

```diff
--- a/api/list.py
+++ b/api/list.py
@@ -20,4 +20,24 @@ def list_items(request, store):
     limit = request.query.get("limit", "20")
     offset = request.query.get("offset", "0")

+    # Seeded defect D1 (new-side line 25): limit is used unbounded — a caller can
+    # request a huge page and exhaust memory (missing max-limit clamp). Flag this.
+    page_size = int(limit)                    # line 25 — unbounded limit (defect D1)
+
+    # Recall/no-narrowing control (new-side lines 30-31): correct, in-scope code that
+    # a narrowing reviewer might wrongly flag. It carries NO seeded defect; flagging it
+    # is a false narrowing, tracked by the recall control.
+    if page_size < 1:
+        page_size = 1                         # line 31 — defensive, correct
+
+    # Seeded defect D2 (new-side line 36): offset parsed without catching ValueError —
+    # a non-numeric offset crashes the handler with an unhandled exception. Distinct
+    # defect from D1, in a separate location.
+    start = int(offset)                       # line 36 — unguarded int() (defect D2)
+
+    # Clean-control region (new-side lines 40-41): defect-free slicing + return. A flag
+    # here is a cry-wolf — there is no seeded defect in this block.
+    rows = store.all()[start:start + page_size]
+    return {"items": rows, "offset": start, "limit": page_size}  # line 41 — defect-free
+
     # (end of new pagination block)
```

Provenance: both defects (unbounded limit; unguarded int parse) were planted at
authoring time from known input-handling anti-patterns, not selected per any review
result. The corpus is frozen and version-stamped.
