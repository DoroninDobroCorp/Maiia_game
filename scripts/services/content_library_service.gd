class_name ContentLibraryService
extends RefCounted

## Phase C: локальный каталог редактируемого содержания.
## Сервис хранит только данные. Публикация по-прежнему проходит через
## QuestService, поэтому импортированный пакет не может сам себя одобрить.

const ContentRepositoryScript = preload("res://scripts/services/content_repository.gd")
const ContentValidationScript = preload("res://scripts/domain/content_validation.gd")
const AdventureContentScript = preload("res://scripts/services/adventure_content.gd")

const PACKAGE_SCHEMA_VERSION := 2
const MAX_PACKAGE_BYTES := 8 * 1024 * 1024
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

static func list_builtin_templates() -> Array[Dictionary]:
	var result: Array[Dictionary] = ContentRepositoryScript.real_quest_templates()
	result.append_array(ContentRepositoryScript.phase_c_templates())
	result.append_array(AdventureContentScript.quests())
	return result

static func get_builtin_template(quest_id: String, revision: int) -> Dictionary:
	for quest in list_builtin_templates():
		if str(quest.get("quest_id", "")) == quest_id and int(quest.get("revision", 0)) == revision:
			return quest.duplicate(true)
	return {}

static func list_parent_templates(state: Dictionary) -> Array[Dictionary]:
	# Merge by revision; family-owned revisions and published snapshots take
	# precedence if they occupied an ID before a later builtin was installed.
	var by_version: Dictionary = {}
	for quest in list_builtin_templates():
		by_version[_version_key(str(quest.quest_id), int(quest.revision))] = quest
	var result: Array[Dictionary] = []
	var custom: Dictionary = ensure_phase_c(state).get("custom_quests", {})
	for quest_value in custom.values():
		if typeof(quest_value) == TYPE_DICTIONARY:
			var quest: Dictionary = quest_value
			by_version[_version_key(str(quest.get("quest_id", "")), int(quest.get("revision", 0)))] = quest.duplicate(true)
	var published: Dictionary = state.get("phase_b", {}).get("published_versions", {})
	for key in published:
		var record: Dictionary = published[key] if published[key] is Dictionary else {}
		var snapshot: Variant = record.get("quest_snapshot", record.get("quest", {}))
		if snapshot is Dictionary and not snapshot.is_empty():
			by_version[key] = snapshot.duplicate(true)
	for quest in by_version.values():
		result.append(quest.duplicate(true))
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
	var key := _version_key(qid, revision)
	var published: Dictionary = state.get("phase_b", {}).get("published_versions", {})
	if published.has(key):
		return {"ok": false, "reason": "published_revision_locked", "message": "Опубликованную ревизию нельзя переписывать. Создайте следующую."}

	var builtin := get_builtin_template(qid, revision)
	if not builtin.is_empty():
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
	var key := _version_key(quest_id, revision)
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
	if not ContentValidationScript._integer(package.get("schema_version")) or not [1, 2].has(int(package.get("schema_version", -1))):
		return {"ok": false, "reason": "unsupported_package_schema"}
	if str(package.get("package_type", "")) != PACKAGE_TYPE:
		return {"ok": false, "reason": "wrong_package_type"}
	var quests_value: Variant = package.get("quests", [])
	if typeof(quests_value) != TYPE_ARRAY:
		return {"ok": false, "reason": "quests_must_be_array"}
	var quests: Array = quests_value
	if quests.is_empty() or quests.size() > MAX_PACKAGE_QUESTS:
		return {"ok": false, "reason": "invalid_quest_count"}

	var sanitized_package := package.duplicate(true)
	for quest_value in sanitized_package.get("quests", []):
		if quest_value is Dictionary:
			quest_value.erase("approved")
			quest_value.erase("is_approved")
	var package_check := ContentValidationScript.validate_package(sanitized_package)
	if not bool(package_check.get("valid", false)):
		return {"ok": false, "reason": "package_validation_failed", "errors": package_check.get("errors", [])}
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
		var checked := ContentValidationScript.validate_package({"schema_version": package.get("schema_version", 1), "quest": incoming_quest})
		if not bool(checked.get("valid", false)):
			for err in checked.get("errors", []):
				errors.append("Карточка %d: %s" % [index + 1, str(err)])
			continue
		var quest: Dictionary = checked.get("sanitized_quest", {})
		var qid := str(quest.get("quest_id", ""))
		var revision := int(quest.get("revision", 0))
		var key := _version_key(qid, revision)
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
		var builtin := get_builtin_template(qid, revision)
		if not builtin.is_empty():
			errors.append("Карточка %d: %s — встроенная ревизия; используйте revision + 1." % [index + 1, key])
			continue
		quest["provenance"] = {"origin": "imported_pack", "package_id": str(package.get("package_id", "local_pack"))}
		prepared.append(quest)
	if not errors.is_empty():
		return {"ok": false, "reason": "package_validation_failed", "errors": errors}

	var phase_c := ensure_phase_c(state)
	var custom: Dictionary = phase_c.get("custom_quests", {})
	for quest in prepared:
		custom[_version_key(str(quest.get("quest_id", "")), int(quest.get("revision", 0)))] = quest.duplicate(true)
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
	if json_text.to_utf8_buffer().size() > MAX_PACKAGE_BYTES:
		return {"ok": false, "reason": "package_too_large"}
	var parsed: Variant = JSON.parse_string(json_text)
	if parsed == null or typeof(parsed) != TYPE_DICTIONARY:
		return {"ok": false, "reason": "invalid_json"}
	return import_package(state, parsed as Dictionary)

static func build_export_package(state: Dictionary) -> Dictionary:
	var quests: Array[Dictionary] = []
	var custom: Dictionary = ensure_phase_c(state).get("custom_quests", {})
	for quest_value in custom.values():
		if typeof(quest_value) == TYPE_DICTIONARY:
			var quest: Dictionary = _without_approval(quest_value)
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
	var a_first_goal := str(a.get("goal_group", "")) == "maya_first_goals"
	var b_first_goal := str(b.get("goal_group", "")) == "maya_first_goals"
	if a_first_goal != b_first_goal:
		return a_first_goal
	if a_first_goal and b_first_goal:
		var a_order := int(a.get("goal_order", 0))
		var b_order := int(b.get("goal_order", 0))
		if a_order != b_order:
			return a_order < b_order
	var aq := str(a.get("quest_id", ""))
	var bq := str(b.get("quest_id", ""))
	if aq == bq:
		return int(a.get("revision", 0)) < int(b.get("revision", 0))
	return aq < bq

static func next_free_revision(state: Dictionary, quest_id: String) -> int:
	var revision := 1
	for quest in list_parent_templates(state):
		if str(quest.get("quest_id", "")) == quest_id:
			revision = maxi(revision, int(quest.get("revision", 0)) + 1)
	return revision

static func _version_key(quest_id: String, revision: int) -> String:
	return "%s@%d" % [quest_id, revision]

static func _without_approval(value: Variant) -> Variant:
	if value is Dictionary:
		var clean: Dictionary = {}
		for key in value:
			if str(key) in ["approved", "is_approved", "approval_records", "approved_by", "approved_at", "published_versions", "published_by", "published_at", "content_hash"]:
				continue
			clean[key] = _without_approval(value[key])
		return clean
	if value is Array:
		var clean: Array = []
		for item in value:
			clean.append(_without_approval(item))
		return clean
	return value
