class_name AdventureEpisode
extends Control

## Public: setup(state,audio=null); open_episode(instance_id,stage_id); show_result(result).
## Drafts stay local until main acknowledges; failed commands never clear any input.
const UI = preload("res://scripts/presentation/adventure_ui.gd")
const Art = preload("res://scripts/presentation/adventure_art.gd")
const Guide = preload("res://scripts/presentation/mission_guide.gd")
const TYPES_SUPPORTED := ["inspect_reveal","match_cards","order_fragments","assemble_selection","scripted_dialogue","real_world_step","compare_observations","exhibit_composition"]
signal closed
signal command_requested(operation: String, payload: Dictionary)
signal episode_requested(instance_id: String, stage_id: String)
signal gallery_requested(room_id: String)
signal collection_requested
signal mission_requested(quest_id: String)
signal work_requested(work_id: String)

var state: Dictionary = {}
var audio_service: Node
var instance_id := ""
var stage_id := ""
var quest: Dictionary = {}
var stage: Dictionary = {}
var progress: Dictionary = {}
var draft: Dictionary = {}
var interactions: Array = []
var interaction_index := 0
var response: Dictionary = {}
var content: VBoxContainer
var area: VBoxContainer
var feedback: Label
var hint_label: Label
var hint_level := 0
var response_fields: Dictionary = {}
var note: TextEdit
var assistance: OptionButton
var current_dialogue := ""
var review_mode := false
var pending_operation := ""
var saved_draft := false
var close_after_save := false
var exit_destination := ""
var attest: CheckBox
var words_open := false
var successful_interactions: Dictionary = {}
var last_payload: Dictionary = {}
var choice_context: Dictionary = {}
var portrait_view: TextureRect
var persona_id := ""
var replay_interaction := false
var help_button: Button

func setup(game_state: Dictionary, audio_svc: Node = null) -> void:
	var restoring := draft.is_empty()
	var was_reviewing := review_mode
	state = game_state.duplicate(true)
	audio_service = audio_svc
	var ctx := UI.context(state)
	instance_id = str(ctx.get("instance_id", instance_id))
	stage_id = str(ctx.get("stage_id", stage_id))
	quest = ctx.get("quest", UI.quest_for(UI.instance_for(state,instance_id)))
	_resolve_stage()
	review_mode = str(progress.get("status", "")) == "AWAITING_REVIEW"
	if draft.is_empty():
		draft = progress.get("draft", {}).duplicate(true)
		# Attempts are already persisted even if the app closed before a draft save.
		if not draft.has("responses"): draft["responses"] = {}
		var recovered: Dictionary = {}
		for attempt in progress.get("attempts", []):
			var id := str(attempt.get("interaction_id", ""))
			recovered[id] = attempt.get("response", {}).duplicate(true)
		for id in recovered:
			if not draft.responses.has(id): draft.responses[id] = recovered[id]
		var resume_id := str(draft.get("interaction_id", ""))
		for i in range(interactions.size()):
			if str(interactions[i].interaction_id) == resume_id:
				interaction_index = i
				break
	if _returned_for_revision() and (restoring or was_reviewing): replay_interaction = true
	_build()

func open_episode(iid: String, sid: String) -> void:
	instance_id = iid
	stage_id = sid
	quest = UI.quest_for(UI.instance_for(state,iid))
	draft = {}
	_resolve_stage()
	draft = progress.get("draft", {}).duplicate(true)
	_build()

func _resolve_stage() -> void:
	stage = {}
	var stage_list: Array = UI.stages(quest)
	if ResourceLoader.exists("res://scripts/services/adventure_service.gd") and not instance_id.is_empty():
		var svc = load("res://scripts/services/adventure_service.gd")
		if svc != null and svc.has_method("choice_context"):
			choice_context = svc.choice_context(state,instance_id)
		if svc != null and svc.has_method("list_stages"):
			stage_list = svc.list_stages(state.duplicate(true),instance_id)
	for candidate in stage_list:
		if str(candidate.get("stage_id", "")) == stage_id or (stage_id.is_empty() and str(candidate.get("status", "AVAILABLE")) != "LOCKED"):
			stage = candidate
			stage_id = str(stage.get("stage_id", ""))
			break
	progress = UI.stage_progress(state,instance_id,stage_id)
	if stage.has("status"): progress = stage
	successful_interactions.clear()
	for attempt in progress.get("attempts", []):
		if bool(attempt.get("success",false)): successful_interactions[str(attempt.get("interaction_id", ""))] = true
	interactions = []
	var definitions: Dictionary = quest.get("adventure", {}).get("interactions", {})
	for id in stage.get("interaction_ids", []):
		if definitions.has(str(id)): interactions.append(definitions[str(id)])
	interaction_index = clampi(interaction_index,0,maxi(0,interactions.size()-1))

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()

func _close() -> void:
	_leave("close")

func _leave(destination: String) -> void:
	_capture()
	if not instance_id.is_empty() and not stage_id.is_empty() and not draft.is_empty() and str(progress.get("status", "")) not in ["COMPLETED","AWAITING_REVIEW","LOCKED"] and str(UI.instance_for(state,instance_id).get("status", "ACTIVE")) == "ACTIVE" and not bool(UI.instance_for(state,instance_id).get("safety_hold",false)):
		close_after_save = true
		exit_destination = destination
		pending_operation = "stage_draft"
		command_requested.emit("stage_draft",_payload({"draft":draft.duplicate(true)}))
		return
	_finish_leave(destination)

func _finish_leave(destination: String) -> void:
	if destination == "collection": collection_requested.emit()
	else: closed.emit()

