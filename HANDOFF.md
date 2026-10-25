# Handoff: Saki

Last updated: 2026-10-25. For whoever picks up this repo next. How to run the backend and
the protocol are in [README.md](README.md). This file covers the current state, what
changed recently, and what is still open.

## Godot app round (`feature/godot-app`): phase 1 done, awaiting desktop check

Spec: `plan/godot_app_phase1_prompt.md` (not in git). Godot **4.7.2-stable** (installed
on the dev machine at `D:\App\Godot 4.7.2\`), Compatibility renderer, GDScript only, GUT
9.7.1 as dev-only test addon. The app lives in `app/`.

### Stages

| # | Stage | State |
|---|---|---|
| 1 | Backend: remove web UI and `/characters`, `protocol_version`, `/history?before=`, `POST /shutdown` | done |
| 2 | Godot project skeleton: `core/` (EventBus, constants), `App` composition root, settings service + migration, translations, GUT setup | done |
| 3 | Packs: manifest parser/validator, zip validator, importer (thread), index cache, loader, fallback chain, test-pack generator | done |
| 4 | Renderers: base class, registry, placeholder, 2d, unsupported fallback | done |
| 5 | Backend service: process manager, `BackendClient` (fake transport in tests), reconnect | done |
| 6 | Performance: tier resources, auto selection, FPS controller, debug overlay | done |
| 7 | Shared UI components: message list (paging, node cap), bubble, sources, input, status, memories, settings, pack manager | done |
| 8 | Modes: chat window, desktop pet (transparency, passthrough, drag, scale, menu, speech bubble, mini chat), switching | done |
| 9 | Global hotkey (backend `RegisterHotKey`), desktop shortcut, export preset, icon | done |
| 10 | Docs (ARCHITECTURE, PACK_GUIDE, GODOT_BEGINNER), measurements, final README/HANDOFF | done (not committed) |

Where it stopped (2026-10-25): stages 1–9 are committed (stage 9 = `d49003e`). Stage 10
is finished and tested but **not committed**. Suggested message:
`Docs (architecture, pack guide, Godot beginner guide), measurements, final README/HANDOFF`.
All stages of the spec are done. What is left needs a person at the desktop (see "Not
verified" under stage 8 and 9) and the export templates (GODOT_BEGINNER.md section 5).

Working rules from the owner: **Claude does not commit or push**; at the end of each stage
it runs the tests, updates this file and gives a suggested commit message.

### Spec deviations and notes (decided while planning)

1. **History paging needs the backend.** `GET /history` only had `limit`. Added an optional
   `before=<id>` and an `id` field per message (additive, old clients unaffected).
2. **Graceful backend stop.** `pythonw.exe` has no window or console, and Windows has no
   SIGTERM, so "graceful first" needs an endpoint: `POST /shutdown`, which exists only if
   the launcher set `SAKI_SHUTDOWN_TOKEN` and sends it as `X-Saki-Token` (a web page cannot
   send that header cross-origin without a CORS preflight, which fails). Fallback after a
   timeout: `taskkill /T /F /PID`.
3. **No working directory in `OS.create_process`.** The app sets `PYTHONPATH=<repo>` before
   starting `pythonw -m saki` instead.
4. **`ZIPReader` hides zip metadata** (symlink flags, declared sizes, duplicate names). The
   validator parses the zip central directory itself and uses `ZIPReader` only to extract
   files that already passed every rule.
5. **"Occluded" cannot be detected** by Godot. Rendering stops when the chat window is
   minimized; unfocused uses the idle rate.
6. **Busy FPS 5–10 also slows the streaming text** to 5–10 updates per second. Acceptable;
   it is per-tier data.
7. **Global hotkey** through the backend (`ctypes` + `RegisterHotKey`, no compilation).
   Protocol additions, both optional: client→server `hotkey_config`, server→client
   `hotkey` and `hotkey_status`.
8. **Mouse passthrough takes one polygon.** The pet builds an x-monotone outline (left and
   right edge per row band) from the character alpha, with the speech bubble rectangle
   merged in.
9. Model suggestions `saki-lite`/`saki-standard` still do not exist (see "Suggested next
   steps" 7); they are only suggestions in a free-text field.

### Stage log

- **Stage 1 (backend).** Removed `saki/web/`, `saki/packs/`, `saki/characters.py`, `GET /`,
  `/static`, `/characters*`, the `character_pack` setting, `open_browser` and
  `--no-browser`, and their tests. A `character_pack` row in old databases is never read;
  removed keys in old `config.json` are skipped silently. Added `protocol_version: 1` to
  `/health`, `before` paging and `id` to `/history`, `POST /shutdown` (token), and no
  console log handler under `pythonw`. `pytest`: 158 passed.
- **Stage 2 (skeleton).** `app/project.godot` (Compatibility renderer, `user://` =
  `%APPDATA%\Saki`, low-processor mode, per-pixel transparency allowed, subwindows not
  embedded, log to `user://logs/app.log`). Autoloads: `EventBus` (typed signals) and `App`
  (composition root; `boot()` is called by `main.gd`, so tests start nothing).
  `SettingsService` (versioned JSON, write-then-rename, type sanitising, migration 0→1).
  `i18n/strings.csv` (keys → Vietnamese) with a test that every `tr("KEY")` exists. GUT
  9.7.1 in `app/addons/gut/`; run `app/run_tests.ps1`. GUT: 10 passed.
