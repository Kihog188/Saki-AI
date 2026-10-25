class_name SakiTheme
extends Resource
## Colours and sizes of one app theme. Themes are data: ui/theme/light.tres and dark.tres.
## ThemeBuilder turns this into a Godot Theme applied to every window.

@export var id: String = "light"
@export var font_size: int = 15
@export var corner_radius: int = 10

@export_group("Colours")
@export var background: Color = Color("#f7f3f6")
@export var panel: Color = Color("#ffffff")
@export var text: Color = Color("#2b2230")
@export var text_muted: Color = Color("#7a6f80")
@export var border: Color = Color("#e3d9e3")
@export var accent: Color = Color("#d9577f")
@export var accent_text: Color = Color("#ffffff")
@export var user_bubble: Color = Color("#fbe1ea")
@export var assistant_bubble: Color = Color("#ffffff")
@export var system_bubble: Color = Color("#eef0f6")
@export var error_bubble: Color = Color("#fde8e6")
@export var error_text: Color = Color("#a12a1d")
@export var warn_text: Color = Color("#8a5a00")
@export var code_background: Color = Color("#2b2730")
@export var code_text: Color = Color("#f2eef4")
@export var link: Color = Color("#2a6fb0")