func _payload(extra: Dictionary = {}) -> Dictionary:
	var p := {"instance_id":instance_id,"stage_id":stage_id}
	p.merge(extra,true)
	return p

func show_result(result: Dictionary) -> void:
	if feedback == null: return
	feedback.text = UI.result_text(result)
	feedback.visible = true
	if not bool(result.get("ok", false)) and pending_operation == "stage_draft":
		close_after_save = false
		exit_destination = ""
	if not bool(result.get("ok", false)) and pending_operation == "stage_attempt":
		var retry := find_child("EpisodePrimaryAction",true,false) as Button
		if retry != null:
			retry.disabled = false
			retry.text = "Повторить проверку"
	if bool(result.get("ok", false)):
		if result.has("lexemes") and state.get("adventures", {}).get("progress", {}).has(instance_id):
			state.adventures.progress[instance_id].lexemes = result.lexemes.duplicate(true)
		if close_after_save and pending_operation == "stage_draft":
			var destination := exit_destination
			close_after_save = false
			exit_destination = ""
			pending_operation = ""
			_finish_leave(destination)
			return
		if bool(result.get("needs_revision",false)):
			review_mode = false
			replay_interaction = true
		if pending_operation == "stage_draft": saved_draft = true
		if pending_operation == "stage_hint": feedback.visible = false
		if bool(result.get("awaiting_review", false)):
			progress["status"] = "AWAITING_REVIEW"
			review_mode = true
			_build()
			feedback.text = "Материал сохранён. Теперь можно посмотреть его вместе."
			feedback.visible = true
		elif pending_operation == "stage_attempt":
			if str(progress.get("status", "")) != "COMPLETED": progress["status"] = "IN_PROGRESS"
			feedback.text = str(result.get("message", "Попытка сохранена."))
			if bool(result.get("success",result.get("correct",false))):
				successful_interactions[str(_interaction().get("interaction_id", ""))] = true
				replay_interaction = false
				_capture()
				_build()
				feedback.visible = false
			elif result.has("success"):
				feedback.text = str(result.get("outcome", {}).get("hint", "Попробуем ещё раз. Кнопка помощи подскажет, на что обратить внимание."))
	pending_operation = ""

func _send(op: String, extra: Dictionary) -> void:
	_capture()
	pending_operation = op
	last_payload = extra.duplicate(true)
	if str(progress.get("status", "")) == "COMPLETED":
		if op == "stage_attempt":
			var rules = load("res://scripts/domain/adventure_rules.gd")
			var outcome: Dictionary = rules.check_interaction(_interaction(),extra.get("response", {}))
			show_result({"ok":true,"success":outcome.get("ok",false),"outcome":outcome,"message":"Повторная игра · без новых наград"})
		return
	command_requested.emit(op,_payload(extra))

func _current_envelope() -> Dictionary:
	var inter_id := str(_interaction().get("interaction_id", ""))
	for entry in quest.get("adventure", {}).get("envelopes", []):
		if entry.get("interaction_ids", []).has(inter_id):
			return entry
	return {}

## Who is speaking and what they say at this moment: the character's line for the
## step (or the current envelope's story in the radio mission), with the portrait.
func _build_story(parent: Node, guide: Dictionary, step: Dictionary, status: String) -> void:
	var speaker := str(guide.get("speaker", ""))
	var text := str(step.get("say", ""))
	var heading := speaker
	var envelope := _current_envelope()
	if status == "COMPLETED" and not str(step.get("done", "")).is_empty():
		text = str(step.done)
		envelope = {}
	if not envelope.is_empty():
		var place := Guide.envelope_position(quest, str(_interaction().get("interaction_id", "")))
		heading = "%s · конверт %d из %d · %s" % [speaker, place.x, place.y, str(envelope.get("title", ""))]
		text = str(envelope.get("story", text))
	if text.is_empty():
		# Family-made adventures have no guide text; keep their chosen-question line.
		if not str(choice_context.get("summary", "")).is_empty():
			UI.label(str(choice_context.summary), parent, 14, UI.TEAL)
		return
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", UI.style(UI.PANEL, Color("4b5457"), 10))
	parent.add_child(panel)
	var line := UI.row(panel)
	var expression := "happy" if status == "COMPLETED" or successful_interactions.has(str(_interaction().get("interaction_id", ""))) else "thinking" if hint_level > 0 else "neutral"
	var portrait_path := "res://assets/characters/%s_%s.svg" % [persona_id, expression]
	portrait_view = null
	if not persona_id.is_empty() and ResourceLoader.exists(portrait_path):
		var portrait := TextureRect.new()
		portrait_view = portrait
		portrait.texture = load(portrait_path)
		portrait.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.custom_minimum_size = Vector2(56, 56)
		portrait.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		line.add_child(portrait)
	elif not speaker.is_empty():
		var art := Art.new()
		art.kind = str(guide.get("portrait_art", quest.get("quest_id", "")))
		art.custom_minimum_size = Vector2(56, 56)
		art.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		line.add_child(art)
	var words := UI.column(line)
	if not heading.is_empty():
		UI.label(heading, words, 14, UI.BRASS)
	UI.label(text, words, 16)
	if not str(choice_context.get("summary", "")).is_empty():
		UI.label(str(choice_context.summary), words, 13, UI.TEAL)

