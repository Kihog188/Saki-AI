# Saki backend

Local-first backend for **Saki**, a desktop AI companion. It runs a small fine-tuned
model (Qwen2.5-1.5B, GGUF q4_k_m) through Ollama or llama.cpp, and lets any frontend
(Godot, Unity, a terminal) chat with it over a WebSocket on `127.0.0.1`.

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
.venv\Scripts\python -m saki                 # server + web chat page at http://127.0.0.1:8765/
.venv\Scripts\python -m saki.cli             # terminal client, in a second window
```

Server options: `--port N`, `--data-dir DIR`, `--log-level DEBUG|INFO|WARNING|ERROR`,
`--no-browser`.

`python -m saki` opens the chat page in the default browser once the server is listening
(turn this off with `--no-browser` or `"open_browser": false` in `config.json`). If the
port is already taken by a running Saki, it prints `Saki đang chạy sẵn ở ...` and just
opens the browser there. If another program holds the port, it prints a Vietnamese
message and exits with code 1.

## Web chat page

A simple browser UI for daily testing, served by the backend itself at
`http://127.0.0.1:<port>/` (files in [saki/web/](saki/web/)). Plain HTML, CSS and ES
modules: no build step, no npm, no CDN, works offline. Godot/Unity will replace it later.

- Character panel (image for the current emotion, status line) and chat panel (streaming
  replies, Stop button, clickable sources for `/se` and `/news`).
- **Ghi nhớ** drawer: list, add and delete memories. **Cài đặt** drawer: address pair,
  model, character pack, and "Xóa lịch sử trò chuyện".
- The last 50 messages are loaded on open. The page reconnects by itself (1 s, 2 s, 5 s,
  then every 10 s) when the backend restarts.
- Enter sends, Shift+Enter adds a line. While Saki is answering, the Send button is
  disabled; pressing Enter with a new message stops the current answer (the page waits
  for its `cancelled`, at most 3 s) and then sends the new one.
- Model output is only ever inserted as text, never as HTML. The page has a strict
  Content-Security-Policy (same origin only).

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
  characters\      optional character packs, see "Gói nhân vật"
