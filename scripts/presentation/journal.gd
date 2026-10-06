class_name JournalUI
extends Control

## Иллюстрированный журнал станции (Пролог S00, Заметки долины, Достижения)

signal closed()
signal quest_open_requested(quest: Dictionary, instance: Dictionary)
signal artifact_delete_requested(artifact_id: String)
signal ritual_day_requested()

const ProgressionRulesScript = preload("res://scripts/domain/progression_rules.gd")
const ContentRepositoryScript = preload("res://scripts/services/content_repository.gd")
const ContentLibraryServiceScript = preload("res://scripts/services/content_library_service.gd")
const QuestServiceScript = preload("res://scripts/services/quest_service.gd")
const ArtifactServiceScript = preload("res://scripts/services/artifact_service.gd")
const AuthorPatchServiceScript = preload("res://scripts/services/author_patch_service.gd")
const ProgressServiceScript = preload("res://scripts/services/progress_service.gd")
const RitualServiceScript = preload("res://scripts/services/ritual_service.gd")
const AtlasMapScript = preload("res://scripts/presentation/atlas_map.gd")
const MissionGuideScript = preload("res://scripts/presentation/mission_guide.gd")

var audio_service: Node
var tab_container: TabContainer

func setup(game_state: Dictionary, audio_svc: Node) -> void:
	audio_service = audio_svc
	_build_ui(game_state)

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			if audio_service != null and audio_service.has_method("play_sfx"):
				audio_service.play_sfx("paper_flip")
			closed.emit()

func _build_ui(state: Dictionary) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08, 0.85)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if audio_service != null and audio_service.has_method("play_sfx"):
				audio_service.play_sfx("paper_flip")
			closed.emit()
	)
	add_child(bg)
	
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)
	
	var book_panel := PanelContainer.new()
	book_panel.custom_minimum_size = Vector2(820, 560)
	var b_style := StyleBoxFlat.new()
	b_style.bg_color = Color(0.15, 0.13, 0.18, 0.98)
	b_style.border_color = Color(0.88, 0.72, 0.32, 0.9)
	b_style.set_border_width_all(2)
	b_style.set_corner_radius_all(10)
	b_style.set_content_margin_all(20)
	book_panel.add_theme_stylebox_override("panel", b_style)
	center.add_child(book_panel)
	
	var main_vbox := VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 14)
	book_panel.add_child(main_vbox)
	
	# Верхняя шапка журнала
	var header := HBoxContainer.new()
	main_vbox.add_child(header)
	
	var title_lbl := Label.new()
	title_lbl.text = "✦ ПОЛЕВОЙ ЖУРНАЛ СТАНЦИИ • ЭЛЬ-БОЛЬСОН ✦"
	title_lbl.add_theme_font_size_override("font_size", 18)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
	title_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_lbl)
	
	var btn_close := Button.new()
	btn_close.text = "Закрыть [Esc]"
	btn_close.pressed.connect(func():
		if audio_service != null and audio_service.has_method("play_sfx"):
			audio_service.play_sfx("paper_flip")
		closed.emit()
	)
	header.add_child(btn_close)
	
	# Табы разделов
	tab_container = TabContainer.new()
	tab_container.size_flags_vertical = Control.SIZE_EXPAND_FILL
	tab_container.tab_changed.connect(func(_idx: int):
		if audio_service != null and audio_service.has_method("play_sfx"):
			audio_service.play_sfx("paper_flip")
	)
	main_vbox.add_child(tab_container)
	
	# 1. Вкладка «Задачи (Пролог S00)»
	var tab_quest := _build_quest_tab(state)
	tab_quest.name = "Задачи (S00)"
	tab_container.add_child(tab_quest)
	
	# 2. Три приключения, выбранные на самый первый игровой отрезок.
	var tab_featured := _build_featured_goals_tab(state)
	tab_featured.name = "Активные приключения"
	tab_container.add_child(tab_featured)

	# 3. Опубликованные семейные экспедиции Phase B.
	var tab_phase_b := _build_phase_b_quests_tab(state)
	tab_phase_b.name = "Экспедиции"
	tab_container.add_child(tab_phase_b)

	# 4. Семейный маршрут из выбранных первых целей Майи.
	var tab_first_goals := _build_first_goals_tab(state)
	tab_first_goals.name = "Первые цели"
	tab_container.add_child(tab_first_goals)

	# 5. Восемь направлений развития.
	var tab_skills := _build_skills_tab(state)
	tab_skills.name = "Навыки"
	tab_container.add_child(tab_skills)

	# 6. Архив подтверждённой работы и локальных вложений.
	var tab_archive := _build_archive_tab(state)
	tab_archive.name = "Архив"
	tab_container.add_child(tab_archive)

	# 7. Вкладка «Атлас долины»
	var tab_atlas := _build_atlas_tab(state)
	tab_atlas.name = "Атлас долины"
	tab_container.add_child(tab_atlas)
	
	# 8. Достижения пролога.
	var tab_achieve := _build_achievements_tab(state)
	tab_achieve.name = "Достижения"
	tab_container.add_child(tab_achieve)

	var s00: Dictionary = state.get("s00_progress", {})
	if bool(s00.get("station_awakened", false)):
		tab_container.current_tab = 1

