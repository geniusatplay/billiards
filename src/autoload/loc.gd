extends Node
## Language selection, autoloaded as `Loc`. The translations themselves are assets/i18n/strings.csv
## (one column per language, the English text is the key); Godot imports that file and Labels / Buttons
## translate their text by themselves. Code that builds a sentence calls L.t() on each piece.
##
## Setting "language": "auto" (follow the phone) or one of the codes below.

signal language_changed

## code, name in its own language (shown in the language picker)
const LANGS := [["en", "English"], ["es", "Español"], ["fr", "Français"], ["de", "Deutsch"], ["pt", "Português"],
	["it", "Italiano"], ["nl", "Nederlands"], ["sv", "Svenska"], ["pl", "Polski"], ["cs", "Čeština"], ["ro", "Română"],
	["tr", "Türkçe"], ["el", "Ελληνικά"], ["ru", "Русский"], ["uk", "Українська"], ["id", "Bahasa Indonesia"],
	["ms", "Bahasa Melayu"], ["vi", "Tiếng Việt"], ["th", "ไทย"], ["ja", "日本語"], ["ko", "한국어"], ["zh", "简体中文"],
	["zh_TW", "繁體中文"], ["ar", "العربية"], ["he", "עברית"], ["ur", "اردو"], ["hi", "हिन्दी"], ["mr", "मराठी"],
	["bn", "বাংলা"], ["pa", "ਪੰਜਾਬੀ"], ["ta", "தமிழ்"], ["te", "తెలుగు"]]


func _ready() -> void:
	apply()


func codes() -> Array:
	return LANGS.map(func(l): return l[0])


## The supported language that matches the phone's language, or English.
func detect(system_locale := "") -> String:
	var loc := (system_locale if system_locale != "" else OS.get_locale()).replace("-", "_")
	var parts := loc.split("_")
	var lang := parts[0].to_lower()
	if lang == "zh":
		# Traditional script, or Taiwan / Hong Kong / Macau, gets Traditional Chinese; everything else Simplified
		for p in parts.slice(1):
			if p.to_lower() in ["hant", "tw", "hk", "mo"]:
				return "zh_TW"
			if p.to_lower() == "hans":
				return "zh"
		return "zh"
	lang = {"in": "id", "iw": "he"}.get(lang, lang)   # Android still reports the old codes for Indonesian and Hebrew
	return lang if lang in codes() else "en"


## The language in use now.
func current() -> String:
	var want := str(Game.get_s("language"))
	return want if want in codes() else detect()


func native_name(code: String) -> String:
	for l in LANGS:
		if l[0] == code:
			return l[1]
	return code


func apply() -> void:
	var code := current()
	UIKit.set_language(code)   # the fallback fonts depend on the language (Chinese / Japanese / Korean)
	if TranslationServer.get_locale() != code:
		TranslationServer.set_locale(code)
	language_changed.emit()


## "auto" or a language code.
func set_language(choice: String) -> void:
	Game.set_s("language", choice if choice in codes() else "auto")
	apply()
