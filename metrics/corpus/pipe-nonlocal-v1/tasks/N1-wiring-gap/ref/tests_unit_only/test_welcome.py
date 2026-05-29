"""UNIT-ONLY reference suite (evidence-class: unit-fake).

Tests the handler in isolation. Never touches build_app(), so a wiring
regression in the composition root is invisible here -> the defect ESCAPES.
"""
from src.handlers import welcome_handler


def test_welcome_message_uses_name():
    assert welcome_handler({"type": "user_signup", "name": "Ben"}) == "Welcome, Ben!"


def test_welcome_message_default_name():
    assert welcome_handler({"type": "user_signup"}) == "Welcome, there!"
