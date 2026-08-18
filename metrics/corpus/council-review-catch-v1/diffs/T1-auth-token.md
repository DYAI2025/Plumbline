# Diff under review — T1-auth-token

A change that adds a bearer-token check to a request handler. ONE defect was seeded
into this diff BEFORE and INDEPENDENT of any review (see oracle.json). The line numbers
in the oracle index the NEW-file side of the hunk below (the `+` lines), counting from
the `@@` hunk-start line number.

```diff
--- a/auth/token.py
+++ b/auth/token.py
@@ -8,6 +8,18 @@ class TokenGuard:
     def __init__(self, secret: str) -> None:
         self._secret = secret

+    def is_authorized(self, header: str | None) -> bool:
+        # Seeded defect D1 (new-side line 17): the comparison is non-constant-time,
+        # leaking the secret via a timing side-channel. A real review should flag it.
+        if header is None:
+            return False
+        token = header.removeprefix("Bearer ").strip()
+        return token == self._secret          # line 17 — non-constant-time compare
+
+    def issue(self, subject: str) -> str:
+        # Clean-control region (new-side lines 19-23): correct, defect-free code. A
+        # flag here is a cry-wolf — there is no seeded defect in this method.
+        payload = {"sub": subject, "secret_bound": True}
+        return self._sign(payload)            # line 23 — defect-free
+
     def _sign(self, payload: dict) -> str:
         return _hmac(self._secret, payload)
```

Provenance: the timing-side-channel defect was planted at authoring time from a known
secure-comparison anti-pattern, not selected because any model caught (or missed) it.
