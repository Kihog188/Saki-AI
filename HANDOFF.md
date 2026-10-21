# Handoff: Saki backend

Last updated: 2026-10-21. For whoever picks up this repo next. How to run it and the
frontend protocol are in [README.md](README.md). This file covers the current state,
what changed recently, and what is still open.

## Current state

- Backend MVP works end to end: FastAPI WebSocket `/ws` + REST, Ollama and llama-server
  adapters, `/se` and `/news` search, memories, address pair (`/xh`), dev CLI.
- Web chat page served by the backend at `http://127.0.0.1:8765/` (branch
  `feature/web-ui`), with character packs. `python -m saki` opens it automatically.
- `pytest`: 196 tests pass and 1 is skipped (the symlink test needs symlink rights on
  Windows), offline (no network, no Ollama).
- Live-tested on the dev machine (i5-3360M, 8 GB RAM) against Ollama model `saki`.

## Web UI round (`feature/web-ui`)

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

## Changes in the review round (from real-use review)

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
5. Frontend (Godot/Unity) against the protocol in the README, including `reset`. The
   web page and the character pack format (`format: 1`) are the reference.
6. Security hardening of the local server: there is no `Origin` check on `/ws` and no
   `Host` check, so any website open in the browser could connect to
   `ws://127.0.0.1:8765/ws` (or use DNS rebinding for REST) and read or change chat and
   memories. Check `Origin`/`Host` against `127.0.0.1`/`localhost` (this predates the
   web UI; it is not part of the protocol, so it can be added without breaking clients
   other than browsers on other origins).
7. The model suggestions in the settings dialog (`saki-lite`, `saki-standard`) come from
   the spec; they do not exist yet and conflict with the "1.5B only" decision. Replace
   them once model names are settled.
