"""RSS fetching (httpx) and parsing (feedparser), with a short per-URL cache."""

from __future__ import annotations

import calendar
import logging
import warnings
from datetime import date, datetime

import feedparser
import httpx

from ..textnorm import fold
from .cache import TTLCache
from .models import SearchResult, domain_of, strip_html

log = logging.getLogger(__name__)

# Non-RFC date formats seen in Vietnamese feeds (e.g. Tuổi Trẻ: "10/19/2026 10:03:00 PM").
_FALLBACK_DATE_FORMATS = ("%m/%d/%Y %I:%M:%S %p", "%m/%d/%Y %H:%M:%S", "%d/%m/%Y %H:%M:%S", "%Y-%m-%d %H:%M:%S")


def entry_date(entry) -> date | None:
    for key in ("published_parsed", "updated_parsed"):
        with warnings.catch_warnings():
            # feedparser warns about its updated_parsed -> published_parsed mapping.
            warnings.simplefilter("ignore", DeprecationWarning)
            st = entry.get(key)
        if st:
            # feedparser normalizes to UTC; convert to the local date.
            return datetime.fromtimestamp(calendar.timegm(st)).date()
    for key in ("published", "updated"):
        raw = entry.get(key)
        if not raw:
            continue
        raw = " ".join(raw.replace(" ", " ").split())
        for fmt in _FALLBACK_DATE_FORMATS:
            try:
                return datetime.strptime(raw, fmt).date()
            except ValueError:
                continue
    return None


def parse_feed(content: bytes, source_name: str = "", paywalled: bool = False) -> list[SearchResult]:
    """Parse RSS/Atom bytes into results. Google News titles 'X - Publisher' are cleaned."""
    feed = feedparser.parse(content)
    out: list[SearchResult] = []
    for e in feed.entries:
        title = strip_html(e.get("title", ""))
        url = e.get("link", "")
        if not title or not url:
            continue
        site = domain_of(url)
        snippet = strip_html(e.get("summary", ""))
        src = e.get("source")
        if src is not None and "news.google." in url:
            publisher = src.get("title", "")
            site = domain_of(src.get("href", "")) or site
            if publisher and title.endswith(" - " + publisher):
                title = title[: -len(publisher) - 3].rstrip()
            # Google's summary is just "<a>title</a> publisher": not a useful snippet.
            if fold(snippet).startswith(fold(title)[:30]):
                snippet = ""
        out.append(
            SearchResult(
                title=title,
                url=url,
                site=site,
                date=entry_date(e),
                snippet=snippet,
                source=source_name,
                paywalled=paywalled,
            )
        )
    return out


class FeedFetcher:
    """Fetches feeds with a proper User-Agent and caches them for a few minutes."""

    def __init__(self, client: httpx.AsyncClient, ttl: float = 300.0):
        self._client = client
        self._cache = TTLCache(ttl=ttl, maxsize=64)

    async def fetch(self, url: str, source_name: str = "", paywalled: bool = False) -> list[SearchResult]:
        cached = self._cache.get(url)
        if cached is not None:
            return cached
        resp = await self._client.get(url, follow_redirects=True)
        resp.raise_for_status()
        items = parse_feed(resp.content, source_name=source_name, paywalled=paywalled)
        self._cache.set(url, items)
        return items
