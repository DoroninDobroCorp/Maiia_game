class_name JournalUI
extends Control

## Иллюстрированный журнал станции (Пролог S00, Заметки долины, Достижения)

signal closed()

const ProgressionRulesScript = preload("res://scripts/domain/progression_rules.gd")

var audio_service: Node
var tab_container: TabContainer

func setup(game_state: Dictionary, audio_svc: Node) -> void:
	audio_service = audio_svc
	_build_ui(game_state)

func _build_ui(state: Dictionary) -> void:
	var bg := ColorRect.new()
	bg.color = Color(0.04, 0.05, 0.08, 0.85)
	bg.set_anchors_preset(PRESET_FULL_RECT)
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
	
	# 2. Вкладка «Атлас долины»
	var tab_atlas := _build_atlas_tab()
	tab_atlas.name = "Атлас долины"
	tab_container.add_child(tab_atlas)
	
	# 3. Вкладка «Достижения и архив»
	var tab_achieve := _build_achievements_tab(state)
	tab_achieve.name = "Достижения"
	tab_container.add_child(tab_achieve)

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
	q_story.text = "В старом архиве у подножия Серро Пилтрикитрон появилось место для новой хозяйки. Пустая деревянная табличка ждёт твоего имени, верстак готов к работе, а шкатулка с дисками хранит секрет запуска радиоканала."
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
	_add_task_item(tasks_box, "3. Разгадать шифр трёх дисков на старинной шкатулке", puzzle_done, "Порядок: Гора (1), Ветер (2), Звезда (3).")
	_add_task_item(tasks_box, "4. Разбудить станцию (зажечь настольную лампу и включить радио)", awaken_done, "Станция освещена теплом, радиоканал восстановлен!")
	
	if awaken_done:
		var complete_banner := Label.new()
		complete_banner.text = "🎉 Пролог успешно завершён! Твоя станция живёт, оформление сохранено, первое изменение мира выполнено."
		complete_banner.add_theme_font_size_override("font_size", 14)
		complete_banner.add_theme_color_override("font_color", Color(0.4, 0.95, 0.55))
		complete_banner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		vbox.add_child(complete_banner)
	
	return scroll

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

func _build_atlas_tab() -> Control:
	var scroll := ScrollContainer.new()
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 12)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)
	
	var notes: Array[Dictionary] = [
		{
			"title": "Вершина Серро Пилтрикитрон (Cerro Piltriquitrón)",
			"desc": "С языка мапуче переводится как «висящий на облаках». Могучий хребет защищает долину от свирепых западных тихоокеанских ветров."
		},
		{
			"title": "Река Рио Асуль (Río Azul)",
			"desc": "Ледниковая река с кристально чистой бирюзовой водой. Берёт начало высоко в заснеженных Андах и протекает через всю долину."
		},
		{
			"title": "Хвойные и нотофагусовые леса",
			"desc": "Древние патагонские кедры (кипарисы лавсоновские), коихве и ленга. В воздухе пахнет хвоей, свежей смолой и речным туманом."
		},
		{
			"title": "Неисследованный сектор карты",
			"desc": "Тропа за старым мостом скрыта в тумане. Чтобы открыть её, предстоит восстановить радиосигналы маяков в будущих экспедициях."
		}
	]
	
	for n in notes:
		var p := PanelContainer.new()
		var p_style := StyleBoxFlat.new()
		p_style.bg_color = Color(0.18, 0.16, 0.22, 0.8)
		p_style.set_corner_radius_all(6)
		p_style.set_content_margin_all(10)
		p.add_theme_stylebox_override("panel", p_style)
		vbox.add_child(p)
		
		var pv := VBoxContainer.new()
		p.add_child(pv)
		
		var l_title := Label.new()
		l_title.text = "✦ " + str(n["title"])
		l_title.add_theme_font_size_override("font_size", 14)
		l_title.add_theme_color_override("font_color", Color(1.0, 0.88, 0.6))
		pv.add_child(l_title)
		
		var l_desc := Label.new()
		l_desc.text = str(n["desc"])
		l_desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l_desc.add_theme_font_size_override("font_size", 12)
		l_desc.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))
		pv.add_child(l_desc)
	
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
