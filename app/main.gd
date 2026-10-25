extends Node
## Main scene: boots the App, hosts the current display mode and the global overlays.
##
## Modes are independent: a new mode = a new script under modes/ + one line in MODES.
## Switching only swaps the mode node; the chat session and the backend connection live
## in App and are untouched.

const MODES: Dictionary = {
	&"chat": "res://modes/chat_window/chat_window_mode.gd",
	&"pet": "res://modes/pet/pet_mode.gd",
}

var current: DisplayMode = null
var current_id: StringName = &""


func _ready() -> void:
	App.boot()
	App.ui.switch_mode = switch_mode
	var overlay := DebugOverlay.new()
	overlay.setup(App.performance, App.packs, App.settings)
	add_child(overlay)
	EventBus.mode_change_requested.connect(switch_mode)
	EventBus.panel_requested.connect(func(id: String) -> void:
		if current:
			current.open_panel(id))
	EventBus.notice.connect(func(text: String) -> void:
		if current:
			current.show_notice(text))
	EventBus.hotkey_pressed.connect(func() -> void:
		if current:
			current.on_hotkey())
	EventBus.pack_import_finished.connect(func(_ok: bool, message: String) -> void:
		if current:
			current.show_notice(message))
	get_window().files_dropped.connect(_on_files_dropped)
	# Main is a plain Node, so a mode (a Control) does not follow the window size by itself.
	get_viewport().size_changed.connect(_fit_mode_to_window)
	# Themes do not pass through a plain Node: give the mode the theme directly.
	EventBus.theme_changed.connect(func(_t: Resource) -> void:
		if current:
			current.theme = App.ui.theme)
	var start: StringName = StringName(App.settings.get_value("mode"))
	switch_mode(start if MODES.has(start) else SakiConst.MODE_CHAT)
	if App.settings.get_value("auto_tier") == "":
		await get_tree().process_frame # let the window appear first
		App.run_tier_detection()


## Replaces the current mode. Remembered as the start mode for next time.
func switch_mode(mode: StringName) -> void:
	if mode == current_id or not MODES.has(mode):
		return
	if current != null:
		current.exit()
		current.queue_free()
		current = null
	PanelWindow.close_all() # panels re-open on top of the new mode when asked
	var script: Script = load(MODES[mode]) as Script
	current = script.new() as DisplayMode
	current_id = mode
	if current is PetMode:
		(current as PetMode).quit_requested = quit_app
	current.theme = App.ui.theme
	add_child(current)
	move_child(current, 0) # below the debug overlay
	current.enter(App.ui)
	_fit_mode_to_window()
	App.settings.set_value("mode", String(mode))


func _fit_mode_to_window() -> void:
	if current != null:
		current.position = Vector2.ZERO
		current.size = get_viewport().get_visible_rect().size


## Saves window state, stops what the app started and quits.
func quit_app() -> void:
	if current != null:
		current.exit()
	App.shutdown()
	get_tree().quit()


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_CLOSE_REQUEST and current != null:
		print("Window close requested: saving %s mode state" % current_id)
		current.exit() # closing the window quits the app (App stops the backend)


func _on_files_dropped(files: PackedStringArray) -> void:
	# A .sakip file or a folder of character images (both go through the importer).
	for f: String in files:
		if f.get_extension().to_lower() == "sakip" or DirAccess.dir_exists_absolute(f):
			if App.packs.import_file(f):
				current.open_panel("packs")
			else:
				current.show_notice(tr("PACKS_IMPORT_BUSY"))
			return
	current.show_notice(tr("PACKS_DROP_ONLY_SAKIP"))
