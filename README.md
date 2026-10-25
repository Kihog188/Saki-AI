# Saki backend

Local-first backend for **Saki**, a desktop AI companion. It runs a small fine-tuned
model (Qwen2.5-1.5B, GGUF q4_k_m) through Ollama or llama.cpp, and lets any frontend
chat with it over a WebSocket on `127.0.0.1`. The desktop app is written in Godot 4 and
lives in [app/](app/) (see [app/GODOT_BEGINNER.md](app/GODOT_BEGINNER.md)). It starts this
backend by itself; a terminal client (`saki.cli`) is kept for debugging.

- No API keys, no telemetry. The only network traffic is search queries and RSS fetches.
- Built for weak machines: no PyTorch, no vector DB, small dependency list.
- Windows first. Also runs on Linux and macOS. Python 3.10+.

## Setup (Windows)

```powershell
cd D:\BOT\Saki
py -3.13 -m venv .venv          # any Python 3.10+ works
.venv\Scripts\python -m pip install -r requirements.txt
```

Create the model in Ollama (once):

```powershell
ollama create saki -f ModelFile
ollama list                      # should show saki:latest
```

## Running

```powershell
.venv\Scripts\python -m saki                 # server only (the desktop app normally starts it)
.venv\Scripts\python -m saki.cli             # terminal client, in a second window
```

Server options: `--port N`, `--data-dir DIR`, `--log-level DEBUG|INFO|WARNING|ERROR`.

If the port is already taken by a running Saki, `python -m saki` prints
`Saki đang chạy sẵn ở ...` and exits with code 0. If another program holds the port, it
prints a Vietnamese message and exits with code 1. Under `pythonw.exe` (no console) these
messages go to the log file only.

In the CLI, type a message or a command. `/cancel` stops the current answer and `/quit`
exits. Typing a new message while Saki is answering also cancels the old answer.
Vietnamese input and output work in Windows PowerShell (the client switches to UTF-8).
When stdin is piped, the CLI waits for each answer before it sends the next line:

```bash
printf '/help\n/news giá vàng\n' | .venv/Scripts/python -m saki.cli
```

## Commands

The backend parses commands before anything reaches the model. Command names are
case-insensitive. An unknown `/xyz` gets a help hint and is not sent to the model.

| Command | What it does | Uses LLM |
|---|---|---|
| `/se <query>` | Web search (DuckDuckGo), then the model summarizes the results | yes |
| `/news <query>` | Recent news from several sources, then the model summarizes them | yes |
| `/rmb <text>` | Save a memory (max 200 chars, max 30 items) | no |
| `/fgt` | List memories with their IDs | no |
| `/fgt <id>` / `/fgt <text>` | Delete by ID, or by text (if several match, they are listed) | no |
| `/xh <self> <user>` | Set how Saki refers to itself and to you, e.g. `/xh em anh`. Saved. No arguments shows the current pair | no |
| `/clear` | Clear conversation history (memories are kept) | no |
| `/help` | List commands | no |

## Configuration

Data lives in `%APPDATA%\Saki\` (`~/Library/Application Support/Saki` on macOS,
`~/.local/share/saki` on Linux). You can override it with `--data-dir` or the
`SAKI_DATA_DIR` environment variable.

```
%APPDATA%\Saki\
  saki.db          SQLite: settings, messages (history), memories
  config.json      optional, see below
  logs\saki.log    rotating log, 4 files x 1 MB
