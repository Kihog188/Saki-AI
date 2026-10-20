"""Ollama backend: POST /api/chat with stream=true (NDJSON)."""

from __future__ import annotations

import json
from collections.abc import AsyncIterator

import httpx

from .base import (
    GenParams,
    LLMBackend,
    LLMResponseError,
    LLMTimeoutError,
    LLMUnavailableError,
)


class OllamaBackend(LLMBackend):
    name = "ollama"

    def __init__(
        self,
        model: str = "saki",
        base_url: str = "http://127.0.0.1:11434",
        read_timeout: float = 120.0,
        transport: httpx.AsyncBaseTransport | None = None,
    ):
        super().__init__(model)
        self.base_url = base_url
        self._client = httpx.AsyncClient(
            base_url=base_url,
            timeout=httpx.Timeout(connect=3.0, read=read_timeout, write=10.0, pool=5.0),
            transport=transport,
        )

    async def stream_chat(self, messages: list[dict], params: GenParams) -> AsyncIterator[str]:
        payload = {
            "model": self.model,
            "messages": messages,
            "stream": True,
            "options": {
                "temperature": params.temperature,
                "top_p": params.top_p,
                "num_ctx": params.num_ctx,
                "repeat_penalty": params.repeat_penalty,
                "repeat_last_n": params.repeat_last_n,
                "stop": list(params.stop),
            },
        }
        try:
            async with self._client.stream("POST", "/api/chat", json=payload) as resp:
                if resp.status_code != 200:
                    body = (await resp.aread()).decode("utf-8", "replace")
                    raise LLMResponseError(f"Ollama HTTP {resp.status_code}: {body[:200]}")
                async for line in resp.aiter_lines():
                    if not line.strip():
                        continue
                    try:
                        data = json.loads(line)
                    except ValueError:
                        continue
                    if data.get("error"):
                        raise LLMResponseError(f"Ollama: {data['error']}")
                    chunk = (data.get("message") or {}).get("content") or ""
                    if chunk:
                        yield chunk
                    if data.get("done"):
                        break
        except (httpx.ConnectError, httpx.ConnectTimeout) as exc:
            raise LLMUnavailableError(f"Cannot reach Ollama at {self.base_url}") from exc
        except httpx.TimeoutException as exc:
            raise LLMTimeoutError("Ollama stopped responding") from exc
        except httpx.HTTPError as exc:
            raise LLMUnavailableError(f"Ollama connection error: {exc}") from exc

    async def health(self) -> dict:
        try:
            resp = await self._client.get("/api/tags", timeout=3.0)
            resp.raise_for_status()
            names = {m.get("name", "") for m in resp.json().get("models", [])}
        except (httpx.HTTPError, ValueError) as exc:
            return {"reachable": False, "model_available": None, "detail": str(exc) or type(exc).__name__}
        available = self.model in names or f"{self.model}:latest" in names
        return {"reachable": True, "model_available": available, "detail": ""}

    async def aclose(self) -> None:
        await self._client.aclose()
