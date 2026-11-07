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
## Сколько последних дней можно вспомнить задним числом.
const BACKFILL_WINDOW_DAYS := 35
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
	if bool(state.get("read_only", false)):
		return state.get("phase_c", {}).get("rituals", {}).get(CHALLENGE_ID, {}).duplicate(true)
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

	if not c.has("has_alarm_clock"):
		c["has_alarm_clock"] = int(c.get("max_streak", 0)) >= 3 or c.get("history", {}).size() >= 2 or bool(c.get("alarm_clock", false))

	var stored_today: String = str(c.get("today_date", ""))
	if stored_today != today:
		# Проверка смены дня и стрика
		var last_date: String = str(c.get("last_completed_date", ""))
		if not last_date.is_empty():
			var diff := days_between(last_date, today)
			if diff > 1:
				# Был пропущен как минимум один полный день — стрик сбивается
				if int(c.get("current_streak", 0)) >= 3 or int(c.get("max_streak", 0)) >= 3 or c.get("history", {}).size() >= 2:
					c["has_alarm_clock"] = true
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

			if int(c["max_streak"]) >= 3 or c.get("history", {}).size() >= 2:
				c["has_alarm_clock"] = true

			history[today] = {
				"completed": true,
				"items": cl.duplicate(true),
				"completed_at": Time.get_datetime_string_from_system()
			}
			c["history"] = history

			if int(c["current_streak"]) >= int(c.get("target_days", CHALLENGE_TARGET_DAYS)) and not bool(c.get("unlocked", false)):
				award = _unlock_challenge(state, c)
				newly_unlocked = true
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
		"has_alarm_clock": bool(c.get("has_alarm_clock", false)),
		"award": award
	}

## Выдаёт награду челленджа один раз: доска почёта, Вечный Огонь, жетон «30 DÍAS».
static func _unlock_challenge(state: Dictionary, c: Dictionary) -> Dictionary:
	c["unlocked"] = true
	c["unlocked_at"] = Time.get_datetime_string_from_system()
	return ProgressServiceScript.apply_award(
		state,
		"player_01",
		"ritual:maya_30_streak:unlock",
		"ritual:maya_30_streak",
		0,
		{},
		[CHALLENGE_UNLOCK_EFFECT, CHALLENGE_UNLOCK_LIGHT]
	)

## Календарная дата на `offset` дней раньше/позже `date_string` (YYYY-MM-DD).
static func shift_date(date_string: String, offset: int) -> String:
	if not _is_valid_date_format(date_string.strip_edges()):
		return ""
	var unix := Time.get_unix_time_from_datetime_string(date_string.strip_edges().left(10) + "T00:00:00")
	return Time.get_date_string_from_unix_time(int(unix) + offset * 86400)

## Дни, которые можно отметить задним числом: от самого раннего до вчерашнего.
## Окно — последние BACKFILL_WINDOW_DAYS дней; сегодняшний день отмечается обычным чек-листом.
static func backfill_dates(today: String = "") -> Array[String]:
	var now := today if not today.is_empty() else Time.get_date_string_from_system()
	var result: Array[String] = []
	for back in range(BACKFILL_WINDOW_DAYS, 0, -1):
		var d := shift_date(now, -back)
		if not d.is_empty():
			result.append(d)
	return result

## Взрослый и Майя вместе вспомнили: в этот день все шесть дел были сделаны.
## Такой день записывается с пометкой `backfilled`; отмечать можно только прошедшие дни,
## а убрать можно только ту отметку, которую поставили задним числом.
## Серия и рекорд всегда пересчитываются по истории, правило «пропуск обнуляет серию» не меняется.
static func set_past_day(state: Dictionary, date_string: String, done: bool) -> Dictionary:
	if bool(state.get("read_only", false)):
		return {"ok": false, "reason": "read_only"}
	var date := date_string.strip_edges()
	var today := Time.get_date_string_from_system()
	var age := days_between(date, today)
	if not _is_valid_date_format(date) or age < 1 or age > BACKFILL_WINDOW_DAYS:
		return {"ok": false, "reason": "date_out_of_range"}
	var c := ensure_challenge(state)
	var history: Dictionary = c.get("history", {})
	if done:
		if not history.has(date) or not bool(history[date].get("completed", false)):
			var items: Dictionary = {}
			for item in CHALLENGE_ITEMS:
				items[item] = true
			history[date] = {"completed": true, "items": items, "completed_at": Time.get_datetime_string_from_system(), "backfilled": true}
	elif history.has(date):
		if not bool(history[date].get("backfilled", false)):
			return {"ok": false, "reason": "logged_on_the_day"}
		history.erase(date)
	c["history"] = history
	var runs := _recompute_streaks(c, today)
	if int(runs.max_run) >= 3 or history.size() >= 2:
		c["has_alarm_clock"] = true
	var newly_unlocked := false
	var award: Dictionary = {}
	if int(runs.max_run) >= int(c.get("target_days", CHALLENGE_TARGET_DAYS)) and not bool(c.get("unlocked", false)):
		award = _unlock_challenge(state, c)
		newly_unlocked = true
	var phase_c: Dictionary = state.get("phase_c", {})
	var rituals: Dictionary = phase_c.get("rituals", {})
	rituals[CHALLENGE_ID] = c
	phase_c["rituals"] = rituals
	state["phase_c"] = phase_c
	return {
		"ok": true,
		"date": date,
		"done": done,
		"current_streak": c.get("current_streak", 0),
		"max_streak": c.get("max_streak", 0),
		"unlocked": bool(c.get("unlocked", false)),
		"newly_unlocked": newly_unlocked,
		"award": award
	}

## Пересчёт по истории: самая длинная серия подряд и текущая (она жива, только если
## последний закрытый день — сегодня или вчера).
static func _recompute_streaks(c: Dictionary, today: String) -> Dictionary:
	var days: Array[String] = []
	for d in c.get("history", {}).keys():
		if bool(c.history[d].get("completed", false)):
			days.append(str(d))
	days.sort()
	var max_run := 0
	var run := 0
	var previous := ""
	for d in days:
		run = run + 1 if not previous.is_empty() and days_between(previous, d) == 1 else 1
		max_run = maxi(max_run, run)
		previous = d
	var last: String = "" if days.is_empty() else days.back()
	c["last_completed_date"] = last
	c["max_streak"] = max_run
	c["current_streak"] = run if not last.is_empty() and days_between(last, today) <= 1 else 0
	return {"max_run": max_run, "run": run}

static func gift_alarm_clock(state: Dictionary) -> Dictionary:
	var c := ensure_challenge(state)
	c["has_alarm_clock"] = true
	var phase_c: Dictionary = state.get("phase_c", {})
	var rituals: Dictionary = phase_c.get("rituals", {})
	rituals[CHALLENGE_ID] = c
	phase_c["rituals"] = rituals
	state["phase_c"] = phase_c
	return c

static func has_alarm_clock(state: Dictionary) -> bool:
	return bool(state.get("phase_c", {}).get("rituals", {}).get(CHALLENGE_ID, {}).get("has_alarm_clock", false))

static func _find_previous_completed_date(history: Dictionary, before_date: String) -> String:
	var best := ""
	for d in history.keys():
		var ds := str(d)
		if ds < before_date and bool(history[d].get("completed", false)):
			if best.is_empty() or ds > best:
				best = ds
	return best

static func ensure(state: Dictionary) -> Dictionary:
	if bool(state.get("read_only", false)):
		return state.get("phase_c", {}).get("rituals", {}).get(MOVEMENT_RITUAL_ID, {}).duplicate(true)
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
