import pytest
from fastapi.testclient import TestClient

from saki.config import AppConfig
from saki.hotkey import (
    MOD_ALT, MOD_CONTROL, MOD_SHIFT, MOD_WIN, HotkeyError, HotkeyManager, parse_combo,
)
from saki.llm import FakeBackend
from saki.storage import Storage


class FakeHotkeys:
    """Records registrations instead of calling Windows."""

    def __init__(self, fail: str | None = None):
        self.fail = fail
        self.registered = []
        self.unregistered = 0
        self.on_press = None

    def register(self, mods, vk, on_press):
        if self.fail:
            raise HotkeyError(self.fail)
        self.registered.append((mods, vk))
        self.on_press = on_press

    def unregister(self):
        self.unregistered += 1


def test_parse_combo():
    assert parse_combo("Ctrl+Shift+S") == (MOD_CONTROL | MOD_SHIFT, ord("S"))
    assert parse_combo(" alt + f12 ") == (MOD_ALT, 0x7B)
    assert parse_combo("Win+Space") == (MOD_WIN, 0x20)
    assert parse_combo("ctrl+1") == (MOD_CONTROL, ord("1"))
    for bad in ["", "S", "Ctrl+", "Hyper+S", "Ctrl+Shift+é", "Ctrl+F99"]:
        with pytest.raises(HotkeyError):
            parse_combo(bad)


def test_manager_status_messages():
    fake = FakeHotkeys()
    m = HotkeyManager(fake)
    assert m.configure(True, "Ctrl+Shift+S") == (True, "")
    assert m.configure(True, "Ctrl+Shift+S") == (True, "")
    assert fake.registered == [(MOD_CONTROL | MOD_SHIFT, ord("S"))], "same combo: no re-register"
    ok, msg = m.configure(True, "S")
    assert not ok and "Ctrl, Shift, Alt hoặc Win" in msg
    assert not m.active
    assert m.configure(False, "") == (True, "")
    in_use = HotkeyManager(FakeHotkeys(fail="in_use"))
    ok, msg = in_use.configure(True, "Ctrl+Shift+S")
    assert not ok and "đang được một chương trình khác dùng" in msg
    ok, msg = HotkeyManager(auto=False).configure(True, "Ctrl+Shift+S")
    assert not ok and msg == "Phím tắt toàn cục chỉ hỗ trợ trên Windows."


def test_hotkey_over_websocket(tmp_path):
    from saki.server import create_app

    fake = FakeHotkeys()
    store = Storage(tmp_path / "saki.db")
    app = create_app(AppConfig(data_dir=tmp_path), llm=FakeBackend(), search=object(), storage=store,
                     hotkeys=HotkeyManager(fake))
    with TestClient(app) as client:
        with client.websocket_connect("/ws") as ws:
            ws.send_json({"type": "hotkey_config", "enabled": True, "combo": "Ctrl+Shift+S"})
            assert ws.receive_json() == {"type": "hotkey_status", "ok": True, "message": ""}
            fake.on_press()  # what the hotkey thread does on a key press
            assert ws.receive_json() == {"type": "hotkey"}
            ws.send_json({"type": "hotkey_config", "enabled": True, "combo": "nope"})
            status = ws.receive_json()
            assert status["type"] == "hotkey_status" and status["ok"] is False
        # The last client left: the hotkey is released.
        assert fake.unregistered >= 1
    store.close()
