class_name ActivityCommitService
extends RefCounted

## Transaction boundary. Every change (including the review submission) is
## prepared on an isolated copy and becomes live only after persistence succeeds.
const Adventures = preload("res://scripts/services/adventure_service.gd")
const Rules = preload("res://scripts/domain/adventure_rules.gd")
const Collections = preload("res://scripts/services/collection_service.gd")
const Progress = preload("res://scripts/services/progress_service.gd")
const Quests = preload("res://scripts/services/quest_service.gd")
const Atlas = preload("res://scripts/services/atlas_service.gd")
const Save = preload("res://scripts/services/save_service.gd")
const Launch = preload("res://scripts/services/launch_service.gd")

static func commit_stage(state: Dictionary, instance_id: String, stage_id: String, evidence: Dictionary = {}, actor_id: String = "player_self", persist: Callable = Callable(), launch_verifier: Callable = Callable()) -> Dictionary:
	if bool(state.get("read_only", false)):
		return {"ok": false, "reason": "read_only"}
	var candidate := state.duplicate(true)
	var attached := Adventures.ensure_instance(candidate, instance_id)
	if not bool(attached.ok):
		return attached
	var checked := Adventures.context(candidate, instance_id, stage_id, true)
	if not bool(checked.ok):
		return checked
	if str(checked.current.status) == "COMPLETED":
		return {"ok": true, "applied": false, "reason": "already_completed", "stage": checked.current}
	if str(checked.current.status) == "AWAITING_REVIEW":
		return {"ok": true, "applied": false, "awaiting_review": true}
	var report: Dictionary = checked.current.get("draft", {}).duplicate(true)
	report.merge(evidence.duplicate(true), true)
	var shape := Rules.validate_evidence_shape(report)
	if not bool(shape.ok):
		return shape
	# Flatten form fields for rules while preserving their authored structure.
	for field in report.get("fields", {}):
		if not report.has(field):
			report[field] = report.fields[field]
	# Keep authored real-world fields and meaningful choices in the result even
	# when the UI submission contains only the final note.
	for attempt in checked.current.get("attempts", []):
		if bool(attempt.get("success", false)):
			for field in attempt.get("response", {}).get("fields", {}):
				if not report.has(field):
					report[field] = attempt.response.fields[field]
	var valid := _validate_completion(checked, report, launch_verifier)
	if not bool(valid.ok):
		valid["draft"] = report
		return valid
	var current: Dictionary = candidate.adventures.progress[instance_id].stages[stage_id]
	current.draft = report.duplicate(true)
	current.submitted_by = actor_id
	current.submitted_at = Time.get_datetime_string_from_system()
	if str(checked.stage.completion_policy) == "joint_review":
		current.status = "AWAITING_REVIEW"
		current.submitted_evidence = report.duplicate(true)
		return _persist(state, candidate, {"ok": true, "applied": true, "awaiting_review": true, "stage": current.duplicate(true)}, persist)
	var finished := _finish(candidate, instance_id, stage_id, report, actor_id)
	if not bool(finished.ok):
		return finished
	return _persist(state, candidate, finished, persist)

static func review_stage(state: Dictionary, instance_id: String, stage_id: String, approved: bool, note: String = "", actor_id: String = "parent_local", persist: Callable = Callable(), review_details: Dictionary = {}, launch_verifier: Callable = Callable()) -> Dictionary:
	if bool(state.get("read_only", false)):
		return {"ok": false, "reason": "read_only"}
	if actor_id not in ["parent_local", "family_joint"]:
		return {"ok": false, "reason": "joint_review_required"}
	var candidate := state.duplicate(true)
	var checked := Adventures.context(candidate, instance_id, stage_id, true)
	if not bool(checked.ok):
		return checked
	if str(checked.current.status) == "COMPLETED":
		return {"ok": true, "applied": false, "reason": "already_completed"}
	if str(checked.current.status) != "AWAITING_REVIEW" or str(checked.stage.completion_policy) != "joint_review":
		return {"ok": false, "reason": "stage_not_submitted"}
	var current: Dictionary = candidate.adventures.progress[instance_id].stages[stage_id]
	var review := {"approved": approved, "actor_id": actor_id, "note": note, "assistance": review_details.get("assistance", ""), "criteria": review_details.get("criteria", []).duplicate(true), "created_at": Time.get_datetime_string_from_system()}
	current.review_history.append(review)
	current.review_note = note
	if not approved:
		current.status = "IN_PROGRESS"
		return _persist(state, candidate, {"ok": true, "applied": true, "needs_revision": true, "stage": current.duplicate(true)}, persist)
	# The explicit review command is the local family's attestation, not identity authentication.
	if review_details.has("criteria"):
		if not review_details.criteria is Array:
			return {"ok": false, "reason": "invalid_evidence", "field": "criteria"}
		var criteria: Array = review_details.criteria
		if criteria.size() != checked.stage.get("criteria", []).size() or criteria.has(false):
			return {"ok": false, "reason": "criteria_not_confirmed"}
		for criterion in criteria:
			if not criterion is bool or not criterion:
				return {"ok": false, "reason": "criteria_not_confirmed"}
	var report: Dictionary = current.get("submitted_evidence", {}).duplicate(true)
	if review_details.has("assistance"):
		report.review_assistance = str(review_details.assistance)
	var valid := _validate_completion(checked, report, launch_verifier)
	if not bool(valid.ok):
		return valid
	var finished := _finish(candidate, instance_id, stage_id, report, actor_id)
	if not bool(finished.ok):
		return finished
	return _persist(state, candidate, finished, persist)

