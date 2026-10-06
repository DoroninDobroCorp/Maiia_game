class_name AdventureHub
extends Control

const UI = preload("res://scripts/presentation/adventure_ui.gd")
const Art = preload("res://scripts/presentation/adventure_art.gd")
const Guide = preload("res://scripts/presentation/mission_guide.gd")
const CURRENT_STORY_QUEST_IDS := ["FG01", "FG11", "FG08"]
signal closed
signal command_requested(operation: String, payload: Dictionary)
signal quest_requested(qid: String)
signal mission_requested(qid: String)
signal episode_requested(instance_id: String, stage_id: String)
signal gallery_requested(room_id: String)
signal collection_requested
signal map_requested
signal editor_requested
signal family_requested
signal legacy_journal_requested

var state: Dictionary = {}
var audio_service: Node
var content: VBoxContainer
var feedback: Label
var current_tab := 0
var query := ""
var filter_status := 0
var interest := ""
var location_filter := ""
var short_only := false
var solo_only := false
var favorites_only := false
var page := 0
var history_quest: Dictionary = {}

func setup(game_state: Dictionary, audio_svc: Node = null) -> void:
	state = game_state.duplicate(true)
	audio_service = audio_svc
	if UI.context(state).has("history_quest_id"):
		for q in _catalog():
			if str(q.get("quest_id", "")) == str(UI.context(state).history_quest_id): history_quest = q
	_build()

func show_result(result: Dictionary) -> void:
	feedback.text = UI.result_text(result)
	feedback.visible = true

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		if not history_quest.is_empty():
			history_quest = {}
			_build()
		else:
			closed.emit()

func _catalog() -> Array:
	if UI.context(state).has("catalog"):
		return UI.context(state).catalog
	var by_id: Dictionary = {}
	for record in UI.records(state.get("phase_b", {}).get("published_versions", {})):
		var q: Dictionary = record.get("quest", record)
		var qid := str(q.get("quest_id", ""))
		if q.has("adventure") and int(q.get("revision", 0)) >= int(by_id.get(qid, {}).get("revision", 0)):
			by_id[qid] = q
	for inst in UI.instances(state):
		var q := UI.quest_for(inst)
		if q.has("adventure"):
			by_id[str(q.get("quest_id", ""))] = q
	var values: Array = by_id.values()
	values.sort_custom(func(a, b): return int(a.get("goal_order", 99)) < int(b.get("goal_order", 99)))
	return values

func _build() -> void:
	var s := UI.shell(self,state,"Журнал станции","Три миссии станции. У каждой есть свой предмет на столе, а здесь видно, что дальше.",func(): closed.emit())
	content = s.content
	feedback = s.feedback
	var tabs := UI.row(content)
	var tab_names := ["Сейчас", "Приключения", "Мои работы", "Карта", "Летопись станции"]
	for i in range(tab_names.size()):
		var index := i
		UI.button(tab_names[i],tabs,func():
			current_tab = index
			history_quest = {}
			_build(), i == current_tab)
	var space := Control.new()
	space.size_flags_horizontal = SIZE_EXPAND_FILL
	tabs.add_child(space)
	UI.button("Архив старых записей",tabs,func(): legacy_journal_requested.emit())
	if not history_quest.is_empty():
		_build_history()
		return
	match current_tab:
		0: _build_now()
		1: _build_catalog()
		2:
			var box := UI.card(content)
			UI.label("История, которую создаёшь ты",box,25,UI.BRASS)
			UI.label("Рисунки, страницы эфира, наблюдения и версии твоей игры. Здесь можно вернуться к каждой работе и выбрать, что оставить на виду.",box)
			var r := UI.row(box)
			UI.button("Открыть архив работ",r,func(): collection_requested.emit(),true)
			UI.button("Войти в галерею",r,func(): gallery_requested.emit(""))
		3:
			var box := UI.card(content)
			UI.label("Карта долины и план станции",box,25,UI.BRASS)
			UI.label("Наблюдения открывают страницы атласа. Из галереи можно перейти в любой из своих залов.",box)
			UI.button("Открыть карту",box,func(): map_requested.emit(),true)
			UI.button("Мои выставочные залы",box,func(): gallery_requested.emit(""))
		4:
			_build_chronicle()
	UI.focus_later(s.close,self)

