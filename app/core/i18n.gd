class_name I18n
## Translation helper usable from static functions and RefCounted classes.
##
## I18n.t("PACK_ERR_SYMLINK", {"file": "a.png"}) looks the key up in i18n/strings.csv and fills
## {placeholders}. Nodes may also use tr("KEY") directly; both forms are checked by
## tests/unit/test_translations.gd.


static func t(key: String, args: Dictionary = {}) -> String:
	var text: String = String(TranslationServer.translate(key))
	return text.format(args) if not args.is_empty() else text
