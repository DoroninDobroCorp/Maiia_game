class_name ContentValidation
extends RefCounted

const ContentRepositoryScript = preload("res://scripts/services/content_repository.gd")

const ALLOWED_SCHEMA_VERSION := 1
const MAX_TEXT_LENGTH := 1200
const FORBIDDEN_KEYS: Array[String] = [
	"approved", "is_approved", "script", "script_path", "path", "file_path",
	"url", "command", "shell", "exec", "action", "actions", "class_name", "resource_path"
]

static func validate_quest(quest: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if int(quest.get("schema_version", -1)) != ALLOWED_SCHEMA_VERSION:
		errors.append("Неизвестная schema_version.")
	if str(quest.get("quest_id", "")).strip_edges().is_empty():
		errors.append("Нужен quest_id.")
	if int(quest.get("revision", 0)) <= 0:
		errors.append("revision должен быть положительным.")
	if str(quest.get("title", "")).strip_edges().is_empty():
		errors.append("Нужно название.")
	if _contains_forbidden_payload(quest):
		errors.append("Пакет содержит запрещённые действия, пути, URL или исполняемые поля.")

	var criteria_value: Variant = quest.get("completion_criteria", [])
	if typeof(criteria_value) != TYPE_ARRAY:
		errors.append("completion_criteria должен быть массивом.")

	var variants_value: Variant = quest.get("variants", [])
	var variants: Array = []
	if typeof(variants_value) != TYPE_ARRAY:
		errors.append("variants должен быть массивом.")
	else:
		variants = variants_value as Array
		for variant in variants:
			if typeof(variant) != TYPE_DICTIONARY or str((variant as Dictionary).get("id", "")).strip_edges().is_empty():
				errors.append("Каждый вариант должен быть объектом с непустым id.")
				break

	var reward_value: Variant = quest.get("reward_policy", {})
	if typeof(reward_value) != TYPE_DICTIONARY:
		errors.append("reward_policy должен быть объектом.")
	else:
		var reward := reward_value as Dictionary
		var budget := int(reward.get("activity_budget", 0))
		if budget < 0 or budget > 500:
			errors.append("Некорректный бюджет награды.")
		var weights_value: Variant = reward.get("skill_weights_percent", {})
		var total_weight := 0
		if typeof(weights_value) != TYPE_DICTIONARY:
			errors.append("skill_weights_percent должен быть объектом.")
		else:
			var weights := weights_value as Dictionary
			for skill_id in weights.keys():
				if not ContentRepositoryScript.SKILLS.has(str(skill_id)):
					errors.append("Неизвестное направление: " + str(skill_id))
				total_weight += int(weights[skill_id])
			if budget > 0 and total_weight != 100:
				errors.append("Сумма весов навыков должна быть 100.")
			if budget == 0 and total_weight != 0:
				errors.append("Для нулевой награды веса должны быть пустыми.")
		var effects_value: Variant = reward.get("world_effect_ids", [])
		if typeof(effects_value) != TYPE_ARRAY:
			errors.append("world_effect_ids должен быть массивом.")
		else:
			for effect_id in effects_value as Array:
				if not ContentRepositoryScript.WORLD_EFFECT_IDS.has(str(effect_id)):
					errors.append("Неизвестный эффект мира: " + str(effect_id))
		if reward.has("milestones_percent"):
			var milestones_value: Variant = reward.get("milestones_percent", [])
			if typeof(milestones_value) != TYPE_ARRAY:
				errors.append("milestones_percent должен быть массивом.")
			else:
				var milestone_total := 0
				for milestone in milestones_value as Array:
					var percent := int(milestone)
					if percent <= 0 or percent > 100:
						errors.append("Каждая веха должна быть от 1 до 100 процентов.")
					milestone_total += percent
				if milestone_total > 100:
					errors.append("Сумма вех не должна превышать 100 процентов.")

	var repeat_value: Variant = quest.get("repeat_policy", {})
	if typeof(repeat_value) != TYPE_DICTIONARY:
		errors.append("repeat_policy должен быть объектом.")
	else:
		var repeat_policy := repeat_value as Dictionary
		if not repeat_policy.is_empty():
			var repeat_mode := str(repeat_policy.get("mode", "once"))
			if not ["once", "limited", "unlimited"].has(repeat_mode):
				errors.append("Неизвестный режим повторения.")
			var max_completions := int(repeat_policy.get("max_completions", 1))
			if repeat_mode == "once" and max_completions != 1:
				errors.append("Режим once допускает ровно одно завершение.")
			if repeat_mode == "limited" and (max_completions < 2 or max_completions > 12):
				errors.append("Ограниченный повтор допускает от 2 до 12 завершений.")

	if bool(quest.get("is_main_quest", false)) and typeof(variants_value) == TYPE_ARRAY:
		var has_home_path := false
		for variant in variants:
			if typeof(variant) == TYPE_DICTIONARY and bool(variant.get("home_available", false)):
				has_home_path = true
		if not has_home_path:
			errors.append("Для сюжетного квеста нужен хотя бы один домашний путь.")

	return {"valid": errors.is_empty(), "errors": errors}

static func validate_package(package: Dictionary) -> Dictionary:
	if int(package.get("schema_version", -1)) != ALLOWED_SCHEMA_VERSION:
		return {"valid": false, "errors": ["Неизвестная schema_version пакета."]}
	if _contains_forbidden_payload(package):
		return {"valid": false, "errors": ["Пакет содержит запрещённые действия, пути, URL или исполняемые поля."]}
	var quest: Dictionary = package.get("quest", package)
	# Любая попытка принести собственное одобрение игнорируется на уровне импорта,
	# но наличие поля всё равно не превращается в взрослое решение.
	quest.erase("approved")
	quest.erase("is_approved")
	quest["content_status"] = "DRAFT"
	var result := validate_quest(quest)
	result["sanitized_quest"] = quest.duplicate(true)
	return result

static func content_hash(quest: Dictionary) -> String:
	var copy := quest.duplicate(true)
	copy.erase("content_status")
	copy.erase("approved")
	copy.erase("is_approved")
	return _canonical_string(copy).sha256_text()

static func _contains_forbidden_payload(value: Variant) -> bool:
	match typeof(value):
		TYPE_DICTIONARY:
			var dict := value as Dictionary
			for key in dict.keys():
				var key_text := str(key).to_lower()
				if FORBIDDEN_KEYS.has(key_text):
					return true
				if _contains_forbidden_payload(dict[key]):
					return true
		TYPE_ARRAY:
			for item in value as Array:
				if _contains_forbidden_payload(item):
					return true
		TYPE_STRING:
			var text := str(value)
			if text.length() > MAX_TEXT_LENGTH:
				return true
			var lower := text.to_lower()
			if lower.contains("res://") or lower.contains("user://") or lower.contains("file://"):
				return true
			if lower.contains("http://") or lower.contains("https://"):
				return true
	return false

static func _canonical_string(value: Variant) -> String:
	match typeof(value):
		TYPE_DICTIONARY:
			var dict := value as Dictionary
			var keys: Array = dict.keys()
			keys.sort_custom(func(a, b): return str(a) < str(b))
			var parts: Array[String] = []
			for key in keys:
				parts.append(JSON.stringify(str(key)) + ":" + _canonical_string(dict[key]))
			return "{" + ",".join(parts) + "}"
		TYPE_ARRAY:
			var arr_parts: Array[String] = []
			for item in value as Array:
				arr_parts.append(_canonical_string(item))
			return "[" + ",".join(arr_parts) + "]"
		_:
			return JSON.stringify(value)
