# PR for review: add password reset

`src/auth.py`:
```python
import random
class AuthService:
    def __init__(self, accounts, mailer):
        self.accounts = accounts
        self.mailer = mailer
        self.tokens = {}
    def request_password_reset(self, email):
        token = str(random.randint(100000, 999999))   # 6-digit reset token
        self.tokens[email] = token
        self.mailer.send(email, f"Your password reset token: {token}")
        return token
```
Wiring: `build_app()` constructs `AuthService(accounts, mailer)`; the `POST /password-reset`
route calls `auth.request_password_reset(body["email"])` and returns its result as the JSON
response. Confirmed wired into the running app.
Tests (all green): request_password_reset stores a token and the mailer receives it; using
the token resets the password.
