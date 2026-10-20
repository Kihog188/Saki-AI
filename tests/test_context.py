from saki.context import build_messages, estimate_tokens


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