func _build_progress(parent: Node, stage_list: Array, subtitle: String) -> void:
	var meta := UI.row(parent)
	var where := UI.label(subtitle,meta,14,UI.MUTED)
	where.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	where.autowrap_mode = TextServer.AUTOWRAP_OFF
	var done := 0
	for definition in stage_list:
		if str(UI.stage_progress(state, instance_id, str(definition.get("stage_id", ""))).get("status", "")) == "COMPLETED":
			done += 1
	var bar := ProgressBar.new()
	bar.max_value = maxi(1, stage_list.size())
	bar.value = done
	bar.show_percentage = false
	bar.custom_minimum_size = Vector2(140,8)
	bar.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar.tooltip_text = "Пройдено шагов: %d из %d" % [done, stage_list.size()]
	meta.add_child(bar)
	if str(quest.get("quest_id", "")) == "FG01":
		var album: Dictionary = state.get("adventures", {}).get("progress", {}).get(instance_id, {}).get("lexemes", {})
		var used := 0
		for word in album.values():
			if bool(word.get("used", false)) or str(word.get("status", "")) == "used": used += 1
		var counter := UI.label("Слов в альбоме: %d из 100 · применено в сценах: %d" % [album.size(), used],meta,13,UI.TEAL)
		counter.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

func _build() -> void:
	var qid := str(quest.get("quest_id", ""))
	var guide := Guide.mission(qid)
	var step := Guide.step(stage_id)
	var stage_list: Array = UI.stages(quest)
	var place := Guide.position(stage_list, stage_id)
	var story_title := str(quest.get("story_title", quest.get("title", "")))
	var subtitle := story_title + (" · шаг %d из %d" % [place.x, place.y] if place.x > 0 else "")
	var title := str(step.get("title", stage.get("title", "Эпизод приключения"))) if not stage.is_empty() else "Эпизод приключения"
	var s := UI.shell(self,state,title,"",_close,true)
	feedback = s.feedback
	content = s.content
	response_fields.clear()
	note = null
	assistance = null
	attest = null
	if stage.is_empty():
		UI.label("Эта история пока не может открыть следующий этап. Все миссии и их путь находятся в журнале.",content)
		return
	persona_id = str(guide.get("persona", ""))
	var status := str(progress.get("status", "AVAILABLE"))
	_build_progress(content,stage_list,subtitle)
	if status == "LOCKED":
		UI.label("Этот шаг откроется после предыдущих. Всё, что уже сделано, сохраняется.",content)
		if Guide.is_current(qid): UI.button("Карта миссии",content,func(): mission_requested.emit(qid))
		return
	var instance := UI.instance_for(state,instance_id)
	if str(instance.get("status", "")) == "PAUSED" or bool(instance.get("safety_hold",false)):
		UI.label("Эта история отложена. Материалы и сделанные шаги сохранены.",content)
		if not bool(instance.get("safety_hold",false)):
			UI.button("Продолжить историю",content,func(): command_requested.emit("resume_adventure",{"instance_id":instance_id}),true)
		else: UI.label("Выберем следующее продолжение вместе в семейной мастерской.",content,0,UI.MUTED)
		return
	var sc := UI.scroll(content)
	sc.add_theme_constant_override("separation",8)
	if review_mode or status == "AWAITING_REVIEW":
		_build_story(sc,guide,step,status)
		_build_review(sc)
		return
	_build_story(sc,guide,step,status)
	if _returned_for_revision():
		var revision := UI.card(sc)
		UI.label("Нужна доработка",revision,20,UI.BRASS)
		UI.label(str(progress.get("review_note", "")),revision)
		UI.label("Можно дописать одну деталь. Уже сделанное и предыдущие работы сохранены.",revision,14,UI.MUTED)
	if status == "COMPLETED":
		var work: Dictionary = state.get("collections", {}).get("works", {}).get(str(progress.get("work_id", "")), {})
		var memory := UI.card(sc)
		UI.label("В твоём архиве · " + str(work.get("title",stage.get("title", ""))),memory,21,UI.BRASS)
		UI.label("Этот шаг уже пройден. Его результат сохранён.",memory)
		if not work.is_empty():
			UI.button("Посмотреть мою работу →",memory,func(): work_requested.emit(str(work.work_id)),true)
	if not interactions.is_empty():
		if interactions.size() > 1:
			var chips := UI.row(sc)
			chips.add_theme_constant_override("separation",8)
			var caption := UI.label("Задания шага:",chips,13,UI.TEAL)
			caption.autowrap_mode = TextServer.AUTOWRAP_OFF
			caption.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
			caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			for i in range(interactions.size()):
				var index := i
				var done_scene := successful_interactions.has(str(interactions[i].get("interaction_id", "")))
				var chip := UI.button(("✓ " if done_scene else "") + str(i+1),chips,func(): _select_interaction(index),i == interaction_index)
				chip.custom_minimum_size = Vector2(46,30)
				chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
				chip.tooltip_text = str(interactions[i].get("title", "Задание"))
		area = UI.card(sc,false,14)
		_render_interaction()
		_build_words(sc)
	else:
		UI.label("У этапа нет игрового взаимодействия. Прочитай, что нужно сделать, и сохрани результат ниже.",sc)
	if str(stage.get("completion_policy", "")) == "self_attest":
		attest = CheckBox.new()
		attest.text = "Мой замысел готов: я выбрала героя и цель" if stage_id == "game_concept" else "Всё верно: я сделала эти шаги"
		attest.button_pressed = bool(draft.get("attested",false))
		sc.add_child(attest)
	if str(_interaction().get("type", "")) != "real_world_step":
		var details := UI.card(sc)
		UI.label("Шаг засчитывается, когда",details,16,UI.BRASS)
		if not str(step.get("task", "")).is_empty(): UI.label(str(step.task),details,14)
		for criterion in Guide.criteria(stage_id,"",stage.get("criteria", [])): UI.label("• " + str(criterion),details,14,UI.MUTED)
	UI.label("Заметка для себя (по желанию)",sc,13,UI.TEAL)
	note = UI.text_input(sc,"Что получилось или где продолжить…",str(draft.get("note", "")),85)
	UI.label("Как ты это делала?",sc,13,UI.TEAL)
	assistance = UI.option(sc,["Сама", "С подсказкой", "Сделали вместе"],int(draft.get("assistance_index",0)))
	var footer := UI.row(content)
	UI.button("Продолжить позже",footer,_close)
	help_button = UI.button("Подсказка · %d/3" % hint_level,footer,_hint)
	if Guide.is_current(qid): UI.button("Карта миссии",footer,func(): _capture(); mission_requested.emit(qid))
	var submit_text := "Проверить и отметить" if str(stage.get("completion_policy", "automatic")) == "joint_review" else "Завершить шаг"
	var all_done := interactions.all(func(i): return successful_interactions.has(str(i.get("interaction_id", ""))))
	var current_done := successful_interactions.has(str(_interaction().get("interaction_id", ""))) and not replay_interaction
	var action_text := submit_text if all_done and not replay_interaction else "Продолжить →" if current_done else "Проверить ответ"
	var submit := UI.button(action_text,footer,func():
		if all_done and not replay_interaction: _submit()
		elif current_done:
			for i in range(interactions.size()):
				if not successful_interactions.has(str(interactions[i].interaction_id)): _select_interaction(i); break
		else: _check_current(),true)
	submit.name = "EpisodePrimaryAction"
	var next_focus := submit
	submit.disabled = status == "COMPLETED" or bool(UI.instance_for(state,instance_id).get("safety_hold",false))
	if not current_done and str(_interaction().get("type", "")) == "scripted_dialogue" and not bool(response.get("terminal",false)):
		submit.text = "Выбери ответ выше"
		submit.disabled = true
	if status == "COMPLETED":
		submit.hide()
		var next_stage: Dictionary = {}
		for definition in UI.stages(quest):
			var record := UI.stage_progress(state,instance_id,str(definition.get("stage_id", "")))
			if str(record.get("status", "LOCKED")) in ["AVAILABLE","IN_PROGRESS","AWAITING_REVIEW"]:
				next_stage = definition
				break
		if not next_stage.is_empty():
			next_focus = UI.button("Следующий шаг →",footer,func(): episode_requested.emit(instance_id,str(next_stage.get("stage_id", ""))),true)
		else:
			next_focus = UI.button("К моим работам →",footer,func(): collection_requested.emit(),true)
	hint_label = UI.label("",content,0,UI.TEAL)
	hint_label.visible = false
	UI.focus_later(next_focus if not next_focus.disabled and next_focus.visible else s.close,self)

