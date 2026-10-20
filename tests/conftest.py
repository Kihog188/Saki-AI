import pytest

from saki.storage import Storage


@pytest.fixture
def storage(tmp_path):
    s = Storage(tmp_path / "test.db")
    yield s
    s.close()
