"""Start the Saki backend: python -m saki [--port N] [--data-dir DIR]."""

from __future__ import annotations

import argparse
import logging
import socket
import sys
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


def main(argv: list[str] | None = None) -> int:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")  # Vietnamese on Windows consoles
        except (AttributeError, ValueError):
            pass  # pythonw has no console: sys.stdout is None

    parser = argparse.ArgumentParser(prog="python -m saki", description="Saki backend server")
    parser.add_argument("--port", type=int, help="override the saved/configured port")
    parser.add_argument("--data-dir", type=Path, help="app-data folder (default: %%APPDATA%%\\Saki)")
    parser.add_argument("--log-level", default="INFO", choices=["DEBUG", "INFO", "WARNING", "ERROR"])
    args = parser.parse_args(argv)

    cfg = AppConfig.load(args.data_dir)
    setup_logging(cfg, getattr(logging, args.log_level))
    app = create_app(cfg)
    port = args.port or app.state.saki.settings.get("port")
    url = f"http://{HOST}:{port}"

    if port_in_use(port):
        app.state.saki.storage.close()
        if is_saki_running(url):
            _print(MSG_ALREADY_RUNNING.format(url=url))
            return 0
        _print(MSG_PORT_BUSY.format(port=port), error=True)
        return 1

    log.info("Data folder: %s", cfg.data_dir)
    log.info("Listening on %s", url)
    server = uvicorn.Server(
        uvicorn.Config(app, host=HOST, port=port, log_config=None, ws_ping_interval=20)
    )
    app.state.saki.request_shutdown = lambda: setattr(server, "should_exit", True)
    server.run()
    return 0


def _print(text: str, error: bool = False) -> None:
    """print() that also works under pythonw.exe, where stdout/stderr are None."""
    stream = sys.stderr if error else sys.stdout
    if stream is not None:
        print(text, file=stream)
    (log.error if error else log.info)(text)


if __name__ == "__main__":
    sys.exit(main())