```

The desktop app keeps its own files in the same folder (`app_settings.json`,
`characters\`, `characters_dev\`, `logs\app.log`); see
[app/GODOT_BEGINNER.md](app/GODOT_BEGINNER.md).

`config.json` is optional. Any key you leave out keeps its default:

```json
{
  "port": 8765,
  "llm_backend": "ollama",
  "model": "saki",
  "ollama_url": "http://127.0.0.1:11434",
  "llamacpp_url": "http://127.0.0.1:8080",
  "self_name": "Saki",
  "user_name": "bạn",
  "temperature": 0.3,
  "top_p": 0.8,
  "num_ctx": 2048,
  "reply_reserve_tokens": 512,
  "context_max_turns": 3,
  "repeat_penalty": 1.15,
  "repeat_last_n": 128,
  "repeat_check_turns": 5,
  "repeat_similarity": 0.9,
  "retry_temperature": 0.7,
  "llm_read_timeout": 120,
  "llm_total_timeout": 300,
  "search_region": "vn-vi",
  "search_cache_ttl": 600,
  "feed_cache_ttl": 300,
  "news_source_timeout": 6,
  "max_search_results": 4,
  "sources_file": null
}
```

`self_name`, `user_name`, `llm_backend`, `model` and `port` are defaults only. Values
saved with `/xh` or `PUT /settings` are stored in SQLite and take precedence. The server
always binds to `127.0.0.1`. The keys `open_browser` and `character_pack` from the web UI
version are ignored if they are still in an old `config.json`.

News sources are listed in [saki/search/sources.json](saki/search/sources.json): name,
type (`rss`, `google_news` or `ddgs_news`), URL or `site:` filter, language,
`paywalled`, `enabled`, and a `note`. To change sources, edit that file, or point
`sources_file` at your own copy.

## Protocol (contract for the frontend)

### WebSocket `ws://127.0.0.1:8765/ws`

All frames are JSON text.

**Client → server**

```json
{"type": "user_message", "text": "Xin chào"}
{"type": "cancel"}
{"type": "hotkey_config", "enabled": true, "combo": "Ctrl+Shift+S"}
```

Sending a new `user_message` while a reply is still streaming cancels that reply first.

`hotkey_config` (optional) asks the backend to register a global hotkey (Windows only,
`RegisterHotKey` in [saki/hotkey.py](saki/hotkey.py)). `combo` is modifiers (`Ctrl`,
`Shift`, `Alt`, `Win`, at least one) plus a key (`A`–`Z`, `0`–`9`, `F1`–`F24`, `Space`,
`Tab`, `Home`, `End`, `PageUp`, `PageDown`, `Insert`, `Delete`, arrows). `enabled: false`
releases it. The hotkey is also released when the last WebSocket client disconnects.

**Server → client**

| Event | Meaning |
|---|---|
| `{"type":"status","state":"searching"}` | a search is running |
| `{"type":"status","state":"thinking"}` | waiting for the model (show the thinking animation) |
| `{"type":"start","emotion":"happy","system":false}` | the emotion is known; change the expression now |
| `{"type":"delta","text":"..."}` | the next piece of visible text (typing effect) |
| `{"type":"end","emotion":"happy","text":"...","sources":[...],"system":false}` | final answer. `text` is the authoritative full text |
| `{"type":"error","message":"..."}` | user-facing Vietnamese error. The turn is over |
| `{"type":"cancelled"}` | the current turn was cancelled. The turn is over |
| `{"type":"reset"}` | the reply just streamed repeated a recent answer. Discard the text shown so far; a new `start` and new `delta`s follow |
| `{"type":"hotkey_status","ok":true,"message":""}` | answer to `hotkey_config`. `ok: false` with a Vietnamese `message` when it is unsupported (not Windows), invalid, or already used by another program |
| `{"type":"hotkey"}` | the global hotkey was pressed (sent to every connected client). Not part of a turn |

Emotions: `neutral`, `happy`, `sad`, `thinking`, `surprised`, `embarrassed`.
Every turn ends with exactly one `end`, `error` or `cancelled`. `reset` happens at most
once per turn.

A normal chat turn:

```json
→ {"type":"user_message","text":"Chào Saki"}
← {"type":"status","state":"thinking"}
← {"type":"start","emotion":"happy","system":false}
← {"type":"delta","text":"Chào "}
← {"type":"delta","text":"bạn."}
← {"type":"end","emotion":"happy","text":"Chào bạn.","sources":[],"system":false}
```

A search turn. The `Nguồn:` line is added by the backend, not by the model:

