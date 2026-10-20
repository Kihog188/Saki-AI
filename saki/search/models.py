"""Search result model and small helpers shared by all search sources."""

from __future__ import annotations

import html
import re
from dataclasses import dataclass, field
from datetime import date
from urllib.parse import urlparse

_TAG_RE = re.compile(r"<[^>]+>")
_WS_RE = re.compile(r"\s+")


@dataclass
class SearchResult:
    title: str
    url: str
    site: str  # bare domain, e.g. "vnexpress.net"
    date: date | None = None
    snippet: str = ""
    source: str = ""  # name of the source definition that produced it
    paywalled: bool = False
    lang: str = ""  # language of the source definition ("vi", "en")
    extra: dict = field(default_factory=dict)


def domain_of(url: str) -> str:
    """'https://www.vnexpress.net/a/b' -> 'vnexpress.net'."""
    try:
        host = urlparse(url).hostname or ""
    except ValueError:
        return ""
    return host[4:] if host.startswith("www.") else host


def is_redirect_link(url: str) -> bool:
    """Google News article links are opaque redirects, not the publisher's URL."""
    return domain_of(url).startswith("news.google.")


def strip_html(text: str) -> str:
    """Remove tags, unescape entities and collapse whitespace."""
    if not text:
        return ""
    text = _TAG_RE.sub(" ", text)
    text = html.unescape(text)
    text = _TAG_RE.sub(" ", text)  # entities may have encoded tags
    return _WS_RE.sub(" ", text).strip()


def truncate_words(text: str, limit: int = 300) -> str:
    """Cut `text` to at most `limit` characters at a word boundary, adding an ellipsis."""
    text = text.strip()
    if len(text) <= limit:
        return text
    cut = text[: limit - 1]
    space = cut.rfind(" ")
    if space > limit // 2:
        cut = cut[:space]
    return cut.rstrip(" ,.;:-–—") + "…"
