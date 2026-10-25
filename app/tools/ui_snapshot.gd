extends SceneTree
## Saves PNG snapshots of the app's own windows (no screen capture, no keystrokes to other
## programs): chat window after a "/help" reply, the three panels, and the desktop pet
## with its speech bubble (transparency kept in the PNG alpha channel).
##
##   godot --path app -s res://tools/ui_snapshot.gd -- <output folder>
##
## Uses a throwaway backend data folder, opens the window off-screen, and restores
## %APPDATA%\Saki\app_settings.json afterwards.

var _out: String
var _backup: String = ""
var _app: Node # the App autoload (autoload names are not usable in -s scripts)


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	_out = args[0] if args.size() > 0 else OS.get_temp_dir()
	DirAccess.make_dir_recursive_absolute(_out)
	OS.set_environment("SAKI_DATA_DIR", OS.get_temp_dir().path_join("saki_snapshot_data"))
	if FileAccess.file_exists(SakiConst.SETTINGS_PATH):
		_backup = FileAccess.get_file_as_string(SakiConst.SETTINGS_PATH)
	root.get_window().position = Vector2i(-4000, 100) # off-screen
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	var main: Node = load("res://main.tscn").instantiate()
	root.add_child(main)
	_app = root.get_node("App")
	await _wait(func() -> bool: return _app.backend != null and _app.backend.connected, 30.0)
	main.switch_mode(SakiConst.MODE_CHAT)
	root.get_window().position = Vector2i(-4000, 100)
	await _frames(10)
	_app.session.send("/help")
	await _wait(func() -> bool: return not _app.backend.turn_running and _app.session.messages.size() > 0, 15.0)
	await _frames(10)
	_save(root, "chat.png")
	for id: String in ["memories", "settings", "packs"]:
		main.current.open_panel(id)
		var w: Window = PanelWindow._open.get(id)
		w.position = Vector2i(-4000, 100)
		await _frames(15)
		_save(w, "panel_%s.png" % id)
		w.close()
	main.switch_mode(SakiConst.MODE_PET)
	await _frames(10)
	_save(root, "pet.png")
	main.current.show_message("Chào bạn! Đây là bong bóng lời nói của Saki khi trả lời.")
	await _frames(10)
	_save(root, "pet_bubble.png")
	var img: Image = root.get_texture().get_image()
	print("pet window %s, corner alpha %.2f, centre alpha %.2f" % [img.get_size(), img.get_pixel(0, img.get_height() - 1).a, img.get_pixel(img.get_width() / 2, img.get_height() - 40).a])
	main.quit_app()
	if _backup != "":
		var f := FileAccess.open(SakiConst.SETTINGS_PATH, FileAccess.WRITE)
		f.store_string(_backup)
	print("snapshots in ", _out)


func _save(w: Viewport, name: String) -> void:
	var img: Image = w.get_texture().get_image()
	img.save_png(_out.path_join(name))
	print("saved %s %s" % [name, img.get_size()])


func _frames(n: int) -> void:
	for _i: int in n:
		await process_frame


func _wait(cond: Callable, timeout: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(timeout * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < deadline:
		await process_frame
