class_name PetMode
extends DisplayMode
## Desktop pet: a borderless, per-pixel transparent window showing only the character
## (plus the speech bubble). Drag to move, Ctrl + wheel to resize, click for a reaction
## and the mini chat, right-click for the menu. Clicks on transparent pixels go through to
## the desktop (mouse passthrough polygon from the character's alpha outline).
##
## Position is stored as the character's bottom-centre point on screen ("anchor"), so the
## window can grow upwards for the bubble without the character moving.

const MIN_SCALE: float = 0.5
const MAX_SCALE: float = 2.0
const WHEEL_STEP: float = 0.05
const DRAG_THRESHOLD: float = 5.0
const BUBBLE_GAP: float = 6.0
## Passthrough updates at most this often (seconds).
const PASSTHROUGH_INTERVAL: float = 0.1
## The pet never gets taller than this part of the screen.
const MAX_SCREEN_FRACTION: float = 0.7

enum MenuItem { OPEN_CHAT, TO_CHAT_WINDOW, ALWAYS_ON_TOP, PACKS, SETTINGS, QUIT }

## Called for "Thoát" (main.gd saves state and quits).
var quit_requested: Callable = Callable()

var _character: CharacterView
var _bubble: SpeechBubble
var _menu: PopupMenu
var _anchor: Vector2i = Vector2i.ZERO
var _char_size: Vector2 = Vector2.ZERO
var _pressed: bool = false
var _dragging: bool = false
var _press_mouse: Vector2i
var _press_anchor: Vector2i
var _bubble_text: String = ""
var _passthrough_dirty: bool = true
var _passthrough_wait: float = 0.0
var _scale_save_left: float = -1.0


func enter(p_ctx: UiContext) -> void:
	super.enter(p_ctx)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bubble = SpeechBubble.new()
	add_child(_bubble)
	_bubble.more_pressed.connect(func() -> void: open_mini_chat())
	_bubble.layout_changed.connect(_relayout)
	_character = CharacterView.new()
	_character.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_character)
	_character.setup(ctx)
	_character.gui_input.connect(_on_character_input)
	_character.visual_changed.connect(func() -> void:
		_passthrough_dirty = true
		if _character.natural_size() != _char_size / _scale():
			_relayout())
	_build_menu()
	_configure_window()
	_restore_anchor()
	_relayout()
	ctx.performance.set_pet_mode(true)
	var bus: Node = ctx.bus
	bus.turn_started.connect(_on_turn_started)
	bus.turn_delta.connect(_on_delta)
	bus.turn_reset.connect(_on_turn_started.bind(SakiConst.DEFAULT_EMOTION, false))
	bus.turn_ended.connect(func(_e: String, text: String, _s: Array, _sys: bool) -> void:
		_bubble_text = text
		_bubble.say(text, true))
	bus.turn_error.connect(func(m: String) -> void: _bubble.say(m, true))
	bus.turn_cancelled.connect(func() -> void: _bubble.dismiss())
	bus.setting_changed.connect(_on_setting_changed)


func exit() -> void:
	_save_anchor()
	ctx.performance.set_pet_mode(false)
	PanelWindow.set_all_on_top(false)
	DisplayServer.window_set_mouse_passthrough(PackedVector2Array(), get_window().get_window_id())


func show_message(text: String) -> void:
	_bubble.say(text, true)


func show_notice(text: String) -> void:
	_bubble.say(text, true)


func on_hotkey() -> void:
	open_mini_chat()


## Opens the mini chat (the shared ChatPanel, compact) next to the pet.
func open_mini_chat() -> void:
	var w: PanelWindow = PanelWindow.show_panel(self, "chat", tr("PANEL_CHAT"), Vector2i(380, 520),
		func() -> Control: return _make_panel("chat"), ctx.theme)
	w.always_on_top = get_window().always_on_top
	var pet := Rect2i(get_window().position, get_window().size)
	var screen: Rect2i = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var x: int = pet.position.x - w.size.x - 8
	if x < screen.position.x:
		x = pet.end.x + 8
	var y: int = clampi(pet.end.y - w.size.y, screen.position.y, screen.end.y - w.size.y)
	w.position = Vector2i(clampi(x, screen.position.x, screen.end.x - w.size.x), y)
	var panel: ChatPanel = _find_chat_panel(w)
	if panel != null:
		panel.input.focus_input()


func open_panel(id: String) -> void:
	super.open_panel(id)
	PanelWindow.set_all_on_top(get_window().always_on_top)


