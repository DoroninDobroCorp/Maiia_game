class_name RitualService
extends RefCounted

## Небольшие повторяемые ритуалы живут отдельно от квестов: они не создают
## соревнование за XP и могут открывать спокойные постоянные изменения станции.

const ProgressServiceScript = preload("res://scripts/services/progress_service.gd")

const MOVEMENT_RITUAL_ID := "movement_warmup"
const TARGET_DAYS := 5
const UNLOCK_EFFECT_ID := "movement_ritual_light"

static func ensure(state: Dictionary) -> Dictionary:
	var phase_c: Dictionary = state.get("phase_c", {})
	var rituals: Dictionary = phase_c.get("rituals", {})
	var ritual: Dictionary = rituals.get(MOVEMENT_RITUAL_ID, {})
	if not ritual.has("days"):
		ritual["days"] = []
	if not ritual.has("target_days"):
		ritual["target_days"] = TARGET_DAYS
	if not ritual.has("unlocked"):
		ritual["unlocked"] = false
	rituals[MOVEMENT_RITUAL_ID] = ritual
	phase_c["rituals"] = rituals
	state["phase_c"] = phase_c
	return ritual

static func get_state(state: Dictionary) -> Dictionary:
	return ensure(state).duplicate(true)

static func mark_today(state: Dictionary) -> Dictionary:
	return mark_day(state, Time.get_date_string_from_system())

static func mark_day(state: Dictionary, date_string: String) -> Dictionary:
	var day := date_string.strip_edges()
	if day.is_empty():
		return {"ok": false, "reason": "empty_date"}

	var ritual := ensure(state)
	var days: Array = ritual.get("days", [])
	if days.has(day):
		return {
			"ok": true,
			"already_marked": true,
			"days": days.size(),
			"target_days": int(ritual.get("target_days", TARGET_DAYS)),
			"unlocked": bool(ritual.get("unlocked", false)),
			"newly_unlocked": false
		}

	days.append(day)
	ritual["days"] = days
	var target_days := int(ritual.get("target_days", TARGET_DAYS))
	var newly_unlocked := false
	var award: Dictionary = {}
	if days.size() >= target_days and not bool(ritual.get("unlocked", false)):
		ritual["unlocked"] = true
		newly_unlocked = true
		award = ProgressServiceScript.apply_award(
			state,
			"player_01",
			"ritual:movement_warmup:unlock",
			"ritual:movement_warmup",
			0,
			{},
			[UNLOCK_EFFECT_ID]
		)

	var phase_c: Dictionary = state.get("phase_c", {})
	var rituals: Dictionary = phase_c.get("rituals", {})
	rituals[MOVEMENT_RITUAL_ID] = ritual
	phase_c["rituals"] = rituals
	state["phase_c"] = phase_c
	return {
		"ok": true,
		"already_marked": false,
		"days": days.size(),
		"target_days": target_days,
		"unlocked": bool(ritual.get("unlocked", false)),
		"newly_unlocked": newly_unlocked,
		"award": award
	}
