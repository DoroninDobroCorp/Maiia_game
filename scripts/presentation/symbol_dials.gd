class_name SymbolDialsUI
extends Control

## Мини-игра «Шкатулка с тремя дисками» (Пролог S00)

signal puzzle_solved()
signal closed()
signal dial_changed(dial_index: int, new_value: int)

const QuestRulesScript = preload("res://scripts/domain/quest_rules.gd")

var current_dials: Array[int] = [1, 2, 1] # Начальное положение

var dial_labels: Array[Label] = []
var dial_sublabels: Array[Label] = []
var feedback_label: Label
var clue_box: PanelContainer
var clue_label: Label
var audio_service: Node

func setup(dials: Array, is_already_solved: bool, audio_svc: Node) -> void:
	audio_service = audio_svc
	current_dials.clear()
	for d in dials:
		current_dials.append(int(d))
	
	_build_ui(is_already_solved)
	_update_dial_displays()

func _unhandled_key_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			if audio_service != null and audio_service.has_method("play_sfx"):
				audio_service.play_sfx("paper_flip")
			closed.emit()

func _build_ui(is_already_solved: bool) -> void:
	# Фоновая полупрозрачная затемняющая подложка
	var bg := ColorRect.new()
	bg.color = Color(0.05, 0.06, 0.1, 0.78)
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and ev.pressed and ev.button_index == MOUSE_BUTTON_LEFT:
			if audio_service != null and audio_service.has_method("play_sfx"):
				audio_service.play_sfx("paper_flip")
			closed.emit()
	)
	add_child(bg)
	
	# Центральная карточка шкатулки
	var center := CenterContainer.new()
	center.set_anchors_preset(PRESET_FULL_RECT)
	add_child(center)
	
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(760, 520)
	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color(0.14, 0.12, 0.18, 0.96)
	p_style.border_color = Color(0.88, 0.72, 0.32, 0.85)
	p_style.set_border_width_all(2)
	p_style.set_corner_radius_all(10)
	p_style.set_content_margin_all(24)
	panel.add_theme_stylebox_override("panel", p_style)
	center.add_child(panel)
	
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	panel.add_child(vbox)
	
	# Заголовок
	var title_lbl := Label.new()
	title_lbl.text = "✦ ПЕРВАЯ ТАЙНА СТАНЦИИ • СТАРИННАЯ ШКАТУЛКА ✦"
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_lbl.add_theme_font_size_override("font_size", 20)
	title_lbl.add_theme_color_override("font_color", Color(1.0, 0.88, 0.55))
	vbox.add_child(title_lbl)
	
	var sub_lbl := Label.new()
	sub_lbl.text = "Внутри шкатулки дремлет старый механизм станции. Разгадай шифр трёх дисков —\nвозможно, именно он сможет разбудить лампу, радио и всю станцию."
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	sub_lbl.add_theme_font_size_override("font_size", 13)
	sub_lbl.add_theme_color_override("font_color", Color(0.88, 0.85, 0.78))
	vbox.add_child(sub_lbl)
	
	# Контейнер для 3 дисков
	var dials_hbox := HBoxContainer.new()
	dials_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	dials_hbox.add_theme_constant_override("separation", 24)
	vbox.add_child(dials_hbox)
	
	dial_labels.clear()
	dial_sublabels.clear()
	
	for i in range(3):
		var dial_col := _create_dial_column(i)
		dials_hbox.add_child(dial_col)
	
	# Текст обратной связи
	feedback_label = Label.new()
	feedback_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	feedback_label.add_theme_font_size_override("font_size", 15)
	feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	vbox.add_child(feedback_label)
	
	if is_already_solved:
		feedback_label.text = "✓ Первая тайна разгадана: шкатулка открыта, станция проснулась!"
		feedback_label.add_theme_color_override("font_color", Color(0.4, 0.95, 0.55))
	
	# Блок улики / записки на крышке (сворачиваемый)
	clue_box = PanelContainer.new()
	var clue_style := StyleBoxFlat.new()
	clue_style.bg_color = Color(0.12, 0.11, 0.14, 0.96)
	clue_style.border_color = Color(0.82, 0.68, 0.36, 0.75)
	clue_style.set_border_width_all(1)
	clue_style.set_corner_radius_all(8)
	clue_style.content_margin_left = 16
	clue_style.content_margin_right = 16
	clue_style.content_margin_top = 12
	clue_style.content_margin_bottom = 12
	clue_box.add_theme_stylebox_override("panel", clue_style)
	clue_box.visible = false
	vbox.add_child(clue_box)
	
	clue_label = Label.new()
	clue_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	clue_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	clue_label.add_theme_font_size_override("font_size", 13)
	clue_label.add_theme_color_override("font_color", Color(0.96, 0.91, 0.78))
	clue_box.add_child(clue_label)
	
	# Нижние кнопки действий
	var btn_hbox := HBoxContainer.new()
	btn_hbox.alignment = BoxContainer.ALIGNMENT_CENTER
	btn_hbox.add_theme_constant_override("separation", 16)
	vbox.add_child(btn_hbox)
	
	var btn_hint := Button.new()
	btn_hint.text = "📜 Записка на крышке"
	btn_hint.custom_minimum_size = Vector2(210, 38)
	btn_hint.pressed.connect(_on_hint_pressed)
	btn_hbox.add_child(btn_hint)
	
	var btn_check := Button.new()
	btn_check.text = "⚙ Проверить положение"
	btn_check.custom_minimum_size = Vector2(200, 38)
	btn_check.pressed.connect(_on_check_pressed)
	btn_hbox.add_child(btn_check)
	
	var btn_close := Button.new()
	btn_close.text = "Закрыть [Esc]"
	btn_close.custom_minimum_size = Vector2(130, 38)
	btn_close.pressed.connect(func(): closed.emit())
	btn_hbox.add_child(btn_close)