# --- window ----------------------------------------------------------------------------

func _configure_window() -> void:
	var w: Window = get_window()
	w.min_size = Vector2i(1, 1)
	w.borderless = true
	w.unresizable = true
	w.transparent = true
	get_viewport().transparent_bg = true
	w.always_on_top = ctx.settings.get_value("always_on_top")
	w.title = tr("APP_TITLE")


func _scale() -> float:
	return clampf(float(ctx.settings.get_value("pet_scale")), MIN_SCALE, MAX_SCALE)


## Sizes the window to the character (+ bubble) and keeps the anchor point fixed.
func _relayout() -> void:
	var natural: Vector2 = _character.natural_size()
	var screen: Rect2i = DisplayServer.screen_get_usable_rect(DisplayServer.window_get_current_screen())
	var s: float = _scale()
	var max_h: float = screen.size.y * MAX_SCREEN_FRACTION
	if natural.y * s > max_h:
		s = max_h / natural.y
	_char_size = (natural * s).round()
	var bubble_size: Vector2 = _bubble.get_combined_minimum_size() if _bubble.visible else Vector2.ZERO
	var w: float = maxf(_char_size.x, bubble_size.x)
	var h: float = _char_size.y + (bubble_size.y + BUBBLE_GAP if _bubble.visible else 0.0)
	var win: Window = get_window()
	win.size = Vector2i(ceili(w), ceili(h))
	win.position = _anchor - Vector2i(ceili(w / 2.0), ceili(h))
	_character.position = Vector2((w - _char_size.x) / 2.0, h - _char_size.y)
	_character.size = _char_size
	_bubble.position = Vector2((w - bubble_size.x) / 2.0, 0)
	_bubble.size = bubble_size
	_passthrough_dirty = true


func _restore_anchor() -> void:
	var natural: Vector2 = _character.natural_size() * _scale()
	var saved: Dictionary = ctx.settings.get_value("pet_position")
	var screens: Array[Rect2i] = WindowService.screens()
	var primary: Rect2i = screens[DisplayServer.get_primary_screen()] if screens.size() > 0 else Rect2i(0, 0, 1280, 720)
	if saved.has_all(["x", "y"]):
		_anchor = Vector2i(int(saved["x"]), int(saved["y"]))
	else:
		var pos: Vector2i = WindowService.default_pet_position(Vector2i(natural), primary)
		_anchor = pos + Vector2i(int(natural.x / 2.0), int(natural.y))
	# Off-screen (monitor unplugged, resolution changed)? Bring it back.
	var rect := Rect2i(_anchor - Vector2i(int(natural.x / 2.0), int(natural.y)), Vector2i(natural))
	var fitted: Rect2i = WindowService.fit_on_screen(rect, screens, DisplayServer.get_primary_screen())
	_anchor = fitted.position + Vector2i(int(natural.x / 2.0), int(natural.y))


func _save_anchor() -> void:
	ctx.settings.set_value("pet_position", {"x": _anchor.x, "y": _anchor.y})


func _process(delta: float) -> void:
	_passthrough_wait -= delta
	if _passthrough_dirty and _passthrough_wait <= 0.0:
		_passthrough_wait = PASSTHROUGH_INTERVAL
		_passthrough_dirty = false
		_update_passthrough()
	if _scale_save_left >= 0.0:
		_scale_save_left -= delta
		if _scale_save_left < 0.0:
			ctx.settings.save()
	if _pressed and _dragging:
		var mouse: Vector2i = DisplayServer.mouse_get_position()
		_anchor = _press_anchor + (mouse - _press_mouse)
		get_window().position = _anchor - Vector2i(get_window().size.x / 2, get_window().size.y)


func _update_passthrough() -> void:
	if _character.renderer == null:
		return
	var outline: PackedVector2Array = _character.renderer.get_alpha_outline()
	for i: int in outline.size():
		outline[i] += _character.position
	var bubble_rect := Rect2(_bubble.position, _bubble.size) if _bubble.visible else Rect2()
	var poly: PackedVector2Array = WindowService.passthrough_polygon(outline, bubble_rect, Rect2(_character.position, _character.size))
	DisplayServer.window_set_mouse_passthrough(poly, get_window().get_window_id())


# --- input -----------------------------------------------------------------------------

