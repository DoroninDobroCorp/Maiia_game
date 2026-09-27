class_name QuestService
extends RefCounted

## Жизненный цикл Phase B: публикация точной версии -> принятие -> заявка
## результата -> подтверждение -> единая награда и устойчивое изменение мира.

const ContentValidationScript = preload("res://scripts/domain/content_validation.gd")
const ProgressServiceScript = preload("res://scripts/services/progress_service.gd")

static func ensure_phase_b(state: Dictionary) -> Dictionary:
	var phase_b: Dictionary = state.get("phase_b", {})
	for pair in [
		["approval_records", []],
		["published_versions", {}],
		["retired_versions", []],
		["revoked_versions", []],
		["quest_instances", {}],
		["activities", {}]
	]:
		if not phase_b.has(pair[0]):
			phase_b[pair[0]] = pair[1]
	state["phase_b"] = phase_b
	ProgressServiceScript.ensure_phase_b(state)
	return state["phase_b"] as Dictionary

static func approve_and_publish(state: Dictionary, quest: Dictionary, actor_id: String = "parent_local") -> Dictionary:
	var checked := ContentValidationScript.validate_quest(quest)
	if not bool(checked.get("valid", false)):
		return {"ok": false, "reason": "validation_failed", "errors": checked.get("errors", [])}

	var qid := str(quest.get("quest_id", ""))
	var revision := int(quest.get("revision", 0))
	var key := version_key(qid, revision)
	var hash := ContentValidationScript.content_hash(quest)
	var phase_b := ensure_phase_b(state)
	var published: Dictionary = phase_b.get("published_versions", {})
	if published.has(key):
		var existing: Dictionary = published[key]
		if str(existing.get("content_hash", "")) == hash:
			return {"ok": true, "already_published": true, "version_key": key, "content_hash": hash}
		return {"ok": false, "reason": "revision_conflict", "message": "Одобренную ревизию нельзя менять на месте; создайте revision + 1."}

	var snapshot := quest.duplicate(true)
	snapshot["content_status"] = "PUBLISHED"
	var approval_id := "approval:%s:%d:%s" % [qid, revision, hash.substr(0, 12)]
	var record := {
		"approval_id": approval_id,
		"actor_id": actor_id,
		"quest_id": qid,
		"revision": revision,
		"content_hash": hash,
		"decision": "APPROVED",
		"created_at": Time.get_datetime_string_from_system()
	}
	published[key] = {
		"quest": snapshot,
		"content_hash": hash,
		"approval_id": approval_id,
		"published_at": record["created_at"]
	}
	var approvals: Array = phase_b.get("approval_records", [])
	approvals.append(record)
	phase_b["approval_records"] = approvals
	phase_b["published_versions"] = published
	state["phase_b"] = phase_b
	return {"ok": true, "version_key": key, "content_hash": hash, "approval": record}

static func is_exact_version_published(state: Dictionary, quest: Dictionary) -> bool:
	var qid := str(quest.get("quest_id", ""))
	var revision := int(quest.get("revision", 0))
	var key := version_key(qid, revision)
	var phase_b := ensure_phase_b(state)
	if (phase_b.get("revoked_versions", []) as Array).has(key):
		return false
	var published: Dictionary = phase_b.get("published_versions", {})
	if not published.has(key):
		return false
	return str((published[key] as Dictionary).get("content_hash", "")) == ContentValidationScript.content_hash(quest)

static func list_player_quests(state: Dictionary) -> Array[Dictionary]:
	var phase_b := ensure_phase_b(state)
	var published: Dictionary = phase_b.get("published_versions", {})
	var retired: Array = phase_b.get("retired_versions", [])
	var revoked: Array = phase_b.get("revoked_versions", [])
	var result: Array[Dictionary] = []
	for key in published.keys():
		if retired.has(key) or revoked.has(key):
			continue
		var quest: Dictionary = (published[key] as Dictionary).get("quest", {})
		if str(quest.get("quest_id", "")) == "S00":
			continue
		result.append(quest.duplicate(true))
	result.sort_custom(func(a, b): return str(a.get("quest_id", "")) < str(b.get("quest_id", "")))
	return result

