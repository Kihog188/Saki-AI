import asyncio
from datetime import date

import httpx
import pytest

from saki.search.cache import TTLCache
from saki.search.ddg import DdgClient, news_item_to_result, text_item_to_result
from saki.search.models import SearchResult, domain_of
from saki.search.news import (
    DEFAULT_SOURCES_FILE,
    NewsAggregator,
    SourceDef,
    SourcesConfig,
    dedupe,
    load_sources,
    matches_query,
    query_terms,
    rank,
)
from saki.search.rss import FeedFetcher, parse_feed
from saki.search.service import SearchService

TODAY = date(2026, 10, 19)

VNEXPRESS_RSS = """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel><title>VnExpress</title>
<item><title>Giá vàng hôm nay tăng mạnh</title>
<link>https://vnexpress.net/gia-vang-1.html</link>
<description><![CDATA[<a href="x"><img src="y"></a></br>Vàng miếng SJC tăng 500.000 đồng.]]></description>
<pubDate>Mon, 19 Oct 2026 08:00:00 +0700</pubDate></item>
<item><title>Bóng đá: tuyển Việt Nam thắng</title>
<link>https://vnexpress.net/bong-da.html</link>
<description>Trận đấu tối qua.</description>
<pubDate>Sun, 18 Oct 2026 21:00:00 +0700</pubDate></item>
<item><title>Giá vàng tuần trước</title>
<link>https://vnexpress.net/gia-vang-old.html</link>
<description>Tin cũ.</description>
<pubDate>Mon, 01 Sep 2026 08:00:00 +0700</pubDate></item>
</channel></rss>"""

TUOITRE_RSS = """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel><title>Tuổi Trẻ</title>
<item><title><![CDATA[GIÁ VÀNG HÔM NAY TĂNG MẠNH]]></title>
<link><![CDATA[https://tuoitre.vn/gia-vang-2.htm]]></link>
<description><![CDATA[Bản tin trùng với VnExpress.]]></description>
<pubDate>10/18/2026 10:03:00 PM</pubDate></item>
</channel></rss>"""

GOOGLE_RSS = """<?xml version="1.0" encoding="UTF-8"?>
<rss version="2.0"><channel><title>Google News</title>
<item><title>Giá vàng thế giới lập đỉnh - Thanh Niên</title>
<link>https://news.google.com/rss/articles/abc</link>
<pubDate>Sat, 17 Oct 2026 03:00:00 GMT</pubDate>
<description>&lt;a href="https://news.google.com/rss/articles/abc"&gt;Giá vàng thế giới lập đỉnh&lt;/a&gt;&amp;nbsp;&amp;nbsp;&lt;font color="#6f6f6f"&gt;Thanh Niên&lt;/font&gt;</description>
<source url="https://thanhnien.vn">Thanh Niên</source></item>
</channel></rss>"""


def test_domain_of():
    assert domain_of("https://www.vnexpress.net/a?b=1") == "vnexpress.net"
    assert domain_of("not a url") == ""


def test_parse_feed_rss():
    items = parse_feed(VNEXPRESS_RSS.encode(), "VnExpress")
    assert [i.title for i in items][0] == "Giá vàng hôm nay tăng mạnh"
    assert items[0].site == "vnexpress.net"
    assert items[0].date == TODAY
    assert items[0].snippet == "Vàng miếng SJC tăng 500.000 đồng."
    assert items[0].source == "VnExpress"


def test_parse_feed_fallback_date_format():
    (item,) = parse_feed(TUOITRE_RSS.encode(), "Tuổi Trẻ")
    assert item.date == date(2026, 10, 18)


def test_parse_feed_google_news():
    (item,) = parse_feed(GOOGLE_RSS.encode(), "Google News", paywalled=False)
    assert item.title == "Giá vàng thế giới lập đỉnh"
    assert item.site == "thanhnien.vn"
    assert item.snippet == ""
    assert item.url.startswith("https://news.google.com/")