func _build_now() -> void:
	var sc := UI.scroll(content)
	var banner := UI.row(sc)
	UI.label("МИССИИ СТАНЦИИ · можно в любом порядке",banner,14,UI.BRASS)
	UI.button("Моя галерея →",banner,func(): gallery_requested.emit(""))
	var cards := UI.row(sc)
	var shown := 0
	var catalog := _catalog()
	for qid in CURRENT_STORY_QUEST_IDS:
		for q in catalog:
			if str(q.get("quest_id", "")) == qid:
				_quest_card(cards,q,true)
				shown += 1
				break
	if shown == 0:
		UI.label("Три первые истории пока не появились в журнале.",sc)
		UI.button("Вместе откроем новую главу",sc,func(): family_requested.emit(),true)
		UI.button("Открыть галерею",sc,func(): gallery_requested.emit(""))
	var done := 0
	for qid in CURRENT_STORY_QUEST_IDS:
		if str(UI.instance_for(state,qid).get("status", "")) == "COMPLETED":
			done += 1
	if done == 3:
		var finale := UI.card(sc)
		UI.label("Вечер открытой станции",finale,24,UI.BRASS)
		UI.label("Три истории готовы встретиться. Выбери название и свои работы в архиве.",finale)
		UI.button("Собрать выставку главы",finale,func(): collection_requested.emit(),true)
	_build_challenge_card(sc)

func _quest_card(parent: Node, quest: Dictionary, illustrated: bool = false) -> void:
	var box := UI.card(parent)
	box.get_parent().size_flags_horizontal = SIZE_EXPAND_FILL
	if illustrated:
		box.get_parent().size_flags_stretch_ratio = 1.0
		var art := Art.new()
		art.kind = str(quest.get("quest_id", ""))
		art.custom_minimum_size.y = 104
		box.add_child(art)
	var qid := str(quest.get("quest_id", ""))
	var inst := UI.instance_for(state,qid)
	var guide := Guide.mission(qid)
	var stages := UI.stages(quest)
	var next := _next_stage(quest,inst)
	var done := 0
	for stage in stages:
		if str(UI.stage_progress(state,str(inst.get("instance_id", "")),str(stage.get("stage_id", ""))).get("status", "")) == "COMPLETED":
			done += 1
	var finished := not inst.is_empty() and not stages.is_empty() and done >= stages.size()
	if guide.is_empty():
		UI.label(UI.status_text(str(inst.get("status", "AVAILABLE"))),box,14,UI.TEAL)
	else:
		UI.label("Миссия выполнена" if finished else "Шаг %d из %d" % [mini(done+1,stages.size()),stages.size()] if done > 0 else "Новая миссия",box,14,UI.TEAL)
	UI.label(str(quest.get("story_title",quest.get("title", "Приключение"))),box,21)
	if guide.is_empty():
		UI.label(str(next.get("title",quest.get("summary", "Выбери первое действие"))),box)
	else:
		UI.label(str(guide.get("goal", quest.get("summary", ""))),box,14)
		if finished:
			UI.label(str(guide.get("remains", "")),box,13,UI.BRASS)
		else:
			var info := Guide.step(str(next.get("stage_id", "")))
			UI.label("Дальше: %s" % str(info.get("title", next.get("title", ""))),box,15)
			UI.label(str(info.get("task", "")),box,13,UI.MUTED)
			var where := Guide.where_text(info)
			if not where.is_empty(): UI.label(where,box,12,UI.TEAL)
			UI.label("Предмет на столе: %s" % str(guide.get("object", "")),box,12,UI.BRASS)
	if guide.is_empty() and not str(next.get("next_hint",quest.get("return_text", ""))).is_empty():
		UI.label(str(next.get("next_hint",quest.get("return_text", ""))),box,14,UI.MUTED)
	var bottom := VBoxContainer.new()
	bottom.size_flags_vertical = SIZE_EXPAND_FILL
	bottom.alignment = BoxContainer.ALIGNMENT_END
	box.add_child(bottom)
	var primary := UI.button(("Открыть итог →" if finished else "Продолжить →") if not inst.is_empty() else "Начать миссию →",bottom,func():
		if inst.is_empty() or (finished and not guide.is_empty()):
			if guide.is_empty(): quest_requested.emit(qid)
			else: mission_requested.emit(qid)
		else: episode_requested.emit(str(inst.get("instance_id", "")),str(next.get("stage_id", ""))),true)
	primary.name = "QuestPrimary_" + qid
	if guide.is_empty():
		UI.button("Посмотреть путь",bottom,func(): history_quest = quest; _build())
	else:
		UI.button("О миссии и весь путь",bottom,func(): mission_requested.emit(qid))
	if not CURRENT_STORY_QUEST_IDS.has(qid):
		var pinned: Array = UI.pinned(state)
		UI.button("Убрать из избранного" if pinned.has(qid) else "В избранное",bottom,func(): command_requested.emit("pin_quest",{"quest_id":qid,"pinned":not pinned.has(qid)}))