```json
→ {"type":"user_message","text":"/news giá vàng"}
← {"type":"status","state":"searching"}
← {"type":"status","state":"thinking"}
← {"type":"start","emotion":"neutral","system":false}
← {"type":"delta","text":"Giá vàng hôm nay tăng nhẹ [1]. "}
← {"type":"delta","text":"\n\nNguồn: [1] dantri.com.vn (19/10/2026)"}
← {"type":"end","emotion":"neutral",
   "text":"Giá vàng hôm nay tăng nhẹ [1].\n\nNguồn: [1] dantri.com.vn (19/10/2026)",
   "sources":[{"index":1,"title":"Rào cản lớn khiến giá vàng giằng co...","url":"https://dantri.com.vn/...",
               "display_url":"https://dantri.com.vn/...","site":"dantri.com.vn","date":"2026-10-19",
               "paywalled":false}],
   "system":false}
```

`url` is the link to open. `display_url` is what to show. For Google News results,
`url` is an opaque `news.google.com` redirect, so `display_url` is the publisher's
domain (e.g. `laodong.vn`).

A repeated reply, regenerated once:

```json
→ {"type":"user_message","text":"Khỏe không"}
← {"type":"status","state":"thinking"}
← {"type":"start","emotion":"neutral","system":false}
← {"type":"delta","text":"Không có gì. Anh đang làm việc."}
← {"type":"reset"}
← {"type":"start","emotion":"happy","system":false}
← {"type":"delta","text":"Em khỏe, cảm ơn anh."}
← {"type":"end","emotion":"happy","text":"Em khỏe, cảm ơn anh.","sources":[],"system":false}
```

A command reply (no model involved). Use `system: true` to style it differently:

```json
→ {"type":"user_message","text":"/rmb Tên tôi là Minh"}
← {"type":"start","emotion":"neutral","system":true}
← {"type":"delta","text":"Đã nhớ: Tên tôi là Minh"}
← {"type":"end","emotion":"neutral","text":"Đã nhớ: Tên tôi là Minh","sources":[],"system":true}
```

When the model server is down:

```json
← {"type":"status","state":"thinking"}
← {"type":"error","message":"Saki chưa kết nối được với mô hình. Hãy mở Ollama (hoặc chạy lệnh: ollama serve) rồi thử lại."}
```

### REST

| Method & path | Body / response |
|---|---|
| `GET /health` | `{"status":"ok","version":"0.1.0","protocol_version":1,"llm":{"backend":"ollama","model":"saki","reachable":true,"model_available":true,"detail":""},"hardware":{"free_ram_gb":1.83,"tier":"small","model_hint":"qwen2.5-0.5b","warning":null}}` |
| `GET /settings` | `{"self_name":"Saki","user_name":"bạn","llm_backend":"ollama","model":"saki","port":8765}` |
| `PUT /settings` | partial body, e.g. `{"self_name":"em","user_name":"anh"}` → new settings plus `"restart_required": bool` (true when the port changed). 400 with a Vietnamese `detail` for invalid values. Unknown keys are ignored |
| `GET /history?limit=50&before=<id>` | `{"messages":[{"id":12,"role":"assistant","content":"...","emotion":"happy","kind":"chat","created_at":1760890000.0}, ...]}`, oldest first. `kind` is `chat` or `search`. `emotion` is set on assistant messages. `before` (optional) returns only messages with a smaller `id`, for paging back through older history |
| `DELETE /history` | `{"ok":true}` |
| `GET /memories` | `{"memories":[{"id":1,"text":"...","created_at":...}]}` |
| `POST /memories` | `{"text":"..."}` → 201 with the memory, or 400 (empty, too long, store full) |
| `DELETE /memories/{id}` | `{"ok":true}` or 404 |
| `POST /shutdown` | stops the server. Only exists when the backend was started with the environment variable `SAKI_SHUTDOWN_TOKEN` set, and needs the header `X-Saki-Token: <that value>` (403 otherwise, 404 without the variable). The desktop app uses it to stop the backend it started |

