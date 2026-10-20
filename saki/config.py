"""Application configuration, per-user paths and logging setup."""

from __future__ import annotations

import json
import logging
import os
import sys
from dataclasses import asdict, dataclass, field, fields
from logging.handlers import RotatingFileHandler
from pathlib import Path

log = logging.getLogger(__name__)

APP_NAME = "Saki"
HOST = "127.0.0.1"  # local only, never exposed on the network
DEFAULT_PORT = 8765


def default_data_dir() -> Path:
    """Per-user app-data folder (%APPDATA%\\Saki on Windows)."""
    override = os.environ.get("SAKI_DATA_DIR")
    if override:
        return Path(override)
    if sys.platform == "win32":
        base = os.environ.get("APPDATA") or str(Path.home() / "AppData" / "Roaming")
        return Path(base) / APP_NAME
    if sys.platform == "darwin":
        return Path.home() / "Library" / "Application Support" / APP_NAME
    base = os.environ.get("XDG_DATA_HOME") or str(Path.home() / ".local" / "share")
    return Path(base) / APP_NAME.lower()


@dataclass
class AppConfig:
    """Static configuration, loaded from `<data_dir>/config.json` if present.

    `self_name`, `user_name`, `llm_backend`, `model` and `port` are only defaults:
    values saved through /xh or PUT /settings (stored in SQLite) take precedence.
    """

    data_dir: Path = field(default_factory=default_data_dir)
    port: int = DEFAULT_PORT

    # Persona defaults
    self_name: str = "Saki"
    user_name: str = "bạn"

    # LLM
    llm_backend: str = "ollama"  # "ollama" | "llamacpp"
    model: str = "saki"
    ollama_url: str = "http://127.0.0.1:11434"
    llamacpp_url: str = "http://127.0.0.1:8080"
    temperature: float = 0.3
    top_p: float = 0.8
    num_ctx: int = 2048
    reply_reserve_tokens: int = 512
    llm_read_timeout: float = 120.0  # max seconds between two streamed chunks
    llm_total_timeout: float = 300.0  # max seconds for a whole reply

    # Search
    search_region: str = "vn-vi"
    search_cache_ttl: float = 600.0
    feed_cache_ttl: float = 300.0
    news_source_timeout: float = 6.0
    ddg_timeout: float = 8.0
    ddg_cooldown: float = 1.5
    max_search_results: int = 4
    sources_file: Path | None = None  # defaults to the bundled saki/search/sources.json

    @property
    def db_path(self) -> Path:
        return self.data_dir / "saki.db"

    @property
    def log_dir(self) -> Path:
        return self.data_dir / "logs"

    @classmethod
    def load(cls, data_dir: Path | None = None) -> "AppConfig":
        cfg = cls(data_dir=Path(data_dir)) if data_dir else cls()
        path = cfg.data_dir / "config.json"
        if not path.is_file():
            return cfg
        try:
            raw = json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            log.warning("Ignoring invalid config file %s: %s", path, exc)
            return cfg
        known = {f.name for f in fields(cls)} - {"data_dir"}
        for key, value in raw.items():
            if key not in known:
                log.warning("Unknown config key ignored: %s", key)
                continue
            if key == "sources_file" and value:
                value = Path(value)
            setattr(cfg, key, value)
        return cfg

    def to_dict(self) -> dict:
        return {k: str(v) if isinstance(v, Path) else v for k, v in asdict(self).items()}


def setup_logging(cfg: AppConfig, level: int = logging.INFO) -> None:
    """Console + rotating file log (4 files x 1 MB) in the app-data folder. No telemetry."""
    cfg.log_dir.mkdir(parents=True, exist_ok=True)
    fmt = logging.Formatter("%(asctime)s %(levelname)s %(name)s: %(message)s")
    root = logging.getLogger()
    root.setLevel(level)
    for h in list(root.handlers):
        if getattr(h, "_saki", False):
            root.removeHandler(h)
    file_handler = RotatingFileHandler(
        cfg.log_dir / "saki.log", maxBytes=1_000_000, backupCount=3, encoding="utf-8"
    )
    console = logging.StreamHandler()
    for h in (file_handler, console):
        h.setFormatter(fmt)
        h._saki = True  # type: ignore[attr-defined]
        root.addHandler(h)
    # httpx logs every request URL (including search queries) at INFO.
    logging.getLogger("httpx").setLevel(logging.WARNING)
    logging.getLogger("primp").setLevel(logging.WARNING)
