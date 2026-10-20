import pytest

from saki.commands import HELP_TEXT, CommandHandler, parse_command
from saki.config import AppConfig
from saki.settings import SettingsStore
from saki.storage import MAX_MEMORY_ITEMS, Storage


@pytest.fixture
def handler(storage, tmp_path):
    return CommandHandler(storage, SettingsStore(storage, AppConfig(data_dir=tmp_path)))


def run(handler, text):
    return handler.handle(parse_command(text))


# --- parsing -----------------------------------------------------------------------


@pytest.mark.parametrize(
    "text,name,args",
    [
        ("/se giá vàng", "se", "giá vàng"),
        ("/SE  Giá Vàng  ", "se", "Giá Vàng"),
        ("/News bão số 5", "news", "bão số 5"),
        ("/rmb tên tôi là Minh", "rmb", "tên tôi là Minh"),
        ("/fgt", "fgt", ""),
        ("/fgt 3", "fgt", "3"),
        ("/xh em anh", "xh", "em anh"),
        ("/Clear", "clear", ""),
        ("  /help", "help", ""),
        ("/xyz abc", "xyz", "abc"),
    ],
)
def test_parse_command(text, name, args):
    cmd = parse_command(text)
    assert cmd is not None
    assert (cmd.name, cmd.args) == (name, args)


@pytest.mark.parametrize("text", ["xin chào", "", "/ có dấu cách", "a /se b", "giá 1/2"])
def test_not_a_command(text):
    assert parse_command(text) is None


def test_known_and_search_flags():
    assert parse_command("/se x").is_search
    assert parse_command("/NEWS x").is_search
    assert parse_command("/rmb x").known and not parse_command("/rmb x").is_search
    assert not parse_command("/sex").known


# --- handlers ------------------------------------------------------------------


def test_unknown_command_hint(handler):
    assert run(handler, "/xyz") == "Không có lệnh /xyz. Gõ /help để xem danh sách lệnh."


def test_help(handler):
    out = run(handler, "/HELP")
    assert out == HELP_TEXT
    for name in ("/se", "/news", "/rmb", "/fgt", "/xh", "/clear", "/help"):
        assert name in out


@pytest.mark.parametrize("text", ["/se", "/news   ", "/rmb", "/rmb    "])
def test_empty_args_give_usage(handler, text):
    assert run(handler, text).startswith("Cách dùng:")


def test_rmb_and_fgt_flow(handler, storage):
    assert run(handler, "/rmb Tên tôi là Minh") == "Đã nhớ: Tên tôi là Minh"
    assert run(handler, "/rmb Tên tôi là Minh") == "Đã nhớ từ trước: Tên tôi là Minh"
    run(handler, "/rmb Tôi thích mèo")
    run(handler, "/rmb Tôi thích chó")
    ids = [m.id for m in storage.list_memories()]

    listing = run(handler, "/fgt")
    assert listing.splitlines()[1] == f"{ids[0]}. Tên tôi là Minh"
    assert listing.endswith("Xóa bằng /fgt <số>.")

    many = run(handler, "/fgt thích")
    assert many.startswith("Có 2 ghi nhớ khớp:")
    assert len(storage.list_memories()) == 3

    assert run(handler, "/fgt meo") == "Đã quên: Tôi thích mèo"
    assert run(handler, f"/fgt {ids[0]}") == "Đã quên: Tên tôi là Minh"
    assert run(handler, f"/fgt {ids[0]}") == f"Không tìm thấy ghi nhớ số {ids[0]}."
    assert run(handler, "/fgt không có") == "Không có ghi nhớ nào chứa “không có”."
    assert [m.text for m in storage.list_memories()] == ["Tôi thích chó"]


def test_fgt_empty_list(handler):
    assert run(handler, "/fgt") == "Chưa có ghi nhớ nào."


def test_rmb_limits(handler):
    assert run(handler, "/rmb " + "x" * 201) == "Ghi nhớ quá dài (tối đa 200 ký tự)."
    for i in range(MAX_MEMORY_ITEMS):
        run(handler, f"/rmb mục {i}")
    assert run(handler, "/rmb thêm").startswith("Bộ nhớ đã đầy")


def test_xh_persists(tmp_path):
    db = tmp_path / "x.db"
    cfg = AppConfig(data_dir=tmp_path)
    s = Storage(db)
    h = CommandHandler(s, SettingsStore(s, cfg))
    assert run(h, "/xh").startswith("Đang xưng hô: tự xưng “Saki”, gọi người dùng là “bạn”.")
    assert run(h, "/xh em anh") == "Đã đổi xưng hô: tự xưng “em”, gọi người dùng là “anh”."
    assert run(h, "/xh em").startswith("Cách dùng:")
    assert run(h, "/xh a b c").startswith("Cách dùng:")
    s.close()

    s2 = Storage(db)
    settings = SettingsStore(s2, cfg).get_all()
    assert (settings["self_name"], settings["user_name"]) == ("em", "anh")
    s2.close()


def test_xh_rejects_bad_names(handler):
    assert run(handler, "/xh " + "a" * 21 + " anh").startswith("Cách xưng hô quá dài")
    assert run(handler, '/xh "em" anh') == "Cách xưng hô chứa ký tự không hợp lệ."


def test_clear(handler, storage):
    storage.add_message("user", "hi")
    storage.add_memory("giữ lại")
    assert run(handler, "/clear") == "Đã xóa lịch sử trò chuyện."
    assert storage.get_history() == []
    assert len(storage.list_memories()) == 1