func _build_quest_tab(state: Dictionary) -> Control:
	var scroll := ScrollContainer.new()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	
	var s00: Dictionary = state.get("s00_progress", {})
	var sign_done: bool = bool(s00.get("sign_named", false))
	var prop_done: bool = bool(s00.get("prop_arranged", false))
	var puzzle_done: bool = bool(s00.get("puzzle_solved", false))
	var awaken_done: bool = bool(s00.get("station_awakened", false))
	
	var q_title := Label.new()
	q_title.text = "Сюжетный пролог: S00 — Это моя станция"
	q_title.add_theme_font_size_override("font_size", 16)
	q_title.add_theme_color_override("font_color", Color(1.0, 0.9, 0.65))
	vbox.add_child(q_title)
	
	var q_story := Label.new()
	q_story.text = "В старом архиве у подножия Серро Пилтрикитрон появилось место для новой хозяйки. Пустая деревянная табличка ждёт твоего имени, верстак готов к работе, а старинная шкатулка хранит первую маленькую тайну станции. На крышке осталась пожелтевшая записка — разгадай её шифр и попробуй разбудить станцию."
	q_story.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	q_story.add_theme_font_size_override("font_size", 13)
	q_story.add_theme_color_override("font_color", Color(0.85, 0.82, 0.76))
	vbox.add_child(q_story)
	
	# Чеклист шагов
	var tasks_box := VBoxContainer.new()
	tasks_box.add_theme_constant_override("separation", 8)
	vbox.add_child(tasks_box)
	
	_add_task_item(tasks_box, "1. Дать станции имя и выбрать символ на вывеске", sign_done, "Оформлено в Терминале автора.")
	_add_task_item(tasks_box, "2. Выставить на верстак памятный экспонат исследователя", prop_done, "Предмет выбран и стоит на подставке.")
	_add_task_item(tasks_box, "3. Разгадать первую тайну станции (шифр шкатулки)", puzzle_done, "Шкатулка открыта — лампа зажглась, радио ожило, станция просыпается!" if puzzle_done else "Внимательно прочти пожелтевшую записку на крышке шкатулки.")
	_add_task_item(tasks_box, "4. Пробудить станцию (зажечь настольную лампу и оживить радио)", awaken_done, "Станция озарена тёплым светом, радиоканал «Южный Маяк» ожил!")
	
	if awaken_done:
		var complete_banner := Label.new()
		complete_banner.text = "🎉 Пролог успешно завершён! Твоя станция живёт, оформление сохранено, первое изменение мира выполнено."
		complete_banner.add_theme_font_size_override("font_size", 14)
		complete_banner.add_theme_color_override("font_color", Color(0.4, 0.95, 0.55))
		complete_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(complete_banner)
	
	return scroll

