extends SceneTree
## Windowed benchmark for the "1,000 messages scroll smoothly" check (not a unit test):
## fills a ChatSession with 1,000 messages, then scrolls a MessageList from the bottom to
## the top and back, 60 px per frame like a mouse wheel, and prints frame-time stats.
##
##   godot --path app -s res://tools/message_list_bench.gd

const COUNT: int = 1000
const STEP_PX: int = 60


func _init() -> void:
	_run.call_deferred()


func _run() -> void:
	TranslationServer.set_locale("vi")
	var bus: Node = load("res://core/event_bus.gd").new()
	root.add_child(bus)
	var session := ChatSession.new(bus, null)
	root.add_child(session)
	for i: int in COUNT:
		var text: String = "Tin nhắn số %d. " % i + "Một câu trả lời có độ dài vừa phải để xuống dòng. ".repeat(1 + i % 3)
		session.messages.append(ChatSession._message({"uid": i + 1, "id": i, "role": "user" if i % 2 == 0 else "assistant", "text": text}))
	root.size = Vector2i(480, 720)
	root.theme = ThemeBuilder.build(ThemeBuilder.resolve("light"))
	var bg := PanelContainer.new()
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.add_child(bg)
	var list := MessageList.new()
	bg.add_child(list)
	list.setup(session)
	Engine.max_fps = 0
	OS.low_processor_usage_mode = false
	for _i: int in 10:
		await process_frame
	var times: Array[float] = []
	var max_live: int = 0
	for dir: int in [-1, 1]:
		var guard: int = 0
		while guard < 5000:
			guard += 1
			var t0: int = Time.get_ticks_usec()
			list.scroll_vertical += dir * STEP_PX
			await process_frame
			times.append((Time.get_ticks_usec() - t0) / 1000.0)
			max_live = maxi(max_live, list.live_count())
			if dir < 0 and list.window().x == 0 and list.scroll_vertical == 0:
				break
			if dir > 0 and list.window().y == COUNT and list.get_v_scroll_bar().value + list.get_v_scroll_bar().page >= list.get_v_scroll_bar().max_value - 1:
				break
	times.sort()
	var n: int = times.size()
	var over: int = times.filter(func(t: float) -> bool: return t > 33.3).size()
	print("frames %d, median %.1f ms, p95 %.1f ms, max %.1f ms, frames > 33 ms: %d, max live nodes %d" % [
		n, times[n / 2], times[int(n * 0.95)], times[n - 1], over, max_live])
	quit()
