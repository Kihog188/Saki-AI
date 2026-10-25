class_name ChatPanel
extends VBoxContainer
## Message list + (optional) status line + input. The chat window uses it full size; the
## pet's mini chat uses the SAME component with compact = true.

var list: MessageList
var input: ChatInput
var status: StatusLine


func setup(ctx: UiContext, compact: bool = false, show_status: bool = false) -> void:
	add_theme_constant_override("separation", 6)
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list = MessageList.new(compact)
	add_child(list)
	list.setup(ctx.session)
	if show_status:
		status = StatusLine.new()
		add_child(status)
		status.setup(ctx)
	input = ChatInput.new()
	add_child(input)
	input.setup(ctx, compact)