- **Stage 3 (packs, `app/services/packs/`).** `PackRules` (limits, path rules),
  `PackManifest` (format 1 parser; errors name the field; unknown fields ignored; newer
  format = unsupported; non-2d types only need common fields), `ZipInspector` (reads the
  zip central directory: sizes, symlink bits, encryption, ZIP64), `PackValidator` (zip and
  folder; traversal, absolute/drive paths, backslashes, symlinks, case-insensitive
  duplicates, extensions, sizes, file count, zip-bomb ratio, manifest size, referenced
  files exist; a zip with the pack inside one top-level folder is accepted),
  `ImageProbe` (size from the header before decoding; decode by magic bytes),
  `PackImporter` (extract to `.incoming_*`, re-encode every image, downscale above 4096 px
  keeping sheet grids exact, thumbnail, SHA-256, swap into place), `PackIndex`
  (`index.json`, re-validates only packs whose manifest mtime changed), `PackData`
  (lazy textures per animation, tier downscale on load, fallback chain, states override),
  `PackService` (activate/unload, import on a `Thread`, delete, dev reload), wired into
  `App.boot()`. Frame lists use the ordered-list form only (no pattern form). The `idle`
  state overrides only the resting emotion. Tools: `app/tools/generate_test_packs.gd`
  (`godot --headless --path app -s res://tools/generate_test_packs.gd -- --count 200`).
  Measured here: 200 packs, warm list 32 ms, cold first scan 2.2 s. GUT: 37 passed,
  `pytest`: 158 passed. Note: tests write under `%APPDATA%\Saki\test_tmp` (cleaned per
  test) and a headless boot created `characters\`, `characters_dev\`, `index.json` and
  `app_settings.json` in `%APPDATA%\Saki`.
- **Stage 4 (renderers, `app/renderers/`).** `CharacterRenderer` (Control; API
  `load_pack`, `set_emotion`, `set_state`, `set_quality`, `get_visible_rect`,
  `get_alpha_outline`, `natural_size`, `unload`; signal `visual_changed`; draws aspect-fit
  aligned by the pack anchor). `RendererRegistry` (`RENDERERS` table type → script path;
  missing script or unknown type → `FallbackRenderer`: thumbnail + "Loại gói này chưa được
  hỗ trợ"). `sprite_2d/` (static, sheet, frames; animates only with more than one frame and
  when the tier allows; shows the placeholder as a child when the pack has nothing
  usable). `placeholder/` (code-drawn face per emotion/state, blink, talking mouth, bob;
  redraws only on visible changes). `core/alpha_outline.gd`: x-monotone outline per frame,
  computed once at load in `PackData` (no GPU read-back later). `QualityTier` Resource
  class added (tier files come in stage 6). GUT: 46 passed (incl. each renderer standalone
  in an empty scene, a simulated deleted renderer folder, a broken pack).
- **Stage 5 (backend service, `app/services/backend/`).** Interfaces `WsTransport`
  (real: `WebSocketTransport`), `HttpTransport` (real: `HttpRequestTransport`; also
  `port_open()` TCP check) and `ProcessLauncher`, so tests use fakes
  (`tests/helpers/fakes.gd`). `BackendClient`: health check → protocol check → WebSocket;
  reconnect 1/2/5/10 s; defensive event parsing (unknown types ignored); supersede (cancel,
  wait for the terminal event ≤ 3 s, then send); socket loss mid-turn ends the turn with
  "Mất kết nối với Saki"; REST helpers return the backend's Vietnamese `detail`.
  `BackendProcess`: finds the repo (setting, else the project folder / .exe folder and up to
  4 parents), probes the port (TCP, then `/health`: Saki → use it, not owned; anything else
  → "Cổng ... đang bị một ứng dụng khác sử dụng"), starts `pythonw -m saki --port N` with
  `PYTHONPATH` and a random `SAKI_SHUTDOWN_TOKEN`, waits up to 90 s, watches it once per
  second and only reports a crash; `stop()` = blocking `POST /shutdown`, wait 3 s, then
  `taskkill /T /F`. Wired into `App.boot()` (`start_backend()` is the "Khởi động lại"
  action; `shutdown()` on window close). Finding: on Windows a refused connection to
  127.0.0.1 shows up in `HTTPRequest` as a timeout (result 13) after about 1.5 s, hence the
  TCP check. Real-backend check `app/tools/backend_smoke.gd` (throwaway `SAKI_DATA_DIR`):
  started hidden in 7.3 s, protocol 1, `/help` answered, graceful stop 346 ms, no process
  left. GUT: 70 passed.
- **Stage 6 (performance, `app/services/performance/`).** Tiers are data:
  `tiers/low.tres`, `medium.tres`, `high.tres` (`QualityTier`: idle/active/busy FPS,
  max texture size, filtering, animations, effects). `TierSelector` (pure): free RAM,
  GPU name and a 45-frame benchmark can each only lower the tier; FPS priority minimized >
  busy > active (input in the last 1.5 s) > idle. `PerformanceService` sets
  `Engine.max_fps` and the low-processor sleep, turns `RenderingServer.render_loop_enabled`
  off while the chat window is minimized (the pet never counts as minimized), and listens
  to `busy_changed`. `App` connects `quality_tier_changed` to the pack texture limit and the
  `quality` setting to the service; first run (no `auto_tier`) runs the detection after
  the window appears. `ui/debug_overlay/` (F3, remembered): FPS and cap, static and
  texture memory, tier, state, active pack. Findings on the dev machine: Godot uses ANGLE
  (Direct3D 11) on the HD 4000 because of its OpenGL driver (automatic, works);
  `OS.get_memory_info()["available"]` includes the page file on Windows (15.5 GB on an
  8 GB machine), so `free` is used. Auto detection here: frame 16.4 ms, HD 4000 → medium.
  First real windowed run (empty window, no UI yet, backend on a throwaway data folder):
  backend started and ready in 5.4 s, app working set 134 MB, idle CPU 0 % over 10 s,
  no `pythonw` left after exit. GUT: 77 passed, `pytest`: 158 passed.
- **Stage 7 (shared UI).** Non-UI logic in `app/services/chat/`: `ChatSession` (message
  model shared by every mode; streaming, `reset`, authoritative `end`, "(đã dừng)",
  errors; `load_recent` / `load_older` history paging; `/rmb` and `/fgt` system replies
  emit `memories_changed`) and `MoodController` (thinking/talking/idle, turn emotion,
  idle timeout per pack, click reactions). Components in `app/ui/` get a `UiContext`
  (services + app actions) instead of using the `App` autoload: `chat/MessageBubble`
  (plain-text `Label`s, ``` blocks monospace, right-click copies), `SourcesList`
  (http/https only), `MessageList` (window of at most 120 live nodes, moves 10 messages per
  step, asks for older pages at the top), `ChatInput` (Enter / Shift+Enter, Dừng only
  while busy), `StatusLine` (+ "Thử lại" / "Khởi động lại"; wording in the tested
  `StatusModel`), `ChatPanel` (the composition both modes use, `compact` for the pet),
  `character/CharacterView`, `panels/MemoriesPanel`, `SettingsPanel`, `PackManager`,
  `common/PanelWindow` (native window per panel), `theme/` (`light.tres`, `dark.tres`,
  `ThemeBuilder`; "Theo Windows" follows dark mode live), `ChatFormat` helpers. `App`
  creates the session, mood, `UiContext` and theme; history reloads on every connect.
  Finding: 20 `RichTextLabel` bubbles (fit_content) took ~245 ms to lay out vs ~29 ms for
  `Label`, so bubbles use `Label` (selection replaced by right-click copy). Windowed
  benchmark `app/tools/message_list_bench.gd` (1,000 messages, 60 px per frame down to the
  first message and back): median 16.6 ms, p95 17.7 ms, 39 of 5,201 frames over 33 ms
  (max 142 ms, when the window shifts), never more than 120 live nodes. GUT: 100 passed,
  `pytest`: 158 passed.
