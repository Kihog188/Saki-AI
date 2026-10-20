from datetime import date

import pytest
from fastapi.testclient import TestClient

from saki.config import AppConfig
from saki.llm import FakeBackend, LLMUnavailableError
from saki.prompts import build_search_message, render_system_prompt
from saki.search.models import SearchResult
from saki.storage import Storage

TODAY = date(2026, 10, 19)
TERMINAL = {"end", "error", "cancelled"}


class FakeSearch:
    def __init__(self, results=None):
        self.results = results or []
        self.calls = []

    async def web(self, query):
        self.calls.append(("web", query))
        return list(self.results)

    async def news(self, query):
        self.calls.append(("news", query))
        return list(self.results)


NEWS_RESULTS = [
    SearchResult("Giá vàng giảm", "https://tuoitre.vn/b", "tuoitre.vn", date(2026, 10, 18), "SJC giảm."),
    SearchResult("Giá vàng tăng", "https://vnexpress.net/a", "vnexpress.net", date(2026, 10, 19), "SJC tăng."),
]


@pytest.fixture
def env(tmp_path):
    from saki.server import create_app

    cfg = AppConfig(data_dir=tmp_path)
    storage = Storage(tmp_path / "saki.db")
    llm = FakeBackend()
    search = FakeSearch()
    app = create_app(cfg, llm=llm, search=search, storage=storage, today=lambda: TODAY)
    with TestClient(app) as client:
        yield client, llm, search, storage
    storage.close()


def turn(ws, text):
    ws.send_json({"type": "user_message", "text": text})
    events = []
    while True:
        ev = ws.receive_json()
        events.append(ev)
        if ev["type"] in TERMINAL:
            return events


def deltas(events):
    return "".join(e["text"] for e in events if e["type"] == "delta")


def test_chat_turn_streams_and_saves_history(env):
    client, llm, _, storage = env
    llm.reply = "[happy] Chào bạn. Gõ /nho để Saki nhớ nhé.<|im_end|>"
    with client.websocket_connect("/ws") as ws:
        events = turn(ws, "Xin chào")
    types = [e["type"] for e in events]
    assert types[0] == "status" and events[0]["state"] == "thinking"
    assert types[1] == "start" and events[1] == {"type": "start", "emotion": "happy", "system": False}
    assert types[-1] == "end"
    end = events[-1]
    assert end["emotion"] == "happy"
    assert end["text"] == "Chào bạn. Gõ /rmb để Saki nhớ nhé."
    assert end["sources"] == [] and end["system"] is False
    assert deltas(events).strip() == end["text"]
    assert [(m["role"], m["content"]) for m in storage.get_history()] == [
        ("user", "Xin chào"),
        ("assistant", "Chào bạn. Gõ /rmb để Saki nhớ nhé."),
    ]
    sent = llm.calls[0]
    assert sent[0] == {"role": "system", "content": render_system_prompt()}
    assert sent[-1] == {"role": "user", "content": "Xin chào"}


def test_history_is_sent_on_next_turn(env):
    client, llm, _, _ = env
    with client.websocket_connect("/ws") as ws:
        turn(ws, "Câu 1")
        turn(ws, "Câu 2")
    roles = [m["role"] for m in llm.calls[1]]
    assert roles == ["system", "user", "assistant", "user"]


def test_news_turn_uses_exact_prompt_and_backend_sources(env):
    client, llm, search, storage = env
    search.results = NEWS_RESULTS
    storage.add_message("user", "câu cũ")
    storage.add_message("assistant", "trả lời cũ")
    llm.reply = "[thinking] Giá vàng hôm nay tăng [1].\n\nNguồn: [1] bịa.vn (01/01/2020)"
    with client.websocket_connect("/ws") as ws:
        events = turn(ws, "/news giá vàng")
    assert [e["state"] for e in events if e["type"] == "status"] == ["searching", "thinking"]
    assert search.calls == [("news", "giá vàng")]

    expected_user = build_search_message("/news giá vàng", [NEWS_RESULTS[1], NEWS_RESULTS[0]], TODAY)
    # Single-turn, like the training data: system + search message, no history.
    assert llm.calls[0] == [
        {"role": "system", "content": render_system_prompt()},
        {"role": "user", "content": expected_user},
    ]

    end = events[-1]
    assert end["emotion"] == "thinking"
    assert end["text"] == (
        "Giá vàng hôm nay tăng [1].\n\nNguồn: [1] vnexpress.net (19/10/2026), [2] tuoitre.vn (18/10/2026)"
    )
    assert [s["site"] for s in end["sources"]] == ["vnexpress.net", "tuoitre.vn"]
    assert end["sources"][0]["url"] == "https://vnexpress.net/a"
    assert "bịa.vn" not in deltas(events)
    assert deltas(events).strip() == end["text"]
    hist = storage.get_history()
    assert hist[2]["content"] == "/news giá vàng"
    assert hist[3]["content"] == end["text"]