func _interaction() -> Dictionary:
	return interactions[interaction_index] if not interactions.is_empty() else {}

func _returned_for_revision() -> bool:
	var history: Array = progress.get("review_history", [])
	return str(progress.get("status", "")) == "IN_PROGRESS" and not history.is_empty() and not bool(history.back().get("approved",true))

func _select_interaction(index: int) -> void:
	_capture()
	interaction_index = clampi(index,0,maxi(0,interactions.size()-1))
	replay_interaction = false
	_build()

func _check_current() -> void:
	_capture()
	_prepare_response()
	_send("stage_attempt",{"interaction_id":str(_interaction().get("interaction_id", "")),"response":response.duplicate(true)})

func _render_interaction() -> void:
	var inter := _interaction()
	var id := str(inter.get("interaction_id", ""))
	response = draft.get("responses", {}).get(id, {}).duplicate(true)
	hint_level = int(response.get("hint_level",0))
	var config: Dictionary = inter.get("config", {})
	if successful_interactions.has(id) and not replay_interaction:
		UI.label("✓ " + str(inter.get("title", "Сцена готова")),area,21,UI.BRASS)
		UI.label(_success_text(inter),area)
		UI.button("Открыть сцену ещё раз",area,func(): _capture(); replay_interaction = true; _build())
		return
	UI.label(Guide.prompt(id,str(inter.get("prompt", ""))),area,19)
	match str(inter.get("type", "")):
		"inspect_reveal": _inspect(config)
		"match_cards": _match(config)
		"order_fragments": _order(config)
		"assemble_selection": _assemble(config)
		"scripted_dialogue": _dialogue(config)
		"real_world_step": _real_world(config)
		"compare_observations": _compare(config)
		"exhibit_composition": _assemble(config); _fields(config)
		_: UI.label("Этот тип сцены требует обновления SUR.",area)
	if TYPES_SUPPORTED.has(str(inter.get("type", ""))) and str(progress.get("status", "")) == "COMPLETED":
		UI.button("Сохранить эту сцену" if str(inter.get("type", "")) in ["real_world_step","compare_observations"] else "Проверить эту попытку",area,func():
			_capture()
			_prepare_response()
			_send("stage_attempt",{"interaction_id":id,"response":response.duplicate(true)}),true)

