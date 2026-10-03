class_name SaveService
extends RefCounted

## Сервис надёжного локального сохранения с атомарной записью и резервной копией

const QuestRulesScript = preload("res://scripts/domain/quest_rules.gd")

const DEFAULT_SAVE_PATH: String = "user://savegame.json"
const DEFAULT_TMP_PATH: String = "user://savegame.tmp"
const DEFAULT_BACKUP_PATH: String = "user://savegame.backup.1.json"
const DEFAULT_BACKUP_PATHS: Array[String] = [
	"user://savegame.backup.1.json",
	"user://savegame.backup.2.json",
	"user://savegame.backup.3.json"
]
const LEGACY_BACKUP_PATH: String = "user://savegame.backup.json"
const SCHEMA_VERSION: String = "1.3.0"
const SUPPORTED_SCHEMAS := ["1.0.0", "1.1.0", "1.2.0", "1.3.0"]

static var _last_error: Dictionary = {}
static var _write_blocked := false

static var SAVE_PATH: String = DEFAULT_SAVE_PATH
static var TMP_PATH: String = DEFAULT_TMP_PATH
static var BACKUP_PATH: String = DEFAULT_BACKUP_PATH
static var BACKUP_PATHS: Array[String] = [
	"user://savegame.backup.1.json",
	"user://savegame.backup.2.json",
	"user://savegame.backup.3.json"
]

static func use_test_storage(prefix: String = "user://test_") -> void:
	_last_error = {}
	_write_blocked = false
	SAVE_PATH = prefix + "savegame.json"
	TMP_PATH = prefix + "savegame.tmp"
	BACKUP_PATH = prefix + "savegame.backup.1.json"
	BACKUP_PATHS = [
		prefix + "savegame.backup.1.json",
		prefix + "savegame.backup.2.json",
		prefix + "savegame.backup.3.json"
	]

static func restore_default_storage() -> void:
	_last_error = {}
	_write_blocked = false
	SAVE_PATH = DEFAULT_SAVE_PATH
	TMP_PATH = DEFAULT_TMP_PATH
	BACKUP_PATH = DEFAULT_BACKUP_PATH
	BACKUP_PATHS = [
		"user://savegame.backup.1.json",
		"user://savegame.backup.2.json",
		"user://savegame.backup.3.json"
	]

static func cleanup_test_storage() -> void:
	# A forgotten use_test_storage must never delete a family profile.
	if SAVE_PATH == DEFAULT_SAVE_PATH:
		return
	for path in [SAVE_PATH, TMP_PATH, premigration_snapshot_path(), premigration_snapshot_path() + ".tmp"] + BACKUP_PATHS:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	restore_default_storage()

static func get_last_error() -> Dictionary:
	return _last_error.duplicate(true)

static func is_write_blocked() -> bool:
	return _write_blocked

static func premigration_snapshot_path() -> String:
	return SAVE_PATH + ".premigration-original.json"

static func _fail(reason: String, message: String) -> bool:
	_last_error = {"ok": false, "reason": reason, "message": message}
	return false

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
			"atlas_unlocked": ["station"],
			"rituals": {
				"movement_warmup": {
					"days": [],
					"target_days": 5,
					"unlocked": false
				}
			}
		},
		"adventures": {"progress": {}, "grants": {}, "reward_lineages": {}, "pending_presentations": {}},
		"collections": {"works": {}, "exhibits": {}, "rooms": {}, "placements": {}, "snapshots": {}},
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
	return _write_game(data, false)

