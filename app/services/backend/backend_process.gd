class_name BackendProcess
extends Node
## Finds, starts, watches and stops the Python backend (`pythonw -m saki`).
##
## - If a Saki backend already answers on the port (started from the CLI), the app uses it
##   and does NOT own it: it is left running when the app exits.
## - If something else holds the port, ensure_running() fails with a clear message.
## - An owned backend is stopped on exit: POST /shutdown with a per-launch token first,
##   then the process tree is killed after STOP_GRACE_MS.
## - If an owned backend dies, this only REPORTS it (EventBus.backend_state_changed with
##   CONN_FAILED). There is no automatic restart loop; the UI offers "Khởi động lại".

const STOP_GRACE_MS: int = 3000
const TOKEN_ENV: String = "SAKI_SHUTDOWN_TOKEN"

## Result codes of ensure_running().
const OK_RUNNING: String = ""
const ERR_NOT_FOUND: String = "not_found"
const ERR_PORT_BUSY: String = "port_busy"
const ERR_START_FAILED: String = "start_failed"
const ERR_TIMEOUT: String = "timeout"

## Seconds to wait for /health after starting the process (imports are slow on old CPUs).
var start_timeout: float = 90.0
var poll_interval: float = 0.5
## Folder that contains saki/ and .venv/ ("" = search next to the app).
var backend_dir: String = ""
var port: int = 8765

var owned: bool = false
var pid: int = -1

var _bus: Node
var _launcher: ProcessLauncher
var _http: HttpTransport
var _token: String = ""
var _watch_elapsed: float = 0.0


func _init(bus: Node, launcher: ProcessLauncher, http: HttpTransport) -> void:
	name = "BackendProcess"
	_bus = bus
	_launcher = launcher
	_http = http


func _ready() -> void:
	if _http.get_parent() == null:
		add_child(_http)


func base_url() -> String:
	return "http://127.0.0.1:%d" % port


## Makes sure a Saki backend answers on `port`. Coroutine.
## Returns {"code": OK_RUNNING or ERR_*, "message": Vietnamese text, "owned": bool}.
func ensure_running() -> Dictionary:
	var probe: Dictionary = await _probe()
	if probe["saki"]:
		owned = false
		return _result(OK_RUNNING, "")
	if probe["busy"]:
		return _result(ERR_PORT_BUSY, I18n.t("BACKEND_PORT_BUSY", {"port": port}))
	var dir: String = BackendProcess.find_backend_dir(backend_dir, BackendProcess.default_search_roots())
	if dir == "":
		return _result(ERR_NOT_FOUND, I18n.t("BACKEND_NOT_FOUND"))

	_bus.backend_state_changed.emit(SakiConst.CONN_STARTING, I18n.t("STATUS_STARTING"))
	_token = Crypto.new().generate_random_bytes(16).hex_encode()
	var env: Dictionary = {"PYTHONPATH": dir, TOKEN_ENV: _token, "PYTHONIOENCODING": "utf-8"}
	pid = _launcher.start(BackendProcess.python_path(dir), PackedStringArray(["-m", "saki", "--port", str(port)]), env)
	if pid <= 0:
		return _result(ERR_START_FAILED, I18n.t("BACKEND_START_FAILED"))
	owned = true
	var waited: float = 0.0
	while waited < start_timeout:
		await get_tree().create_timer(poll_interval).timeout
		waited += poll_interval
		if not _launcher.is_running(pid):
			owned = false
			return _result(ERR_START_FAILED, I18n.t("BACKEND_START_FAILED"))
		if (await _probe())["saki"]:
			return _result(OK_RUNNING, "")
	return _result(ERR_TIMEOUT, I18n.t("BACKEND_START_TIMEOUT"))


## {"saki": bool, "busy": bool}: busy = something that is not Saki holds the port.
func _probe() -> Dictionary:
	if not await _http.port_open("127.0.0.1", port):
		return {"saki": false, "busy": false}
	var r: Dictionary = await _http.request(HTTPClient.METHOD_GET, base_url() + "/health", null, [], 3.0)
	var saki: bool = r["code"] == 200 and BackendProcess.looks_like_saki(r["data"])
	return {"saki": saki, "busy": not saki}