func _success_text(inter: Dictionary) -> String:
	if str(inter.get("type", "")) == "scripted_dialogue":
		var config: Dictionary = inter.get("config", {})
		var current := str(config.get("start_node_id", ""))
		var message := ""
		for choice_id in response.get("choice_ids", []):
			for entry in config.get("nodes", []):
				if str(entry.get("node_id", "")) != current: continue
				for choice in entry.get("choices", []):
					if str(choice.get("id", "")) == str(choice_id):
						message = str(choice.get("feedback", ""))
						current = str(choice.get("next_node_id", ""))
						break
				break
		if not message.is_empty(): return message
	var authored := str(inter.get("success_text", ""))
	if not authored.is_empty() and authored != "Эта часть истории сохранена. Можно продолжить или вернуться позже.": return authored
	return {"match_cards":"Пары сошлись. Можно открыть следующую часть истории.","order_fragments":"История сложилась в твоём порядке.","inspect_reveal":"Старая запись открыта. Теперь можно выбрать, что исследовать дальше.","assemble_selection":"Твой выбор сохранён.","exhibit_composition":"Твои детали сохранились — у работы появилось своё лицо.","real_world_step":"Твоё наблюдение сохранено. Теперь можно посмотреть результат вместе.","compare_observations":"Две страницы теперь связаны твоим ответом."}.get(str(inter.get("type", "")),"Эта сцена готова. Можно продолжить или вернуться позже.")

func _capture() -> void:
	for key in response_fields:
		var field = response_fields[key]
		if is_instance_valid(field):
			if not response.has("fields"): response["fields"] = {}
			response.fields[key] = field.text
	if not interactions.is_empty():
		if not draft.has("responses"): draft["responses"] = {}
		draft["interaction_id"] = str(_interaction().get("interaction_id", ""))
		draft.responses[str(_interaction().get("interaction_id", ""))] = response.duplicate(true)
	if is_instance_valid(attest): draft["attested"] = attest.button_pressed
	if is_instance_valid(note): draft["note"] = note.text
	if is_instance_valid(assistance):
		draft["assistance_index"] = assistance.selected
		draft["assistance"] = ["independent","hint","together"][assistance.selected]

func _inspect(config: Dictionary) -> void:
	var seen: Array = response.get("revealed_ids", [])
	response["revealed_ids"] = seen
	for detail in config.get("details", []):
		var item: Dictionary = detail
		var id := str(item.get("id", ""))
		var text := UI.label(str(item.get("text", "")),area,0,UI.MUTED)
		text.visible = seen.has(id)
		var reveal := UI.button(("✓ " if seen.has(id) else "Открыть · ") + str(item.get("title",id)),area,func():
			text.visible = true
			if not response.revealed_ids.has(id): response.revealed_ids.append(id))
		reveal.pressed.connect(func(): reveal.text = "✓ " + str(item.get("title",id)))

func _match(config: Dictionary) -> void:
	if str(_interaction().get("interaction_id", "")) == "water_home_examples":
		var pictures := UI.row(area)
		for example in [["example_flow","Рисунок горизонтального течения"],["example_fall","Рисунок падающей воды"]]:
			var frame := UI.column(pictures)
			var art := Art.new()
			art.kind = example[0]
			art.custom_minimum_size = Vector2(0,92)
			frame.add_child(art)
			UI.label(str(example[1]),frame,13,UI.MUTED).horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	if config.has("minimum_unassisted_correct"):
		UI.button("Новая попытка без карточек",area,_reset_mixed_attempt)
	if not response.has("pairs"): response["pairs"] = {}
	var targets: Array = config.get("targets", []).duplicate(true)
	targets.reverse()
	for card in config.get("cards", []):
		var line := UI.row(area)
		UI.label(str(card.get("text", "")),line)
		var labels: Array = ["Выбрать пару…"]
		for target in targets: labels.append(str(target.get("text", "")))
		var id := str(card.get("id", ""))
		var selected := 0
		for i in range(targets.size()):
			if str(targets[i].get("id", "")) == str(response.pairs.get(id, "")): selected = i+1
		var choices := UI.option(line,labels,selected)
		choices.item_selected.connect(func(index):
			if index == 0: response.pairs.erase(id)
			else: response.pairs[id] = str(targets[index-1].get("id", "")))
		if config.has("minimum_unassisted_correct"):
			if not response.has("assisted_ids"): response["assisted_ids"] = []
			var help := UI.button("Карточка",line,func():
				if not response.assisted_ids.has(id): response.assisted_ids.append(id)
				feedback.text = str(config.get("pair_feedback", {}).get(id, ""))
				feedback.visible = true)
			help.tooltip_text = "Открыть перевод; это слово отметится с помощью"

func _reset_mixed_attempt() -> void:
	var id := str(_interaction().get("interaction_id", ""))
	if not _interaction().get("config", {}).has("minimum_unassisted_correct"): return
	_capture()
	response = {"pairs":{},"assisted_ids":[],"hint_level":0}
	draft.responses[id] = response.duplicate(true)
	successful_interactions.erase(id)
	hint_level = 0
	_build()
	feedback.text = "Новая попытка. Выбери пары заново; предыдущие попытки остаются в истории."
	feedback.visible = true

func _order(config: Dictionary) -> void:
	var fragments: Array = config.get("fragments", [])
	if not response.has("order"):
		response["order"] = []
		for frag in fragments: response.order.push_front(str(frag.get("id", "")))
	var list := UI.column(area)
	_draw_order(list,fragments)

func _draw_order(list: VBoxContainer, fragments: Array) -> void:
	UI.clear(list)
	for i in range(response.get("order", []).size()):
		var index := i
		var id := str(response.order[i])
		var text := id
		for fragment in fragments:
			if str(fragment.get("id", "")) == id: text = str(fragment.get("text",id))
		var line := UI.row(list)
		UI.label("%d. %s" % [i+1,text],line)
		var up := UI.button("↑",line,func():
			var a = response.order[index-1]
			response.order[index-1] = response.order[index]
			response.order[index] = a
			_draw_order(list,fragments))
		up.tooltip_text = "Передвинуть выше"
		up.disabled = i == 0
		var down := UI.button("↓",line,func():
			var a = response.order[index+1]
			response.order[index+1] = response.order[index]
			response.order[index] = a
			_draw_order(list,fragments))
		down.tooltip_text = "Передвинуть ниже"
		down.disabled = i == response.order.size()-1

