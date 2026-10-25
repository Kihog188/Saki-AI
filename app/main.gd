extends Node
## Main scene: boots the App and hosts the current display mode and global overlays.


func _ready() -> void:
	App.boot()
	var overlay := DebugOverlay.new()
	overlay.setup(App.performance, App.packs, App.settings)
	add_child(overlay)
	if App.settings.get_value("auto_tier") == "":
		await get_tree().process_frame # let the window appear first
		App.run_tier_detection()
