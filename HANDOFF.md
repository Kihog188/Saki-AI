# Handoff: Saki backend

Last updated: 2026-10-20. For whoever picks up this repo next. How to run it and the
frontend protocol are in [README.md](README.md). This file covers the current state,
what changed recently, and what is still open.

## Current state

- Backend MVP works end to end: FastAPI WebSocket `/ws` + REST, Ollama and llama-server
  adapters, `/se` and `/news` search, memories, address pair (`/xh`), dev CLI.
- `pytest`: 149 tests pass, offline (no network, no Ollama).
- Live-tested on the dev machine (i5-3360M, 8 GB RAM) against Ollama model `saki`.

## Changes in this round (from real-use review)

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
5. Frontend (Godot/Unity) against the protocol in the README, including `reset`.
