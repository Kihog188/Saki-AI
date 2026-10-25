class_name MemoriesPanel
extends VBoxContainer
## "Ghi nhớ": list, add and delete (with confirmation) through the REST API. Refreshes when
## a /rmb or /fgt reply arrives (EventBus.memories_changed).

const MAX_CHARS: int = 200

var _ctx: UiContext
var _list: VBoxContainer
var _input: LineEdit
var _message: Label
var _confirm: ConfirmationDialog
var _pending_delete: int = -1


func setup(ctx: UiContext) -> void:
	_ctx = ctx
	add_theme_constant_override("separation", 8)
	var note := Label.new()
	note.theme_type_variation = &"MutedLabel"
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	note.text = tr("MEMORIES_NOTE")
	add_child(note)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_list = VBoxContainer.new()
	_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_list)
	add_child(scroll)

	var row := HBoxContainer.new()
	_input = LineEdit.new()
	_input.placeholder_text = tr("MEMORIES_ADD_PLACEHOLDER")
	_input.max_length = MAX_CHARS
	_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_input.text_submitted.connect(func(_t: String) -> void: _add())
	row.add_child(_input)
	var add_btn := Button.new()
	add_btn.text = tr("MEMORIES_ADD")
	add_btn.theme_type_variation = &"AccentButton"
	add_btn.pressed.connect(_add)
	row.add_child(add_btn)
	add_child(row)

	_message = Label.new()
	_message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	add_child(_message)

	_confirm = ConfirmationDialog.new()
	_confirm.dialog_text = tr("MEMORIES_CONFIRM_DELETE")
	_confirm.ok_button_text = tr("ACTION_DELETE")
	_confirm.cancel_button_text = tr("ACTION_CANCEL")
	_confirm.confirmed.connect(_delete_confirmed)
	add_child(_confirm)

	ctx.bus.memories_changed.connect(refresh)
	refresh()


func refresh() -> void:
	var r: Dictionary = await _ctx.backend.get_memories()
	for c: Node in _list.get_children():
		c.queue_free()
	if not r["ok"]:
		_show(r["error"], true)
		return
	var items: Array = r["data"].get("memories", []) if r["data"] is Dictionary else []
	if items.is_empty():
		var empty := Label.new()
		empty.theme_type_variation = &"MutedLabel"
		empty.text = tr("MEMORIES_EMPTY")
		_list.add_child(empty)
	for m: Variant in items:
		if m is Dictionary:
			_list.add_child(_row(m))


func _row(m: Dictionary) -> Control:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = String(m.get("text", "")) # plain text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var del := Button.new()
	del.text = tr("ACTION_DELETE")
	var id: int = int(m.get("id", -1))
	del.pressed.connect(func() -> void:
		_pending_delete = id
		_confirm.popup_centered())
	row.add_child(del)
	return row


func _add() -> void:
	var text: String = _input.text.strip_edges()
	if text == "":
		return
	var r: Dictionary = await _ctx.backend.add_memory(text)
	if r["ok"]:
		_input.text = ""
		_show(tr("MEMORIES_ADDED"), false)
		refresh()
	else:
		_show(r["error"], true)


func _delete_confirmed() -> void:
	if _pending_delete < 0:
		return
	var r: Dictionary = await _ctx.backend.delete_memory(_pending_delete)
	_pending_delete = -1
	if not r["ok"]:
		_show(r["error"], true)
	refresh()


func _show(text: String, error: bool) -> void:
	_message.text = text
	_message.theme_type_variation = &"ErrorLabel" if error else &"MutedLabel"
