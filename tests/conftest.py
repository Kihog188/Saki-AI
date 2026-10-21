import webbrowser

import pytest
from fastapi.testclient import TestClient

from saki.config import AppConfig
from saki.llm import FakeBackend
from saki.storage import Storage


@pytest.fixture(autouse=True)
def no_browser(monkeypatch):
    """Tests must never open a real browser."""

    def fail(*args, **kwargs):
        raise AssertionError("a test tried to open a browser")

    monkeypatch.setattr(webbrowser, "open", fail)


@pytest.fixture
def storage(tmp_path):
    s = Storage(tmp_path / "test.db")
    yield s
    s.close()


@pytest.fixture
def web(tmp_path):
    """A TestClient over a temp data dir; yields (client, data_dir)."""
    from saki.server import create_app

    cfg = AppConfig(data_dir=tmp_path)
    store = Storage(tmp_path / "saki.db")
    app = create_app(cfg, llm=FakeBackend(), search=object(), storage=store)
    with TestClient(app) as client:
        yield client, tmp_path
    store.close()
