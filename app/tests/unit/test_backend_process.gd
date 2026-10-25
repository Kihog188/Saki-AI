extends GutTest
## BackendProcess with a fake launcher and fake HTTP: no real process is ever started.

const TMP: String = "user://test_tmp/backend"

var _bus: Node
var _http: TestFakes.FakeHttp
var _launcher: TestFakes.FakeLauncher
var _proc: BackendProcess
var _repo: String


func before_each() -> void:
	_repo = ProjectSettings.globalize_path(TMP.path_join(str(randi())))
	_make_repo(_repo)
	_bus = add_child_autofree(load("res://core/event_bus.gd").new())
	_http = TestFakes.FakeHttp.new()
	_launcher = TestFakes.FakeLauncher.new()
	_proc = BackendProcess.new(_bus, _launcher, _http)
	_proc.backend_dir = _repo
	_proc.port = 1 # nothing listens there: the exit-time POST fails fast and locally
	_proc.poll_interval = 0.02
	_proc.start_timeout = 1.0
	add_child_autofree(_proc)
	watch_signals(_bus)


func after_each() -> void:
	PackFiles.remove_tree(TMP)


func _make_repo(dir: String) -> void:
	DirAccess.make_dir_recursive_absolute(dir.path_join("saki"))
	FileAccess.open(dir.path_join("saki/__main__.py"), FileAccess.WRITE).store_string("#")
	var py: String = BackendProcess.python_path(dir)
	DirAccess.make_dir_recursive_absolute(py.get_base_dir())
	FileAccess.open(py, FileAccess.WRITE).store_string("")


func test_finds_repo_from_nested_folder() -> void:
	var nested: String = _repo.path_join("app/export/win")
	DirAccess.make_dir_recursive_absolute(nested)
	assert_eq(BackendProcess.find_backend_dir("", PackedStringArray([nested])), _repo)
	assert_eq(BackendProcess.find_backend_dir("", PackedStringArray([ProjectSettings.globalize_path("user://")])), "")
	assert_eq(BackendProcess.find_backend_dir(_repo, PackedStringArray()), _repo)
	assert_eq(BackendProcess.find_backend_dir(_repo.path_join("nope"), PackedStringArray([nested])), _repo, "a stale saved folder falls back to searching")


func test_existing_saki_is_used_not_owned() -> void:
	_http.routes["/health"] = TestFakes.FakeHttp.health()
	var r: Dictionary = await _proc.ensure_running()
	assert_eq(r["code"], BackendProcess.OK_RUNNING)
	assert_false(r["owned"])
	assert_eq(_launcher.started.size(), 0)
	_proc.stop()
	assert_eq(_launcher.killed.size(), 0, "a backend we did not start is left running")


func test_port_used_by_another_program() -> void:
	_http.routes["/health"] = TestFakes.FakeHttp.ok("<html>", 200)
	var r: Dictionary = await _proc.ensure_running()
	assert_eq(r["code"], BackendProcess.ERR_PORT_BUSY)
	assert_string_contains(r["message"], "Cổng 1 đang bị một ứng dụng khác sử dụng")
	assert_eq(_launcher.started.size(), 0)


func test_backend_not_found() -> void:
	_proc.backend_dir = _repo.path_join("missing")
	_proc.search_roots = PackedStringArray([ProjectSettings.globalize_path("user://")])
	var r: Dictionary = await _proc.ensure_running()
	assert_eq(r["code"], BackendProcess.ERR_NOT_FOUND)
	assert_string_contains(r["message"], "Không tìm thấy backend Saki")


func test_starts_hidden_and_owns_it() -> void:
	_launcher.on_start = func() -> void: _http.routes["/health"] = TestFakes.FakeHttp.health()
	var r: Dictionary = await _proc.ensure_running()
	assert_eq(r["code"], BackendProcess.OK_RUNNING)
	assert_true(r["owned"])
	var start: Dictionary = _launcher.started[0]
	assert_eq(start["path"], BackendProcess.python_path(_repo))
	assert_eq(start["args"], PackedStringArray(["-m", "saki", "--port", "1"]))
	assert_eq(start["env"]["PYTHONPATH"], _repo)
	assert_eq(String(start["env"]["SAKI_SHUTDOWN_TOKEN"]).length(), 32)
	assert_signal_emitted_with_parameters(_bus, "backend_state_changed", [SakiConst.CONN_STARTING, "Đang khởi động Saki..."])
	_proc.stop()
	assert_push_warning("did not stop in time")
	assert_eq(_launcher.killed, [4242], "graceful stop failed -> process tree killed")
	assert_false(_proc.owned)


func test_process_exits_during_start() -> void:
	_launcher.on_start = func() -> void: _launcher.running.clear()
	var r: Dictionary = await _proc.ensure_running()
	assert_eq(r["code"], BackendProcess.ERR_START_FAILED)
	assert_string_contains(r["message"], "saki.log")


func test_start_timeout() -> void:
	var r: Dictionary = await _proc.ensure_running()
	assert_eq(r["code"], BackendProcess.ERR_TIMEOUT)


func test_crash_is_reported_once_without_restart() -> void:
	_launcher.on_start = func() -> void: _http.routes["/health"] = TestFakes.FakeHttp.health()
	await _proc.ensure_running()
	_launcher.running.clear() # the backend dies
	_proc._process(1.1)
	_proc._process(1.1)
	assert_push_warning("exited unexpectedly")
	assert_signal_emit_count(_bus, "backend_state_changed", 2, "starting + one crash report")
	assert_eq(get_signal_parameters(_bus, "backend_state_changed")[0], SakiConst.CONN_FAILED)
	assert_eq(_launcher.started.size(), 1, "no automatic restart")


func test_silent_program_on_port_is_busy() -> void:
	_http.listening = true # accepts TCP, never answers HTTP
	var r: Dictionary = await _proc.ensure_running()
	assert_eq(r["code"], BackendProcess.ERR_PORT_BUSY)
