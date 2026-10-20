"""LLM backend interface."""

from __future__ import annotations

from abc import ABC, abstractmethod
from collections.abc import AsyncIterator
from dataclasses import dataclass, field


@dataclass(frozen=True)
class GenParams:
    temperature: float = 0.3
    top_p: float = 0.8
    num_ctx: int = 2048
    repeat_penalty: float = 1.15
    repeat_last_n: int = 128
    stop: tuple[str, ...] = field(default=("<|im_end|>",))


class LLMError(Exception):
    """Base class for LLM backend failures."""


class LLMUnavailableError(LLMError):
    """The LLM server is not running or cannot be reached."""


class LLMTimeoutError(LLMError):
    """The LLM server stopped responding."""


class LLMResponseError(LLMError):
    """The LLM server answered with an error (e.g. unknown model)."""


class LLMBackend(ABC):
    name: str = "base"

    def __init__(self, model: str = ""):
        self.model = model

    @abstractmethod
    def stream_chat(self, messages: list[dict], params: GenParams) -> AsyncIterator[str]:
        """Yield text chunks of the assistant reply.

        Cancellation: cancel the task consuming the iterator; the HTTP request is
        closed when the generator is closed.
        """

    @abstractmethod
    async def health(self) -> dict:
        """{'reachable': bool, 'model_available': bool | None, 'detail': str}"""

    async def aclose(self) -> None:  # noqa: B027 - optional hook
        pass
