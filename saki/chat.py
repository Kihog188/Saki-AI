"""One chat turn: commands, search, LLM streaming, post-processing, history.

Transport-agnostic: events are passed to an async `emit` callback (the WebSocket
handler in server.py, or a list in tests).
"""

from __future__ import annotations

import asyncio
import logging
from collections.abc import Awaitable, Callable
from datetime import date

from .commands import CommandHandler, parse_command
from .config import AppConfig
from .context import build_messages
from .llm import GenParams, LLMBackend, LLMResponseError, LLMTimeoutError, LLMUnavailableError
from .postprocess import (
    DEFAULT_EMOTION,
    ReplyStream,
    build_sources_line,
    finalize_search_reply,
    sources_payload,
)
from .prompts import build_search_message, render_system_prompt, select_results
from .search.models import SearchResult
from .search.service import SearchProvider
from .settings import SettingsStore
from .storage import Storage

log = logging.getLogger(__name__)

Emit = Callable[[dict], Awaitable[None]]

HISTORY_FETCH_LIMIT = 40

ERR_UNAVAILABLE = {
    "ollama": "Saki chưa kết nối được với mô hình. Hãy mở Ollama (hoặc chạy lệnh: ollama serve) rồi thử lại.",
    "llamacpp": "Saki chưa kết nối được với mô hình. Hãy kiểm tra llama-server đã chạy chưa rồi thử lại.",
}
ERR_UNAVAILABLE_DEFAULT = "Saki chưa kết nối được với mô hình. Hãy kiểm tra máy chủ mô hình rồi thử lại."
ERR_TIMEOUT = "Saki phản hồi quá lâu nên đã dừng lại. Bạn thử lại nhé."
ERR_MODEL = "Máy chủ mô hình báo lỗi (có thể chưa có mô hình “{model}”). Hãy kiểm tra cài đặt mô hình."
ERR_GENERIC = "Có lỗi xảy ra, bạn thử lại nhé."
ERR_EMPTY = "Tin nhắn trống."