## Stops the backend if this app started it. Blocking (used on exit), at most a few s.
func stop() -> void:
	if not owned or not _launcher.is_running(pid):
		owned = false
		return
	BackendProcess.blocking_post("127.0.0.1", port, "/shutdown", ["X-Saki-Token: " + _token], 1500)
	var deadline: int = Time.get_ticks_msec() + STOP_GRACE_MS
	while _launcher.is_running(pid) and Time.get_ticks_msec() < deadline:
		OS.delay_msec(100)
	if _launcher.is_running(pid):
		push_warning("Backend did not stop in time, killing process tree %d" % pid)
		_launcher.kill_tree(pid)
	owned = false


## Watches an owned backend once per second; reports (never restarts) a crash.
func _process(delta: float) -> void:
	if not owned:
		return
	_watch_elapsed += delta
	if _watch_elapsed < 1.0:
		return
	_watch_elapsed = 0.0
	if not _launcher.is_running(pid):
		owned = false
		push_warning("Backend process %d exited unexpectedly" % pid)
		_bus.backend_state_changed.emit(SakiConst.CONN_FAILED, I18n.t("BACKEND_CRASHED"))


func _result(code: String, message: String) -> Dictionary:
	return {"code": code, "message": message, "owned": owned}


# --- pure helpers (tested directly) ----------------------------------------------------

static func looks_like_saki(data: Variant) -> bool:
	return data is Dictionary and data.get("status") == "ok" and data.get("llm") is Dictionary


static func python_path(dir: String) -> String:
	if OS.get_name() == "Windows":
		return dir.path_join(".venv/Scripts/pythonw.exe")
	return dir.path_join(".venv/bin/python")


static func is_backend_dir(dir: String) -> bool:
	return dir != "" and FileAccess.file_exists(dir.path_join("saki/__main__.py")) \
		and FileAccess.file_exists(BackendProcess.python_path(dir))


## `configured` wins if valid. Otherwise each root and up to 4 parent folders are tried
## (the repo root is the parent of app/, and an exported .exe may sit deeper).
static func find_backend_dir(configured: String, roots: PackedStringArray) -> String:
	if configured != "":
		return configured if is_backend_dir(configured) else ""
	for root: String in roots:
		var dir: String = root.simplify_path()
		for _i: int in 5:
			if is_backend_dir(dir):
				return dir
			var parent: String = dir.get_base_dir()
			if parent == dir or parent == "":
				break
			dir = parent
	return ""


## Where to look by default: the project folder (editor runs) and the .exe folder.
static func default_search_roots() -> PackedStringArray:
	var roots: PackedStringArray = []
	if not OS.has_feature("template"):
		roots.append(ProjectSettings.globalize_path("res://"))
	roots.append(OS.get_executable_path().get_base_dir())
	return roots


## A tiny synchronous HTTP POST (for app exit, when no frames run any more).
## Returns the HTTP status code, or 0 on failure / timeout.
static func blocking_post(host: String, p_port: int, path: String, headers: PackedStringArray, timeout_ms: int) -> int:
	var client := HTTPClient.new()
	if client.connect_to_host(host, p_port) != OK:
		return 0
	var deadline: int = Time.get_ticks_msec() + timeout_ms
	while client.get_status() in [HTTPClient.STATUS_CONNECTING, HTTPClient.STATUS_RESOLVING]:
		client.poll()
		if Time.get_ticks_msec() > deadline:
			return 0
		OS.delay_msec(10)
	if client.get_status() != HTTPClient.STATUS_CONNECTED:
		return 0
	if client.request(HTTPClient.METHOD_POST, path, headers, "") != OK:
		return 0
	while client.get_status() == HTTPClient.STATUS_REQUESTING:
		client.poll()
		if Time.get_ticks_msec() > deadline:
			return 0
		OS.delay_msec(10)
	var code: int = client.get_response_code() if client.has_response() else 0
	client.close()
	return code
