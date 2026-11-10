class_name StoryService
extends RefCounted

## Прохождение сюжетных серий (StoryGuide). Состояние: `phase_c.story[серия]` =
## {scenes: {id_сцены: {choice, reply: {id: текст}, done_at}}, finished_at}.
## Ничего не проверяется на «правильно»: Майя читает, выбирает и отвечает как хочет.
## Серия идёт свободно, подтверждение взрослого не открывает и не закрывает сцены.
const Guide = preload("res://scripts/presentation/story_guide.gd")

static func _record(state: Dictionary, series_id: String) -> Dictionary:
	return state.get("phase_c", {}).get("story", {}).get(series_id, {})

static func _write(state: Dictionary, series_id: String, record: Dictionary) -> void:
	var phase_c: Dictionary = state.get("phase_c", {})
	var story: Dictionary = phase_c.get("story", {})
	story[series_id] = record
	phase_c["story"] = story
	state["phase_c"] = phase_c

static func scene_done(state: Dictionary, series_id: String, scene_id: String) -> bool:
	return _record(state, series_id).get("scenes", {}).has(scene_id)

static func next_scene(state: Dictionary, series_id: String) -> Dictionary:
	for scene in Guide.scenes(series_id):
		if not scene_done(state, series_id, str(scene.id)):
			return scene
	return {}

## Токены текста: value выбранного варианта и ответы Майи по их id.
static func tokens(state: Dictionary, series_id: String) -> Dictionary:
	var result: Dictionary = {}
	var done: Dictionary = _record(state, series_id).get("scenes", {})
	for scene in Guide.scenes(series_id):
		var entry: Dictionary = done.get(str(scene.id), {})
		if entry.is_empty():
			continue
		var choice: Dictionary = scene.get("choice", {})
		if not choice.is_empty():
			for option in choice.options:
				if str(option.id) == str(entry.get("choice", "")):
					result[str(choice.id)] = str(option.value)
		for reply in scene.get("replies", []):
			var text := str(entry.get("reply", {}).get(str(reply.id), "")).strip_edges()
			if not text.is_empty():
				result[str(reply.id)] = text
	return result

static func text_for(state: Dictionary, series_id: String, text: String) -> String:
	return Guide.render(text, series_id, tokens(state, series_id))

## Сводка: сцены и главы (сколько прослушано).
static func progress(state: Dictionary, series_id: String) -> Dictionary:
	var done := 0
	var total := 0
	var chapters: Array[Dictionary] = []
	for chapter in Guide.series(series_id).get("chapters", []):
		var chapter_done := 0
		for scene in chapter.scenes:
			total += 1
			if scene_done(state, series_id, str(scene.id)):
				done += 1
				chapter_done += 1
		chapters.append({"id": str(chapter.id), "title": str(chapter.title), "stage_id": str(chapter.get("stage_id", "")), "done": chapter_done, "total": chapter.scenes.size()})
	return {"done": done, "total": total, "chapters": chapters, "finished": total > 0 and done >= total}

static func finished(state: Dictionary, series_id: String) -> bool:
	return bool(progress(state, series_id).finished)

## Сцена отыграна: выбор (если он есть) обязателен, ответы обязательны только там, где так написано.
static func complete_scene(state: Dictionary, series_id: String, scene_id: String, choice_id: String, replies: Dictionary) -> Dictionary:
	if bool(state.get("read_only", false)):
		return {"ok": false, "reason": "read_only"}
	var scene := Guide.scene(series_id, scene_id)
	if scene.is_empty():
		return {"ok": false, "reason": "unknown_scene"}
	if scene_done(state, series_id, scene_id):
		return {"ok": true, "applied": false}
	var next := next_scene(state, series_id)
	if str(next.get("id", "")) != scene_id:
		return {"ok": false, "reason": "not_current", "message": "Сначала нужно дослушать предыдущее письмо."}
	var choice: Dictionary = scene.get("choice", {})
	var reaction := ""
	if not choice.is_empty():
		var found := false
		for option in choice.options:
			if str(option.id) == choice_id:
				found = true
				reaction = str(option.reaction)
		if not found:
			return {"ok": false, "reason": "choice_required", "message": "Выбери вариант: от него зависит продолжение."}
	var saved_replies: Dictionary = {}
	for reply in scene.get("replies", []):
		var text := str(replies.get(str(reply.id), "")).strip_edges().left(400)
		if bool(reply.get("required", false)) and text.is_empty():
			return {"ok": false, "reason": "reply_required", "field": str(reply.id), "message": "Напиши хотя бы слово: это твоя передача."}
		saved_replies[str(reply.id)] = text
	var record := _record(state, series_id).duplicate(true)
	var scenes: Dictionary = record.get("scenes", {})
	scenes[scene_id] = {"choice": choice_id, "reply": saved_replies, "done_at": Time.get_datetime_string_from_system()}
	record["scenes"] = scenes
	var summary := progress({"phase_c": {"story": {series_id: record}}}, series_id)
	var chapter_done := false
	for chapter in summary.chapters:
		if str(chapter.id) == str(scene.chapter_id) and int(chapter.done) == int(chapter.total):
			chapter_done = true
	if bool(summary.finished):
		record["finished_at"] = Time.get_datetime_string_from_system()
	_write(state, series_id, record)
	return {"ok": true, "applied": true, "reaction": reaction, "chapter_done": chapter_done, "finished": bool(summary.finished)}

## Журнал эфира: все выборы и ответы Майи по порядку (для перечитывания и для архива).
static func journal(state: Dictionary, series_id: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var done: Dictionary = _record(state, series_id).get("scenes", {})
	for scene in Guide.scenes(series_id):
		var entry: Dictionary = done.get(str(scene.id), {})
		if entry.is_empty():
			continue
		var choice_text := ""
		for option in scene.get("choice", {}).get("options", []):
			if str(option.id) == str(entry.get("choice", "")):
				choice_text = str(option.text)
		var replies: Array[String] = []
		for reply in scene.get("replies", []):
			var text := str(entry.get("reply", {}).get(str(reply.id), "")).strip_edges()
			if not text.is_empty():
				replies.append(text)
		result.append({"scene_id": str(scene.id), "title": str(scene.title), "who": str(scene.who), "choice": choice_text, "replies": replies})
	return result
