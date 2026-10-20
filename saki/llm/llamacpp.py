"""llama.cpp `llama-server` backend: OpenAI-compatible /v1/chat/completions (SSE).

The context size is fixed when llama-server starts (`-c 2048`), so `num_ctx`
is not sent per request.
"""

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


class LlamaCppBackend(LLMBackend):
    name = "llamacpp"

    def __init__(
        self,
        model: str = "saki",
        base_url: str = "http://127.0.0.1:8080",
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
            "temperature": params.temperature,
            "top_p": params.top_p,
            "stop": list(params.stop),
        }
        try:
            async with self._client.stream("POST", "/v1/chat/completions", json=payload) as resp:
                if resp.status_code != 200:
                    body = (await resp.aread()).decode("utf-8", "replace")
                    raise LLMResponseError(f"llama-server HTTP {resp.status_code}: {body[:200]}")
                async for line in resp.aiter_lines():
                    line = line.strip()
                    if not line.startswith("data:"):
                        continue
                    data_str = line[5:].strip()
                    if data_str == "[DONE]":
                        break
                    try:
                        data = json.loads(data_str)
                    except ValueError:
                        continue
                    if data.get("error"):
                        raise LLMResponseError(f"llama-server: {data['error']}")
                    for choice in data.get("choices") or []:
                        chunk = (choice.get("delta") or {}).get("content") or ""
                        if chunk:
                            yield chunk
        except (httpx.ConnectError, httpx.ConnectTimeout) as exc:
            raise LLMUnavailableError(f"Cannot reach llama-server at {self.base_url}") from exc
        except httpx.TimeoutException as exc:
            raise LLMTimeoutError("llama-server stopped responding") from exc
        except httpx.HTTPError as exc:
            raise LLMUnavailableError(f"llama-server connection error: {exc}") from exc

    async def health(self) -> dict:
        try:
            resp = await self._client.get("/health", timeout=3.0)
        except httpx.HTTPError as exc:
            return {"reachable": False, "model_available": None, "detail": str(exc) or type(exc).__name__}
        # 200 = model loaded, 503 = still loading.
        return {
            "reachable": True,
            "model_available": resp.status_code == 200,
            "detail": "" if resp.status_code == 200 else f"HTTP {resp.status_code}",
        }

    async def aclose(self) -> None:
        await self._client.aclose()
