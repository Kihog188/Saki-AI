from datetime import date

import pytest

from saki.postprocess import (
    EmotionStreamParser,
    ReplyStream,
    StreamCleaner,
    build_sources_line,
    clean_reply,
    finalize_search_reply,
    parse_emotion,
    rewrite_commands,
    sources_payload,
    strip_cjk,
    strip_model_sources,
    strip_special_tokens,
)
from saki.search.models import SearchResult


def stream(chunks, strip_sources=False):
    rs = ReplyStream(strip_sources=strip_sources)
    deltas = [rs.feed(c) for c in chunks]
    deltas.append(rs.finish())
    return rs, deltas


# --- emotion tag ---------------------------------------------------------------


@pytest.mark.parametrize(
    "text,emotion,rest",
    [
        ("[happy] Chào bạn.", "happy", "Chào bạn."),
        ("  [Thinking]Để Saki xem.", "thinking", "Để Saki xem."),
        ("[embarrassed]\nỪm...", "embarrassed", "Ừm..."),
        ("Chào bạn.", "neutral", "Chào bạn."),
        ("[angry] Hừ.", "neutral", "Hừ."),
        ("[1] là nguồn.", "neutral", "[1] là nguồn."),
        ("Xin chào [happy] bạn", "neutral", "Xin chào [happy] bạn"),
        ("", "neutral", ""),
    ],
)
def test_parse_emotion(text, emotion, rest):
    assert parse_emotion(text) == (emotion, rest)


def test_stream_tag_split_across_chunks():
    rs, deltas = stream(["[ha", "ppy", "] Ch", "ào bạn", "."])
    assert rs.emotion == "happy"
    assert deltas[0] == deltas[1] == ""
    assert rs.final_text() == "Chào bạn."


def test_stream_tag_then_space_in_next_chunk():
    rs, _ = stream(["[sad]", " ", "Tiếc quá."])
    assert rs.emotion == "sad"
    assert rs.final_text() == "Tiếc quá."


def test_stream_no_tag_resolves_immediately():
    p = EmotionStreamParser()
    assert p.feed("Chào") == "Chào"
    assert p.emotion == "neutral"


def test_stream_tag_in_middle_is_kept_as_text():
    rs, _ = stream(["Xin chào ", "[happy] bạn"])
    assert rs.emotion == "neutral"
    assert rs.final_text() == "Xin chào [happy] bạn"


def test_stream_bracket_without_close_gives_up_after_window():
    p = EmotionStreamParser()
    assert p.feed("[đây là một câu rất dài") != ""
    assert p.emotion == "neutral"


def test_stream_unclosed_short_tag_flushed_at_finish():
    rs, _ = stream(["[hap"])
    assert rs.emotion == "neutral"
    assert rs.final_text() == "[hap"


def test_stream_only_whitespace_then_tag():
    rs, _ = stream(["\n ", " [surprised", "] Ồ!"])
    assert rs.emotion == "surprised"
    assert rs.final_text() == "Ồ!"


# --- cleanup -----------------------------------------------------------------------


def test_strip_cjk():
    assert strip_cjk("Hôm nay trời 很 đẹp.") == "Hôm nay trời đẹp."
    assert strip_cjk("Xong rồi，bạn nhé。") == "Xong rồi bạn nhé"
    assert strip_cjk("Không có gì") == "Không có gì"
    assert strip_cjk("一二三") == ""
    assert strip_cjk("trời 很 ") == "trời "


def test_strip_special_tokens():
    assert strip_special_tokens("Xong.<|im_end|>") == "Xong."
    assert strip_special_tokens("<|im_start|>assistant\nHi") == "assistant\nHi"
    assert strip_special_tokens("Xong.<|im_", final=True) == "Xong."


def test_rewrite_commands():
    assert rewrite_commands("Gõ /nho tên tôi là Minh.") == "Gõ /rmb tên tôi là Minh."
    assert rewrite_commands("Dùng /quen 2 hoặc /NHO.") == "Dùng /fgt 2 hoặc /rmb."
    assert rewrite_commands("xem a.com/nho và /nhom") == "xem a.com/nho và /nhom"


