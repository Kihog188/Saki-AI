"""FastAPI app: WebSocket chat at /ws plus a small REST API. Binds to 127.0.0.1 only."""

from __future__ import annotations

import asyncio
import contextlib
import json
import logging
from collections.abc import Callable
from contextlib import asynccontextmanager
from datetime import date

from fastapi import FastAPI, HTTPException, WebSocket, WebSocketDisconnect
from pydantic import BaseModel

from . import __version__
from .chat import ChatService
from .config import AppConfig
from .hardware import recommend_tier
from .llm import LLMBackend, create_backend
from .search.service import SearchProvider, create_search_service
from .settings import SettingsError, SettingsStore
from .storage import MemoryLimitError, Storage

log = logging.getLogger(__name__)

MEMORY_ERRORS = {
    "empty": "Nội dung ghi nhớ không được để trống.",
    "too_long": "Ghi nhớ quá dài (tối đa 200 ký tự).",
    "full": "Bộ nhớ đã đầy (tối đa 30 mục).",
}


class SettingsUpdate(BaseModel):
    self_name: str | None = None
    user_name: str | None = None
    llm_backend: str | None = None
    model: str | None = None
    port: int | None = None


class MemoryCreate(BaseModel):
    text: str


class AppState:
    """Everything the endpoints need. The LLM backend can be swapped at runtime."""

    def __init__(
        self,
        cfg: AppConfig,
        storage: Storage,
        llm: LLMBackend | None,
        search: SearchProvider | None,
        today: Callable[[], date],
    ):
        self.cfg = cfg
        self.storage = storage
        self.settings = SettingsStore(storage, cfg)
        self._owns_llm = llm is None
        s = self.settings.get_all()
        self.llm = llm or create_backend(cfg, s["llm_backend"], s["model"])
        self._http = None
        if search is None:
            search, self._http = create_search_service(cfg)
        self.search = search
        self.chat = ChatService(cfg, storage, self.settings, lambda: self.llm, search, today=today)

    async def apply_llm_settings(self) -> None:
        """Recreate the backend if llm_backend/model changed (only for an owned backend)."""
        if not self._owns_llm:
            return
        s = self.settings.get_all()
        if s["llm_backend"] == self.llm.name and s["model"] == self.llm.model:
            return
        old, self.llm = self.llm, create_backend(self.cfg, s["llm_backend"], s["model"])
        await old.aclose()
        log.info("LLM backend switched to %s (%s)", self.llm.name, self.llm.model)

    async def aclose(self) -> None:
        if self._owns_llm:
            await self.llm.aclose()
        if self._http is not None:
            await self._http.aclose()


def create_app(
    cfg: AppConfig | None = None,
    llm: LLMBackend | None = None,
    search: SearchProvider | None = None,
    storage: Storage | None = None,
    today: Callable[[], date] = date.today,
) -> FastAPI:
    cfg = cfg or AppConfig.load()
    owns_storage = storage is None
    storage = storage or Storage(cfg.db_path)
    state = AppState(cfg, storage, llm, search, today)

    @asynccontextmanager
    async def lifespan(app: FastAPI):
        rec = recommend_tier()
        log.info(
            "Saki %s ready. LLM: %s/%s. Free RAM %.2f GB -> tier %s",
            __version__, state.llm.name, state.llm.model, rec.free_ram_gb, rec.tier,
        )
        if rec.warning:
            log.warning(rec.warning)
        yield
        await state.aclose()
        if owns_storage:
            storage.close()

    app = FastAPI(title="Saki backend", version=__version__, lifespan=lifespan)
    app.state.saki = state

    # --- REST -------------------------------------------------------------------

    @app.get("/health")
    async def health():
        llm_health = await state.llm.health()
        return {
            "status": "ok",
            "version": __version__,
            "llm": {"backend": state.llm.name, "model": state.llm.model, **llm_health},
            "hardware": recommend_tier().to_dict(),
        }

    @app.get("/settings")
    async def get_settings():
        return state.settings.get_all()

    @app.put("/settings")
    async def put_settings(update: SettingsUpdate):
        before = state.settings.get_all()
        try:
            after = state.settings.update(**update.model_dump(exclude_none=True))
        except SettingsError as exc:
            raise HTTPException(status_code=400, detail=str(exc)) from None
        await state.apply_llm_settings()
        return {**after, "restart_required": after["port"] != before["port"]}

    @app.get("/history")
    async def get_history(limit: int = 50):
        return {"messages": state.storage.get_history(max(1, min(limit, 500)))}

    @app.delete("/history")
    async def delete_history():
        state.storage.clear_history()
        return {"ok": True}

    @app.get("/memories")
    async def list_memories():
        return {"memories": [m.to_dict() for m in state.storage.list_memories()]}

    @app.post("/memories", status_code=201)
    async def add_memory(body: MemoryCreate):
        try:
            return state.storage.add_memory(body.text).to_dict()
        except MemoryLimitError as exc:
            raise HTTPException(status_code=400, detail=MEMORY_ERRORS[exc.reason]) from None

    @app.delete("/memories/{memory_id}")
    async def delete_memory(memory_id: int):
        if not state.storage.delete_memory(memory_id):
            raise HTTPException(status_code=404, detail="Không tìm thấy ghi nhớ.")
        return {"ok": True}

    # --- WebSocket -------------------------------------------------------------

    @app.websocket("/ws")
    async def ws_chat(ws: WebSocket):
        await ws.accept()
        send_lock = asyncio.Lock()
        current: asyncio.Task | None = None

        async def emit(event: dict) -> None:
            async with send_lock:
                await ws.send_text(json.dumps(event, ensure_ascii=False))

        async def run_turn(text: str) -> None:
            try:
                await state.chat.handle_message(text, emit)
            except asyncio.CancelledError:
                with contextlib.suppress(Exception):
                    await emit({"type": "cancelled"})
                raise
            except Exception:
                log.exception("Chat turn failed")
                with contextlib.suppress(Exception):
                    await emit({"type": "error", "message": "Có lỗi xảy ra, bạn thử lại nhé."})

        async def cancel_current() -> None:
            nonlocal current
            if current is not None and not current.done():
                current.cancel()
                with contextlib.suppress(asyncio.CancelledError, Exception):
                    await current
            current = None

        try:
            while True:
                raw = await ws.receive_text()
                try:
                    msg = json.loads(raw)
                    kind = msg.get("type")
                except (ValueError, AttributeError):
                    kind, msg = None, {}
                if kind == "user_message" and isinstance(msg.get("text"), str):
                    await cancel_current()
                    current = asyncio.create_task(run_turn(msg["text"]))
                elif kind == "cancel":
                    await cancel_current()
                else:
                    await emit({"type": "error", "message": "Tin nhắn không hợp lệ."})
        except WebSocketDisconnect:
            pass
        finally:
            await cancel_current()

    return app