def test_query_terms_and_matching():
    assert query_terms("Giá vàng hôm nay") == ["gia", "vang"]
    assert query_terms("hôm nay") == ["hom", "nay"]
    item = SearchResult("GIÁ VÀNG tăng", "u", "s", snippet="")
    assert matches_query(item, query_terms("giá vàng"))
    assert not matches_query(item, query_terms("giá xăng"))
    # whole-word match: "vang" must not match "vangs"
    assert not matches_query(SearchResult("gia vangs", "u", "s"), ["gia", "vang"])


def _r(title, url, d=None):
    return SearchResult(title, url, domain_of(url), d)


def test_dedupe_by_url_and_title():
    items = [
        _r("Giá vàng hôm nay tăng mạnh", "https://a.vn/1"),
        _r("Khác hẳn", "https://a.vn/1/"),
        _r("GIÁ VÀNG HÔM NAY TĂNG MẠNH!", "https://b.vn/2"),
        _r("Giá xăng giảm", "https://c.vn/3"),
    ]
    assert [i.url for i in dedupe(items)] == ["https://a.vn/1", "https://c.vn/3"]


def test_rank_prefers_recent_then_falls_back():
    items = [
        _r("old", "https://a.vn/old", date(2026, 9, 1)),
        _r("new", "https://a.vn/new", date(2026, 10, 18)),
        _r("undated", "https://a.vn/u"),
    ]
    assert [i.title for i in rank(items, TODAY)] == ["new"]
    only_old = [items[0], items[2]]
    assert [i.title for i in rank(only_old, TODAY)] == ["old", "undated"]


def test_ttl_cache_expiry():
    now = [0.0]
    c = TTLCache(ttl=10, clock=lambda: now[0])
    c.set("k", 1)
    assert c.get("k") == 1
    now[0] = 10.5
    assert c.get("k") is None


def test_ddg_item_conversion():
    t = text_item_to_result(
        {"title": "Giá vàng", "href": "https://www.24h.com.vn/x", "body": "Oct 12, 2026 · Giá bán 143 triệu."}
    )
    assert (t.site, t.date, t.snippet) == ("24h.com.vn", date(2026, 10, 12), "Giá bán 143 triệu.")
    n = news_item_to_result(
        {"title": "T", "url": "https://x.vn/a", "body": "B", "date": "2026-10-19T01:00:00+00:00"}
    )
    assert n.date in (date(2026, 10, 18), date(2026, 10, 19))  # depends on local timezone


class FakeDDGS:
    calls = []

    def __init__(self, timeout):
        pass

    def text(self, query, **kw):
        FakeDDGS.calls.append(("text", query, kw))
        return [{"title": "Kết quả", "href": "https://a.vn/x", "body": "Nội dung"}]

    def news(self, query, **kw):
        FakeDDGS.calls.append(("news", query, kw))
        return [{"title": "Giá vàng DDG", "url": "https://ddg.vn/n", "body": "B", "date": "2026-10-16T05:00:00+00:00"}]


async def test_ddg_client_passes_region_and_survives_errors():
    FakeDDGS.calls = []
    c = DdgClient(cooldown=0, ddgs_factory=FakeDDGS)
    res = await c.text("giá vàng")
    assert res[0].title == "Kết quả"
    assert FakeDDGS.calls[0][2]["region"] == "vn-vi"
    assert FakeDDGS.calls[0][2]["safesearch"] == "moderate"

    class Broken:
        def __init__(self, timeout):
            raise RuntimeError("rate limited")

    assert await DdgClient(cooldown=0, ddgs_factory=Broken).text("x") == []


async def test_ddg_client_timeout_returns_empty():
    class Slow:
        def __init__(self, timeout):
            pass

        def text(self, query, **kw):
            import time

            time.sleep(0.5)
            return [{"title": "late", "href": "https://a.vn"}]

    c = DdgClient(cooldown=0, timeout=-1.9, ddgs_factory=Slow)  # wait_for timeout = 0.1 s
    assert await c.text("x") == []


def test_sources_file_is_valid():
    cfg = load_sources()
    names = {s.name for s in cfg.sources}
    assert {"VnExpress", "Tuổi Trẻ", "Thanh Niên", "Dân Trí", "VietnamNet"} <= names
    types = {s.type for s in cfg.sources}
    assert types == {"rss", "google_news", "ddgs_news"}
    for s in cfg.sources:
        if s.type == "rss":
            assert s.url and s.url.startswith("https://")
        if s.site in ("ft.com", "wsj.com"):
            assert s.paywalled
    assert "{query}" in cfg.google_news_url
    assert DEFAULT_SOURCES_FILE.is_file()