`protocol_version` (currently `1`) changes only when the contract above changes in a way
that clients must handle. The desktop app refuses to talk to a backend with another
version and says so. Version 1 removed the web page (`GET /`, `/static/*`), the
`/characters` endpoints and the `character_pack` setting, and added `id`/`before` to
`/history` and `/shutdown`.

Hardware tiers by free RAM: under 1.2 GB is `insufficient` (with a warning), 1.2–2.5 GB
is `small` (0.5B model recommended), above that is `standard` (1.5B). The backend only
reports the tier; it never switches models by itself.

## Desktop app (`app/`)

Godot 4.7.2 (Compatibility renderer, GDScript). It starts this backend hidden
(`pythonw -m saki`), stops it on exit, and has two display modes: a chat window and a
transparent desktop pet. Docs (Vietnamese):

- [app/GODOT_BEGINNER.md](app/GODOT_BEGINNER.md): install Godot, run, tests, export
  `Saki.exe`, desktop shortcut, where logs and settings live, troubleshooting.
- [app/ARCHITECTURE.md](app/ARCHITECTURE.md): layers, EventBus signals, the flow of one
  chat turn, how to add a renderer.
- [app/PACK_GUIDE.md](app/PACK_GUIDE.md): character pack format and `.sakip` import.

Measured on the dev machine (i5-3360M, Intel HD 4000 through ANGLE/D3D11, 8 GB RAM, tier
"Vừa", `app/tools/measure.gd`):

| | Chat window | Desktop pet |
|---|---|---|
| App RAM (working set) | 158 MB | 153 MB |
| CPU idle / busy | 0–0.5 % / 0–0.3 % of one core | 0 % / 0–1 % |
| Loop rate idle / busy | 12 / 8 per second (tier caps) | 12 / 8 |

Backend (`pythonw` + interpreter, no model loaded) 61 MB. Pack list with 200 packs: 32 ms
from the cache, 2.2 s for the first scan. Scrolling 1,000 messages: median 16.6 ms per
frame.

## Gói nhân vật

Gói nhân vật giờ do app desktop quản lý (backend không còn biết gì về ảnh). Cách tạo gói:
[app/PACK_GUIDE.md](app/PACK_GUIDE.md).

## Switching to llama.cpp (`llama-server`)

`llama-server` is lighter than Ollama and can ship with the app.

```powershell
llama-server -m Qwen2.5-1.5B-Instruct.Q4_K_M.gguf -c 2048 --host 127.0.0.1 --port 8080 --chat-template chatml
```

Then either set `"llm_backend": "llamacpp"` in `config.json`, or switch at runtime:

```powershell
Invoke-RestMethod -Method Put -Uri http://127.0.0.1:8765/settings -ContentType 'application/json' -Body '{"llm_backend":"llamacpp"}'
```

The context size is fixed by `-c` when llama-server starts. Temperature, top_p and the
`<|im_end|>` stop token are sent with each request. On a CPU without AVX2, use a
llama.cpp build for AVX (or a generic build).

## How it works

- **System prompt** ([saki/prompts.py](saki/prompts.py)): matches the fine-tuning data
  exactly. Only the two address words change. Memories are appended as
  `\n[BỘ NHỚ] a; b; c`, capped at about 400 characters (the oldest are dropped first).
  A unit test asserts the exact string.
- **Search prompt**: the user message for `/se` and `/news` is the original command,
  a blank line, `[HÔM NAY: YYYY-MM-DD]`, then `[KẾT QUẢ TÌM KIẾM]` with up to 4 results,
  newest first. This is the same format as the training data. Search turns are sent
  without chat history, because they were trained as single-turn conversations. History
  stores only the command and the final answer, marked `kind: "search"`. These turns are
  shown in `GET /history` but never sent back to the model.
- **`/news`** queries every enabled source in parallel (6 s timeout each) and tolerates
  failures. Sources: VnExpress, Tuổi Trẻ, Thanh Niên, Dân Trí and VietnamNet RSS (kept
  only if every query keyword appears in the **title**, accent-insensitive), Google News
  RSS for Vietnam, Google News with `site:` filters for Reuters, AP, FT and WSJ (FT and
  WSJ are marked `paywalled`), and DuckDuckGo news as a fallback. Results are
  deduplicated by URL and by near-identical title. Items from the last 7 days are
  preferred, sources with `lang: "vi"` come first, and each source contributes at most 2
  results. Feeds are cached for 5 minutes and query results for 10 minutes.
