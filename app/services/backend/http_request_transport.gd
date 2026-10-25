class_name HttpRequestTransport
extends HttpTransport
## HttpTransport using one short-lived HTTPRequest node per call.

## Responses larger than this are refused (the backend never sends that much).
const MAX_BODY_BYTES: int = 4 * 1024 * 1024


func request(method: HTTPClient.Method, url: String, body: Variant = null, headers: PackedStringArray = [], timeout: float = 10.0) -> Dictionary:
	var req := HTTPRequest.new()
	req.timeout = timeout
	req.body_size_limit = MAX_BODY_BYTES
	req.accept_gzip = false
	add_child(req)
	var all_headers: PackedStringArray = headers.duplicate()
	var payload: String = ""
	if body != null:
		all_headers.append("Content-Type: application/json")
		payload = JSON.stringify(body)
	var err: int = req.request(url, all_headers, method, payload)
	if err != OK:
		req.queue_free()
		return {"result": HTTPRequest.RESULT_CANT_CONNECT, "code": 0, "data": null}
	var res: Array = await req.request_completed
	req.queue_free()
	var data: Variant = null
	var bytes: PackedByteArray = res[3]
	if bytes.size() > 0:
		var json := JSON.new()
		if json.parse(bytes.get_string_from_utf8()) == OK:
			data = json.data
	return {"result": res[0], "code": res[1], "data": data}
