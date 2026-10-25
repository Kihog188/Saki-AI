extends Node
## Global typed signals (autoload "EventBus").
##
## Services emit, UI and modes listen. Nobody calls another service directly through the
## bus: it only carries facts ("a delta arrived", "the active pack changed").
## The full list with the flow of one chat turn is in ARCHITECTURE.md.

# --- backend connection --------------------------------------------------------------

## state: one of SakiConst.CONN_*. message: Vietnamese text for the status line ("" = none).
signal backend_state_changed(state: StringName, message: String)
## Result of GET /health: whether the model server (Ollama) answers.
signal llm_reachability_changed(reachable: bool)

# --- one chat turn (mirrors the WebSocket events, see README "Protocol") ---------------

## state: "thinking" or "searching".
signal turn_status(state: String)
signal turn_started(emotion: String, system: bool)
signal turn_delta(text: String)
signal turn_reset()
signal turn_ended(emotion: String, text: String, sources: Array, system: bool)
signal turn_error(message: String)
signal turn_cancelled()

# --- app state -------------------------------------------------------------------------

## True while the backend works on a turn (thinking, searching or streaming).
signal busy_changed(busy: bool)
## What the character should show now (decided by MoodController).
signal character_emotion_changed(emotion: String)
signal character_state_changed(state: StringName)
## A short visual reaction (pet click). Not sent to the model.
signal character_reaction(emotion: String, seconds: float)

signal active_pack_changed(pack_id: String)
## The list of installed packs changed (import, delete, reload).
signal packs_changed()
## progress: 0..1. text: Vietnamese.
signal pack_import_progress(progress: float, text: String)
## ok, Vietnamese summary or error.
signal pack_import_finished(ok: bool, message: String)

signal memories_changed()
signal history_cleared()

## An app-owned setting changed (SettingsService.set_value).
signal setting_changed(key: String, value: Variant)
signal quality_tier_changed(tier: Resource)
signal theme_changed(theme: Resource)

## UI asks to switch display mode (SakiConst.MODE_*).
signal mode_change_requested(mode: StringName)
## UI asks to open a panel ("memories", "settings", "packs", "chat").
signal panel_requested(panel: String)
## The global hotkey was pressed (backend Windows hotkey).
signal hotkey_pressed()
## Vietnamese notice for the user (shown in the status line or a toast).
signal notice(text: String)
