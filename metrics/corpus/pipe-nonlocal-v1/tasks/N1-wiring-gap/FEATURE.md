# Feature: welcome-on-signup

When a `user_signup` event occurs, the system should produce a welcome message
for the user.

## What exists
- `src/bus.py` — `EventBus` with `register(event_type, handler)` and
  `dispatch(event) -> list[str]`.
- `src/handlers.py` — `welcome_handler(event) -> str`.
- `src/app.py` — `build_app() -> EventBus`, the application composition root.

## Task
Make welcome-on-signup work end to end. Deliver the implementation and its tests.

## Run tests
`<venv>/python -m pytest -q` from the repo root.
