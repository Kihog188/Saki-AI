"""Fake backend for tests: streams a canned reply in small chunks."""

from __future__ import annotations

import asyncio
from collections.abc import AsyncIterator

from .base import GenParams, LLMBackend


class FakeBackend(LLMBackend):
    name = "fake"

    def __init__(
        self,
        reply: str = "[happy] Chào bạn.",
        chunk_size: int = 3,
        delay: float = 0.0,
        error: Exception | None = None,
    ):
        super().__init__("fake")
        self.reply = reply
        self.chunk_size = chunk_size
        self.delay = delay
        self.error = error
        self.calls: list[list[dict]] = []

    async def stream_chat(self, messages: list[dict], params: GenParams) -> AsyncIterator[str]:
        self.calls.append(messages)
        if self.error is not None:
            raise self.error
        for i in range(0, len(self.reply), self.chunk_size):
            if self.delay:
                await asyncio.sleep(self.delay)
            yield self.reply[i : i + self.chunk_size]

    async def health(self) -> dict:
        return {"reachable": self.error is None, "model_available": True, "detail": ""}