func _build_phase_b_quests_tab(state: Dictionary) -> Control:
	var scroll := ScrollContainer.new()
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)

	var world_effects: Array = ProgressServiceScript.get_profile_world_effects(state, "player_01")
	if world_effects.has("observatory_view_01"):
		var finale := Label.new()
		finale.text = "✦ Глава завершена: обсерватория снова светится. Станция сохранила сделанную работу и теперь ждёт, какую следующую главу выберет её автор."
		finale.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		finale.add_theme_font_size_override("font_size", 13)
		finale.add_theme_color_override("font_color", Color(0.96, 0.82, 0.52))
		vbox.add_child(finale)

	var intro := Label.new()
	intro.text = "Экспедиции станции. Выбирай любое направление, знакомься с планом и отправляйся в путь."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 11)
	intro.add_theme_color_override("font_color", Color(0.70, 0.69, 0.66))
	vbox.add_child(intro)

	var quests := QuestServiceScript.list_player_quests(state)
	if quests.is_empty():
		var empty := Label.new()
		empty.text = "Здесь появятся дополнительные экспедиции. А прямо сейчас можно открыть приключения во вкладках «Активные приключения» и «Первые цели»!"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", Color(0.78, 0.74, 0.66))
		vbox.add_child(empty)
		return scroll

	for quest in quests:
		var qid := str(quest.get("quest_id", ""))
		var instance := _latest_instance_for_quest(state, qid)
		var card := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.18, 0.155, 0.19, 0.90)
		style.border_color = Color(0.50, 0.43, 0.28, 0.75)
		style.set_border_width_all(1)
		style.set_corner_radius_all(7)
		style.set_content_margin_all(11)
		card.add_theme_stylebox_override("panel", style)
		vbox.add_child(card)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
		var text_box := VBoxContainer.new()
		text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text_box)
		var title := Label.new()
		title.text = "%s • %s" % [qid, str(quest.get("title", ""))]
		title.add_theme_font_size_override("font_size", 14)
		title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.58))
		text_box.add_child(title)
		var summary := Label.new()
		summary.text = str(quest.get("summary", ""))
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary.add_theme_font_size_override("font_size", 11)
		text_box.add_child(summary)
		var status := Label.new()
		status.text = "Доступно" if instance.is_empty() else _instance_status_title(str(instance.get("status", "")))
		status.add_theme_font_size_override("font_size", 10)
		status.add_theme_color_override("font_color", Color(0.58, 0.86, 0.64) if instance.is_empty() or str(instance.get("status", "")) == "COMPLETED" else Color(0.84, 0.74, 0.50))
		text_box.add_child(status)
		var open_btn := Button.new()
		open_btn.text = "Открыть"
		var exact_quest: Dictionary = quest.duplicate(true)
		var exact_instance: Dictionary = instance.duplicate(true)
		open_btn.pressed.connect(func(): quest_open_requested.emit(exact_quest, exact_instance))
		row.add_child(open_btn)

	return scroll

