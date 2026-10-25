class_name DisplayMode
extends Control
## Interface every display mode implements (chat window, desktop pet, later e.g. "mini").
## A mode is an independent scene/script: main.gd creates it, calls enter(), and calls
## exit() before switching to another mode. Chat state lives in ChatSession (App), so a
## switch never loses messages and never reconnects the backend.

var ctx: UiContext


## Configure the window and build the UI. `ctx` gives the services.
func enter(p_ctx: UiContext) -> void:
	ctx = p_ctx


## Save window state (position, size...) and release anything outside this node.
func exit() -> void:
	pass


## Show a Saki message prominently (chat: scroll to it; pet: speech bubble).
func show_message(_text: String) -> void:
	pass


## A short Vietnamese notice for the user (import done, hotkey unavailable...).
func show_notice(_text: String) -> void:
	pass


## Open a panel: "memories", "settings", "packs" or "chat".
func open_panel(id: String) -> void:
	var title_key: String = {"memories": "PANEL_MEMORIES", "settings": "PANEL_SETTINGS", "packs": "PANEL_PACKS", "chat": "PANEL_CHAT"}.get(id, "")
	if title_key == "":
		return
	var size: Vector2i = {"memories": Vector2i(460, 520), "settings": Vector2i(560, 640), "packs": Vector2i(860, 620), "chat": Vector2i(380, 520)}[id]
	PanelWindow.show_panel(self, id, tr(title_key), size, func() -> Control: return _make_panel(id), ctx.theme)


## The global hotkey: show/hide Saki or bring the chat up. Modes decide what fits.
func on_hotkey() -> void:
	pass


func _make_panel(id: String) -> Control:
	match id:
		"memories":
			var m := MemoriesPanel.new()
			m.setup(ctx)
			return m
		"settings":
			var s := SettingsPanel.new()
			s.setup(ctx)
			return s
		"packs":
			var p := PackManager.new()
			p.setup(ctx)
			return p
		"chat":
			var c := ChatPanel.new()
			c.setup(ctx, true, true)
			return c
	return Control.new()
