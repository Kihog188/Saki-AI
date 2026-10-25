class_name SpeechBubble
extends PanelContainer
## Saki's reply next to the pet while it streams. Long text is cut with "…xem tiếp"
## (opens the mini chat). Hides itself after ChatFormat.bubble_seconds(text).

signal more_pressed()
## Size or visibility changed: the pet re-lays out its window.
signal layout_changed()

const WIDTH: float = 260.0

var _label: Label
var _more: Button
var _hide_left: float = -1.0


func _ready() -> void:
	theme_type_variation = &"AssistantBubble"
	mouse_filter = Control.MOUSE_FILTER_STOP
	var box := VBoxContainer.new()
	_label = Label.new()
	_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label.custom_minimum_size.x = WIDTH - 20.0
	box.add_child(_label)
	_more = Button.new()
	_more.theme_type_variation = &"SourceButton"
	_more.text = tr("PET_READ_MORE")
	_more.alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_more.pressed.connect(more_pressed.emit)
	box.add_child(_more)
	add_child(box)
	visible = false


## Shows `text` (plain). `final` = the turn is over: start the hide timer.
func say(text: String, final: bool) -> void:
	var cut: Dictionary = ChatFormat.bubble_text(text if text != "" else "…")
	var was_visible: bool = visible
	var old_size: Vector2 = get_combined_minimum_size()
	_label.text = cut["text"]
	_more.visible = cut["truncated"]
	visible = true
	_hide_left = ChatFormat.bubble_seconds(text) if final else -1.0
	if not was_visible or get_combined_minimum_size() != old_size:
		layout_changed.emit()


func dismiss() -> void:
	if visible:
		visible = false
		_hide_left = -1.0
		layout_changed.emit()


func _process(delta: float) -> void:
	if _hide_left >= 0.0:
		_hide_left -= delta
		if _hide_left < 0.0:
			dismiss()
