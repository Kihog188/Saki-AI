class_name ChatFormat
## Text helpers shared by the chat components of every mode. Pure functions, tested.
##
## Model and search text is UNTRUSTED: it is only ever shown with Label/TextEdit (plain
## text), never as BBCode, and links are opened only for http/https URLs.


## Splits text into plain and ``` code ``` segments: [{"code": bool, "text": String}].
## An unclosed fence makes the rest code. A language tag after the opening fence is dropped.
static func segments(text: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var parts: PackedStringArray = text.split("```")
	for i: int in parts.size():
		var part: String = parts[i]
		var is_code: bool = i % 2 == 1
		if is_code:
			var nl: int = part.find("\n")
			if nl >= 0 and nl < 20 and not part.substr(0, nl).strip_edges().contains(" "):
				part = part.substr(nl + 1) # "python\n..." -> "..."
			part = part.trim_suffix("\n")
		else:
			part = part.strip_edges(i > 0, i < parts.size() - 1)
		if part != "" or is_code:
			out.append({"code": is_code, "text": part})
	return out


## "[1] Tiêu đề — dantri.com.vn (19/10/2026) (trả phí)"; "không rõ ngày" without a date.
static func format_source(s: Dictionary) -> String:
	var shown_url: String = s.get("display_url", "") if s.get("display_url", "") != "" else s.get("url", "")
	var date: String = format_date(s.get("date", ""))
	var line: String = "[%d] %s — %s (%s)" % [int(s.get("index", 0)), s.get("title", ""), shown_url,
		date if date != "" else I18n.t("SOURCE_NO_DATE")]
	if s.get("paywalled", false):
		line += " " + I18n.t("SOURCE_PAYWALLED")
	return line


## "2026-10-19" -> "19/10/2026"; anything else -> "".
static func format_date(iso: String) -> String:
	var p: PackedStringArray = iso.split("-")
	if p.size() != 3 or not p[0].is_valid_int() or not p[1].is_valid_int() or not p[2].is_valid_int():
		return ""
	return "%s/%s/%s" % [p[2].pad_zeros(2), p[1].pad_zeros(2), p[0]]


## Only plain http(s) URLs may be opened in the browser.
static func is_openable_url(url: String) -> bool:
	var u: String = url.strip_edges()
	if u != url or u.length() > 2048:
		return false
	var lower: String = u.to_lower()
	if not (lower.begins_with("http://") or lower.begins_with("https://")):
		return false
	for c: int in u.to_utf8_buffer():
		if c <= 0x20 or c == 0x7F:
			return false
	return u.length() > lower.find("//") + 2


## How long the pet's speech bubble stays after a reply (seconds).
static func bubble_seconds(text: String) -> float:
	return minf(SakiConst.BUBBLE_BASE_SEC + SakiConst.BUBBLE_PER_CHAR_SEC * text.length(), SakiConst.BUBBLE_MAX_SEC)


## Text for the speech bubble: cut at a word boundary. {"text": String, "truncated": bool}
static func bubble_text(text: String, max_chars: int = SakiConst.BUBBLE_MAX_CHARS) -> Dictionary:
	var t: String = text.strip_edges()
	if t.length() <= max_chars:
		return {"text": t, "truncated": false}
	var cut: String = t.left(max_chars)
	var space: int = cut.rfind(" ")
	if space > max_chars * 0.6:
		cut = cut.left(space)
	return {"text": cut.strip_edges() + "…", "truncated": true}