static func create_instance(
	state: Dictionary,
	quest_id: String,
	revision: int,
	variant_id: String = "",
	profile_id: String = "player_01"
) -> Dictionary:
	var phase_b := ensure_phase_b(state)
	var key := version_key(quest_id, revision)
	if (phase_b.get("retired_versions", []) as Array).has(key) or (phase_b.get("revoked_versions", []) as Array).has(key):
		return {"ok": false, "reason": "version_unavailable"}
	var published: Dictionary = phase_b.get("published_versions", {})
	if not published.has(key):
		return {"ok": false, "reason": "not_published"}
	var frozen: Dictionary = (published[key] as Dictionary).get("quest", {}).duplicate(true)
	var repeat_check := _check_repeat_policy(phase_b, frozen, profile_id)
	if not bool(repeat_check.get("ok", true)):
		return repeat_check
	var variants: Array = frozen.get("variants", [])
	var chosen_variant := variant_id
	if chosen_variant.is_empty() and not variants.is_empty():
		chosen_variant = str((variants[0] as Dictionary).get("id", ""))
	if not _variant_exists(variants, chosen_variant):
		return {"ok": false, "reason": "unknown_variant"}

	var instances: Dictionary = phase_b.get("quest_instances", {})
	var instance_id := "%s:%d:%s:%d" % [quest_id, revision, profile_id, instances.size() + 1]
	var instance := {
		"instance_id": instance_id,
		"profile_id": profile_id,
		"quest_id": quest_id,
		"revision": revision,
		"content_hash": (published[key] as Dictionary).get("content_hash", ""),
		"quest_snapshot": frozen,
		"variant_id": chosen_variant,
		"status": "ACTIVE",
		"created_at": Time.get_datetime_string_from_system(),
		"activity_id": "",
		"awarded_budget": 0,
		"completed_milestones": [],
		"safety_hold": false
	}
	instances[instance_id] = instance
	phase_b["quest_instances"] = instances
	state["phase_b"] = phase_b
	ProgressServiceScript.ensure_profile(state, profile_id)
	return {"ok": true, "instance": instance.duplicate(true)}

static func submit_result(
	state: Dictionary,
	instance_id: String,
	activity_id: String,
	note: String = "",
	artifact_id: String = ""
) -> Dictionary:
	var phase_b := ensure_phase_b(state)
	var instances: Dictionary = phase_b.get("quest_instances", {})
	if not instances.has(instance_id):
		return {"ok": false, "reason": "unknown_instance"}
	var instance: Dictionary = instances[instance_id]
	if bool(instance.get("safety_hold", false)):
		return {"ok": false, "reason": "safety_hold"}
	if str(instance.get("status", "")) != "ACTIVE":
		return {"ok": false, "reason": "instance_not_active"}
	var activities: Dictionary = phase_b.get("activities", {})
	if activities.has(activity_id):
		return {"ok": false, "reason": "activity_already_used"}

	var activity := {
		"activity_id": activity_id,
		"instance_id": instance_id,
		"profile_id": str(instance.get("profile_id", "player_01")),
		"quest_id": str(instance.get("quest_id", "")),
		"revision": int(instance.get("revision", 0)),
		"note": note.substr(0, 800),
		"artifact_id": artifact_id,
		"status": "SUBMITTED",
		"submitted_at": Time.get_datetime_string_from_system()
	}
	activities[activity_id] = activity
	instance["activity_id"] = activity_id
	instance["status"] = "SUBMITTED"
	instances[instance_id] = instance
	phase_b["activities"] = activities
	phase_b["quest_instances"] = instances
	state["phase_b"] = phase_b
	return {"ok": true, "activity": activity.duplicate(true)}

static func request_revision(state: Dictionary, activity_id: String, review_note: String) -> Dictionary:
	var phase_b := ensure_phase_b(state)
	var activities: Dictionary = phase_b.get("activities", {})
	if not activities.has(activity_id):
		return {"ok": false, "reason": "unknown_activity"}
	var activity: Dictionary = activities[activity_id]
	if str(activity.get("status", "")) != "SUBMITTED":
		return {"ok": false, "reason": "activity_not_submitted"}
	var instance_id := str(activity.get("instance_id", ""))
	var instances: Dictionary = phase_b.get("quest_instances", {})
	var instance: Dictionary = instances.get(instance_id, {})
	activity["status"] = "NEEDS_REVISION"
	activity["review_note"] = review_note.substr(0, 500)
	instance["status"] = "ACTIVE"
	instance["activity_id"] = ""
	activities[activity_id] = activity
	instances[instance_id] = instance
	phase_b["activities"] = activities
	phase_b["quest_instances"] = instances
	state["phase_b"] = phase_b
	return {"ok": true}

