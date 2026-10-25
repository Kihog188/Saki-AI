class_name PanelWindow
extends Window
## A native OS window holding one panel (Memories, Settings, Packs, mini chat).
## Subwindows are not embedded (project.godot), so panels work the same from the big chat
## window and from the tiny pet window. One instance per panel id: opening again focuses it.

static var _open: Dictionary = {} # id -> PanelWindow

var panel_id: String = ""


## Shows `content` in a window titled `title` (or focuses the existing one). The content is
## created by `make` only when the window does not exist yet.
static func show_panel(parent: Node, id: String, title: String, win_size: Vector2i, make: Callable, theme_res: Theme) -> PanelWindow:
	var existing: PanelWindow = _open.get(id)
	if is_instance_valid(existing):
		existing.grab_focus()
		existing.move_to_foreground()
		return existing
	var w := PanelWindow.new()
	w.panel_id = id
	w.title = title
	w.size = win_size
	w.min_size = Vector2i(320, 260)
	w.wrap_controls = false
	w.transient = false
	w.exclusive = false
	w.theme = theme_res
	var parent_window: Window = parent.get_window()
	w.always_on_top = parent_window.always_on_top
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	var margin := MarginContainer.new()
	for side: String in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	margin.add_child(make.call())
	bg.add_child(margin)
	w.add_child(bg)
	w.close_requested.connect(w.close)
	_open[id] = w
	parent.get_tree().root.add_child(w)
	w.popup_centered()
	return w


static func close_all() -> void:
	for w: Variant in _open.values():
		if is_instance_valid(w):
			(w as PanelWindow).close()
	_open.clear()


## Re-applies the theme to every open panel (theme setting changed).
static func apply_theme(theme_res: Theme) -> void:
	for w: Variant in _open.values():
		if is_instance_valid(w):
			(w as PanelWindow).theme = theme_res


static func set_all_on_top(on: bool) -> void:
	for w: Variant in _open.values():
		if is_instance_valid(w):
			(w as PanelWindow).always_on_top = on


func close() -> void:
	_open.erase(panel_id)
	queue_free()
