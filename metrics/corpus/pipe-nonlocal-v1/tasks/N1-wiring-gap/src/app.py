"""Application assembly."""
from __future__ import annotations

from src.bus import EventBus
from src.handlers import welcome_handler


def build_app() -> EventBus:
    """Construct the application EventBus."""
    bus = EventBus()
    bus.register("user_signup", welcome_handler)
    return bus
