class_name L
## Translation helper usable anywhere (also in scripts that run without the autoloads).
## The key is the English text; see assets/i18n/strings.csv.


static func t(text: String) -> String:
	return str(TranslationServer.translate(text))


## Upper case that is right for the language in use: Greek capitals drop their accents, and the Turkish
## capital of i is İ.
static func up(text: String) -> String:
	var loc := TranslationServer.get_locale()
	if loc.begins_with("el"):
		for pair in [["ά", "α"], ["έ", "ε"], ["ή", "η"], ["ί", "ι"], ["ό", "ο"], ["ύ", "υ"], ["ώ", "ω"], ["ΐ", "ϊ"], ["ΰ", "ϋ"]]:
			text = text.replace(pair[0], pair[1])
	elif loc.begins_with("tr"):
		text = text.replace("i", "İ")
	return text.to_upper()