func _assemble(config: Dictionary) -> void:
	if not response.has("selected_ids"): response["selected_ids"] = []
	var minimum := int(config.get("min_selected",1))
	var maximum := int(config.get("max_selected",maxi(1,config.get("items",config.get("choices", [])).size())))
	var group := ButtonGroup.new() if maximum == 1 else null
	if group != null: group.allow_unpress = true
	for item in config.get("items",config.get("choices", [])):
		var id := str(item.get("id", ""))
		var choice := UI.check(str(item.get("text",id)),area,response.selected_ids.has(id),func(on):
			if on and not response.selected_ids.has(id): response.selected_ids.append(id)
			elif not on: response.selected_ids.erase(id))
		if group != null: choice.button_group = group
	UI.label("Выбери один вариант." if minimum == 1 and maximum == 1 else "Выбери ровно %d." % minimum if minimum == maximum else "Выбери от %d до %d деталей." % [minimum,maximum],area,0,UI.MUTED)

func _dialogue(config: Dictionary) -> void:
	var node_id := str(response.get("node_id",config.get("start_node_id", "")))
	var node: Dictionary = {}
	for entry in config.get("nodes", []):
		if str(entry.get("node_id", "")) == node_id: node = entry
	response["node_id"] = node_id
	response["terminal"] = bool(node.get("terminal",false))
	if not response.has("choice_ids"): response["choice_ids"] = []
	UI.label(str(node.get("speaker", "")) + " · " + str(node.get("text", "")),area)
	for choice in node.get("choices", []):
		var picked: Dictionary = choice
		UI.button(str(picked.get("text", "")),area,func():
			if not bool(picked.get("correct",true)):
				feedback.text = str(picked.get("feedback", "Можно выбрать другую реплику."))
				feedback.visible = true
				return
			response.choice_ids.append(str(picked.get("id", "")))
			response["node_id"] = str(picked.get("next_node_id",node_id))
			_capture()
			UI.clear(area)
			response_fields.clear()
			_render_interaction()
			feedback.text = str(picked.get("feedback", ""))
			feedback.visible = not feedback.text.is_empty()
			if bool(response.get("terminal",false)): _check_current())
	if bool(node.get("terminal",false)):
		UI.button("Пройти диалог снова",area,func():
			response = {"node_id":str(config.get("start_node_id", "")),"choice_ids":[]}
			_capture()
			UI.clear(area)
			_render_interaction())

func _fields(config: Dictionary) -> void:
	var interaction_id := str(_interaction().get("interaction_id", ""))
	for field in config.get("fields", []):
		var id := str(field.get("id", ""))
		var label_text := Guide.field_label(interaction_id,id,str(field.get("label",id)))
		UI.label(label_text + (" *" if bool(field.get("required",false)) else ""),area,0,UI.BRASS)
		response_fields[id] = UI.text_input(area,"Можно написать коротко…",str(response.get("fields", {}).get(id, "")),80)