func _next_stage(quest: Dictionary, inst: Dictionary) -> Dictionary:
	var list := UI.stages(quest)
	for stage in list:
		var progress := UI.stage_progress(state,str(inst.get("instance_id", "")),str(stage.get("stage_id", "")))
		if str(progress.get("status", "AVAILABLE")) not in ["COMPLETED", "LOCKED"]:
			return stage
	return list.back() if not list.is_empty() else {}

func _build_catalog() -> void:
	var filters := UI.row(content)
	var search := UI.input(filters,"Найти приключение…",query)
	search.text_submitted.connect(func(value): query = value; page = 0; _build())
	UI.button("Найти",filters,func(): query = search.text; page = 0; _build())
	var statuses := UI.option(filters,["Все", "Доступно", "Начато", "Отложено", "Завершено"],filter_status)
	statuses.item_selected.connect(func(index): filter_status = index; page = 0; _build())
	var more := UI.row(content)
	var topic := UI.input(more,"Интерес или тема",interest)
	topic.text_submitted.connect(func(v): interest = v; page = 0; _build())
	var place := UI.input(more,"Место",location_filter)
	place.text_submitted.connect(func(v): location_filter = v; page = 0; _build())
	for item in [["До 15 минут",short_only,"short"],["Без взрослого",solo_only,"solo"],["Избранное",favorites_only,"favorite"]]:
		var c := CheckButton.new()
		c.text = item[0]
		c.button_pressed = item[1]
		var key: String = item[2]
		c.toggled.connect(func(v):
			if key == "short": short_only = v
			elif key == "solo": solo_only = v
			else: favorites_only = v
			page = 0
			_build())
		more.add_child(c)
	var matches: Array = []
	for q in _catalog():
		var qid := str(q.get("quest_id", ""))
		var inst := UI.instance_for(state,qid)
		var status := str(inst.get("status", "AVAILABLE"))
		if filter_status > 0 and status != ["", "AVAILABLE", "ACTIVE", "PAUSED", "COMPLETED"][filter_status]: continue
		if not query.is_empty() and not str(q.get("story_title",q.get("title", ""))).to_lower().contains(query.to_lower()): continue
		if not interest.is_empty() and not str(q.get("tags",q.get("skill_id", ""))).to_lower().contains(interest.to_lower()): continue
		if not location_filter.is_empty() and not str(q.get("location_id",q.get("entry_anchor_id", ""))).to_lower().contains(location_filter.to_lower()): continue
		if short_only and int(_next_stage(q,inst).get("estimated_minutes",q.get("duration_minutes",15))) > 15: continue
		if solo_only and str(_next_stage(q,inst).get("completion_policy", "")) == "joint_review": continue
		if favorites_only and not UI.pinned(state).has(qid): continue
		matches.append(q)
	var list := UI.scroll(content)
	UI.label("Найдено: %d" % matches.size(),list,14,UI.MUTED)
	for q in matches.slice(page*9,mini((page+1)*9,matches.size())):
		_quest_card(list,q)
	if matches.is_empty(): UI.label("Подходящих историй пока нет. Можно изменить фильтры или вернуться к выставке.",list)
	var pages := UI.row(content)
	var prev := UI.button("← Назад",pages,func(): page -= 1; _build())
	prev.disabled = page == 0
	UI.label("Страница %d" % (page+1),pages)
	var next := UI.button("Дальше →",pages,func(): page += 1; _build())
	next.disabled = (page+1)*9 >= matches.size()

