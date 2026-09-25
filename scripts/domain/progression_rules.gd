class_name ProgressionRules
extends RefCounted

## Логика наград и достижений (Phase A: Пролог S00)

const ACHIEVEMENTS: Dictionary = {
	"station_keeper": {
		"id": "station_keeper",
		"title": "Хозяйка станции",
		"desc": "Выбрано собственное имя станции и символ на табличке.",
		"icon": "🏷️"
	},
	"master_curator": {
		"id": "master_curator",
		"title": "Хранительница реликвий",
		"desc": "На рабочий стол выставлен памятный предмет исследователя.",
		"icon": "🧭"
	},
	"first_world_change": {
		"id": "first_world_change",
		"title": "Первое изменение мира",
		"desc": "Шифр дисков разгадан, лампа включена, радиоканал станции ожил!",
		"icon": "✨"
	}
}

static func unlock_achievement(state_dict: Dictionary, achievement_id: String) -> bool:
	if not ACHIEVEMENTS.has(achievement_id):
		return false
	
	var achievements: Array = state_dict.get("achievements", [])
	for item in achievements:
		if typeof(item) == TYPE_DICTIONARY and item.get("id") == achievement_id:
			return false # Уже получено ранее — защита от дублирования (идемпотентность)
		elif typeof(item) == TYPE_STRING and item == achievement_id:
			return false
	
	var entry: Dictionary = {
		"id": achievement_id,
		"unlocked_at": Time.get_datetime_string_from_system()
	}
	achievements.append(entry)
	state_dict["achievements"] = achievements
	return true

static func has_achievement(state_dict: Dictionary, achievement_id: String) -> bool:
	var achievements: Array = state_dict.get("achievements", [])
	for item in achievements:
		if typeof(item) == TYPE_DICTIONARY and item.get("id") == achievement_id:
			return true
		elif typeof(item) == TYPE_STRING and item == achievement_id:
			return true
	return false

static func get_achievement_info(achievement_id: String) -> Dictionary:
	return ACHIEVEMENTS.get(achievement_id, {})
