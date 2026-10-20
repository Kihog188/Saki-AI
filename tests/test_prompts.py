from datetime import date

from saki.prompts import (
    build_search_message,
    render_memory_block,
    render_system_prompt,
    select_results,
)
from saki.search.models import SearchResult, strip_html, truncate_words

# Written out literally on purpose: this must equal the fine-tuning system prompt.
EXPECTED_DEFAULT = (
    'Bạn là Saki, trợ lý AI. Tính cách: kuudere — điềm tĩnh, ít nói, trả lời ngắn gọn và chính xác, '
    'ít bộc lộ cảm xúc nhưng thật lòng quan tâm người dùng. Saki tự xưng là "Saki", gọi người dùng '
    'là "bạn". Luôn mở đầu bằng đúng một thẻ cảm xúc: [neutral] [happy] [sad] [thinking] [surprised] '
    '[embarrassed]. Khi có KẾT QUẢ TÌM KIẾM: chỉ dùng thông tin trong đó, nêu ngày, ghi nguồn dạng [1]. '
    "Không chắc thì nói thẳng, không bịa."
)


def test_system_prompt_default_exact():
    assert render_system_prompt() == EXPECTED_DEFAULT
    assert render_system_prompt("Saki", "bạn", []) == EXPECTED_DEFAULT


def test_system_prompt_matches_modelfile_and_training_data():
    # Same text as the SYSTEM block of the Modelfile used to build the `saki` model.
    assert "\n" not in EXPECTED_DEFAULT
    assert len(EXPECTED_DEFAULT) == len(render_system_prompt())


def test_system_prompt_other_pair():
    p = render_system_prompt("em", "anh")
    assert 'Saki tự xưng là "em", gọi người dùng là "anh".' in p
    assert p == EXPECTED_DEFAULT.replace('"Saki", gọi', '"em", gọi').replace('"bạn"', '"anh"')


def test_system_prompt_with_memories_exact():
    p = render_system_prompt("Saki", "bạn", ["Tên tôi là Minh", "Tôi thích mèo"])
    assert p == EXPECTED_DEFAULT + "\n[BỘ NHỚ] Tên tôi là Minh; Tôi thích mèo"


def test_memory_block_drops_oldest_to_fit():
    mems = [f"memory number {i} " + "x" * 80 for i in range(10)]
    block = render_memory_block(mems)
    assert len(block) <= 400
    assert block.startswith("[BỘ NHỚ] ")
    assert block.endswith(mems[-1])
    assert mems[0] not in block


def test_memory_block_empty():
    assert render_memory_block([]) == ""
    assert render_memory_block(["  "]) == ""


def _r(title, site, d, snippet="Tóm tắt.", url=None):
    return SearchResult(title=title, url=url or f"https://{site}/a", site=site, date=d, snippet=snippet)


def test_search_message_exact():
    results = select_results(
        [
            _r("Giá vàng giảm", "tuoitre.vn", date(2026, 10, 18), "SJC giảm 300 nghìn."),
            _r("Giá vàng hôm nay", "vnexpress.net", date(2026, 10, 19), "<b>SJC</b> tăng &amp; nhẫn giảm."),
        ]
    )
    msg = build_search_message("/news giá vàng hôm nay", results, date(2026, 10, 19))
    assert msg == (
        "/news giá vàng hôm nay\n"
        "\n"
        "[HÔM NAY: 2026-10-19]\n"
        "[KẾT QUẢ TÌM KIẾM]\n"
        "[1] Giá vàng hôm nay | vnexpress.net | 2026-10-19\n"
        "SJC tăng & nhẫn giảm.\n"
        "[2] Giá vàng giảm | tuoitre.vn | 2026-10-18\n"
        "SJC giảm 300 nghìn."
    )


def test_search_message_no_results_exact():
    msg = build_search_message("/se thời tiết Huế", [], date(2026, 10, 19))
    assert msg == "/se thời tiết Huế\n\n[HÔM NAY: 2026-10-19]\n[KẾT QUẢ TÌM KIẾM]\n(không có kết quả)"


def test_search_message_unknown_date():
    msg = build_search_message("/se x", [_r("T", "a.vn", None, "S")], date(2026, 10, 19))
    assert msg.endswith("[1] T | a.vn | không rõ ngày\nS")


def test_select_results_sorting_and_limit():
    items = [
        _r("undated1", "a.vn", None),
        _r("old", "b.vn", date(2026, 1, 1)),
        _r("new", "c.vn", date(2026, 10, 19)),
        _r("undated2", "d.vn", None),
        _r("mid", "e.vn", date(2026, 5, 5)),
    ]
    assert [r.title for r in select_results(items)] == ["new", "mid", "old", "undated1"]
    assert [r.title for r in select_results(items, limit=2)] == ["new", "mid"]


def test_snippet_truncation_at_word_boundary():
    long = " ".join(["từ"] * 200)  # 599 chars
    msg = build_search_message("/se x", [_r("T", "a.vn", None, long)], date(2026, 10, 19))
    snippet = msg.split("\n")[-1]
    assert len(snippet) <= 300
    assert snippet.endswith("từ…")


def test_truncate_words_and_strip_html():
    assert truncate_words("short", 300) == "short"
    assert truncate_words("aaaa bbbb cccc", 10) == "aaaa bbbb…"
    assert strip_html("<p>Xin&nbsp;chào <a href='x'>bạn</a></p>\n\n") == "Xin chào bạn"


def test_title_newlines_are_flattened():
    msg = build_search_message("/se x", [_r("Dòng 1\nDòng 2", "a.vn", None, "")], date(2026, 10, 19))
    assert msg.endswith("[1] Dòng 1 Dòng 2 | a.vn | không rõ ngày\nDòng 1 Dòng 2")
