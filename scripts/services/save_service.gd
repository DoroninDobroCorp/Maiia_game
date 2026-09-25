class_name SaveService
extends RefCounted

## Сервис надёжного локального сохранения с атомарной записью и резервной копией

const QuestRulesScript = preload("res://scripts/domain/quest_rules.gd")

const SAVE_PATH: String = "user://savegame.json"
const TMP_PATH: String = "user://savegame.tmp"
const BACKUP_PATH: String = "user://savegame.backup.json"
const SCHEMA_VERSION: String = "1.0.0"

static func get_default_state() -> Dictionary:
	return {
		"schema_version": SCHEMA_VERSION,
		"updated_at": Time.get_datetime_string_from_system(),
		"station_name": "Лесная станция",
		"station_emblem": "star",
		"desk_prop_id": "compass",
		"puzzle_solved": false,
		"puzzle_state": [1, 2, 1], # Начальное неверное положение дисков
		"radio_powered": false,
		"s00_progress": QuestRulesScript.create_default_progress(),
		"achievements": [],
		"settings": {
			"master_volume": 0.8,
			"music_volume": 0.7,
			"sfx_volume": 0.8,
			"muted": false,
			"ui_scale": 1.0,
			"reduce_motion": false
		}
	}

static func save_game(data: Dictionary) -> bool:
	data["updated_at"] = Time.get_datetime_string_from_system()
	data["schema_version"] = SCHEMA_VERSION
	
	var json_str: String = JSON.stringify(data, "  ")
	
	# Шаг 1: Запись во временный файл
	var file: FileAccess = FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if file == null:
		push_error("SaveService: не удалось открыть временный файл для записи: " + TMP_PATH)
		return false
	
	file.store_string(json_str)
	file.flush()
	file.close()
	
	# Шаг 2: Проверка целостности временного файла
	var verify_file: FileAccess = FileAccess.open(TMP_PATH, FileAccess.READ)
	if verify_file == null:
		push_error("SaveService: временный файл не читается после записи.")
		return false
	var content: String = verify_file.get_as_text()
	verify_file.close()
	
	var test_parse: Variant = JSON.parse_string(content)
	if test_parse == null or typeof(test_parse) != TYPE_DICTIONARY:
		push_error("SaveService: ошибка парсинга временного файла. Сохранение прервано.")
		return false
	
	# Шаг 3: Ротация старого сохранения в резервную копию
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		push_error("SaveService: не удалось открыть директорию user://")
		return false
	
	if FileAccess.file_exists(SAVE_PATH):
		if FileAccess.file_exists(BACKUP_PATH):
			dir.remove("savegame.backup.json")
		dir.copy(SAVE_PATH, BACKUP_PATH)
		dir.remove("savegame.json")
	
	# Шаг 4: Атомарное перемещение временного файла на место основного
	var err: Error = dir.rename(TMP_PATH, SAVE_PATH)
	if err != OK:
		push_error("SaveService: ошибка перемещения файла сохранения: " + str(err))
		return false
	
	return true

static func load_game() -> Dictionary:
	var state: Dictionary = _try_read_file(SAVE_PATH)
	if not state.is_empty():
		return _merge_with_defaults(state)
	
	# Попытка восстановить из резервной копии
	if FileAccess.file_exists(BACKUP_PATH):
		push_warning("SaveService: основное сохранение повреждено, читаем резервную копию...")
		var backup_state: Dictionary = _try_read_file(BACKUP_PATH)
		if not backup_state.is_empty():
			return _merge_with_defaults(backup_state)
	
	print("SaveService: файлы сохранения не найдены. Создаём чистый профиль по умолчанию.")
	var fresh_state: Dictionary = get_default_state()
	save_game(fresh_state)
	return fresh_state

static func reset_save() -> Dictionary:
	var dir: DirAccess = DirAccess.open("user://")
	if dir != null:
		if FileAccess.file_exists(SAVE_PATH):
			dir.remove("savegame.json")
		if FileAccess.file_exists(BACKUP_PATH):
			dir.remove("savegame.backup.json")
		if FileAccess.file_exists(TMP_PATH):
			dir.remove("savegame.tmp")
	var fresh: Dictionary = get_default_state()
	save_game(fresh)
	return fresh

static func _try_read_file(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {}
	
	var file: FileAccess = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	
	var text: String = file.get_as_text()
	file.close()
	
	var parsed: Variant = JSON.parse_string(text)
	if parsed != null and typeof(parsed) == TYPE_DICTIONARY:
		return parsed as Dictionary
	return {}

static func _merge_with_defaults(loaded: Dictionary) -> Dictionary:
	var defaults: Dictionary = get_default_state()
	for key: String in defaults:
		if not loaded.has(key):
			loaded[key] = defaults[key]
		elif typeof(defaults[key]) == TYPE_DICTIONARY and typeof(loaded[key]) == TYPE_DICTIONARY:
			var default_sub: Dictionary = defaults[key] as Dictionary
			var loaded_sub: Dictionary = loaded[key] as Dictionary
			for sub_key: String in default_sub:
				if not loaded_sub.has(sub_key):
					loaded_sub[sub_key] = default_sub[sub_key]
	return loaded
