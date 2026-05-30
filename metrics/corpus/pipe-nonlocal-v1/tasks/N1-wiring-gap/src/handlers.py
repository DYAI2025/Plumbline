"""Event handlers."""
from __future__ import annotations


def welcome_handler(event: dict) -> str:
    """Produce a welcome message for a user_signup event."""
    name = event.get("name", "there")
    return f"Welcome, {name}!"
