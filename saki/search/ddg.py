"""DuckDuckGo search through the unofficial `ddgs` package (no API key).

It can fail or be rate-limited at any time, so every call has a timeout, a
cooldown between calls, and returns [] instead of raising.
"""

from __future__ import annotations

import asyncio
import logging
import re
import time
from collections.abc import Callable
from datetime import date, datetime
from typing import Any

from .models import SearchResult, domain_of, strip_html

log = logging.getLogger(__name__)

# DDG text snippets often start with a date: "Oct 12, 2026 · Giá vàng ..."
_LEADING_DATE_RE = re.compile(r"^([A-Z][a-z]{2} \d{1,2}, \d{4})\s*[·\-—]\s*")


def _default_factory(timeout: float):
    from ddgs import DDGS  # imported lazily: keeps server start-up fast

    return DDGS(timeout=int(max(1, timeout)))


def parse_iso_date(value: str | None) -> date | None:
    if not value:
        return None
    try:
        dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None
    if dt.tzinfo is not None:
        dt = dt.astimezone()  # convert to local time
    return dt.date()


def text_item_to_result(item: dict) -> SearchResult:
    url = item.get("href") or item.get("url") or ""
    snippet = strip_html(item.get("body") or "")
    d = None
    m = _LEADING_DATE_RE.match(snippet)
    if m:
        try:
            d = datetime.strptime(m.group(1), "%b %d, %Y").date()
            snippet = snippet[m.end():]
        except ValueError:
            pass
    return SearchResult(
        title=strip_html(item.get("title") or ""),
        url=url,
        site=domain_of(url),
        date=d,
        snippet=snippet,
        source="DuckDuckGo",
    )


def news_item_to_result(item: dict) -> SearchResult:
    url = item.get("url") or item.get("href") or ""
    return SearchResult(
        title=strip_html(item.get("title") or ""),
        url=url,
        site=domain_of(url),
        date=parse_iso_date(item.get("date")),
        snippet=strip_html(item.get("body") or ""),
        source="DuckDuckGo News",
    )


class DdgClient:
    def __init__(
        self,
        region: str = "vn-vi",
        safesearch: str = "moderate",
        timeout: float = 8.0,
        cooldown: float = 1.5,
        ddgs_factory: Callable[[float], Any] | None = None,
    ):
        self.region = region
        self.safesearch = safesearch
        self.timeout = timeout
        self.cooldown = cooldown
        self._factory = ddgs_factory or _default_factory
        self._lock = asyncio.Lock()
        self._last_call = 0.0

    async def text(self, query: str, max_results: int = 8) -> list[SearchResult]:
        items = await self._call("text", query, max_results=max_results)
        return [r for r in map(text_item_to_result, items) if r.url and r.title]

    async def news(self, query: str, timelimit: str = "w", max_results: int = 8) -> list[SearchResult]:
        items = await self._call("news", query, max_results=max_results, timelimit=timelimit)
        return [r for r in map(news_item_to_result, items) if r.url and r.title]

    async def _call(self, method: str, query: str, **kwargs) -> list[dict]:
        async with self._lock:
            wait = self.cooldown - (time.monotonic() - self._last_call)
            if wait > 0:
                await asyncio.sleep(wait)

            def run() -> list[dict]:
                client = self._factory(self.timeout)
                fn = getattr(client, method)
                return fn(query, region=self.region, safesearch=self.safesearch, **kwargs) or []

            try:
                return await asyncio.wait_for(asyncio.to_thread(run), timeout=self.timeout + 2)
            except Exception as exc:  # ddgs raises many exception types; never crash
                log.warning("DuckDuckGo %s search failed: %s", method, type(exc).__name__)
                return []
            finally:
                self._last_call = time.monotonic()