def test_se_turn_without_results(env):
    client, llm, search, _ = env
    llm.reply = "[neutral] Không tìm thấy kết quả nào."
    with client.websocket_connect("/ws") as ws:
        events = turn(ws, "/SE thời tiết Huế")
    assert search.calls == [("web", "thời tiết Huế")]
    assert llm.calls[0][-1]["content"].endswith("[KẾT QUẢ TÌM KIẾM]\n(không có kết quả)")
    assert llm.calls[0][-1]["content"].startswith("/SE thời tiết Huế\n\n[HÔM NAY: 2026-10-19]")
    assert events[-1]["text"] == "Không tìm thấy kết quả nào."
    assert events[-1]["sources"] == []


def test_commands_over_websocket(env):
    client, llm, search, storage = env
    with client.websocket_connect("/ws") as ws:
        ev = turn(ws, "/rmb Tên tôi là Minh")
        assert ev[0] == {"type": "start", "emotion": "neutral", "system": True}
        assert ev[-1]["text"] == "Đã nhớ: Tên tôi là Minh" and ev[-1]["system"] is True

        assert turn(ws, "/xh em anh")[-1]["text"].startswith("Đã đổi xưng hô")
        turn(ws, "Chào em")
        assert llm.calls[-1][0]["content"] == render_system_prompt("em", "anh", ["Tên tôi là Minh"])

        assert "Tên tôi là Minh" in turn(ws, "/fgt")[-1]["text"]
        assert turn(ws, "/clear")[-1]["text"] == "Đã xóa lịch sử trò chuyện."
        assert storage.get_history() == []
        assert "/news" in turn(ws, "/help")[-1]["text"]
        assert turn(ws, "/abc")[-1]["text"].startswith("Không có lệnh /abc")
        assert turn(ws, "/se")[-1]["text"].startswith("Cách dùng:")
    assert search.calls == []
    assert len(llm.calls) == 1  # only the normal chat message reached the model


def test_llm_unavailable_gives_friendly_error(env):
    client, llm, _, storage = env
    llm.error = LLMUnavailableError("refused")
    with client.websocket_connect("/ws") as ws:
        events = turn(ws, "Xin chào")
        assert events[-1]["type"] == "error"
        assert "chưa kết nối được" in events[-1]["message"]
        llm.error = None
        assert turn(ws, "Lại nào")[-1]["type"] == "end"  # connection still usable
    assert [m["content"] for m in storage.get_history()][0] == "Lại nào"


def test_cancel_and_new_message(env):
    client, llm, _, storage = env
    llm.reply = "[neutral] " + "chữ " * 200
    llm.chunk_size = 2
    llm.delay = 0.01
    with client.websocket_connect("/ws") as ws:
        ws.send_json({"type": "user_message", "text": "Kể chuyện dài"})
        while ws.receive_json()["type"] != "delta":
            pass
        ws.send_json({"type": "cancel"})
        while True:
            ev = ws.receive_json()
            if ev["type"] == "cancelled":
                break
            assert ev["type"] == "delta"
        llm.reply, llm.delay = "[happy] Ừ.", 0
        assert turn(ws, "Thôi")[-1]["text"] == "Ừ."
    assert [m["content"] for m in storage.get_history()] == ["Thôi", "Ừ."]


def test_invalid_ws_message(env):
    client, *_ = env
    with client.websocket_connect("/ws") as ws:
        ws.send_text("not json")
        assert ws.receive_json() == {"type": "error", "message": "Tin nhắn không hợp lệ."}
        ws.send_json({"type": "user_message", "text": "   "})
        assert ws.receive_json() == {"type": "error", "message": "Tin nhắn trống."}


def test_rest_health(env):
    client, *_ = env
    h = client.get("/health").json()
    assert h["status"] == "ok"
    assert h["llm"]["backend"] == "fake" and h["llm"]["reachable"] is True
    assert h["hardware"]["tier"] in ("insufficient", "small", "standard")


def test_rest_settings(env):
    client, *_ = env
    s = client.get("/settings").json()
    assert s == {"self_name": "Saki", "user_name": "bạn", "llm_backend": "ollama", "model": "saki", "port": 8765}
    r = client.put("/settings", json={"self_name": "tớ", "user_name": "cậu"})
    assert r.status_code == 200
    assert r.json()["self_name"] == "tớ" and r.json()["restart_required"] is False
    assert client.put("/settings", json={"port": 9000}).json()["restart_required"] is True
    assert client.put("/settings", json={"llm_backend": "gpt"}).status_code == 400
    assert client.put("/settings", json={"user_name": ""}).status_code == 400
    # /xh sees the same setting
    with client.websocket_connect("/ws") as ws:
        assert "“tớ”" in turn(ws, "/xh")[-1]["text"]


def test_rest_history_and_memories(env):
    client, _, _, storage = env
    storage.add_message("user", "a")
    assert client.get("/history").json()["messages"][0]["content"] == "a"
    assert client.delete("/history").json() == {"ok": True}
    assert client.get("/history").json()["messages"] == []

    r = client.post("/memories", json={"text": "Thích mèo"})
    assert r.status_code == 201
    mid = r.json()["id"]
    assert client.get("/memories").json()["memories"][0]["text"] == "Thích mèo"
    assert client.post("/memories", json={"text": "x" * 201}).status_code == 400
    assert client.delete(f"/memories/{mid}").status_code == 200
    assert client.delete(f"/memories/{mid}").status_code == 404