func _build_featured_goals_tab(state: Dictionary) -> Control:
	var scroll := ScrollContainer.new()
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 12)
	scroll.add_child(vbox)

	var heading := Label.new()
	heading.text = "ТРИ ПЕРВЫХ ПРИКЛЮЧЕНИЯ"
	heading.add_theme_font_size_override("font_size", 16)
	heading.add_theme_color_override("font_color", Color(1.0, 0.86, 0.52))
	vbox.add_child(heading)
	var intro := Label.new()
	intro.text = "Три миссии можно проходить в любом порядке. У каждой есть свой предмет на столе станции. Подробный путь с шагами и подсказками — в журнале миссий (J)."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 11)
	intro.add_theme_color_override("font_color", Color(0.78, 0.76, 0.70))
	vbox.add_child(intro)

	for goal in ContentRepositoryScript.featured_goal_templates():
		var qid := str(goal.get("quest_id", ""))
		var published := _latest_published_quest(state, qid)
		var instance := _latest_instance_for_quest(state, qid)
		var card := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.18, 0.15, 0.20, 0.94)
		style.border_color = Color(0.76, 0.58, 0.26, 0.84)
		style.set_border_width_all(1)
		style.set_corner_radius_all(8)
		style.set_content_margin_all(12)
		card.add_theme_stylebox_override("panel", style)
		vbox.add_child(card)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
		var text_box := VBoxContainer.new()
		text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text_box)
		var reward: Dictionary = goal.get("reward_policy", {})
		var weights: Dictionary = reward.get("skill_weights_percent", {})
		var skill_id := str(weights.keys()[0]) if not weights.is_empty() else ""
		var title := Label.new()
		title.text = "%s  •  %s" % [ContentRepositoryScript.get_skill_title(skill_id), str(goal.get("title", ""))]
		title.add_theme_font_size_override("font_size", 14)
		title.add_theme_color_override("font_color", Color(1.0, 0.90, 0.62))
		text_box.add_child(title)
		var summary := Label.new()
		summary.text = str(goal.get("summary", ""))
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary.add_theme_font_size_override("font_size", 11)
		text_box.add_child(summary)
		var clarity: Dictionary = MissionGuideScript.mission(qid)
		if not clarity.is_empty():
			var world_note := Label.new()
			world_note.text = "На столе: %s\nПосле миссии: %s" % [str(clarity.object_hint), str(clarity.remains)]
			world_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			world_note.add_theme_font_size_override("font_size", 10)
			world_note.add_theme_color_override("font_color", Color(0.76, 0.82, 0.72))
			text_box.add_child(world_note)
		var steps: Array = goal.get("goal_steps", [])
		if not steps.is_empty():
			var steps_label := Label.new()
			var step_titles: Array[String] = []
			for step in steps:
				step_titles.append(str(step))
			steps_label.text = "Маршрут: " + "  →  ".join(step_titles)
			steps_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			steps_label.add_theme_font_size_override("font_size", 10)
			steps_label.add_theme_color_override("font_color", Color(0.70, 0.76, 0.82))
			text_box.add_child(steps_label)

		var status := Label.new()
		if instance.is_empty():
			status.text = "Можно выполнять"
			status.add_theme_color_override("font_color", Color(0.60, 0.88, 0.66))
		elif str(instance.get("status", "")) == "COMPLETED":
			status.text = "✓ Выполнено"
			status.add_theme_color_override("font_color", Color(0.45, 0.95, 0.55))
		else:
			status.text = _instance_status_title(str(instance.get("status", "")))
			status.add_theme_color_override("font_color", Color(0.86, 0.74, 0.50))
		text_box.add_child(status)

		var open_btn := Button.new()
		open_btn.text = "Открыть"
		var exact_quest: Dictionary = published.duplicate(true) if not published.is_empty() else goal.duplicate(true)
		var exact_instance: Dictionary = instance.duplicate(true)
		open_btn.pressed.connect(func(): quest_open_requested.emit(exact_quest, exact_instance))
		row.add_child(open_btn)

	var ritual := RitualServiceScript.get_state(state)
	var days: Array = ritual.get("days", [])
	var target_days := int(ritual.get("target_days", 5))
	var ritual_card := PanelContainer.new()
	var ritual_style := StyleBoxFlat.new()
	ritual_style.bg_color = Color(0.10, 0.16, 0.17, 0.94)
	ritual_style.border_color = Color(0.35, 0.66, 0.61, 0.76)
	ritual_style.set_border_width_all(1)
	ritual_style.set_corner_radius_all(8)
	ritual_style.set_content_margin_all(12)
	ritual_card.add_theme_stylebox_override("panel", ritual_style)
	vbox.add_child(ritual_card)
	var ritual_row := HBoxContainer.new()
	ritual_row.add_theme_constant_override("separation", 14)
	ritual_card.add_child(ritual_row)
	var ritual_text := VBoxContainer.new()
	ritual_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	ritual_row.add_child(ritual_text)
	var ritual_title := Label.new()
	ritual_title.text = "РИТУАЛ ДВИЖЕНИЯ  •  5 спокойных дней"
	ritual_title.add_theme_font_size_override("font_size", 13)
	ritual_title.add_theme_color_override("font_color", Color(0.72, 0.94, 0.82))
	ritual_text.add_child(ritual_title)
	var marks: Array[String] = []
	for i in range(target_days):
		marks.append("✦" if i < days.size() else "○")
	var mark_label := Label.new()
	mark_label.text = "  ".join(marks) + "    %d/%d" % [min(days.size(), target_days), target_days]
	mark_label.add_theme_font_size_override("font_size", 18)
	mark_label.add_theme_color_override("font_color", Color(0.88, 0.82, 0.56))
	ritual_text.add_child(mark_label)
	var ritual_hint := Label.new()
	ritual_hint.text = "5–10 минут лёгкой разминки. Дни не обязаны идти подряд: пропуск ничего не сбрасывает. На пятой отметке на станции навсегда загорается маленький огонь."
	ritual_hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ritual_hint.add_theme_font_size_override("font_size", 10)
	ritual_hint.add_theme_color_override("font_color", Color(0.68, 0.76, 0.72))
	ritual_text.add_child(ritual_hint)
	var ritual_btn := Button.new()
	var today := Time.get_date_string_from_system()
	var today_marked := days.has(today)
	var unlocked := bool(ritual.get("unlocked", false))
	ritual_btn.text = "Огонь открыт ✦" if unlocked else ("Сегодня сделано ✓" if today_marked else "Отметить сегодня")
	ritual_btn.disabled = today_marked or unlocked
	ritual_btn.pressed.connect(func(): ritual_day_requested.emit())
	ritual_row.add_child(ritual_btn)

	return scroll

