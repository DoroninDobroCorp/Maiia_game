class_name Chapter2Service
extends RefCounted

## Правила миссий главы 2 (Тео, Бруно, Нора). Данные и тексты — Chapter2Guide.
## Состояние: `phase_c.chapter2[mission_id]` = {steps, drafts, pitched, completed, finale_seen},
## плюс `phase_c.chapter2._chapter` = {finale_seen}. Шаги идут по порядку; никаких наград XP.
const Guide = preload("res://scripts/presentation/chapter2_guide.gd")
const Ritual = preload("res://scripts/services/ritual_service.gd")
const ProgressServiceScript = preload("res://scripts/services/progress_service.gd")

const CHAPTER_KEY := "_chapter"

static func ids() -> Array:
	return Guide.IDS

static func _read(state: Dictionary, mid: String) -> Dictionary:
	return state.get("phase_c", {}).get("chapter2", {}).get(mid, {})

static func _write(state: Dictionary, mid: String, rec: Dictionary) -> void:
	var phase_c: Dictionary = state.get("phase_c", {})
	var root: Dictionary = phase_c.get("chapter2", {})
	root[mid] = rec
	phase_c["chapter2"] = root
	state["phase_c"] = phase_c

static func _quest_completed(state: Dictionary, quest_id: String) -> bool:
	for instance in state.get("phase_b", {}).get("quest_instances", {}).values():
		if str(instance.get("quest_id", "")) == quest_id and str(instance.get("profile_id", "player_01")) == "player_01" and str(instance.get("status", "")) == "COMPLETED":
			return true
	return false

## Миссия открывается, когда закончена первая миссия этого героя.
static func unlocked(state: Dictionary, mid: String) -> bool:
	var rule := str(Guide.mission(mid).get("unlock", ""))
	if rule == "challenge":
		return bool(state.get("phase_c", {}).get("rituals", {}).get(Ritual.CHALLENGE_ID, {}).get("unlocked", false))
	return not rule.is_empty() and _quest_completed(state, rule)

static func any_unlocked(state: Dictionary) -> bool:
	for mid in Guide.IDS:
		if unlocked(state, mid):
			return true
	return false

## Сводка по миссии: шаги со статусами DONE / CURRENT / LOCKED и записанные данные.
static func mission_state(state: Dictionary, mid: String) -> Dictionary:
	var def := Guide.mission(mid)
	var rec := _read(state, mid)
	var done_steps: Dictionary = rec.get("steps", {})
	var rows: Array[Dictionary] = []
	var current_seen := false
	var done := 0
	for step in def.get("steps", []):
		var sid := str(step.id)
		var status := "DONE"
		if not done_steps.has(sid):
			status = "LOCKED" if current_seen else "CURRENT"
			current_seen = true
		else:
			done += 1
		rows.append({"id": sid, "status": status, "record": done_steps.get(sid, {})})
	return {"steps": rows, "done": done, "total": rows.size(), "completed": bool(rec.get("completed", false)),
		"pitched": bool(rec.get("pitched", false)), "finale_seen": bool(rec.get("finale_seen", false)),
		"drafts": rec.get("drafts", {}).duplicate(true)}

static func current_step_id(state: Dictionary, mid: String) -> String:
	for row in mission_state(state, mid).steps:
		if str(row.status) == "CURRENT":
			return str(row.id)
	return ""

## Сохраняет черновик шага (фото). Пока шаг не сдан, фото можно заменить.
static func set_draft(state: Dictionary, mid: String, sid: String, patch: Dictionary) -> Dictionary:
	if bool(state.get("read_only", false)):
		return {"ok": false, "reason": "read_only"}
	if Guide.step_def(mid, sid).is_empty():
		return {"ok": false, "reason": "unknown_step"}
	var rec := _read(state, mid).duplicate(true)
	var drafts: Dictionary = rec.get("drafts", {})
	var draft: Dictionary = drafts.get(sid, {})
	draft.merge(patch, true)
	drafts[sid] = draft
	rec["drafts"] = drafts
	_write(state, mid, rec)
	return {"ok": true}

## Путь к сохранённому фото шага (черновик или сданный шаг) или "".
static func photo_path(state: Dictionary, mid: String, sid: String) -> String:
	var rec := _read(state, mid)
	var artifact_id := str(rec.get("steps", {}).get(sid, {}).get("artifact_id", rec.get("drafts", {}).get(sid, {}).get("artifact_id", "")))
	if artifact_id.is_empty():
		return ""
	return preload("res://scripts/services/artifact_service.gd").media_path_for(state, artifact_id)

## Неверные пункты теста: индексы предложений и признак неверного правила.
static func check_quiz(step: Dictionary, answers: Array, rule_choice: int) -> Dictionary:
	var quiz: Dictionary = step.get("quiz", {})
	var items: Array = quiz.get("items", [])
	var wrong: Array[int] = []
	for i in range(items.size()):
		var given := str(answers[i]) if i < answers.size() else ""
		if given != str(items[i].answer):
			wrong.append(i)
	var rule_ok := rule_choice == int(quiz.get("rule", {}).get("answer", 0))
	return {"wrong_items": wrong, "rule_ok": rule_ok, "ok": wrong.is_empty() and rule_ok}

