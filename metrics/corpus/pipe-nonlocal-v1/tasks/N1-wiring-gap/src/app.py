"""Composition root: builds the wired application."""
from __future__ import annotations

from src.bus import EventBus
from src.handlers import welcome_handler


def build_app() -> EventBus:
    """Construct the EventBus with all handlers wired in.

    This is the production composition root: whatever is NOT registered here
    never runs in production, no matter how correct the handler is in isolation.
    """
    bus = EventBus()
    bus.register("user_signup", welcome_handler)  # WIRING
    return bus
