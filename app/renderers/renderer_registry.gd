class_name RendererRegistry
## Maps a pack's manifest `type` to the renderer script that draws it.
##
## Adding a renderer = a new folder under renderers/ + ONE line in RENDERERS
## (see "Thêm một bộ vẽ mới trong 5 bước" in ARCHITECTURE.md).
## Nothing else refers to a renderer by name, so deleting a renderer folder only makes
## packs of that type fall back to FallbackRenderer (thumbnail + notice).

const RENDERERS: Dictionary = {
	"2d": "res://renderers/sprite_2d/sprite_renderer.gd",
	"placeholder": "res://renderers/placeholder/placeholder_renderer.gd",
}


## True if a renderer for `type` is registered AND its script is present.
## `table` is only passed by tests (to simulate a deleted renderer folder).
static func has_renderer(type: String, table: Dictionary = RENDERERS) -> bool:
	return table.has(type) and ResourceLoader.exists(table[type])


## A new renderer for `type`, or a FallbackRenderer if the type is unknown/unavailable.
static func create(type: String, table: Dictionary = RENDERERS) -> CharacterRenderer:
	if has_renderer(type, table):
		var script: Script = load(table[type]) as Script
		if script != null and script.can_instantiate():
			var node: Object = script.new()
			if node is CharacterRenderer:
				return node
			if node is Node:
				node.free()
			push_error("Renderer for '%s' does not extend CharacterRenderer" % type)
	elif type != "placeholder":
		push_warning("No renderer for pack type '%s', showing the thumbnail" % type)
	var fallback := FallbackRenderer.new()
	fallback.unsupported = type != "placeholder"
	return fallback


## A renderer for `pack`, with the pack already loaded.
static func create_for_pack(pack: PackData) -> CharacterRenderer:
	var type: String = pack.manifest.type if pack != null else "placeholder"
	var r: CharacterRenderer = create(type)
	r.load_pack(pack)
	return r
