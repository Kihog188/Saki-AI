class_name HttpTransport
extends Node
## Interface for REST calls, so BackendClient can be tested with a fake.
## request() is a coroutine: `var r: Dictionary = await http.request(...)`.
##
## Result: {"result": int (HTTPRequest.RESULT_*), "code": int (HTTP status, 0 if none),
##          "data": Variant (parsed JSON, or null)}


func request(_method: HTTPClient.Method, _url: String, _body: Variant = null, _headers: PackedStringArray = [], _timeout: float = 10.0) -> Dictionary:
	await get_tree().process_frame
	return {"result": HTTPRequest.RESULT_CANT_CONNECT, "code": 0, "data": null}


## True if something accepts TCP connections on host:port. Coroutine. Needed because a
## refused connection and a silent program look the same to HTTPRequest (both time out).
func port_open(host: String, port: int, timeout: float = 3.0) -> bool:
	var tcp := StreamPeerTCP.new()
	if tcp.connect_to_host(host, port) != OK:
		return false
	var deadline: int = Time.get_ticks_msec() + int(timeout * 1000.0)
	while Time.get_ticks_msec() < deadline:
		tcp.poll()
		match tcp.get_status():
			StreamPeerTCP.STATUS_CONNECTED:
				tcp.disconnect_from_host()
				return true
			StreamPeerTCP.STATUS_ERROR, StreamPeerTCP.STATUS_NONE:
				return false
		await get_tree().process_frame
	tcp.disconnect_from_host()
	return false