func _create_dial_column(dial_idx: int) -> Control:
	var col := VBoxContainer.new()
	col.custom_minimum_size = Vector2(180, 160)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_theme_constant_override("separation", 8)
	
	# Номер диска
	var num_lbl := Label.new()
	num_lbl.text = "Диск " + str(dial_idx + 1)
	num_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	num_lbl.add_theme_font_size_override("font_size", 13)
	num_lbl.add_theme_color_override("font_color", Color(0.75, 0.70, 0.60))
	col.add_child(num_lbl)
	
	# Кнопка «Вверх»
	var btn_up := Button.new()
	btn_up.text = "▲"
	btn_up.custom_minimum_size = Vector2(120, 30)
	btn_up.pressed.connect(func(): _rotate_dial(dial_idx, -1))
	col.add_child(btn_up)
	
	# Панель текущего символа
	var p := PanelContainer.new()
	p.custom_minimum_size = Vector2(160, 72)
	var p_style := StyleBoxFlat.new()
	p_style.bg_color = Color(0.20, 0.17, 0.12, 0.95)
	p_style.border_color = Color(0.88, 0.72, 0.32, 0.7)
	p_style.set_border_width_all(1)
	p_style.set_corner_radius_all(6)
	p.add_theme_stylebox_override("panel", p_style)
	
	var inner_vbox := VBoxContainer.new()
	inner_vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	p.add_child(inner_vbox)
	
	var main_lbl := Label.new()
	main_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	main_lbl.add_theme_font_size_override("font_size", 18)
	main_lbl.add_theme_color_override("font_color", Color(1.0, 0.92, 0.7))
	inner_vbox.add_child(main_lbl)
	dial_labels.append(main_lbl)
	
	var sub_lbl := Label.new()
	sub_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub_lbl.add_theme_font_size_override("font_size", 11)
	sub_lbl.add_theme_color_override("font_color", Color(0.75, 0.72, 0.65))
	inner_vbox.add_child(sub_lbl)
	dial_sublabels.append(sub_lbl)
	
	col.add_child(p)
	
	# Кнопка «Вниз»
	var btn_down := Button.new()
	btn_down.text = "▼"
	btn_down.custom_minimum_size = Vector2(120, 30)
	btn_down.pressed.connect(func(): _rotate_dial(dial_idx, 1))
	col.add_child(btn_down)
	
	return col

func _rotate_dial(dial_idx: int, dir: int) -> void:
	var count: int = QuestRulesScript.DIAL_DATA[dial_idx].size()
	current_dials[dial_idx] = (current_dials[dial_idx] + dir + count) % count
	
	if audio_service != null and audio_service.has_method("play_sfx"):
		audio_service.play_sfx("click_dial")
	
	_update_dial_displays()
	dial_changed.emit(dial_idx, current_dials[dial_idx])
	
	# Сбрасываем текст ошибки при новом вращении
	if feedback_label.text.begins_with("Диски щёлкнули"):
		feedback_label.text = ""

func _update_dial_displays() -> void:
	for i in range(3):
		var val: int = current_dials[i]
		var item: Dictionary = QuestRulesScript.DIAL_DATA[i][val]
		dial_labels[i].text = item.get("title", "")
		dial_sublabels[i].text = item.get("desc", "")

func _on_hint_pressed() -> void:
	if audio_service != null and audio_service.has_method("play_sfx"):
		audio_service.play_sfx("paper_flip")
	
	clue_box.visible = !clue_box.visible
	if clue_box.visible:
		clue_label.text = QuestRulesScript.get_clue_text()

func _on_check_pressed() -> void:
	var is_correct: bool = QuestRulesScript.check_solution(current_dials)
	if is_correct:
		feedback_label.text = "✨ Замок щёлкнул и мягко раскрылся! Где-то внутри отозвался старый механизм — станция просыпается!"
		feedback_label.add_theme_color_override("font_color", Color(0.4, 0.95, 0.55))
		if audio_service != null and audio_service.has_method("play_sfx"):
			audio_service.play_sfx("chime_solve")
		puzzle_solved.emit()
	else:
		feedback_label.text = "Диски щёлкнули, но замок не поддался. Вчитайся в записку на крышке."
		feedback_label.add_theme_color_override("font_color", Color(0.95, 0.75, 0.4))
		if audio_service != null and audio_service.has_method("play_sfx"):
			audio_service.play_sfx("wood_thump")