static func confirm_result(state: Dictionary, activity_id: String, reviewer_id: String = "parent_local") -> Dictionary:
	var phase_b := ensure_phase_b(state)
	var activities: Dictionary = phase_b.get("activities", {})
	if not activities.has(activity_id):
		return {"ok": false, "reason": "unknown_activity"}
	var activity: Dictionary = activities[activity_id]
	if str(activity.get("status", "")) == "CONFIRMED":
		return {"ok": true, "applied": false, "reason": "already_confirmed"}
	if str(activity.get("status", "")) != "SUBMITTED":
		return {"ok": false, "reason": "activity_not_submitted"}

	var instances: Dictionary = phase_b.get("quest_instances", {})
	var instance_id := str(activity.get("instance_id", ""))
	if not instances.has(instance_id):
		return {"ok": false, "reason": "unknown_instance"}
	var instance: Dictionary = instances[instance_id]
	var quest: Dictionary = instance.get("quest_snapshot", {})
	var reward: Dictionary = quest.get("reward_policy", {})
	var total_budget := int(reward.get("activity_budget", 0))
	var already_awarded := int(instance.get("awarded_budget", 0))
	var remainder := maxi(0, total_budget - already_awarded)
	var award := ProgressServiceScript.apply_award(
		state,
		str(instance.get("profile_id", "player_01")),
		"award:" + activity_id + ":final",
		activity_id,
		remainder,
		reward.get("skill_weights_percent", {}) if remainder > 0 else {},
		reward.get("world_effect_ids", [])
	)
	if not bool(award.get("applied", false)) and str(award.get("reason", "")) != "duplicate_award":
		return {"ok": false, "reason": "award_failed", "detail": award}

	phase_b = ensure_phase_b(state)
	activities = phase_b.get("activities", {})
	instances = phase_b.get("quest_instances", {})
	activity = activities[activity_id]
	instance = instances[instance_id]
	activity["status"] = "CONFIRMED"
	activity["reviewer_id"] = reviewer_id
	activity["confirmed_at"] = Time.get_datetime_string_from_system()
	instance["status"] = "COMPLETED"
	instance["awarded_budget"] = total_budget
	activities[activity_id] = activity
	instances[instance_id] = instance
	phase_b["activities"] = activities
	phase_b["quest_instances"] = instances
	state["phase_b"] = phase_b
	return {"ok": true, "applied": true, "award": award, "world_effects": reward.get("world_effect_ids", []).duplicate(true)}

static func record_milestone(state: Dictionary, instance_id: String, milestone_index: int) -> Dictionary:
	var phase_b := ensure_phase_b(state)
	var instances: Dictionary = phase_b.get("quest_instances", {})
	if not instances.has(instance_id):
		return {"ok": false, "reason": "unknown_instance"}
	var instance: Dictionary = instances[instance_id]
	if str(instance.get("status", "")) != "ACTIVE":
		return {"ok": false, "reason": "instance_not_active"}
	var quest: Dictionary = instance.get("quest_snapshot", {})
	var reward: Dictionary = quest.get("reward_policy", {})
	var milestones: Array = reward.get("milestones_percent", [])
	if milestone_index < 0 or milestone_index >= milestones.size():
		return {"ok": false, "reason": "unknown_milestone"}
	var completed: Array = instance.get("completed_milestones", [])
	if completed.has(milestone_index):
		return {"ok": true, "applied": false, "reason": "already_recorded"}
	var total_budget := int(reward.get("activity_budget", 0))
	var remaining := maxi(0, total_budget - int(instance.get("awarded_budget", 0)))
	var milestone_amount := mini(remaining, int(round(float(total_budget) * float(int(milestones[milestone_index])) / 100.0)))
	var activity_id := "milestone:%s:%d" % [instance_id, milestone_index]
	var award := ProgressServiceScript.apply_award(
		state,
		str(instance.get("profile_id", "player_01")),
		"award:" + activity_id,
		activity_id,
		milestone_amount,
		reward.get("skill_weights_percent", {}) if milestone_amount > 0 else {},
		[]
	)
	if not bool(award.get("applied", false)):
		return {"ok": false, "reason": "award_failed", "detail": award}

	phase_b = ensure_phase_b(state)
	instances = phase_b.get("quest_instances", {})
	instance = instances[instance_id]
	completed = instance.get("completed_milestones", [])
	completed.append(milestone_index)
	instance["completed_milestones"] = completed
	instance["awarded_budget"] = int(instance.get("awarded_budget", 0)) + milestone_amount
	instances[instance_id] = instance
	var activities: Dictionary = phase_b.get("activities", {})
	activities[activity_id] = {
		"activity_id": activity_id,
		"instance_id": instance_id,
		"profile_id": str(instance.get("profile_id", "player_01")),
		"status": "CONFIRMED",
		"kind": "milestone",
		"milestone_index": milestone_index
	}
	phase_b["activities"] = activities
	phase_b["quest_instances"] = instances
	state["phase_b"] = phase_b
	return {"ok": true, "applied": true, "amount": milestone_amount}

