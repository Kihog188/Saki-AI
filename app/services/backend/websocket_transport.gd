class_name WebSocketTransport
extends WsTransport
## WsTransport on top of Godot's WebSocketPeer.

var _peer: WebSocketPeer = null


func open(url: String) -> int:
	close()
	_peer = WebSocketPeer.new()
	_peer.inbound_buffer_size = 1 << 20 # long replies with sources fit in one frame
	return _peer.connect_to_url(url)


func poll() -> void:
	if _peer != null:
		_peer.poll()


func get_state() -> State:
	if _peer == null:
		return State.CLOSED
	match _peer.get_ready_state():
		WebSocketPeer.STATE_CONNECTING:
			return State.CONNECTING
		WebSocketPeer.STATE_OPEN:
			return State.OPEN
	return State.CLOSED


func send_text(text: String) -> int:
	if get_state() != State.OPEN:
		return ERR_UNCONFIGURED
	return _peer.send_text(text)


func receive() -> PackedStringArray:
	var out: PackedStringArray = []
	if _peer == null:
		return out
	while _peer.get_available_packet_count() > 0:
		var packet: PackedByteArray = _peer.get_packet()
		if _peer.was_string_packet():
			out.append(packet.get_string_from_utf8())
	return out


func close() -> void:
	if _peer != null:
		_peer.close()
		_peer = null
