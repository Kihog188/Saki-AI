class_name PackAutoManifest
## Builds a format-1 manifest for a pack that has no manifest.json: "just a folder of
## images". Pure logic on file names (no file access, no UI), so the validator, the
## importer and a future Studio share it.
##
## Rules (PACK_GUIDE.md, "Cách đơn giản"):
## - Only images at the pack root are used. Names are matched case-insensitively.
## - "<name>.png" is a static image; "<name>_<n>.png" are animation frames (FRAME_FPS,
##   loop, ordered by n). Frames win over a static image of the same name (warning).
## - <name> is one of SakiConst.EMOTIONS (-> emotions) or STATE_NAMES (-> states).
## - No neutral image: the first image (by name) becomes neutral (warning).
## - Every other file is ignored and listed in one warning; nothing ignored is ever read.

const FRAME_FPS: float = 8.0
## App states a plain folder can provide ("thinking" is already an emotion name).
const STATE_NAMES: PackedStringArray = ["idle", "talking"]
## Files the OS creates by itself: ignored without a warning.
const JUNK_FILES: PackedStringArray = ["thumbs.db", "desktop.ini", ".ds_store"]
const MAX_NAME_CHARS: int = 60
const FALLBACK_ID: String = "nhan-vat"
const _ID_CHARS: String = "abcdefghijklmnopqrstuvwxyz0123456789"
## Vietnamese letters -> ASCII, for the pack id.
const _FOLD: Dictionary = {
	"a": "àáạảãâầấậẩẫăằắặẳẵ", "e": "èéẹẻẽêềếệểễ", "i": "ìíịỉĩ",
	"o": "òóọỏõôồốộổỗơờớợởỡ", "u": "ùúụủũưừứựửữ", "y": "ỳýỵỷỹ", "d": "đ",
}

static var _frame_re: RegEx
static var _fold_map: Dictionary = {}


## files: paths relative to the pack root (any names, as found). pack_name: the folder or
## zip name. Returns {"data": Dictionary (the manifest as a JSON object; its id is
## slug(name), the importer makes it unique), "warnings": PackedStringArray (Vietnamese),
## "error": String ("" = ok)}.
static func build(files: PackedStringArray, pack_name: String) -> Dictionary:
	if _frame_re == null:
		_frame_re = RegEx.create_from_string("^([a-z][a-z0-9_]*?)_([0-9]{1,4})$")
	var sorted: Array = Array(files)
	sorted.sort_custom(func(a: String, b: String) -> bool: return a.naturalnocasecmp_to(b) < 0)

	var singles: Dictionary = {} # name -> file
	var frames: Dictionary = {} # name -> Array of [number, file]
	var first_image: String = ""
	var unused: PackedStringArray = []
	for f: String in sorted:
		if JUNK_FILES.has(f.get_file().to_lower()):
			continue
		var usable: bool = not f.contains("/") and PackRules.is_image(f) and PackRules.check_path(f) == ""
		if not usable:
			unused.append(f)
			continue
		if first_image == "":
			first_image = f
		var base: String = f.get_basename().to_lower()
		var m: RegExMatch = _frame_re.search(base)
		if m != null and _known(m.get_string(1)):
			var key: String = m.get_string(1)
			if not frames.has(key):
				frames[key] = []
			frames[key].append([int(m.get_string(2)), f])
		elif _known(base) and not singles.has(base):
			singles[base] = f
		else:
			unused.append(f) # unknown name, or a second extension of the same name

	var warnings: PackedStringArray = []
	for key: String in frames:
		if singles.has(key):
			warnings.append(I18n.t("PACK_AUTO_FRAMES_WIN", {"file": singles[key], "name": key}))
			singles.erase(key)
		frames[key].sort_custom(func(a: Array, b: Array) -> bool:
			return a[0] < b[0] or (a[0] == b[0] and String(a[1]).naturalnocasecmp_to(b[1]) < 0))

	var emotions: Dictionary = {}
	var states: Dictionary = {}
	for key: String in Array(SakiConst.EMOTIONS) + Array(STATE_NAMES):
		var entry: Dictionary = {}
		if frames.has(key):
			var list: Array = []
			for pair: Array in frames[key]:
				list.append(pair[1])
			entry = {"frames": list, "fps": FRAME_FPS, "loop": true}
		elif singles.has(key):
			entry = {"image": singles[key]}
		if entry.is_empty():
			continue
		if STATE_NAMES.has(key):
			states[key] = entry
		else:
			emotions[key] = entry

	if not emotions.has(SakiConst.DEFAULT_EMOTION):
		if first_image == "":
			return {"data": {}, "warnings": warnings, "error": I18n.t("PACK_AUTO_NO_IMAGES")}
		emotions[SakiConst.DEFAULT_EMOTION] = {"image": first_image}
		var idx: int = unused.find(first_image)
		if idx >= 0:
			unused.remove_at(idx)
		warnings.append(I18n.t("PACK_AUTO_NO_NEUTRAL", {"file": first_image}))

	if not unused.is_empty():
		var shown: PackedStringArray = unused.slice(0, 5)
		var more: String = "" if unused.size() <= 5 else " " + I18n.t("PACK_AUTO_MORE", {"n": unused.size() - 5})
		warnings.append(I18n.t("PACK_AUTO_IGNORED", {"n": unused.size(), "files": ", ".join(shown) + more}))

	var name: String = pack_name.strip_edges().left(MAX_NAME_CHARS).strip_edges()
	if name == "":
		name = I18n.t("PACK_AUTO_DEFAULT_NAME")
	var data: Dictionary = {
		"format": PackManifest.FORMAT, "id": slug(name), "name": name, "author": "",
		"version": "", "license": "", "type": "2d",
		"default_emotion": SakiConst.DEFAULT_EMOTION, "emotions": emotions,
	}
	if not states.is_empty():
		data["states"] = states
	return {"data": data, "warnings": warnings, "error": ""}


## A valid pack id from any name: "Saki Hồng" -> "saki-hong".
static func slug(text: String) -> String:
	if _fold_map.is_empty():
		for ascii: String in _FOLD:
			for ch: String in String(_FOLD[ascii]):
				_fold_map[ch] = ascii
	var out: String = ""
	for ch: String in text.to_lower():
		var code: int = ch.unicode_at(0)
		if code >= 0x300 and code <= 0x36F:
			continue # combining accent (decomposed text, e.g. names from macOS)
		ch = _fold_map.get(ch, ch)
		out += ch if _ID_CHARS.contains(ch) else "-"
	while out.contains("--"):
		out = out.replace("--", "-")
	out = out.left(64).trim_prefix("-").trim_suffix("-")
	return out if PackRules.is_valid_id(out) else FALLBACK_ID


static func _known(name: String) -> bool:
	return SakiConst.EMOTIONS.has(name) or STATE_NAMES.has(name)