func _build_first_goals_tab(state: Dictionary) -> Control:
	var scroll := ScrollContainer.new()
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)

	var intro := Label.new()
	intro.text = "Это первый выбранный маршрут Майи. Любую цель можно открыть, узнать что нужно сделать и отметить выполненной."
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_font_size_override("font_size", 11)
	intro.add_theme_color_override("font_color", Color(0.76, 0.74, 0.68))
	vbox.add_child(intro)

	for goal in ContentRepositoryScript.first_goal_templates():
		var qid := str(goal.get("quest_id", ""))
		var published := _latest_published_quest(state, qid)
		var instance := _latest_instance_for_quest(state, qid)
		var status_text := "Можно выполнять"
		var status_color := Color(0.58, 0.86, 0.64)
		if not instance.is_empty():
			if str(instance.get("status", "")) == "COMPLETED":
				status_text = "✓ Выполнено"
				status_color = Color(0.45, 0.95, 0.55)
			else:
				status_text = _instance_status_title(str(instance.get("status", "")))
				status_color = Color(0.84, 0.74, 0.50)

		var card := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.17, 0.15, 0.19, 0.92)
		style.border_color = Color(0.58, 0.48, 0.30, 0.72)
		style.set_border_width_all(1)
		style.set_corner_radius_all(7)
		style.set_content_margin_all(11)
		card.add_theme_stylebox_override("panel", style)
		vbox.add_child(card)

		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		card.add_child(row)
		var text_box := VBoxContainer.new()
		text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text_box)

		var title := Label.new()
		title.text = "%02d  •  %s" % [int(goal.get("goal_order", 0)), str(goal.get("title", ""))]
		title.add_theme_font_size_override("font_size", 14)
		title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.58))
		text_box.add_child(title)

		var reward: Dictionary = goal.get("reward_policy", {})
		var weights: Dictionary = reward.get("skill_weights_percent", {})
		var skill_id := str(weights.keys()[0]) if not weights.is_empty() else ""
		var skill := Label.new()
		skill.text = ContentRepositoryScript.get_skill_title(skill_id) if not skill_id.is_empty() else "Семейная цель"
		skill.add_theme_font_size_override("font_size", 10)
		skill.add_theme_color_override("font_color", Color(0.68, 0.72, 0.72))
		text_box.add_child(skill)

		var summary := Label.new()
		summary.text = str(goal.get("summary", ""))
		summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		summary.add_theme_font_size_override("font_size", 11)
		text_box.add_child(summary)

		var steps: Array = goal.get("goal_steps", [])
		if not steps.is_empty():
			var steps_label := Label.new()
			var step_titles: Array[String] = []
			for step in steps:
				step_titles.append(str(step))
			steps_label.text = "Маршрут: " + "  →  ".join(step_titles)
			steps_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			steps_label.add_theme_font_size_override("font_size", 10)
			steps_label.add_theme_color_override("font_color", Color(0.70, 0.76, 0.82))
			text_box.add_child(steps_label)

		var status := Label.new()
		status.text = status_text
		status.add_theme_font_size_override("font_size", 10)
		status.add_theme_color_override("font_color", status_color)
		text_box.add_child(status)

		var open_btn := Button.new()
		open_btn.text = "Открыть"
		var exact_quest: Dictionary = published.duplicate(true) if not published.is_empty() else goal.duplicate(true)
		var exact_instance: Dictionary = instance.duplicate(true)
		open_btn.pressed.connect(func(): quest_open_requested.emit(exact_quest, exact_instance))
		row.add_child(open_btn)

	return scroll