- **Stage 8 (modes).** `modes/display_mode.gd` (interface: `enter`, `exit`,
  `show_message`, `show_notice`, `open_panel`, `on_hotkey`), `modes/chat_window/`
  (character panel + name + status line, chat panel, header buttons, remembered rect with
  off-screen fallback, character strip on top below 680 px) and `modes/pet/` (borderless,
  per-pixel transparent, always on top by default, size = character × scale (+ bubble),
  position stored as the character's bottom-centre so the bubble grows upwards, drag with
  a 5 px threshold so a drag is never a click, click = `surprised` 1.5 s + mini chat when
  idle, Ctrl + wheel scale (saved 0.6 s after the wheel stops), right-click menu, speech
  bubble with "…xem tiếp", mini chat = the shared `ChatPanel` in a native window next to
  the pet, click-through polygon = alpha outline + bubble via `WindowService`, updated at
  most every 0.1 s). `services/platform/window_service.gd`: multi-monitor fit, default
  pet corner, passthrough polygon merge. `main.gd` hosts the modes (`MODES` table, start in
  the last mode, switch without touching session/backend, .sakip drag-and-drop, notices,
  hotkey, quit). `SettingsService.set_value(..., persist=false)` for live values.
  Findings: (1) `Main` is a plain `Node`, so neither anchors nor themes reach the mode:
  `main.gd` sizes the mode to the viewport and sets `mode.theme` itself. (2) headless
  Godot reports its window as minimized. (3) GUI automation from outside the app is not
  usable on the dev machine: Windows blocks `SetForegroundWindow`, so screen captures and
  `SendKeys` hit the owner's other windows (this happened once; stopped). Instead
  `app/tools/ui_snapshot.gd` saves PNGs of the app's own windows (off-screen, no focus,
  throwaway backend data, restores `app_settings.json`): chat after `/help`, the three
  panels, the pet with and without bubble. Checked visually: layout, Vietnamese text,
  light theme, pet PNG alpha 0 in the corner and 1 on the character. Fixed from the
  snapshots: theme not applied, mode not filling the window, check boxes drawn as buttons.
  GUT: 107 passed, `pytest`: 158 passed.

  Owner decision after review: the backend folder is no longer in Settings. The app
  finds it by itself (a saved folder that is no longer valid falls back to searching);
  only when nothing is found, the status line shows "Không tìm thấy backend Saki..." with
  a **Chọn thư mục...** button (`CONN_NOT_FOUND`, action `pick_backend_dir`). Spec 3 is
  still met (ask only when not found), without the setting cluttering the panel.

  **Not verified (needs a person at the desktop):** pet transparency as composited by
  Windows (ANGLE/D3D11), click-through on transparent pixels, drag, Ctrl + wheel,
  right-click menu, always-on-top, mini chat placement, .sakip drag-and-drop, multi-monitor
  restore, dark theme on screen.