static func _validate_completion(checked: Dictionary, evidence: Dictionary, launch_verifier: Callable = Callable()) -> Dictionary:
	var policy := str(checked.stage.get("completion_policy", ""))
	if policy == "self_attest" and not bool(evidence.get("attested", false)):
		return {"ok": false, "reason": "self_attestation_required"}
	var interactions: Dictionary = checked.quest.get("adventure", {}).get("interactions", {})
	for interaction_id in checked.stage.get("interaction_ids", []):
		if not interactions.has(str(interaction_id)):
			return {"ok": false, "reason": "missing_frozen_interaction", "interaction_id": interaction_id}
		var definition: Dictionary = interactions[str(interaction_id)]
		var success := false
		for attempt in checked.current.get("attempts", []):
			if str(attempt.get("interaction_id", "")) == str(interaction_id) and bool(attempt.get("success", false)):
				# Recheck actual data against frozen rules, not a persisted/UI success flag.
				if bool(Rules.check_interaction(definition, attempt.get("response", {})).get("ok", false)):
					success = true
		if not success:
			return {"ok": false, "reason": "interaction_incomplete", "interaction_id": interaction_id}
		if str(interaction_id) == str(checked.quest.get("adventure", {}).get("final_check", {}).get("interaction_id", "")):
			var matching_attempt := false
			for attempt in checked.current.get("attempts", []):
				if str(attempt.get("interaction_id", "")) != str(interaction_id) or not bool(Rules.check_interaction(definition, attempt.get("response", {})).get("ok", false)):
					continue
				var unassisted := Rules.unassisted_lexemes(definition, attempt.get("response", {}))
				var claimed := Rules.unique_ids(evidence.get("unassisted_lexeme_ids", []))
				var sample := Rules.unique_ids(evidence.get("sample_lexeme_ids", []))
				var actual_sample := Rules.unique_ids(definition.get("config", {}).get("lexeme_ids", []))
				unassisted.sort()
				claimed.sort()
				sample.sort()
				actual_sample.sort()
				if unassisted == claimed and sample == actual_sample:
					matching_attempt = true
			if not matching_attempt:
				return {"ok": false, "reason": "mixed_check_attempt_required"}
		for source_id in definition.get("config", {}).get("source_stage_ids", []):
			if str(checked.progress.stages.get(str(source_id), {}).get("status", "")) != "COMPLETED":
				return {"ok": false, "reason": "source_work_incomplete", "stage_id": source_id}
	var checked_evidence := Rules.check_evidence(checked.quest, checked.stage, checked.progress, evidence)
	if not bool(checked_evidence.ok):
		return checked_evidence
	if str(checked.instance.quest_id) == "FG11" and str(checked.stage.stage_id) == "game_premiere":
		var entry_id := str(evidence.get("launch_entry_id", ""))
		if entry_id.is_empty():
			return {"ok": false, "reason": "registered_game_required"}
		var verified: Dictionary = launch_verifier.call(entry_id, str(checked.instance.profile_id)) if launch_verifier.is_valid() else Launch.new().inspect_entry(entry_id, str(checked.instance.profile_id))
		if not bool(verified.get("ok", false)):
			return {"ok": false, "reason": "registered_game_unavailable", "detail": verified}
		var entry: Dictionary = verified.get("entry", {})
		if str(entry.get("launch_entry_id", "")) != entry_id or str(entry.get("profile_id", "")) != str(checked.instance.profile_id):
			return {"ok": false, "reason": "launch_profile_mismatch"}
		if bool(entry.get("demonstration_only", true)):
			return {"ok": false, "reason": "own_project_required"}
		var archive := str(entry.get("source_archive_file", ""))
		if archive.is_empty() or archive.begins_with("/") or archive.contains(":") or archive.contains(".."):
			return {"ok": false, "reason": "managed_source_archive_required"}
		evidence.source_archive_file = archive
		# Derive the archive label from the verified registration, never a claimed
		# UI field. A saved .app contains a binary bundle rather than project source.
		evidence.source_archive_kind = str(entry.get("source_archive_kind", "project_source"))
	return {"ok": true}