static func pause_instance(state: Dictionary, instance_id: String) -> bool:
	var phase_b := ensure_phase_b(state)
	var instances: Dictionary = phase_b.get("quest_instances", {})
	if not instances.has(instance_id):
		return false
	var instance: Dictionary = instances[instance_id]
	var status := str(instance.get("status", ""))
	if status != "ACTIVE" and status != "AVAILABLE":
		return false
	instance["status_before_pause"] = status
	instance["status"] = "PAUSED"
	instances[instance_id] = instance
	phase_b["quest_instances"] = instances
	state["phase_b"] = phase_b
	return true

static func resume_instance(state: Dictionary, instance_id: String) -> bool:
	var phase_b := ensure_phase_b(state)
	var instances: Dictionary = phase_b.get("quest_instances", {})
	if not instances.has(instance_id):
		return false
	var instance: Dictionary = instances[instance_id]
	if str(instance.get("status", "")) != "PAUSED" or bool(instance.get("safety_hold", false)):
		return false
	instance["status"] = str(instance.get("status_before_pause", "ACTIVE"))
	instances[instance_id] = instance
	phase_b["quest_instances"] = instances
	state["phase_b"] = phase_b
	return true

static func revoke_version(state: Dictionary, quest_id: String, revision: int) -> bool:
	var phase_b := ensure_phase_b(state)
	var key := version_key(quest_id, revision)
	var published: Dictionary = phase_b.get("published_versions", {})
	if not published.has(key):
		return false
	var revoked: Array = phase_b.get("revoked_versions", [])
	if not revoked.has(key):
		revoked.append(key)
	var instances: Dictionary = phase_b.get("quest_instances", {})
	for instance_id in instances.keys():
		var instance: Dictionary = instances[instance_id]
		if version_key(str(instance.get("quest_id", "")), int(instance.get("revision", 0))) == key and str(instance.get("status", "")) != "COMPLETED":
			instance["status_before_pause"] = str(instance.get("status", "ACTIVE"))
			instance["status"] = "PAUSED"
			instance["safety_hold"] = true
			instances[instance_id] = instance
	phase_b["revoked_versions"] = revoked
	phase_b["quest_instances"] = instances
	state["phase_b"] = phase_b
	return true

static func retire_version(state: Dictionary, quest_id: String, revision: int) -> bool:
	var phase_b := ensure_phase_b(state)
	var key := version_key(quest_id, revision)
	if not (phase_b.get("published_versions", {}) as Dictionary).has(key):
		return false
	var retired: Array = phase_b.get("retired_versions", [])
	if not retired.has(key):
		retired.append(key)
	phase_b["retired_versions"] = retired
	state["phase_b"] = phase_b
	return true

static func version_key(quest_id: String, revision: int) -> String:
	return "%s@%d" % [quest_id, revision]

static func _variant_exists(variants: Array, variant_id: String) -> bool:
	for variant in variants:
		if typeof(variant) == TYPE_DICTIONARY and str((variant as Dictionary).get("id", "")) == variant_id:
			return true
	return variants.is_empty() and variant_id.is_empty()

static func _check_repeat_policy(phase_b: Dictionary, quest: Dictionary, profile_id: String) -> Dictionary:
	var policy: Dictionary = quest.get("repeat_policy", {})
	if policy.is_empty() or str(policy.get("mode", "unlimited")) == "unlimited":
		return {"ok": true}
	var qid := str(quest.get("quest_id", ""))
	var completed := 0
	var active := 0
	var instances: Dictionary = phase_b.get("quest_instances", {})
	for instance_value in instances.values():
		if typeof(instance_value) != TYPE_DICTIONARY:
			continue
		var instance: Dictionary = instance_value
		if str(instance.get("profile_id", "")) != profile_id or str(instance.get("quest_id", "")) != qid:
			continue
		var status := str(instance.get("status", ""))
		if status == "COMPLETED":
			completed += 1
		elif ["ACTIVE", "SUBMITTED", "PAUSED"].has(status):
			active += 1
	if active > 0:
		return {"ok": false, "reason": "quest_already_active"}
	var mode := str(policy.get("mode", "once"))
	var max_completions := 1 if mode == "once" else int(policy.get("max_completions", 1))
	if completed >= max_completions:
		return {"ok": false, "reason": "repeat_limit_reached", "completed": completed, "max_completions": max_completions}
	return {"ok": true, "completed": completed, "max_completions": max_completions}
