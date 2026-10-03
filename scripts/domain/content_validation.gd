class_name ContentValidation
extends RefCounted

const ContentRepositoryScript = preload("res://scripts/services/content_repository.gd")

const ALLOWED_SCHEMA_VERSION := 1
const AdventureContentScript = preload("res://scripts/services/adventure_content.gd")
const SUPPORTED_SCHEMA_VERSIONS := [1, 2]
const MAX_STAGES := 64
const MAX_DIALOGUE_NODES := 256
const MAX_LEXEMES := 1000
const MAX_PACKAGE_QUESTS := 50
const POLICIES := ["automatic", "self_attest", "joint_review"]
const MAIN_BUDGETS := {"FG01": 40, "FG11": 60, "FG08": 40}
const ATLAS_IDS := ["station", "rio_azul", "waterfalls", "piltriquitron", "el_bolson_skatepark", "lago_puelo", "bariloche", "bariloche_skatepark", "chile", "whales", "ushuaia"]
const MAX_TEXT_LENGTH := 1200
const FORBIDDEN_KEYS: Array[String] = [
	"approved", "is_approved", "script", "script_path", "path", "file_path",
	"url", "command", "shell", "exec", "action", "actions", "class_name", "resource_path",
	"executable", "executable_path", "launch_path", "launch_registry", "approval_records", "published_versions"
]

