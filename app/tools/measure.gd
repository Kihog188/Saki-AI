extends SceneTree
## Measures the real app (not a unit test): RAM (working set), CPU and main-loop rate in
## each mode while idle and while "busy" (EventBus.busy_changed(true), as during a turn),
## plus the pack list time. No input is sent and nothing is captured from the screen.
##
##   godot --path app -s res://tools/measure.gd -- [seconds per phase, default 10]
##
## Uses a throwaway backend data folder, keeps the windows off-screen, and restores
## %APPDATA%\Saki\app_settings.json afterwards. Windows only (reads Get-Process).

var _backup: String = ""
var _app: Node # the App autoload (autoload names are not usable in -s scripts)
var _main: Node


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var args: PackedStringArray = OS.get_cmdline_user_args()
	var seconds: float = float(args[0]) if args.size() > 0 else 10.0
	OS.set_environment("SAKI_DATA_DIR", OS.get_temp_dir().path_join("saki_measure_data"))
	if FileAccess.file_exists(SakiConst.SETTINGS_PATH):
		_backup = FileAccess.get_file_as_string(SakiConst.SETTINGS_PATH)
	root.get_window().position = Vector2i(-4000, 100)
	root.set_flag(Window.FLAG_NO_FOCUS, true)
	_main = load("res://main.tscn").instantiate()
	root.add_child(_main)
	_app = root.get_node("App")
	await _wait(func() -> bool: return _app.backend != null and _app.backend.connected, 60.0)
	print("backend connected=%s, tier=%s" % [_app.backend.connected, _app.performance.tier.id])

	var t0: int = Time.get_ticks_usec()
	var count: int = _app.packs.list().size()
	print("pack list (cached): %d packs in %.1f ms" % [count, (Time.get_ticks_usec() - t0) / 1000.0])
	_measure_pack()

	for mode: StringName in [SakiConst.MODE_CHAT, SakiConst.MODE_PET]:
		_main.switch_mode(mode)
		root.get_window().position = Vector2i(-4000, 100)
		await _phase("%s idle" % mode, seconds, false)
		await _phase("%s busy" % mode, seconds / 2.0, true)
	var backend_pid: int = _app.backend_process.pid
	if backend_pid > 0:
		print("backend pythonw: %s" % _proc_line(backend_pid))
	_main.quit_app()
	if _backup != "":
		var f := FileAccess.open(SakiConst.SETTINGS_PATH, FileAccess.WRITE)
		f.store_string(_backup)


## Loads every emotion of the active pack once (as a long chat would) and prints the load
## time and the texture memory after each one.
func _measure_pack() -> void:
	var pack: PackData = _app.packs.active
	print("active pack: %s, type %s, max texture %d" % [pack.entry["key"], pack.manifest.type, pack.max_texture_size])
	for emotion: String in SakiConst.EMOTIONS:
		var t0: int = Time.get_ticks_usec()
		var anim: Dictionary = pack.get_animation(emotion)
		var frames: Array = anim.get("frames", [])
		var frame_size: Vector2 = frames[0].get_size() if not frames.is_empty() else Vector2.ZERO
		print("  %-12s %d frames %s in %5.1f ms; textures resident: %d, texture memory %.1f MB" % [
			emotion, frames.size(), frame_size, (Time.get_ticks_usec() - t0) / 1000.0, pack.loaded_texture_count(),
			Performance.get_monitor(Performance.RENDER_TEXTURE_MEM_USED) / 1048576.0])


## One phase: settle 2 s, then count main-loop iterations and CPU time over `seconds`.
func _phase(label: String, seconds: float, busy: bool) -> void:
	_app.get_node("/root/EventBus").busy_changed.emit(busy)
	await _sleep(2.0)
	var before: Dictionary = _proc(OS.get_process_id())
	var frames0: int = Engine.get_process_frames()
	var t0: int = Time.get_ticks_msec()
	await _sleep(seconds)
	var wall: float = (Time.get_ticks_msec() - t0) / 1000.0
	var loops: float = (Engine.get_process_frames() - frames0) / wall
	var after: Dictionary = _proc(OS.get_process_id())
	var cpu: float = (after["cpu"] - before["cpu"]) / wall * 100.0
	print("%-10s loop %5.1f/s (cap %d)  CPU %4.1f %% of one core  RAM %d MB  static %d MB" % [
		label, loops, Engine.max_fps, cpu, after["ws"] / 1048576, OS.get_static_memory_usage() / 1048576])
	if busy:
		_app.get_node("/root/EventBus").busy_changed.emit(false)


## {"ws": working set bytes, "cpu": total processor seconds} of a process.
func _proc(pid: int) -> Dictionary:
	var out: Array = []
	OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command",
		"$p = Get-Process -Id %d; '{0} {1}' -f $p.WorkingSet64, $p.TotalProcessorTime.TotalSeconds" % pid], out)
	var parts: PackedStringArray = String(out[0]).strip_edges().split(" ") if out.size() > 0 else PackedStringArray()
	if parts.size() < 2:
		return {"ws": 0, "cpu": 0.0}
	return {"ws": int(parts[0]), "cpu": float(parts[1].replace(",", "."))}


## Working set of a process plus its children (the .venv pythonw.exe is a small launcher
## that starts the real interpreter as a child).
func _proc_line(pid: int) -> String:
	var out: Array = []
	OS.execute("powershell.exe", ["-NoProfile", "-NonInteractive", "-Command",
		"$ids = @(%d) + @(Get-CimInstance Win32_Process -Filter 'ParentProcessId=%d' | ForEach-Object ProcessId); " % [pid, pid]
		+ "(Get-Process -Id $ids | Measure-Object WorkingSet64 -Sum).Sum"], out)
	var total: int = int(String(out[0]).strip_edges()) if out.size() > 0 else 0
	return "RAM %d MB (launcher + interpreter)" % (total / 1048576)


func _sleep(seconds: float) -> void:
	await create_timer(seconds).timeout


func _wait(cond: Callable, timeout: float) -> void:
	var deadline: int = Time.get_ticks_msec() + int(timeout * 1000.0)
	while not cond.call() and Time.get_ticks_msec() < deadline:
		await process_frame
