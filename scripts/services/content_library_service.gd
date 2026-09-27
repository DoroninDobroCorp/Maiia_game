class_name ContentLibraryService
extends RefCounted

## Phase C: локальный каталог редактируемого содержания.
## Сервис хранит только данные. Публикация по-прежнему проходит через
## QuestService, поэтому импортированный пакет не может сам себя одобрить.

const ContentRepositoryScript = preload("res://scripts/services/content_repository.gd")
const ContentValidationScript = preload("res://scripts/domain/content_validation.gd")
const QuestServiceScript = preload("res://scripts/services/quest_service.gd")

const PACKAGE_SCHEMA_VERSION := 1
const PACKAGE_TYPE := "sur_quest_pack"
const MAX_PACKAGE_QUESTS := 50

static func ensure_phase_c(state: Dictionary) -> Dictionary:
	var phase_c: Dictionary = state.get("phase_c", {})
	if not phase_c.has("custom_quests"):
		phase_c["custom_quests"] = {}
	if not phase_c.has("import_history"):
		phase_c["import_history"] = []
	if not phase_c.has("locations_unlocked"):
		phase_c["locations_unlocked"] = ["radio_cafe", "workshop_annex", "field_archive"]
	state["phase_c"] = phase_c
	return phase_c

static func list_parent_templates(state: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = ContentRepositoryScript.real_quest_templates()
	result.append_array(ContentRepositoryScript.phase_c_templates())
	var custom: Dictionary = ensure_phase_c(state).get("custom_quests", {})
	for quest_value in custom.values():
		if typeof(quest_value) == TYPE_DICTIONARY:
			result.append((quest_value as Dictionary).duplicate(true))
	result.sort_custom(_sort_quests)
	return result

static func get_template(state: Dictionary, quest_id: String, revision: int = -1) -> Dictionary:
	var candidates: Array[Dictionary] = []
	for quest in list_parent_templates(state):
		if str(quest.get("quest_id", "")) != quest_id:
			continue
		if revision > 0 and int(quest.get("revision", 0)) != revision:
			continue
		candidates.append(quest)
	if candidates.is_empty():
		return {}
	candidates.sort_custom(func(a, b): return int(a.get("revision", 0)) > int(b.get("revision", 0)))
	return candidates[0].duplicate(true)

static func save_draft(state: Dictionary, quest: Dictionary) -> Dictionary:
	var draft := quest.duplicate(true)
	draft["content_status"] = "DRAFT"
	draft.erase("approved")
	draft.erase("is_approved")
	var checked := ContentValidationScript.validate_quest(draft)
	if not bool(checked.get("valid", false)):
		return {"ok": false, "reason": "validation_failed", "errors": checked.get("errors", [])}

	var qid := str(draft.get("quest_id", ""))
	var revision := int(draft.get("revision", 0))
	var key := QuestServiceScript.version_key(qid, revision)
	var published: Dictionary = state.get("phase_b", {}).get("published_versions", {})
	if published.has(key):
		return {"ok": false, "reason": "published_revision_locked", "message": "Опубликованную ревизию нельзя переписывать. Создайте следующую."}

	var builtin := ContentRepositoryScript.get_template(qid)
	if not builtin.is_empty() and int(builtin.get("revision", 0)) == revision:
		return {"ok": false, "reason": "builtin_revision_locked", "message": "Встроенную ревизию нельзя менять. Создайте копию revision + 1."}

	var phase_c := ensure_phase_c(state)
	var custom: Dictionary = phase_c.get("custom_quests", {})
	draft["provenance"] = draft.get("provenance", {}).duplicate(true)
	(draft["provenance"] as Dictionary)["origin"] = str((draft["provenance"] as Dictionary).get("origin", "parent_editor"))
	custom[key] = draft
	phase_c["custom_quests"] = custom
	state["phase_c"] = phase_c
	return {"ok": true, "version_key": key, "quest": draft.duplicate(true)}

static func delete_draft(state: Dictionary, quest_id: String, revision: int) -> Dictionary:
	var key := QuestServiceScript.version_key(quest_id, revision)
	if (state.get("phase_b", {}).get("published_versions", {}) as Dictionary).has(key):
		return {"ok": false, "reason": "published_revision_locked"}
	var phase_c := ensure_phase_c(state)
	var custom: Dictionary = phase_c.get("custom_quests", {})
	if not custom.has(key):
		return {"ok": false, "reason": "not_custom_draft"}
	custom.erase(key)
	phase_c["custom_quests"] = custom
	state["phase_c"] = phase_c
	return {"ok": true}

static func import_package(state: Dictionary, package: Dictionary) -> Dictionary:
	if int(package.get("schema_version", -1)) != PACKAGE_SCHEMA_VERSION:
		return {"ok": false, "reason": "unsupported_package_schema"}
	if str(package.get("package_type", "")) != PACKAGE_TYPE:
		return {"ok": false, "reason": "wrong_package_type"}
	var quests_value: Variant = package.get("quests", [])
	if typeof(quests_value) != TYPE_ARRAY:
		return {"ok": false, "reason": "quests_must_be_array"}
	var quests: Array = quests_value
	if quests.is_empty() or quests.size() > MAX_PACKAGE_QUESTS:
		return {"ok": false, "reason": "invalid_quest_count"}

	# Сначала валидируем пакет целиком. Ошибка одной карточки не оставляет
	# половину импорта в состоянии игры.
	var prepared: Array[Dictionary] = []
	var errors: Array[String] = []
	var seen_keys: Dictionary = {}
	var existing_custom: Dictionary = state.get("phase_c", {}).get("custom_quests", {})
	for index in range(quests.size()):
		if typeof(quests[index]) != TYPE_DICTIONARY:
			errors.append("Карточка %d не является объектом." % (index + 1))
			continue
		# Approval is deliberately outside the package format. We accept legacy/
		# hand-authored files that carry these flags, strip them, and still require
		# a separate local parent publication afterwards.
		var incoming_quest := (quests[index] as Dictionary).duplicate(true)
		incoming_quest.erase("approved")
		incoming_quest.erase("is_approved")
		var checked := ContentValidationScript.validate_package({"schema_version": 1, "quest": incoming_quest})
		if not bool(checked.get("valid", false)):
			for err in checked.get("errors", []):
				errors.append("Карточка %d: %s" % [index + 1, str(err)])
			continue
		var quest: Dictionary = checked.get("sanitized_quest", {})
		var qid := str(quest.get("quest_id", ""))
		var revision := int(quest.get("revision", 0))
		var key := QuestServiceScript.version_key(qid, revision)
		if seen_keys.has(key):
			errors.append("Карточка %d: %s дублируется внутри пакета." % [index + 1, key])
			continue
		seen_keys[key] = true
		if (state.get("phase_b", {}).get("published_versions", {}) as Dictionary).has(key):
			errors.append("Карточка %d: %s уже опубликована и заблокирована." % [index + 1, key])
			continue
		if existing_custom.has(key):
			errors.append("Карточка %d: %s уже существует как локальный черновик; используйте следующую ревизию." % [index + 1, key])
			continue
		var builtin := ContentRepositoryScript.get_template(qid)
		if not builtin.is_empty() and int(builtin.get("revision", 0)) == revision:
			errors.append("Карточка %d: %s — встроенная ревизия; используйте revision + 1." % [index + 1, key])
			continue
		quest["provenance"] = {"origin": "imported_pack", "package_id": str(package.get("package_id", "local_pack"))}
		prepared.append(quest)
	if not errors.is_empty():
		return {"ok": false, "reason": "package_validation_failed", "errors": errors}

	var phase_c := ensure_phase_c(state)
	var custom: Dictionary = phase_c.get("custom_quests", {})
	for quest in prepared:
		custom[QuestServiceScript.version_key(str(quest.get("quest_id", "")), int(quest.get("revision", 0)))] = quest.duplicate(true)
	phase_c["custom_quests"] = custom
	var history: Array = phase_c.get("import_history", [])
	history.append({
		"package_id": str(package.get("package_id", "local_pack")),
		"quest_count": prepared.size(),
		"imported_at": Time.get_datetime_string_from_system()
	})
	phase_c["import_history"] = history
	state["phase_c"] = phase_c
	return {"ok": true, "imported": prepared.size()}

static func import_package_json(state: Dictionary, json_text: String) -> Dictionary:
	var parsed: Variant = JSON.parse_string(json_text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "invalid_json"}
	return import_package(state, parsed as Dictionary)

static func build_export_package(state: Dictionary) -> Dictionary:
	var quests: Array[Dictionary] = []
	var custom: Dictionary = ensure_phase_c(state).get("custom_quests", {})
	for quest_value in custom.values():
		if typeof(quest_value) == TYPE_DICTIONARY:
			var quest := (quest_value as Dictionary).duplicate(true)
			quest["content_status"] = "DRAFT"
			quests.append(quest)
	quests.sort_custom(_sort_quests)
	return {
		"schema_version": PACKAGE_SCHEMA_VERSION,
		"package_type": PACKAGE_TYPE,
		"package_id": "sur-local-export",
		"quests": quests
	}

static func list_locations(state: Dictionary) -> Array[Dictionary]:
	var unlocked: Array = ensure_phase_c(state).get("locations_unlocked", [])
	var result: Array[Dictionary] = []
	for location in ContentRepositoryScript.PHASE_C_LOCATIONS:
		var copy := location.duplicate(true)
		copy["unlocked"] = unlocked.has(str(copy.get("location_id", "")))
		result.append(copy)
	return result

static func _sort_quests(a: Dictionary, b: Dictionary) -> bool:
	var aq := str(a.get("quest_id", ""))
	var bq := str(b.get("quest_id", ""))
	if aq == bq:
		return int(a.get("revision", 0)) < int(b.get("revision", 0))
	return aq < bq
