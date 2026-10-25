class_name ChatInput
extends HBoxContainer
## Message box + Gửi + Dừng. Enter sends, Shift+Enter adds a line. "Dừng" is only visible
## while a turn runs. Sending while Saki answers is allowed: the client cancels first.

const MAX_LINES: int = 6

var _ctx: UiContext
var _edit: TextEdit
var _send: Button
var _stop: Button
var _base_height: float = 40.0


func setup(ctx: UiContext, compact: bool = false) -> void:
	_ctx = ctx
	add_theme_constant_override("separation", 6)
	_edit = TextEdit.new()
	_edit.placeholder_text = tr("CHAT_PLACEHOLDER")
	_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	_edit.scroll_fit_content_height = true
	_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_base_height = 40.0 if not compact else 34.0
	_edit.custom_minimum_size = Vector2(0, _base_height)
	_edit.gui_input.connect(_on_edit_input)
	_edit.text_changed.connect(_on_text_changed)
	add_child(_edit)
	_send = Button.new()
	_send.text = tr("CHAT_SEND")
	_send.theme_type_variation = &"AccentButton"
	_send.pressed.connect(submit)
	add_child(_send)
	_stop = Button.new()
	_stop.text = tr("CHAT_STOP")
	_stop.visible = false
	_stop.pressed.connect(func() -> void: _ctx.session.cancel())
	add_child(_stop)
	ctx.bus.busy_changed.connect(func(busy: bool) -> void: _stop.visible = busy)
	ctx.bus.backend_state_changed.connect(func(_s: StringName, _m: String) -> void: _refresh_enabled())
	_refresh_enabled()


func focus_input() -> void:
	_edit.grab_focus()


## Sends the current text (Enter or the Gửi button).
func submit() -> void:
	var text: String = _edit.text.strip_edges()
	if text == "":
		return
	if _ctx.session.send(text):
		_edit.text = ""
		_on_text_changed()


func _on_edit_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and (event.keycode == KEY_ENTER or event.keycode == KEY_KP_ENTER):
		if event.shift_pressed:
			return # TextEdit inserts the new line
		_edit.accept_event()
		submit()


func _on_text_changed() -> void:
	# Grow with the text up to MAX_LINES, then scroll inside the box.
	var fits: bool = _edit.get_line_count() <= MAX_LINES
	_edit.scroll_fit_content_height = fits
	_edit.custom_minimum_size.y = _base_height if fits else MAX_LINES * _edit.get_line_height() + 16


func _refresh_enabled() -> void:
	var on: bool = _ctx.backend != null and _ctx.backend.connected
	_send.disabled = not on
	_edit.editable = true # typing is fine while offline; sending is not
