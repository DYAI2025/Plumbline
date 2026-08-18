"""INTEGRATION reference suite (evidence-class: real-boundary-smoke).

Exercises the feature THROUGH the production composition root build_app().
If the handler is not wired in build_app(), dispatch returns nothing and this
suite goes RED -> the wiring regression is CAUGHT.
"""
from src.app import build_app


def test_signup_produces_welcome_through_app():
    app = build_app()
    results = app.dispatch({"type": "user_signup", "name": "Ben"})
    assert results == ["Welcome, Ben!"], (
        "signup event produced no welcome through the wired app "
        f"(got {results!r}) -- handler not wired into build_app()?"
    )
