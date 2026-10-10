class_name MissionPage
extends Control

## One screen that answers "what is this mission, what do I do, what will I get".
## Opened the first time a mission object is used, and later from the journal or
## from the "Карта миссии" button inside a step. Read-only projection of state.
## Context (via _adventure_ui): quest, instance_id.
const UI = preload("res://scripts/presentation/adventure_ui.gd")
const Art = preload("res://scripts/presentation/adventure_art.gd")
const Guide = preload("res://scripts/presentation/mission_guide.gd")
signal closed
signal command_requested(operation: String, payload: Dictionary)
signal episode_requested(instance_id: String, stage_id: String)
signal collection_requested
signal weather_requested
signal secret_requested(secret_id: String)
signal hub_requested
signal water_photos_requested

var state: Dictionary = {}
var audio_service: Node
var quest: Dictionary = {}
var instance_id := ""
var feedback: Label
var voiced := false

func setup(game_state: Dictionary, audio_svc: Node = null) -> void:
	state = game_state.duplicate(true)
	audio_service = audio_svc
	var ctx := UI.context(state)
	instance_id = str(ctx.get("instance_id", ""))
	var instance := UI.instance_for(state, instance_id)
	quest = ctx.get("quest", UI.quest_for(instance))
	if instance_id.is_empty():
		instance_id = str(UI.instance_for(state, str(quest.get("quest_id", ""))).get("instance_id", ""))
	_build()

func show_result(result: Dictionary) -> void:
	if feedback == null:
		return
	feedback.text = UI.result_text(result)
	feedback.visible = true

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		closed.emit()

func _stage_status(stage: Dictionary) -> String:
	return str(UI.stage_progress(state, instance_id, str(stage.get("stage_id", ""))).get("status", "AVAILABLE"))

func _next_stage(stages: Array) -> Dictionary:
	for stage in stages:
		if _stage_status(stage) in ["AVAILABLE", "IN_PROGRESS", "AWAITING_REVIEW"]:
			return stage
	return {}

func _completed_count(stages: Array) -> int:
	var count := 0
	for stage in stages:
		if _stage_status(stage) == "COMPLETED":
			count += 1
	return count

func _build() -> void:
	var qid := str(quest.get("quest_id", ""))
	var guide := Guide.mission(qid)
	var instance := UI.instance_for(state, instance_id)
	var stages: Array = UI.stages(quest)
	var done := _completed_count(stages)
	var finished := not stages.is_empty() and done >= stages.size()
	var subtitle := str(guide.get("speaker", "")) + (" · " + str(guide.get("role", "")) if not str(guide.get("role", "")).is_empty() else "")
	var s := UI.shell(self, state, str(quest.get("story_title", quest.get("title", "Миссия"))), subtitle, func(): closed.emit(), true)
	feedback = s.feedback
	var content: VBoxContainer = s.content
	if stages.is_empty():
		UI.label("У этой истории пока нет шагов.", content)
		return
	var sc := UI.scroll(content)
	var columns := UI.row(sc)
	columns.add_theme_constant_override("separation", 18)
	var left := UI.column(columns)
	left.size_flags_stretch_ratio = 1.0
	var right := UI.column(columns)
	right.size_flags_stretch_ratio = 1.15

	_build_story(left, guide, finished)
	_build_path(right, stages, done, finished)

	var footer := UI.row(content)
	_build_actions(footer, guide, instance, stages, finished)
	var primary := footer.find_child("MissionPrimaryAction", true, false) as Control
	UI.focus_later(primary if primary != null else s.close, self)

func _build_story(parent: Node, guide: Dictionary, finished: bool) -> void:
	var card := UI.card(parent)
	var head := UI.row(card)
	head.add_theme_constant_override("separation", 14)
	var persona := str(guide.get("persona", ""))
	var portrait_path := Guide.portrait_path(persona, "happy" if finished else "neutral")
	if not voiced:
		voiced = true
		UI.voice(audio_service, persona, "happy" if finished else "greet")
	if not portrait_path.is_empty():
		UI.portrait(portrait_path, 150, head)
	else:
		var art := Art.new()
		art.kind = str(guide.get("portrait_art", quest.get("quest_id", "")))
		art.custom_minimum_size = Vector2(64, 64)
		head.add_child(art)
	var who := UI.column(head)
	who.alignment = BoxContainer.ALIGNMENT_CENTER
	UI.label(str(guide.get("speaker", "")), who, 22, UI.BRASS)
	var hero := Guide.character(persona)
	if not hero.is_empty():
		UI.label(str(hero.get("role", "")), who, 14, UI.TEAL)
		UI.label("«" + str(hero.get("tagline", "")) + "»", who, 14, UI.MUTED)
	UI.label(("Миссия выполнена" if finished else "Предмет на столе: " + str(guide.get("object", ""))), who, 13, UI.MUTED)
	if finished:
		UI.label(str(guide.get("done_title", "Готово")), card, 20, UI.BRASS)
		UI.label(str(guide.get("done_text", "")), card, 16)
		if not str(guide.get("postscript", "")).is_empty():
			UI.label("«" + str(guide.get("postscript", "")) + "»", card, 15, UI.TEAL)
	elif str(quest.get("quest_id", "")) == "FG08" and bool(state.get("adventures", {}).get("progress", {}).get(instance_id, {}).get("water_photos_submitted", false)):
		UI.label("«Снимки реки и водопада переданы Кларе! Клара проявляет плёнку в тёмной комнате редакции газеты Эль-Больсона. Новых миссий пока нет — героиня появится на станции позже!»", card, 16, UI.TEAL)
	else:
		UI.label("«" + str(guide.get("hook", quest.get("summary", ""))) + "»", card, 16)
	var goal := UI.card(parent)
	UI.label("ЦЕЛЬ", goal, 12, UI.TEAL)
	UI.label(str(guide.get("goal", quest.get("summary", ""))), goal, 18)
	for pair in [["ЧТО ПОЯВИТСЯ НА СТАНЦИИ", "payoff"], ["СКОЛЬКО ВРЕМЕНИ", "rhythm"], ["ЧТО ПОНАДОБИТСЯ", "needs"]]:
		var text := str(guide.get(pair[1], ""))
		if text.is_empty():
			continue
		UI.label(str(pair[0]), goal, 12, UI.TEAL)
		UI.label(text, goal, 14, UI.MUTED)

