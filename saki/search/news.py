"""/news: aggregate Vietnamese RSS feeds, Google News RSS and DuckDuckGo news."""

from __future__ import annotations

import asyncio
import json
import logging
from collections import Counter
from collections.abc import Callable
from dataclasses import dataclass
from datetime import date
from difflib import SequenceMatcher
from pathlib import Path
from urllib.parse import quote_plus

from ..textnorm import fold_words
from .ddg import DdgClient
from .models import SearchResult
from .rss import FeedFetcher

log = logging.getLogger(__name__)

DEFAULT_SOURCES_FILE = Path(__file__).with_name("sources.json")
RECENT_DAYS = 7
TITLE_SIMILARITY = 0.9
MAX_PER_SOURCE = 2

# Filler words ignored when matching a query against RSS items (accent-folded).
STOPWORDS = frozenset(
    "hom nay qua mai moi nhat tin tuc ve la gi co khong cua va nhung cac the nao ra sao "
    "bao nhieu hien tai dang da se duoc cho voi tai o thi mot nhu nay do".split()
)


@dataclass
class SourceDef:
    name: str
    type: str  # "rss" | "google_news" | "ddgs_news"
    url: str | None = None
    site: str | None = None
    lang: str = "vi"
    hl: str = "vi"
    gl: str = "VN"
    ceid: str = "VN:vi"
    timelimit: str = "w"
    paywalled: bool = False
    enabled: bool = True
    note: str = ""


@dataclass
class SourcesConfig:
    user_agent: str
    google_news_url: str
    sources: list[SourceDef]


def load_sources(path: Path | None = None) -> SourcesConfig:
    raw = json.loads(Path(path or DEFAULT_SOURCES_FILE).read_text(encoding="utf-8"))
    known = set(SourceDef.__dataclass_fields__)
    sources = [SourceDef(**{k: v for k, v in s.items() if k in known}) for s in raw["sources"]]
    return SourcesConfig(raw["user_agent"], raw["google_news_url"], sources)


def query_terms(query: str) -> list[str]:
    words = fold_words(query).split()
    content = [w for w in words if w not in STOPWORDS]
    return content or words


def matches_query(item: SearchResult, terms: list[str]) -> bool:
    """Accent-insensitive: every query term must appear as a word in the title.

    The summary is ignored on purpose: matching on it let unrelated articles in
    (e.g. a celebrity story for "/news thời tiết").
    """
    if not terms:
        return False
    haystack = f" {fold_words(item.title)} "
    return all(f" {t} " in haystack for t in terms)


def _url_key(url: str) -> str:
    return url.split("#", 1)[0].rstrip("/").lower()


def dedupe(items: list[SearchResult]) -> list[SearchResult]:
    """Drop duplicate URLs and near-identical titles, keeping the first occurrence."""
    kept: list[SearchResult] = []
    urls: set[str] = set()
    titles: list[str] = []
    for it in items:
        uk = _url_key(it.url)
        tk = fold_words(it.title)
        if uk in urls or any(SequenceMatcher(None, tk, t).ratio() >= TITLE_SIMILARITY for t in titles):
            continue
        urls.add(uk)
        titles.append(tk)
        kept.append(it)
    return kept


def sort_newest_first(items: list[SearchResult]) -> list[SearchResult]:
    dated = sorted((r for r in items if r.date), key=lambda r: r.date, reverse=True)
    return dated + [r for r in items if not r.date]


def rank(
    items: list[SearchResult],
    today: date,
    recent_days: int = RECENT_DAYS,
    limit: int = 4,
    per_source: int = MAX_PER_SOURCE,
) -> list[SearchResult]:
    """Pick the results to send to the model.

    Deduplicated, recent items only if there are any, Vietnamese sources first
    (newest first within each language group), at most `per_source` per source.
    """
    items = dedupe(sort_newest_first(items))
    recent = [r for r in items if r.date and 0 <= (today - r.date).days <= recent_days]
    items = recent or items
    items = sorted(items, key=lambda r: r.lang != "vi")  # stable: keeps date order
    picked: list[SearchResult] = []
    per: Counter[str] = Counter()
    for r in items:
        if per[r.source] >= per_source:
            continue
        per[r.source] += 1
        picked.append(r)
        if len(picked) >= limit:
            break
    return picked


class NewsAggregator:
    def __init__(
        self,
        config: SourcesConfig,
        fetcher: FeedFetcher,
        ddg: DdgClient | None,
        source_timeout: float = 6.0,
        today: Callable[[], date] = date.today,
        limit: int = 4,
    ):
        self.config = config
        self.fetcher = fetcher
        self.ddg = ddg
        self.source_timeout = source_timeout
        self.today = today
        self.limit = limit

    @property
    def enabled_sources(self) -> list[SourceDef]:
        return [s for s in self.config.sources if s.enabled]

    def google_news_url(self, src: SourceDef, query: str) -> str:
        q = f"{query} site:{src.site}" if src.site else query
        return self.config.google_news_url.format(
            query=quote_plus(q), hl=src.hl, gl=src.gl, ceid=src.ceid
        )

    async def _from_source(self, src: SourceDef, query: str) -> list[SearchResult]:
        if src.type == "rss" and src.url:
            items = await self.fetcher.fetch(src.url, src.name, src.paywalled)
            terms = query_terms(query)
            return [it for it in items if matches_query(it, terms)]
        if src.type == "google_news":
            return await self.fetcher.fetch(self.google_news_url(src, query), src.name, src.paywalled)
        if src.type == "ddgs_news" and self.ddg is not None:
            return await self.ddg.news(query, timelimit=src.timelimit)
        return []

    async def _safe(self, src: SourceDef, query: str) -> list[SearchResult]:
        try:
            items = await asyncio.wait_for(self._from_source(src, query), self.source_timeout)
            for it in items:  # tag with the source definition (used by `rank`)
                it.source = src.name
                it.lang = src.lang
                it.paywalled = it.paywalled or src.paywalled
            return items
        except asyncio.TimeoutError:
            log.warning("News source %s timed out", src.name)
        except Exception as exc:
            log.warning("News source %s failed: %s", src.name, exc)
        return []

    async def search(self, query: str) -> list[SearchResult]:
        batches = await asyncio.gather(*(self._safe(s, query) for s in self.enabled_sources))
        merged = [it for batch in batches for it in batch]
        log.info("News search: %d raw items from %d sources", len(merged), len(batches))
        return rank(merged, self.today(), limit=self.limit)
