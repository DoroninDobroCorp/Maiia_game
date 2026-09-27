class_name SaveService
extends RefCounted

## Сервис надёжного локального сохранения с атомарной записью и резервной копией

const QuestRulesScript = preload("res://scripts/domain/quest_rules.gd")

const SAVE_PATH: String = "user://savegame.json"
const TMP_PATH: String = "user://savegame.tmp"
const BACKUP_PATH: String = "user://savegame.backup.1.json"
const BACKUP_PATHS: Array[String] = [
	"user://savegame.backup.1.json",
	"user://savegame.backup.2.json",
	"user://savegame.backup.3.json"
]
const LEGACY_BACKUP_PATH: String = "user://savegame.backup.json"
const SCHEMA_VERSION: String = "1.2.0"

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
		"phase_b": {
			"approval_records": [],
			"published_versions": {},
			"retired_versions": [],
			"revoked_versions": [],
			"quest_instances": {},
			"activities": {},
			"award_events": {},
			"skill_xp_by_profile": {},
			"world_effects": [],
			"world_effects_by_profile": {},
			"artifacts": {},
			"author_patches": {},
			"dialogue_overrides": {}
		},
		"phase_c": {
			"custom_quests": {},
			"import_history": [],
			"locations_unlocked": ["radio_cafe", "workshop_annex", "field_archive"],
			"atlas_unlocked": ["station"]
		},
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
	
	# Шаг 3: Ротация трёх последних целых снимков.
	var dir: DirAccess = DirAccess.open("user://")
	if dir == null:
		push_error("SaveService: не удалось открыть директорию user://")
		return false
	
	if FileAccess.file_exists(BACKUP_PATHS[2]):
		dir.remove("savegame.backup.3.json")
	if FileAccess.file_exists(BACKUP_PATHS[1]):
		dir.rename(BACKUP_PATHS[1], BACKUP_PATHS[2])
	if FileAccess.file_exists(BACKUP_PATHS[0]):
		dir.rename(BACKUP_PATHS[0], BACKUP_PATHS[1])
	if FileAccess.file_exists(SAVE_PATH):
		dir.copy(SAVE_PATH, BACKUP_PATHS[0])
		dir.remove("savegame.json")
	
	# Шаг 4: Атомарное перемещение временного файла на место основного
	var err: Error = dir.rename(TMP_PATH, SAVE_PATH)
	if err != OK:
		push_error("SaveService: ошибка перемещения файла сохранения: " + str(err))
		return false
	
	return true

static func load_game() -> Dictionary:
	var state: Dictionary = _try_read_file(SAVE_PATH)
	if not state.is_empty() and _is_supported_schema(state):
		return _merge_with_defaults(state)

	# Повреждённый/неподдерживаемый основной файл не перезаписываем.
	# Возвращаем первый проверенный предыдущий снимок и оставляем заметку для UI.
	var recovery_paths: Array[String] = BACKUP_PATHS.duplicate()
	recovery_paths.append(LEGACY_BACKUP_PATH)
	for backup_path in recovery_paths:
		var backup_state: Dictionary = _try_read_file(backup_path)
		if backup_state.is_empty() or not _is_supported_schema(backup_state):
			continue
		push_warning("SaveService: основной снимок недоступен, загружена резервная копия: " + backup_path)
		var restored := _merge_with_defaults(backup_state)
		restored["recovery_notice"] = {
			"kind": "backup_loaded",
			"source": backup_path.get_file(),
			"main_save_preserved": FileAccess.file_exists(SAVE_PATH)
		}
		return restored
	
	print("SaveService: файлы сохранения не найдены. Создаём чистый профиль по умолчанию.")
	var fresh_state: Dictionary = get_default_state()
	if not FileAccess.file_exists(SAVE_PATH):
		save_game(fresh_state)
	else:
		fresh_state["recovery_notice"] = {
			"kind": "no_valid_snapshot",
			"main_save_preserved": true
		}
	return fresh_state

static func reset_save() -> Dictionary:
	var dir: DirAccess = DirAccess.open("user://")
	if dir != null:
		if FileAccess.file_exists(SAVE_PATH):
			dir.remove("savegame.json")
		for backup_path in BACKUP_PATHS:
			if FileAccess.file_exists(backup_path):
				dir.remove(backup_path.get_file())
		if FileAccess.file_exists(LEGACY_BACKUP_PATH):
			dir.remove(LEGACY_BACKUP_PATH.get_file())
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
	_merge_dictionary_defaults(loaded, defaults)
	loaded["schema_version"] = SCHEMA_VERSION
	return loaded

static func _merge_dictionary_defaults(target: Dictionary, defaults: Dictionary) -> void:
	for key in defaults.keys():
		if not target.has(key):
			target[key] = defaults[key].duplicate(true) if typeof(defaults[key]) in [TYPE_DICTIONARY, TYPE_ARRAY] else defaults[key]
		elif typeof(defaults[key]) == TYPE_DICTIONARY and typeof(target[key]) == TYPE_DICTIONARY:
			_merge_dictionary_defaults(target[key] as Dictionary, defaults[key] as Dictionary)

static func _is_supported_schema(state: Dictionary) -> bool:
	var version := str(state.get("schema_version", "1.0.0"))
	return version == "1.0.0" or version == "1.1.0" or version == SCHEMA_VERSION
