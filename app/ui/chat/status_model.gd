class_name StatusModel
## What the status line says, from the connection, model and turn state. Pure, tested.
##
## Result: {"text": String, "level": "ok" | "busy" | "warn" | "error",
##          "action": "" | "retry_llm" | "restart_backend"}


static func describe(conn: StringName, conn_message: String, llm_reachable: bool, turn: String) -> Dictionary:
	match conn:
		SakiConst.CONN_STARTING:
			return _r(I18n.t("STATUS_STARTING"), "busy")
		SakiConst.CONN_CONNECTING:
			return _r(I18n.t("STATUS_CONNECTING"), "busy")
		SakiConst.CONN_DISCONNECTED:
			return _r(conn_message if conn_message != "" else I18n.t("STATUS_DISCONNECTED"), "error")
		SakiConst.CONN_FAILED:
			return _r(conn_message if conn_message != "" else I18n.t("STATUS_DISCONNECTED"), "error", "restart_backend")
	match turn:
		"searching":
			return _r(I18n.t("STATUS_SEARCHING"), "busy")
		"thinking", "streaming":
			return _r(I18n.t("STATUS_THINKING"), "busy")
	if not llm_reachable:
		return _r(I18n.t("LLM_DOWN_HINT"), "warn", "retry_llm")
	return _r(I18n.t("STATUS_READY"), "ok")


static func _r(text: String, level: String, action: String = "") -> Dictionary:
	return {"text": text, "level": level, "action": action}