static func _finish(state: Dictionary, instance_id: String, stage_id: String, evidence: Dictionary, actor_id: String) -> Dictionary:
	var instance: Dictionary = state.phase_b.quest_instances[instance_id]
	var progress: Dictionary = state.adventures.progress[instance_id]
	var quest: Dictionary = instance.quest_snapshot
	var stage := Rules.stage_by_id(quest, stage_id)
	var current: Dictionary = progress.stages[stage_id]
	var profile_id := str(instance.profile_id)
	var lineage_id := str(progress.reward_lineage_id)
	var lineage: Dictionary = state.adventures.reward_lineages[lineage_id]
	if str(lineage.profile_id) != profile_id:
		return {"ok": false, "reason": "lineage_profile_mismatch"}
	var canonical_id := str(progress.stage_reward_map.get(stage_id, stage_id))
	var key := Rules.grant_key(profile_id, lineage_id, canonical_id + ":stage")
	var remaining := int(lineage.budget) - Adventures.lineage_awarded(state, lineage_id)
	if remaining < 0:
		return {"ok": false, "reason": "lineage_budget_exceeded"}
	var amount := mini(remaining, int(progress.remaining_budget_plan.get(stage_id, stage.get("budget_share", 0))))
	var grant: Dictionary = state.adventures.grants.get(key, {})
	if grant.is_empty():
		var activity_id := "stage:" + key
		var award := Progress.apply_award(state, profile_id, "award:" + key, activity_id, amount,
			quest.get("reward_policy", {}).get("skill_weights_percent", {}) if amount > 0 else {}, [])
		if not bool(award.get("applied", false)):
			return {"ok": false, "reason": "award_failed", "detail": award}
		state.phase_b.award_events["award:" + key].reward_lineage_id = lineage_id
		state.phase_b.award_events["award:" + key].canonical_reward_id = canonical_id
		state.phase_b.activities[activity_id] = {"activity_id": activity_id, "profile_id": profile_id,
			"instance_id": instance_id, "quest_id": instance.quest_id, "stage_id": stage_id,
			"reward_lineage_id": lineage_id, "status": "CONFIRMED", "kind": "adventure_stage",
			"note": evidence.get("note", ""), "evidence": evidence.duplicate(true), "reviewer_id": actor_id,
			"confirmed_at": Time.get_datetime_string_from_system()}
		var work_result := _record_work(state, instance_id, stage, evidence, actor_id, key)
		if not bool(work_result.ok):
			return work_result
		grant = {"grant_id": key, "profile_id": profile_id, "reward_lineage_id": lineage_id,
			"canonical_reward_id": canonical_id + ":stage", "source_instance_id": instance_id,
			"source_activity_id": activity_id, "stage_id": stage_id, "amount": amount,
			"work_id": work_result.get("work_id", ""), "version_id": work_result.get("version_id", ""),
			"exhibit_id": work_result.get("exhibit_id", ""), "created_at": Time.get_datetime_string_from_system()}
		state.adventures.grants[key] = grant
		for reward_id in stage.get("grant_ids", []):
			if not quest.get("adventure", {}).get("grant_definitions", {}).has(str(reward_id)):
				return {"ok": false, "reason": "unknown_grant", "grant_id": reward_id}
			var effect_key := Rules.grant_key(profile_id, lineage_id, canonical_id + ":effect:" + str(reward_id))
			if not state.adventures.grants.has(effect_key):
				state.adventures.grants[effect_key] = {"grant_id": effect_key, "profile_id": profile_id,
					"reward_lineage_id": lineage_id, "canonical_reward_id": canonical_id + ":effect:" + str(reward_id),
					"effect_id": reward_id, "source_instance_id": instance_id, "source_activity_id": activity_id,
					"definition": quest.adventure.grant_definitions[str(reward_id)].duplicate(true), "amount": 0,
					"created_at": Time.get_datetime_string_from_system()}
		var atlas_ids: Array = stage.get("atlas_unlock_ids", []).duplicate(true)
		if str(instance.quest_id) == "FG08" and str(stage.stage_id) in ["water_river", "water_fall"]:
			atlas_ids = [str(evidence.get("atlas_location_id", ""))]
		var unlocked := _unlock_atlas(state, profile_id, atlas_ids)
		if not bool(unlocked.ok):
			return unlocked
		state.adventures.pending_presentations[key] = {"event_id": key, "profile_id": profile_id,
			"instance_id": instance_id, "stage_id": stage_id, "grant_ids": stage.get("grant_ids", []).duplicate(true),
			"work_id": grant.work_id, "shown": false}
	current.status = "COMPLETED"
	current.confirmation_source = actor_id
	current.confirmed_at = Time.get_datetime_string_from_system()
	current.award_key = key
	current.work_id = grant.get("work_id", "")
	current.version_id = grant.get("version_id", "")
	current.exhibit_id = grant.get("exhibit_id", "")
	current.evidence = evidence.duplicate(true)
	progress.choices.merge(evidence.get("choices", {}).duplicate(true), true)
	instance.awarded_budget = Adventures.lineage_awarded(state, lineage_id)
	Adventures.refresh_availability(state, instance_id)
	var completed := Rules.all_required_complete(quest, progress)
	if completed:
		if int(instance.awarded_budget) != int(lineage.budget):
			return {"ok": false, "reason": "incomplete_budget_allocation"}
		var final_activity_id := "adventure-final:" + Rules.grant_key(profile_id, lineage_id, "final")
		var submitted := Quests.submit_result(state, instance_id, final_activity_id, str(evidence.get("note", "")), str(evidence.get("artifact_id", "")))
		if not bool(submitted.get("ok", false)):
			return submitted
		var confirmed := Quests.confirm_result(state, final_activity_id, actor_id)
		if not bool(confirmed.get("ok", false)):
			return confirmed
	return {"ok": true, "applied": true, "stage": current.duplicate(true), "amount": int(grant.get("amount", 0)),
		"grant_id": key, "work_id": grant.get("work_id", ""), "exhibit_id": grant.get("exhibit_id", ""), "completed": completed}