```

`config.json` is optional. Any key you leave out keeps its default:

```json
{
  "port": 8765,
  "open_browser": true,
  "llm_backend": "ollama",
  "model": "saki",
  "ollama_url": "http://127.0.0.1:11434",
  "llamacpp_url": "http://127.0.0.1:8080",
  "self_name": "Saki",
  "user_name": "bạn",
  "character_pack": "default",
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

`self_name`, `user_name`, `character_pack`, `llm_backend`, `model` and `port` are defaults only. Values
saved with `/xh` or `PUT /settings` are stored in SQLite and take precedence. The server
always binds to `127.0.0.1`.

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
```

Sending a new `user_message` while a reply is still streaming cancels that reply first.

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
| `GET /health` | `{"status":"ok","version":"0.1.0","llm":{"backend":"ollama","model":"saki","reachable":true,"model_available":true,"detail":""},"hardware":{"free_ram_gb":1.83,"tier":"small","model_hint":"qwen2.5-0.5b","warning":null}}` |
| `GET /settings` | `{"self_name":"Saki","user_name":"bạn","character_pack":"default","llm_backend":"ollama","model":"saki","port":8765}` |
| `PUT /settings` | partial body, e.g. `{"self_name":"em","user_name":"anh"}` → new settings plus `"restart_required": bool` (true when the port changed). 400 with a Vietnamese `detail` for invalid values, including a `character_pack` that is unknown or invalid |
| `GET /history?limit=50` | `{"messages":[{"role":"assistant","content":"...","emotion":"happy","kind":"chat","created_at":1760890000.0}, ...]}`. `kind` is `chat` or `search`. `emotion` is set on assistant messages |
| `DELETE /history` | `{"ok":true}` |
| `GET /memories` | `{"memories":[{"id":1,"text":"...","created_at":...}]}` |
| `POST /memories` | `{"text":"..."}` → 201 with the memory, or 400 (empty, too long, store full) |
| `DELETE /memories/{id}` | `{"ok":true}` or 404 |
| `GET /characters` | `{"packs":[{"id":"default","name":"Saki (mặc định)","author":"Saki","builtin":true,"valid":true,"error":null}, ...]}`. Invalid user packs are listed with `valid: false` and a Vietnamese `error` |
| `GET /characters/{pack_id}/manifest` | the validated manifest with image URLs: `{"format":1,"id":"default","name":"...","author":"...","builtin":true,"idle_seconds":10,"default":"/characters/default/files/neutral.svg","emotions":{"neutral":"...","happy":"...",...}}`. All six emotions are present (missing ones point at `default`). 404 with `detail` if the pack is missing or invalid |
| `GET /characters/{pack_id}/files/{filename}` | one image referenced by the manifest, with the right `Content-Type` and `X-Content-Type-Options: nosniff`. Anything else is 404 |
| `GET /`, `GET /static/...` | the web chat page |

Hardware tiers by free RAM: under 1.2 GB is `insufficient` (with a warning), 1.2–2.5 GB
is `small` (0.5B model recommended), above that is `standard` (1.5B). The backend only
reports the tier; it never switches models by itself.

## Gói nhân vật

Ảnh nhân vật được nạp từ một "gói": một thư mục chứa `manifest.json` và các tệp ảnh.
Gói `default` có sẵn trong app (ảnh SVG tạm, chỉ là khuôn mặt đơn giản). Để dùng ảnh
của bạn:

1. Tạo thư mục `%APPDATA%\Saki\characters\<tên-gói>\`. Tên gói chỉ gồm chữ không
   dấu, số, `-` và `_` (ví dụ `saki-ao-dai`).
2. Chép ảnh vào thư mục đó và viết `manifest.json`:

   ```json
   {
     "format": 1,
     "name": "Saki",
     "author": "",
     "default": "neutral.png",
     "idle_seconds": 10,
     "emotions": {
       "neutral": "neutral.png",
       "happy": "happy.png",
       "sad": "sad.png",
       "thinking": "thinking.png",
       "surprised": "surprised.png",
       "embarrassed": "embarrassed.png"
     }
   }
   ```

3. Mở **Cài đặt → Nhân vật** trên trang chat, chọn gói rồi bấm **Lưu**.

Quy tắc:

- `format` phải là `1`. `name` bắt buộc (tối đa 50 ký tự), `author` tùy chọn.
- `default` là ảnh bắt buộc. Cảm xúc nào không khai báo trong `emotions` sẽ dùng ảnh
  `default`, nên một gói chỉ có `neutral.png` vẫn chạy được. Khai báo cảm xúc lạ (ngoài
  6 cảm xúc trên) làm gói không hợp lệ.
- `idle_seconds` (1–3600, mặc định 10): sau bao nhiêu giây không có gì mới thì nhân vật
  quay về `neutral`.
- Chỉ nhận ảnh `.png`, `.jpg`, `.jpeg`, `.webp`, `.gif`, mỗi ảnh tối đa 5 MB.
  `manifest.json` tối đa 64 KB. Gói người dùng **không được dùng SVG** (SVG có thể chứa
  mã script). GIF/WebP động vẫn chạy bình thường. Chưa hỗ trợ sprite sheet.
- Tên tệp chỉ gồm chữ không dấu, số, `-`, `_` và một dấu chấm trước đuôi. Ảnh phải nằm
  ngay trong thư mục gói (không dùng thư mục con hay symlink).
- Gói sai quy tắc vẫn hiện trong danh sách kèm lý do lỗi, nhưng không được nạp. Trang chat
  khi đó dùng gói `default`. Không thể đặt tên gói là `default` (tên của gói có sẵn).

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
full WebSocket/REST flow, the web page and static files, character pack validation and
file-serving security, and the browser-opening startup logic. A fixture makes any test
that tries to open a real browser fail.

### Kiểm tra thủ công (trang chat)

Chạy `python -m saki` (Ollama đang chạy, đã có model `saki`), rồi kiểm tra:

- [ ] Trình duyệt tự mở `http://127.0.0.1:8765/`. Trạng thái hiện "Sẵn sàng".
- [ ] Gửi "Xin chào": chữ hiện dần, ảnh nhân vật chuyển sang "thinking" rồi sang cảm xúc
      của câu trả lời, khoảng 10 giây sau quay về "neutral".
- [ ] `/se thời tiết Hà Nội` và `/news giá vàng`: trạng thái "Đang tìm kiếm...", dưới câu
      trả lời có danh sách nguồn bấm được (mở tab mới), nguồn trả phí có "(trả phí)".
- [ ] Gửi một câu dài rồi bấm **Dừng**: câu trả lời có "(đã dừng)", nút Gửi dùng lại được.
- [ ] Đang trả lời thì gõ câu mới và Enter: câu cũ dừng, câu mới được trả lời.
- [ ] `/rmb Tên tôi là Minh`: tin nhắn hệ thống hiện ra, mở **Ghi nhớ** thấy mục mới.
      Xóa một mục (có hỏi xác nhận).
- [ ] **Cài đặt**: đổi xưng hô thành `em` / `anh`, lưu, hỏi Saki một câu xem cách xưng
      hô. Đổi mô hình sang tên không tồn tại: câu sau báo lỗi bằng tiếng Việt. Đổi lại
      `saki`.
- [ ] Tắt backend (Ctrl+C) khi trang đang mở: trạng thái "Mất kết nối với Saki", nút Gửi
      bị khóa. Chạy lại `python -m saki --no-browser`: trang tự kết nối lại.
- [ ] Tắt Ollama rồi tải lại trang: trạng thái "Chưa kết nối được với mô hình", gửi tin
      nhắn thì hiện lỗi tiếng Việt.
- [ ] Tạo gói `%APPDATA%\Saki\characters\thu\` chỉ có `neutral.png` và `manifest.json`
      tối thiểu, chọn trong **Cài đặt**: ảnh đó hiện cho mọi cảm xúc.
- [ ] Thu cửa sổ còn khoảng 360 px: vẫn dùng được, không có thanh cuộn ngang.
- [ ] Đổi Windows sang chế độ tối: trang đổi màu theo.
- [ ] Tải lại trang: 50 tin nhắn gần nhất hiện lại.
- [ ] Chạy `python -m saki` lần thứ hai khi Saki đang chạy: in "Saki đang chạy sẵn ở ..."
      và mở trang, không có traceback.

## Project layout

```
saki/
  __main__.py      start the server, open the browser, handle a busy port
  config.py        AppConfig, app-data paths, logging
  settings.py      editable settings (shared by /xh and PUT /settings)
  prompts.py       system prompt + search prompt builders
  commands.py      command parsing and non-LLM handlers
  postprocess.py   emotion tag, cleanup, rewrites, sources, streaming
  context.py       context-window trimming
  chat.py          one chat turn (transport-agnostic)
  server.py        FastAPI app: /ws + REST + web page
  characters.py    character packs: discovery, validation, safe file lookup
  storage.py       SQLite
  hardware.py      free RAM -> tier; ModelProvisioner interface (TODO)
  cli.py           terminal client
  llm/             base.py, ollama.py, llamacpp.py, fake.py
  search/          models.py, ddg.py, rss.py, news.py, service.py, cache.py, sources.json
  packs/default/   built-in placeholder pack (manifest.json + one SVG per emotion)
  web/             index.html, style.css, favicon.svg,
                   js/ main.js, api.js, chat.js, character.js, panels.js
tests/
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