- **Repetition control**: `repeat_penalty` 1.15 (Ollama also gets `repeat_last_n` 128),
  only the last 3 chat turns in context, and if a new reply is nearly identical to one of
  the last 5 replies, it is regenerated once at temperature 0.7 without history (the
  client gets a `reset` event).
- **Post-processing** ([saki/postprocess.py](saki/postprocess.py)) runs on every reply,
  while it streams:
  1. Parse the emotion tag (`neutral` if it is missing).
  2. Strip leaked CJK characters and special tokens.
  3. Rewrite `/nho` to `/rmb` and `/quen` to `/fgt` (the old command names in the training data).
  4. On every turn, drop any `Nguồn:` block the model wrote. On search turns, the backend
     appends its own.
- **Context**: system prompt, then up to the last 3 chat turns (assistant replies get
  their emotion tag back, e.g. `[happy] ...`, as in training) as far as they fit in
  `num_ctx` minus a 512-token reply reserve (about 3 characters per token), then the
  current message.

## Tests

```powershell
.venv\Scripts\python -m pytest
```

Tests run without network access or Ollama. HTTP is mocked, `FakeBackend` streams canned
replies, and search sources are faked. They cover exact prompt strings, command parsing,
the search prompt builder, sources, emotion streaming edge cases, the CJK and command
rewrites, storage limits, context trimming, the LLM adapters, the news aggregator, the
full WebSocket/REST flow (including history paging and the shutdown token), and the
startup logic for a busy port. The desktop app has its own tests (GUT), see
[app/GODOT_BEGINNER.md](app/GODOT_BEGINNER.md).

## Project layout

```
saki/
  __main__.py      start the server, handle a busy port
  config.py        AppConfig, app-data paths, logging
  settings.py      editable settings (shared by /xh and PUT /settings)
  prompts.py       system prompt + search prompt builders
  commands.py      command parsing and non-LLM handlers
  postprocess.py   emotion tag, cleanup, rewrites, sources, streaming
  context.py       context-window trimming
  chat.py          one chat turn (transport-agnostic)
  server.py        FastAPI app: /ws + REST
  storage.py       SQLite
  hardware.py      free RAM -> tier; ModelProvisioner interface (TODO)
  hotkey.py        optional global hotkey for the desktop app (Windows RegisterHotKey)
  cli.py           terminal client
  llm/             base.py, ollama.py, llamacpp.py, fake.py
  search/          models.py, ddg.py, rss.py, news.py, service.py, cache.py, sources.json
tests/
app/               Godot 4 desktop app (see app/ARCHITECTURE.md)
```

## Known limitations

- **Search sources are unofficial.** DuckDuckGo (`ddgs`) and Google News RSS can change,
  rate-limit or break at any time. Newspaper RSS URLs can move. On failure, Saki answers
  from "no results" instead of crashing. Feed URLs were last checked on 2026-10-19.
- **The model is small and can be wrong.** It sometimes ignores memories (only 2 training
  examples used `[BỘ NHỚ]`) and gives weak summaries of generic web pages (for example,
  undated weather pages from `/se`). Treat its answers as hints.
- `/se` results usually have no date (`không rõ ngày`). `/news` results do.
- Google News links are `news.google.com` redirect URLs. `site` shows the real publisher.
- The model was trained with `/nho` and `/quen`. The backend rewrites them in output until
  the model is retrained.
- Model files are not downloaded automatically yet (see the TODO in `hardware.py`).
- Changing the port requires a restart.
- Desktop app: the pet's transparency, click-through, drag and resize, and a real press
  of the global hotkey were built and unit-tested but not yet tried by a person on the
  desktop. A real `Saki.exe` export was not made (export templates not installed on the
  dev machine). See "Not verified" in [HANDOFF.md](HANDOFF.md).