func _build_history() -> void:
	var inst := UI.instance_for(state,str(history_quest.get("quest_id", "")))
	var sc := UI.scroll(content)
	UI.label(str(history_quest.get("story_title",history_quest.get("title", ""))),sc,26,UI.BRASS)
	for stage in UI.stages(history_quest):
		var progress := UI.stage_progress(state,str(inst.get("instance_id", "")),str(stage.get("stage_id", "")))
		var box := UI.card(sc)
		UI.label("%s · %s" % [UI.status_text(str(progress.get("status", "AVAILABLE"))),str(stage.get("title", ""))],box,21)
		UI.label(str(stage.get("summary", "")),box)
		UI.label(str(stage.get("next_hint", "")),box,0,UI.TEAL)
		for criterion in stage.get("criteria", []): UI.label("• " + str(criterion),box,0,UI.MUTED)
		var btn := UI.button("Открыть этап",box,func():
			if inst.is_empty(): quest_requested.emit(str(history_quest.get("quest_id", "")))
			else: episode_requested.emit(str(inst.get("instance_id", "")),str(stage.get("stage_id", ""))))
		btn.disabled = str(progress.get("status", "")) == "LOCKED"
	if not inst.is_empty() and str(inst.get("status", "")) != "COMPLETED":
		var paused := str(inst.get("status", "")) == "PAUSED"
		UI.button("Продолжить историю" if paused else "Отложить, сохранив всё",content,func(): command_requested.emit("resume_adventure" if paused else "pause_adventure",{"instance_id":inst.get("instance_id", "")}))

func _build_challenge_card(parent: Node) -> void:
	var Ritual = preload("res://scripts/services/ritual_service.gd")
	var c := Ritual.get_challenge_state(state)
	var streak := int(c.get("current_streak", 0))
	var max_s := int(c.get("max_streak", 0))
	var unlocked := bool(c.get("unlocked", false))
	var cl: Dictionary = c.get("today_checklist", {})
	var meta := Ritual.challenge_item_meta()

	var box := UI.card(parent)
	var top := UI.row(box)
	UI.label("БОЛЬШОЙ РИТМ МАЙИ · 30 ДНЕЙ ПОДРЯД", top, 16, UI.BRASS)
	var badge_text := "✦ ВЕЧНЫЙ ОГОНЬ ✦" if unlocked else ("🔥 День %d из 30" % streak)
	var badge := UI.label(badge_text, top, 16, Color(1.0, 0.82, 0.40) if unlocked else Color(1.0, 0.65, 0.30))
	badge.size_flags_horizontal = SIZE_SHRINK_END

	var info_text := "Утром пробежка, вечером растяжка, 4 подхода испанского. Если пропущен хотя бы 1 пункт за день — стрик сбрасывается. На 30-й день на станции навсегда появится памятная доска и вечный огонь!"
	if max_s > 0 and not unlocked:
		info_text += " (Рекорд: %d дней)" % max_s
	UI.label(info_text, box, 12, UI.MUTED)

	var items_row1 := UI.row(box)
	var items_row2 := UI.row(box)
	var count := 0
	var done_count := 0
	for key in Ritual.CHALLENGE_ITEMS:
		var item_info: Dictionary = meta.get(key, {})
		var done := bool(cl.get(key, false))
		if done: done_count += 1
		var target_row := items_row1 if count < 3 else items_row2
		count += 1
		var item_key: String = str(key)
		var text := "%s %s  %s" % [str(item_info.get("icon", "")), str(item_info.get("title", key)), "✓" if done else "○"]
		UI.button(text, target_row, func():
			command_requested.emit("toggle_challenge_item", {"item_key": item_key})
		, done)

	var status_row := UI.row(box)
	if done_count == 6:
		UI.label("🎉 Все 6 пунктов на сегодня закрыты! День засчитан в стрик!", status_row, 14, Color(0.55, 0.95, 0.72))
	else:
		UI.label("Сегодня выполнено: %d из 6 пунктов" % done_count, status_row, 13, UI.TEAL)

