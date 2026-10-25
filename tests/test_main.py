import logging
import socket

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


def test_saki_already_running_exits_cleanly(busy_port, tmp_path, monkeypatch, capsys):
    monkeypatch.setattr(entry, "is_saki_running", lambda url: True)
    assert entry.main(["--port", str(busy_port), "--data-dir", str(tmp_path)]) == 0
    assert "Saki đang chạy sẵn" in capsys.readouterr().out


def test_removed_config_keys_are_ignored(busy_port, tmp_path, monkeypatch):
    monkeypatch.setattr(entry, "is_saki_running", lambda url: True)
    (tmp_path / "config.json").write_text(
        '{"open_browser": false, "character_pack": "x"}', encoding="utf-8"
    )
    assert entry.main(["--port", str(busy_port), "--data-dir", str(tmp_path)]) == 0


def test_no_browser_flag_is_gone(tmp_path):
    with pytest.raises(SystemExit):
        entry.main(["--no-browser", "--data-dir", str(tmp_path)])
