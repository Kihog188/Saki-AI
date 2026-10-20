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
        replies: list[str] | None = None,
    ):
        super().__init__("fake")
        self.reply = reply
        self.replies = list(replies or [])  # if set, consumed one per call before `reply`
        self.chunk_size = chunk_size
        self.delay = delay
        self.error = error
        self.calls: list[list[dict]] = []
        self.params: list[GenParams] = []

    async def stream_chat(self, messages: list[dict], params: GenParams) -> AsyncIterator[str]:
        self.calls.append(messages)
        self.params.append(params)
        if self.error is not None:
            raise self.error
        reply = self.replies.pop(0) if self.replies else self.reply
        for i in range(0, len(reply), self.chunk_size):
            if self.delay:
                await asyncio.sleep(self.delay)
            yield reply[i : i + self.chunk_size]

    async def health(self) -> dict:
        return {"reachable": self.error is None, "model_available": True, "detail": ""}
