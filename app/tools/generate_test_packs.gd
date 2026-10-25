extends SceneTree
## Generates test packs for the pack-list performance check.
##
##   godot --headless --path app -s res://tools/generate_test_packs.gd -- --count 200 [--dev]
##
## Without --dev the packs go to %APPDATA%\Saki\characters (as if imported); with --dev to
## characters_dev. Delete the test-pack-* folders afterwards to clean up.


func _init() -> void:
	var count: int = 200
	var dev: bool = false
	var args: PackedStringArray = OS.get_cmdline_user_args()
	for i: int in args.size():
		if args[i] == "--count" and i + 1 < args.size():
			count = int(args[i + 1])
		elif args[i] == "--dev":
			dev = true
	var root: String = SakiConst.DEV_PACKS_DIR if dev else SakiConst.USER_PACKS_DIR
	var t0: int = Time.get_ticks_msec()
	TestPackGenerator.generate(root, count)
	print("Created %d packs in %s (%d ms)" % [count, ProjectSettings.globalize_path(root), Time.get_ticks_msec() - t0])
	quit(0)
