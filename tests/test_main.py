import logging
import socket
import webbrowser

import pytest

from saki import __main__ as entry


@pytest.fixture(autouse=True)
def drop_log_handlers():
    yield
    root = logging.getLogger()
    for h in list(root.handlers):
        if getattr(h, "_saki", False):
            root.removeHandler(h)
            h.close()


class FakeServer:
    def __init__(self, start_after=0, exit_after=None):
        self.polls = 0
        self.start_after = start_after
        self.exit_after = exit_after

    @property
    def started(self):
        self.polls += 1
        return self.polls > self.start_after

    @property
    def should_exit(self):
        return self.exit_after is not None and self.polls >= self.exit_after


def test_browser_opens_only_after_server_started():
    opened = []
    server = FakeServer(start_after=3)
    assert entry.open_when_ready(server, "http://x/", opener=opened.append, interval=0) is True
    assert opened == ["http://x/"] and server.polls == 4


def test_browser_not_opened_when_server_exits_first():
    opened = []
    server = FakeServer(start_after=10**9, exit_after=2)
    assert entry.open_when_ready(server, "http://x/", opener=opened.append, interval=0) is False
    assert opened == []


@pytest.fixture
def busy_port():
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        sock.bind(("127.0.0.1", 0))
        sock.listen()
        yield sock.getsockname()[1]


def test_port_used_by_another_app_gives_clear_message(busy_port, tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(entry, "is_saki_running", lambda url: False)
    assert entry.port_in_use(busy_port)
    assert entry.main(["--port", str(busy_port), "--data-dir", str(tmp_path)]) == 1
    assert f"Cổng {busy_port} đang bị một ứng dụng khác sử dụng" in capsys.readouterr().err


def test_saki_already_running_opens_existing_instance(busy_port, tmp_path, monkeypatch, capsys):
    opened = []
    monkeypatch.setattr(entry, "is_saki_running", lambda url: True)
    monkeypatch.setattr(webbrowser, "open", opened.append)
    assert entry.main(["--port", str(busy_port), "--data-dir", str(tmp_path)]) == 0
    assert opened == [f"http://127.0.0.1:{busy_port}/"]
    assert "Saki đang chạy sẵn" in capsys.readouterr().out


def test_no_browser_flag_and_config_key(busy_port, tmp_path, monkeypatch):
    monkeypatch.setattr(entry, "is_saki_running", lambda url: True)
    # The autouse fixture fails the test if anything opens a browser.
    assert entry.main(["--port", str(busy_port), "--data-dir", str(tmp_path), "--no-browser"]) == 0
    (tmp_path / "config.json").write_text('{"open_browser": false}', encoding="utf-8")
    assert entry.main(["--port", str(busy_port), "--data-dir", str(tmp_path)]) == 0