func _build_skills_tab(state: Dictionary) -> Control:
	var scroll := ScrollContainer.new()
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 9)
	scroll.add_child(vbox)
	var phase_b: Dictionary = state.get("phase_b", {})
	var profile_xp: Dictionary = (phase_b.get("skill_xp_by_profile", {}) as Dictionary).get("player_01", {})
	for skill_id in ContentRepositoryScript.SKILLS.keys():
		var data: Dictionary = ContentRepositoryScript.SKILLS[skill_id]
		var card := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.16, 0.145, 0.18, 0.88)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(10)
		card.add_theme_stylebox_override("panel", style)
		vbox.add_child(card)
		var box := VBoxContainer.new()
		card.add_child(box)
		var title := Label.new()
		title.text = "%s  %s — %d XP" % [str(data.get("icon", "✦")), str(data.get("title", skill_id)), int(profile_xp.get(str(skill_id), 0))]
		title.add_theme_font_size_override("font_size", 14)
		title.add_theme_color_override("font_color", Color(0.96, 0.86, 0.60))
		box.add_child(title)
		var sub := Label.new()
		sub.text = "Поднавыки: " + ", ".join(ContentRepositoryScript.get_subskills(str(skill_id)))
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		sub.add_theme_font_size_override("font_size", 10)
		sub.add_theme_color_override("font_color", Color(0.68, 0.68, 0.66))
		box.add_child(sub)
	return scroll