func _build_chronicle() -> void:
	var sc := UI.scroll(content)
	var box := UI.card(sc)
	UI.label("Летопись станции · Хроника изменений мира", box, 24, UI.BRASS)
	UI.label("Каждое реальное действие Майи навсегда меняет мир игры. Станция растёт новыми комнатами и артефактами. Здесь собрана вся история свершений.", box, 14, UI.MUTED)

	var entries: Array[Dictionary] = [
		{
			"title": "Пролог · Пробуждение станции (S00)",
			"action": "Разгадана шкатулка (Гора / Ветер / Звезда), станция названа «Станция Майи», установлена сова.",
			"impact": "Станция ожила: зажёгся тёплый свет, появилась вывеска над дверью, шкатулка бережно сохранена в шкафу истории.",
			"icon": "✦",
			"done": bool(state.get("puzzle_solved", false))
		},
		{
			"title": "Радио «Южный Маяк» (FG01)",
			"action": "20 конвертов историй, 100 испанских слов в личный словарь и авторская передача с Норой.",
			"impact": "Ярлык радио переходит в режим «в эфире». В приёмнике навсегда разблокирован личный альбом слов и выпуски эфира.",
			"icon": "📻",
			"done": str(UI.instance_for(state, "FG01").get("status", "")) == "COMPLETED"
		},
		{
			"title": "Автомат для станции (FG11)",
			"action": "Своя игра (на Python, JavaScript, Godot, Scratch или Lua): персонаж, 3 огонька, победа и перезапуск.",
			"impact": "Чертёж уходит со стола. В мастерской у перехода к обсерватории появляется настоящий 3D автомат с игрой и зажжёнными огоньками.",
			"icon": "🕹️",
			"done": str(UI.instance_for(state, "FG11").get("status", "")) == "COMPLETED"
		},
		{
			"title": "Два голоса воды (FG08)",
			"action": "Семейные прогулки к реке и водопаду, две реальные фотографии и сравнение звуков воды.",
			"impact": "На стене у входа в Галерею вешается латунный диптих с реальными фотографиями Майи. На карте атласа открыты Río Azul и Водопады.",
			"icon": "🌊",
			"done": str(UI.instance_for(state, "FG08").get("status", "")) == "COMPLETED"
		},
		{
			"title": "Большой ритм Майи · 30 дней подряд",
			"action": "30 дней подряд: утренняя пробежка, вечерняя растяжка и 4 подхода испанского без срывов.",
			"impact": "На стене станции зажигается именная латунная доска почёта и вечный огонь стойкости; на панели архива появляется жетон 30 DÍAS.",
			"icon": "🔥",
			"done": bool(state.get("phase_c", {}).get("rituals", {}).get("maya_30_streak", {}).get("unlocked", false))
		},
		{
			"title": "Галерея моих открытий и Выставки",
			"action": "Завершение первой главы и сборка авторской выставки.",
			"impact": "Открыта Галерея открытий (12 выставочных мест). На стене станции появились 3 рамы для сменяемых любимых работ.",
			"icon": "🏛️",
			"done": bool(state.get("puzzle_solved", false))
		},
		{
			"title": "Концепция масштабирования: Новые комнаты станции",
			"action": "По мере прохождения сотен новых миссий мир растёт новыми комнатами, а не захламляет одну.",
			"impact": "Открыты: Главная комната, Переход к обсерватории, Галерея. Будущие главы добавят новые двери: Лабораторию природы, Радио-рубку и Оранжерею.",
			"icon": "🚪",
			"done": true
		}
	]

	for entry in entries:
		var item_card := UI.card(sc)
		var top_row := UI.row(item_card)
		UI.label("%s  %s" % [entry.icon, entry.title], top_row, 18, UI.BRASS)
		var status_lbl := UI.label("ГОТОВО ✓" if entry.done else "В ПРОЦЕССЕ", top_row, 14, UI.TEAL if entry.done else UI.MUTED)
		status_lbl.size_flags_horizontal = SIZE_SHRINK_END
		UI.label("Что сделано: " + entry.action, item_card, 14)
		UI.label("След в мире: " + entry.impact, item_card, 14, Color(0.85, 0.78, 0.60))
