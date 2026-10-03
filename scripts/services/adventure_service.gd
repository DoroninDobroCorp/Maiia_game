class_name AdventureService
extends RefCounted

## QuestService owns instance lifecycle. This service owns only its stage overlay.
## Mutations below edit a candidate state; the UI/controller persists the candidate.
const Rules = preload("res://scripts/domain/adventure_rules.gd")
const Quests = preload("res://scripts/services/quest_service.gd")
const Collections = preload("res://scripts/services/collection_service.gd")
const Content = preload("res://scripts/services/adventure_content.gd")
const Validation = preload("res://scripts/domain/content_validation.gd")

static func ensure_adventures(state: Dictionary) -> Dictionary:
	if bool(state.get("read_only", false)):
		return state.get("adventures", {})
	if not state.has("adventures"):
		state.adventures = {}
	for key in ["progress", "grants", "reward_lineages", "pending_presentations"]:
		if not state.adventures.has(key):
			state.adventures[key] = {}
	return state.adventures

static func get_instance(state: Dictionary, instance_id: String) -> Dictionary:
	return state.get("phase_b", {}).get("quest_instances", {}).get(instance_id, {}).duplicate(true)

static func get_progress(state: Dictionary, instance_id: String) -> Dictionary:
	return state.get("adventures", {}).get("progress", {}).get(instance_id, {}).duplicate(true)

static func ensure_instance(state: Dictionary, instance_id: String) -> Dictionary:
	if bool(state.get("read_only", false)):
		return {"ok": false, "reason": "read_only"}
	var instance := get_instance(state, instance_id)
	if instance.is_empty():
		return {"ok": false, "reason": "unknown_instance"}
	var adventures := ensure_adventures(state)
	if adventures.progress.has(instance_id):
		return {"ok": true, "progress": get_progress(state, instance_id)}
	var quest: Dictionary = instance.get("quest_snapshot", {})
	var checked := Rules.validate_adventure(quest)
	if not bool(checked.valid):
		return {"ok": false, "reason": "invalid_adventure", "errors": checked.errors}
	var lineage_id := str(instance.get("reward_lineage_id", "lineage:" + instance_id))
	var profile_id := str(instance.get("profile_id", "player_01"))
	instance.reward_lineage_id = lineage_id
	state.phase_b.quest_instances[instance_id] = instance
	var budget := int(quest.get("reward_policy", {}).get("activity_budget", 0))
	if not adventures.reward_lineages.has(lineage_id):
		adventures.reward_lineages[lineage_id] = {"reward_lineage_id": lineage_id, "profile_id": profile_id,
			"quest_id": instance.quest_id, "budget": budget, "legacy_awarded_budget": int(instance.get("awarded_budget", 0)),
			"source_instance_id": instance_id, "created_at": instance.get("created_at", "")}
	var progress := {"instance_id": instance_id, "profile_id": profile_id, "reward_lineage_id": lineage_id,
		"snapshot_hash": Validation.content_hash(quest), "snapshot_revision": instance.get("revision", 1),
		"stages": {}, "choices": {}, "lexemes": {}, "next_context": "", "stage_reward_map": {}, "remaining_budget_plan": {}}
	for stage in Rules.stages(quest):
		var sid := str(stage.stage_id)
		var status := "AVAILABLE" if stage.get("prerequisite_stage_ids", []).is_empty() else "LOCKED"
		if not quest.has("adventure") and str(instance.get("status", "")) == "COMPLETED":
			status = "COMPLETED"
		progress.stages[sid] = {"stage_id": sid, "status": status, "draft": {}, "attempts": [], "help_history": [], "review_history": [], "confirmation_source": "", "award_key": ""}
		progress.stage_reward_map[sid] = str(stage.get("canonical_reward_id", sid))
	adventures.progress[instance_id] = progress
	_allocate_remaining(state, instance_id)
	refresh_availability(state, instance_id)
	return {"ok": true, "progress": get_progress(state, instance_id)}

static func accept(state: Dictionary, quest_id: String, revision: int, profile_id: String = "player_01", variant_id: String = "") -> Dictionary:
	var candidate := state.duplicate(true)
	var created := Quests.create_instance(candidate, quest_id, revision, variant_id, profile_id)
	if not bool(created.get("ok", false)):
		return created
	var instance_id := str(created.instance.instance_id)
	var attached := ensure_instance(candidate, instance_id)
	if not bool(attached.ok):
		return attached
	state.clear()
	state.merge(candidate, true)
	return {"ok": true, "instance": get_instance(state, instance_id), "progress": get_progress(state, instance_id)}

