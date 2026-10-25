class_name ThemeBuilder
## Builds a Godot Theme from a SakiTheme and picks light/dark ("Theo Windows" follows
## DisplayServer.is_dark_mode()). Components only use the type variations below, never
## hard-coded colours, so a new theme is just a new .tres file.
##
## Type variations: UserBubble, AssistantBubble, SystemBubble, ErrorBubble (PanelContainer),
## CodeBlock (PanelContainer), CodeLabel, MutedLabel, ErrorLabel, WarnLabel, SourceButton
## (Button), AccentButton (Button), Card (PanelContainer).

const LIGHT: String = "res://ui/theme/light.tres"
const DARK: String = "res://ui/theme/dark.tres"
const UI_FONTS: PackedStringArray = ["Segoe UI", "Noto Sans", "Arial", "sans-serif"]
const MONO_FONTS: PackedStringArray = ["Consolas", "Cascadia Mono", "Noto Sans Mono", "Courier New", "monospace"]


## "system" | "light" | "dark" -> the SakiTheme to use.
static func resolve(setting: String) -> SakiTheme:
	var dark: bool = setting == "dark"
	if setting == "system":
		dark = DisplayServer.is_dark_mode_supported() and DisplayServer.is_dark_mode()
	return load(DARK if dark else LIGHT) as SakiTheme


static func build(t: SakiTheme) -> Theme:
	var th := Theme.new()
	var font := SystemFont.new()
	font.font_names = UI_FONTS
	th.default_font = font
	th.default_font_size = t.font_size
	var mono := SystemFont.new()
	mono.font_names = MONO_FONTS

	for type: String in ["Label", "Button", "CheckBox", "CheckButton", "OptionButton", "LineEdit", "TextEdit", "ItemList", "PopupMenu", "LinkButton", "SpinBox"]:
		th.set_color("font_color", type, t.text)
	th.set_color("default_color", "RichTextLabel", t.text)
	th.set_color("selection_color", "RichTextLabel", Color(t.accent, 0.35))
	th.set_color("font_placeholder_color", "LineEdit", t.text_muted)
	th.set_color("font_placeholder_color", "TextEdit", t.text_muted)
	th.set_color("caret_color", "TextEdit", t.text)
	th.set_color("caret_color", "LineEdit", t.text)
	th.set_color("font_hover_color", "Button", t.accent)
	th.set_color("font_pressed_color", "Button", t.accent)
	th.set_color("font_disabled_color", "Button", t.text_muted)

	th.set_stylebox("panel", "PanelContainer", _box(t.background, 0))
	th.set_stylebox("panel", "Panel", _box(t.background, 0))
	th.set_stylebox("panel", "PopupMenu", _box(t.panel, 6, t.border))
	th.set_stylebox("panel", "PopupPanel", _box(t.panel, 6, t.border))
	th.set_stylebox("embedded_border", "Window", _box(t.panel, 0))
	th.set_color("title_color", "Window", t.text)

	var btn: StyleBoxFlat = _box(t.panel, t.corner_radius / 2, t.border)
	btn.set_content_margin_all(6)
	th.set_stylebox("normal", "Button", btn)
	var hover: StyleBoxFlat = btn.duplicate()
	hover.border_color = t.accent
	th.set_stylebox("hover", "Button", hover)
	th.set_stylebox("pressed", "Button", hover)
	th.set_stylebox("focus", "Button", _focus(t))
	var disabled: StyleBoxFlat = btn.duplicate()
	disabled.bg_color = t.background
	th.set_stylebox("disabled", "Button", disabled)
	for type: String in ["OptionButton", "MenuButton"]:
		th.set_stylebox("normal", type, btn)
		th.set_stylebox("hover", type, hover)
		th.set_stylebox("pressed", type, hover)

	var field: StyleBoxFlat = _box(t.panel, t.corner_radius / 2, t.border)
	field.set_content_margin_all(8)
	for type: String in ["LineEdit", "TextEdit"]:
		th.set_stylebox("normal", type, field)
		th.set_stylebox("focus", type, _focus(t))
		th.set_stylebox("read_only", type, field)

	# Type variations used by the components.
	_variation(th, "AccentButton", "Button")
	var accent: StyleBoxFlat = _box(t.accent, t.corner_radius / 2)
	accent.set_content_margin_all(6)
	th.set_stylebox("normal", "AccentButton", accent)
	th.set_stylebox("hover", "AccentButton", accent)
	th.set_stylebox("pressed", "AccentButton", accent)
	th.set_color("font_color", "AccentButton", t.accent_text)
	th.set_color("font_hover_color", "AccentButton", t.accent_text)
	th.set_color("font_pressed_color", "AccentButton", t.accent_text)

	for pair: Array in [["UserBubble", t.user_bubble], ["AssistantBubble", t.assistant_bubble],
			["SystemBubble", t.system_bubble], ["ErrorBubble", t.error_bubble], ["Card", t.panel]]:
		_variation(th, pair[0], "PanelContainer")
		var b: StyleBoxFlat = _box(pair[1], t.corner_radius, t.border if pair[0] != "UserBubble" else Color.TRANSPARENT)
		b.set_content_margin_all(10)
		th.set_stylebox("panel", pair[0], b)

	_variation(th, "CodeBlock", "PanelContainer")
	var code: StyleBoxFlat = _box(t.code_background, 6)
	code.set_content_margin_all(8)
	th.set_stylebox("panel", "CodeBlock", code)
	_variation(th, "CodeLabel", "Label")
	th.set_font("font", "CodeLabel", mono)
	th.set_color("font_color", "CodeLabel", t.code_text)
	th.set_font_size("font_size", "CodeLabel", t.font_size - 1)

	for pair: Array in [["MutedLabel", t.text_muted], ["ErrorLabel", t.error_text], ["WarnLabel", t.warn_text]]:
		_variation(th, pair[0], "Label")
		th.set_color("font_color", pair[0], pair[1])
	th.set_font_size("font_size", "MutedLabel", t.font_size - 2)

	_variation(th, "SourceButton", "Button")
	var flat := StyleBoxEmpty.new()
	for s: String in ["normal", "hover", "pressed", "focus", "disabled"]:
		th.set_stylebox(s, "SourceButton", flat)
	th.set_color("font_color", "SourceButton", t.link)
	th.set_color("font_hover_color", "SourceButton", t.accent)
	th.set_color("font_disabled_color", "SourceButton", t.text_muted)
	th.set_font_size("font_size", "SourceButton", t.font_size - 2)
	return th


static func _variation(th: Theme, name: String, base: String) -> void:
	th.set_type_variation(name, base)


static func _box(color: Color, radius: int, border: Color = Color.TRANSPARENT) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = color
	b.set_corner_radius_all(radius)
	if border.a > 0.0:
		b.border_color = border
		b.set_border_width_all(1)
	return b


static func _focus(t: SakiTheme) -> StyleBoxFlat:
	var f := StyleBoxFlat.new()
	f.draw_center = false
	f.border_color = t.accent
	f.set_border_width_all(2)
	f.set_corner_radius_all(t.corner_radius / 2)
	return f
