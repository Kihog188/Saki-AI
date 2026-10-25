"""SQLite storage: settings, conversation history and long-term memories."""

from __future__ import annotations

import sqlite3
import threading
import time
from dataclasses import dataclass
from pathlib import Path

from .textnorm import fold

MAX_MEMORY_CHARS = 200
MAX_MEMORY_ITEMS = 30

_SCHEMA = """
CREATE TABLE IF NOT EXISTS settings (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL
);
CREATE TABLE IF NOT EXISTS messages (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    role       TEXT NOT NULL,
    content    TEXT NOT NULL,
    created_at REAL NOT NULL,
    emotion    TEXT,
    kind       TEXT NOT NULL DEFAULT 'chat'
);
CREATE TABLE IF NOT EXISTS memories (
    id         INTEGER PRIMARY KEY AUTOINCREMENT,
    text       TEXT NOT NULL,
    created_at REAL NOT NULL
);
"""


class MemoryLimitError(ValueError):
    """Raised when a memory item is empty, too long, or the store is full."""

    def __init__(self, reason: str):
        super().__init__(reason)
        self.reason = reason  # "empty" | "too_long" | "full"


@dataclass(frozen=True)
class Memory:
    id: int
    text: str
    created_at: float

    def to_dict(self) -> dict:
        return {"id": self.id, "text": self.text, "created_at": self.created_at}


class Storage:
    """Thread-safe wrapper around one SQLite file (or ':memory:')."""

    def __init__(self, path: Path | str):
        if str(path) != ":memory:":
            Path(path).parent.mkdir(parents=True, exist_ok=True)
        self._conn = sqlite3.connect(str(path), check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._lock = threading.Lock()
        with self._lock, self._conn:
            self._conn.executescript(_SCHEMA)
            self._migrate()

    def _migrate(self) -> None:
        """Add columns introduced after the first release to existing databases."""
        cols = {r["name"] for r in self._conn.execute("PRAGMA table_info(messages)")}
        if "emotion" not in cols:
            self._conn.execute("ALTER TABLE messages ADD COLUMN emotion TEXT")
        if "kind" not in cols:
            self._conn.execute("ALTER TABLE messages ADD COLUMN kind TEXT NOT NULL DEFAULT 'chat'")

    def close(self) -> None:
        with self._lock:
            self._conn.close()

    # --- settings ---------------------------------------------------------

    def get_setting(self, key: str, default: str | None = None) -> str | None:
        with self._lock:
            row = self._conn.execute("SELECT value FROM settings WHERE key = ?", (key,)).fetchone()
        return row["value"] if row else default

    def set_setting(self, key: str, value: object) -> None:
        with self._lock, self._conn:
            self._conn.execute(
                "INSERT INTO settings(key, value) VALUES(?, ?) "
                "ON CONFLICT(key) DO UPDATE SET value = excluded.value",
                (key, str(value)),
            )

    def all_settings(self) -> dict[str, str]:
        with self._lock:
            rows = self._conn.execute("SELECT key, value FROM settings").fetchall()
        return {r["key"]: r["value"] for r in rows}

    # --- conversation history ---------------------------------------------

    def add_message(
        self, role: str, content: str, emotion: str | None = None, kind: str = "chat"
    ) -> None:
        """`kind` is "chat" or "search" (search turns are kept out of the model context)."""
        with self._lock, self._conn:
            self._conn.execute(
                "INSERT INTO messages(role, content, created_at, emotion, kind) VALUES(?, ?, ?, ?, ?)",
                (role, content, time.time(), emotion, kind),
            )

    def get_history(self, limit: int = 50, before_id: int | None = None) -> list[dict]:
        """The most recent `limit` messages (older than `before_id` if given), oldest first."""
        where, params = ("WHERE id < ? ", (before_id, limit)) if before_id is not None else ("", (limit,))
        with self._lock:
            rows = self._conn.execute(
                "SELECT id, role, content, emotion, kind, created_at FROM messages "
                f"{where}ORDER BY id DESC LIMIT ?",
                params,
            ).fetchall()
        return [dict(r) for r in reversed(rows)]

    def clear_history(self) -> None:
        with self._lock, self._conn:
            self._conn.execute("DELETE FROM messages")

    # --- memories ---------------------------------------------------------

    def list_memories(self) -> list[Memory]:
        with self._lock:
            rows = self._conn.execute(
                "SELECT id, text, created_at FROM memories ORDER BY id"
            ).fetchall()
        return [Memory(r["id"], r["text"], r["created_at"]) for r in rows]

    def add_memory(self, text: str) -> Memory:
        """Add a memory. Adding an identical text again returns the existing item."""
        text = " ".join(text.split())
        if not text:
            raise MemoryLimitError("empty")
        if len(text) > MAX_MEMORY_CHARS:
            raise MemoryLimitError("too_long")
        with self._lock, self._conn:
            existing = self._conn.execute(
                "SELECT id, text, created_at FROM memories WHERE text = ?", (text,)
            ).fetchone()
            if existing:
                return Memory(existing["id"], existing["text"], existing["created_at"])
            count = self._conn.execute("SELECT COUNT(*) FROM memories").fetchone()[0]
            if count >= MAX_MEMORY_ITEMS:
                raise MemoryLimitError("full")
            now = time.time()
            cur = self._conn.execute(
                "INSERT INTO memories(text, created_at) VALUES(?, ?)", (text, now)
            )
            return Memory(cur.lastrowid, text, now)

    def get_memory(self, memory_id: int) -> Memory | None:
        with self._lock:
            r = self._conn.execute(
                "SELECT id, text, created_at FROM memories WHERE id = ?", (memory_id,)
            ).fetchone()
        return Memory(r["id"], r["text"], r["created_at"]) if r else None

    def delete_memory(self, memory_id: int) -> bool:
        with self._lock, self._conn:
            cur = self._conn.execute("DELETE FROM memories WHERE id = ?", (memory_id,))
        return cur.rowcount > 0

    def find_memories(self, needle: str) -> list[Memory]:
        """Memories containing `needle` (case- and accent-insensitive)."""
        key = fold(" ".join(needle.split()))
        if not key:
            return []
        return [m for m in self.list_memories() if key in fold(m.text)]
