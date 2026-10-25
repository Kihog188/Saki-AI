class_name TestFakes
## Fake transports and launcher for backend tests. No network, no processes.


class FakeWs:
	extends WsTransport
	var state: WsTransport.State = WsTransport.State.CLOSED
	var sent: Array[Dictionary] = []
	var inbox: PackedStringArray = []
	var opened_urls: PackedStringArray = []
	## What the next open() leads to on the next poll: OPEN or CLOSED (handshake fails).
	var next_open_result: WsTransport.State = WsTransport.State.OPEN
	var _pending_open: bool = false

	func open(url: String) -> int:
		opened_urls.append(url)
		state = WsTransport.State.CONNECTING
		_pending_open = true
		return OK

	func poll() -> void:
		if _pending_open:
			_pending_open = false
			state = next_open_result

	func get_state() -> WsTransport.State:
		return state

	func send_text(text: String) -> int:
		if state != WsTransport.State.OPEN:
			return ERR_UNCONFIGURED
		sent.append(JSON.parse_string(text))
		return OK

	func receive() -> PackedStringArray:
		var out: PackedStringArray = inbox
		inbox = PackedStringArray()
		return out

	func push(event: Dictionary) -> void:
		inbox.append(JSON.stringify(event))

	func drop() -> void:
		state = WsTransport.State.CLOSED

	func close() -> void:
		state = WsTransport.State.CLOSED


class FakeHttp:
	extends HttpTransport
	## url suffix -> response {"result", "code", "data"}; default = connection refused.
	var routes: Dictionary = {}
	var calls: Array[Dictionary] = []

	func request(method: HTTPClient.Method, url: String, body: Variant = null, _headers: PackedStringArray = [], _timeout: float = 10.0) -> Dictionary:
		calls.append({"method": method, "url": url, "body": body})
		await get_tree().process_frame
		var path: String = url.substr(url.find("/", 8))
		for key: String in routes:
			if path == key or path.begins_with(key + "?"):
				return routes[key]
		return {"result": HTTPRequest.RESULT_CANT_CONNECT, "code": 0, "data": null}

	## The fake port is "open" when a /health route exists (or `listening` is forced).
	var listening: bool = false

	func port_open(_host: String, _port: int, _timeout: float = 3.0) -> bool:
		await get_tree().process_frame
		return listening or routes.has("/health")

	static func ok(data: Variant, code: int = 200) -> Dictionary:
		return {"result": HTTPRequest.RESULT_SUCCESS, "code": code, "data": data}

	static func health(protocol: int = 1, reachable: bool = true) -> Dictionary:
		return ok({"status": "ok", "version": "0.1.0", "protocol_version": protocol, "llm": {"reachable": reachable}})


class FakeLauncher:
	extends ProcessLauncher
	var started: Array[Dictionary] = []
	var running: Dictionary = {}
	var killed: Array[int] = []
	var next_pid: int = 4242
	## Called after start() (e.g. to make the fake health route answer).
	var on_start: Callable = Callable()

	func start(path: String, args: PackedStringArray, env: Dictionary) -> int:
		started.append({"path": path, "args": args, "env": env})
		running[next_pid] = true
		if on_start.is_valid():
			on_start.call()
		return next_pid

	func is_running(pid: int) -> bool:
		return running.get(pid, false)

	func kill_tree(pid: int) -> void:
		killed.append(pid)
		running.erase(pid)