- **Stage 9 (hotkey, shortcut, export, icon).** Backend `saki/hotkey.py`: combo parser,
  `WindowsHotkeyBackend` (`RegisterHotKey` on its own message-loop thread via ctypes,
  `AllowSetForegroundWindow` on a press so the app may come to the front), `HotkeyManager`
  (Vietnamese status: not Windows / invalid / in use). Server: client→server
  `hotkey_config`, server→client `hotkey_status` and `hotkey` (broadcast); released when the
  last client disconnects; README protocol updated. App: sends the setting on every
  connect and when it changes; `hotkey_status` failures become a notice; chat mode
  toggles minimize/front, pet mode opens the mini chat. `services/platform/desktop_shortcut.gd`:
  PowerShell + `WScript.Shell` .lnk with the exe icon, only for the exported .exe (from the
  editor it says so). `tools/make_icon.gd` renders `assets/icon.svg` into
  `assets/icon.ico` (16–256 px); `project.godot` uses it as the window icon.
  `app/export_presets.cfg` (Windows x86_64, PCK embedded, excludes GUT/tests/tools,
  includes `packs/*/manifest.json`, icon, version info, ANGLE auto). Checked for real:
  `RegisterHotKey` register / conflict ("đang được một chương trình khác dùng") / release
  with Ctrl+Alt+Shift+F24; registration through the real backend from Godot
  (`tools/backend_smoke.gd`); the generated shortcut command against a temp folder
  (target, working dir and icon correct); `.ico` read by System.Drawing; the preset parses
  (export stops only at "No export template found"). **Not done here:** an actual export,
  because the 4.7.2 export templates are 1.28 GB (owner step in GODOT_BEGINNER.md); a real
  key press of the hotkey (no input injection into the owner's session).
  pytest: 161 passed, GUT: 110 passed.
- **Stage 10 (docs, measurements).**
  - Vietnamese docs:
    - `app/ARCHITECTURE.md`: module diagram, layer rules with a grep check, every
      EventBus signal and who emits it, the flow of one chat turn, the Modularization,
      Scalability and Reusability checks, and "Thêm một bộ vẽ mới trong 5 bước".
    - `app/PACK_GUIDE.md`: every manifest field with its limits, the three entry kinds,
      how states override emotions, the limits table, `.sakip` zipping, folder mode, and
      the common error messages.
    - `app/GODOT_BEGINNER.md`: Godot 4.7.2 install, open/run, GUT, tools, export
      templates, export, shortcut, file locations, troubleshooting.
  - README: new "Desktop app" section with the measurements, plus app limitations.
  - New tool `app/tools/measure.gd`: real app, throwaway backend data, windows
    off-screen, no input; restores `app_settings.json`.
  - Fixes found while writing:
    - The built-in pack's images were not downscaled to the tier limit; now they go
      through `PackData.fit_image` like user packs.
    - `BACKEND_PORT_BUSY` said to change the port "trong Cài đặt", but Settings has no
      port field; it now points to `app_settings.json`.
  - Measurements: two runs, 10 s per idle phase, 5 s per busy phase; busy =
    `busy_changed(true)`, the FPS state during a turn.

    | | Chat window | Desktop pet |
    |---|---|---|
    | App working set | 158–162 MB | 153 MB |
    | CPU, idle | 0–0.5 % of one core | 0 % |
    | CPU, busy | 0–0.3 % | 0–1 % |
    | Main loop, idle / busy | 12.2 / 8.4 per s | 12.2 / 8.4 per s |

    - Loop rates equal the "Vừa" tier caps (12 idle, 8 busy). Low-processor mode only
      redraws when something changed.
    - Godot static memory: 40 MB.
    - Backend (venv `pythonw` launcher + interpreter, no model loaded): 61 MB. Started
      and ready in 5.4 s.
    - No `pythonw`/`python` left after exit.
    - Earlier numbers still hold: 200 packs list in 32 ms (cache) / 2.2 s (first scan);
      1,000 messages scroll at a median of 16.6 ms per frame.
    - Not measured: a real model turn (Ollama's own RAM/CPU dominates and depends on the
      model, not on the app).

  pytest: 161 passed, GUT: 110 passed.

### Known limitations of the app (phase 1)

- Pet transparency, click-through, drag, Ctrl + wheel, always-on-top, multi-monitor
  restore, `.sakip` drag-and-drop and the dark theme on screen are implemented and
  unit-tested, but not yet checked by a person (see stage 8).
- No real export yet: the templates are not installed here. The preset parses.
- `rcedit` may be needed for the `.exe` icon (GODOT_BEGINNER.md section 6).
- Click-through takes one x-monotone polygon. Characters with holes (e.g. between arm and
  body) catch clicks in the hole.
- Busy FPS (5–10) also slows the streaming text to 5–10 updates per second.
- Selecting text in a bubble is not possible (`Label`); right-click copies the message.
- The backend must be a repo checkout with `.venv`; there is no bundled Python yet.
- The port is only changeable in `app_settings.json`.
- The built-in pack (`app/packs/default/`) has no images yet, so the code-drawn
  placeholder is shown.

### Next phases

1. **1b: llama-server.** Backend-managed `llama-server` with the bundled 1.5B GGUF (no
   Ollama in the release app), model provisioning and update/rollback through
   `ModelProvisioner`, a bundled Python (embeddable or frozen) so the `.exe` needs no repo.
2. **2: glTF.** A `3d-gltf` renderer (`renderers/gltf/`, one registry line, see
   ARCHITECTURE.md section 6), emotion → animation mapping in the manifest.
3. **3: VRM.** VRM avatars (blend shapes for emotions, look-at), probably on top of the
   glTF renderer.
4. **4: Live2D.** Needs the Cubism SDK (licence and a native GDExtension): check the
   licence before starting.

Also still open from earlier: the `Origin`/`Host` check on the local server ("Suggested
next steps" 6) and the model-name suggestions (7).

## Earlier rounds

### State before the Godot round

- Backend MVP works end to end: FastAPI WebSocket `/ws` + REST, Ollama and llama-server
  adapters, `/se` and `/news` search, memories, address pair (`/xh`), dev CLI.
- Web chat page served by the backend at `http://127.0.0.1:8765/` (branch
  `feature/web-ui`), with character packs. `python -m saki` opens it automatically.
- `pytest`: 196 tests pass and 1 is skipped (the symlink test needs symlink rights on
  Windows), offline (no network, no Ollama).
- Live-tested on the dev machine (i5-3360M, 8 GB RAM) against Ollama model `saki`.

### Web UI round (`feature/web-ui`)

Spec: `plan/frontend_prompt.md` (not in git). All additive: the WebSocket protocol and
the old REST endpoints are unchanged.

1. **Web page** in `saki/web/`: plain HTML/CSS/ES modules, no build, no CDN. Modules:
   `api.js` (REST), `chat.js` (rendering, `Connection` with reconnect, `ChatController`
   turn state machine), `character.js` (image per emotion, idle return), `panels.js`
   (memories and settings drawers), `main.js` (wiring, status line). Served at `/` with a
   strict CSP and at `/static/*`. `.js`/`.css`/`.svg` MIME types are forced because the
   Windows registry can map `.js` to `text/plain`. (`test_web`)
2. **Superseding a turn.** The backend gives no turn IDs, and a task cancelled before it
   starts emits nothing. So the page never overlaps turns: a new message sent while a
   turn runs first sends `cancel`, waits for that turn's terminal event (at most 3 s, then
   it ends the turn locally) and only then sends `user_message`. The Stop button uses the
   same 3 s fallback.
3. **Character packs** (`saki/characters.py`, built-in `saki/packs/default/`). New
   endpoints `GET /characters`, `GET /characters/{id}/manifest`,
   `GET /characters/{id}/files/{filename}`. User packs: strict id/filename regex, raster
   images only (no SVG), 5 MB per image, 64 KB manifest, files must sit directly in the
   pack folder (symlinks rejected), and only files referenced by the manifest are
   served. Packs are re-read on every request (no cache). (`test_characters`)
4. **New settings/config keys.** `character_pack` (settings + config, validated against
   valid packs; `GET /settings` now includes it, so `test_rest_settings` was updated
   for the extra key). `open_browser` (config only) plus `--no-browser`.
5. **Startup** (`__main__.py`): opens the browser from a thread that waits for
   `uvicorn.Server.started`. If the port is busy it checks `GET /health`: a running Saki
   gets the browser opened, anything else gets a Vietnamese message and exit code 1. An
   autouse fixture in `tests/conftest.py` fails any test that opens a browser.
   (`test_main`)

Verified in headless Chrome (CDP script against the real app with a fake LLM; not in
the repo): streaming, a `reset` after a repeated reply (no doubled text), code blocks,
`/news` sources (dated, paywalled, `javascript:` URL not linked), `/rmb` refreshing the
memories list, Stop, superseding, settings save and 400 errors, pack switch with
missing-emotion fallback, history on reload, reconnect after a server restart, 360 px
width, dark mode, no console errors. **Not verified:** Firefox, and a real Ollama model
behind the page.

### Changes in the review round (from real-use review)

Each item has tests. Test file in brackets.

1. **Emotion tags in history.** `messages` now has `emotion` and `kind` columns (old
   databases are migrated automatically). Assistant replies are stored without the tag,
   and the tag is re-attached as `[emotion] text` when building context, so the model
   sees the same shape it was trained on. (`test_storage`, `test_context`, `test_server`)
2. **Search turns are kept out of later context.** `/se` and `/news` turns are stored with
   `kind="search"`. They still show in `GET /history`, but `history_for_context` skips
   them. (`test_context`, `test_server::test_search_turn_not_in_later_context`)
3. **`Nguồn:` stripping on every turn.** The model sometimes made up a sources line in
   normal chat (e.g. `Nguồn: [1] /healthline.com`). Now `strip_sources=True` is always
   on. (`test_server::test_chat_turn_drops_model_written_sources`)
4. **Anti-repetition.** (`test_server`, `test_llm`, `test_cli`)
   - Context is capped at the last 3 chat turns (`context_max_turns`).
   - `repeat_penalty: 1.15` and `repeat_last_n: 128` go to Ollama; `repeat_penalty` goes
     to llama-server.
   - If a reply is ≥ 0.9 similar (accent-folded, `difflib`) to one of the last 5 replies,
     it is regenerated **once** at temperature 0.7 without history. The client gets a new
     `{"type":"reset"}` event: discard the text streamed so far, then a new `start` and
     `delta`s follow. This is a **protocol addition** and is documented in the README.
5. **`/news` quality.** (`test_search`, `test_postprocess`, `test_cli`)
   - At most 2 results per source, and `lang: "vi"` sources first (`rank()` in
     `search/news.py`).
   - The RSS keyword filter matches the **title only**. Matching the summary let in
     off-topic items, e.g. a Selena Gomez story for `/news thời tiết`.
   - Sources payload has a new `display_url` field: the publisher domain for Google News
     redirect links, the real URL otherwise. `url` is unchanged and still clickable.
6. **CLI**: a blank line after the sources list, so it no longer runs into the `>`
   prompt. Uses `display_url`, and prints a note on `reset`.

Live check after these changes: all four results for `/news thời tiết` were on topic,
Google News items showed publisher domains, and asking "Bạn khỏe không" and then
"Khỏe không" gave two different answers.

## Known issues

- **The model is still the weak point.** It invents facts (e.g. a clock time in a
  weather summary), barely uses `[BỘ NHỚ]` (only 2 training examples), and confuses
  roles ("Anh là Saki"). These are training-data problems, not backend bugs.
- Regeneration happens after the first reply has already streamed, so the user briefly
  sees the repeated text before `reset`. On this CPU it doubles the wait for that turn.
- Uvicorn prints a `KeyboardInterrupt`/`CancelledError` traceback on Ctrl+C. It is
  harmless.
- Windows dev-machine gotcha: WinNAT (Hyper-V/WSL) can reserve ports 11119–12118,
  including Ollama's 11434 (`bind: forbidden`). Fix: `net stop winnat` and
  `net start winnat` as admin, or run Ollama on another port (`OLLAMA_HOST`) and set
  `ollama_url` in `%APPDATA%\Saki\config.json`.
- With under about 1.2 GB of free RAM, first replies can take minutes because of
  swapping.

## Decisions to respect

- The app ships with **only the 1.5B q4_k_m GGUF** bundled in the installer. There is
  **no 0.5B fallback**. The `small → qwen2.5-0.5b` hint in `hardware.py` should become a
  plain minimum-RAM warning.
- The release app uses **llama-server, managed by the backend** (no Ollama in the app).
- Model updates: the app asks before updating, shows change notes, and offers rollback.
  From v4 on, the plan is a fixed base model plus one LoRA adapter per version. Training
  files (`*.jsonl`, `gen_saki_data.py`) stay on the developer's machine.

## Suggested next steps

1. Retrain with more `[BỘ NHỚ]` examples, `/rmb` and `/fgt` instead of `/nho` and
   `/quen` (then remove `rewrite_commands`), multi-turn chat examples whose assistant
   turns keep their tags, and "no results / undated results" search examples.
2. Backend-managed `llama-server` process (start, health-wait, restart, port selection)
   for the release build.
3. Replace the 0.5B tier hint with a minimum-RAM warning in `hardware.py`.
4. Model update and rollback flow (manifest with `prompt_version` and
   `min_app_version`). The `ModelProvisioner` interface in `hardware.py` is the hook.
5. ~~Frontend~~: done as the Godot app in `app/` (this round). Remaining: the desktop
   check and a real export (see "Known limitations of the app").
6. Security hardening of the local server: there is no `Origin` check on `/ws` and no
   `Host` check, so any website open in the browser could connect to
   `ws://127.0.0.1:8765/ws` (or use DNS rebinding for REST) and read or change chat and
   memories. Check `Origin`/`Host` against `127.0.0.1`/`localhost` (this predates the
   web UI; it is not part of the protocol, so it can be added without breaking clients
   other than browsers on other origins).
7. The model suggestions in the settings dialog (`saki-lite`, `saki-standard`) come from
   the spec; they do not exist yet and conflict with the "1.5B only" decision. Replace
   them once model names are settled.
