"""Start the Saki backend: python -m saki [--port N] [--data-dir DIR]."""

from __future__ import annotations

import argparse
import logging
import sys
from pathlib import Path

import uvicorn

from .config import HOST, AppConfig, setup_logging
from .server import create_app


def main(argv: list[str] | None = None) -> None:
    for stream in (sys.stdout, sys.stderr):
        try:
            stream.reconfigure(encoding="utf-8", errors="replace")  # Vietnamese on Windows consoles
        except (AttributeError, ValueError):
            pass

    parser = argparse.ArgumentParser(prog="python -m saki", description="Saki backend server")
    parser.add_argument("--port", type=int, help="override the saved/configured port")
    parser.add_argument("--data-dir", type=Path, help="app-data folder (default: %%APPDATA%%\\Saki)")
    parser.add_argument("--log-level", default="INFO", choices=["DEBUG", "INFO", "WARNING", "ERROR"])
    args = parser.parse_args(argv)

    cfg = AppConfig.load(args.data_dir)
    setup_logging(cfg, getattr(logging, args.log_level))
    app = create_app(cfg)
    port = args.port or app.state.saki.settings.get("port")
    logging.getLogger("saki").info("Data folder: %s", cfg.data_dir)
    uvicorn.run(app, host=HOST, port=port, log_config=None, ws_ping_interval=20)


if __name__ == "__main__":
    main()
