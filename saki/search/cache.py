"""A tiny in-memory TTL cache."""

from __future__ import annotations

import time
from collections import OrderedDict
from collections.abc import Callable
from typing import Any


class TTLCache:
    def __init__(self, ttl: float, maxsize: int = 128, clock: Callable[[], float] = time.monotonic):
        self.ttl = ttl
        self.maxsize = maxsize
        self._clock = clock
        self._data: OrderedDict[str, tuple[float, Any]] = OrderedDict()

    def get(self, key: str) -> Any | None:
        item = self._data.get(key)
        if item is None:
            return None
        expires, value = item
        if self._clock() >= expires:
            del self._data[key]
            return None
        self._data.move_to_end(key)
        return value

    def set(self, key: str, value: Any) -> None:
        self._data[key] = (self._clock() + self.ttl, value)
        self._data.move_to_end(key)
        while len(self._data) > self.maxsize:
            self._data.popitem(last=False)

    def clear(self) -> None:
        self._data.clear()
