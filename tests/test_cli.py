from saki.chat import is_near_duplicate
from saki.cli import Printer, render_event


def test_blank_line_between_sources_and_prompt(capsys):
    render_event(
        {
            "type": "end",
            "emotion": "neutral",
            "text": "x",
            "system": False,
            "sources": [
                {
                    "index": 1,
                    "title": "Dự báo thời tiết",
                    "url": "https://news.google.com/rss/articles/abc",
                    "display_url": "laodong.vn",
                    "site": "laodong.vn",
                    "date": "2026-10-20",
                    "paywalled": False,
                }
            ],
        },
        Printer(color=False),
    )
    out = capsys.readouterr().out
    assert out == "\n  [1] Dự báo thời tiết — laodong.vn (2026-10-20)\n\n> "
    assert "news.google.com" not in out


def test_no_extra_blank_line_without_sources(capsys):
    render_event({"type": "end", "emotion": "neutral", "text": "x", "sources": []}, Printer(False))
    assert capsys.readouterr().out == "\n> "


def test_reset_event_is_shown(capsys):
    render_event({"type": "reset"}, Printer(False))
    assert "trả lời lại" in capsys.readouterr().out


def test_is_near_duplicate():
    prev = ["Không có gì. Anh đang làm việc.", "Hôm nay trời đẹp."]
    assert is_near_duplicate("Không có gì, anh đang làm việc!", prev)
    assert is_near_duplicate("Hôm nay trời đẹp.\n\nNguồn: [1] a.vn", prev)
    assert not is_near_duplicate("Em thích mèo.", prev)
    assert not is_near_duplicate("", prev)
    assert not is_near_duplicate("abc", [])
