class_name WsTransport
extends RefCounted
## Interface of a WebSocket connection, so BackendClient can be tested with a fake.
## The real one is WebSocketTransport (Godot's WebSocketPeer). All calls are non-blocking;
## the owner calls poll() every frame.

enum State { CLOSED, CONNECTING, OPEN }


## Starts connecting. Returns OK or an error code.
func open(_url: String) -> int:
	return ERR_UNAVAILABLE


func poll() -> void:
	pass


func get_state() -> State:
	return State.CLOSED


func send_text(_text: String) -> int:
	return ERR_UNAVAILABLE


## Every text frame received since the last call, oldest first.
func receive() -> PackedStringArray:
	return PackedStringArray()


func close() -> void:
	pass