func _real_world(config: Dictionary) -> void:
	var interaction_id := str(_interaction().get("interaction_id", ""))
	var how: Array = Guide.how_steps(interaction_id)
	if how.is_empty():
		UI.label("РЕАЛЬНЫЙ ШАГ · можно продолжить в другой день",area,14,UI.TEAL)
	else:
		UI.label("ЧТО СДЕЛАТЬ · можно продолжить в другой день",area,14,UI.TEAL)
		for i in range(how.size()): UI.label("%d. %s" % [i+1,str(how[i])],area,15)
	for hint in choice_context.get("hints", []): UI.label(str(hint),area,14,UI.TEAL)
	var materials: Array = Guide.materials(interaction_id,config.get("materials", []))
	if not materials.is_empty():
		var needed: Array[String] = []
		for material in materials: needed.append(str(material))
		UI.label("Понадобится: " + ", ".join(PackedStringArray(needed)),area,14,UI.MUTED)
	_fields(config)
	if bool(config.get("real_visit_required",false)) and config.has("atlas_location_id"):
		var visit := CheckBox.new()
		visit.text = "Этот семейный выход состоялся · " + {"rio_azul":"Río Azul","waterfalls":"Водопады"}.get(str(config.atlas_location_id),str(config.atlas_location_id))
		visit.button_pressed = bool(response.get("visited",false))
		visit.toggled.connect(func(on): response["visited"] = on; response["atlas_location_id"] = config.atlas_location_id)
		area.add_child(visit)
		UI.label("Домашнее исследование можно сохранить отдельно в архиве. Эта страница относится к реальному выходу.",area,0,UI.MUTED)
		UI.button("Сохранить домашнее исследование отдельно",area,func():
			_capture()
			var observation := str(response.get("fields", {}).get("observation",draft.get("note", ""))).strip_edges()
			if observation.is_empty():
				show_result({"ok":false,"message":"Добавь своё наблюдение в поле выше. Оно сохранится отдельной работой."})
				return
			command_requested.emit("create_work",{"title":"Исследование по материалам","kind":"note","quest_ids":[str(quest.get("quest_id", ""))],"authorship":{"category":"personal"},"content":{"note":observation,"home_materials":true},"status":"IN_PROGRESS"}))
	if not config.get("required_checks", []).is_empty():
		if not response.has("checks"): response["checks"] = {}
		var check_names := {"launches":"Проект запускается", "movement":"Герой управляется", "collection":"Три предмета собираются", "win":"Победа достижима", "clean_restart":"Перезапуск начинает чистую попытку", "own_improvement":"Проверили выбранное автором улучшение"}
		for check_id in config.required_checks:
			var key := str(check_id)
			var c := CheckBox.new()
			c.text = str(check_names.get(key,key))
			c.button_pressed = bool(response.checks.get(key,false))
			c.toggled.connect(func(on): response.checks[key] = on)
			area.add_child(c)
	if not response.has("criteria"): response["criteria"] = []
	var criteria: Array = Guide.criteria(stage_id,interaction_id,config.get("criteria",stage.get("criteria", [])))
	if not criteria.is_empty(): UI.label("Отметь то, что уже сделано:",area,14,UI.TEAL)
	while response.criteria.size() < criteria.size(): response.criteria.append(false)
	for i in range(criteria.size()):
		var idx := i
		UI.check(str(criteria[i]),area,bool(response.criteria[i]),func(on): response.criteria[idx] = on)
	if stage_id == "game_premiere":
		var entries: Array = UI.context(state).get("launch_entries", [])
		UI.label("Сохранённая версия игры",area,18,UI.BRASS)
		var titles: Array = ["Выбрать сохранённую сборку…"]
		var chosen := 0
		for i in range(entries.size()):
			titles.append("%s · %s" % [str(entries[i].get("title", "Моя игра")),str(entries[i].get("version_label", ""))])
			if str(entries[i].get("launch_entry_id", "")) == str(response.get("launch_entry_id", "")): chosen = i+1
		var builds := UI.option(area,titles,chosen)
		builds.item_selected.connect(func(i):
			if i == 0: response.erase("launch_entry_id")
			else: response["launch_entry_id"] = str(entries[i-1].get("launch_entry_id", "")))
		if entries.is_empty(): UI.label("Сначала зарегистрируйте свою сборку в семейной мастерской. Версия будет доступна в этом списке.",area,0,UI.MUTED)
	if config.has("starter_project_id"):
		UI.label("Учебная основа — отдельный проект. В заметке отметь, что выбрала сама и что вы сделали вместе.",area,0,UI.MUTED)
		UI.button("Открыть учебную основу",area,func(): command_requested.emit("open_starter_project",{"starter_project_id":config.starter_project_id}))
	var btn_attach_title := "Прикрепить изображение"
	if stage_id == "water_river":
		btn_attach_title = "Прикрепить фото реки 📷"
	elif stage_id == "water_fall":
		btn_attach_title = "Прикрепить фото водопада 📷"
	var has_image := not str(draft.get("artifact_id", "")).is_empty()
	if has_image:
		UI.label("✓ Фотография прикреплена (появится в настенном диптихе на станции!)",area,14,UI.TEAL)
	UI.button(btn_attach_title,area,func():
		_capture()
		command_requested.emit("attach_stage_media",_payload({"draft":draft.duplicate(true)})))

func _compare(config: Dictionary) -> void:
	var pair := UI.row(area)
	for sid in config.get("source_stage_ids", []):
		var box := UI.card(pair)
		var source := UI.stage_progress(state,instance_id,str(sid))
		var saved: Dictionary = source.get("evidence",source.get("draft", {}))
		var title := str(sid)
		for definition in UI.stages(quest):
			if str(definition.get("stage_id", "")) == str(sid): title = str(definition.get("title",sid))
		UI.label(title,box,20,UI.BRASS)
		var text := str(saved.get("note", ""))
		if text.is_empty(): text = str(saved.get("fields", {}).get("observation", "Открой сохранённую работу в архиве, чтобы сравнить подробности."))
		UI.label(text,box)
	UI.button("Посмотреть работы",area,func(): _leave("collection"))
	var categories: Array = config.get("categories", [])
	var names: Array = []
	for category in categories: names.append(str(category.get("text", "")))
	if not names.is_empty():
		var choose := UI.option(area,names)
		choose.item_selected.connect(func(i): response["category_id"] = str(categories[i].get("id", "")))
		if not response.has("category_id"): response["category_id"] = str(categories[0].get("id", ""))
	_fields(config)
	if config.get("fields", []).is_empty():
		response_fields["comparison"] = UI.text_input(area,"Одно различие между моими наблюдениями…",str(response.get("fields", {}).get("comparison", "")))

func _hint() -> void:
	var hints: Array = _interaction().get("hints", [])
	if hints.is_empty(): return
	hint_level = mini(hint_level+1,mini(3,hints.size()))
	if is_instance_valid(help_button): help_button.text = "Подсказка · %d/3" % hint_level
	response["hint_level"] = hint_level
	hint_label.text = str(hints[hint_level-1])
	hint_label.visible = true
	if is_instance_valid(portrait_view) and not persona_id.is_empty():
		var path := "res://assets/characters/%s_thinking.svg" % persona_id
		if ResourceLoader.exists(path): portrait_view.texture = load(path)
	if _interaction().get("config", {}).has("minimum_unassisted_correct") and hint_level == 3:
		if not response.has("assisted_ids"): response["assisted_ids"] = []
		for card in _interaction().config.get("cards", []):
			if not response.assisted_ids.has(str(card.id)): response.assisted_ids.append(str(card.id))
	_send("stage_hint",{"interaction_id":str(_interaction().get("interaction_id", "")),"level":hint_level})