static func _write_game(data: Dictionary, explicit_restore: bool) -> bool:
	_last_error = {}
	if ProjectSettings.globalize_path(TMP_PATH) == ProjectSettings.globalize_path(SAVE_PATH):
		return _fail("invalid_storage_paths", "Основной и временный файл должны быть разными.")
	if (_write_blocked and not explicit_restore) or bool(data.get("read_only", false)) or not _is_supported_schema(data):
		return _fail("unsupported_schema", "Этот профиль доступен только для чтения. Откройте его совместимой версией SUR.")
	# Recheck disk: a newer client may have written it since our last load.
	var previous := _try_read_file(SAVE_PATH)
	if not previous.is_empty() and not _is_supported_schema(previous) and not explicit_restore:
		_write_blocked = true
		return _fail("unsupported_schema", "Основной файл создан несовместимой версией SUR; запись отменена.")
	if not previous.is_empty() and str(previous.get("schema_version", "1.0.0")) != SCHEMA_VERSION and not explicit_restore:
		if not _preserve_original(SAVE_PATH):
			return false
	var candidate := _merge_with_defaults(data.duplicate(true))
	candidate["updated_at"] = Time.get_datetime_string_from_system()
	candidate.erase("recovery_notice")
	candidate.erase("read_only")
	var json_str := JSON.stringify(candidate, "  ")
	var file := FileAccess.open(TMP_PATH, FileAccess.WRITE)
	if file == null:
		return _fail("temporary_open_failed", "Не удалось открыть временный файл сохранения.")
	file.store_string(json_str)
	file.flush()
	var write_error := file.get_error()
	file.close()
	if write_error != OK:
		return _fail("temporary_write_failed", "Не удалось записать временный файл сохранения.")
	# Compare exact bytes too: syntactically valid truncation is not a successful write.
	if FileAccess.get_file_as_string(TMP_PATH) != json_str or _try_read_file(TMP_PATH).is_empty():
		return _fail("temporary_verification_failed", "Проверка временного файла сохранения не пройдена.")
	# Backups are copied, never moved from the main path. A failed rotation or
	# rename leaves the entire last committed main file available.
	if not previous.is_empty():
		for index in range(BACKUP_PATHS.size() - 1, 0, -1):
			if FileAccess.file_exists(BACKUP_PATHS[index - 1]):
				if not _copy_backup(BACKUP_PATHS[index - 1], BACKUP_PATHS[index]):
					return _fail("backup_failed", "Не удалось сохранить резервную копию; основной файл сохранён.")
		if not _copy_backup(SAVE_PATH, BACKUP_PATHS[0]):
			return _fail("backup_failed", "Не удалось сохранить резервную копию; основной файл сохранён.")
	# Same-filesystem rename replaces an existing file atomically; never unlink
	# SAVE_PATH first. On platforms unable to replace, fail without deleting it.
	var err := DirAccess.rename_absolute(ProjectSettings.globalize_path(TMP_PATH), ProjectSettings.globalize_path(SAVE_PATH))
	if err != OK:
		return _fail("atomic_replace_failed", "Не удалось заменить сохранение; прежний файл сохранён.")
	data["schema_version"] = SCHEMA_VERSION
	data["updated_at"] = candidate["updated_at"]
	_write_blocked = false
	return true

## The UI calls this only for an explicit family restoration. Ordinary saves,
## reset and load never replace an unsupported file. Preserve its exact bytes
## outside the rotating backups before committing the selected candidate.
static func restore_snapshot(snapshot: Dictionary) -> Dictionary:
	_last_error = {}
	if not _is_supported_schema(snapshot) or snapshot.is_empty() or bool(snapshot.get("read_only", false)):
		_fail("unsupported_restore_schema", "Выбранный снимок требует совместимую версию SUR.")
		return get_last_error()
	var candidate := _merge_with_defaults(snapshot.duplicate(true))
	for key in ["phase_b", "phase_c", "adventures", "collections", "settings"]:
		if not candidate.get(key) is Dictionary:
			_fail("invalid_restore_snapshot", "Выбранный снимок содержит повреждённый раздел: " + key)
			return get_last_error()
	candidate.erase("recovery_notice")
	var preserved_file := ""
	if FileAccess.file_exists(SAVE_PATH):
		preserved_file = SAVE_PATH + ".before-restore-" + str(Time.get_unix_time_from_system()).replace(".", "_") + "-" + str(Time.get_ticks_usec()) + ".json"
		if DirAccess.copy_absolute(ProjectSettings.globalize_path(SAVE_PATH), ProjectSettings.globalize_path(preserved_file)) != OK or FileAccess.get_sha256(SAVE_PATH) != FileAccess.get_sha256(preserved_file):
			_fail("restore_preservation_failed", "Не удалось сохранить исходный файл перед восстановлением.")
			return get_last_error()
	if not _write_game(candidate, true):
		return get_last_error()
	return {"ok": true, "state": candidate, "preserved_file": preserved_file}

static func restore_from_backup(path: String) -> Dictionary:
	var snapshot := _try_read_file(path)
	if snapshot.is_empty():
		_fail("invalid_backup", "Выбранная резервная копия не читается.")
		return get_last_error()
	return restore_snapshot(snapshot)

static func list_recovery_snapshots() -> Array[Dictionary]:
	var results: Array[Dictionary] = []
	var paths: Array[String] = BACKUP_PATHS.duplicate()
	paths.append(premigration_snapshot_path())
	if SAVE_PATH == DEFAULT_SAVE_PATH:
		paths.append(LEGACY_BACKUP_PATH)
	for path in paths:
		var snapshot := _try_read_file(path)
		if snapshot.is_empty():
			continue
		results.append({"path": path, "name": path.get_file(), "schema_version": str(snapshot.get("schema_version", "1.0.0")), "supported": _is_supported_schema(snapshot), "updated_at": str(snapshot.get("updated_at", ""))})
	return results