func _on_character_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb: InputEventMouseButton = event
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				_pressed = true
				_dragging = false
				_press_mouse = DisplayServer.mouse_get_position()
				_press_anchor = _anchor
			else:
				var was_drag: bool = _dragging
				_pressed = false
				_dragging = false
				if was_drag:
					_save_anchor()
				else:
					_on_click()
			_character.accept_event()
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
			_show_menu()
			_character.accept_event()
		elif mb.ctrl_pressed and mb.pressed and (mb.button_index == MOUSE_BUTTON_WHEEL_UP or mb.button_index == MOUSE_BUTTON_WHEEL_DOWN):
			var step: float = WHEEL_STEP if mb.button_index == MOUSE_BUTTON_WHEEL_UP else -WHEEL_STEP
			_set_scale_live(clampf(_scale() + step, MIN_SCALE, MAX_SCALE))
			_character.accept_event()
	elif event is InputEventMouseMotion and _pressed and not _dragging:
		if Vector2(DisplayServer.mouse_get_position() - _press_mouse).length() > DRAG_THRESHOLD:
			_dragging = true # a drag never counts as a click
	ctx.performance.note_input()


## Click (not a drag): short reaction, and the mini chat when Saki is not busy.
func _on_click() -> void:
	ctx.bus.character_reaction.emit(SakiConst.CLICK_REACTION_EMOTION, SakiConst.CLICK_REACTION_SEC)
	if not (ctx.backend != null and ctx.backend.turn_running):
		open_mini_chat()


## Wheel resizing applies at once; saving to disk waits until the wheel stops.
func _set_scale_live(value: float) -> void:
	ctx.settings.set_value("pet_scale", value, false) # emits setting_changed -> _relayout
	_scale_save_left = 0.6


func _on_setting_changed(key: String, value: Variant) -> void:
	match key:
		"always_on_top":
			get_window().always_on_top = bool(value)
			PanelWindow.set_all_on_top(bool(value))
			_menu.set_item_checked(_menu.get_item_index(MenuItem.ALWAYS_ON_TOP), bool(value))
		"pet_scale":
			_relayout()


func _on_turn_started(_emotion: String, _system: bool) -> void:
	_bubble_text = ""
	_bubble.say("", false)


func _on_delta(text: String) -> void:
	_bubble_text += text
	_bubble.say(_bubble_text, false)


# --- menu ------------------------------------------------------------------------------

func _build_menu() -> void:
	_menu = PopupMenu.new()
	_menu.add_item(tr("PET_MENU_OPEN_CHAT"), MenuItem.OPEN_CHAT)
	_menu.add_item(tr("PET_MENU_TO_CHAT_WINDOW"), MenuItem.TO_CHAT_WINDOW)
	_menu.add_separator()
	_menu.add_check_item(tr("PET_MENU_ALWAYS_ON_TOP"), MenuItem.ALWAYS_ON_TOP)
	_menu.set_item_checked(_menu.get_item_index(MenuItem.ALWAYS_ON_TOP), ctx.settings.get_value("always_on_top"))
	_menu.add_item(tr("PET_MENU_PACKS"), MenuItem.PACKS)
	_menu.add_item(tr("PET_MENU_SETTINGS"), MenuItem.SETTINGS)
	_menu.add_separator()
	_menu.add_item(tr("PET_MENU_QUIT"), MenuItem.QUIT)
	_menu.id_pressed.connect(_on_menu)
	add_child(_menu)


func _show_menu() -> void:
	_menu.theme = ctx.theme
	_menu.always_on_top = true
	_menu.reset_size()
	_menu.position = DisplayServer.mouse_get_position()
	_menu.popup()


func _on_menu(id: int) -> void:
	match id:
		MenuItem.OPEN_CHAT:
			open_mini_chat()
		MenuItem.TO_CHAT_WINDOW:
			ctx.bus.mode_change_requested.emit(SakiConst.MODE_CHAT)
		MenuItem.ALWAYS_ON_TOP:
			ctx.settings.set_value("always_on_top", not bool(ctx.settings.get_value("always_on_top")))
		MenuItem.PACKS:
			open_panel("packs")
		MenuItem.SETTINGS:
			open_panel("settings")
		MenuItem.QUIT:
			if quit_requested.is_valid():
				quit_requested.call()


func _find_chat_panel(n: Node) -> ChatPanel:
	for c: Node in n.get_children():
		if c is ChatPanel:
			return c
		var found: ChatPanel = _find_chat_panel(c)
		if found != null:
			return found
	return null
