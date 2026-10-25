class_name MessageBubble
extends MarginContainer
## One chat message. Text is plain (Label: never BBCode); ``` blocks are shown in a
## monospace panel, still as plain text. Right-click copies the message text.
## Label, not RichTextLabel: 20 RichTextLabels with fit_content took ~245 ms to lay out on
## the dev machine (vs ~29 ms), which made paging through history stutter.

var uid: int = -1

var _compact: bool = false
var _panel: PanelContainer
var _box: VBoxContainer
var _segments_box: VBoxContainer
var _sources: SourcesList
var _segment_count: int = -1
var _role: String = ""
var _text: String = ""


func _init(compact: bool = false) -> void:
	_compact = compact
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_panel = PanelContainer.new()
	_box = VBoxContainer.new()
	_box.add_theme_constant_override("separation", 4)
	_segments_box = VBoxContainer.new()
	_segments_box.add_theme_constant_override("separation", 6)
	_sources = SourcesList.new()
	_sources.visible = false
	_box.add_child(_segments_box)
	_box.add_child(_sources)
	_panel.add_child(_box)
	_panel.tooltip_text = tr("CHAT_COPY_HINT")
	_panel.gui_input.connect(_on_panel_input)
	add_child(_panel)


func set_message(m: Dictionary) -> void:
	uid = m.get("uid", -1)
	var role: String = m.get("role", "assistant")
	if m.get("system", false) and role == "assistant":
		role = "system"
	if role != _role:
		_role = role
		_apply_role()
	_text = String(m.get("text", ""))
	var segs: Array[Dictionary] = ChatFormat.segments(_text)
	if segs.is_empty() and m.get("status", "") == "streaming":
		segs = [{"code": false, "text": "…"}]
	if segs.size() != _segment_count:
		_rebuild(segs)
	else:
		for i: int in segs.size():
			_set_segment_text(_segments_box.get_child(i), segs[i]["text"])
	_sources.set_sources(m.get("sources", []))


func _apply_role() -> void:
	var variation: StringName = {
		"user": &"UserBubble", "assistant": &"AssistantBubble", "system": &"SystemBubble", "error": &"ErrorBubble",
	}.get(_role, &"AssistantBubble")
	_panel.theme_type_variation = variation
	# User messages on the right, Saki on the left; bubbles never span the full width.
	var side: int = 48 if not _compact else 20
	add_theme_constant_override("margin_left", side if _role == "user" else 0)
	add_theme_constant_override("margin_right", 0 if _role == "user" else side)
	add_theme_constant_override("margin_top", 2)
	add_theme_constant_override("margin_bottom", 2)


func _rebuild(segs: Array[Dictionary]) -> void:
	for c: Node in _segments_box.get_children():
		_segments_box.remove_child(c)
		c.queue_free()
	_segment_count = segs.size()
	for s: Dictionary in segs:
		_segments_box.add_child(_make_segment(s))


func _make_segment(s: Dictionary) -> Control:
	if s["code"]:
		var panel := PanelContainer.new()
		panel.theme_type_variation = &"CodeBlock"
		var label := Label.new()
		label.theme_type_variation = &"CodeLabel"
		label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		label.text = s["text"]
		panel.add_child(label)
		return panel
	var label := Label.new() # plain text: untrusted model output is never markup
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_PASS
	label.text = s["text"]
	return label


func _set_segment_text(node: Node, text: String) -> void:
	if node is Label:
		if (node as Label).text != text:
			(node as Label).text = text
	elif node is PanelContainer:
		var label: Label = node.get_child(0) as Label
		if label.text != text:
			label.text = text


func _on_panel_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
		DisplayServer.clipboard_set(_text)
		_panel.accept_event()