func _build_archive_tab(state: Dictionary) -> Control:
	var scroll := ScrollContainer.new()
	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 10)
	scroll.add_child(vbox)
	var archive_note := Label.new()
	archive_note.text = "✦ " + AuthorPatchServiceScript.get_dialogue(state, "archive_note")
	archive_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	archive_note.add_theme_color_override("font_color", Color(0.92, 0.82, 0.58))
	vbox.add_child(archive_note)

	var phase_b: Dictionary = state.get("phase_b", {})
	var artifacts: Dictionary = phase_b.get("artifacts", {})
	var activities: Dictionary = phase_b.get("activities", {})
	var has_content := false

	for artifact_id in artifacts.keys():
		var artifact: Dictionary = artifacts[artifact_id]
		if str(artifact.get("profile_id", "player_01")) != "player_01":
			continue
		has_content = true
		var card := PanelContainer.new()
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.18, 0.15, 0.17, 0.9)
		style.set_corner_radius_all(6)
		style.set_content_margin_all(10)
		card.add_theme_stylebox_override("panel", style)
		vbox.add_child(card)
		var row := HBoxContainer.new()
		card.add_child(row)
		var text_box := VBoxContainer.new()
		text_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(text_box)
		var title := Label.new()
		title.text = "Работа: " + str(artifact.get("title", "Без названия"))
		text_box.add_child(title)
		var media := Label.new()
		var available := not ArtifactServiceScript.media_path_for(state, str(artifact_id)).is_empty()
		media.text = "Локальное медиа доступно" if available else "Медиа удалено или недоступно; запись результата сохранена"
		media.add_theme_font_size_override("font_size", 10)
		media.add_theme_color_override("font_color", Color(0.58, 0.82, 0.64) if available else Color(0.66, 0.64, 0.60))
		text_box.add_child(media)
		if available:
			var delete_btn := Button.new()
			delete_btn.text = "Удалить медиа"
			var exact_id := str(artifact_id)
			delete_btn.pressed.connect(func(): artifact_delete_requested.emit(exact_id))
			row.add_child(delete_btn)

	for activity_value in activities.values():
		var activity: Dictionary = activity_value
		if str(activity.get("profile_id", "")) != "player_01" or str(activity.get("status", "")) != "CONFIRMED":
			continue
		if str(activity.get("kind", "")) == "milestone":
			continue
		has_content = true
		var qid := str(activity.get("quest_id", ""))
		var quest := ContentLibraryServiceScript.get_template(state, qid, int(activity.get("revision", -1)))
		var line := Label.new()
		line.text = "✓ %s — %s" % [qid, str(quest.get("title", "Подтверждённая работа"))]
		line.add_theme_color_override("font_color", Color(0.62, 0.88, 0.66))
		vbox.add_child(line)

	if not has_content:
		var empty := Label.new()
		empty.text = "Архив пока пуст. Подтверждённые реальные результаты будут появляться здесь."
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		empty.add_theme_color_override("font_color", Color(0.68, 0.66, 0.62))
		vbox.add_child(empty)
	return scroll

func _latest_instance_for_quest(state: Dictionary, quest_id: String) -> Dictionary:
	var instances: Dictionary = state.get("phase_b", {}).get("quest_instances", {})
	var best: Dictionary = {}
	var best_score := -1
	for instance_value in instances.values():
		var instance: Dictionary = instance_value
		if str(instance.get("profile_id", "")) != "player_01" or str(instance.get("quest_id", "")) != quest_id:
			continue
		var status := str(instance.get("status", ""))
		var live_score := 100 if ["ACTIVE", "SUBMITTED", "PAUSED"].has(status) else 0
		var score := live_score + int(instance.get("revision", 0))
		if score >= best_score:
			best_score = score
			best = instance.duplicate(true)
	return best

func _latest_published_quest(state: Dictionary, quest_id: String) -> Dictionary:
	var best: Dictionary = {}
	var best_revision := -1
	for quest in QuestServiceScript.list_player_quests(state):
		if str(quest.get("quest_id", "")) != quest_id:
			continue
		var revision := int(quest.get("revision", 0))
		if revision > best_revision:
			best_revision = revision
			best = quest.duplicate(true)
	return best

func _instance_status_title(status: String) -> String:
	return {
		"ACTIVE": "В работе",
		"PAUSED": "Отложено",
		"SUBMITTED": "На проверке",
		"COMPLETED": "Завершено"
	}.get(status, status)

func _add_task_item(parent: Control, task_title: String, is_done: bool, hint: String) -> void:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	parent.add_child(h)
	
	var status_lbl := Label.new()
	status_lbl.text = "✓" if is_done else "○"
	status_lbl.add_theme_font_size_override("font_size", 16)
	status_lbl.add_theme_color_override("font_color", Color(0.4, 0.9, 0.45) if is_done else Color(0.6, 0.6, 0.6))
	h.add_child(status_lbl)
	
	var v := VBoxContainer.new()
	h.add_child(v)
	
	var t_lbl := Label.new()
	t_lbl.text = task_title
	t_lbl.add_theme_font_size_override("font_size", 13)
	t_lbl.add_theme_color_override("font_color", Color(0.95, 0.92, 0.85) if is_done else Color(0.8, 0.78, 0.72))
	v.add_child(t_lbl)
	
	var h_lbl := Label.new()
	h_lbl.text = hint
	h_lbl.add_theme_font_size_override("font_size", 11)
	h_lbl.add_theme_color_override("font_color", Color(0.65, 0.62, 0.55))
	v.add_child(h_lbl)

