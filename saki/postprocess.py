"""Post-processing of model output: emotion tag, cleanup, rewrites, sources.

Every step is a small pure function; `ReplyStream` chains them for streaming.
"""

from __future__ import annotations

import re
import unicodedata
from collections.abc import Sequence

from .search.models import SearchResult, is_redirect_link

EMOTIONS = ("neutral", "happy", "sad", "thinking", "surprised", "embarrassed")
DEFAULT_EMOTION = "neutral"
TAG_WINDOW = 20  # the closing "]" must appear within this many characters

SOURCES_PREFIX = "Nguồn:"

# --- emotion tag ---------------------------------------------------------------

_TAG_RE = re.compile(r"\s*\[([^\[\]\n]{0,18})\]")
_WORD_TAG_RE = re.compile(r"[a-z_]+")


def parse_emotion(text: str) -> tuple[str, str]:
    """Split a leading emotion tag off a complete reply.

    Returns (emotion, rest). Missing tag -> neutral, text unchanged. An unknown
    word tag such as "[angry]" is removed and mapped to neutral.
    """
    m = _TAG_RE.match(text)
    if m and len(m.group(0).lstrip()) <= TAG_WINDOW:
        tag = m.group(1).strip().lower()
        if tag in EMOTIONS:
            return tag, text[m.end():].lstrip()
        if _WORD_TAG_RE.fullmatch(tag):
            return DEFAULT_EMOTION, text[m.end():].lstrip()
    return DEFAULT_EMOTION, text.lstrip()


class EmotionStreamParser:
    """Buffers the first characters of a stream until the emotion tag is resolved."""

    def __init__(self) -> None:
        self._buf = ""
        self.emotion: str | None = None
        self._strip_leading = True

    @property
    def resolved(self) -> bool:
        return self.emotion is not None

    def _emit(self, text: str) -> str:
        if self._strip_leading:
            text = text.lstrip()
            if text:
                self._strip_leading = False
        return text

    def _resolve(self) -> str:
        self.emotion, rest = parse_emotion(self._buf)
        self._buf = ""
        return self._emit(rest)

    def feed(self, chunk: str) -> str:
        """Return text that can be shown now ("" while still buffering)."""
        if self.resolved:
            return self._emit(chunk)
        self._buf += chunk
        head = self._buf.lstrip()
        if not head:
            return ""
        if not head.startswith("[") or "]" in head or len(head) >= TAG_WINDOW or "\n" in head:
            return self._resolve()
        return ""

    def finish(self) -> str:
        return "" if self.resolved else self._resolve()


# --- text cleanup --------------------------------------------------------------

_SPECIAL_TOKEN_RE = re.compile(r"<\|[A-Za-z0-9_]+\|>")
_PARTIAL_TOKEN_TAIL_RE = re.compile(r"<\|[A-Za-z0-9_]*\|?$")
_CJK_RE = re.compile(
    "[　-〿"  # CJK symbols and punctuation
    "㐀-䶿"  # CJK Extension A
    "一-鿿"  # CJK Unified Ideographs
    "豈-﫿"  # CJK Compatibility Ideographs
    "＀-￯"  # half/full-width forms (，。！ etc.)
    "]+"
)
_MULTI_SPACE_RE = re.compile(r"[ \t]{2,}")
_SPACE_BEFORE_PUNCT_RE = re.compile(r"[ \t]+([,.!?;:…)])")
_COMMAND_REWRITES = (
    (re.compile(r"(?<![\w/])/nho\b", re.IGNORECASE), "/rmb"),
    (re.compile(r"(?<![\w/])/quen\b", re.IGNORECASE), "/fgt"),
)


def strip_special_tokens(text: str, final: bool = False) -> str:
    """Remove leaked chat-template tokens such as <|im_end|>."""
    text = _SPECIAL_TOKEN_RE.sub("", text)
    if final:
        text = _PARTIAL_TOKEN_TAIL_RE.sub("", text)
    return text


def strip_cjk(text: str) -> str:
    """Remove Chinese/Japanese characters that Qwen sometimes leaks, then tidy spaces."""
    cleaned = _CJK_RE.sub(" ", text)
    if cleaned == text:
        return text
    cleaned = _MULTI_SPACE_RE.sub(" ", cleaned)
    cleaned = _SPACE_BEFORE_PUNCT_RE.sub(r"\1", cleaned)
    # Do not introduce leading/trailing spaces the original text did not have.
    if not text[:1].isspace():
        cleaned = cleaned.lstrip(" ")
    if not text[-1:].isspace():
        cleaned = cleaned.rstrip(" ")
    return cleaned


def rewrite_commands(text: str) -> str:
    """The model was trained with /nho and /quen; the commands are now /rmb and /fgt."""
    for pattern, replacement in _COMMAND_REWRITES:
        text = pattern.sub(replacement, text)
    return text


def clean_text(text: str, final: bool = False) -> str:
    return rewrite_commands(strip_cjk(strip_special_tokens(text, final=final)))


# --- sources -------------------------------------------------------------------

_LINE_DECOR = " \t*_>#-•"
_SOURCES_LINE_RE = re.compile(r"nguồn\s*:", re.IGNORECASE)
_SOURCES_PARTIAL_RE = re.compile(r"n(g(u(ồ(n\s*)?)?)?)?", re.IGNORECASE)


