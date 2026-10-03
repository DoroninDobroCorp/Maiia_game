class_name AdventureRules
extends RefCounted

## Pure rules. Definitions always come from the accepted QuestInstance snapshot.
const BUDGETS := {"FG01": 40, "FG11": 60, "FG08": 40}
const POLICIES := ["automatic", "self_attest", "joint_review"]
const INTERACTIONS := ["inspect_reveal", "match_cards", "order_fragments", "assemble_selection", "scripted_dialogue", "real_world_step", "compare_observations", "exhibit_composition"]

static func stages(quest: Dictionary) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if quest.has("adventure"):
		for stage in quest.get("adventure", {}).get("stages", []):
			if stage is Dictionary:
				result.append(stage.duplicate(true))
	else:
		result.append({"stage_id": "legacy_result", "title": quest.get("title", "Результат"),
			"prerequisite_stage_ids": [], "completion_policy": "joint_review", "required": true,
			"criteria": quest.get("completion_criteria", []).duplicate(true),
			"budget_share": quest.get("reward_policy", {}).get("activity_budget", 0),
			"work_recipe_id": "legacy_card", "interaction_ids": []})
	return result

static func stage_by_id(quest: Dictionary, stage_id: String) -> Dictionary:
	for stage in stages(quest):
		if str(stage.get("stage_id", "")) == stage_id:
			return stage
	return {}

static func validate_adventure(quest: Dictionary) -> Dictionary:
	var errors: Array[String] = []
	var definitions := stages(quest)
	if definitions.is_empty() or definitions.size() > 64:
		errors.append("adventure.stages: требуется от 1 до 64 этапов")
	var ids: Dictionary = {}
	var canonical_ids: Dictionary = {}
	var total := 0
	for stage in definitions:
		var sid := str(stage.get("stage_id", ""))
		if sid.is_empty() or ids.has(sid):
			errors.append("adventure.stages: пустой или повторный stage_id " + sid)
		ids[sid] = stage
		var canonical := str(stage.get("canonical_reward_id", sid))
		if canonical.is_empty() or canonical_ids.has(canonical):
			errors.append("Повторный canonical_reward_id: " + canonical)
		canonical_ids[canonical] = true
		if not POLICIES.has(str(stage.get("completion_policy", ""))):
			errors.append(sid + ": неизвестная completion_policy")
		var share := int(stage.get("budget_share", 0))
		if share < 0 or (not bool(stage.get("required", true)) and share != 0):
			errors.append(sid + ": необязательный этап не расходует основной бюджет")
		if bool(stage.get("required", true)):
			total += share
		if not stage.get("prerequisite_stage_ids", []) is Array:
			errors.append(sid + ": зависимости должны быть массивом")
	var budget := int(quest.get("reward_policy", {}).get("activity_budget", 0))
	if total != budget:
		errors.append("Сумма budget_share должна равняться activity_budget")
	var qid := str(quest.get("quest_id", ""))
	if quest.has("adventure") and BUDGETS.has(qid) and budget != int(BUDGETS[qid]):
		errors.append(qid + ": изменён исходный бюджет")
	for stage in definitions:
		if not stage.get("prerequisite_stage_ids", []) is Array:
			continue
		for dependency in stage.get("prerequisite_stage_ids", []):
			if not ids.has(str(dependency)):
				errors.append(str(stage.get("stage_id", "")) + ": нет зависимости " + str(dependency))
	var reachable: Dictionary = {}
	for _pass in range(definitions.size()):
		for stage in definitions:
			if not stage.get("prerequisite_stage_ids", []) is Array:
				continue
			var ready := true
			for dependency in stage.get("prerequisite_stage_ids", []):
				if not reachable.has(str(dependency)):
					ready = false
			if ready:
				reachable[str(stage.get("stage_id", ""))] = true
	if reachable.size() != ids.size():
		errors.append("Граф этапов содержит цикл или недостижимую зависимость")
	return {"valid": errors.is_empty(), "ok": errors.is_empty(), "errors": errors}

static func dependencies_complete(stage: Dictionary, progress: Dictionary) -> bool:
	for dependency in stage.get("prerequisite_stage_ids", []):
		if str(progress.get("stages", {}).get(str(dependency), {}).get("status", "LOCKED")) != "COMPLETED":
			return false
	return true

static func all_required_complete(quest: Dictionary, progress: Dictionary) -> bool:
	for stage in stages(quest):
		if bool(stage.get("required", true)) and str(progress.get("stages", {}).get(str(stage.stage_id), {}).get("status", "")) != "COMPLETED":
			return false
	return true

static func grant_key(profile_id: String, lineage_id: String, canonical_reward_id: String) -> String:
	# A serialized tuple avoids ambiguous ':' concatenations in external IDs.
	return "grant:" + JSON.stringify([profile_id, lineage_id, canonical_reward_id]).sha256_text()

static func normalise_word(value: String) -> String:
	return " ".join(value.to_lower().replace("\t", " ").replace("\n", " ").replace("\r", " ").strip_edges().split(" ", false))