func _build_atlas_tab(state: Dictionary) -> Control:
	var scroll := ScrollContainer.new()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	var station_name := str(state.get("station_name", "Лесная станция")).strip_edges()
	if station_name.is_empty():
		station_name = "Лесная станция"

	var intro := Label.new()
	intro.text = "Открыта только станция «%s». Остальные места видны сквозь туман войны и будут раскрываться постепенно." % station_name
	intro.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	intro.add_theme_color_override("font_color", Color(0.78, 0.77, 0.70))
	vbox.add_child(intro)

	var atlas: Control = AtlasMapScript.new()
	atlas.custom_minimum_size = Vector2(820, 390)
	atlas.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_child(atlas)
	atlas.setup(state)

	var detail := Label.new()
	detail.text = "◎ %s — единственная открытая точка. Нажми на метку в тумане, чтобы увидеть, что там появится позже." % station_name
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	detail.add_theme_font_size_override("font_size", 12)
	detail.add_theme_color_override("font_color", Color(0.88, 0.84, 0.73))
	vbox.add_child(detail)
	atlas.location_selected.connect(func(location: Dictionary):
		if bool(location.get("unlocked", false)):
			detail.text = "◎ %s — %s\n%s" % [str(location.get("title", "")), str(location.get("subtitle", "")), str(location.get("description", ""))]
		else:
			detail.text = "☁ %s — %s\nТуман войны. %s" % [str(location.get("title", "")), str(location.get("subtitle", "")), str(location.get("description", ""))]
	)
	
	return scroll

func _build_achievements_tab(state: Dictionary) -> Control:
	var scroll := ScrollContainer.new()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	
	var a_list: Array = [
		ProgressionRulesScript.ACHIEVEMENTS["station_keeper"],
		ProgressionRulesScript.ACHIEVEMENTS["master_curator"],
		ProgressionRulesScript.ACHIEVEMENTS["first_world_change"]
	]
	
	for a_data: Dictionary in a_list:
		var a_id: String = str(a_data.get("id", ""))
		var is_unlocked: bool = ProgressionRulesScript.has_achievement(state, a_id)
		
		var p := PanelContainer.new()
		var p_style := StyleBoxFlat.new()
		p_style.bg_color = Color(0.20, 0.17, 0.14, 0.9) if is_unlocked else Color(0.12, 0.11, 0.14, 0.6)
		p_style.border_color = Color(0.88, 0.72, 0.32, 0.8) if is_unlocked else Color(0.3, 0.3, 0.35, 0.5)
		p_style.set_border_width_all(1)
		p_style.set_corner_radius_all(6)
		p_style.set_content_margin_all(12)
		p.add_theme_stylebox_override("panel", p_style)
		vbox.add_child(p)
		
		var h := HBoxContainer.new()
		h.add_theme_constant_override("separation", 14)
		p.add_child(h)
		
		var icon_lbl := Label.new()
		icon_lbl.text = str(a_data.get("icon", "✦"))
		icon_lbl.add_theme_font_size_override("font_size", 24)
		h.add_child(icon_lbl)
		
		var text_vbox := VBoxContainer.new()
		text_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(text_vbox)
		
		var title_lbl := Label.new()
		title_lbl.text = str(a_data.get("title", "")) + (" [Получено]" if is_unlocked else " [В процессе]")
		title_lbl.add_theme_font_size_override("font_size", 14)
		title_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55) if is_unlocked else Color(0.65, 0.62, 0.55))
		text_vbox.add_child(title_lbl)
		
		var desc_lbl := Label.new()
		desc_lbl.text = str(a_data.get("desc", ""))
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		desc_lbl.add_theme_font_size_override("font_size", 12)
		desc_lbl.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75) if is_unlocked else Color(0.5, 0.48, 0.45))
		text_vbox.add_child(desc_lbl)
	
	return scroll
