extends SceneTree
## Manual end-to-end check against the REAL Python backend (not part of the unit tests):
## starts `pythonw -m saki` hidden with a throwaway data folder, connects, sends "/help"
## (a command: no model needed), waits for the reply, then stops the backend and checks
## that the process is gone.
##
##   godot --headless --path app -s res://tools/backend_smoke.gd -- [--port 8799]

var _ok: bool = false


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	var port: int = 8799
	var args: PackedStringArray = OS.get_cmdline_user_args()
	if args.size() >= 2 and args[0] == "--port":
		port = int(args[1])
	var data_dir: String = OS.get_temp_dir().path_join("saki_smoke_%d" % Time.get_ticks_usec())
	OS.set_environment("SAKI_DATA_DIR", data_dir) # inherited by the backend process
	var bus: Node = load("res://core/event_bus.gd").new()
	root.add_child(bus)
	var proc := BackendProcess.new(bus, ProcessLauncher.new(), HttpRequestTransport.new())
	proc.port = port
	root.add_child(proc)
	var t0: int = Time.get_ticks_msec()
	var r: Dictionary = await proc.ensure_running()
	print("ensure_running: code='%s' owned=%s after %d ms" % [r["code"], r["owned"], Time.get_ticks_msec() - t0])
	if r["code"] != "":
		print("FAILED: ", r["message"])
		quit(1)
		return
	var client := BackendClient.new(bus, WebSocketTransport.new(), HttpRequestTransport.new(), proc.base_url())
	root.add_child(client)
	bus.turn_ended.connect(func(_e: String, text: String, _s: Array, system: bool) -> void:
		print("reply (system=%s): %s" % [system, text.left(80).replace("\n", " | ")])
		_ok = true)
	client.start()
	var deadline: int = Time.get_ticks_msec() + 15000
	while not client.connected and Time.get_ticks_msec() < deadline:
		await process_frame
	print("connected=%s protocol=%s llm_reachable=%s" % [client.connected, client.last_health.get("protocol_version"), client.llm_reachable])
	client.send_message("/help")
	while not _ok and Time.get_ticks_msec() < deadline:
		await process_frame
	var pid: int = proc.pid
	client.stop()
	var s0: int = Time.get_ticks_msec()
	proc.stop()
	print("stop took %d ms, process still running: %s" % [Time.get_ticks_msec() - s0, OS.is_process_running(pid)])
	quit(0 if _ok and not OS.is_process_running(pid) else 1)