static func unique_ids(values: Array) -> Array[String]:
	var result: Array[String] = []
	for value in values:
		var id := str(value).strip_edges()
		if not id.is_empty() and not result.has(id):
			result.append(id)
	return result

static func check_interaction(definition: Dictionary, response: Dictionary) -> Dictionary:
	for key in ["fields", "pairs"]:
		if response.has(key) and not response[key] is Dictionary:
			return {"ok": false, "reason": "invalid_response", "field": key}
	for key in ["order", "selected_ids", "revealed_ids", "choice_ids", "assisted_ids", "unassisted_lexeme_ids", "assisted_lexeme_ids", "criteria", "work_ids"]:
		if response.has(key) and not response[key] is Array:
			return {"ok": false, "reason": "invalid_response", "field": key}
	var kind := str(definition.get("type", definition.get("template", definition.get("kind", ""))))
	var data: Dictionary = definition.get("config", definition.get("data", definition))
	var valid := false
	match kind:
		"match_cards":
			var expected: Variant = data.get("accepted_pairs", data.get("correct_pairs", data.get("pairs", {})))
			valid = not expected.is_empty() and response.get("pairs", {}) == expected
			if data.has("minimum_unassisted_correct"):
				var correct := unassisted_lexemes(definition, response)
				valid = correct.size() >= int(data.minimum_unassisted_correct)
		"order_fragments":
			var orders: Array = data.get("accepted_orders", [data.get("correct_order", [])])
			valid = not response.get("order", []).is_empty() and orders.has(response.get("order", []))
		"inspect_reveal":
			var required: Array = data.get("required_detail_ids", data.get("required_ids", data.get("reveal_ids", [])))
			valid = not required.is_empty()
			for id in required:
				valid = valid and response.get("revealed_ids", []).has(id)
		"assemble_selection", "exhibit_composition":
			var selected := unique_ids(response.get("selected_ids", []))
			var allowed := unique_ids(data.get("allowed_ids", data.get("option_ids", [])))
			for item in data.get("items", data.get("choices", [])):
				allowed.append(str(item.get("id", "")))
			var required := unique_ids(data.get("required_ids", []))
			valid = selected.size() >= int(data.get("min_selected", data.get("min_selections", 1))) and selected.size() <= int(data.get("max_selected", allowed.size())) and not allowed.is_empty()
			for id in selected:
				valid = valid and allowed.has(id)
			for id in required:
				valid = valid and selected.has(id)
		"scripted_dialogue":
			var nodes: Dictionary = {}
			for node in data.get("nodes", []):
				nodes[str(node.get("node_id", ""))] = node
			var node_id := str(data.get("start_node_id", ""))
			valid = nodes.has(node_id)
			for choice_id in response.get("choice_ids", []):
				var choice: Dictionary = {}
				for item in nodes.get(node_id, {}).get("choices", []):
					if str(item.get("id", "")) == str(choice_id):
						choice = item
				if choice.is_empty() or not bool(choice.get("correct", true)):
					valid = false
					break
				node_id = str(choice.get("next_node_id", ""))
				if not nodes.has(node_id):
					valid = false
					break
			valid = valid and bool(nodes.get(node_id, {}).get("terminal", false)) and str(response.get("node_id", node_id)) == node_id
		"compare_observations":
			valid = not str(response.get("comparison", response.get("note", response.get("fields", {}).get("comparison", response.get("fields", {}).get("difference", ""))))).strip_edges().is_empty()
			var categories: Array[String] = []
			for category in data.get("categories", []):
				categories.append(str(category.get("id", "")))
			valid = valid and (categories.is_empty() or categories.has(str(response.get("category_id", response.get("fields", {}).get("category_id", "")))))
		"real_world_step":
			# This validates a report, not the real-world claim. Joint review remains mandatory.
			valid = not response.get("fields", {}).is_empty() or not str(response.get("note", "")).strip_edges().is_empty()
		_:
			return {"ok": false, "reason": "unsupported_interaction"}
	for field in data.get("fields", []):
		if bool(field.get("required", false)) and str(response.get("fields", {}).get(str(field.get("id", "")), "")).strip_edges().is_empty():
			valid = false
	return {"ok": valid, "reason": "" if valid else "try_again", "hint": data.get("error_hint", "Посмотри на условие и попробуй ещё раз.")}

static func unassisted_lexemes(definition: Dictionary, response: Dictionary) -> Array[String]:
	var data: Dictionary = definition.get("config", {})
	var cards: Array = data.get("cards", [])
	var lexemes: Array = data.get("lexeme_ids", [])
	var expected: Dictionary = data.get("accepted_pairs", {})
	var result: Array[String] = []
	for index in range(mini(cards.size(), lexemes.size())):
		var card_id := str(cards[index].get("id", ""))
		var lexeme_id := str(lexemes[index])
		if response.get("assisted_ids", []).has(card_id) or response.get("assisted_lexeme_ids", []).has(lexeme_id):
			continue
		# Older callers supplied an explicit subset rather than assisted card IDs.
		if response.has("unassisted_lexeme_ids") and not response.unassisted_lexeme_ids.has(lexeme_id):
			continue
		if expected.has(card_id) and response.get("pairs", {}).get(card_id, "") == expected[card_id]:
			result.append(lexeme_id)
	return unique_ids(result)

