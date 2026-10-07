class_name RitualService
extends RefCounted

## Небольшие повторяемые ритуалы живут отдельно от квестов: они не создают
## соревнование за XP и могут открывать спокойные постоянные изменения станции.

const ProgressServiceScript = preload("res://scripts/services/progress_service.gd")

const MOVEMENT_RITUAL_ID := "movement_warmup"
const TARGET_DAYS := 5
const UNLOCK_EFFECT_ID := "movement_ritual_light"

const CHALLENGE_ID := "maya_30_streak"
const CHALLENGE_TARGET_DAYS := 30
const CHALLENGE_UNLOCK_EFFECT := "challenge_30_board"
const CHALLENGE_UNLOCK_LIGHT := "challenge_30_light"
const CHALLENGE_ITEMS: Array[String] = [
	"morning_run",
	"evening_stretch",
	"spanish_1",
	"spanish_2",
	"spanish_3",
	"spanish_4"
]

static func challenge_item_meta() -> Dictionary:
	return {
		"morning_run": {"title": "Утренняя пробежка", "icon": "🏃‍♀️", "desc": "Бег на свежем воздухе"},
		"evening_stretch": {"title": "Вечерняя растяжка", "icon": "🧘‍♀️", "desc": "Спокойная разминка и растяжка"},
		"spanish_1": {"title": "Испанский · подход 1", "icon": "🇪🇸", "desc": "Утренний диалог или слова"},
		"spanish_2": {"title": "Испанский · подход 2", "icon": "🇪🇸", "desc": "Дневной подход к карточкам"},
		"spanish_3": {"title": "Испанский · подход 3", "icon": "🇪🇸", "desc": "Вечернее чтение или эфир"},
		"spanish_4": {"title": "Испанский · подход 4", "icon": "🇪🇸", "desc": "Закрепление слов перед сном"}
	}

static func _is_valid_date_format(s: String) -> bool:
	if s.length() < 10:
		return false
	if s[4] != "-" or s[7] != "-":
		return false
	for i in [0, 1, 2, 3, 5, 6, 8, 9]:
		var c := s.unicode_at(i)
		if c < 48 or c > 57:
			return false
	return true

static func days_between(date_a: String, date_b: String) -> int:
	if date_a.is_empty() or date_b.is_empty():
		return 999999
	var s_a := date_a.strip_edges()
	var s_b := date_b.strip_edges()
	if not _is_valid_date_format(s_a) or not _is_valid_date_format(s_b):
		return 999999
	var dt_a: String = s_a if s_a.contains("T") else s_a + "T00:00:00"
	var dt_b: String = s_b if s_b.contains("T") else s_b + "T00:00:00"
	var unix_a := Time.get_unix_time_from_datetime_string(dt_a)
	var unix_b := Time.get_unix_time_from_datetime_string(dt_b)
	if unix_a == -1 or unix_b == -1:
		return 999999
	return int(round((unix_b - unix_a) / 86400.0))

static func ensure_challenge(state: Dictionary) -> Dictionary:
	var phase_c: Dictionary = state.get("phase_c", {})
	var rituals: Dictionary = phase_c.get("rituals", {})
	var c: Dictionary = rituals.get(CHALLENGE_ID, {})
	var today := Time.get_date_string_from_system()

	if not c.has("current_streak"): c["current_streak"] = 0
	if not c.has("max_streak"): c["max_streak"] = 0
	if not c.has("target_days"): c["target_days"] = CHALLENGE_TARGET_DAYS
	if not c.has("unlocked"): c["unlocked"] = false
	if not c.has("unlocked_at"): c["unlocked_at"] = ""
	if not c.has("last_completed_date"): c["last_completed_date"] = ""
	if not c.has("history"): c["history"] = {}
	if not c.has("today_checklist"):
		var cl: Dictionary = {}
		for item in CHALLENGE_ITEMS:
			cl[item] = false
		c["today_checklist"] = cl

	var stored_today: String = str(c.get("today_date", ""))
	if stored_today != today:
		# Проверка смены дня и стрика
		var last_date: String = str(c.get("last_completed_date", ""))
		if not last_date.is_empty():
			var diff := days_between(last_date, today)
			if diff > 1:
				# Был пропущен как минимум один полный день — стрик сбивается
				c["current_streak"] = 0
		else:
			c["current_streak"] = 0

		# Инициализация чек-листа нового дня
		var history: Dictionary = c.get("history", {})
		if history.has(today):
			var rec: Dictionary = history[today]
			c["today_checklist"] = rec.get("items", {}).duplicate(true)
		else:
			var cl: Dictionary = {}
			for item in CHALLENGE_ITEMS:
				cl[item] = false
			c["today_checklist"] = cl
		c["today_date"] = today

	rituals[CHALLENGE_ID] = c
	phase_c["rituals"] = rituals
	state["phase_c"] = phase_c
	return c