static func validate_quest(quest: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	_validate_base_types(quest, errors)
	if not errors.is_empty():
		return {"valid": false, "errors": errors}
	if not SUPPORTED_SCHEMA_VERSIONS.has(int(quest.get("schema_version", -1))):
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

	if int(quest.get("schema_version", 1)) == 2:
		_validate_adventure(quest, errors)
	return {"valid": errors.is_empty(), "errors": errors}

static func validate_package(package: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	if not _integer(package.get("schema_version")) or not SUPPORTED_SCHEMA_VERSIONS.has(int(package.get("schema_version", -1))):
		return {"valid": false, "errors": ["Неизвестная schema_version пакета."]}
	if _contains_forbidden_payload(package):
		return {"valid": false, "errors": ["Пакет содержит запрещённые действия, пути, URL или исполняемые поля."]}
	_validate_capabilities(package.get("required_capabilities", []), "required_capabilities", errors)
	if package.has("manifest"):
		var manifest := _dict(package.manifest, "manifest", errors)
		_validate_capabilities(manifest.get("required_capabilities", []), "manifest.required_capabilities", errors)
	if package.has("quests"):
		var quests := _array(package["quests"], "quests", errors)
		if quests.is_empty() or quests.size() > MAX_PACKAGE_QUESTS:
			errors.append("quests: требуется от 1 до 50 миссий.")
			return {"valid": false, "errors": errors}
		var sanitized: Array[Dictionary] = []
		var seen: Dictionary = {}
		var lexeme_count := 0
		for index in range(quests.size()):
			if not quests[index] is Dictionary:
				errors.append("quests[%d]: требуется объект." % index)
				continue
			var quest: Dictionary = quests[index].duplicate(true)
			var checked := validate_quest(quest)
			for error in checked.errors:
				errors.append("quests[%d].%s" % [index, error])
			var key := str(quest.get("quest_id", "")) + "@" + str(quest.get("revision", 0))
			if seen.has(key):
				errors.append("quests[%d]: повторная ревизия %s." % [index, key])
			seen[key] = true
			if quest.get("adventure") is Dictionary and quest.adventure.get("lexicon") is Array:
				lexeme_count += quest.adventure.lexicon.size()
			quest["content_status"] = "DRAFT"
			sanitized.append(quest)
		if package.get("lexicon") is Array:
			lexeme_count += package.lexicon.size()
		if lexeme_count > MAX_LEXEMES:
			errors.append("lexicon: пакет превышает 1000 словарных единиц.")
		# Dependencies must be frozen in the same package (no ambient lookup).
		for quest in sanitized:
			for dependency in _array(quest.get("content_dependencies", []), "content_dependencies", errors):
				if dependency is Dictionary:
					var dependency_key := str(dependency.get("quest_id", "")) + "@" + str(dependency.get("revision", 0))
					if not seen.has(dependency_key):
						errors.append("content_dependencies: отсутствует " + dependency_key)
		return {"valid": errors.is_empty(), "errors": errors, "sanitized_quests": sanitized}
	var quest_value: Variant = package.get("quest", package)
	if not quest_value is Dictionary:
		return {"valid": false, "errors": ["quest: требуется объект."]}
	var quest: Dictionary = quest_value.duplicate(true)
	quest["content_status"] = "DRAFT"
	var result := validate_quest(quest)
	result.errors.append_array(errors)
	result["valid"] = result.errors.is_empty()
	result["sanitized_quest"] = quest
	return result

static func content_hash(quest: Dictionary) -> String:
	var copy := quest.duplicate(true)
	copy.erase("content_status")
	copy.erase("approved")
	copy.erase("is_approved")
	return _canonical_string(copy).sha256_text()

static func _contains_forbidden_payload(value: Variant, depth: int = 0) -> bool:
	if depth > 32:
		return true
	match typeof(value):
		TYPE_DICTIONARY:
			var dict := value as Dictionary
			for key in dict.keys():
				var key_text := str(key).to_lower()
				if FORBIDDEN_KEYS.has(key_text):
					return true
				if _contains_forbidden_payload(dict[key], depth + 1):
					return true
		TYPE_ARRAY:
			for item in value as Array:
				if _contains_forbidden_payload(item, depth + 1):
					return true
		TYPE_STRING:
			var text := str(value)
			if text.length() > MAX_TEXT_LENGTH:
				return true
			var lower := text.to_lower()
			if lower.contains("res://") or lower.contains("user://") or lower.contains("file://"):
				return true
			if lower.contains("http://") or lower.contains("https://") or text.begins_with("/") or text.begins_with("\\") or (text.length() > 2 and text.substr(1, 2) in [":/", ":\\"]):
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
		TYPE_FLOAT:
			# JSON.parse represents numbers as floats. Hashes must survive a save/
			# load round trip without changing frozen integer-valued definitions.
			if is_finite(value) and value == floor(value):
				return str(int(value))
			return JSON.stringify(value)
		_:
			return JSON.stringify(value)

# Check nested JSON before any conversion: malformed input is a validation error.
static func _integer(value: Variant) -> bool:
	return typeof(value) == TYPE_INT or (typeof(value) == TYPE_FLOAT and is_finite(value) and value == floor(value))

static func _array(value: Variant, location: String, errors: Array[String]) -> Array:
	if not value is Array:
		errors.append(location + ": требуется массив.")
		return []
	return value

static func _dict(value: Variant, location: String, errors: Array[String]) -> Dictionary:
	if not value is Dictionary:
		errors.append(location + ": требуется объект.")
		return {}
	return value

static func _strings(value: Variant, location: String, errors: Array[String], unique: bool = false) -> Array:
	var values := _array(value, location, errors)
	var seen: Dictionary = {}
	for index in range(values.size()):
		if not values[index] is String or str(values[index]).strip_edges().is_empty():
			errors.append(location + "[%d]: нужна непустая строка." % index)
		elif unique and seen.has(values[index]):
			errors.append(location + ": повтор " + values[index])
		seen[str(values[index])] = true
	return values

static func _text_fields(value: Dictionary, keys: Array, location: String, errors: Array[String]) -> void:
	for key in keys:
		if value.has(key) and not value[key] is String:
			errors.append(location + "." + key + ": требуется строка.")

static func _number(value: Variant, location: String, errors: Array[String], low: int = 0, high: int = 500) -> int:
	if not _integer(value) or value < low or value > high:
		errors.append(location + ": нужно целое число от %d до %d." % [low, high])
		return 0
	return int(value)

static func _boolean(value: Dictionary, key: String, location: String, errors: Array[String]) -> void:
	if value.has(key) and not value[key] is bool:
		errors.append(location + "." + key + ": требуется true или false.")

static func _validate_base_types(quest: Dictionary, errors: Array[String]) -> void:
	_number(quest.get("schema_version", -1), "schema_version", errors, 1, 2)
	_number(quest.get("revision", 0), "revision", errors, 1, 1000000)
	_text_fields(quest, ["quest_id", "title", "summary", "content_status", "chapter_key", "story_title", "entry_anchor_id"], "quest", errors)
	_strings(quest.get("completion_criteria", []), "completion_criteria", errors)
	_boolean(quest, "is_main_quest", "quest", errors)
	for key in ["goal_steps", "atlas_targets", "tags", "interests"]:
		if quest.has(key):
			if key == "goal_steps" and quest.get("schema_version", 1) == 1:
				for legacy_step in _array(quest[key], "goal_steps", errors):
					if _integer(legacy_step):
						_number(legacy_step, "goal_steps[]", errors, 0, 1000000)
					elif not legacy_step is String or str(legacy_step).strip_edges().is_empty():
						errors.append("goal_steps[]: нужна строка или числовой порог старой схемы.")
				continue
			_strings(quest[key], key, errors)
	if quest.has("goal_order"):
		_number(quest.goal_order, "goal_order", errors, 0, 1000000)
	if quest.has("estimated_minutes"):
		var minutes := _dict(quest.estimated_minutes, "estimated_minutes", errors)
		var minimum := _number(minutes.get("min", 0), "estimated_minutes.min", errors, 0, 1000000)
		_number(minutes.get("max", minimum), "estimated_minutes.max", errors, minimum, 1000000)
	if quest.has("context"):
		var context := _dict(quest.context, "context", errors)
		_text_fields(context, ["adult_presence"], "context", errors)
		for key in ["requires_network", "requires_purchase"]:
			_boolean(context, key, "context", errors)
		_strings(context.get("risk_tags", []), "context.risk_tags", errors)
	if quest.has("evidence_policy"):
		var evidence := _dict(quest.evidence_policy, "evidence_policy", errors)
		_text_fields(evidence, ["reviewer"], "evidence_policy", errors)
		_strings(evidence.get("allowed", []), "evidence_policy.allowed", errors)
		_boolean(evidence, "required_media", "evidence_policy", errors)
	if quest.has("provenance"):
		var provenance := _dict(quest.provenance, "provenance", errors)
		_text_fields(provenance, ["origin", "package_id"], "provenance", errors)
	for variant in _array(quest.get("variants", []), "variants", errors):
		var data := _dict(variant, "variants[]", errors)
		_text_fields(data, ["id", "title", "description"], "variants[]", errors)
		_boolean(data, "home_available", "variants[]", errors)
	var reward := _dict(quest.get("reward_policy", {}), "reward_policy", errors)
	_number(reward.get("activity_budget", 0), "reward_policy.activity_budget", errors)
	var weights := _dict(reward.get("skill_weights_percent", {}), "reward_policy.skill_weights_percent", errors)
	for key in weights:
		_number(weights[key], "reward_policy.skill_weights_percent." + str(key), errors, 0, 100)
	_strings(reward.get("world_effect_ids", []), "reward_policy.world_effect_ids", errors)
	if reward.has("milestones_percent"):
		for value in _array(reward.milestones_percent, "milestones_percent", errors):
			_number(value, "milestones_percent[]", errors, 1, 100)
	var repeat := _dict(quest.get("repeat_policy", {}), "repeat_policy", errors)
	_text_fields(repeat, ["mode"], "repeat_policy", errors)
	if repeat.has("max_completions"):
		_number(repeat.max_completions, "repeat_policy.max_completions", errors, 0, 1000000)

static func _validate_capabilities(value: Variant, location: String, errors: Array[String]) -> void:
	for capability in _strings(value, location, errors, true):
		if not AdventureContentScript.CAPABILITY_IDS.has(capability):
			errors.append(location + ": неподдерживаемая обязательная возможность " + str(capability))

static func _registry_refs(value: Variant, registry: Variant, location: String, errors: Array[String]) -> void:
	for id in _strings(value, location, errors, true):
		if not registry.has(id):
			errors.append(location + ": неизвестная ссылка " + str(id))

static func _entities(value: Variant, id_field: String, location: String, errors: Array[String]) -> Dictionary:
	var entries: Array = []
	if value is Dictionary:
		for key in value:
			var entry := _dict(value[key], location + "." + str(key), errors)
			if str(entry.get(id_field, "")) != str(key):
				errors.append(location + "." + str(key) + ": ID не совпадает с ключом.")
			entries.append(entry)
	else:
		entries = _array(value, location, errors)
	var indexed: Dictionary = {}
	for index in range(entries.size()):
		var entry := _dict(entries[index], location + "[%d]" % index, errors)
		var id_value: Variant = entry.get(id_field, "")
		if not id_value is String or str(id_value).strip_edges().is_empty():
			errors.append(location + "[%d].%s: нужен ID." % [index, id_field])
			continue
		if indexed.has(id_value):
			errors.append(location + ": повторный ID " + str(id_value))
		indexed[id_value] = entry
	return indexed

static func _validate_adventure(quest: Dictionary, errors: Array[String]) -> void:
	_validate_capabilities(quest.get("required_capabilities", []), "required_capabilities", errors)
	_strings(quest.get("exhibit_ids", []), "exhibit_ids", errors, true)
	for dependency in _array(quest.get("content_dependencies", []), "content_dependencies", errors):
		var data := _dict(dependency, "content_dependencies[]", errors)
		_text_fields(data, ["quest_id", "content_hash"], "content_dependencies[]", errors)
		_number(data.get("revision", 0), "content_dependencies[].revision", errors, 1, 1000000)
	var adventure := _dict(quest.get("adventure"), "adventure", errors)
	var stage_values := _array(adventure.get("stages"), "adventure.stages", errors)
	if stage_values.is_empty() or stage_values.size() > MAX_STAGES:
		errors.append("adventure.stages: требуется от 1 до 64 этапов.")
		return
	var stages := _entities(stage_values, "stage_id", "adventure.stages", errors)
	var interactions := _entities(adventure.get("interactions", {}), "interaction_id", "adventure.interactions", errors)
	var recipes := _entities(adventure.get("work_recipes", {}), "recipe_id", "adventure.work_recipes", errors)
	var grants := _entities(adventure.get("grant_definitions", {}), "grant_id", "adventure.grant_definitions", errors)
	for recipe_id in recipes:
		if not AdventureContentScript.WORK_RECIPE_IDS.has(recipe_id):
			errors.append("adventure.work_recipes: неизвестный рецепт " + recipe_id)
		_text_fields(recipes[recipe_id], ["kind", "work_kind", "title", "description", "presentation"], "work_recipes." + recipe_id, errors)
		_strings(recipes[recipe_id].get("presentations", []), "work_recipes." + recipe_id + ".presentations", errors)
	_registry_refs(quest.get("exhibit_ids", []), recipes, "exhibit_ids", errors)
	for grant_id in grants:
		if not AdventureContentScript.GRANT_IDS.has(grant_id):
			errors.append("adventure.grant_definitions: неизвестная выдача " + grant_id)
		_text_fields(grants[grant_id], ["title", "description", "kind"], "grant_definitions." + grant_id, errors)
	var total := 0
	var canonical_ids: Dictionary = {}
	for stage_id in stages:
		var stage: Dictionary = stages[stage_id]
		var location: String = "adventure.stages." + stage_id
		_text_fields(stage, ["title", "summary", "next_hint", "completion_policy", "work_recipe_id", "canonical_reward_id"], location, errors)
		_boolean(stage, "required", location, errors)
		_strings(stage.get("criteria", []), location + ".criteria", errors)
		_registry_refs(stage.get("prerequisite_stage_ids", []), stages, location + ".prerequisite_stage_ids", errors)
		_registry_refs(stage.get("interaction_ids", []), interactions, location + ".interaction_ids", errors)
		_registry_refs(stage.get("grant_ids", []), grants, location + ".grant_ids", errors)
		_registry_refs(stage.get("atlas_unlock_ids", []), ATLAS_IDS, location + ".atlas_unlock_ids", errors)
		if not POLICIES.has(stage.get("completion_policy", "")):
			errors.append(location + ": неизвестная completion_policy.")
		var share := _number(stage.get("budget_share", 0), location + ".budget_share", errors)
		if stage.get("required", true) == true:
			total += share
		elif share != 0:
			errors.append(location + ": необязательный этап должен иметь budget_share 0.")
		var canonical := str(stage.get("canonical_reward_id", stage_id))
		if canonical.is_empty() or canonical_ids.has(canonical):
			errors.append(location + ": повторный canonical_reward_id.")
		canonical_ids[canonical] = true
		var recipe: Variant = stage.get("work_recipe_id", "")
		if recipe != "" and (not recipe is String or not recipes.has(recipe)):
			errors.append(location + ".work_recipe_id: отсутствует рецепт " + str(recipe))
	var budget := int(quest.get("reward_policy", {}).get("activity_budget", 0))
	if total != budget:
		errors.append("adventure.stages.budget_share: сумма обязательных этапов %d не равна бюджету %d." % [total, budget])
	if MAIN_BUDGETS.has(quest.get("quest_id")) and budget != MAIN_BUDGETS[quest.quest_id]:
		errors.append("reward_policy.activity_budget: бюджет " + quest.quest_id + " должен быть " + str(MAIN_BUDGETS[quest.quest_id]))
	var reachable: Dictionary = {}
	for _pass in range(stages.size()):
		for stage_id in stages:
			var prerequisites: Variant = stages[stage_id].get("prerequisite_stage_ids", [])
			if not prerequisites is Array:
				continue
			var ready := true
			for dependency in prerequisites:
				if not reachable.has(dependency):
					ready = false
			if ready:
				reachable[stage_id] = true
	if reachable.size() != stages.size():
		errors.append("adventure.stages: цикл или недостижимый этап.")
	if adventure.has("final_stage_id") and not reachable.has(adventure.final_stage_id):
		errors.append("adventure.final_stage_id: финал недостижим.")
	var node_count := 0
	for interaction_id in interactions:
		node_count += _validate_interaction(interactions[interaction_id], stages, "adventure.interactions." + interaction_id, errors)
	var dialogues_value: Variant = adventure.get("dialogues", {})
	if not dialogues_value is Dictionary and not dialogues_value is Array:
		errors.append("adventure.dialogues: требуется объект или массив.")
	else:
		var dialogues: Array = dialogues_value.values() if dialogues_value is Dictionary else dialogues_value
		for dialogue in dialogues:
			if dialogue is String:
				node_count += 1
				continue
			var data := _dict(dialogue, "adventure.dialogues[]", errors)
			if data.has("nodes"):
				node_count += _validate_dialogue(data, "adventure.dialogues[]", errors)
			else:
				node_count += 1
				_text_fields(data, ["node_id", "speaker", "text"], "adventure.dialogues[]", errors)
	if node_count > MAX_DIALOGUE_NODES:
		errors.append("adventure.dialogues: превышен лимит 256 узлов диалога.")
	var lexicon := _entities(adventure.get("lexicon", []), "lexeme_id", "adventure.lexicon", errors)
	if lexicon.size() > MAX_LEXEMES:
		errors.append("adventure.lexicon: превышен лимит 1000 словарных единиц.")
	for lexeme_id in lexicon:
		var lexeme: Dictionary = lexicon[lexeme_id]
		_text_fields(lexeme, ["lemma", "base_form", "text", "translation", "channel_id", "example", "example_translation", "status"], "adventure.lexicon." + lexeme_id, errors)
		_strings(lexeme.get("accepted_variants", []), "adventure.lexicon." + lexeme_id + ".accepted_variants", errors)
		_strings(lexeme.get("topics", []), "adventure.lexicon." + lexeme_id + ".topics", errors)
		if lexeme.has("normalization"):
			var normalization := _dict(lexeme.normalization, "lexicon.normalization", errors)
			for key in ["casefold", "trim_spaces", "preserve_diacritics"]:
				_boolean(normalization, key, "lexicon.normalization", errors)
	var channels := _entities(adventure.get("channels", []), "channel_id", "adventure.channels", errors)
	for channel in channels.values():
		_registry_refs(channel.get("lexeme_ids", []), lexicon, "adventure.channels[].lexeme_ids", errors)
	var envelopes := _entities(adventure.get("envelopes", []), "envelope_id", "adventure.envelopes", errors)
	for data in envelopes.values():
		_text_fields(data, ["channel_id", "title", "story", "world_reaction"], "adventure.envelopes[]", errors)
		if not channels.has(data.get("channel_id", "")):
			errors.append("adventure.envelopes[].channel_id: отсутствует канал.")
		_registry_refs(data.get("lexeme_ids", []), lexicon, "adventure.envelopes[].lexeme_ids", errors)
		_registry_refs(data.get("review_lexeme_ids", []), lexicon, "adventure.envelopes[].review_lexeme_ids", errors)
		_registry_refs(data.get("interaction_ids", []), interactions, "adventure.envelopes[].interaction_ids", errors)
	if adventure.has("final_check"):
		var final_check := _dict(adventure.final_check, "adventure.final_check", errors)
		if not interactions.has(final_check.get("interaction_id", "")):
			errors.append("adventure.final_check.interaction_id: отсутствует взаимодействие.")
		var sample_size := _number(final_check.get("sample_size", 20), "adventure.final_check.sample_size", errors, 1, 1000)
		_number(final_check.get("minimum_unassisted_correct", 0), "adventure.final_check.minimum_unassisted_correct", errors, 0, sample_size)
	if adventure.has("choice_effects"):
		var choices := _dict(adventure.choice_effects, "adventure.choice_effects", errors)
		for choice_id in choices:
			if choices[choice_id] is String:
				continue # A named optional presentation; never a grant handler.
			var effects := _dict(choices[choice_id], "adventure.choice_effects." + str(choice_id), errors)
			for effect in effects.values():
				if not effect is String or not AdventureContentScript.GRANT_IDS.has(effect):
					errors.append("adventure.choice_effects: неизвестная выдача " + str(effect))

static func _validate_interaction(definition: Dictionary, stages: Dictionary, location: String, errors: Array[String]) -> int:
	_text_fields(definition, ["interaction_id", "type", "title", "prompt"], location, errors)
	_strings(definition.get("hints", []), location + ".hints", errors)
	var kind: Variant = definition.get("type", "")
	if not AdventureContentScript.INTERACTION_TYPES.has(kind):
		errors.append(location + ".type: неизвестный тип взаимодействия.")
		return 0
	var config := _dict(definition.get("config", {}), location + ".config", errors)
	match kind:
		"match_cards":
			var cards := _entities(config.get("cards", []), "id", location + ".cards", errors)
			var targets := _entities(config.get("targets", []), "id", location + ".targets", errors)
			var pairs := _dict(config.get("accepted_pairs", {}), location + ".accepted_pairs", errors)
			if pairs.is_empty():
				errors.append(location + ".accepted_pairs: нужны пары.")
			for card_id in pairs:
				if not cards.has(card_id) or not pairs[card_id] is String or not targets.has(pairs[card_id]):
					errors.append(location + ".accepted_pairs: отсутствует карточка или цель.")
		"order_fragments":
			var fragments := _entities(config.get("fragments", []), "id", location + ".fragments", errors)
			var orders := _array(config.get("accepted_orders", []), location + ".accepted_orders", errors)
			if orders.is_empty():
				errors.append(location + ".accepted_orders: нужен порядок.")
			for order in orders:
				_registry_refs(order, fragments, location + ".accepted_orders[]", errors)
				if order is Array and order.size() != fragments.size():
					errors.append(location + ".accepted_orders[]: порядок должен содержать все фрагменты.")
		"assemble_selection", "exhibit_composition":
			var field := "items" if kind == "assemble_selection" else "choices"
			var items := _entities(config.get(field, []), "id", location + "." + field, errors)
			_registry_refs(config.get("required_ids", []), items, location + ".required_ids", errors)
			var minimum := _number(config.get("min_selected", 1), location + ".min_selected", errors, 0, items.size())
			_number(config.get("max_selected", items.size()), location + ".max_selected", errors, minimum, items.size())
			_boolean(config, "ordered", location, errors)
			_registry_refs(config.get("source_stage_ids", []), stages, location + ".source_stage_ids", errors)
		"inspect_reveal":
			var details := _entities(config.get("details", []), "id", location + ".details", errors)
			_registry_refs(config.get("required_detail_ids", []), details, location + ".required_detail_ids", errors)
		"scripted_dialogue":
			return _validate_dialogue(config, location + ".config", errors)
		"real_world_step":
			_strings(config.get("criteria", []), location + ".criteria", errors)
			_strings(config.get("materials", []), location + ".materials", errors)
			var fields := _entities(config.get("fields", []), "id", location + ".fields", errors)
			for field in fields.values():
				_text_fields(field, ["label"], location + ".fields[]", errors)
				_boolean(field, "required", location + ".fields[]", errors)
			if config.has("starter_project_id") and config.starter_project_id not in ["", "station_arcade_starter"]:
				errors.append(location + ".starter_project_id: неизвестный проект.")
		"compare_observations":
			_registry_refs(config.get("source_stage_ids", []), stages, location + ".source_stage_ids", errors)
			_entities(config.get("categories", []), "id", location + ".categories", errors)
			_number(config.get("min_observations", 2), location + ".min_observations", errors, 2, 64)
	return 0

static func _validate_dialogue(config: Dictionary, location: String, errors: Array[String]) -> int:
	var nodes := _entities(config.get("nodes", []), "node_id", location + ".nodes", errors)
	if not nodes.has(config.get("start_node_id", "")):
		errors.append(location + ".start_node_id: отсутствует начальный узел.")
	var links: Dictionary = {}
	for node_id in nodes:
		var node: Dictionary = nodes[node_id]
		_text_fields(node, ["speaker", "text"], location + ".nodes." + node_id, errors)
		var choices := _entities(node.get("choices", []), "id", location + ".choices", errors)
		links[node_id] = []
		for choice in choices.values():
			_text_fields(choice, ["text", "next_node_id", "feedback"], location + ".choices[]", errors)
			_boolean(choice, "correct", location + ".choices[]", errors)
			var next: Variant = choice.get("next_node_id", "")
			if next == "":
				continue
			if not next is String or not nodes.has(next):
				errors.append(location + ".choices[].next_node_id: отсутствует узел " + str(next))
			else:
				links[node_id].append(next)
	var visited: Dictionary = {}
	var pending: Array = [config.get("start_node_id", "")]
	while not pending.is_empty():
		var current: Variant = pending.pop_back()
		if visited.has(current) or not links.has(current):
			continue
		visited[current] = true
		pending.append_array(links[current])
	if visited.size() != nodes.size():
		errors.append(location + ".nodes: недостижимый узел диалога.")
	return nodes.size()