static func _copy_backup(source: String, destination: String) -> bool:
	if not DirAccess.dir_exists_absolute(ProjectSettings.globalize_path(destination.get_base_dir())):
		return false
	return DirAccess.copy_absolute(ProjectSettings.globalize_path(source), ProjectSettings.globalize_path(destination)) == OK

static func load_game() -> Dictionary:
	_last_error = {}
	_write_blocked = false
	var state := _try_read_file(SAVE_PATH)
	if not state.is_empty():
		if not _is_supported_schema(state):
			_write_blocked = true
			_fail("unsupported_schema", "Сохранение создано другой версией SUR. Используйте совместимую версию; исходный профиль сохранён.")
			state["read_only"] = true
			state["recovery_notice"] = {"kind": "unsupported_schema", "main_save_preserved": true, "message": _last_error["message"]}
			return state
		if str(state.get("schema_version", "1.0.0")) != SCHEMA_VERSION and not _preserve_original(SAVE_PATH):
			state["read_only"] = true
			_write_blocked = true
			return state
		return _merge_with_defaults(state)

	var recovery_paths: Array[String] = BACKUP_PATHS.duplicate()
	# Test/custom storage may never fall through into the real profile backup.
	if SAVE_PATH == DEFAULT_SAVE_PATH:
		recovery_paths.append(LEGACY_BACKUP_PATH)
	for backup_path in recovery_paths:
		var backup_state := _try_read_file(backup_path)
		if backup_state.is_empty() or not _is_supported_schema(backup_state):
			continue
		if str(backup_state.get("schema_version", "1.0.0")) != SCHEMA_VERSION:
			var original_path := SAVE_PATH if FileAccess.file_exists(SAVE_PATH) else backup_path
			if not _preserve_original(original_path):
				backup_state["read_only"] = true
				_write_blocked = true
				return backup_state
		var restored := _merge_with_defaults(backup_state)
		restored["recovery_notice"] = {"kind": "backup_loaded", "source": backup_path.get_file(), "main_save_preserved": FileAccess.file_exists(SAVE_PATH)}
		return restored

	var fresh_state := get_default_state()
	if not FileAccess.file_exists(SAVE_PATH):
		save_game(fresh_state)
	else:
		_write_blocked = true
		_fail("no_valid_snapshot", "Файл сохранения повреждён; исходный файл сохранён для восстановления.")
		fresh_state["read_only"] = true
		fresh_state["recovery_notice"] = {"kind": "no_valid_snapshot", "main_save_preserved": true}
	return fresh_state

static func _preserve_original(source_path: String) -> bool:
	var destination := premigration_snapshot_path()
	# This snapshot is independent from rotating backups and is never replaced.
	if FileAccess.file_exists(destination):
		return true
	var temporary := destination + ".tmp"
	if DirAccess.copy_absolute(ProjectSettings.globalize_path(source_path), ProjectSettings.globalize_path(temporary)) != OK:
		return _fail("premigration_backup_failed", "Не удалось сохранить исходный файл перед миграцией.")
	if FileAccess.get_sha256(source_path) != FileAccess.get_sha256(temporary):
		return _fail("premigration_backup_failed", "Копия исходного файла не прошла проверку.")
	if DirAccess.rename_absolute(ProjectSettings.globalize_path(temporary), ProjectSettings.globalize_path(destination)) != OK:
		return _fail("premigration_backup_failed", "Не удалось зафиксировать копию исходного файла.")
	return true

static func reset_save() -> Dictionary:
	# Even reset cannot silently destroy a file from a newer client.
	var existing := _try_read_file(SAVE_PATH)
	if _write_blocked or (not existing.is_empty() and not _is_supported_schema(existing)):
		return load_game()
	for path in [SAVE_PATH, TMP_PATH] + BACKUP_PATHS:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	if SAVE_PATH == DEFAULT_SAVE_PATH and FileAccess.file_exists(LEGACY_BACKUP_PATH):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(LEGACY_BACKUP_PATH))
	var fresh := get_default_state()
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
	
	var parser := JSON.new()
	if parser.parse(text) == OK and parser.data is Dictionary:
		return parser.data as Dictionary
	return {}

static func _merge_with_defaults(loaded: Dictionary) -> Dictionary:
	if not _is_supported_schema(loaded):
		return loaded
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
	return SUPPORTED_SCHEMAS.has(version)