static func get_challenge_state(state: Dictionary) -> Dictionary:
	return ensure_challenge(state).duplicate(true)

static func toggle_challenge_item(state: Dictionary, item_key: String) -> Dictionary:
	var c := ensure_challenge(state)
	if not CHALLENGE_ITEMS.has(item_key):
		return {"ok": false, "reason": "unknown_item"}

	var today := Time.get_date_string_from_system()
	var cl: Dictionary = c.get("today_checklist", {})
	var current_val := bool(cl.get(item_key, false))
	cl[item_key] = not current_val
	c["today_checklist"] = cl

	# Проверяем, закрыты ли все 6 пунктов на сегодня
	var all_done := true
	for k in CHALLENGE_ITEMS:
		if not bool(cl.get(k, false)):
			all_done = false
			break

	var history: Dictionary = c.get("history", {})
	var last_date: String = str(c.get("last_completed_date", ""))
	var newly_unlocked := false
	var award: Dictionary = {}

	if all_done:
		if not history.has(today) or not bool(history[today].get("completed", false)):
			var diff := days_between(last_date, today)
			if diff == 1:
				c["current_streak"] = int(c.get("current_streak", 0)) + 1
			elif diff == 0:
				pass # уже был завершён сегодня
			else:
				c["current_streak"] = 1

			c["last_completed_date"] = today
			if int(c["current_streak"]) > int(c.get("max_streak", 0)):
				c["max_streak"] = c["current_streak"]

			history[today] = {
				"completed": true,
				"items": cl.duplicate(true),
				"completed_at": Time.get_datetime_string_from_system()
			}
			c["history"] = history

			if int(c["current_streak"]) >= int(c.get("target_days", CHALLENGE_TARGET_DAYS)) and not bool(c.get("unlocked", false)):
				c["unlocked"] = true
				c["unlocked_at"] = Time.get_datetime_string_from_system()
				newly_unlocked = true
				award = ProgressServiceScript.apply_award(
					state,
					"player_01",
					"ritual:maya_30_streak:unlock",
					"ritual:maya_30_streak",
					0,
					{},
					[CHALLENGE_UNLOCK_EFFECT, CHALLENGE_UNLOCK_LIGHT]
				)
	else:
		# Если сегодня было завершено, а теперь пункт снят
		if history.has(today) and bool(history[today].get("completed", false)):
			history.erase(today)
			c["history"] = history
			if last_date == today:
				c["current_streak"] = maxi(0, int(c.get("current_streak", 1)) - 1)
				c["last_completed_date"] = _find_previous_completed_date(history, today)

	var phase_c: Dictionary = state.get("phase_c", {})
	var rituals: Dictionary = phase_c.get("rituals", {})
	rituals[CHALLENGE_ID] = c
	phase_c["rituals"] = rituals
	state["phase_c"] = phase_c

	return {
		"ok": true,
		"today_checklist": cl,
		"current_streak": c.get("current_streak", 0),
		"max_streak": c.get("max_streak", 0),
		"unlocked": bool(c.get("unlocked", false)),
		"newly_unlocked": newly_unlocked,
		"all_done_today": all_done,
		"award": award
	}

static func _find_previous_completed_date(history: Dictionary, before_date: String) -> String:
	var best := ""
	for d in history.keys():
		var ds := str(d)
		if ds < before_date and bool(history[d].get("completed", false)):
			if best.is_empty() or ds > best:
				best = ds
	return best

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
