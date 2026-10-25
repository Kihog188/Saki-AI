class_name SourcesList
extends VBoxContainer
## "[n] title — display_url (date)" lines under a search answer. Clicking opens the
## default browser, only for http/https URLs (ChatFormat.is_openable_url).


func set_sources(sources: Array) -> void:
	for c: Node in get_children():
		c.queue_free()
	visible = not sources.is_empty()
	for s: Variant in sources:
		if not s is Dictionary:
			continue
		var b := Button.new()
		b.theme_type_variation = &"SourceButton"
		b.text = ChatFormat.format_source(s)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var url: String = s.get("url", "")
		b.disabled = not ChatFormat.is_openable_url(url)
		b.tooltip_text = url if not b.disabled else tr("SOURCE_NO_LINK")
		b.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		b.pressed.connect(func() -> void:
			if ChatFormat.is_openable_url(url):
				OS.shell_open(url))
		add_child(b)