func _prepare_response() -> void:
	var config: Dictionary = _interaction().get("config", {})
	if str(_interaction().get("type", "")) == "compare_observations":
		response["source_stage_ids"] = config.get("source_stage_ids", []).duplicate()
		response["comparison"] = str(response.get("fields", {}).get("comparison",response.get("fields", {}).get("difference",draft.get("note", ""))))
	if config.has("minimum_unassisted_correct"):
		response["sample_lexeme_ids"] = config.get("lexeme_ids", []).duplicate()
		response["unassisted_lexeme_ids"] = []
		response["assisted_lexeme_ids"] = []
		var cards: Array = config.get("cards", [])
		for i in range(cards.size()):
			var id := str(cards[i].get("id", ""))
			if response.get("assisted_ids", []).has(id): response.assisted_lexeme_ids.append(config.lexeme_ids[i])
			if response.get("pairs", {}).get(id, "") == config.get("accepted_pairs", {}).get(id, "!") and not response.get("assisted_ids", []).has(id):
				response.unassisted_lexeme_ids.append(config.lexeme_ids[i])
	_capture()

func _submit() -> void:
	_capture()
	_prepare_response()
	var evidence := draft.duplicate(true)
	evidence["fields"] = {}
	evidence["choices"] = {}
	for response_id in draft.get("responses", {}):
		var saved: Dictionary = draft.responses[response_id]
		evidence.fields.merge(saved.get("fields", {}),true)
		for key in ["visited","atlas_location_id","checks","sample_lexeme_ids","unassisted_lexeme_ids","category_id","comparison","launch_entry_id"]:
			if saved.has(key): evidence[key] = saved[key]
		if saved.has("selected_ids"): evidence.choices[str(response_id)] = {"interaction_id":str(response_id),"selected_ids":saved.selected_ids.duplicate(),"fields":saved.get("fields", {}).duplicate(true)}
	evidence["criteria"] = response.get("criteria", []).duplicate()
	if str(evidence.get("note", "")).strip_edges().is_empty(): evidence["note"] = str(evidence.fields.get("observation",evidence.fields.get("note", "")))
	_send("stage_submit",{"evidence":evidence,"draft":draft.duplicate(true)})

func _build_review(parent: Node) -> void:
	var box := UI.card(parent)
	UI.label("Проверь результат",box,25,UI.BRASS)
	UI.label("Пройди по пунктам и отметь каждый, когда он точно выполнен. Если чего-то не хватает, вернись и доработай: всё сделанное сохранится.",box)
	UI.label(str(draft.get("note",progress.get("draft", {}).get("note", ""))),box)
	for saved in draft.get("responses", {}).values():
		for value in saved.get("fields", {}).values():
			if not str(value).strip_edges().is_empty(): UI.label(str(value),box,0,UI.MUTED)
	var checks: Array = []
	for criterion in Guide.criteria(stage_id,"",stage.get("criteria", [])):
		var check := UI.check(str(criterion),box,false,func(_on): pass)
		checks.append(check)
	var review_note := UI.text_input(box,"Заметка (по желанию)…",str(progress.get("review_note", "")))
	var r := UI.row(content)
	var approve := UI.button("Всё верно — отмечаю",r,func():
		var flags: Array = []
		for check in checks: flags.append(check.button_pressed)
		_send("stage_review",{"approved":true,"criteria":flags,"note":review_note.text,"assistance":draft.get("assistance", "together")}),true)
	approve.disabled = not checks.is_empty()
	for check in checks:
		check.toggled.connect(func(_on):
			var all_checked := true
			for c in checks: all_checked = all_checked and c.button_pressed
			approve.disabled = not all_checked)
	UI.button("Нужно доработать",r,func(): _send("stage_review",{"approved":false,"criteria":[],"note":review_note.text}))

func _build_words(parent: Node) -> void:
	var inter_id := str(_interaction().get("interaction_id", ""))
	var envelope := _current_envelope()
	if envelope.is_empty(): return
	var box := UI.card(parent)
	var count: int = envelope.get("lexeme_ids", []).size()
	UI.button("Скрыть слова конверта" if words_open else "Слова этого конверта · %d" % count,box,func(): _capture(); words_open = not words_open; _build())
	if not words_open: return
	var lexicon: Array = UI.records(quest.get("adventure", {}).get("lexicon", []))
	for word in lexicon:
		if not envelope.get("lexeme_ids", []).has(str(word.get("lexeme_id", ""))): continue
		var line := UI.row(box)
		UI.label("%s — %s\n%s" % [str(word.get("base_form",word.get("lemma",word.get("word", "")))),str(word.get("translation", "")),str(word.get("example", ""))],line)
		var id := str(word.get("lexeme_id", ""))
		UI.button("Повторить позже",line,func(): _send("stage_lexemes",{"lexeme_ids":[id],"status":"want_review","assistance":""}))
	var actions := UI.row(box)
	UI.button("Добавить в альбом",actions,func(): _send("stage_lexemes",{"lexeme_ids":envelope.get("lexeme_ids", []),"status":"encountered","assistance":""}))
	for pair in [["Узнаю в сцене","recognized"],["Использовала","used"]]:
		var target_status: String = pair[1]
		var mark := UI.button(pair[0],actions,func(): _send("stage_lexemes",{"lexeme_ids":envelope.get("lexeme_ids", []),"status":target_status,"assistance":"hint" if hint_level > 0 else ""}))
		mark.disabled = not successful_interactions.has(inter_id)
		if mark.disabled: mark.tooltip_text = "Сначала примени слова в этой сцене"
