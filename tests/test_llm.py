import asyncio
import json

import httpx
import pytest

from saki.llm import (
    FakeBackend,
    GenParams,
    LlamaCppBackend,
    LLMResponseError,
    LLMTimeoutError,
    LLMUnavailableError,
    OllamaBackend,
)

MESSAGES = [{"role": "system", "content": "S"}, {"role": "user", "content": "hi"}]


async def collect(backend):
    return [c async for c in backend.stream_chat(MESSAGES, GenParams())]


def ndjson(*objs):
    return "\n".join(json.dumps(o, ensure_ascii=False) for o in objs) + "\n"


async def test_ollama_streams_and_sends_params():
    seen = {}

    def handler(request: httpx.Request):
        seen["path"] = request.url.path
        seen["body"] = json.loads(request.content)
        body = ndjson(
            {"message": {"content": "[happy] "}, "done": False},
            {"message": {"content": "Chào bạn"}, "done": False},
            {"message": {"content": ""}, "done": True},
        )
        return httpx.Response(200, text=body)

    b = OllamaBackend(transport=httpx.MockTransport(handler))
    assert await collect(b) == ["[happy] ", "Chào bạn"]
    assert seen["path"] == "/api/chat"
    assert seen["body"]["model"] == "saki"
    assert seen["body"]["stream"] is True
    assert seen["body"]["messages"] == MESSAGES
    assert seen["body"]["options"] == {
        "temperature": 0.3,
        "top_p": 0.8,
        "num_ctx": 2048,
        "repeat_penalty": 1.15,
        "repeat_last_n": 128,
        "stop": ["<|im_end|>"],
    }
    await b.aclose()


async def test_ollama_not_running():
    def handler(request):
        raise httpx.ConnectError("refused", request=request)

    b = OllamaBackend(transport=httpx.MockTransport(handler))
    with pytest.raises(LLMUnavailableError):
        await collect(b)
    assert (await b.health())["reachable"] is False


async def test_ollama_timeout():
    def handler(request):
        raise httpx.ReadTimeout("slow", request=request)

    b = OllamaBackend(transport=httpx.MockTransport(handler))
    with pytest.raises(LLMTimeoutError):
        await collect(b)


async def test_ollama_model_missing():
    b = OllamaBackend(
        transport=httpx.MockTransport(lambda r: httpx.Response(404, json={"error": "model 'saki' not found"}))
    )
    with pytest.raises(LLMResponseError):
        await collect(b)


async def test_ollama_health():
    def handler(request):
        assert request.url.path == "/api/tags"
        return httpx.Response(200, json={"models": [{"name": "saki:latest"}]})

    h = await OllamaBackend(transport=httpx.MockTransport(handler)).health()
    assert h == {"reachable": True, "model_available": True, "detail": ""}


async def test_llamacpp_streams_sse():
    seen = {}

    def handler(request):
        seen["path"] = request.url.path
        seen["body"] = json.loads(request.content)
        lines = [
            'data: {"choices":[{"delta":{"role":"assistant"}}]}',
            'data: {"choices":[{"delta":{"content":"[neutral] "}}]}',
            'data: {"choices":[{"delta":{"content":"Ừ."}}]}',
            "data: [DONE]",
        ]
        return httpx.Response(200, text="\n\n".join(lines) + "\n\n")

    b = LlamaCppBackend(transport=httpx.MockTransport(handler))
    assert await collect(b) == ["[neutral] ", "Ừ."]
    assert seen["path"] == "/v1/chat/completions"
    assert seen["body"]["stream"] is True
    assert seen["body"]["temperature"] == 0.3 and seen["body"]["top_p"] == 0.8
    assert seen["body"]["repeat_penalty"] == 1.15
    assert seen["body"]["stop"] == ["<|im_end|>"]


async def test_llamacpp_not_running():
    def handler(request):
        raise httpx.ConnectError("refused", request=request)

    with pytest.raises(LLMUnavailableError):
        await collect(LlamaCppBackend(transport=httpx.MockTransport(handler)))


async def test_fake_backend_chunks_and_records():
    b = FakeBackend(reply="[happy] Chào bạn.", chunk_size=4)
    chunks = await collect(b)
    assert "".join(chunks) == "[happy] Chào bạn."
    assert len(chunks) > 1
    assert b.calls == [MESSAGES]


async def test_fake_backend_cancellation():
    b = FakeBackend(reply="x" * 100, chunk_size=1, delay=0.01)
    got = []

    async def consume():
        async for c in b.stream_chat(MESSAGES, GenParams()):
            got.append(c)

    task = asyncio.create_task(consume())
    await asyncio.sleep(0.05)
    task.cancel()
    with pytest.raises(asyncio.CancelledError):
        await task
    assert 0 < len(got) < 100