def test_stream_command_rewrite_split_across_chunks():
    rs, _ = stream(["[neutral] Gõ /n", "ho tên", " nhé."])
    assert rs.final_text() == "Gõ /rmb tên nhé."
    assert "/nho" not in "".join(rs.text)


def test_stream_special_token_split_across_chunks():
    rs, deltas = stream(["[happy] Xong", "<|im_", "end|>"])
    assert rs.final_text() == "Xong"
    assert all("<|" not in d for d in deltas)


def test_stream_cjk_removed():
    rs, _ = stream(["[neutral] Trời ", "很 ", "đẹp."])
    assert rs.final_text() == "Trời đẹp."


# --- sources -------------------------------------------------------------------


def _results():
    return [
        SearchResult("A", "https://vnexpress.net/a", "vnexpress.net", date(2026, 10, 19), "s"),
        SearchResult("B", "https://tuoitre.vn/b", "tuoitre.vn", date(2026, 10, 18), "s"),
        SearchResult("C", "https://x.vn/c", "x.vn", None, "s", paywalled=True),
    ]


def test_build_sources_line_exact():
    assert build_sources_line(_results()[:2]) == (
        "Nguồn: [1] vnexpress.net (19/10/2026), [2] tuoitre.vn (18/10/2026)"
    )
    assert build_sources_line(_results()).endswith(", [3] x.vn (không rõ ngày)")
    assert build_sources_line([]) == ""


def test_sources_payload():
    p = sources_payload(_results())
    assert p[0] == {
        "index": 1,
        "title": "A",
        "url": "https://vnexpress.net/a",
        "display_url": "https://vnexpress.net/a",
        "site": "vnexpress.net",
        "date": "2026-10-19",
        "paywalled": False,
    }
    assert p[2]["date"] is None and p[2]["paywalled"] is True


def test_sources_payload_shows_publisher_for_google_news():
    r = SearchResult(
        "T", "https://news.google.com/rss/articles/CBMi123?oc=5", "thanhnien.vn", date(2026, 10, 20)
    )
    (p,) = sources_payload([r])
    assert p["display_url"] == "thanhnien.vn"
    assert p["url"].startswith("https://news.google.com/")  # still clickable


@pytest.mark.parametrize(
    "text,expected",
    [
        ("Vàng tăng [1].\n\nNguồn: [1] abc.vn", "Vàng tăng [1]."),
        ("Vàng tăng.\nNguồn: [1] a\n[2] b", "Vàng tăng."),
        ("Vàng tăng.\n**Nguồn:** [1] a", "Vàng tăng."),
        ("Vàng tăng.\n- nguồn : a", "Vàng tăng."),
        ("Nguồn tin chưa rõ.\nVàng tăng.", "Nguồn tin chưa rõ.\nVàng tăng."),
        ("Không có nguồn.", "Không có nguồn."),
    ],
)
def test_strip_model_sources(text, expected):
    assert strip_model_sources(text) == expected


def test_finalize_search_reply():
    out = finalize_search_reply("Vàng tăng [1].\nNguồn: [1] sai.vn", _results()[:1])
    assert out == "Vàng tăng [1].\n\nNguồn: [1] vnexpress.net (19/10/2026)"
    assert finalize_search_reply("Không có kết quả.", []) == "Không có kết quả."


def test_stream_suppresses_model_sources_line():
    rs, deltas = stream(
        ["[thinking] Vàng tăng [1].", "\n\nNg", "uồn: [1] ", "abc.vn (19/10/2026)"],
        strip_sources=True,
    )
    assert rs.emotion == "thinking"
    assert rs.final_text() == "Vàng tăng [1]."
    assert "Ng" not in "".join(deltas)


def test_stream_line_starting_with_ng_is_released():
    rs, _ = stream(["[neutral] A.\nNg", "ày mai mưa."], strip_sources=True)
    assert rs.final_text() == "A.\nNgày mai mưa."


def test_stream_cleaner_releases_at_whitespace():
    c = StreamCleaner()
    assert c.feed("Xin chà") == "Xin "
    assert c.feed("o bạn") == "chào "
    assert c.finish() == "bạn"


def test_clean_reply_full_pipeline():
    emotion, text = clean_reply("[happy] Gõ /nho 很 tên nhé.<|im_end|>")
    assert emotion == "happy"
    assert text == "Gõ /rmb tên nhé."
