import pytest

from saki.storage import MAX_MEMORY_ITEMS, MemoryLimitError, Storage


def test_settings_roundtrip_and_persistence(tmp_path):
    path = tmp_path / "s.db"
    s = Storage(path)
    assert s.get_setting("self_name") is None
    s.set_setting("self_name", "em")
    s.set_setting("self_name", "tớ")
    s.close()
    s2 = Storage(path)
    assert s2.get_setting("self_name") == "tớ"
    assert s2.all_settings() == {"self_name": "tớ"}
    s2.close()


def test_history_order_limit_and_clear(storage):
    for i in range(5):
        storage.add_message("user", f"u{i}")
    hist = storage.get_history(limit=3)
    assert [m["content"] for m in hist] == ["u2", "u3", "u4"]
    storage.clear_history()
    assert storage.get_history() == []


def test_history_pages_backwards_by_id(storage):
    for i in range(7):
        storage.add_message("user", f"u{i}")
    newest = storage.get_history(limit=3)
    assert [m["content"] for m in newest] == ["u4", "u5", "u6"]
    older = storage.get_history(limit=3, before_id=newest[0]["id"])
    assert [m["content"] for m in older] == ["u1", "u2", "u3"]
    oldest = storage.get_history(limit=3, before_id=older[0]["id"])
    assert [m["content"] for m in oldest] == ["u0"]
    assert storage.get_history(limit=3, before_id=oldest[0]["id"]) == []


def test_history_stores_emotion_and_kind(storage):
    storage.add_message("user", "/news x", kind="search")
    storage.add_message("assistant", "Tin.", emotion="thinking", kind="search")
    storage.add_message("user", "hi")
    storage.add_message("assistant", "Chào.", emotion="happy")
    h = storage.get_history()
    assert [(m["role"], m["emotion"], m["kind"]) for m in h] == [
        ("user", None, "search"),
        ("assistant", "thinking", "search"),
        ("user", None, "chat"),
        ("assistant", "happy", "chat"),
    ]


def test_migrates_old_messages_table(tmp_path):
    import sqlite3

    path = tmp_path / "old.db"
    conn = sqlite3.connect(path)
    conn.execute(
        "CREATE TABLE messages (id INTEGER PRIMARY KEY AUTOINCREMENT, role TEXT NOT NULL, "
        "content TEXT NOT NULL, created_at REAL NOT NULL)"
    )
    conn.execute("INSERT INTO messages(role, content, created_at) VALUES('user', 'cũ', 0)")
    conn.commit()
    conn.close()
    s = Storage(path)
    s.add_message("assistant", "mới", emotion="happy")
    h = s.get_history()
    assert h[0]["content"] == "cũ" and h[0]["kind"] == "chat" and h[0]["emotion"] is None
    assert h[1]["emotion"] == "happy"
    s.close()


def test_memory_crud(storage):
    m1 = storage.add_memory("  Tên tôi   là Minh ")
    assert m1.text == "Tên tôi là Minh"
    m2 = storage.add_memory("Tôi thích mèo")
    assert [m.id for m in storage.list_memories()] == [m1.id, m2.id]
    # Duplicate returns the existing item, no new row.
    assert storage.add_memory("Tôi thích mèo").id == m2.id
    assert len(storage.list_memories()) == 2
    assert storage.get_memory(m1.id).text == "Tên tôi là Minh"
    assert storage.delete_memory(m1.id) is True
    assert storage.delete_memory(m1.id) is False
    assert [m.text for m in storage.list_memories()] == ["Tôi thích mèo"]


def test_memory_find_is_accent_insensitive(storage):
    storage.add_memory("Tôi thích mèo")
    storage.add_memory("Sinh nhật ngày 5/3")
    assert [m.text for m in storage.find_memories("MEO")] == ["Tôi thích mèo"]
    assert [m.text for m in storage.find_memories("thích")] == ["Tôi thích mèo"]
    assert storage.find_memories("   ") == []


@pytest.mark.parametrize(
    "text,reason", [("", "empty"), ("   ", "empty"), ("x" * 201, "too_long")]
)
def test_memory_rejects_bad_text(storage, text, reason):
    with pytest.raises(MemoryLimitError) as exc:
        storage.add_memory(text)
    assert exc.value.reason == reason


def test_memory_accepts_exactly_200_chars(storage):
    assert len(storage.add_memory("y" * 200).text) == 200


def test_memory_item_limit(storage):
    for i in range(MAX_MEMORY_ITEMS):
        storage.add_memory(f"item {i}")
    with pytest.raises(MemoryLimitError) as exc:
        storage.add_memory("one too many")
    assert exc.value.reason == "full"
