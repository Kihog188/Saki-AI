from saki.context import build_messages, estimate_tokens, history_for_context


def test_history_for_context_restores_emotion_tags():
    hist = [
        {"role": "user", "content": "Chào", "emotion": None, "kind": "chat"},
        {"role": "assistant", "content": "Chào bạn.", "emotion": "happy", "kind": "chat"},
        {"role": "assistant", "content": "không có thẻ", "emotion": None, "kind": "chat"},
    ]
    out = history_for_context(hist)
    assert out[1] == {"role": "assistant", "content": "[happy] Chào bạn."}
    assert out[2] == {"role": "assistant", "content": "không có thẻ"}


def test_history_for_context_skips_search_turns():
    hist = [
        {"role": "user", "content": "/news vàng", "kind": "search"},
        {"role": "assistant", "content": "Vàng tăng.\n\nNguồn: [1] a.vn", "emotion": "neutral", "kind": "search"},
        {"role": "user", "content": "hi", "kind": "chat"},
        {"role": "assistant", "content": "Ừ.", "emotion": "neutral", "kind": "chat"},
    ]
    out = history_for_context(hist)
    assert [m["content"] for m in out] == ["hi", "[neutral] Ừ."]


def test_history_for_context_keeps_last_three_turns():
    hist = []
    for i in range(6):
        hist.append({"role": "user", "content": f"u{i}", "kind": "chat"})
        hist.append({"role": "assistant", "content": f"a{i}", "emotion": "neutral", "kind": "chat"})
    out = history_for_context(hist, max_turns=3)
    assert [m["content"] for m in out] == ["u3", "[neutral] a3", "u4", "[neutral] a4", "u5", "[neutral] a5"]
    assert history_for_context(hist, max_turns=0) == []


def test_history_without_kind_field_counts_as_chat():
    out = history_for_context([{"role": "user", "content": "x"}])
    assert out == [{"role": "user", "content": "x"}]


def _hist(n, size=30):
    out = []
    for i in range(n):
        out.append({"role": "user", "content": f"u{i} " + "a" * size})
        out.append({"role": "assistant", "content": f"a{i} " + "b" * size})
    return out


def test_all_history_kept_when_small():
    msgs = build_messages("SYS", _hist(3), "hi")
    assert msgs[0] == {"role": "system", "content": "SYS"}
    assert msgs[-1] == {"role": "user", "content": "hi"}
    assert len(msgs) == 2 + 6


def test_history_trimmed_to_budget_keeps_newest():
    hist = _hist(50, size=300)  # ~105 tokens per message
    msgs = build_messages("S" * 900, hist, "câu hỏi", num_ctx=2048, reply_reserve=512)
    total = sum(estimate_tokens(m["content"]) for m in msgs)
    assert total <= 2048 - 512
    assert msgs[-2]["content"].startswith("a49")
    assert msgs[1]["role"] == "user"
    assert 4 <= len(msgs) - 2 <= 12


def test_current_message_always_kept_even_if_huge():
    msgs = build_messages("SYS", _hist(3), "x" * 10000)
    assert msgs == [{"role": "system", "content": "SYS"}, {"role": "user", "content": "x" * 10000}]


def test_kept_history_never_starts_with_assistant():
    hist = [{"role": "assistant", "content": "orphan"}, {"role": "user", "content": "q"},
            {"role": "assistant", "content": "a"}]
    msgs = build_messages("SYS", hist, "now")
    assert [m["role"] for m in msgs] == ["system", "user", "assistant", "user"]
