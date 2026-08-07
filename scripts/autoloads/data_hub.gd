extends Node
## Autoload "Data": loads game data and provides localized text helpers.
## Language mode lives in Game.settings ("both" | "zh" | "en").

func _ready() -> void:
	GameData.load_all()


func lang_mode() -> String:
	return Game.settings.get("lang_mode", "both")


## Localized UI string by key from strings.json.
func t(key: String) -> String:
	var e: Dictionary = GameData.strings.get(key, {})
	if e.is_empty():
		return key
	return bi(e.get("zh", key), e.get("en", key))


## Bilingual formatting per settings: "中文 English" / 中 / EN.
## For NAMES and short labels — see `bi2` for anything sentence-length.
func bi(zh: String, en: String) -> String:
	match lang_mode():
		"zh": return zh
		"en": return en
		_: return "%s %s" % [zh, en] if zh != en else zh


## Bilingual join for SENTENCES: one language per line. Side by side, two full
## sentences read as one run-on string with a space in the middle of it —
## "…可被暈眩取消 Raging Combo: announced on turns 3, 6, 9…" — which is worse
## than either language alone. Anything longer than a label goes through here.
func bi2(zh: String, en: String) -> String:
	match lang_mode():
		"zh": return zh
		"en": return en
		_: return zh if zh == en else "%s\n%s" % [zh, en]


## Keyword description line, e.g. "中毒 Poison:回合結束受層數傷…".
## Thin passthrough — `Glossary` owns the text, and data/glossary.json owns
## `Glossary`.
func kw_line(kw: String) -> String:
	return Glossary.line(kw)


## Short keyword name only, e.g. "中毒 Poison".
func kw_name(kw: String) -> String:
	return Glossary.term_name(kw)


## Forge/event enchants show as a "+" per upgrade appended to the face name
## (斬擊 → 斬擊+ → 斬擊++). The growth keyword does not earn one.
func plus_mark(fd: Dictionary) -> String:
	return "+".repeat(maxi(int(fd.get("plus", 0)), 0))


func face_name_zh(fd: Dictionary) -> String:
	return String(fd.get("zh", "?")) + plus_mark(fd)


func face_name_en(fd: Dictionary) -> String:
	return String(fd.get("en", "?")) + plus_mark(fd)


## Face display name, per language mode, including any "+" marks.
func face_name(fd: Dictionary) -> String:
	return bi(face_name_zh(fd), face_name_en(fd))


## Keywords present on a face (ordered), for tooltips and icon badges.
func face_keywords(fd: Dictionary) -> Array:
	return Glossary.sub_terms(fd)


## Plain-text version of a face's detail card — name, what it does, where it
## goes, then every term it uses spelled out. `DetailCard` shows the same
## content laid out; this is the fallback for anywhere that only takes a string.
func face_tooltip(fd: Dictionary) -> String:
	var lines := [face_name(fd), Glossary.effect_sentence(fd), Glossary.target_line(fd)]
	for kw in Glossary.face_terms(fd):
		lines.append("· " + Glossary.line(kw))
	return "\n".join(lines)
