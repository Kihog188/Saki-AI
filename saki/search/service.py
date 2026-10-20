"""Search facade used by the chat service, with a per-query result cache."""

from __future__ import annotations

from typing import Protocol

import httpx

from ..config import AppConfig
from ..textnorm import fold_words
from .cache import TTLCache
from .ddg import DdgClient
from .models import SearchResult
from .news import NewsAggregator, load_sources
from .rss import FeedFetcher


class SearchProvider(Protocol):
    async def web(self, query: str) -> list[SearchResult]: ...

    async def news(self, query: str) -> list[SearchResult]: ...


class SearchService:
    def __init__(self, ddg: DdgClient, news: NewsAggregator, ttl: float = 600.0):
        self.ddg = ddg
        self.aggregator = news
        self._cache = TTLCache(ttl=ttl, maxsize=128)

    async def web(self, query: str) -> list[SearchResult]:
        return await self._cached("se", query, self.ddg.text)

    async def news(self, query: str) -> list[SearchResult]:
        return await self._cached("news", query, self.aggregator.search)

    async def _cached(self, kind: str, query: str, fn) -> list[SearchResult]:
        key = f"{kind}:{fold_words(query)}"
        hit = self._cache.get(key)
        if hit is not None:
            return hit
        results = await fn(query)
        if results:  # do not cache failures/empty answers
            self._cache.set(key, results)
        return results


def create_search_service(cfg: AppConfig) -> tuple[SearchService, httpx.AsyncClient]:
    """Build the real search stack. The caller owns (and must close) the HTTP client."""
    sources = load_sources(cfg.sources_file)
    client = httpx.AsyncClient(
        headers={"User-Agent": sources.user_agent, "Accept-Language": "vi,en;q=0.8"},
        timeout=httpx.Timeout(cfg.news_source_timeout),
    )
    ddg = DdgClient(
        region=cfg.search_region, timeout=cfg.ddg_timeout, cooldown=cfg.ddg_cooldown
    )
    aggregator = NewsAggregator(
        sources,
        FeedFetcher(client, ttl=cfg.feed_cache_ttl),
        ddg,
        source_timeout=cfg.news_source_timeout,
    )
    return SearchService(ddg, aggregator, ttl=cfg.search_cache_ttl), client