class ChatService:
    def __init__(
        self,
        cfg: AppConfig,
        storage: Storage,
        settings: SettingsStore,
        llm: Callable[[], LLMBackend],
        search: SearchProvider,
        today: Callable[[], date] = date.today,
    ):
        self.cfg = cfg
        self.storage = storage
        self.settings = settings
        self.commands = CommandHandler(storage, settings)
        self._llm = llm
        self.search = search
        self.today = today
        self.params = GenParams(temperature=cfg.temperature, top_p=cfg.top_p, num_ctx=cfg.num_ctx)

    # --- entry point ---------------------------------------------------------

    async def handle_message(self, text: str, emit: Emit) -> None:
        text = (text or "").strip()
        if not text:
            await emit({"type": "error", "message": ERR_EMPTY})
            return
        cmd = parse_command(text)
        if cmd is None:
            await self._chat_turn(text, emit)
        elif cmd.is_search and cmd.args:
            await self._search_turn(text, cmd.name, cmd.args, emit)
        else:
            await self._system_reply(self.commands.handle(cmd), emit)

    # --- turn types ------------------------------------------------------------

    async def _system_reply(self, text: str, emit: Emit) -> None:
        await emit({"type": "start", "emotion": DEFAULT_EMOTION, "system": True})
        await emit({"type": "delta", "text": text})
        await emit(
            {"type": "end", "emotion": DEFAULT_EMOTION, "text": text, "sources": [], "system": True}
        )

    def _system_prompt(self) -> str:
        s = self.settings.get_all()
        memories = [m.text for m in self.storage.list_memories()]
        return render_system_prompt(s["self_name"], s["user_name"], memories)

    def _messages(self, user_message: str, with_history: bool = True) -> list[dict]:
        history = self.storage.get_history(HISTORY_FETCH_LIMIT) if with_history else []
        return build_messages(
            self._system_prompt(),
            history,
            user_message,
            num_ctx=self.cfg.num_ctx,
            reply_reserve=self.cfg.reply_reserve_tokens,
        )

    async def _chat_turn(self, text: str, emit: Emit) -> None:
        await emit({"type": "status", "state": "thinking"})
        result = await self._generate(self._messages(text), emit, strip_sources=False)
        if result is None:
            return
        emotion, reply, _ = result
        await emit({"type": "end", "emotion": emotion, "text": reply, "sources": [], "system": False})
        self._remember_turn(text, reply)

    async def _search_turn(self, raw: str, kind: str, query: str, emit: Emit) -> None:
        await emit({"type": "status", "state": "searching"})
        results = await self._run_search(kind, query)
        selected = select_results(results, self.cfg.max_search_results)
        user_message = build_search_message(raw, selected, self.today())
        await emit({"type": "status", "state": "thinking"})
        # Search turns were trained as single-turn conversations: no history here.
        messages = self._messages(user_message, with_history=False)
        result = await self._generate(messages, emit, strip_sources=True)
        if result is None:
            return
        emotion, reply, streamed = result
        line = build_sources_line(selected)
        if line:
            trailing = len(streamed) - len(streamed.rstrip("\n"))
            gap = "\n" * max(0, 2 - trailing) if reply else ""
            await emit({"type": "delta", "text": gap + line})
        final = finalize_search_reply(reply, selected)
        await emit(
            {
                "type": "end",
                "emotion": emotion,
                "text": final,
                "sources": sources_payload(selected),
                "system": False,
            }
        )
        # Keep context small: store the command, not the whole results block.
        self._remember_turn(raw, final)

    async def _run_search(self, kind: str, query: str) -> list[SearchResult]:
        try:
            if kind == "news":
                return await self.search.news(query)
            return await self.search.web(query)
        except Exception:
            log.exception("Search failed")
            return []

    def _remember_turn(self, user_text: str, reply: str) -> None:
        if not reply:
            return
        self.storage.add_message("user", user_text)
        self.storage.add_message("assistant", reply)

    # --- generation --------------------------------------------------------------

    async def _generate(
        self, messages: list[dict], emit: Emit, strip_sources: bool
    ) -> tuple[str, str, str] | None:
        """Stream one model reply.

        Returns (emotion, final text, text as streamed), or None after an error event.
        """
        llm = self._llm()
        stream = ReplyStream(strip_sources=strip_sources)
        started = False

        async def start_if_ready() -> None:
            nonlocal started
            if not started and stream.emotion is not None:
                started = True
                await emit({"type": "start", "emotion": stream.emotion, "system": False})

        async def consume() -> None:
            async for chunk in llm.stream_chat(messages, self.params):
                delta = stream.feed(chunk)
                await start_if_ready()
                if delta:
                    await emit({"type": "delta", "text": delta})

        try:
            await asyncio.wait_for(consume(), timeout=self.cfg.llm_total_timeout)
        except LLMUnavailableError as exc:
            log.warning("LLM unavailable: %s", exc)
            await emit({"type": "error", "message": ERR_UNAVAILABLE.get(llm.name, ERR_UNAVAILABLE_DEFAULT)})
            return None
        except (LLMTimeoutError, asyncio.TimeoutError) as exc:
            log.warning("LLM timeout: %s", exc)
            await emit({"type": "error", "message": ERR_TIMEOUT})
            return None
        except LLMResponseError as exc:
            log.warning("LLM error: %s", exc)
            await emit({"type": "error", "message": ERR_MODEL.format(model=llm.model)})
            return None
        except asyncio.CancelledError:
            raise
        except Exception:
            log.exception("Unexpected LLM failure")
            await emit({"type": "error", "message": ERR_GENERIC})
            return None

        tail = stream.finish()
        await start_if_ready()
        if tail:
            await emit({"type": "delta", "text": tail})
        return stream.emotion or DEFAULT_EMOTION, stream.final_text(), stream.text