def _is_sources_line(line: str) -> bool:
    head = unicodedata.normalize("NFC", line).lstrip(_LINE_DECOR)
    return bool(_SOURCES_LINE_RE.match(head))


def _may_become_sources_line(line: str) -> bool:
    head = unicodedata.normalize("NFC", line).lstrip(_LINE_DECOR)
    return head == "" or bool(_SOURCES_PARTIAL_RE.fullmatch(head))


def strip_model_sources(text: str) -> str:
    """Drop the first line starting with 'Nguồn:' and everything after it."""
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if _is_sources_line(line):
            return "\n".join(lines[:i]).rstrip()
    return text.rstrip()


def format_source_date(r: SearchResult) -> str:
    return r.date.strftime("%d/%m/%Y") if r.date else "không rõ ngày"


def build_sources_line(results: Sequence[SearchResult]) -> str:
    """'Nguồn: [1] vnexpress.net (19/10/2026), [2] ...' or '' when there are no results."""
    if not results:
        return ""
    parts = [f"[{i}] {r.site} ({format_source_date(r)})" for i, r in enumerate(results, start=1)]
    return f"{SOURCES_PREFIX} " + ", ".join(parts)


def sources_payload(results: Sequence[SearchResult]) -> list[dict]:
    return [
        {
            "index": i,
            "title": r.title,
            "url": r.url,
            # What to show the user: the publisher's domain for Google News redirects.
            "display_url": r.site if is_redirect_link(r.url) else r.url,
            "site": r.site,
            "date": r.date.isoformat() if r.date else None,
            "paywalled": r.paywalled,
        }
        for i, r in enumerate(results, start=1)
    ]


def finalize_search_reply(text: str, results: Sequence[SearchResult]) -> str:
    """Replace any model-written sources with the backend's own sources line."""
    body = strip_model_sources(text)
    line = build_sources_line(results)
    if not line:
        return body
    return f"{body}\n\n{line}" if body else line


# --- streaming -----------------------------------------------------------------


class StreamCleaner:
    """Applies `clean_text` to a stream without breaking tokens across chunks.

    Text is released at whitespace boundaries, so special tokens and command
    words are never split. With `strip_sources`, a line starting with 'Nguồn:'
    stops the stream (the backend appends its own sources line).
    """

    def __init__(self, strip_sources: bool = False) -> None:
        self.strip_sources = strip_sources
        self._pending = ""
        self._at_line_start = True
        self._stopped = False
        self._last_char = ""

    def feed(self, chunk: str) -> str:
        if self._stopped or not chunk:
            return ""
        self._pending += chunk
        return self._drain(final=False)

    def finish(self) -> str:
        if self._stopped:
            return ""
        return self._drain(final=True)

    def _drain(self, final: bool) -> str:
        out: list[str] = []
        while self._pending and not self._stopped:
            if self.strip_sources and self._at_line_start:
                line = self._pending.split("\n", 1)[0]
                if _is_sources_line(line):
                    self._stopped = True
                    self._pending = ""
                    break
                if not final and "\n" not in self._pending and _may_become_sources_line(line):
                    break
            nl = self._pending.find("\n")
            if nl != -1:
                seg, self._pending = self._pending[: nl + 1], self._pending[nl + 1 :]
                self._at_line_start = True
            elif final:
                seg, self._pending = self._pending, ""
                self._at_line_start = False
            else:
                ws = max(self._pending.rfind(" "), self._pending.rfind("\t"))
                if ws == -1:
                    break
                seg, self._pending = self._pending[: ws + 1], self._pending[ws + 1 :]
                self._at_line_start = False
            out.append(self._clean(seg, final and not self._pending))
        return "".join(out)

    def _clean(self, seg: str, final: bool) -> str:
        cleaned = clean_text(seg, final=final)
        # Removing CJK at a segment start can leave a double space across segments.
        if cleaned != seg and self._last_char in ("", " ", "\t", "\n"):
            cleaned = cleaned.lstrip(" \t")
        if cleaned:
            self._last_char = cleaned[-1]
        return cleaned


class ReplyStream:
    """Emotion tag parsing + cleanup for one streamed model reply."""

    def __init__(self, strip_sources: bool = False) -> None:
        self._emotion = EmotionStreamParser()
        self._cleaner = StreamCleaner(strip_sources=strip_sources)
        self._parts: list[str] = []

    @property
    def emotion(self) -> str | None:
        return self._emotion.emotion

    @property
    def text(self) -> str:
        return "".join(self._parts)

    def feed(self, chunk: str) -> str:
        visible = self._emotion.feed(chunk)
        delta = self._cleaner.feed(visible) if visible else ""
        self._parts.append(delta)
        return delta

    def finish(self) -> str:
        visible = self._emotion.finish()
        delta = self._cleaner.feed(visible) if visible else ""
        delta += self._cleaner.finish()
        self._parts.append(delta)
        return delta

    def final_text(self) -> str:
        return self.text.strip()


def clean_reply(text: str, strip_sources: bool = False) -> tuple[str, str]:
    """Non-streaming convenience: (emotion, cleaned text)."""
    stream = ReplyStream(strip_sources=strip_sources)
    stream.feed(text)
    stream.finish()
    return stream.emotion or DEFAULT_EMOTION, stream.final_text()
