"""User-editable settings: config defaults overridden by values saved in SQLite.

Both the /xh command and PUT /settings go through `SettingsStore.update`.
"""

from __future__ import annotations

from .config import AppConfig
from .storage import Storage

# `character_pack` was removed with the web UI: a value still stored in old databases is
# simply never read, because only these keys are.
EDITABLE_KEYS = ("self_name", "user_name", "llm_backend", "model", "port")
LLM_BACKENDS = ("ollama", "llamacpp")
MAX_NAME_CHARS = 20


class SettingsError(ValueError):
    """Invalid setting value. The message is user-facing Vietnamese."""


def validate_name(value: object) -> str:
    name = " ".join(str(value or "").split())
    if not name:
        raise SettingsError("Cách xưng hô không được để trống.")
    if len(name) > MAX_NAME_CHARS:
        raise SettingsError(f"Cách xưng hô quá dài (tối đa {MAX_NAME_CHARS} ký tự).")
    if any(c in name for c in "\"[]{}<>"):
        raise SettingsError("Cách xưng hô chứa ký tự không hợp lệ.")
    return name


class SettingsStore:
    def __init__(self, storage: Storage, config: AppConfig):
        self._storage = storage
        self._config = config

    def get_all(self) -> dict:
        saved = self._storage.all_settings()
        out: dict = {}
        for key in EDITABLE_KEYS:
            value = saved.get(key, getattr(self._config, key))
            out[key] = int(value) if key == "port" else value
        return out

    def get(self, key: str):
        return self.get_all()[key]

    def update(self, **changes) -> dict:
        """Validate and persist the given keys. Returns the new full settings."""
        clean: dict[str, object] = {}
        for key, value in changes.items():
            if value is None:
                continue
            if key not in EDITABLE_KEYS:
                raise SettingsError(f"Không có cài đặt '{key}'.")
            if key in ("self_name", "user_name"):
                clean[key] = validate_name(value)
            elif key == "llm_backend":
                if value not in LLM_BACKENDS:
                    raise SettingsError("llm_backend phải là 'ollama' hoặc 'llamacpp'.")
                clean[key] = value
            elif key == "model":
                model = str(value).strip()
                if not model:
                    raise SettingsError("Tên mô hình không được để trống.")
                clean[key] = model
            elif key == "port":
                try:
                    port = int(value)
                except (TypeError, ValueError):
                    raise SettingsError("Cổng phải là số.") from None
                if not 1024 <= port <= 65535:
                    raise SettingsError("Cổng phải nằm trong khoảng 1024–65535.")
                clean[key] = port
        for key, value in clean.items():
            self._storage.set_setting(key, value)
        return self.get_all()