def _aggregator(handler, sources, ddg=None, timeout=2.0):
    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    cfg = SourcesConfig("UA", load_sources().google_news_url, sources)
    return NewsAggregator(cfg, FeedFetcher(client), ddg, source_timeout=timeout, today=lambda: TODAY), client


async def test_news_aggregator_merges_filters_dedupes_and_tolerates_failures():
    requested = []

    def handler(request: httpx.Request):
        url = str(request.url)
        requested.append(url)
        if "vnexpress" in url:
            return httpx.Response(200, content=VNEXPRESS_RSS.encode())
        if "tuoitre" in url:
            return httpx.Response(200, content=TUOITRE_RSS.encode())
        if "news.google.com" in url and "site%3Areuters.com" in url:
            return httpx.Response(500)
        if "news.google.com" in url:
            return httpx.Response(200, content=GOOGLE_RSS.encode())
        raise httpx.ConnectError("down", request=request)

    sources = [
        SourceDef("VnExpress", "rss", url="https://vnexpress.net/rss/tin-moi-nhat.rss"),
        SourceDef("Tuổi Trẻ", "rss", url="https://tuoitre.vn/rss/tin-moi-nhat.rss"),
        SourceDef("Dead", "rss", url="https://dead.example/rss"),
        SourceDef("Disabled", "rss", url="https://disabled.example/rss", enabled=False),
        SourceDef("Google News (VN)", "google_news"),
        SourceDef("Reuters", "google_news", site="reuters.com", hl="en-US", gl="US", ceid="US:en"),
        SourceDef("DuckDuckGo News", "ddgs_news"),
    ]
    agg, client = _aggregator(handler, sources, ddg=DdgClient(cooldown=0, ddgs_factory=FakeDDGS))
    results = await agg.search("giá vàng hôm nay")
    await client.aclose()

    titles = [r.title for r in results]
    # bóng đá filtered out; Tuổi Trẻ duplicate title removed; old item dropped (recent ones exist)
    assert titles == ["Giá vàng hôm nay tăng mạnh", "Giá vàng thế giới lập đỉnh", "Giá vàng DDG"]
    assert all("disabled.example" not in u for u in requested)
    reuters = [u for u in requested if "reuters" in u][0]
    assert "hl=en-US" in reuters and "gl=US" in reuters
    vn = [u for u in requested if "news.google.com" in u and "reuters" not in u][0]
    assert "hl=vi" in vn and "gl=VN" in vn


async def test_news_aggregator_source_timeout():
    async def slow_handler(request):
        await asyncio.sleep(1)
        return httpx.Response(200, content=VNEXPRESS_RSS.encode())

    sources = [SourceDef("Slow", "rss", url="https://slow.example/rss")]
    agg, client = _aggregator(slow_handler, sources, timeout=0.05)
    assert await agg.search("giá vàng") == []
    await client.aclose()


async def test_feed_fetcher_caches():
    count = {"n": 0}

    def handler(request):
        count["n"] += 1
        return httpx.Response(200, content=VNEXPRESS_RSS.encode())

    client = httpx.AsyncClient(transport=httpx.MockTransport(handler))
    f = FeedFetcher(client, ttl=60)
    await f.fetch("https://vnexpress.net/rss")
    await f.fetch("https://vnexpress.net/rss")
    assert count["n"] == 1
    await client.aclose()


async def test_search_service_caches_per_normalized_query():
    class CountingDdg:
        n = 0

        async def text(self, q):
            CountingDdg.n += 1
            return [_r("x", "https://a.vn")]

    class NoNews:
        async def search(self, q):
            return []

    svc = SearchService(CountingDdg(), NoNews())
    await svc.web("Giá Vàng")
    await svc.web("  giá   vàng ")
    assert CountingDdg.n == 1
    assert await svc.news("x") == []


@pytest.mark.parametrize("q", ["", "   "])
def test_query_terms_empty(q):
    assert query_terms(q) == []
