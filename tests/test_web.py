import re
from pathlib import Path

import pytest

WEB_DIR = Path(__file__).parent.parent / "saki" / "web"


def test_index_serves_the_chat_page(web):
    client, _ = web
    r = client.get("/")
    assert r.status_code == 200
    assert r.headers["content-type"].startswith("text/html")
    assert r.headers["x-content-type-options"] == "nosniff"
    csp = r.headers["content-security-policy"]
    assert "script-src 'self'" in csp and "ws://testserver" in csp
    assert '<html lang="vi">' in r.text
    assert 'src="/static/js/main.js"' in r.text


def test_csp_ignores_a_malformed_host_header(web):
    client, _ = web
    r = client.get("/", headers={"host": "evil; script-src *"})
    assert "ws://127.0.0.1;" in r.headers["content-security-policy"]


@pytest.mark.parametrize(
    "path, content_type",
    [
        ("/static/style.css", "text/css"),
        ("/static/js/main.js", "text/javascript"),
        ("/static/js/api.js", "text/javascript"),
        ("/static/js/chat.js", "text/javascript"),
        ("/static/js/character.js", "text/javascript"),
        ("/static/js/panels.js", "text/javascript"),
    ],
)
def test_static_files_have_correct_content_types(web, path, content_type):
    client, _ = web
    r = client.get(path)
    assert r.status_code == 200
    assert r.headers["content-type"].split(";")[0] == content_type
    assert r.headers["x-content-type-options"] == "nosniff"


def test_static_rejects_traversal_and_missing_files(web):
    client, _ = web
    assert client.get("/static/nope.js").status_code == 404
    assert client.get("/static/..%2f__init__.py").status_code == 404
    assert client.get("/static/%2e%2e/server.py").status_code == 404


def test_every_module_import_resolves():
    for js in WEB_DIR.glob("js/*.js"):
        for name in re.findall(r'from "\./([\w.]+)"', js.read_text(encoding="utf-8")):
            assert (WEB_DIR / "js" / name).is_file(), f"{js.name} imports missing {name}"


def test_frontend_never_uses_html_sinks():
    """Model output and search titles are untrusted: no innerHTML-style sinks anywhere."""
    for js in WEB_DIR.glob("js/*.js"):
        code = js.read_text(encoding="utf-8")
        for sink in ("innerHTML", "outerHTML", "insertAdjacentHTML", "document.write", "eval("):
            assert sink not in code, f"{js.name} uses {sink}"


def test_page_has_no_external_resources():
    for f in [WEB_DIR / "index.html", WEB_DIR / "style.css", *WEB_DIR.glob("js/*.js")]:
        text = f.read_text(encoding="utf-8")
        assert not re.search(r'(src|href)="(https?:)?//', text), f"{f.name} loads an external resource"
        assert "@import" not in text and "url(http" not in text
