class_name ProgressService
extends RefCounted

## Единственная точка начисления Phase B. Награда и открытия идемпотентны
## по award_event_id и разделены по локальным профилям.

const ContentRepositoryScript = preload("res://scripts/services/content_repository.gd")
const PRIMARY_PROFILE_ID := "player_01"

static func ensure_phase_b(state: Dictionary) -> Dictionary:
	var phase_b: Dictionary = state.get("phase_b", {})
	if not phase_b.has("award_events"):
		phase_b["award_events"] = {}
	if not phase_b.has("skill_xp_by_profile"):
		phase_b["skill_xp_by_profile"] = {}
	if not phase_b.has("world_effects"):
		phase_b["world_effects"] = []
	if not phase_b.has("world_effects_by_profile"):
		phase_b["world_effects_by_profile"] = {}
	# Legacy saves kept the visible station effects in one array. Treat those
	# existing effects as belonging to the real player, then keep that array as
	# a compatibility mirror for player_01 only.
	var by_profile: Dictionary = phase_b.get("world_effects_by_profile", {})
	var primary_effects: Array = (by_profile.get(PRIMARY_PROFILE_ID, []) as Array).duplicate(true)
	for effect_id in (phase_b.get("world_effects", []) as Array):
		if not primary_effects.has(effect_id):
			primary_effects.append(effect_id)
	by_profile[PRIMARY_PROFILE_ID] = primary_effects
	phase_b["world_effects_by_profile"] = by_profile
	phase_b["world_effects"] = primary_effects.duplicate(true)
	state["phase_b"] = phase_b
	return phase_b

static func ensure_profile(state: Dictionary, profile_id: String) -> Dictionary:
	var phase_b := ensure_phase_b(state)
	var profiles: Dictionary = phase_b.get("skill_xp_by_profile", {})
	if not profiles.has(profile_id):
		var empty_xp: Dictionary = {}
		for skill_id in ContentRepositoryScript.SKILLS.keys():
			empty_xp[str(skill_id)] = 0
		profiles[profile_id] = empty_xp
	phase_b["skill_xp_by_profile"] = profiles
	state["phase_b"] = phase_b
	return profiles[profile_id] as Dictionary

static func apply_award(
	state: Dictionary,
	profile_id: String,
	award_event_id: String,
	activity_id: String,
	amount: int,
	weights: Dictionary,
	world_effect_ids: Array
) -> Dictionary:
	var phase_b := ensure_phase_b(state)
	var events: Dictionary = phase_b.get("award_events", {})
	if events.has(award_event_id):
		return {"applied": false, "reason": "duplicate_award", "event": events[award_event_id]}
	if amount < 0:
		return {"applied": false, "reason": "negative_amount"}

	var allocation := _allocate(amount, weights)
	if not bool(allocation.get("valid", false)):
		return {"applied": false, "reason": str(allocation.get("reason", "invalid_weights"))}
	for effect_id in world_effect_ids:
		var effect_text := str(effect_id)
		if not ContentRepositoryScript.WORLD_EFFECT_IDS.has(effect_text):
			return {"applied": false, "reason": "unknown_world_effect", "effect_id": effect_text}

	var xp := ensure_profile(state, profile_id)
	for skill_id in allocation.get("xp", {}).keys():
		xp[str(skill_id)] = int(xp.get(str(skill_id), 0)) + int(allocation["xp"][skill_id])

	phase_b = ensure_phase_b(state)
	var effects_by_profile: Dictionary = phase_b.get("world_effects_by_profile", {})
	var effects: Array = (effects_by_profile.get(profile_id, []) as Array).duplicate(true)
	for effect_id in world_effect_ids:
		var effect_text := str(effect_id)
		if not effects.has(effect_text):
			effects.append(effect_text)
	effects_by_profile[profile_id] = effects

	var event := {
		"award_event_id": award_event_id,
		"activity_id": activity_id,
		"profile_id": profile_id,
		"budget": amount,
		"xp": allocation.get("xp", {}).duplicate(true),
		"world_effect_ids": world_effect_ids.duplicate(true),
		"created_at": Time.get_datetime_string_from_system()
	}
	events[award_event_id] = event
	phase_b["award_events"] = events
	phase_b["world_effects_by_profile"] = effects_by_profile
	if profile_id == PRIMARY_PROFILE_ID:
		phase_b["world_effects"] = effects.duplicate(true)
	state["phase_b"] = phase_b
	return {"applied": true, "event": event, "allocation": allocation.get("xp", {})}

static func get_profile_xp(state: Dictionary, profile_id: String = "player_01") -> Dictionary:
	return ensure_profile(state, profile_id).duplicate(true)

static func get_profile_world_effects(state: Dictionary, profile_id: String = PRIMARY_PROFILE_ID) -> Array:
	var phase_b := ensure_phase_b(state)
	var by_profile: Dictionary = phase_b.get("world_effects_by_profile", {})
	return (by_profile.get(profile_id, []) as Array).duplicate(true)

static func _allocate(amount: int, weights: Dictionary) -> Dictionary:
	if amount == 0:
		return {"valid": weights.is_empty(), "xp": {}, "reason": "weights_for_zero_budget" if not weights.is_empty() else ""}
	if weights.is_empty():
		return {"valid": false, "xp": {}, "reason": "missing_weights"}

	var total_weight := 0
	var skill_ids: Array = weights.keys()
	skill_ids.sort_custom(func(a, b): return str(a) < str(b))
	for skill_id in skill_ids:
		if not ContentRepositoryScript.SKILLS.has(str(skill_id)):
			return {"valid": false, "xp": {}, "reason": "unknown_skill"}
		total_weight += int(weights[skill_id])
	if total_weight != 100:
		return {"valid": false, "xp": {}, "reason": "weights_not_100"}

	var xp: Dictionary = {}
	var assigned := 0
	for i in range(skill_ids.size()):
		var skill_id = skill_ids[i]
		var share: int
		if i == skill_ids.size() - 1:
			share = amount - assigned
		else:
			share = int(floor(float(amount) * float(int(weights[skill_id])) / 100.0))
		xp[str(skill_id)] = share
		assigned += share
	return {"valid": true, "xp": xp, "reason": ""}
