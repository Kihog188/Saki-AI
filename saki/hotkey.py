"""Optional global hotkey (Windows only) for the desktop app.

Godot cannot register a system-wide hotkey without native code, so the backend does it
with the Windows `RegisterHotKey` API through ctypes (nothing to compile). When the key is
pressed, every connected WebSocket client gets `{"type": "hotkey"}`.

The client turns it on with `{"type": "hotkey_config", "enabled": true, "combo":
"Ctrl+Shift+S"}` and gets `{"type": "hotkey_status", "ok": bool, "message": "..."}` back.
On other systems, or if another program already owns the combination, `ok` is false with a
Vietnamese message and the feature simply stays off.
"""

from __future__ import annotations

import logging
import sys
import threading
from collections.abc import Callable
from typing import Protocol

log = logging.getLogger(__name__)

MOD_ALT, MOD_CONTROL, MOD_SHIFT, MOD_WIN, MOD_NOREPEAT = 0x1, 0x2, 0x4, 0x8, 0x4000
MODIFIERS = {"ctrl": MOD_CONTROL, "control": MOD_CONTROL, "shift": MOD_SHIFT, "alt": MOD_ALT, "win": MOD_WIN}
NAMED_KEYS = {
    "space": 0x20, "tab": 0x09, "pageup": 0x21, "pagedown": 0x22, "end": 0x23, "home": 0x24,
    "left": 0x25, "up": 0x26, "right": 0x27, "down": 0x28, "insert": 0x2D, "delete": 0x2E,
}
ERROR_HOTKEY_ALREADY_REGISTERED = 1409

MSG_UNSUPPORTED = "Phím tắt toàn cục chỉ hỗ trợ trên Windows."
MSG_IN_USE = "Phím tắt {combo} đang được một chương trình khác dùng. Hãy chọn tổ hợp khác."
MSG_FAILED = "Không đăng ký được phím tắt {combo}."


class HotkeyError(ValueError):
    """Invalid or unavailable hotkey. The message is user-facing Vietnamese."""


def parse_combo(text: str) -> tuple[int, int]:
    """'Ctrl+Shift+S' -> (MOD_CONTROL | MOD_SHIFT, 0x53). Raises HotkeyError."""
    parts = [p.strip().lower() for p in str(text or "").replace(" ", "").split("+") if p.strip()]
    if not parts:
        raise HotkeyError("Phím tắt trống.")
    mods = 0
    for p in parts[:-1]:
        if p not in MODIFIERS:
            raise HotkeyError(f"Phím bổ trợ '{p}' không hợp lệ (dùng Ctrl, Shift, Alt, Win).")
        mods |= MODIFIERS[p]
    key = parts[-1]
    if len(key) == 1 and (key.isascii() and key.isalnum()):
        vk = ord(key.upper())
    elif key.startswith("f") and key[1:].isdigit() and 1 <= int(key[1:]) <= 24:
        vk = 0x70 + int(key[1:]) - 1
    elif key in NAMED_KEYS:
        vk = NAMED_KEYS[key]
    else:
        raise HotkeyError(f"Phím '{parts[-1]}' không được hỗ trợ.")
    if mods == 0:
        raise HotkeyError("Phím tắt cần ít nhất một phím Ctrl, Shift, Alt hoặc Win.")
    return mods, vk


class HotkeyBackend(Protocol):
    def register(self, mods: int, vk: int, on_press: Callable[[], None]) -> None: ...
    def unregister(self) -> None: ...


class WindowsHotkeyBackend:
    """RegisterHotKey on a dedicated thread with its own message loop."""

    HOTKEY_ID = 0x5A1C
    WM_HOTKEY = 0x0312
    WM_QUIT = 0x0012
    ASFW_ANY = -1

    def __init__(self) -> None:
        import ctypes
        from ctypes import wintypes

        self._ctypes = ctypes
        self._wintypes = wintypes
        self._user32 = ctypes.WinDLL("user32", use_last_error=True)
        self._kernel32 = ctypes.WinDLL("kernel32", use_last_error=True)
        self._thread: threading.Thread | None = None
        self._thread_id = 0

    def register(self, mods: int, vk: int, on_press: Callable[[], None]) -> None:
        self.unregister()
        ready = threading.Event()
        result: dict[str, int] = {}
        self._thread = threading.Thread(
            target=self._loop, args=(mods, vk, on_press, ready, result), name="saki-hotkey", daemon=True
        )
        self._thread.start()
        if not ready.wait(3.0):
            raise HotkeyError("Không đăng ký được phím tắt (hết thời gian chờ).")
        if not result.get("ok"):
            self._thread = None
            if result.get("error") == ERROR_HOTKEY_ALREADY_REGISTERED:
                raise HotkeyError("in_use")
            raise HotkeyError("failed")

    def unregister(self) -> None:
        if self._thread is None:
            return
        self._user32.PostThreadMessageW(self._thread_id, self.WM_QUIT, 0, 0)
        self._thread.join(2.0)
        self._thread = None

    def _loop(self, mods, vk, on_press, ready, result) -> None:
        self._thread_id = self._kernel32.GetCurrentThreadId()
        ok = self._user32.RegisterHotKey(None, self.HOTKEY_ID, mods | MOD_NOREPEAT, vk)
        result["ok"] = int(bool(ok))
        result["error"] = self._ctypes.get_last_error()
        ready.set()
        if not ok:
            return
        msg = self._wintypes.MSG()
        try:
            while self._user32.GetMessageW(self._ctypes.byref(msg), None, 0, 0) > 0:
                if msg.message == self.WM_HOTKEY:
                    # The process that got the key press may hand the foreground to the
                    # app, so Windows lets the Saki window come to the front.
                    self._user32.AllowSetForegroundWindow(self.ASFW_ANY)
                    on_press()
        finally:
            self._user32.UnregisterHotKey(None, self.HOTKEY_ID)


def default_backend() -> HotkeyBackend | None:
    if sys.platform != "win32":
        return None
    try:
        return WindowsHotkeyBackend()
    except (OSError, AttributeError):  # pragma: no cover - broken Windows install
        log.exception("Global hotkey unavailable")
        return None


class HotkeyManager:
    """Keeps at most one registered hotkey and reports status in Vietnamese."""

    def __init__(self, backend: HotkeyBackend | None = None, *, auto: bool = True):
        self._backend = backend if backend is not None or not auto else default_backend()
        self._active: tuple[int, int] | None = None
        self.on_press: Callable[[], None] = lambda: None

    @property
    def active(self) -> bool:
        return self._active is not None

    def configure(self, enabled: bool, combo: str) -> tuple[bool, str]:
        """Turns the hotkey on/off. Returns (ok, message); never raises."""
        if not enabled:
            self.disable()
            return True, ""
        if self._backend is None:
            return False, MSG_UNSUPPORTED
        try:
            mods, vk = parse_combo(combo)
        except HotkeyError as exc:
            self.disable()
            return False, str(exc)
        if self._active == (mods, vk):
            return True, ""
        self.disable()
        try:
            self._backend.register(mods, vk, lambda: self.on_press())
        except HotkeyError as exc:
            reason = str(exc)
            log.warning("Global hotkey %s not registered: %s", combo, reason)
            if reason == "in_use":
                return False, MSG_IN_USE.format(combo=combo)
            if reason == "failed":
                return False, MSG_FAILED.format(combo=combo)
            return False, reason
        self._active = (mods, vk)
        log.info("Global hotkey %s registered", combo)
        return True, ""

    def disable(self) -> None:
        if self._active is not None and self._backend is not None:
            self._backend.unregister()
        self._active = None
