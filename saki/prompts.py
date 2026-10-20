"""Prompt builders. The formats here MUST match the fine-tuning data exactly."""

from __future__ import annotations

from collections.abc import Sequence
from datetime import date

from .search.models import SearchResult, strip_html, truncate_words

# Copied character-for-character from the training data. Only the two placeholders
# may change. Do not translate, reformat or "improve" this string.
SYSTEM_PROMPT_TEMPLATE = (
    "Bạn là Saki, trợ lý AI. Tính cách: kuudere — điềm tĩnh, ít nói, trả lời ngắn gọn "
    "và chính xác, ít bộc lộ cảm xúc nhưng thật lòng quan tâm người dùng. Saki tự xưng "
    'là "{self_name}", gọi người dùng là "{user_name}". Luôn mở đầu bằng đúng một thẻ '
    "cảm xúc: [neutral] [happy] [sad] [thinking] [surprised] [embarrassed]. Khi có "
    "KẾT QUẢ TÌM KIẾM: chỉ dùng thông tin trong đó, nêu ngày, ghi nguồn dạng [1]. "
    "Không chắc thì nói thẳng, không bịa."
)

MEMORY_PREFIX = "[BỘ NHỚ] "
MEMORY_SEPARATOR = "; "
MEMORY_BLOCK_MAX_CHARS = 400

TODAY_LINE = "[HÔM NAY: {today}]"
RESULTS_HEADER = "[KẾT QUẢ TÌM KIẾM]"
NO_RESULTS = "(không có kết quả)"
UNKNOWN_DATE = "không rõ ngày"
SNIPPET_MAX_CHARS = 300


def render_memory_block(memories: Sequence[str], max_chars: int = MEMORY_BLOCK_MAX_CHARS) -> str:
    """'[BỘ NHỚ] a; b; c', dropping the oldest items until it fits in `max_chars`.

    `memories` is ordered oldest first. Returns "" when there is nothing to show.
    """
    items = [" ".join(m.split()) for m in memories if m and m.strip()]
    while items:
        block = MEMORY_PREFIX + MEMORY_SEPARATOR.join(items)
        if len(block) <= max_chars:
            return block
        items.pop(0)
    return ""


def render_system_prompt(
    self_name: str = "Saki", user_name: str = "bạn", memories: Sequence[str] = ()
) -> str:
    prompt = SYSTEM_PROMPT_TEMPLATE.format(self_name=self_name, user_name=user_name)
    block = render_memory_block(memories)
    if block:
        prompt += "\n" + block
    return prompt


def _one_line(text: str) -> str:
    return " ".join(text.split())


def select_results(results: Sequence[SearchResult], limit: int = 4) -> list[SearchResult]:
    """Newest first (unknown dates last, stable otherwise), capped at `limit`."""
    dated = sorted((r for r in results if r.date), key=lambda r: r.date, reverse=True)
    undated = [r for r in results if not r.date]
    return (dated + undated)[:limit]


def format_result_date(d: date | None) -> str:
    return d.isoformat() if d else UNKNOWN_DATE


def build_search_message(command_text: str, results: Sequence[SearchResult], today: date) -> str:
    """The single user message sent to the model for /se and /news turns.

    `results` must already be selected (see `select_results`); they are numbered
    in the given order so that the sources line matches.
    """
    lines = [command_text.strip(), "", TODAY_LINE.format(today=today.isoformat()), RESULTS_HEADER]
    if not results:
        lines.append(NO_RESULTS)
    for i, r in enumerate(results, start=1):
        lines.append(f"[{i}] {_one_line(r.title)} | {r.site} | {format_result_date(r.date)}")
        # The training data always has a snippet line; fall back to the title.
        snippet = truncate_words(strip_html(r.snippet), SNIPPET_MAX_CHARS) or _one_line(r.title)
        lines.append(snippet)
    return "\n".join(lines)