## Сдать текущий шаг. data: {fields:{id:text}, answers:[…], rule_choice:int}; adult: взрослый рядом.
static func complete_step(state: Dictionary, mid: String, sid: String, data: Dictionary, adult: bool) -> Dictionary:
	if bool(state.get("read_only", false)):
		return {"ok": false, "reason": "read_only"}
	var step := Guide.step_def(mid, sid)
	if step.is_empty() or not unlocked(state, mid):
		return {"ok": false, "reason": "locked", "message": "Эта миссия пока закрыта."}
	var summary := mission_state(state, mid)
	for row in summary.steps:
		if str(row.id) == sid and str(row.status) == "DONE":
			return {"ok": true, "applied": false, "completed": bool(summary.completed)}
	if current_step_id(state, mid) != sid:
		return {"ok": false, "reason": "not_current", "message": "Сначала нужно закончить предыдущий шаг."}
	if bool(step.get("adult", false)) and not adult:
		return {"ok": false, "reason": "adult_required", "message": "На этом шаге нужен взрослый рядом. Отметь, что он был с тобой."}
	var values: Dictionary = {}
	for field in step.get("fields", []):
		var fid := str(field.id)
		var text := str(data.get("fields", {}).get(fid, "")).strip_edges()
		if bool(field.get("required", false)) and text.is_empty():
			return {"ok": false, "reason": "field_required", "field": fid, "message": "Заполни поле: %s." % str(field.label)}
		if bool(field.get("numeric", false)) and not text.is_empty():
			var number := text.replace(",", ".")
			if not number.is_valid_float() or float(number) <= 0.0 or float(number) > 100000.0:
				return {"ok": false, "reason": "bad_number", "field": fid, "message": "В поле «%s» нужно число больше нуля." % str(field.label)}
			text = number
		if str(step.kind) == "text" and fid == "reply" and text.split(" ", false).size() < 2:
			return {"ok": false, "reason": "too_short", "field": fid, "message": "Напиши хотя бы два слова: маяк ждёт ответа."}
		values[fid] = text.left(500)
	var record := {"done_at": Time.get_datetime_string_from_system(), "fields": values, "adult": adult}
	if str(step.kind) == "quiz":
		var checked := check_quiz(step, data.get("answers", []), int(data.get("rule_choice", -1)))
		if not bool(checked.ok):
			return {"ok": false, "reason": "quiz_incorrect", "wrong_items": checked.wrong_items, "rule_ok": checked.rule_ok,
				"message": "Почти! Посмотри на отмеченные предложения и правило: радио любит перепроверять."}
		record["answers"] = data.get("answers", [])
	var photo_mode := str(step.get("photo", ""))
	var draft_artifact := str(_read(state, mid).get("drafts", {}).get(sid, {}).get("artifact_id", ""))
	if photo_mode == "required" and draft_artifact.is_empty():
		return {"ok": false, "reason": "photo_required", "message": "Приложи фото: Клара, Тео и Бруно любят доказательства."}
	if not draft_artifact.is_empty():
		record["artifact_id"] = draft_artifact
	var rec := _read(state, mid).duplicate(true)
	var steps: Dictionary = rec.get("steps", {})
	steps[sid] = record
	rec["steps"] = steps
	var finished: bool = steps.size() >= (Guide.mission(mid).get("steps", []) as Array).size()
	if finished:
		rec["completed"] = true
		rec["completed_at"] = Time.get_datetime_string_from_system()
	_write(state, mid, rec)
	return {"ok": true, "applied": true, "completed": finished, "message": str(step.get("done", "Шаг отмечен.")), "reaction": str(step.get("done", ""))}

# ---------------------------------------------------------------- сцены и финалы

static func chapter_done(state: Dictionary) -> bool:
	for mid in Guide.IDS:
		if not bool(mission_state(state, mid).completed):
			return false
	return bool(Ritual.school_state(state).completed)

## Следующая сцена, которую пора показать: питч, финал миссии или финал главы.
## {} — ничего не нужно. kind: "pitch" | "finale" | "chapter".
static func next_scene(state: Dictionary) -> Dictionary:
	for mid in Guide.IDS:
		if not unlocked(state, mid):
			continue
		var info := mission_state(state, mid)
		if not bool(info.pitched):
			return {"kind": "pitch", "mid": mid, "key": str(Guide.mission(mid).pitch_key)}
	for mid in Guide.IDS:
		var info := mission_state(state, mid)
		if bool(info.completed) and not bool(info.finale_seen):
			return {"kind": "finale", "mid": mid, "key": str(Guide.mission(mid).finale_key)}
	if chapter_done(state) and not bool(_read(state, CHAPTER_KEY).get("finale_seen", false)):
		return {"kind": "chapter", "mid": CHAPTER_KEY, "key": "ch2_chapter"}
	return {}

static func mark_scene(state: Dictionary, scene: Dictionary) -> void:
	var mid := str(scene.get("mid", ""))
	if mid.is_empty():
		return
	var rec := _read(state, mid).duplicate(true)
	rec["pitched" if str(scene.get("kind", "")) == "pitch" else "finale_seen"] = true
	_write(state, mid, rec)

## Всё, что нужно станции: фото маячка, шаги, части шифра, огонёк в окне.
static func station_view(state: Dictionary) -> Dictionary:
	var teo := mission_state(state, "teo2")
	var bruno := mission_state(state, "bruno2")
	var nora := mission_state(state, "nora2")
	var parts: Array = []
	var steps: Array = Guide.mission("nora2").get("steps", [])
	for row in nora.steps:
		if str(row.status) != "DONE":
			continue
		for step in steps:
			if str(step.id) == str(row.id) and step.has("quiz"):
				parts.append(step.quiz.reveal)
	return {
		"teo_visible": bool(teo.pitched) or int(teo.done) > 0,
		"teo_model": int(teo.done) >= 5,
		"teo_lit": bool(teo.completed),
		"teo_photo": photo_path(state, "teo2", "t_carve"),
		"bruno_done": int(bruno.done),
		"bruno_total": int(bruno.total),
		"nora_lamps": mini(parts.size(), 6),
		"nora_parts": parts,
		"chapter_done": chapter_done(state),
	}
