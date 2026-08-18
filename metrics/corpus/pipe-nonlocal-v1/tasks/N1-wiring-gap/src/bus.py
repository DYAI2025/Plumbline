"""A tiny synchronous event bus."""
from __future__ import annotations

from typing import Callable


class EventBus:
    def __init__(self) -> None:
        self._handlers: dict[str, list[Callable[[dict], str]]] = {}

    def register(self, event_type: str, handler: Callable[[dict], str]) -> None:
        self._handlers.setdefault(event_type, []).append(handler)

    def dispatch(self, event: dict) -> list[str]:
        et = event.get("type", "")
        return [h(event) for h in self._handlers.get(et, [])]
