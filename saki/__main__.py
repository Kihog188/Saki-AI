"""Start the Saki backend: python -m saki [--port N] [--data-dir DIR] [--no-browser]."""

from __future__ import annotations

import argparse
import logging
import socket
import sys
import threading
import time
import webbrowser
from collections.abc import Callable
from pathlib import Path

import httpx
import uvicorn

from .config import HOST, AppConfig, setup_logging
from .server import create_app

log = logging.getLogger("saki")

MSG_ALREADY_RUNNING = "Saki đang chạy sẵn ở {url}."
MSG_PORT_BUSY = (
    "Cổng {port} đang bị một ứng dụng khác sử dụng. "
    "Hãy đóng ứng dụng đó, hoặc chạy Saki với cổng khác: python -m saki --port 8766"
)


def port_in_use(port: int, host: str = HOST) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        try:
            sock.bind((host, port))
        except OSError:
            return True
    return False


def is_saki_running(url: str) -> bool:
    try:
        r = httpx.get(f"{url}/health", timeout=2.0)
        data = r.json() if r.status_code == 200 else {}
        return isinstance(data, dict) and data.get("status") == "ok" and "llm" in data
    except (httpx.HTTPError, ValueError):
        return False


def open_when_ready(
    server: uvicorn.Server,
    url: str,
    opener: Callable[[str], object] = webbrowser.open,
    timeout: float = 60.0,
    interval: float = 0.1,
) -> bool:
    """Wait until uvicorn is listening, then open `url`. False if it never started."""
    deadline = time.monotonic() + timeout
    while not server.started:
        if server.should_exit or time.monotonic() > deadline:
            return False
        time.sleep(interval)
    opener(url)
    return True


def main(argv: list[str] | None = None) -> int:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")  # Vietnamese on Windows consoles
        except (AttributeError, ValueError):
            pass

    parser = argparse.ArgumentParser(prog="python -m saki", description="Saki backend server")
    parser.add_argument("--port", type=int, help="override the saved/configured port")
    parser.add_argument("--data-dir", type=Path, help="app-data folder (default: %%APPDATA%%\\Saki)")
    parser.add_argument("--log-level", default="INFO", choices=["DEBUG", "INFO", "WARNING", "ERROR"])
    parser.add_argument("--no-browser", action="store_true", help="do not open the chat page")
    args = parser.parse_args(argv)

    cfg = AppConfig.load(args.data_dir)
    setup_logging(cfg, getattr(logging, args.log_level))
    open_browser = cfg.open_browser and not args.no_browser
    app = create_app(cfg)
    port = args.port or app.state.saki.settings.get("port")
    url = f"http://{HOST}:{port}"

    if port_in_use(port):
        app.state.saki.storage.close()
        if is_saki_running(url):
            print(MSG_ALREADY_RUNNING.format(url=url))
            if open_browser:
                webbrowser.open(f"{url}/")
            return 0
        print(MSG_PORT_BUSY.format(port=port), file=sys.stderr)
        return 1

    log.info("Data folder: %s", cfg.data_dir)
    log.info("Chat page: %s/", url)
    server = uvicorn.Server(
        uvicorn.Config(app, host=HOST, port=port, log_config=None, ws_ping_interval=20)
    )
    if open_browser:
        threading.Thread(target=open_when_ready, args=(server, f"{url}/"), daemon=True).start()
    server.run()
    return 0


if __name__ == "__main__":
    sys.exit(main())