static func list_stages(state: Dictionary, instance_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var instance := get_instance(state, instance_id)
	var progress := get_progress(state, instance_id)
	for stage in Rules.stages(instance.get("quest_snapshot", {})) if not instance.is_empty() else []:
		var copy: Dictionary = stage.duplicate(true)
		copy.merge(progress.get("stages", {}).get(str(stage.stage_id), {"status": "LOCKED"}), true)
		copy["available"] = Rules.dependencies_complete(stage, progress) and str(instance.get("status", "")) == "ACTIVE" and not bool(instance.get("safety_hold", false))
		result.append(copy)
	return result

static func context(state: Dictionary, instance_id: String, stage_id: String, allow_completed: bool = false) -> Dictionary:
	var instance := get_instance(state, instance_id)
	var progress := get_progress(state, instance_id)
	if instance.is_empty() or progress.is_empty():
		return {"ok": false, "reason": "unknown_instance"}
	var quest: Dictionary = instance.get("quest_snapshot", {})
	if str(progress.get("snapshot_hash", "")) != Validation.content_hash(quest):
		return {"ok": false, "reason": "snapshot_changed"}
	var stage := Rules.stage_by_id(quest, stage_id)
	if stage.is_empty() or not progress.stages.has(stage_id):
		return {"ok": false, "reason": "unknown_stage"}
	var current: Dictionary = progress.stages[stage_id]
	# Completed stages are read-only/idempotent even after revocation.
	if allow_completed and str(current.status) == "COMPLETED":
		return {"ok": true, "instance": instance, "quest": quest, "progress": progress, "stage": stage, "current": current}
	var version_key := Quests.version_key(str(instance.quest_id), int(instance.revision))
	if bool(instance.get("safety_hold", false)) or state.get("phase_b", {}).get("revoked_versions", []).has(version_key):
		return {"ok": false, "reason": "safety_hold"}
	if not str(instance.get("superseded_by_instance_id", "")).is_empty():
		return {"ok": false, "reason": "instance_migrated"}
	if str(instance.get("status", "")) != "ACTIVE":
		return {"ok": false, "reason": "instance_not_active"}
	if not Rules.dependencies_complete(stage, progress):
		return {"ok": false, "reason": "stage_locked"}
	if str(current.status) == "COMPLETED":
		return {"ok": false, "reason": "stage_completed"}
	return {"ok": true, "instance": instance, "quest": quest, "progress": progress, "stage": stage, "current": current}

static func refresh_availability(state: Dictionary, instance_id: String) -> void:
	var progress: Dictionary = state.adventures.progress[instance_id]
	var quest: Dictionary = state.phase_b.quest_instances[instance_id].quest_snapshot
	progress.next_context = ""
	for stage in Rules.stages(quest):
		var current: Dictionary = progress.stages[str(stage.stage_id)]
		if str(current.status) == "LOCKED" and Rules.dependencies_complete(stage, progress):
			current.status = "AVAILABLE"
		if str(current.status) in ["AVAILABLE", "IN_PROGRESS", "AWAITING_REVIEW"] and str(progress.next_context).is_empty():
			progress.next_context = str(stage.get("next_hint", stage.get("title", "")))

static func start_stage(state: Dictionary, instance_id: String, stage_id: String) -> Dictionary:
	var checked := context(state, instance_id, stage_id)
	if not bool(checked.ok):
		return checked
	if str(checked.current.status) == "AWAITING_REVIEW":
		return {"ok": false, "reason": "awaiting_review"}
	var current: Dictionary = state.adventures.progress[instance_id].stages[stage_id]
	current.status = "IN_PROGRESS"
	if not current.has("started_at"):
		current.started_at = Time.get_datetime_string_from_system()
	return {"ok": true, "stage": current.duplicate(true)}

static func save_draft(state: Dictionary, instance_id: String, stage_id: String, draft: Dictionary) -> Dictionary:
	var shape := Rules.validate_evidence_shape(draft)
	if not bool(shape.ok):
		return shape
	var checked := start_stage(state, instance_id, stage_id)
	if not bool(checked.ok):
		return checked
	state.adventures.progress[instance_id].stages[stage_id].draft = draft.duplicate(true)
	if draft.get("choices", {}) is Dictionary:
		state.adventures.progress[instance_id].choices.merge(draft.get("choices", {}).duplicate(true), true)
	return {"ok": true}

static func record_attempt(state: Dictionary, instance_id: String, stage_id: String, interaction_id: String, response: Dictionary) -> Dictionary:
	var checked := context(state, instance_id, stage_id)
	if not bool(checked.ok):
		return checked
	var interactions: Dictionary = checked.quest.get("adventure", {}).get("interactions", {})
	if not interactions.has(interaction_id) or not _interaction_in_stage(checked.quest, checked.stage, interaction_id):
		return {"ok": false, "reason": "unknown_interaction"}
	if str(checked.current.status) == "AWAITING_REVIEW":
		return {"ok": false, "reason": "awaiting_review"}
	var outcome := Rules.check_interaction(interactions[interaction_id], response)
	if str(outcome.get("reason", "")) == "invalid_response":
		return outcome
	var current: Dictionary = state.adventures.progress[instance_id].stages[stage_id]
	current.status = "IN_PROGRESS"
	var attempt := {"interaction_id": interaction_id, "response": response.duplicate(true), "success": bool(outcome.ok), "created_at": Time.get_datetime_string_from_system(), "assistance": response.get("assistance", ""), "help_history": current.help_history.duplicate(true)}
	current.attempts.append(attempt)
	var lexeme_update: Dictionary = {}
	if bool(outcome.ok):
		state.adventures.progress[instance_id].choices[interaction_id] = response.duplicate(true)
		var definition: Dictionary = interactions[interaction_id]
		var kind := str(definition.get("type", ""))
		if bool(definition.get("config", {}).get("lexeme_credit", true)) and kind in ["inspect_reveal", "match_cards", "order_fragments", "assemble_selection", "scripted_dialogue", "exhibit_composition"]:
			var ids: Array = definition.get("config", {}).get("lexeme_ids", []).duplicate(true)
			if ids.is_empty():
				for envelope in checked.quest.get("adventure", {}).get("envelopes", []):
					if envelope.get("interaction_ids", []).has(interaction_id):
						ids.append_array(envelope.get("lexeme_ids", []))
			if not ids.is_empty():
				var word_status := "recognized" if kind in ["inspect_reveal", "match_cards", "order_fragments"] else "used"
				lexeme_update = record_lexemes(state, instance_id, ids, word_status, str(response.get("assistance", "")))
	var result := {"ok": true, "success": bool(outcome.ok), "outcome": outcome, "attempt": attempt.duplicate(true), "lexeme_update": lexeme_update}
	result["lexemes"] = state.adventures.progress[instance_id].lexemes.duplicate(true)
	return result

static func _interaction_in_stage(quest: Dictionary, stage: Dictionary, interaction_id: String) -> bool:
	if stage.get("interaction_ids", []).has(interaction_id):
		return true
	# Envelope interactions are part of the corresponding frozen channel.
	for envelope in quest.get("adventure", {}).get("envelopes", []):
		if envelope.get("interaction_ids", []).has(interaction_id):
			var sid := str(stage.get("stage_id", ""))
			return str(envelope.get("channel_id", "")) == sid or (sid == "es_intro" and int(envelope.get("number", 0)) == 1)
	return false

static func request_help(state: Dictionary, instance_id: String, stage_id: String, interaction_id: String = "", level: int = 1) -> Dictionary:
	var checked := context(state, instance_id, stage_id)
	if not bool(checked.ok):
		return checked
	var chosen := interaction_id
	if chosen.is_empty() and not checked.stage.get("interaction_ids", []).is_empty():
		chosen = str(checked.stage.interaction_ids[0])
	var interaction: Dictionary = checked.quest.get("adventure", {}).get("interactions", {}).get(chosen, {})
	if interaction.is_empty() or not _interaction_in_stage(checked.quest, checked.stage, chosen):
		return {"ok": false, "reason": "unknown_interaction"}
	var hints: Array = interaction.get("hints", [])
	if level < 1 or level > 3 or level > hints.size():
		return {"ok": false, "reason": "unknown_hint"}
	state.adventures.progress[instance_id].stages[stage_id].help_history.append({"interaction_id": chosen, "level": level, "created_at": Time.get_datetime_string_from_system()})
	return {"ok": true, "hint": hints[level - 1], "level": level}

static func record_lexemes(state: Dictionary, instance_id: String, lexeme_ids: Array, status: String = "encountered", assistance: String = "") -> Dictionary:
	var instance := get_instance(state, instance_id)
	if instance.is_empty() or not state.get("adventures", {}).get("progress", {}).has(instance_id):
		return {"ok": false, "reason": "unknown_instance"}
	if str(instance.get("status", "")) != "ACTIVE" or bool(instance.get("safety_hold", false)) or not str(instance.get("superseded_by_instance_id", "")).is_empty():
		return {"ok": false, "reason": "instance_not_active"}
	if state.get("phase_b", {}).get("revoked_versions", []).has(Quests.version_key(str(instance.quest_id), int(instance.revision))):
		return {"ok": false, "reason": "safety_hold"}
	if str(state.adventures.progress[instance_id].snapshot_hash) != Validation.content_hash(instance.quest_snapshot):
		return {"ok": false, "reason": "snapshot_changed"}
	if not ["encountered", "recognised", "recognized", "used", "want_review"].has(status):
		return {"ok": false, "reason": "unknown_lexeme_status"}
	var known: Dictionary = {}
	for lexeme in instance.quest_snapshot.get("adventure", {}).get("lexicon", []):
		known[str(lexeme.get("lexeme_id", ""))] = lexeme
	var ids := Rules.unique_ids(lexeme_ids)
	for id in ids:
		if not known.has(id):
			return {"ok": false, "reason": "unknown_lexeme", "lexeme_id": id}
	var progress: Dictionary = state.adventures.progress[instance_id]
	for id in ids:
		var record: Dictionary = progress.lexemes.get(id, {"lexeme_id": id, "recognized": false, "used": false, "history": []})
		record.status = status
		record.used = bool(record.used) or status == "used"
		record.recognized = bool(record.get("recognized", false)) or status in ["recognized", "recognised", "used"]
		record.last_seen_at = Time.get_datetime_string_from_system()
		record.history.append({"status": status, "assistance": assistance, "created_at": record.last_seen_at})
		progress.lexemes[id] = record
	var recognized_count := 0
	var used_count := 0
	for record in progress.lexemes.values():
		if bool(record.get("recognized", false)): recognized_count += 1
		if bool(record.get("used", false)): used_count += 1
	return {"ok": true, "unique_count": progress.lexemes.size(), "recognized_count": recognized_count, "used_count": used_count, "current_status": status}

## Resolve only successful, validated choices against the frozen snapshot.
## UI can use these concrete labels and authored hints in subsequent scenes.
static func choice_context(state: Dictionary, instance_id: String) -> Dictionary:
	var instance := get_instance(state, instance_id)
	var progress := get_progress(state, instance_id)
	var adventure: Dictionary = instance.get("quest_snapshot", {}).get("adventure", {})
	var result := {"summary": "", "hints": [], "theme": "", "layout": "", "question": "", "choices": {}, "effect_ids": [], "suggested_category_id": "", "visual_theme": ""}
	var aliases := {"broadcast_theme": "es_15_dispatch", "theme": "game_choose_concept", "layout": "game_choose_layout", "question": "water_question"}
	var summaries: Array[String] = []
	for choice_key in adventure.get("choice_effects", {}):
		var interaction_id := str(aliases.get(str(choice_key), str(choice_key)))
		var stored: Variant = progress.get("choices", {}).get(interaction_id, {})
		var response: Dictionary = stored.duplicate(true) if stored is Dictionary else {}
		if stored is Array:
			# Compatibility for an early UI which saved only selected IDs. Recover
			# authored fields from the validated attempt rather than inventing them.
			for stage_progress in progress.get("stages", {}).values():
				for attempt in stage_progress.get("attempts", []):
					if str(attempt.get("interaction_id", "")) == interaction_id and bool(attempt.get("success", false)):
						response = attempt.get("response", {}).duplicate(true)
			response.selected_ids = stored.duplicate(true)
		var definition: Dictionary = adventure.get("interactions", {}).get(interaction_id, {})
		if definition.is_empty() or not bool(Rules.check_interaction(definition, response).get("ok", false)):
			continue
		var effects: Dictionary = adventure.choice_effects[choice_key]
		var chosen := Rules.unique_ids(response.get("selected_ids", []))
		var options: Array = definition.get("config", {}).get("choices", definition.get("config", {}).get("items", []))
		var labels: Array[String] = []
		var ids: Array[String] = []
		for id in chosen:
			if not effects.has(id): continue
			ids.append(id)
			for option in options:
				if str(option.get("id", "")) == id:
					labels.append(str(option.get("text", id)))
			if not result.effect_ids.has(str(effects[id])):
				result.effect_ids.append(str(effects[id]))
		if ids.is_empty(): continue
		result.choices[str(choice_key)] = {"selected_ids": ids, "labels": labels, "fields": response.get("fields", {}).duplicate(true), "interaction_id": interaction_id}
		var label_text := ", ".join(labels)
		if str(choice_key) in ["broadcast_theme", "theme"]:
			result.theme = label_text
			result.visual_theme = ids[0]
			summaries.append("Тема: " + label_text)
		elif str(choice_key) == "layout":
			result.layout = label_text
			summaries.append("Места предметов: " + label_text)
		elif str(choice_key) == "question":
			var own_question := str(response.get("fields", {}).get("question", "")).strip_edges()
			result.question = own_question if ids[0] == "own" and not own_question.is_empty() else label_text
			result.suggested_category_id = ids[0]
			summaries.append("Исследуем: " + str(result.question))
			for interaction in adventure.get("interactions", {}).values():
				var hint := str(interaction.get("config", {}).get("question_hints", {}).get(ids[0], ""))
				if not hint.is_empty() and not result.hints.has(hint): result.hints.append(hint)
		var instruction := str(adventure.get("choice_instructions", {}).get(choice_key, ""))
		if not instruction.is_empty(): result.hints.append(instruction)
		if str(choice_key) == "broadcast_theme":
			result.hints.append("Продолжи выбранную тему в следующем сообщении и оформлении открытки: " + label_text)
	result.summary = " · ".join(summaries)
	return result

static func pause(state: Dictionary, instance_id: String) -> Dictionary:
	return {"ok": Quests.pause_instance(state, instance_id)}

static func resume(state: Dictionary, instance_id: String) -> Dictionary:
	if not str(get_instance(state, instance_id).get("superseded_by_instance_id", "")).is_empty():
		return {"ok": false, "reason": "instance_migrated"}
	return {"ok": Quests.resume_instance(state, instance_id)}

static func lineage_awarded(state: Dictionary, lineage_id: String) -> int:
	var lineage: Dictionary = state.get("adventures", {}).get("reward_lineages", {}).get(lineage_id, {})
	var total := 0
	var legacy_events := 0
	var phase_b: Dictionary = state.get("phase_b", {})
	for event in state.get("phase_b", {}).get("award_events", {}).values():
		if str(event.get("profile_id", "")) != str(lineage.get("profile_id", "")):
			continue
		if str(event.get("reward_lineage_id", "")) == lineage_id:
			total += int(event.get("budget", 0))
		elif str(event.get("reward_lineage_id", "")).is_empty():
			var source_id := str(phase_b.get("activities", {}).get(str(event.get("activity_id", "")), {}).get("instance_id", ""))
			var source: Dictionary = phase_b.get("quest_instances", {}).get(source_id, {})
			if str(source.get("reward_lineage_id", "")) == lineage_id:
				legacy_events += int(event.get("budget", 0))
	return total + maxi(int(lineage.get("legacy_awarded_budget", 0)), legacy_events)

static func _allocate_remaining(state: Dictionary, instance_id: String) -> void:
	var progress: Dictionary = state.adventures.progress[instance_id]
	var instance: Dictionary = state.phase_b.quest_instances[instance_id]
	var lineage: Dictionary = state.adventures.reward_lineages[progress.reward_lineage_id]
	var remaining := maxi(0, int(lineage.budget) - lineage_awarded(state, str(progress.reward_lineage_id)))
	var definitions := Rules.stages(instance.quest_snapshot)
	var shares := 0
	for stage in definitions:
		var existing_key := Rules.grant_key(str(progress.profile_id), str(progress.reward_lineage_id), str(progress.stage_reward_map[str(stage.stage_id)]) + ":stage")
		if str(progress.stages[str(stage.stage_id)].status) != "COMPLETED" and not state.adventures.grants.has(existing_key):
			shares += int(stage.get("budget_share", 0))
	var assigned := 0
	var cumulative := 0
	for stage in definitions:
		var sid := str(stage.stage_id)
		var share := int(stage.get("budget_share", 0)) if str(progress.stages[sid].status) != "COMPLETED" else 0
		if state.adventures.grants.has(Rules.grant_key(str(progress.profile_id), str(progress.reward_lineage_id), str(progress.stage_reward_map[sid]) + ":stage")):
			share = 0
		cumulative += share
		var allocation := int(floor(float(remaining) * float(cumulative) / float(shares))) - assigned if shares > 0 else 0
		progress.remaining_budget_plan[sid] = allocation
		assigned += allocation

static func migrate_instance(state: Dictionary, instance_id: String, revision: int, stage_mapping: Dictionary = {}, actor_id: String = "parent_local") -> Dictionary:
	if actor_id not in ["parent_local", "family_joint"]:
		return {"ok": false, "reason": "joint_review_required"}
	var candidate := state.duplicate(true)
	var ensured := ensure_instance(candidate, instance_id)
	if not bool(ensured.ok):
		return ensured
	var old := get_instance(candidate, instance_id)
	if str(old.get("status", "")) == "COMPLETED":
		return {"ok": false, "reason": "completed_result_in_archive", "instance_id": instance_id}
	if not str(old.get("superseded_by_instance_id", "")).is_empty():
		return {"ok": false, "reason": "already_migrated"}
	if revision == int(old.revision):
		return {"ok": false, "reason": "same_revision"}
	# Only the explicitly transferred instance is omitted from repeat checking.
	# It is restored verbatim as historical evidence immediately afterwards.
	candidate.phase_b.quest_instances.erase(instance_id)
	var created := Quests.create_instance(candidate, str(old.quest_id), revision, str(old.get("variant_id", "")), str(old.profile_id))
	candidate.phase_b.quest_instances[instance_id] = old
	if not bool(created.get("ok", false)):
		return created
	var new_id := str(created.instance.instance_id)
	var new_instance: Dictionary = candidate.phase_b.quest_instances[new_id]
	if int(new_instance.quest_snapshot.get("reward_policy", {}).get("activity_budget", 0)) != int(candidate.adventures.reward_lineages[old.reward_lineage_id].budget):
		return {"ok": false, "reason": "migration_budget_changed"}
	new_instance.reward_lineage_id = old.reward_lineage_id
	new_instance.migrated_from_instance_id = instance_id
	new_instance.awarded_budget = lineage_awarded(candidate, str(old.reward_lineage_id))
	var attached := ensure_instance(candidate, new_id)
	if not bool(attached.ok):
		return attached
	var source: Dictionary = candidate.adventures.progress[instance_id]
	var destination: Dictionary = candidate.adventures.progress[new_id]
	var used_sources: Dictionary = {}
	for new_stage_id in stage_mapping:
		if stage_mapping[new_stage_id] is Dictionary:
			var mapping: Dictionary = stage_mapping[new_stage_id]
			var activity_id := str(mapping.get("source_activity_id", ""))
			var activity: Dictionary = candidate.phase_b.get("activities", {}).get(activity_id, {})
			if not destination.stages.has(str(new_stage_id)) or str(activity.get("instance_id", "")) != instance_id or str(activity.get("profile_id", "")) != str(old.profile_id) or str(activity.get("status", "")) != "CONFIRMED" or used_sources.has(activity_id):
				return {"ok": false, "reason": "invalid_legacy_activity_mapping", "stage_id": new_stage_id}
			used_sources[activity_id] = true
			var credited: Dictionary = destination.stages[str(new_stage_id)]
			credited.status = "COMPLETED"
			credited.confirmation_source = str(activity.get("reviewer_id", "legacy_milestone"))
			credited.source_activity_id = activity_id
			credited.migration_note = str(mapping.get("note", ""))
			credited.migration_actor_id = actor_id
			destination.stage_reward_map[str(new_stage_id)] = "legacy_activity:" + activity_id
			continue
		var source_id := str(stage_mapping[new_stage_id])
		if not destination.stages.has(str(new_stage_id)) or not source.stages.has(source_id) or str(source.stages[source_id].status) != "COMPLETED" or used_sources.has(source_id):
			return {"ok": false, "reason": "invalid_stage_mapping", "stage_id": new_stage_id}
		used_sources[source_id] = true
		destination.stages[str(new_stage_id)] = source.stages[source_id].duplicate(true)
		destination.stages[str(new_stage_id)].stage_id = str(new_stage_id)
		destination.stages[str(new_stage_id)].migrated_from_stage_id = source_id
		destination.stage_reward_map[str(new_stage_id)] = str(source.stage_reward_map[source_id])
	# Copy only lexemes actually known in both snapshots; never invent knowledge.
	var permitted: Dictionary = {}
	for lexeme in new_instance.quest_snapshot.get("adventure", {}).get("lexicon", []):
		permitted[str(lexeme.get("lexeme_id", ""))] = true
	for id in source.lexemes:
		if permitted.has(str(id)):
			destination.lexemes[id] = source.lexemes[id].duplicate(true)
	destination.choices = source.choices.duplicate(true)
	destination.migration = {"actor_id": actor_id, "stage_mapping": stage_mapping.duplicate(true), "source_instance_id": instance_id, "created_at": Time.get_datetime_string_from_system()}
	old.superseded_by_instance_id = new_id
	if str(old.status) != "COMPLETED":
		Quests.pause_instance(candidate, instance_id)
	_allocate_remaining(candidate, new_id)
	refresh_availability(candidate, new_id)
	state.clear()
	state.merge(candidate, true)
	return {"ok": true, "instance": get_instance(state, new_id), "progress": get_progress(state, new_id), "already_awarded": new_instance.awarded_budget, "remaining_budget_plan": destination.remaining_budget_plan.duplicate(true)}

static func migrate_legacy(state: Dictionary) -> Dictionary:
	if bool(state.get("read_only", false)):
		return {"ok": false, "reason": "read_only"}
	ensure_adventures(state)
	Collections.ensure_collections(state)
	var count := 0
	var errors: Array = []
	for instance_id in state.get("phase_b", {}).get("quest_instances", {}).keys():
		var instance := get_instance(state, str(instance_id))
		if instance.get("quest_snapshot", {}).has("adventure"):
			continue
		var attached := ensure_instance(state, str(instance_id))
		if not bool(attached.ok):
			errors.append(attached)
			continue
		if str(instance.get("status", "")) != "COMPLETED":
			_allocate_remaining(state, str(instance_id))
			continue
		state.adventures.progress[instance_id].stages.legacy_result.status = "COMPLETED"
		state.adventures.progress[instance_id].next_context = ""
		var work_id := "legacy-work:" + str(instance_id)
		if state.collections.works.has(work_id):
			continue
		var activity: Dictionary = state.get("phase_b", {}).get("activities", {}).get(str(instance.get("activity_id", "")), {})
		var data := {"work_id": work_id, "title": instance.quest_snapshot.get("title", instance.quest_id), "kind": "note", "status": "COMPLETED",
			"quest_ids": [instance.quest_id], "authorship": {"category": "personal", "confirmation_source": activity.get("reviewer_id", "unknown_legacy")},
			"content": {"note": activity.get("note", "Ранее завершённый результат"), "legacy_instance_id": instance_id, "legacy_activity_id": activity.get("activity_id", "")},
			"source": {"instance_id": instance_id, "activity_id": activity.get("activity_id", ""), "reviewer_id": activity.get("reviewer_id", "unknown_legacy"), "quest_snapshot": instance.quest_snapshot.duplicate(true)}}
		var artifact_id := str(activity.get("artifact_id", ""))
		if not artifact_id.is_empty() and state.get("phase_b", {}).get("artifacts", {}).get(artifact_id, {}).get("profile_id", "") == instance.profile_id:
			data.content.artifact_id = artifact_id
		var created := Collections.create_work(state, data, str(instance.profile_id))
		if bool(created.ok):
			Collections.create_exhibit(state, work_id, "legacy_card", "", str(instance.profile_id))
			count += 1
		else:
			errors.append(created)
	return {"ok": errors.is_empty(), "created_works": count, "errors": errors}

static func list_adventures(state: Dictionary, profile_id: String = "player_01", filters: Dictionary = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var seen: Dictionary = {}
	for instance in state.get("phase_b", {}).get("quest_instances", {}).values():
		if str(instance.get("profile_id", "")) != profile_id:
			continue
		var row: Dictionary = instance.get("quest_snapshot", {}).duplicate(true)
		row.merge({"instance_id": instance.instance_id, "status": instance.status, "progress": get_progress(state, str(instance.instance_id))}, true)
		result.append(row)
		seen[str(instance.quest_id)] = true
	for quest in Quests.list_player_quests(state.duplicate(true)):
		if not seen.has(str(quest.quest_id)):
			quest.status = "AVAILABLE"
			result.append(quest)
	var filtered: Array[Dictionary] = []
	var query := str(filters.get("search", filters.get("query", ""))).to_lower()
	for row in result:
		if not query.is_empty() and not (str(row.get("title", "")) + " " + str(row.get("story_title", ""))).to_lower().contains(query):
			continue
		if filters.has("status") and str(filters.status) != "" and str(row.status) != str(filters.status):
			continue
		if filters.has("location_id") and str(row.get("location_id", "")) != str(filters.location_id):
			continue
		if filters.has("interest") and not row.get("reward_policy", {}).get("skill_weights_percent", {}).has(str(filters.interest)):
			continue
		var next_stage: Dictionary = {}
		if row.has("instance_id"):
			for stage in list_stages(state, str(row.instance_id)):
				if str(stage.get("status", "")) in ["AVAILABLE", "IN_PROGRESS", "AWAITING_REVIEW"]:
					next_stage = stage
					break
		elif not Rules.stages(row).is_empty():
			next_stage = Rules.stages(row)[0]
		if filters.has("adult_required"):
			var adult := str(next_stage.get("completion_policy", "")) == "joint_review" or str(row.get("adult_participation", "")) == "required"
			if adult != bool(filters.adult_required):
				continue
		if filters.has("max_minutes"):
			var duration: Variant = next_stage.get("estimated_minutes", row.get("estimated_minutes", {}))
			var minutes := int(duration.get("min", 0)) if duration is Dictionary else int(duration)
			if minutes > int(filters.max_minutes):
				continue
		if bool(filters.get("favorites", false)) and not get_pinned(state, profile_id).has(str(row.quest_id)):
			continue
		filtered.append(row)
	filtered.sort_custom(func(a, b):
		var left := int(a.get("editorial_priority", a.get("featured_order", 999)))
		var right := int(b.get("editorial_priority", b.get("featured_order", 999)))
		return left < right if left != right else str(a.quest_id) < str(b.quest_id))
	return filtered

static func get_pinned(state: Dictionary, profile_id: String = "player_01") -> Array[String]:
	return Rules.unique_ids(state.get("adventures", {}).get("pinned_by_profile", {}).get(profile_id, ["FG01", "FG11", "FG08"]))

static func set_pinned(state: Dictionary, quest_ids: Array, profile_id: String = "player_01") -> Dictionary:
	var ids := Rules.unique_ids(quest_ids)
	if ids.size() > 3:
		return {"ok": false, "reason": "pin_limit"}
	var available: Dictionary = {}
	for row in list_adventures(state, profile_id):
		available[str(row.quest_id)] = true
	for id in ids:
		if not available.has(id):
			return {"ok": false, "reason": "unknown_quest"}
	var adventures := ensure_adventures(state)
	if not adventures.has("pinned_by_profile"):
		adventures.pinned_by_profile = {}
	adventures.pinned_by_profile[profile_id] = ids
	return {"ok": true, "quest_ids": ids}

static func get_secrets(state: Dictionary, profile_id: String = "player_01") -> Array[String]:
	return Rules.unique_ids(state.get("adventures", {}).get("secrets_by_profile", {}).get(profile_id, []))

static func discover_secret(state: Dictionary, secret_id: String, profile_id: String = "player_01") -> Dictionary:
	var definition: Dictionary = {}
	for secret in Content.secrets():
		if str(secret.get("secret_id", secret.get("id", ""))) == secret_id:
			definition = secret
	if definition.is_empty():
		return {"ok": false, "reason": "unknown_secret"}
	var secrets := get_secrets(state, profile_id)
	if secrets.has(secret_id):
		return {"ok": true, "applied": false}
	secrets.append(secret_id)
	var adventures := ensure_adventures(state)
	if not adventures.has("secrets_by_profile"):
		adventures.secrets_by_profile = {}
	adventures.secrets_by_profile[profile_id] = secrets
	var created := Collections.create_work(state, {"work_id": "secret:" + profile_id + ":" + secret_id, "title": definition.get("title", "Находка"), "kind": "note", "status": "COMPLETED", "authorship": {"category": "story"}, "content": definition.duplicate(true)}, profile_id)
	if bool(created.ok):
		Collections.create_exhibit(state, str(created.work_id), "note", "", profile_id)
	if secrets.size() >= 3:
		_cosmetic_grant(state, profile_id, "secrets", "secret_constellation_theme")
	return {"ok": true, "applied": true, "secret": definition, "theme_unlocked": secrets.size() >= 3}

static func _cosmetic_grant(state: Dictionary, profile_id: String, lineage_id: String, reward_id: String) -> void:
	var key := Rules.grant_key(profile_id, lineage_id, reward_id)
	var adventures := ensure_adventures(state)
	if not adventures.grants.has(key):
		adventures.grants[key] = {"grant_id": key, "profile_id": profile_id, "reward_lineage_id": lineage_id, "canonical_reward_id": reward_id, "effect_id": reward_id, "amount": 0, "created_at": Time.get_datetime_string_from_system()}

static func chapter_status(state: Dictionary, profile_id: String = "player_01") -> Dictionary:
	var completed: Array[String] = []
	for instance in state.get("phase_b", {}).get("quest_instances", {}).values():
		var qid := str(instance.get("quest_id", ""))
		if str(instance.get("profile_id", "")) == profile_id and str(instance.get("status", "")) == "COMPLETED" and Rules.BUDGETS.has(qid) and not completed.has(qid):
			completed.append(qid)
	var chapter: Dictionary = state.get("adventures", {}).get("chapters_by_profile", {}).get(profile_id, {})
	return {"available": completed.size() == 3, "completed": bool(chapter.get("completed", false)), "completed_quest_ids": completed, "selections": chapter.get("selections", {}).duplicate(true)}

static func complete_chapter(state: Dictionary, selections: Dictionary, profile_id: String = "player_01") -> Dictionary:
	var status := chapter_status(state, profile_id)
	if not bool(status.available):
		return {"ok": false, "reason": "chapter_not_ready"}
	if bool(status.completed):
		return {"ok": true, "applied": false, "snapshot_offer": true}
	for qid in Rules.BUDGETS:
		var work := Collections.get_work(state, str(selections.get(qid, "")), profile_id)
		if work.is_empty() or not work.get("quest_ids", []).has(qid):
			return {"ok": false, "reason": "chapter_work_required", "quest_id": qid}
	var adventures := ensure_adventures(state)
	if not adventures.has("chapters_by_profile"):
		adventures.chapters_by_profile = {}
	adventures.chapters_by_profile[profile_id] = {"completed": true, "selections": selections.duplicate(true), "created_at": Time.get_datetime_string_from_system()}
	for reward_id in ["gallery_evening_light", "chapter_card"]:
		_cosmetic_grant(state, profile_id, "station_on_air", reward_id)
	var work := Collections.create_work(state, {"work_id": "chapter:" + profile_id + ":station_on_air", "title": str(selections.get("title", "Первая глава")), "kind": "album", "status": "COMPLETED", "authorship": {"category": "personal"}, "quest_ids": ["FG01", "FG11", "FG08"], "content": {"selected_work_ids": selections.duplicate(true)}}, profile_id)
	if not bool(work.ok): return work
	var exhibit := Collections.create_exhibit(state, str(work.work_id), "chapter_album", "", profile_id)
	return {"ok": true, "applied": true, "snapshot_offer": true, "work_id": work.work_id, "exhibit_id": exhibit.get("exhibit_id", "")}

## Controller adapter. Stage completion uses an in-memory persistence callback:
## caller MUST save this candidate before replacing live state or showing effects.
## Runtime loading here deliberately avoids Adventure -> Commit -> Adventure preload cycles.
static func dispatch(state: Dictionary, operation: String, payload: Dictionary, profile_id: String = "player_01", launch_verifier: Callable = Callable()) -> Dictionary:
	if bool(state.get("read_only", false)):
		return {"ok": false, "reason": "read_only"}
	var iid := str(payload.get("instance_id", ""))
	var sid := str(payload.get("stage_id", ""))
	if not iid.is_empty() and str(get_instance(state, iid).get("profile_id", "")) != profile_id:
		return {"ok": false, "reason": "unknown_instance"}
	match operation:
		"start_adventure":
			var qid := str(payload.get("quest_id", ""))
			var revision := int(payload.get("revision", 0))
			var choose_latest := revision == 0
			for row in list_adventures(state, profile_id):
				if str(row.quest_id) != qid:
					continue
				if row.has("instance_id") and str(row.status) in ["ACTIVE", "PAUSED", "SUBMITTED"]:
					return {"ok": true, "instance": get_instance(state, str(row.instance_id)), "instance_id": row.instance_id}
				if choose_latest:
					revision = maxi(revision, int(row.get("revision", 0)))
			var result := accept(state, qid, revision, profile_id, str(payload.get("variant_id", "")))
			if bool(result.get("ok", false)):
				result.instance_id = result.instance.instance_id
			return result
		"stage_start":
			return start_stage(state, iid, sid)
		"stage_draft":
			return save_draft(state, iid, sid, payload.get("draft", {}))
		"stage_attempt":
			return record_attempt(state, iid, sid, str(payload.get("interaction_id", "")), payload.get("response", {}))
		"stage_lexemes":
			return record_lexemes(state, iid, payload.get("lexeme_ids", []), str(payload.get("status", "encountered")), str(payload.get("assistance", "")))
		"stage_hint":
			return request_help(state, iid, sid, str(payload.get("interaction_id", "")), int(payload.get("level", 1)))
		"stage_submit", "stage_review":
			var commit = load("res://scripts/services/activity_commit_service.gd")
			var candidate_only := func(_candidate: Dictionary) -> bool: return true
			if operation == "stage_submit":
				return commit.commit_stage(state, iid, sid, payload.get("evidence", {}), "player_self", candidate_only, launch_verifier)
			return commit.review_stage(state, iid, sid, bool(payload.get("approved", false)), str(payload.get("note", "")), "parent_local", candidate_only, payload, launch_verifier)
		"pause", "pause_adventure", "pause_quest":
			return pause(state, iid)
		"resume", "resume_adventure", "resume_quest":
			return resume(state, iid)
		"pin_quest":
			var ids := get_pinned(state, profile_id)
			var qid := str(payload.get("quest_id", ""))
			ids.erase(qid)
			if bool(payload.get("pinned", true)):
				ids.append(qid)
			return set_pinned(state, ids, profile_id)
		"discover_secret":
			return discover_secret(state, str(payload.get("secret_id", "")), profile_id)
		"chapter_finale":
			var selections: Dictionary = payload.get("selections", {}).duplicate(true)
			selections.title = str(payload.get("title", "Первая глава"))
			selections.quiet = bool(payload.get("quiet", false))
			for work_id in payload.get("work_ids", []):
				var work := Collections.get_work(state, str(work_id), profile_id)
				for qid in work.get("quest_ids", []):
					if Rules.BUDGETS.has(str(qid)):
						selections[str(qid)] = str(work_id)
			return complete_chapter(state, selections, profile_id)
		"migrate_adventure":
			return migrate_instance(state, iid, int(payload.get("revision", 0)), payload.get("stage_mapping", {}), "parent_local")
	return {"ok": false, "reason": "unknown_operation", "operation": operation}