func _build_path(parent: Node, stages: Array, done: int, finished: bool) -> void:
	var header := UI.row(parent)
	UI.label("ПУТЬ · %d из %d шагов" % [done, stages.size()], header, 14, UI.BRASS)
	var bar := ProgressBar.new()
	bar.max_value = stages.size()
	bar.value = done
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(120, 10)
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(bar)
	var current := _next_stage(stages)
	for i in range(stages.size()):
		_step_row(parent, i + 1, stages[i], str(stages[i].get("stage_id", "")) == str(current.get("stage_id", "")) and not finished)

func _step_row(parent: Node, number: int, stage: Dictionary, is_current: bool) -> void:
	var sid := str(stage.get("stage_id", ""))
	var status := _stage_status(stage)
	var info := Guide.step(sid)
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var fill := Color("233843") if is_current else UI.PANEL
	var border := UI.BRASS if is_current else Color("4b5457")
	panel.add_theme_stylebox_override("panel", UI.style(fill, border, 12))
	parent.add_child(panel)
	var line := UI.row(panel)
	var badge := Label.new()
	badge.text = "✓" if status == "COMPLETED" else str(number)
	badge.custom_minimum_size = Vector2(30, 30)
	badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	badge.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	badge.add_theme_font_size_override("font_size", 20)
	badge.add_theme_color_override("font_color", UI.TEAL if status == "COMPLETED" else UI.BRASS if is_current else UI.MUTED)
	line.add_child(badge)
	var text := UI.column(line)
	var dim := status == "LOCKED"
	UI.label(str(info.get("title", stage.get("title", ""))), text, 17, UI.MUTED if dim else UI.PAPER)
	UI.label(str(info.get("task", stage.get("summary", ""))), text, 13, UI.MUTED)
	var meta: Array[String] = []
	var where := Guide.where_text(info)
	if not where.is_empty():
		meta.append(where)
	if not str(info.get("time", "")).is_empty():
		meta.append(str(info.time))
	if not str(info.get("reward", "")).is_empty():
		meta.append("после шага: " + str(info.reward))
	if not meta.is_empty():
		UI.label(" · ".join(PackedStringArray(meta)), text, 12, UI.TEAL)
	if status == "AWAITING_REVIEW":
		UI.label("Осталось проверить и отметить", text, 12, UI.BRASS)

func _build_actions(footer: Control, guide: Dictionary, instance: Dictionary, stages: Array, finished: bool) -> void:
	var qid := str(quest.get("quest_id", ""))
	var paused := str(instance.get("status", "")) == "PAUSED"
	var held := bool(instance.get("safety_hold", false))
	UI.button("Все миссии", footer, func(): hub_requested.emit())
	var space := Control.new()
	space.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(space)
	if finished:
		if qid == "FG01":
			UI.button("Отметки на шкале", footer, func(): secret_requested.emit("radio_reply"))
			UI.button("Погода Эль-Больсона", footer, func(): weather_requested.emit())
		var results := UI.button("Мои работы →", footer, func(): collection_requested.emit(), true)
		results.name = "MissionPrimaryAction"
		return
	if paused and not held:
		var resume := UI.button("Вернуться к миссии", footer, func(): command_requested.emit("resume_adventure", {"instance_id": instance_id}), true)
		resume.name = "MissionPrimaryAction"
		return
	if qid == "FG08":
		var inst_prog: Dictionary = state.get("adventures", {}).get("progress", {}).get(instance_id, {})
		var photos_submitted := bool(inst_prog.get("water_photos_submitted", false))
		if photos_submitted:
			UI.label("Снимки у Клары · героиня появится позже", footer, 13, UI.TEAL)
		UI.button("Загрузить фото реки и водопада 📷", footer, func(): water_photos_requested.emit())
	var next := _next_stage(stages)
	var started := _completed_count(stages) > 0 or str(UI.stage_progress(state, instance_id, str(next.get("stage_id", ""))).get("status", "")) == "IN_PROGRESS"
	var step_title := str(Guide.step(str(next.get("stage_id", ""))).get("title", next.get("title", "")))
	var label := ("Продолжить: " if started else "Начать: ") + step_title + " →"
	var go := UI.button(label, footer, func(): episode_requested.emit(instance_id, str(next.get("stage_id", ""))), true)
	go.name = "MissionPrimaryAction"
	go.disabled = next.is_empty() or held
	if next.is_empty():
		go.text = "Сейчас нет доступного шага"
