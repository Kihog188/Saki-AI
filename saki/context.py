"""Fit system prompt + recent history + current message into the context window."""

from __future__ import annotations

from collections.abc import Sequence

CHARS_PER_TOKEN = 3  # rough estimate for Vietnamese with the Qwen tokenizer
MESSAGE_OVERHEAD_TOKENS = 4  # <|im_start|>role\n ... <|im_end|>\n
MAX_CONTEXT_TURNS = 3


def estimate_tokens(text: str) -> int:
    return -(-len(text) // CHARS_PER_TOKEN) + MESSAGE_OVERHEAD_TOKENS


def history_for_context(history: Sequence[dict], max_turns: int = MAX_CONTEXT_TURNS) -> list[dict]:
    """Turn stored history into model messages.

    - Search turns (kind "search") are left out: they are kept for display only.
    - Assistant replies get their emotion tag back ("[happy] ..."), as in training,
      so the model keeps starting its replies with a tag.
    - At most the last `max_turns` turns (a turn starts with a user message).
    """
    out: list[dict] = []
    for m in history:
        if m.get("kind", "chat") == "search":
            continue
        content = m["content"]
        if m["role"] == "assistant" and m.get("emotion"):
            content = f"[{m['emotion']}] {content}"
        out.append({"role": m["role"], "content": content})
    starts = [i for i, m in enumerate(out) if m["role"] == "user"]
    if max_turns <= 0:
        return []
    if len(starts) > max_turns:
        out = out[starts[-max_turns]:]
    return out


def build_messages(
    system_prompt: str,
    history: Sequence[dict],
    user_message: str,
    num_ctx: int = 2048,
    reply_reserve: int = 512,
) -> list[dict]:
    """System + as many recent history messages as fit + the current user message.

    The system prompt and the current message are always kept. History is added
    from newest to oldest; the kept history never starts with an assistant turn.
    """
    budget = num_ctx - reply_reserve - estimate_tokens(system_prompt) - estimate_tokens(user_message)
    kept: list[dict] = []
    for msg in reversed(history):
        cost = estimate_tokens(msg["content"])
        if cost > budget:
            break
        budget -= cost
        kept.append({"role": msg["role"], "content": msg["content"]})
    kept.reverse()
    while kept and kept[0]["role"] != "user":
        kept.pop(0)
    return [
        {"role": "system", "content": system_prompt},
        *kept,
        {"role": "user", "content": user_message},
    ]
