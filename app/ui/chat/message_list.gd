class_name MessageList
extends ScrollContainer
## Scrollable list of MessageBubbles for a ChatSession. Shared by the chat window and the
## pet's mini chat (compact = true).
##
## Only a window of messages [_start, _end) has nodes, at most SakiConst.MAX_LIVE_MESSAGES.
## Scrolling near the top renders older messages (and asks the session for an older page
## from the backend when the window already starts at message 0); nodes at the far end are
## freed. Scrolling back down does the reverse. So 1,000 messages never mean 1,000 nodes.

## Messages rendered per step when the window moves.
const STEP: int = 10
## Distance from the top/bottom edge (px) that triggers moving the window.
const EDGE_PX: float = 48.0

var compact: bool = false

var _session: ChatSession
var _box: VBoxContainer
var _start: int = 0
var _end: int = 0
var _follow: bool = true # stick to the bottom when new messages arrive
var _shifting: bool = false


func _init(p_compact: bool = false) -> void:
	compact = p_compact
	horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 6 if not compact else 4)
	add_child(_box)


func setup(session: ChatSession) -> void:
	_session = session
	session.message_added.connect(_on_added)
	session.message_changed.connect(_on_changed)
	session.older_loaded.connect(_on_older_loaded)
	session.cleared.connect(_rebuild_bottom)
	get_v_scroll_bar().value_changed.connect(_on_scrolled)
	_rebuild_bottom()


func live_count() -> int:
	return _box.get_child_count()


func window() -> Vector2i:
	return Vector2i(_start, _end)


func scroll_to_bottom() -> void:
	_follow = true
	await get_tree().process_frame
	scroll_vertical = int(get_v_scroll_bar().max_value)


## Renders the newest messages (after a clear, a history load or on setup).
func _rebuild_bottom() -> void:
	for c: Node in _box.get_children():
		_box.remove_child(c)
		c.queue_free()
	var total: int = _session.messages.size()
	_end = total
	_start = maxi(0, total - mini(SakiConst.MAX_LIVE_MESSAGES, SakiConst.HISTORY_PAGE_SIZE))
	for i: int in range(_start, _end):
		_box.add_child(_make(i))
	scroll_to_bottom()


func _make(index: int) -> MessageBubble:
	var b := MessageBubble.new(compact)
	b.set_message(_session.messages[index])
	return b


func _on_added(index: int) -> void:
	if index != _end:
		return # the window is not at the bottom (user scrolled far up): render later
	var was_at_bottom: bool = _at_bottom()
	_box.add_child(_make(index))
	_end += 1
	if _session.messages[index]["role"] == "user":
		was_at_bottom = true # your own message always scrolls into view
	_trim_top()
	if was_at_bottom or _follow:
		scroll_to_bottom()


func _on_changed(index: int) -> void:
	if index >= _start and index < _end:
		var node: MessageBubble = _box.get_child(index - _start) as MessageBubble
		node.set_message(_session.messages[index])
		if _follow and index == _end - 1:
			scroll_to_bottom()


func _on_older_loaded(count: int) -> void:
	_start += count
	_end += count
	_extend_up()


func _on_scrolled(_value: float) -> void:
	if _shifting:
		return
	_follow = _at_bottom()
	if scroll_vertical <= EDGE_PX:
		if _start > 0:
			_extend_up()
		elif _session.has_more and not _session.loading_older:
			_session.load_older()
	elif _at_bottom(EDGE_PX) and _end < _session.messages.size():
		_extend_down()


func _at_bottom(slack: float = 8.0) -> bool:
	var bar: VScrollBar = get_v_scroll_bar()
	return bar.value + bar.page >= bar.max_value - slack


## Renders up to STEP older messages above, keeping the visible content still.
func _extend_up() -> void:
	if _start <= 0:
		return
	_shifting = true
	var new_start: int = maxi(0, _start - STEP)
	var before_h: float = _box.get_combined_minimum_size().y
	for i: int in range(_start - 1, new_start - 1, -1):
		var node: MessageBubble = _make(i)
		_box.add_child(node)
		_box.move_child(node, 0)
	_start = new_start
	_trim_bottom()
	await get_tree().process_frame
	scroll_vertical += int(_box.get_combined_minimum_size().y - before_h)
	_shifting = false


func _extend_down() -> void:
	_shifting = true
	var new_end: int = mini(_session.messages.size(), _end + STEP)
	for i: int in range(_end, new_end):
		_box.add_child(_make(i))
	_end = new_end
	var removed_h: float = _trim_top()
	await get_tree().process_frame
	scroll_vertical -= int(removed_h)
	_shifting = false


## Frees nodes at the top over the cap. Returns the height removed.
func _trim_top() -> float:
	var removed: float = 0.0
	var sep: int = _box.get_theme_constant("separation")
	while _box.get_child_count() > SakiConst.MAX_LIVE_MESSAGES:
		var c: Control = _box.get_child(0) as Control
		removed += c.size.y + sep
		_box.remove_child(c)
		c.queue_free()
		_start += 1
	return removed


func _trim_bottom() -> void:
	while _box.get_child_count() > SakiConst.MAX_LIVE_MESSAGES:
		var c: Node = _box.get_child(_box.get_child_count() - 1)
		_box.remove_child(c)
		c.queue_free()
		_end -= 1