static func _record_work(state: Dictionary, instance_id: String, stage: Dictionary, evidence: Dictionary, actor_id: String, grant_key: String) -> Dictionary:
	var instance: Dictionary = state.phase_b.quest_instances[instance_id]
	var progress: Dictionary = state.adventures.progress[instance_id]
	var profile_id := str(instance.profile_id)
	var recipe_id := str(stage.get("work_recipe_id", "legacy_card"))
	var recipe: Dictionary = instance.quest_snapshot.get("adventure", {}).get("work_recipes", {}).get(recipe_id, {})
	if recipe.is_empty() and instance.quest_snapshot.has("adventure"):
		return {"ok": false, "reason": "unknown_work_recipe", "recipe_id": recipe_id}
	var content := {"note": evidence.get("note", ""), "fields": evidence.get("fields", {}).duplicate(true),
		"choices": progress.choices.duplicate(true), "stage_id": stage.stage_id,
		"evidence": evidence.duplicate(true), "source_stage_works": {}}
	content.choices.merge(evidence.get("choices", {}).duplicate(true), true)
	if str(instance.quest_id) == "FG01":
		content.lexemes = progress.lexemes.duplicate(true)
	for dependency in stage.get("prerequisite_stage_ids", []):
		var source: Dictionary = progress.stages.get(str(dependency), {})
		if not str(source.get("work_id", "")).is_empty():
			content.source_stage_works[str(dependency)] = {"work_id": source.work_id, "version_id": source.get("version_id", "")}
	if evidence.has("artifact_id") and not str(evidence.artifact_id).is_empty():
		content.artifact_id = str(evidence.artifact_id)
	if evidence.has("launch_entry_id"):
		content.launch_entry_id = str(evidence.launch_entry_id)
	if evidence.has("source_archive_file"):
		content.source_archive_file = str(evidence.source_archive_file)
		content.source_archive_kind = str(evidence.get("source_archive_kind", "project_source"))
	# Only the growing album and game project share works; observations stay distinct.
	var group := str(recipe.get("work_group_id", ""))
	if group.is_empty() and str(instance.quest_id) == "FG11" and str(stage.stage_id) != "game_concept":
		group = "game_project"
	if group.is_empty() and str(instance.quest_id) == "FG01" and str(stage.stage_id) != "es_intro":
		group = "radio_album"
	var work_id := "work:" + Rules.grant_key(profile_id, str(progress.reward_lineage_id), group if not group.is_empty() else str(progress.stage_reward_map[str(stage.stage_id)]))
	var result: Dictionary
	if Collections.get_work(state, work_id, profile_id).is_empty():
		result = Collections.create_work(state, {"work_id": work_id,
			"title": str(evidence.get("work_title", recipe.get("title", stage.get("title", "Моя работа")))) ,
			"kind": recipe.get("work_kind", "note"), "status": "IN_PROGRESS", "quest_ids": [instance.quest_id],
			"authorship": {"category": evidence.get("authorship_category", "personal"), "contribution": evidence.get("own_contribution", evidence.get("own_change", "")), "shared_work": evidence.get("shared_work", ""), "confirmation_source": actor_id},
			"content": content, "assistance": evidence.get("review_assistance", evidence.get("assistance", "")),
			"source": {"instance_id": instance_id, "grant_id": grant_key, "recipe": recipe.duplicate(true), "quest_snapshot": instance.quest_snapshot.duplicate(true)}}, profile_id)
	else:
		result = Collections.add_version(state, work_id, content, str(stage.get("title", "")), str(evidence.get("review_assistance", evidence.get("assistance", ""))), profile_id)
	if not bool(result.ok):
		return result
	var exhibit := Collections.create_exhibit(state, work_id, recipe_id, "", profile_id)
	if not bool(exhibit.ok):
		return exhibit
	var other_required := false
	for other in Rules.stages(instance.quest_snapshot):
		if str(other.stage_id) != str(stage.stage_id) and bool(other.get("required", true)) and str(progress.stages[str(other.stage_id)].status) != "COMPLETED":
			other_required = true
	state.collections.works[work_id].status = "IN_PROGRESS" if other_required and not group.is_empty() else "COMPLETED"
	return {"ok": true, "work_id": work_id, "version_id": result.version_id, "exhibit_id": exhibit.exhibit_id}

