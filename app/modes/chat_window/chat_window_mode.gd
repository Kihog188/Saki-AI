class_name ChatWindowMode
extends DisplayMode
## Normal window: character panel (renderer, name, status line) + chat panel, with header
## buttons Ghi nhớ / Cài đặt / Nhân vật / Chuyển sang desktop pet. Remembers its size and
## position; below NARROW_WIDTH the character goes on top in a short strip.

const DEFAULT_SIZE: Vector2i = Vector2i(960, 640)
const MIN_SIZE: Vector2i = Vector2i(360, 420)
const NARROW_WIDTH: int = 680
const CHARACTER_WIDTH: int = 300
const CHARACTER_STRIP_HEIGHT: int = 150

var _layout: BoxContainer
var _character_panel: VBoxContainer
var _character: CharacterView
var _name: Label
var _chat: ChatPanel
var _toast: Label
var _toast_left: float = 0.0


func enter(p_ctx: UiContext) -> void:
	super.enter(p_ctx)
	_configure_window()
	_build()
	ctx.bus.active_pack_changed.connect(func(_k: String) -> void: _update_name())
	resized.connect(_apply_layout)
	_apply_layout()
	_chat.input.focus_input()


func exit() -> void:
	var w: Window = get_window()
	save_window_rect(w.position, w.size, w.mode)


## Remembers the window rect, except while minimized (no useful size then).
func save_window_rect(pos: Vector2i, win_size: Vector2i, mode: Window.Mode) -> void:
	if mode != Window.MODE_MINIMIZED:
		ctx.settings.set_value("chat_window", {"x": pos.x, "y": pos.y, "w": win_size.x, "h": win_size.y})


func show_message(_text: String) -> void:
	_chat.list.scroll_to_bottom()


func show_notice(text: String) -> void:
	_toast.text = text
	_toast.visible = text != ""
	_toast_left = 6.0


func on_hotkey() -> void:
	var w: Window = get_window()
	if w.mode == Window.MODE_MINIMIZED or not w.has_focus():
		w.mode = Window.MODE_WINDOWED
		w.grab_focus()
		w.move_to_foreground()
		_chat.input.focus_input()
	else:
		w.mode = Window.MODE_MINIMIZED


func _process(delta: float) -> void:
	if _toast_left > 0.0:
		_toast_left -= delta
		if _toast_left <= 0.0:
			_toast.visible = false


func _configure_window() -> void:
	var w: Window = get_window()
	w.transparent = false
	get_viewport().transparent_bg = false
	w.borderless = false
	w.always_on_top = false
	w.unresizable = false
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array())
	w.min_size = MIN_SIZE
	w.title = tr("APP_TITLE")
	var saved: Dictionary = ctx.settings.get_value("chat_window")
	var rect := Rect2i(Vector2i.ZERO, DEFAULT_SIZE)
	var screens: Array[Rect2i] = WindowService.screens()
	if saved.has_all(["x", "y", "w", "h"]):
		rect = Rect2i(int(saved["x"]), int(saved["y"]), maxi(MIN_SIZE.x, int(saved["w"])), maxi(MIN_SIZE.y, int(saved["h"])))
	else:
		var primary: Rect2i = screens[DisplayServer.get_primary_screen()] if screens.size() > 0 else Rect2i(0, 0, 1280, 720)
		rect.position = primary.position + (primary.size - rect.size) / 2
	rect = WindowService.fit_on_screen(rect, screens, DisplayServer.get_primary_screen())
	w.size = rect.size
	w.position = rect.position


func _build() -> void:
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 10)
	bg.add_child(margin)
	_layout = BoxContainer.new()
	_layout.add_theme_constant_override("separation", 10)
	margin.add_child(_layout)

	_character_panel = VBoxContainer.new()
	_character = CharacterView.new()
	_character.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_character.custom_minimum_size = Vector2(120, 120)
	_character_panel.add_child(_character)
	_character.setup(ctx)
	_name = Label.new()
	_name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_name.add_theme_font_size_override("font_size", 18)
	_character_panel.add_child(_name)
	var status := StatusLine.new()
	_character_panel.add_child(status)
	status.setup(ctx)
	_layout.add_child(_character_panel)
	_update_name()

	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(_header())
	_toast = Label.new()
	_toast.theme_type_variation = &"MutedLabel"
	_toast.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_toast.visible = false
	right.add_child(_toast)
	_chat = ChatPanel.new()
	right.add_child(_chat)
	_chat.setup(ctx, false, false)
	_layout.add_child(right)


func _header() -> Control:
	var bar := HFlowContainer.new()
	bar.alignment = FlowContainer.ALIGNMENT_END
	for item: Array in [["PANEL_MEMORIES", "memories"], ["PANEL_SETTINGS", "settings"], ["PANEL_PACKS", "packs"]]:
		var b := Button.new()
		b.text = tr(item[0])
		var id: String = item[1]
		b.pressed.connect(func() -> void: open_panel(id))
		bar.add_child(b)
	var pet := Button.new()
	pet.text = tr("MODE_TO_PET")
	pet.theme_type_variation = &"AccentButton"
	pet.pressed.connect(func() -> void: ctx.bus.mode_change_requested.emit(SakiConst.MODE_PET))
	bar.add_child(pet)
	return bar


func _apply_layout() -> void:
	apply_layout_for_width(size.x)


## Side by side when wide; character in a short strip above the chat when narrow.
func apply_layout_for_width(width: float) -> void:
	var narrow: bool = width < NARROW_WIDTH
	_layout.vertical = narrow
	_character_panel.custom_minimum_size = Vector2(0, CHARACTER_STRIP_HEIGHT) if narrow else Vector2(CHARACTER_WIDTH, 0)
	_name.visible = not narrow


func _update_name() -> void:
	var e: Dictionary = ctx.packs.index.get_entry(ctx.packs.active_key())
	_name.text = String(e.get("name", "Saki"))
