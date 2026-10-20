"""Slash commands, parsed by the backend before anything reaches the model."""

from __future__ import annotations

import re
from dataclasses import dataclass

from .settings import SettingsError, SettingsStore
from .storage import MAX_MEMORY_CHARS, MAX_MEMORY_ITEMS, MemoryLimitError, Storage

KNOWN_COMMANDS = ("se", "news", "rmb", "fgt", "xh", "clear", "help")
SEARCH_COMMANDS = ("se", "news")

_COMMAND_RE = re.compile(r"^\s*/(\S+)\s*(.*)$", re.DOTALL)

HELP_TEXT = (
    "Các lệnh:\n"
    "/se <nội dung> — tìm kiếm trên web\n"
    "/news <chủ đề> — tìm tin tức mới\n"
    "/rmb <nội dung> — ghi nhớ một điều\n"
    "/fgt [số | nội dung] — xem hoặc xóa ghi nhớ\n"
    "/xh <tự xưng> <gọi người dùng> — đổi cách xưng hô, ví dụ /xh em anh\n"
    "/clear — xóa lịch sử trò chuyện\n"
    "/help — xem danh sách lệnh"
)

USAGE = {
    "se": "Cách dùng: /se <nội dung cần tìm>",
    "news": "Cách dùng: /news <chủ đề tin tức>",
    "rmb": "Cách dùng: /rmb <nội dung cần nhớ>",
    "xh": "Cách dùng: /xh <tự xưng> <gọi người dùng>, ví dụ /xh em anh",
}


@dataclass(frozen=True)
class Command:
    name: str  # lowercased command name without "/"
    args: str
    raw: str

    @property
    def known(self) -> bool:
        return self.name in KNOWN_COMMANDS

    @property
    def is_search(self) -> bool:
        return self.name in SEARCH_COMMANDS


def parse_command(text: str) -> Command | None:
    """A message is a command if it starts with '/' directly followed by a name."""
    m = _COMMAND_RE.match(text or "")
    if not m:
        return None
    return Command(name=m.group(1).lower(), args=m.group(2).strip(), raw=text.strip())


def _format_memory_list(memories) -> str:
    return "\n".join(f"{m.id}. {m.text}" for m in memories)


class CommandHandler:
    """Executes the commands that do not need the model. Returns Vietnamese replies."""

    def __init__(self, storage: Storage, settings: SettingsStore):
        self.storage = storage
        self.settings = settings

    def handle(self, cmd: Command) -> str:
        if not cmd.known:
            return f"Không có lệnh /{cmd.name}. Gõ /help để xem danh sách lệnh."
        if cmd.is_search:
            # Search commands only reach here with missing arguments.
            return USAGE[cmd.name]
        return getattr(self, f"_cmd_{cmd.name}")(cmd.args)

    def _cmd_help(self, args: str) -> str:
        return HELP_TEXT

    def _cmd_clear(self, args: str) -> str:
        self.storage.clear_history()
        return "Đã xóa lịch sử trò chuyện."

    def _cmd_rmb(self, args: str) -> str:
        if not args:
            return USAGE["rmb"]
        before = {m.id for m in self.storage.list_memories()}
        try:
            mem = self.storage.add_memory(args)
        except MemoryLimitError as exc:
            if exc.reason == "too_long":
                return f"Ghi nhớ quá dài (tối đa {MAX_MEMORY_CHARS} ký tự)."
            if exc.reason == "full":
                return f"Bộ nhớ đã đầy (tối đa {MAX_MEMORY_ITEMS} mục). Dùng /fgt để xóa bớt."
            return USAGE["rmb"]
        if mem.id in before:
            return f"Đã nhớ từ trước: {mem.text}"
        return f"Đã nhớ: {mem.text}"

    def _cmd_fgt(self, args: str) -> str:
        if not args:
            memories = self.storage.list_memories()
            if not memories:
                return "Chưa có ghi nhớ nào."
            return "Ghi nhớ:\n" + _format_memory_list(memories) + "\nXóa bằng /fgt <số>."
        if args.isdigit():
            mem = self.storage.get_memory(int(args))
            if mem is None or not self.storage.delete_memory(mem.id):
                return f"Không tìm thấy ghi nhớ số {args}."
            return f"Đã quên: {mem.text}"
        matches = self.storage.find_memories(args)
        if not matches:
            return f"Không có ghi nhớ nào chứa “{args}”."
        if len(matches) == 1:
            self.storage.delete_memory(matches[0].id)
            return f"Đã quên: {matches[0].text}"
        return (
            f"Có {len(matches)} ghi nhớ khớp:\n"
            + _format_memory_list(matches)
            + "\nGõ /fgt <số> để xóa đúng mục."
        )

    def _cmd_xh(self, args: str) -> str:
        parts = args.split()
        if not parts:
            s = self.settings.get_all()
            return (
                f"Đang xưng hô: tự xưng “{s['self_name']}”, gọi người dùng là “{s['user_name']}”.\n"
                + USAGE["xh"]
            )
        if len(parts) != 2:
            return USAGE["xh"]
        try:
            s = self.settings.update(self_name=parts[0], user_name=parts[1])
        except SettingsError as exc:
            return str(exc)
        return f"Đã đổi xưng hô: tự xưng “{s['self_name']}”, gọi người dùng là “{s['user_name']}”."