static func check_evidence(quest: Dictionary, stage: Dictionary, progress: Dictionary, evidence: Dictionary) -> Dictionary:
	var shape := validate_evidence_shape(evidence)
	if not bool(shape.ok):
		return shape
	var sid := str(stage.get("stage_id", ""))
	var checks: Dictionary = stage.get("completion_checks", {})
	for field in checks.get("required_fields", []):
		if str(evidence.get(str(field), "")).strip_edges().is_empty():
			return {"ok": false, "reason": "missing_evidence", "field": field}
	for check in checks.get("required_checks", []):
		if not bool(evidence.get("checks", {}).get(str(check), false)):
			return {"ok": false, "reason": "criterion_not_met", "criterion": check}
	var thresholds := {"es_intro": 5, "es_channel_01": 25, "es_channel_02": 50, "es_channel_03": 75, "es_channel_04": 100, "es_final": 100}
	var min_words := int(checks.get("min_lexemes", thresholds.get(sid, 0) if str(quest.get("quest_id", "")) == "FG01" else 0))
	if progress.get("lexemes", {}).size() < min_words:
		return {"ok": false, "reason": "not_enough_lexemes", "required": min_words}
	if sid == "es_final" and str(quest.get("quest_id", "")) == "FG01":
		var sample := unique_ids(evidence.get("sample_lexeme_ids", []))
		var correct := unique_ids(evidence.get("unassisted_lexeme_ids", []))
		var final_check: Dictionary = quest.get("adventure", {}).get("final_check", {})
		if sample.size() != int(checks.get("sample_size", final_check.get("sample_size", 20))) or correct.size() < int(checks.get("min_correct", final_check.get("minimum_unassisted_correct", 14))):
			return {"ok": false, "reason": "mixed_check_incomplete"}
		var channels: Dictionary = {}
		for lexeme in quest.get("adventure", {}).get("lexicon", quest.get("lexicon", [])):
			if sample.has(str(lexeme.get("lexeme_id", ""))):
				var channel_id := str(lexeme.get("channel_id", lexeme.get("channel", "")))
				if not channel_id.is_empty():
					channels[channel_id] = true
		for envelope in quest.get("adventure", {}).get("envelopes", []):
			for id in envelope.get("lexeme_ids", []):
				if sample.has(str(id)):
					channels[str(envelope.get("channel_id", ""))] = true
		for id in sample:
			if not progress.get("lexemes", {}).has(id):
				return {"ok": false, "reason": "unknown_sample_lexeme"}
		for id in correct:
			if not sample.has(id):
				return {"ok": false, "reason": "invalid_correct_sample"}
		if channels.size() < 4:
			return {"ok": false, "reason": "sample_requires_four_channels"}
	if str(quest.get("quest_id", "")) == "FG08":
		if ["water_river", "water_fall"].has(sid):
			if not bool(evidence.get("visited", false)) or bool(evidence.get("home_materials", false)):
				return {"ok": false, "reason": "real_visit_required"}
			if str(evidence.get("note", evidence.get("observation", ""))).strip_edges().is_empty() and str(evidence.get("artifact_id", "")).is_empty():
				return {"ok": false, "reason": "observation_required"}
			if not stage.get("atlas_unlock_ids", []).has(str(evidence.get("atlas_location_id", ""))):
				return {"ok": false, "reason": "agreed_atlas_location_required"}
		if sid == "water_compare" and str(evidence.get("comparison", evidence.get("note", evidence.get("difference", "")))).strip_edges().is_empty():
			return {"ok": false, "reason": "comparison_required"}
	if str(quest.get("quest_id", "")) == "FG11" and sid != "game_concept":
		if bool(evidence.get("demo_only", false)):
			return {"ok": false, "reason": "own_project_required"}
		if sid in ["game_move", "game_premiere"] and str(evidence.get("own_contribution", evidence.get("own_change", ""))).strip_edges().is_empty():
			return {"ok": false, "reason": "own_contribution_required"}
		if sid == "game_premiere" and str(evidence.get("causal_explanation", "")).strip_edges().is_empty():
			return {"ok": false, "reason": "causal_explanation_required"}
	return {"ok": true}

static func validate_evidence_shape(evidence: Dictionary) -> Dictionary:
	for key in ["fields", "choices", "checks"]:
		if evidence.has(key) and not evidence[key] is Dictionary:
			return {"ok": false, "reason": "invalid_evidence", "field": key}
	for key in ["sample_lexeme_ids", "unassisted_lexeme_ids", "criteria"]:
		if evidence.has(key) and not evidence[key] is Array:
			return {"ok": false, "reason": "invalid_evidence", "field": key}
	for key in ["attested", "visited", "home_materials", "demo_only"]:
		if evidence.has(key) and not evidence[key] is bool:
			return {"ok": false, "reason": "invalid_evidence", "field": key}
	return {"ok": true}