static func _unlock_atlas(state: Dictionary, profile_id: String, location_ids: Array) -> Dictionary:
	for location_id in location_ids:
		if Atlas.get_location({}, str(location_id)).is_empty():
			return {"ok": false, "reason": "unknown_atlas_location", "location_id": location_id}
	if not state.has("phase_c"):
		state.phase_c = {}
	if not state.phase_c.has("atlas_unlocked_by_profile"):
		state.phase_c.atlas_unlocked_by_profile = {}
	var ids: Array = state.phase_c.atlas_unlocked_by_profile.get(profile_id, []).duplicate(true)
	for location_id in location_ids:
		if not ids.has(location_id):
			ids.append(location_id)
		if profile_id == "player_01":
			Atlas.unlock(state, str(location_id))
	state.phase_c.atlas_unlocked_by_profile[profile_id] = ids
	return {"ok": true}

static func _persist(live: Dictionary, candidate: Dictionary, result: Dictionary, persist: Callable) -> Dictionary:
	var saved: Variant = persist.call(candidate) if persist.is_valid() else Save.save_game(candidate)
	var ok: bool = bool(saved.get("ok", false)) if saved is Dictionary else (saved is bool and saved)
	if not ok:
		var detail: Dictionary = saved if saved is Dictionary else (Save.get_last_error() if not persist.is_valid() else {})
		return {"ok": false, "reason": "save_failed", "detail": detail.duplicate(true), "retryable": true}
	live.clear()
	live.merge(candidate, true)
	return result

static func pending_presentations(state: Dictionary, profile_id: String = "player_01") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event in state.get("adventures", {}).get("pending_presentations", {}).values():
		if str(event.get("profile_id", "")) == profile_id and not bool(event.get("shown", false)):
			result.append(event.duplicate(true))
	return result

static func acknowledge_presentation(state: Dictionary, event_id: String, profile_id: String = "player_01", persist: Callable = Callable()) -> Dictionary:
	var event: Dictionary = state.get("adventures", {}).get("pending_presentations", {}).get(event_id, {})
	if event.is_empty() or str(event.get("profile_id", "")) != profile_id:
		return {"ok": false, "reason": "unknown_presentation"}
	var candidate := state.duplicate(true)
	candidate.adventures.pending_presentations[event_id].shown = true
	return _persist(state, candidate, {"ok": true}, persist)
