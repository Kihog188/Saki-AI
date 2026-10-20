"""Developer terminal client: python -m saki.cli [--url ws://127.0.0.1:8765/ws]

Type messages or commands (/se, /news, /rmb, /fgt, /xh, /clear, /help).
Local commands: /cancel stops the current answer, /quit exits.
Typing a new message while Saki is answering also cancels the old answer.
"""

from __future__ import annotations

import argparse
import asyncio
import json
import os
import sys

import websockets

DEFAULT_URL = "ws://127.0.0.1:8765/ws"


class Printer:
    def __init__(self, color: bool):
        self.color = color

    def _c(self, code: str, text: str) -> str:
        return f"\033[{code}m{text}\033[0m" if self.color else text

    def dim(self, text: str) -> str:
        return self._c("2", text)

    def cyan(self, text: str) -> str:
        return self._c("36", text)

    def yellow(self, text: str) -> str:
        return self._c("33", text)

    def red(self, text: str) -> str:
        return self._c("31", text)

    def out(self, text: str = "", end: str = "\n") -> None:
        sys.stdout.write(text + end)
        sys.stdout.flush()


def render_event(ev: dict, p: Printer) -> None:
    kind = ev.get("type")
    if kind == "status":
        label = "đang tìm kiếm..." if ev.get("state") == "searching" else "đang suy nghĩ..."
        p.out(p.dim(f"({label})"))
    elif kind == "start":
        who = "Hệ thống" if ev.get("system") else "Saki"
        p.out(p.cyan(f"{who} [{ev.get('emotion')}]: "), end="")
    elif kind == "delta":
        p.out(ev.get("text", ""), end="")
    elif kind == "end":
        p.out()
        sources = ev.get("sources") or []
        for s in sources:
            extra = " (paywall)" if s.get("paywalled") else ""
            date = s.get("date") or "không rõ ngày"
            link = s.get("display_url") or s.get("url")
            p.out(p.dim(f"  [{s['index']}] {s['title']} — {link} ({date}){extra}"))
        if sources:
            p.out()  # keep the prompt off the last source line
        p.out(p.yellow("> "), end="")
    elif kind == "reset":
        p.out()
        p.out(p.dim("(câu trả lời bị lặp, Saki trả lời lại...)"))
    elif kind == "error":
        p.out()
        p.out(p.red(f"[lỗi] {ev.get('message')}"))
        p.out(p.yellow("> "), end="")
    elif kind == "cancelled":
        p.out()
        p.out(p.dim("[đã dừng]"))
        p.out(p.yellow("> "), end="")


TERMINAL_EVENTS = ("end", "error", "cancelled")


async def receive_loop(ws, p: Printer, idle: asyncio.Event) -> None:
    async for raw in ws:
        try:
            ev = json.loads(raw)
        except ValueError:
            p.out(p.red(f"[bad message] {raw!r}"))
            continue
        render_event(ev, p)
        if ev.get("type") in TERMINAL_EVENTS:
            idle.set()


async def input_loop(ws, p: Printer, idle: asyncio.Event, wait_each: bool) -> None:
    """Read lines from stdin. With `wait_each` (piped input), wait for each answer."""
    p.out(p.dim("Gõ tin nhắn hoặc /help. /cancel để dừng câu trả lời, /quit để thoát."))
    p.out(p.yellow("> "), end="")
    while True:
        try:
            line = await asyncio.to_thread(sys.stdin.readline)
        except (EOFError, KeyboardInterrupt):
            return
        if not line:  # EOF
            await idle.wait()
            return
        text = line.strip()
        if not text:
            p.out(p.yellow("> "), end="")
            continue
        if text.lower() in ("/quit", "/exit"):
            return
        if text.lower() == "/cancel":
            await ws.send(json.dumps({"type": "cancel"}))
            continue
        if wait_each:
            p.out(text)
        idle.clear()
        await ws.send(json.dumps({"type": "user_message", "text": text}, ensure_ascii=False))
        if wait_each:
            await idle.wait()


async def run(url: str, color: bool) -> int:
    p = Printer(color)
    idle = asyncio.Event()
    idle.set()
    wait_each = not sys.stdin.isatty()
    try:
        async with websockets.connect(url, max_size=2**22) as ws:
            receiver = asyncio.create_task(receive_loop(ws, p, idle))
            sender = asyncio.create_task(input_loop(ws, p, idle, wait_each))
            done, pending = await asyncio.wait({receiver, sender}, return_when=asyncio.FIRST_COMPLETED)
            for t in pending:
                t.cancel()
            if receiver in done and receiver.exception() is None:
                p.out(p.red("\nMất kết nối tới máy chủ Saki."))
    except (OSError, websockets.exceptions.WebSocketException) as exc:
        p.out(p.red(f"Không kết nối được tới {url}: {exc}"))
        p.out("Hãy chạy máy chủ trước: python -m saki")
        return 1
    return 0


def main(argv: list[str] | None = None) -> None:
    for stream in (sys.stdout, sys.stderr, sys.stdin):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")
        except (AttributeError, ValueError):
            pass
    parser = argparse.ArgumentParser(prog="python -m saki.cli", description="Saki terminal client")
    parser.add_argument("--url", default=DEFAULT_URL)
    parser.add_argument("--no-color", action="store_true")
    args = parser.parse_args(argv)
    color = not args.no_color and sys.stdout.isatty()
    if color and os.name == "nt":
        os.system("")  # enables ANSI escape codes in the Windows console
    try:
        code = asyncio.run(run(args.url, color))
    except KeyboardInterrupt:
        code = 0
    # The input thread may still be blocked on stdin; exit without waiting for it.
    sys.stdout.flush()
    os._exit(code)


if __name__ == "__main__":
    main()
